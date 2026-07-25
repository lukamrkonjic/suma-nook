class_name SkillActions
extends Node
## Sequences fishing / woodcutting / attacking around the player state machine.
## One interaction starts a loop; auto-repeat continues it; movement or cancel
## ends it. Rewards resolve ON the visible impact frame, never before.

signal action_feedback(kind: String, data: Dictionary)   # renderer/audio hooks
signal storage_requested
signal landmark_prompt_requested(node: Node3D)

var core: GameCore
var player: PlayerController
var visual: PlayerVisual
var effects: EffectsManager

var _loop_id := 0    # bumping this cancels any in-flight sequence


func setup(game_core: GameCore, player_controller: PlayerController, player_visual: PlayerVisual, effects_manager: EffectsManager) -> void:
	core = game_core
	player = player_controller
	visual = player_visual
	effects = effects_manager
	player.state_changed.connect(_on_player_state_changed)


func _on_player_state_changed(new_state: PlayerController.State) -> void:
	if new_state == PlayerController.State.FREE or new_state == PlayerController.State.BUILDING:
		_loop_id += 1
		visual.apply_equipment(core.equipment)


func try_interact() -> void:
	if player.state != PlayerController.State.FREE:
		return
	var focus := player.focus()
	match focus.get("kind", ""):
		"anchor":
			var anchor: Defs.AnchorDefinition = focus["anchor"]
			if anchor.skill_id == "fishing":
				_start_fishing(focus["coord"])
			elif anchor.skill_id == "woodcutting":
				_start_chopping(focus["coord"])
		"storage":
			storage_requested.emit()
		"enemy":
			attack(focus["node"])
		"landmark_prompt":
			landmark_prompt_requested.emit(focus["node"])


# ------------------------------------------------------------------ fishing

func _start_fishing(coord: Vector2i) -> void:
	var my_loop := _prepare_action(coord, "rod")
	_fishing_cycle(my_loop, coord)


func _fishing_cycle(my_loop: int, coord: Vector2i) -> void:
	if my_loop != _loop_id or core.grid.cell(coord) == null:
		return
	player.set_state(PlayerController.State.FISHING_CAST)
	visual.play("fish_cast")
	var cast_point := _pond_point(coord)
	action_feedback.emit("fish_cast", {"point": cast_point})
	var speed := core.equipment.tool_stat("rod", "speed", 1.0)
	await _wait(0.45 / speed)
	if my_loop != _loop_id:
		return
	effects.show_bobber(cast_point)
	effects.ripple(cast_point)
	player.set_state(PlayerController.State.FISHING_WAIT)
	visual.play("fish_wait")
	var wait_seconds := core.rng.randf_range("fishing_wait", core.registries.tunef("fishing_wait_min", 1.2), core.registries.tunef("fishing_wait_max", 3.2)) / speed
	await _wait(wait_seconds)
	if my_loop != _loop_id:
		effects.hide_bobber()
		return
	# Bite!
	effects.bobber_dip()
	effects.ripple(cast_point)
	action_feedback.emit("fish_bite", {"point": cast_point})
	await _wait(0.35)
	if my_loop != _loop_id:
		effects.hide_bobber()
		return
	player.set_state(PlayerController.State.FISHING_CATCH)
	visual.play("fish_catch")
	effects.hide_bobber()
	var skill := core.registries.skill("fishing")
	# The catch arcs to the player; rewards resolve at the landing moment.
	await effects.arc_reward(cast_point, player.global_position + Vector3(0, 0.7, 0))
	if my_loop != _loop_id:
		return
	core.skills.record_action("fishing")
	core.skills.add_xp("fishing", skill.action_xp)
	var grants := core.rewards.roll_action_loot(skill, core.equipment.stat_total("yield_bonus"), core.equipment.stat_total("rare_bonus"))
	action_feedback.emit("fish_catch", {"grants": grants, "point": player.global_position})
	await _wait(core.registries.tunef("fishing_repeat_pause", 0.7))
	if my_loop != _loop_id:
		return
	_fishing_cycle(my_loop, coord)   # auto-repeat until moved/cancelled


func _pond_point(coord: Vector2i) -> Vector3:
	var state := core.grid.cell(coord)
	var offset := Vector3(0.14, 0.0, 0.14).rotated(Vector3.UP, state.rotation * PI * 0.5)
	return core.grid.cell_to_world(coord) + offset + Vector3(0, -0.22, 0)


# ------------------------------------------------------------------ woodcutting

func _start_chopping(coord: Vector2i) -> void:
	var my_loop := _prepare_action(coord, "axe")
	_chop_cycle(my_loop, coord)


func _chop_cycle(my_loop: int, coord: Vector2i) -> void:
	if my_loop != _loop_id:
		return
	var state := core.grid.cell(coord)
	var def := core.grid.tile_def(coord)
	if state == null or def == null or state.anchor_resting:
		player.set_state(PlayerController.State.FREE)
		return
	var anchor := core.registries.anchor(def.anchor_id)
	player.set_state(PlayerController.State.WOODCUTTING)
	visual.play("chop")
	action_feedback.emit("chop_windup", {})
	var speed := core.equipment.tool_stat("axe", "speed", 1.0)
	await _wait(0.28 / speed)   # the swing reaches the trunk exactly here
	if my_loop != _loop_id:
		return
	var impact_point := core.grid.cell_to_world(coord) + Vector3(0.45, 0.7, 0.45)
	effects.burst("fx_wood_chip", impact_point, 6)
	effects.shake_vegetation(coord)
	core.skills.record_action("woodcutting")
	core.skills.add_xp("woodcutting", core.registries.skill("woodcutting").action_xp)
	var grants := core.rewards.roll_action_loot(core.registries.skill("woodcutting"), core.equipment.stat_total("yield_bonus"), core.equipment.stat_total("rare_bonus"))
	action_feedback.emit("chop_impact", {"grants": grants, "point": impact_point})
	state.anchor_actions_done += 1
	if state.anchor_actions_done >= anchor.cycle_actions + state.anchor_upgrade:
		state.anchor_resting = true
		state.anchor_regen_left = anchor.regen_seconds * (1.0 - 0.1 * state.anchor_upgrade)
		action_feedback.emit("grove_rest", {"coord": coord})
		core.autosave_soon()
		await _wait(0.4)
		player.set_state(PlayerController.State.FREE)
		return
	await _wait(maxf(0.4, core.registries.skill("woodcutting").action_seconds / speed - 0.28))
	if my_loop != _loop_id:
		return
	_chop_cycle(my_loop, coord)


# ------------------------------------------------------------------ combat

func attack(enemy_node: Node3D) -> void:
	if player.state != PlayerController.State.FREE:
		return
	var my_loop := _loop_id + 1
	_loop_id = my_loop
	player.face_toward(enemy_node.global_position)
	player.set_state(PlayerController.State.ATTACKING)
	visual.apply_equipment(core.equipment, "weapon")
	visual.play("attack")
	action_feedback.emit("attack_swing", {})
	await _wait(0.14)
	if is_instance_valid(enemy_node) and player.global_position.distance_to(enemy_node.global_position) < 2.0:
		if enemy_node.has_method("take_player_hit"):
			enemy_node.take_player_hit()
			effects.burst("fx_leaf", enemy_node.global_position + Vector3(0, 0.5, 0), 5)
	await _wait(0.22)
	if my_loop == _loop_id and player.state == PlayerController.State.ATTACKING:
		player.set_state(PlayerController.State.FREE)


# ------------------------------------------------------------------ helpers

func _prepare_action(coord: Vector2i, tool_type: String) -> int:
	_loop_id += 1
	player.face_toward(core.grid.cell_to_world(coord))
	visual.apply_equipment(core.equipment, tool_type)
	action_feedback.emit("tool_equip", {})
	return _loop_id


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func cancel_all() -> void:
	_loop_id += 1
	effects.hide_bobber()
