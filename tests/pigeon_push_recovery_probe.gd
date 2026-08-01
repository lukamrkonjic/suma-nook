extends Node
## Focused acceptance probe for player collision, edge shoves, and the
## pigeon's self-rescue flight. This avoids booting the full presentation UI.

var _failures := 0


func _ready() -> void:
	var core := GameCore.new()
	core.setup("res://data", 7319)
	var profile := PlayerProfile.new()
	profile.display_name = "Pigeon Pusher"
	core.new_game(profile)

	var player := PlayerController.new()
	var player_shape := CollisionShape3D.new()
	var player_capsule := CapsuleShape3D.new()
	player_capsule.radius = 0.3
	player_capsule.height = 1.1
	player_shape.shape = player_capsule
	player_shape.position.y = 0.55
	player.add_child(player_shape)
	var player_visual := PlayerVisual.new()
	player.add_child(player_visual)
	var camera_rig := CameraRig.new()
	add_child(camera_rig)
	camera_rig.set_process(false)
	add_child(player)
	player.setup(core, camera_rig, player_visual)
	player.set_physics_process(false)
	_check(
		(player.collision_mask & PlayerController.PUSHABLE_NPC_LAYER) != 0,
		"player collision mask includes pushable NPCs",
	)
	_check(
		(player.collision_mask & PlayerController.EDGE_WALL_MASK) == 0,
		"NPC collision does not accidentally enable the island edge wall",
	)

	var mascot := (
		load("res://characters/mascots/pigeon_mascot.tscn") as PackedScene
	).instantiate() as CharacterBody3D
	add_child(mascot)
	var controller := mascot.get_node(
		"MascotController"
	) as PigeonMascotController
	controller.setup(player, core.grid)
	controller.spawn_near_player()
	await get_tree().process_frame
	_check(mascot.is_in_group("pushable_npcs"), "pigeon exposes the pushable NPC contract")
	_check(
		mascot.collision_layer == PlayerController.PUSHABLE_NPC_LAYER,
		"grounded pigeon has physical player collision",
	)
	await _check_real_player_contact(player, mascot, controller)

	var edge := _find_clear_edge(core.grid)
	_check(bool(edge.get("found", false)), "starter world has a clear edge for the shove test")
	if not bool(edge.get("found", false)):
		_finish()
		return
	var edge_cell: Vector2i = edge["cell"]
	var outward: Vector2i = edge["outward"]
	player.global_position = (
		core.grid.cell_to_world(edge_cell)
		- Vector3(outward.x, 0.0, outward.y) * 1.4
	)
	mascot.global_position = core.grid.cell_to_world(edge_cell) + Vector3.UP * 0.025
	controller.set("_current_cell", edge_cell)
	controller.set("_last_safe_cell", edge_cell)
	controller.set("_has_last_safe_cell", true)
	controller.call("_begin_idle", 10.0)
	controller.set_physics_process(true)
	var start := mascot.global_position
	var state_history: PackedStringArray = []
	controller.movement_state_changed.connect(func(_state: int) -> void:
		state_history.append(controller.movement_state_name())
	)
	var push_direction := Vector3(outward.x, 0.0, outward.y)
	controller.apply_player_push(push_direction * 4.0)
	_check(
		controller.movement_state_name() == "pushed",
		"player contact puts the pigeon into a physical shove",
	)

	var minimum_y := mascot.global_position.y
	var maximum_horizontal_displacement := 0.0
	var collision_was_disabled_airborne := false
	var deadline := Time.get_ticks_msec() + 4500
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		minimum_y = minf(minimum_y, mascot.global_position.y)
		maximum_horizontal_displacement = maxf(
			maximum_horizontal_displacement,
			_horizontal_distance(start, mascot.global_position),
		)
		if (
			controller.movement_state_name() in ["falling", "recovering"]
			and mascot.collision_layer == 0
		):
			collision_was_disabled_airborne = true
		if (
			"recovering" in state_history
			and controller.movement_state_name() == "idle"
		):
			break

	_check(
		maximum_horizontal_displacement > 0.05,
		"pigeon moves in response to the shove",
	)
	_check("falling" in state_history, "pigeon visibly drops after leaving the tile")
	_check("recovering" in state_history, "pigeon switches from falling to return flight")
	_check(
		minimum_y <= start.y - controller.recovery_drop_distance + 0.06,
		"return flight begins only after a readable edge drop",
	)
	_check(collision_was_disabled_airborne, "airborne recovery cannot block the player")
	_check(controller.movement_state_name() == "idle", "pigeon lands and resumes idle behavior")
	_check(
		core.grid.is_walkable(core.grid.world_to_cell(mascot.global_position)),
		"pigeon returns to supported ground",
	)
	_check(
		mascot.collision_layer == PlayerController.PUSHABLE_NPC_LAYER,
		"player collision is restored after landing",
	)
	_finish()


func _check_real_player_contact(
	player: PlayerController,
	mascot: CharacterBody3D,
	controller: PigeonMascotController,
) -> void:
	controller.set_physics_process(false)
	controller.call("_begin_idle", 10.0)
	mascot.global_position = Vector3.ZERO
	player.global_position = Vector3(-0.85, 0.0, 0.0)
	await get_tree().physics_frame
	var contacted := false
	for _step in 24:
		var intended_velocity := Vector3.RIGHT * 3.0
		player.velocity = intended_velocity
		player.move_and_slide()
		player.call("_push_collided_npcs", intended_velocity)
		if controller.movement_state_name() == "pushed":
			contacted = true
			break
		await get_tree().physics_frame
	_check(contacted, "a real CharacterBody collision dispatches a pigeon shove")
	controller.call("_begin_idle", 10.0)


func _find_clear_edge(grid: WorldGrid) -> Dictionary:
	for cell: Vector2i in grid.cells:
		if not grid.is_walkable(cell):
			continue
		var state := grid.cell(cell)
		if state == null or not state.structures.is_empty():
			continue
		for outward: Vector2i in WorldGrid.NEIGHBORS:
			if not grid.is_walkable(cell + outward):
				return {"found": true, "cell": cell, "outward": outward}
	return {"found": false}


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS ", label)
	else:
		_failures += 1
		push_error("PIGEON_PUSH_RECOVERY: " + label)


func _finish() -> void:
	print("PIGEON_PUSH_RECOVERY failures=", _failures)
	var exit_code := 0 if _failures == 0 else 1
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	get_tree().quit(exit_code)
