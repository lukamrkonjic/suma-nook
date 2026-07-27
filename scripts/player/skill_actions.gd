class_name SkillActions
extends Node
## Sequences fishing / woodcutting / attacking around the player state machine.
## One interaction starts a loop; auto-repeat continues it; movement or cancel
## ends it. Rewards resolve ON the visible impact frame, never before.

signal action_feedback(kind: String, data: Dictionary)   # renderer/audio hooks
signal storage_requested
signal landmark_prompt_requested(node: Node3D)
signal delivery_package_requested

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
	interact_with(player.focus())


## Direct-target companion to proximity focus, used when a click command
## reaches the object the player actually selected.
func interact_with(focus: Dictionary) -> void:
	if player.state != PlayerController.State.FREE:
		return
	match focus.get("kind", ""):
		"anchor":
			var coord: Vector2i = focus.get("coord", Vector2i(9999, 9999))
			var anchor: Defs.AnchorDefinition = focus["anchor"]
			var instance_id := int(focus.get("instance_id", 0))
			if instance_id > 0:
				var found := core.grid.find_structure(instance_id)
				if found.is_empty():
					return
				var structure: WorldGrid.StructureState = found["structure"]
				if structure.anchor_resting:
					return
				if anchor.skill_id == "woodcutting":
					_start_chopping(instance_id)
			elif anchor.skill_id == "fishing":
				var state := core.grid.cell(coord)
				if state == null or state.anchor_resting:
					return
				_start_fishing(coord)
		"storage":
			storage_requested.emit()
		"delivery_package":
			delivery_package_requested.emit()
		"enemy":
			if not core.registries.feature("combat_enabled", false):
				return
			var enemy_node := focus.get("node") as Node3D
			if is_instance_valid(enemy_node):
				attack(enemy_node)
		"landmark_prompt":
			var prompt_node := focus.get("node") as Node3D
			if is_instance_valid(prompt_node):
				landmark_prompt_requested.emit(prompt_node)


# ------------------------------------------------------------------ fishing

func _start_fishing(coord: Vector2i) -> void:
	var my_loop := _prepare_action(coord, "rod")
	_fishing_cycle(my_loop, coord)


func _fishing_cycle(my_loop: int, coord: Vector2i) -> void:
	if my_loop != _loop_id or core.grid.cell(coord) == null:
		return
	player.set_state(PlayerController.State.FISHING_CAST)
	var cast_point := _pond_point(coord)
	action_feedback.emit("fish_cast", {"point": cast_point})
	var speed := core.equipment.tool_stat("rod", "speed", 1.0)
	var cast_seconds := (
		visual.authored_action_duration("fish_cast", 0.45) / speed
	)
	visual.play("fish_cast", cast_seconds)
	await _wait(cast_seconds)
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
	# The catch is briefly visible, admired, and released automatically.
	await effects.catch_and_release(cast_point, player.global_position + Vector3(0, 0.85, 0))
	if my_loop != _loop_id:
		return
	var result := core.rewards.resolve_hobby_action(skill)
	core.skills.record_action("fishing")
	core.skills.add_xp("fishing", result.xp_awarded)
	action_feedback.emit("fish_catch", {"result": result.to_dict(), "point": player.global_position})
	await _wait(core.registries.tunef("fishing_repeat_pause", 0.7))
	if my_loop != _loop_id:
		return
	_fishing_cycle(my_loop, coord)   # auto-repeat until moved/cancelled


func _pond_point(coord: Vector2i) -> Vector3:
	var state := core.grid.cell(coord)
	var offset := Vector3(0.14, 0.0, 0.14).rotated(Vector3.UP, state.rotation * PI * 0.5)
	return core.grid.cell_to_world(coord) + offset + Vector3(0, -0.22, 0)


# ------------------------------------------------------------------ woodcutting

func _start_chopping(instance_id: int) -> void:
	var point := _structure_world_position(instance_id)
	var my_loop := _prepare_action_at(point, "axe")
	_chop_cycle(my_loop, instance_id)


func _chop_cycle(my_loop: int, instance_id: int) -> void:
	if my_loop != _loop_id:
		return
	var found := core.grid.find_structure(instance_id)
	if found.is_empty():
		player.set_state(PlayerController.State.FREE)
		return
	var structure: WorldGrid.StructureState = found["structure"]
	var definition := core.registries.structure(structure.structure_id)
	if definition == null or definition.anchor_id == "" or structure.anchor_resting:
		player.set_state(PlayerController.State.FREE)
		return
	var anchor := core.registries.anchor(definition.anchor_id)
	if anchor == null:
		player.set_state(PlayerController.State.FREE)
		return
	player.set_state(PlayerController.State.WOODCUTTING)
	action_feedback.emit("chop_windup", {})
	var speed := core.equipment.tool_stat("axe", "speed", 1.0)
	var cycle_seconds := (
		core.registries.skill("woodcutting").action_seconds / speed
	)
	var impact_seconds := cycle_seconds * visual.authored_action_impact_ratio(
		"chop", 0.47
	)
	visual.play("chop", cycle_seconds)
	await _wait(impact_seconds)
	if my_loop != _loop_id:
		return
	found = core.grid.find_structure(instance_id)
	if found.is_empty():
		player.set_state(PlayerController.State.FREE)
		return
	structure = found["structure"]
	var impact_point := _structure_world_position(instance_id) + Vector3(0, 0.7, 0)
	effects.burst("fx_wood_chip", impact_point, 6)
	effects.shake_structure(instance_id)
	var result := core.rewards.resolve_hobby_action(core.registries.skill("woodcutting"))
	core.skills.record_action("woodcutting")
	core.skills.add_xp("woodcutting", result.xp_awarded)
	action_feedback.emit("chop_impact", {"result": result.to_dict(), "point": impact_point})
	structure.anchor_actions_done += 1
	if structure.anchor_actions_done >= anchor.cycle_actions + structure.anchor_upgrade:
		structure.anchor_resting = true
		structure.anchor_regen_left = anchor.regen_seconds * (
			1.0 - 0.1 * structure.anchor_upgrade
		)
		action_feedback.emit("grove_rest", {"instance_id": instance_id})
		core.autosave_soon()
		await _wait(maxf(0.12, cycle_seconds - impact_seconds))
		player.set_state(PlayerController.State.FREE)
		return
	await _wait(maxf(0.12, cycle_seconds - impact_seconds))
	if my_loop != _loop_id:
		return
	_chop_cycle(my_loop, instance_id)


# ------------------------------------------------------------------ combat

func attack(enemy_node: Node3D) -> void:
	if not core.registries.feature("combat_enabled", false) or player.state != PlayerController.State.FREE:
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
	return _prepare_action_at(core.grid.cell_to_world(coord), tool_type)


func _prepare_action_at(point: Vector3, tool_type: String) -> int:
	_loop_id += 1
	player.face_toward(point)
	visual.apply_equipment(core.equipment, tool_type)
	action_feedback.emit("tool_equip", {})
	return _loop_id


func _structure_world_position(instance_id: int) -> Vector3:
	var found := core.grid.find_structure(instance_id)
	if found.is_empty():
		return player.global_position
	return (
		core.grid.cell_to_world(found["coord"], int(found["elevation"]))
		+ core.grid.structure_local_transform(instance_id).origin
	)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func cancel_all() -> void:
	_loop_id += 1
	effects.hide_bobber()
