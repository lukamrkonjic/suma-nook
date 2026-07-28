class_name PlayerController
extends CharacterBody3D
## Continuous free movement — the hard requirement. The physics transform is a
## float Vector3 driven by move_and_slide every tick; grid coordinates are only
## ever derived FROM the position for placement queries, never imposed on it.
## Also owns the player action state machine.

signal state_changed(new_state: State)
signal interaction_focus_changed(focus: Dictionary)   # {} when none
signal click_interaction_reached(interaction: Dictionary)

enum State { FREE, FISHING_CAST, FISHING_WAIT, FISHING_CATCH, WOODCUTTING, ATTACKING, DODGING, HIT, BUILDING, DISABLED, RESCUED, SWIMMING }

const GROUND_MASK := 1
const EDGE_WALL_MASK := WorldRenderer.EDGE_WALL_LAYER

var core: GameCore
var camera_rig: CameraRig
var visual: PlayerVisual

var state: State = State.FREE
var move_locked := false
## Grace window after spawns/reloads: world colliders can take a few frames
## to rebuild, and the brief floorless drop must not trigger the rescue.
var _rescue_grace := 0.0
var _rescue_tween: Tween
var _swim_phase := 0.0
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
	# Only the ground layer: the perimeter lip exists for enemies, never for
	# the player — stepping off the edge is a real choice (swim or portal).
	collision_mask = GROUND_MASK
	suspend_water_rescue()


func _physics_process(delta: float) -> void:
	if core == null:
		return
	if state == State.RESCUED:
		# The rescue tween owns the transform; physics stays out of the way.
		core.profile.position = position
		return
	_invuln_timer = maxf(0.0, _invuln_timer - delta)
	_rescue_grace = maxf(0.0, _rescue_grace - delta)
	match state:
		State.DODGING:
			_dodge_timer -= delta
			velocity = _dodge_dir * core.registries.tunef("dodge_speed", 8.5)
			if _dodge_timer <= 0.0:
				set_state(State.FREE)
		State.DISABLED:
			velocity = Vector3.ZERO
		State.SWIMMING:
			_swim_move(delta)
		_:
			_free_move(delta)
	if state != State.SWIMMING:
		if not is_on_floor():
			velocity.y -= core.registries.tunef("jump_gravity", 25.0) * delta
		else:
			velocity.y = maxf(velocity.y, 0.0)
	move_and_slide()
	# Landing in open water means floating, not sinking: swim mode.
	if (
		state in [State.FREE, State.BUILDING, State.DODGING, State.HIT]
		and velocity.y <= 0.0
		and _over_open_water()
		and position.y < core.registries.tunef("water_level_y", -0.14) - 0.05
	):
		velocity.y = 0.0
		set_state(State.SWIMMING)
	# Falling into the VOID — off the world entirely, no water beneath, Mario
	# Kart style — is what summons the rescue hole. Skill loops, cutscenes,
	# and scripted states are never hijacked.
	if (
		_rescue_grace <= 0.0
		and not is_on_floor()
		and state in [State.FREE, State.BUILDING, State.DODGING, State.HIT, State.SWIMMING]
		and not _over_open_water()
		and position.y < core.registries.tunef("water_rescue_trigger_y", -0.9)
	):
		_begin_water_rescue()
		return
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
	var walk_speed := core.registries.tunef("walk_speed", 2.2)
	var speed := walk_speed
	# Hold sprint to run: faster feet, faster clip, and a happy wobble.
	var sprinting := (
		Input.is_action_pressed("sprint")
		and state == State.FREE
		and wish.length_squared() > 0.001
	)
	if sprinting:
		speed *= core.registries.tunef("sprint_multiplier", 1.6)
	var accel := core.registries.tunef("walk_accel", 26.0) if wish != Vector3.ZERO else core.registries.tunef("walk_decel", 32.0)
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	horizontal = horizontal.move_toward(wish * speed, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if wish.length_squared() > 0.001:
		var target_yaw := atan2(-wish.x, -wish.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, core.registries.tunef("turn_speed", 12.0) * delta)
	# Normalized against WALK speed so a sprint drives the gait above 1.0
	# (faster stride and the run wobble in PlayerVisual).
	visual.set_walk(horizontal.length() / walk_speed, delta)


## Floating in open water: slower movement, a buoyancy spring that holds the
## swimmer at the surface with a gentle bob, and paddling arms from the walk
## cycle. Jump kicks out of the water; swimming past the water's edge into
## the void hands over to the rescue.
func _swim_move(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input.length_squared() > 0.04:
		cancel_click_command()
	var wish := Vector3.ZERO
	if not move_locked and input.length_squared() > 0.04:
		var basis := camera_rig.horizontal_basis()
		wish = (basis.x * input.x + basis.z * input.y)
		wish.y = 0.0
		if wish.length_squared() > 1.0:
			wish = wish.normalized()
	var speed := core.registries.tunef("swim_speed", 1.35)
	if Input.is_action_pressed("sprint") and wish.length_squared() > 0.001:
		speed *= core.registries.tunef("swim_sprint_multiplier", 1.3)
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	horizontal = horizontal.move_toward(wish * speed, core.registries.tunef("swim_accel", 14.0) * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if wish.length_squared() > 0.001:
		var target_yaw := atan2(-wish.x, -wish.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, core.registries.tunef("turn_speed", 12.0) * 0.7 * delta)
	_swim_phase += delta * 2.6
	if _over_open_water():
		var water_level := core.registries.tunef("water_level_y", -0.14)
		var swim_line := water_level - core.registries.tunef("swim_submerge", 0.32)
		var bob := sin(_swim_phase) * 0.05
		velocity.y = (swim_line + bob - position.y) * 8.0
	else:
		# Swam past the last water tile: nothing holds them up out here.
		velocity.y -= core.registries.tunef("jump_gravity", 25.0) * delta
	visual.set_walk(clampf(horizontal.length() / speed, 0.25, 1.0) * 0.85, delta)
	if is_on_floor():
		set_state(State.FREE)


func _over_open_water() -> bool:
	var def := core.grid.tile_def(current_cell())
	return def != null and def.water_cells.has("open_water")


func _unhandled_input(event: InputEvent) -> void:
	if state == State.DISABLED:
		return
	if (
		event.is_action_pressed("jump")
		and not move_locked
		and (
			(is_on_floor() and state in [State.FREE, State.BUILDING])
			or state == State.SWIMMING
		)
	):
		var swim_hop := state == State.SWIMMING
		if swim_hop:
			# Kick out of the water — enough to mount the shoreline lip.
			set_state(State.FREE)
		velocity.y = core.registries.tunef("jump_velocity", 5.4) * (0.9 if swim_hop else 1.0)
		floor_snap_length = 0.0
		get_tree().create_timer(0.12).timeout.connect(func():
			floor_snap_length = 0.4
		)
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
	var leaving_rescue := state == State.RESCUED
	state = new_state
	if leaving_rescue:
		_abort_rescue()
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
		or state == State.RESCUED
	):
		return
	_invuln_timer = core.registries.tunef("player_hit_invuln_seconds", 0.8)
	visual.play("hit")
	core.combat.damage_player(damage)


func current_cell() -> Vector2i:
	return core.grid.world_to_cell(position)


## Give the world a moment (rebuilds, teleports) before overboard detection
## resumes.
func suspend_water_rescue(seconds := 1.2) -> void:
	_rescue_grace = seconds


func teleport_home() -> void:
	cancel_click_command()
	var home := core.grid.nearest_walkable(core.grid.home_cell)
	position = core.grid.cell_to_world(home)
	velocity = Vector3.ZERO


# ------------------------------------------------------------------ water rescue

const RESCUE_HOLE_SHADER: Shader = preload("res://assets/materials/reworked/rescue_black_hole.gdshader")

## Overboard! The swimmer takes a proper long plunge, a flat matte hole
## (Donut County-style) opens on the water right under them, they drop
## through it like a teleport, and pop back out of a ground hole on the
## nearest shore with a squashy double bounce.
func _begin_water_rescue() -> void:
	if state == State.RESCUED:
		return
	set_state(State.RESCUED)
	cancel_click_command()
	velocity = Vector3.ZERO
	visual.set_walk(0.0, 0.016)
	visual.play("idle")
	var splash := position
	var target_cell := core.grid.nearest_walkable(current_cell())
	var target := core.grid.cell_to_world(target_cell)
	# Plop out BESIDE the exit hole, biased toward the island interior so the
	# landing spot stays on the walkable tile.
	var inward := Vector3(target.x - splash.x, 0.0, target.z - splash.z)
	inward = inward.normalized() if inward.length() > 0.1 else -global_basis.z
	var land_spot := target + inward * 0.42
	var rescue := create_tween()
	_rescue_tween = rescue
	# Mario Kart void poof: the hole opens right where the faller is — out of
	# bounds, under the level — growing small-to-large as they drop into it.
	var swallow_hole := _spawn_rescue_hole(Vector3(splash.x, splash.y - 1.15, splash.z))
	_grow_hole(swallow_hole, 0.05)
	rescue.tween_property(self, "position:y", splash.y - 2.1, 0.34) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Eaten: the player vanishes as they pass the portal plane, then it shuts.
	rescue.parallel().tween_callback(func(): visual.visible = false).set_delay(0.24)
	rescue.tween_callback(_close_hole.bind(swallow_hole))
	# Teleport beat while the hole is shut.
	rescue.tween_interval(0.16)
	# The same portal animation on land: grow small-to-large, then the player
	# plops out of it onto the tile.
	rescue.tween_callback(func():
		# Sits above every speckle/pebble decoration layer so nothing
		# renders on top of the portal.
		var exit_hole := _spawn_rescue_hole(target + Vector3(0.0, 0.1, 0.0))
		_grow_hole(exit_hole)
		_close_hole(exit_hole, 0.78)
		position = Vector3(target.x, target.y - 1.2, target.z)
		rotation.y = wrapf(rotation.y, -PI, PI)
	)
	rescue.tween_interval(0.24)
	# Plop! Reappear rising out of the hole, arc onto the tile beside it.
	rescue.tween_callback(func():
		visual.visible = true
		_squash(0.86, 1.18)
	)
	rescue.tween_property(self, "position:y", target.y + 0.62, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rescue.parallel().tween_property(self, "position:x", land_spot.x, 0.32) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	rescue.parallel().tween_property(self, "position:z", land_spot.z, 0.32) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	rescue.tween_property(self, "position:y", target.y, 0.14) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Bouncy squash-and-stretch landing beside the shrinking hole.
	rescue.tween_callback(_squash.bind(1.26, 0.7))
	rescue.tween_property(self, "position:y", target.y + 0.2, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rescue.tween_callback(_squash.bind(0.9, 1.12))
	rescue.tween_property(self, "position:y", target.y, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	rescue.tween_callback(_squash.bind(1.1, 0.88))
	rescue.tween_property(self, "position:y", target.y + 0.07, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rescue.tween_property(self, "position:y", target.y, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	rescue.tween_callback(func():
		_squash(1.0, 1.0)
		velocity = Vector3.ZERO
		core.profile.position = position
		core.profile.facing = rotation.y
		set_state(State.FREE)
	)


## External systems (cutscenes, scripted teleports, tests) may force the
## state away mid-rescue; the tween must not keep dragging the player around.
func _abort_rescue() -> void:
	if _rescue_tween != null and _rescue_tween.is_valid():
		_rescue_tween.kill()
	_rescue_tween = null
	visual.scale = Vector3.ONE
	visual.visible = true
	velocity = Vector3.ZERO


func _spawn_rescue_hole(at: Vector3) -> MeshInstance3D:
	var hole := MeshInstance3D.new()
	var disc := QuadMesh.new()
	disc.size = Vector2(0.81, 0.81)
	hole.mesh = disc
	var material := ShaderMaterial.new()
	material.shader = RESCUE_HOLE_SHADER
	hole.material_override = material
	hole.rotation_degrees.x = -90.0
	hole.scale = Vector3(0.01, 0.01, 0.01)
	hole.top_level = true
	add_child(hole)
	hole.global_position = at
	return hole


## The portal's signature entrance: a small pupil of a hole that snaps open,
## then widens to full size.
func _grow_hole(hole: MeshInstance3D, delay := 0.0) -> void:
	var grow := create_tween()
	if delay > 0.0:
		grow.tween_interval(delay)
	grow.tween_property(hole, "scale", Vector3(0.38, 0.38, 0.38), 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	grow.tween_property(hole, "scale", Vector3.ONE, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _close_hole(hole: MeshInstance3D, delay := 0.0) -> void:
	var close := create_tween()
	if delay > 0.0:
		close.tween_interval(delay)
	close.tween_property(hole, "scale", Vector3(0.01, 0.01, 0.01), 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	close.tween_callback(hole.queue_free)


func _squash(width: float, height: float) -> void:
	var squash := create_tween()
	squash.tween_property(visual, "scale", Vector3(width, height, width), 0.09) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------ click movement

func set_click_command(destination: Vector3, interaction := {}) -> bool:
	if state != State.FREE:
		return false
	var start := current_cell()
	var goal := core.grid.world_to_cell(destination)
	if not core.grid.is_traversable(goal):
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
	if not core.grid.is_traversable(start):
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
	if not core.grid.is_traversable(coord):
		return false
	if coord == goal:
		return true
	var tile_def := core.grid.tile_def(coord)
	# A pond tile can be approached as an interaction goal, but its blocked
	# basin is never a safe shortcut to somewhere else.
	if (
		tile_def != null
		and not tile_def.water_cells.is_empty()
		and not core.grid.has_walkable_structure_surface(coord)
	):
		return false
	var state := core.grid.cell(coord)
	for structure in state.structures:
		if structure.parent_instance_id == 0:
			return false
	return true


# ------------------------------------------------------------------ interaction focus

func focus() -> Dictionary:
	return _focus


## Continuous, proximity-based interaction: nearest valid target within range,
## no tile-center requirement. Terrain owns water/mineral anchors; independently
## placed trees own woodland anchors; the chest remains an ordinary structure.
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
	for slot: Dictionary in core.grid.all_cell_slots():
		var coord: Vector2i = slot["coord"]
		if absi(coord.x - my_cell.x) > 1 or absi(coord.y - my_cell.y) > 1:
			continue
		var elevation := int(slot["elevation"])
		var cell_state: WorldGrid.CellState = slot["state"]
		var cell_origin := core.grid.cell_to_world(coord, elevation)
		for structure: WorldGrid.StructureState in cell_state.structures:
			var struct_def := core.registries.structure(structure.structure_id)
			if struct_def == null:
				continue
			var struct_pos := (
				cell_origin
				+ core.grid.structure_local_transform(structure.instance_id).origin
			)
			var struct_distance := position.distance_to(struct_pos)
			if (
				struct_def.anchor_id != ""
				and not structure.anchor_resting
				and struct_distance < best_distance
			):
				var anchor := core.registries.anchor(struct_def.anchor_id)
				if anchor != null and core.skills.is_playable(anchor.skill_id):
					best = {
						"kind": "anchor",
						"coord": coord,
						"elevation": elevation,
						"instance_id": structure.instance_id,
						"anchor": anchor,
						"point": struct_pos,
					}
					best_distance = struct_distance
			if struct_def.has_capability("storage_access") and struct_distance < best_distance:
				best = {
					"kind": "storage",
					"coord": coord,
					"elevation": elevation,
					"instance_id": structure.instance_id,
					"point": struct_pos,
				}
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
	if (
		best.get("kind") != _focus.get("kind")
		or best.get("coord") != _focus.get("coord")
		or best.get("instance_id") != _focus.get("instance_id")
		or best.get("node") != _focus.get("node")
	):
		_focus = best
		interaction_focus_changed.emit(best)
