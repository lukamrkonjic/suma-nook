class_name PlayerController
extends CharacterBody3D
## Continuous free movement — the hard requirement. The physics transform is a
## float Vector3 driven by move_and_slide every tick; grid coordinates are only
## ever derived FROM the position for placement queries, never imposed on it.
## Also owns the player action state machine.

signal state_changed(new_state: State)
signal interaction_focus_changed(focus: Dictionary)   # {} when none
signal click_interaction_reached(interaction: Dictionary)

enum State { FREE, FISHING_CAST, FISHING_WAIT, FISHING_CATCH, WOODCUTTING, ATTACKING, DODGING, HIT, BUILDING, DISABLED }

var core: GameCore
var camera_rig: CameraRig
var visual: PlayerVisual

var state: State = State.FREE
var move_locked := false
var _dodge_timer := 0.0
var _dodge_dir := Vector3.ZERO
var _invuln_timer := 0.0
var _focus: Dictionary = {}
var _focus_scan_accum := 0.0
var _click_path: Array[Vector3] = []
var _click_interaction: Dictionary = {}
var _click_stop_radius := 0.12


func setup(game_core: GameCore, rig: CameraRig, player_visual: PlayerVisual) -> void:
	core = game_core
	camera_rig = rig
	visual = player_visual
	position = core.profile.position
	rotation.y = core.profile.facing
	floor_snap_length = 0.4


func _physics_process(delta: float) -> void:
	if core == null:
		return
	_invuln_timer = maxf(0.0, _invuln_timer - delta)
	match state:
		State.DODGING:
			_dodge_timer -= delta
			velocity = _dodge_dir * core.registries.tunef("dodge_speed", 8.5)
			if _dodge_timer <= 0.0:
				set_state(State.FREE)
		State.DISABLED:
			velocity = Vector3.ZERO
		_:
			_free_move(delta)
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = maxf(velocity.y, 0.0)
	move_and_slide()
	core.profile.position = position
	core.profile.facing = rotation.y
	_focus_scan_accum += delta
	if _focus_scan_accum >= 0.15:
		_focus_scan_accum = 0.0
		_update_focus()


func _free_move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Any deliberate movement cancels an in-progress skill loop gracefully.
	if input.length_squared() > 0.04 and state in [State.FISHING_CAST, State.FISHING_WAIT, State.FISHING_CATCH, State.WOODCUTTING]:
		set_state(State.FREE)
	if input.length_squared() > 0.04:
		cancel_click_command()
	var can_run := state == State.FREE or state == State.BUILDING
	var wish := Vector3.ZERO
	if can_run and not move_locked:
		if input.length_squared() > 0.04:
			var basis := camera_rig.horizontal_basis()
			wish = (basis.x * input.x + basis.z * input.y)
			wish.y = 0.0
			if wish.length_squared() > 1.0:
				wish = wish.normalized()
		elif state == State.FREE and not _click_path.is_empty():
			wish = _click_wish()
	var speed := core.registries.tunef("walk_speed", 4.0)
	var accel := core.registries.tunef("walk_accel", 26.0) if wish != Vector3.ZERO else core.registries.tunef("walk_decel", 32.0)
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	horizontal = horizontal.move_toward(wish * speed, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if wish.length_squared() > 0.001:
		var target_yaw := atan2(-wish.x, -wish.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, core.registries.tunef("turn_speed", 12.0) * delta)
	visual.set_walk(horizontal.length() / speed, delta)


func _unhandled_input(event: InputEvent) -> void:
	if state == State.DISABLED:
		return
	if (
		core.registries.feature("combat_enabled", false)
		and event.is_action_pressed("dodge")
		and state in [State.FREE, State.ATTACKING]
	):
		_start_dodge()


func _start_dodge() -> void:
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	_dodge_dir = horizontal.normalized() if horizontal.length() > 0.5 else -global_basis.z
	_dodge_timer = core.registries.tunef("dodge_seconds", 0.32)
	set_state(State.DODGING)
	visual.play("dodge")


func set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	if new_state != State.FREE:
		cancel_click_command()
	if new_state == State.FREE:
		visual.play("idle")
	state_changed.emit(new_state)


func face_toward(target: Vector3) -> void:
	var to_target := target - position
	to_target.y = 0.0
	if to_target.length_squared() > 0.01:
		rotation.y = atan2(-to_target.x, -to_target.z)


func take_hit(damage: int) -> void:
	if (
		not core.registries.feature("combat_enabled", false)
		or _invuln_timer > 0.0
		or state == State.DODGING
		or state == State.DISABLED
	):
		return
	_invuln_timer = core.registries.tunef("player_hit_invuln_seconds", 0.8)
	visual.play("hit")
	core.combat.damage_player(damage)


func current_cell() -> Vector2i:
	return core.grid.world_to_cell(position)


func teleport_home() -> void:
	cancel_click_command()
	var home := core.grid.nearest_walkable(core.grid.home_cell)
	position = core.grid.cell_to_world(home)
	velocity = Vector3.ZERO


# ------------------------------------------------------------------ click movement

func set_click_command(destination: Vector3, interaction := {}) -> bool:
	if state != State.FREE:
		return false
	var start := current_cell()
	var goal := core.grid.world_to_cell(destination)
	if not core.grid.is_walkable(goal):
		return false
	var route := _cell_route(start, goal)
	if start != goal and route.is_empty():
		return false
	_click_path.clear()
	for coord in route:
		_click_path.append(core.grid.cell_to_world(coord))
	if _click_path.is_empty():
		_click_path.append(destination)
	else:
		_click_path[_click_path.size() - 1] = destination
	_click_interaction = interaction.duplicate()
	_click_stop_radius = (
		core.registries.tunef("click_interaction_stop_radius", 1.2)
		if not _click_interaction.is_empty()
		else core.registries.tunef("click_ground_stop_radius", 0.12)
	)
	return true


func cancel_click_command() -> void:
	_click_path.clear()
	_click_interaction.clear()


func has_click_command() -> bool:
	return not _click_path.is_empty()


func _click_wish() -> Vector3:
	if _click_path.is_empty():
		return Vector3.ZERO
	if _click_path.size() == 1 and _click_interaction.has("node"):
		var target_node := _click_interaction.get("node") as Node3D
		if is_instance_valid(target_node):
			_click_path[0] = target_node.global_position
		else:
			cancel_click_command()
			return Vector3.ZERO
	var to_waypoint := _click_path[0] - global_position
	to_waypoint.y = 0.0
	var stop_radius := _click_stop_radius if _click_path.size() == 1 else 0.16
	if to_waypoint.length() <= stop_radius:
		_click_path.pop_front()
		if _click_path.is_empty():
			var interaction := _click_interaction
			_click_interaction = {}
			if not interaction.is_empty():
				click_interaction_reached.emit(interaction)
			return Vector3.ZERO
		return _click_wish()
	return to_waypoint.normalized()


func _cell_route(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if start == goal:
		return result
	if not core.grid.is_walkable(start):
		start = core.grid.nearest_walkable(start)
	var frontier: Array[Vector2i] = [start]
	var came_from := {start: start}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == goal:
			break
		for offset: Vector2i in WorldGrid.NEIGHBORS:
			var next := current + offset
			if came_from.has(next) or not _click_route_cell_open(next, goal):
				continue
			came_from[next] = current
			frontier.append(next)
	if not came_from.has(goal):
		return result
	var cursor := goal
	while cursor != start:
		result.push_front(cursor)
		cursor = came_from[cursor]
	return result


func _click_route_cell_open(coord: Vector2i, goal: Vector2i) -> bool:
	if not core.grid.is_walkable(coord):
		return false
	if coord == goal:
		return true
	var tile_def := core.grid.tile_def(coord)
	# A pond tile can be approached as an interaction goal, but its blocked
	# basin is never a safe shortcut to somewhere else.
	if tile_def != null and not tile_def.water_cells.is_empty():
		return false
	var state := core.grid.cell(coord)
	for structure in state.structures:
		var structure_def := core.registries.structure(structure.structure_id)
		if (
			structure.socket_index == 0
			and structure_def != null
			and structure_def.blocks_movement
		):
			return false
	return true


# ------------------------------------------------------------------ interaction focus

func focus() -> Dictionary:
	return _focus


## Continuous, proximity-based interaction: nearest valid target within range,
## no tile-center requirement. Targets: pond edges (fish), grove anchors
## (chop), chest (storage), enemies (attack), reclaimed landmarks (resolve).
func _update_focus() -> void:
	if state != State.FREE:
		return
	var best: Dictionary = {}
	var best_distance := core.registries.tunef("interact_range", 1.6) + 0.9
	var my_cell := current_cell()
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var coord := my_cell + Vector2i(dx, dy)
			var cell_state := core.grid.cell(coord)
			if cell_state == null:
				continue
			var def := core.grid.tile_def(coord)
			if def == null:
				continue
			var center := core.grid.cell_to_world(coord)
			var interaction_point := center
			if not def.walkable and def.water_cells.has("open_water"):
				interaction_point += Vector3(0, 0, 1.25)
			var distance := position.distance_to(interaction_point)
			if def.anchor_id != "" and distance < best_distance:
				var anchor := core.registries.anchor(def.anchor_id)
				if core.skills.is_playable(anchor.skill_id) and not cell_state.anchor_resting:
					best = {"kind": "anchor", "coord": coord, "anchor": anchor, "point": interaction_point}
					best_distance = distance
			for s in cell_state.structures:
				var struct_def := core.registries.structure(s.structure_id)
				if struct_def != null and struct_def.provides.has("storage_access"):
					var struct_pos := center + core.grid.socket_offset(s.socket_index)
					var struct_distance := position.distance_to(struct_pos)
					if struct_distance < best_distance:
						best = {"kind": "storage", "coord": coord, "point": struct_pos}
						best_distance = struct_distance
	for package in get_tree().get_nodes_in_group("delivery_packages"):
		var package_node := package as Node3D
		if not is_instance_valid(package_node) or not package_node.visible:
			continue
		var point := package_node.global_position
		# A waiting parcel is the dock's primary interaction, ahead of the
		# adjacent fishing shoreline when both are within reach.
		var distance := position.distance_to(point) - 1.0
		if distance < best_distance:
			best = {"kind": "delivery_package", "node": package_node, "point": point}
			best_distance = distance
	if core.registries.feature("combat_enabled", false):
		for enemy in get_tree().get_nodes_in_group("enemies"):
			var enemy_node := enemy as Node3D
			var distance := position.distance_to(enemy_node.global_position)
			if distance < best_distance + 0.6:
				best = {"kind": "enemy", "node": enemy_node, "point": enemy_node.global_position}
				best_distance = distance
	if core.registries.feature("hostile_landmarks_enabled", false):
		for marker in get_tree().get_nodes_in_group("landmark_prompts"):
			var marker_node := marker as Node3D
			var distance := position.distance_to(marker_node.global_position)
			if distance < best_distance:
				best = {"kind": "landmark_prompt", "node": marker_node, "point": marker_node.global_position}
				best_distance = distance
	if best.get("kind") != _focus.get("kind") or best.get("coord") != _focus.get("coord") or best.get("node") != _focus.get("node"):
		_focus = best
		interaction_focus_changed.emit(best)
