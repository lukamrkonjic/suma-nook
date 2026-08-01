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
var _void_cast_point := Vector3.ZERO
var _void_session_visuals := false


func setup(game_core: GameCore, player_controller: PlayerController, player_visual: PlayerVisual, effects_manager: EffectsManager) -> void:
	core = game_core
	player = player_controller
	visual = player_visual
	effects = effects_manager
	player.state_changed.connect(_on_player_state_changed)
	var session: FishingSessionService = core.fishing.session
	session.cast_started.connect(_on_fishing_cast_started)
	session.waiting_started.connect(_on_fishing_waiting_started)
	session.bite_started.connect(_on_fishing_bite_started)
	session.manual_reel_started.connect(_on_fishing_reel_started)
	session.auto_reel_started.connect(_on_fishing_reel_started)
	session.reveal_started.connect(_on_fishing_reveal_started)
	session.haul_committed.connect(_on_fishing_haul_committed)
	session.basket_full_paused.connect(_on_fishing_basket_full)
	session.fishing_stopped.connect(_on_fishing_stopped)


func _on_player_state_changed(new_state: PlayerController.State) -> void:
	if new_state == PlayerController.State.FREE or new_state == PlayerController.State.BUILDING:
		_loop_id += 1
		visual.apply_equipment(core.equipment)
		# Walking away (or opening build mode) ends the fishing session; the
		# session releases any reserved Spirit itself.
		if _void_session_visuals and core.fishing.session.is_active():
			core.fishing.session.cancel("player_moved")


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
		"void_fishing":
			_start_void_fishing(
				focus.get("cast_point", focus.get("point", player.global_position))
			)
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
	_pond_fishing_cycle(my_loop, coord, _pond_point(coord))


## Edge fishing hands control to the fishing session state machine; this node
## only stages the seated presentation and mirrors session events into
## animation, effects, and player states.
func _start_void_fishing(cast_point: Vector3) -> void:
	if core.fishing.session.is_active():
		return
	_loop_id += 1
	var my_loop := _loop_id
	# The keeper moves in free 360° directions, but the world has four grid
	# directions: the cast snaps their facing to the chosen edge's exact
	# cardinal, so body, rod, and line all point straight over that edge.
	var cell := player.current_cell()
	var origin := core.grid.cell_to_world(
		cell,
		core.grid.top_elevation(cell)
	)
	var direction := cast_point - origin
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		direction = direction.normalized()
		player.rotation.y = atan2(-direction.x, -direction.z)
	else:
		player.face_toward(cast_point)
	player.set_state(PlayerController.State.FISHING_CAST)
	_void_cast_point = cast_point
	var staged := await effects.prepare_void_fishing(cast_point)
	if not staged or my_loop != _loop_id:
		effects.cancel_void_fishing()
		if player.state != PlayerController.State.FREE:
			player.set_state(PlayerController.State.FREE)
		return
	action_feedback.emit("tool_equip", {})
	_void_session_visuals = true
	core.fishing.session.begin_session(cell)


## The fishing input pressed while the line is out. At the bite it retrieves
## the catch faster; at any other moment it does nothing.
func fishing_input() -> void:
	core.fishing.session.request_manual_reel()


func _on_fishing_cast_started(_context: FishingRollContext, _duration: float) -> void:
	if not _void_session_visuals:
		return
	player.set_state(PlayerController.State.FISHING_CAST)
	# The seated keeper needs only a short settle beat before the line drops.
	visual.play("fish_wait")
	action_feedback.emit("fish_cast", {"point": _void_cast_point, "void": true})


func _on_fishing_waiting_started(_duration: float) -> void:
	if not _void_session_visuals:
		return
	# The line drops once the settle beat ends: the rift opens under the LIVE
	# rod tip, which has finished blending into the seated pose by now.
	effects.show_void_cast(_void_cast_point)
	player.set_state(PlayerController.State.FISHING_WAIT)
	visual.play("fish_wait")


func _on_fishing_bite_started(_window: float) -> void:
	if not _void_session_visuals:
		return
	effects.void_bite()
	action_feedback.emit("fish_bite", {"point": _void_cast_point})


func _on_fishing_reel_started(_duration: float) -> void:
	if not _void_session_visuals:
		return
	player.set_state(PlayerController.State.FISHING_CATCH)
	visual.play("fish_catch")


func _on_fishing_reveal_started(haul: FishingHaul, _duration: float) -> void:
	if not _void_session_visuals:
		return
	var primary := haul.primary_entry()
	if primary != null:
		# Fire-and-forget: the session's reveal timer paces the sequence.
		effects.retrieve_void_reward({
			"kind": primary.content_kind(),
			"id": primary.building_id,
		})


func _on_fishing_haul_committed(haul: FishingHaul) -> void:
	if not _void_session_visuals:
		return
	effects.consume_carried_void_reward()
	action_feedback.emit("fish_catch", {
		"haul": haul.to_dict(),
		"void": true,
		"point": player.global_position,
	})


func _on_fishing_basket_full() -> void:
	if not _void_session_visuals:
		return
	action_feedback.emit("basket_full", {})


func _on_fishing_stopped(_reason: String) -> void:
	if not _void_session_visuals:
		return
	_void_session_visuals = false
	effects.cancel_void_fishing()
	if player.state in [
		PlayerController.State.FISHING_CAST,
		PlayerController.State.FISHING_WAIT,
		PlayerController.State.FISHING_CATCH,
	]:
		player.set_state(PlayerController.State.FREE)


## Pond fishing is a cozy ambient moment: the catch is admired and released.
## Fish are ambient water animals — never rewards, records, or resources.
func _pond_fishing_cycle(
	my_loop: int,
	coord: Vector2i,
	cast_point: Vector3
) -> void:
	if my_loop != _loop_id or core.grid.cell(coord) == null:
		return
	player.set_state(PlayerController.State.FISHING_CAST)
	action_feedback.emit("fish_cast", {"point": cast_point, "void": false})
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
	var wait_seconds := core.rng.randf_range(
		"fishing_wait",
		core.registries.tunef("fishing_wait_min", 1.2),
		core.registries.tunef("fishing_wait_max", 3.2)
	) / speed
	await _wait(wait_seconds)
	if my_loop != _loop_id:
		effects.hide_bobber()
		return
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
	await effects.catch_and_release(
		cast_point,
		player.global_position + Vector3(0, 0.85, 0)
	)
	core.progression.on_activity_action("fishing")
	if my_loop != _loop_id:
		return
	action_feedback.emit("fish_catch", {
		"void": false,
		"point": player.global_position,
	})
	player.set_state(PlayerController.State.FREE)


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
	core.progression.on_activity_action("woodcutting")
	action_feedback.emit("chop_impact", {
		"result": result.to_dict(),
		"point": impact_point,
	})
	structure.anchor_actions_done += 1
	if structure.anchor_actions_done >= anchor.cycle_actions + structure.anchor_upgrade:
		structure.anchor_resting = true
		structure.anchor_regen_left = anchor.regen_seconds * (
			1.0 - 0.1 * structure.anchor_upgrade
		)
		core.track_resting_structure(instance_id)
		# The finished cycle publishes a narrow completion event; the Spirit
		# adapter — not this node — decides it is worth a Grove Spirit.
		core.progression.on_activity_cycle_completed("woodcutting")
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
	if core != null and core.fishing.session.is_active():
		core.fishing.session.cancel("cancel_all")
	effects.hide_bobber()
	effects.cancel_void_fishing()
