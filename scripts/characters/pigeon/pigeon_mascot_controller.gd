class_name PigeonMascotController
extends Node

## Lightweight ambient mascot AI. The pigeon walks only between clear,
## traversable WorldGrid cells, then periodically takes off, circles the
## moving player, and lands on another safe nearby cell.

signal movement_state_changed(state: MovementState)

enum MovementState {
	DORMANT,
	IDLE,
	WALKING,
	TAKING_OFF,
	FLYING,
	LANDING,
}

@export_range(0.1, 3.0, 0.05, "suffix:m/s") var walk_speed := 0.62
@export_range(0.5, 8.0, 0.1, "suffix:m/s") var flight_speed := 2.65
@export_range(0.5, 3.0, 0.05, "suffix:m") var flight_altitude := 1.15
@export_range(0.5, 5.0, 0.05, "suffix:m") var orbit_radius_min := 1.65
@export_range(0.5, 5.0, 0.05, "suffix:m") var orbit_radius_max := 2.45
@export_range(2.0, 20.0, 0.25, "suffix:s") var flight_duration_min := 5.0
@export_range(2.0, 20.0, 0.25, "suffix:s") var flight_duration_max := 8.5
@export_range(1.0, 12.0, 0.25, "suffix:m") var ground_follow_radius := 4.5
@export_range(2.0, 16.0, 0.25, "suffix:m") var forced_takeoff_distance := 6.5

@onready var mascot := get_parent() as CharacterBody3D
@onready var model := mascot.get_node("Model") as Node3D
@onready var skeleton := mascot.get_node("Model/PigeonRig/Skeleton3D") as Skeleton3D
@onready var face := mascot.get_node("FaceAttachment/FaceAnchor") as PigeonFaceRig

var movement_state := MovementState.DORMANT
var player: PlayerController
var grid: WorldGrid

var _rng := RandomNumberGenerator.new()
var _state_seconds := 0.0
var _look_seconds := 0.0
var _pose_time := 0.0
var _walk_phase := 0.0
var _wing_phase := 0.0
var _ground_hops := 0
var _current_cell := Vector2i.ZERO
var _target_cell := Vector2i.ZERO
var _target_world := Vector3.ZERO
var _takeoff_origin := Vector3.ZERO
var _takeoff_target_y := 0.0
var _landing_cell := Vector2i.ZERO
var _landing_world := Vector3.ZERO
var _orbit_phase := 0.0
var _orbit_radius := 2.0
var _orbit_direction := 1.0
var _model_rest_position := Vector3.ZERO

var _wing_root_bones: Array[int] = []
var _wing_mid_bones: Array[int] = []
var _wing_tip_bones: Array[int] = []
var _thigh_bones: Array[int] = []
var _shin_bones: Array[int] = []
var _foot_bones: Array[int] = []
var _neck_bones: Array[int] = []
var _head_bones: Array[int] = []
var _tail_bones: Array[int] = []
var _animated_bones: Array[int] = []
var _base_bone_rotations: Dictionary = {}
var _lab_preview_animation := ""


func _ready() -> void:
	_rng.randomize()
	_model_rest_position = model.position
	_cache_bones()
	# Wing deformation can extend well beyond the imported T-pose bounds.
	# Give skinned meshes room so the body is never culled while the wings move.
	for child in model.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).extra_cull_margin = 1.5
	mascot.visible = false
	mascot.collision_layer = 0
	mascot.collision_mask = 0
	set_physics_process(false)


func setup(player_controller: PlayerController, world_grid: WorldGrid) -> void:
	player = player_controller
	grid = world_grid
	set_physics_process(true)


func spawn_near_player() -> void:
	if not is_instance_valid(player) or grid == null:
		return
	var result := _find_safe_cell_near(grid.world_to_cell(player.global_position), 3)
	if bool(result.get("found", false)):
		_current_cell = result["cell"]
		mascot.global_position = _ground_position(_current_cell)
	else:
		_current_cell = grid.world_to_cell(player.global_position)
		mascot.global_position = player.global_position + Vector3(0.72, 0.03, 0.32)
	var player_direction := player.global_position - mascot.global_position
	player_direction.y = 0.0
	if player_direction.length_squared() > 0.001:
		_face_direction(player_direction.normalized())
	model.visible = true
	mascot.visible = true
	_ground_hops = 0
	_begin_idle(0.7)


func despawn() -> void:
	movement_state = MovementState.DORMANT
	mascot.visible = false
	_reset_visual_pose()


func movement_state_name() -> String:
	return MovementState.keys()[movement_state].to_lower()


func is_flying() -> bool:
	return movement_state in [
		MovementState.TAKING_OFF,
		MovementState.FLYING,
		MovementState.LANDING,
	]


## Drives the same procedural poses used in the world from a deterministic
## editor timeline. Root translation belongs to the preview host so this API
## can be reused by the Clothing Lab without a WorldGrid or player.
func set_lab_preview_animation(animation_name: String) -> void:
	_lab_preview_animation = animation_name
	_reset_visual_pose()
	face.set_talking(false)
	match animation_name:
		"fly":
			face.set_expression(PigeonFaceRig.EyeExpression.HAPPY)
		"fishing":
			face.set_expression(PigeonFaceRig.EyeExpression.NEUTRAL)
			face.set_pupil_direction(Vector2(0.0, -0.72))
		_:
			face.set_expression(PigeonFaceRig.EyeExpression.NEUTRAL)


func apply_lab_preview_animation(time_seconds: float, _delta: float) -> void:
	match _lab_preview_animation:
		"idle":
			_apply_ground_wing_tuck(0.82)
			_apply_idle_body_pose(time_seconds)
			model.position = (
				_model_rest_position
				+ Vector3.UP * sin(time_seconds * 2.2) * 0.004
			)
			model.rotation.x = sin(time_seconds * 0.8) * 0.008
			model.rotation.z = sin(time_seconds * 1.35) * 0.008
		"walk":
			var phase := time_seconds * 8.5
			_apply_ground_wing_tuck(0.82 + sin(phase) * 0.018)
			_apply_walk_cycle(phase)
			model.position = (
				_model_rest_position
				+ Vector3.UP * absf(sin(phase)) * 0.026
			)
			model.rotation.x = 0.0
			model.rotation.z = sin(phase) * 0.035
		"fly":
			var phase := time_seconds * 11.5
			_wing_phase = phase
			_apply_flight_flap(0.52)
			_apply_flight_body_pose(phase)
			model.position = (
				_model_rest_position
				+ Vector3.UP * sin(phase) * 0.018
			)
			model.rotation.x = -0.14
			model.rotation.z = sin(time_seconds * 1.6) * 0.045
		"fishing":
			_apply_fishing_pose(time_seconds)
		_:
			# Rest mode deliberately leaves the lab's manual DEF-bone edits alone.
			pass


func _physics_process(delta: float) -> void:
	if (
		movement_state == MovementState.DORMANT
		or not mascot.visible
		or not is_instance_valid(player)
		or grid == null
	):
		return

	_pose_time += delta
	_update_face_tracking(delta)
	if (
		movement_state in [MovementState.IDLE, MovementState.WALKING]
		and _horizontal_distance(mascot.global_position, player.global_position)
		> forced_takeoff_distance
	):
		_begin_takeoff()

	match movement_state:
		MovementState.IDLE:
			_update_idle(delta)
		MovementState.WALKING:
			_update_walking(delta)
		MovementState.TAKING_OFF:
			_update_takeoff(delta)
		MovementState.FLYING:
			_update_flying(delta)
		MovementState.LANDING:
			_update_landing(delta)

	_update_visual_pose(delta)


func _update_face_tracking(delta: float) -> void:
	_look_seconds -= delta
	if _look_seconds <= 0.0:
		face.look_at_world_point(player.global_position + Vector3.UP * 0.82)
		_look_seconds = 0.10


func _update_idle(delta: float) -> void:
	_state_seconds -= delta
	if _state_seconds > 0.0:
		return
	if _ground_hops >= _rng.randi_range(2, 4) or _rng.randf() < 0.28:
		_begin_takeoff()
		return
	if not _begin_walk_to_neighbor():
		_begin_takeoff()


func _begin_idle(minimum_seconds := 1.0) -> void:
	_set_state(MovementState.IDLE)
	_state_seconds = maxf(minimum_seconds, _rng.randf_range(1.25, 3.25))
	face.set_expression(PigeonFaceRig.EyeExpression.NEUTRAL)


func _begin_walk_to_neighbor() -> bool:
	_current_cell = grid.world_to_cell(mascot.global_position)
	var candidates: Array[Vector2i] = []
	for offset: Vector2i in WorldGrid.NEIGHBORS:
		var candidate := _current_cell + offset
		if not _is_clear_ground_cell(candidate):
			continue
		var candidate_world := _ground_position(candidate)
		if (
			_horizontal_distance(candidate_world, player.global_position)
			<= ground_follow_radius
		):
			candidates.append(candidate)
	if candidates.is_empty():
		return false
	candidates.shuffle()
	# Prefer a step that does not increase the distance from a moving player.
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (
			_horizontal_distance(_ground_position(a), player.global_position)
			< _horizontal_distance(_ground_position(b), player.global_position)
		)
	)
	var choice_pool := mini(2, candidates.size())
	_target_cell = candidates[_rng.randi_range(0, choice_pool - 1)]
	_target_world = _ground_position(_target_cell)
	var walk_direction := _target_world - mascot.global_position
	walk_direction.y = 0.0
	if walk_direction.length_squared() > 0.001:
		# Complete the little in-place turn before translating so the bird never
		# appears to moonwalk during a 90/180-degree route change.
		_face_direction(walk_direction.normalized())
	_set_state(MovementState.WALKING)
	return true


func _update_walking(delta: float) -> void:
	if not _is_clear_ground_cell(_target_cell):
		_begin_idle(0.4)
		return
	var offset := _target_world - mascot.global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= 0.025:
		mascot.global_position = _target_world
		_current_cell = _target_cell
		_ground_hops += 1
		_begin_idle(0.45)
		return
	var direction := offset / distance
	var step := minf(walk_speed * delta, distance)
	mascot.global_position += direction * step
	mascot.global_position.y = _target_world.y
	_turn_toward(direction, delta, 8.0)
	_walk_phase += delta * 8.5


func _begin_takeoff() -> void:
	if movement_state in [MovementState.TAKING_OFF, MovementState.FLYING]:
		return
	_set_state(MovementState.TAKING_OFF)
	_state_seconds = 0.72
	_takeoff_origin = mascot.global_position
	_takeoff_target_y = maxf(
		_takeoff_origin.y + flight_altitude,
		player.global_position.y + flight_altitude
	)
	_wing_phase = 0.0


func _update_takeoff(delta: float) -> void:
	_state_seconds -= delta
	var progress := clampf(1.0 - _state_seconds / 0.72, 0.0, 1.0)
	var eased := progress * progress * (3.0 - 2.0 * progress)
	mascot.global_position.y = lerpf(_takeoff_origin.y, _takeoff_target_y, eased)
	var toward_player := player.global_position - mascot.global_position
	toward_player.y = 0.0
	if toward_player.length_squared() > 0.001:
		_turn_toward(toward_player.normalized(), delta, 5.0)
	if _state_seconds <= 0.0:
		_begin_flying()


func _begin_flying() -> void:
	_set_state(MovementState.FLYING)
	_state_seconds = _rng.randf_range(flight_duration_min, flight_duration_max)
	_orbit_radius = _rng.randf_range(orbit_radius_min, orbit_radius_max)
	_orbit_direction = -1.0 if _rng.randf() < 0.5 else 1.0
	var relative := mascot.global_position - player.global_position
	_orbit_phase = atan2(relative.z, relative.x)


func _update_flying(delta: float) -> void:
	_state_seconds -= delta
	_orbit_phase += delta * 0.86 * _orbit_direction
	var altitude_wave := sin(_orbit_phase * 1.7) * 0.14
	var target := player.global_position + Vector3(
		cos(_orbit_phase) * _orbit_radius,
		flight_altitude + altitude_wave,
		sin(_orbit_phase) * _orbit_radius
	)
	var previous := mascot.global_position
	mascot.global_position = mascot.global_position.move_toward(
		target,
		flight_speed * delta
	)
	var direction := mascot.global_position - previous
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		_turn_toward(direction.normalized(), delta, 6.0)
	if _state_seconds <= 0.0:
		var landing := _find_safe_cell_near(
			grid.world_to_cell(player.global_position),
			3
		)
		if bool(landing.get("found", false)):
			_begin_landing(landing["cell"])
		else:
			_state_seconds = 2.0


func _begin_landing(cell: Vector2i) -> void:
	_landing_cell = cell
	_landing_world = _ground_position(cell)
	_set_state(MovementState.LANDING)


func _update_landing(delta: float) -> void:
	if not _is_clear_ground_cell(_landing_cell):
		_begin_flying()
		return
	var horizontal_offset := _landing_world - mascot.global_position
	horizontal_offset.y = 0.0
	var horizontal_distance := horizontal_offset.length()
	var approach_height := clampf(horizontal_distance * 0.5, 0.0, 0.72)
	var approach := _landing_world + Vector3.UP * approach_height
	var previous := mascot.global_position
	mascot.global_position = mascot.global_position.move_toward(
		approach,
		flight_speed * 0.82 * delta
	)
	var direction := mascot.global_position - previous
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		_turn_toward(direction.normalized(), delta, 7.0)
	if mascot.global_position.distance_to(_landing_world) <= 0.045:
		mascot.global_position = _landing_world
		_current_cell = _landing_cell
		_ground_hops = 0
		_begin_idle(1.0)


func _update_visual_pose(delta: float) -> void:
	var bob := 0.0
	var roll := 0.0
	var pitch := 0.0
	match movement_state:
		MovementState.WALKING:
			bob = absf(sin(_walk_phase)) * 0.026
			roll = sin(_walk_phase) * 0.035
			_apply_ground_wing_tuck(0.82 + sin(_walk_phase) * 0.018)
			_apply_walk_cycle(_walk_phase)
		MovementState.IDLE:
			bob = sin(_pose_time * 2.2) * 0.004
			roll = sin(_pose_time * 1.35) * 0.008
			_apply_ground_wing_tuck(0.82)
			_apply_idle_body_pose(_pose_time)
		MovementState.TAKING_OFF:
			_wing_phase += delta * 18.0
			var remaining_tuck := clampf(_state_seconds / 0.72, 0.0, 1.0) * 0.82
			_apply_flight_flap(0.62, remaining_tuck)
			pitch = -0.10
		MovementState.FLYING:
			_wing_phase += delta * 11.5
			_apply_flight_flap(0.52)
			_apply_flight_body_pose(_wing_phase)
			bob = sin(_wing_phase) * 0.018
			roll = sin(_orbit_phase) * 0.075 * _orbit_direction
			pitch = -0.14
		MovementState.LANDING:
			_wing_phase += delta * 15.0
			_apply_flight_flap(0.46)
			_apply_landing_body_pose()
			pitch = 0.08
	model.position = _model_rest_position + Vector3.UP * bob
	model.rotation.x = lerpf(model.rotation.x, pitch, minf(1.0, delta * 8.0))
	model.rotation.z = lerpf(model.rotation.z, roll, minf(1.0, delta * 8.0))


func _apply_flight_flap(amplitude: float, shoulder_tuck := 0.0) -> void:
	var angle := sin(_wing_phase) * amplitude
	var fold_weight := clampf(shoulder_tuck / 0.82, 0.0, 1.0)
	var mid_angle := -angle * 0.36 + fold_weight
	var tip_angle := -angle * 0.22 + fold_weight * 0.55
	_apply_shoulder_pose(fold_weight * 1.35, angle)
	_apply_bone_rotation(_wing_mid_bones, Vector3.RIGHT, mid_angle)
	_apply_bone_rotation(_wing_tip_bones, Vector3.RIGHT, tip_angle)


func _apply_walk_cycle(phase: float) -> void:
	for side_index in _thigh_bones.size():
		var direction := 1.0 if side_index == 0 else -1.0
		var swing := sin(phase) * 0.30 * direction
		_apply_bone_index_angle(
			_thigh_bones[side_index], Vector3.RIGHT, swing
		)
		_apply_bone_index_angle(
			_shin_bones[side_index],
			Vector3.RIGHT,
			-maxf(0.0, -sin(phase) * direction) * 0.34,
		)
		_apply_bone_index_angle(
			_foot_bones[side_index], Vector3.RIGHT, -swing * 0.42
		)
	_apply_bone_rotation(
		_head_bones,
		Vector3.RIGHT,
		-sin(phase) * 0.055,
	)
	_apply_bone_rotation(
		_tail_bones,
		Vector3.RIGHT,
		sin(phase) * 0.045,
	)


func _apply_idle_body_pose(time_seconds: float) -> void:
	_reset_bone_group(_thigh_bones)
	_reset_bone_group(_shin_bones)
	_reset_bone_group(_foot_bones)
	_apply_bone_rotation(
		_head_bones,
		Vector3.RIGHT,
		sin(time_seconds * 1.4) * 0.025,
	)
	_apply_bone_rotation(
		_tail_bones,
		Vector3.RIGHT,
		sin(time_seconds * 1.1) * 0.018,
	)


func _apply_flight_body_pose(phase: float) -> void:
	for bone_index in _thigh_bones:
		_apply_bone_index_angle(bone_index, Vector3.RIGHT, -0.18)
	for bone_index in _shin_bones:
		_apply_bone_index_angle(bone_index, Vector3.RIGHT, 0.30)
	for bone_index in _foot_bones:
		_apply_bone_index_angle(bone_index, Vector3.RIGHT, -0.16)
	_apply_bone_rotation(
		_tail_bones,
		Vector3.RIGHT,
		0.10 + sin(phase * 0.5) * 0.035,
	)
	_apply_bone_rotation(_head_bones, Vector3.RIGHT, -0.055)


func _apply_landing_body_pose() -> void:
	_reset_bone_group(_thigh_bones)
	_reset_bone_group(_shin_bones)
	_reset_bone_group(_foot_bones)
	_apply_bone_rotation(_tail_bones, Vector3.RIGHT, 0.14)
	_apply_bone_rotation(_head_bones, Vector3.RIGHT, 0.05)


func _apply_fishing_pose(time_seconds: float) -> void:
	var cycle := fmod(time_seconds, 4.8)
	var cast_amount := 0.0
	if cycle < 0.72:
		cast_amount = sin(cycle / 0.72 * PI) * 0.46
	var cast_open := cast_amount / 0.46
	var fold_weight := 1.0 - cast_open * 0.70
	_apply_shoulder_pose(1.35 * fold_weight, -cast_amount)
	_apply_bone_rotation(
		_wing_mid_bones,
		Vector3.RIGHT,
		fold_weight + cast_amount * 0.24,
	)
	_apply_bone_rotation(
		_wing_tip_bones,
		Vector3.RIGHT,
		fold_weight * 0.55 + cast_amount * 0.16,
	)
	_reset_bone_group(_thigh_bones)
	_reset_bone_group(_shin_bones)
	_reset_bone_group(_foot_bones)
	var watch_bobber := sin(time_seconds * 2.1) * 0.025
	_apply_bone_rotation(
		_neck_bones,
		Vector3.RIGHT,
		0.10 + watch_bobber,
	)
	_apply_bone_rotation(
		_head_bones,
		Vector3.RIGHT,
		0.19 + watch_bobber,
	)
	_apply_bone_rotation(
		_tail_bones,
		Vector3.RIGHT,
		-0.04 + sin(time_seconds * 1.3) * 0.025,
	)
	model.position = (
		_model_rest_position
		+ Vector3.UP * sin(time_seconds * 2.1) * 0.004
	)
	model.rotation.x = 0.07 + cast_amount * 0.08
	model.rotation.z = sin(time_seconds * 0.9) * 0.008
	face.set_pupil_direction(Vector2(0.0, -0.72))


func _apply_ground_wing_tuck(shoulder_tuck: float) -> void:
	# The imported rest pose is fully spread. A convincing ground silhouette
	# therefore needs all three bird joints: sweep the shoulder rearward, fold
	# sharply at the elbow, then lay the tip over the flank toward the tail.
	var fold_weight := clampf(shoulder_tuck / 0.82, 0.0, 1.08)
	_apply_shoulder_pose(1.35 * fold_weight, 0.0)
	_apply_bone_rotation(
		_wing_mid_bones,
		Vector3.RIGHT,
		fold_weight,
	)
	_apply_bone_rotation(
		_wing_tip_bones,
		Vector3.RIGHT,
		0.55 * fold_weight,
	)


func _apply_shoulder_pose(shoulder_tuck: float, flap_angle: float) -> void:
	# Rigify mirrors the local Z axis across the body, so the rearward tuck must
	# use opposite signs while the local-X flap keeps the same sign.
	for side_index in _wing_root_bones.size():
		var bone_index := _wing_root_bones[side_index]
		if bone_index < 0:
			continue
		var mirrored_tuck := shoulder_tuck if side_index == 0 else -shoulder_tuck
		_apply_bone_index_offset(
			bone_index,
			Quaternion(Vector3.BACK, mirrored_tuck)
				* Quaternion(Vector3.RIGHT, flap_angle)
		)


func _apply_bone_rotation(bones: Array[int], axis: Vector3, angle: float) -> void:
	_apply_bone_offset(bones, Quaternion(axis, angle))


func _apply_bone_index_angle(
	bone_index: int,
	axis: Vector3,
	angle: float,
) -> void:
	if bone_index >= 0:
		_apply_bone_index_offset(bone_index, Quaternion(axis, angle))


func _reset_bone_group(bones: Array[int]) -> void:
	for bone_index in bones:
		if bone_index >= 0:
			skeleton.set_bone_pose_rotation(
				bone_index,
				_base_bone_rotations.get(
					bone_index,
					Quaternion.IDENTITY,
				),
			)


func _apply_bone_offset(bones: Array[int], offset: Quaternion) -> void:
	for bone_index in bones:
		if bone_index >= 0:
			_apply_bone_index_offset(bone_index, offset)


func _apply_bone_index_offset(bone_index: int, offset: Quaternion) -> void:
	var base: Quaternion = _base_bone_rotations.get(
		bone_index,
		Quaternion.IDENTITY
	)
	skeleton.set_bone_pose_rotation(bone_index, base * offset)


func _cache_bones() -> void:
	_wing_root_bones = [
		skeleton.find_bone("DEF-Wing.L"),
		skeleton.find_bone("DEF-Wing.R"),
	]
	_wing_mid_bones = [
		skeleton.find_bone("DEF-Wing.001.L"),
		skeleton.find_bone("DEF-Wing.001.R"),
	]
	_wing_tip_bones = [
		skeleton.find_bone("DEF-Wing.002.L"),
		skeleton.find_bone("DEF-Wing.002.R"),
	]
	_thigh_bones = [
		skeleton.find_bone("DEF-thigh.L"),
		skeleton.find_bone("DEF-thigh.R"),
	]
	_shin_bones = [
		skeleton.find_bone("DEF-shin.L"),
		skeleton.find_bone("DEF-shin.R"),
	]
	_foot_bones = [
		skeleton.find_bone("DEF-foot.L"),
		skeleton.find_bone("DEF-foot.R"),
	]
	_neck_bones = [
		skeleton.find_bone("DEF-neck.001"),
		skeleton.find_bone("DEF-neck.002"),
	]
	_head_bones = [skeleton.find_bone("DEF-head")]
	_tail_bones = [
		skeleton.find_bone("DEF-spine"),
		skeleton.find_bone("DEF-spine.001"),
		skeleton.find_bone("DEF-spine.002"),
	]
	_animated_bones = (
		_wing_root_bones
		+ _wing_mid_bones
		+ _wing_tip_bones
		+ _thigh_bones
		+ _shin_bones
		+ _foot_bones
		+ _neck_bones
		+ _head_bones
		+ _tail_bones
	)
	for bone_index in _animated_bones:
		if bone_index >= 0:
			_base_bone_rotations[bone_index] = skeleton.get_bone_pose_rotation(
				bone_index
			)


func _reset_visual_pose() -> void:
	model.position = _model_rest_position
	model.rotation.x = 0.0
	model.rotation.z = 0.0
	for bone_index in _animated_bones:
		if bone_index >= 0:
			skeleton.set_bone_pose_rotation(
				bone_index,
				_base_bone_rotations.get(bone_index, Quaternion.IDENTITY)
			)


func _find_safe_cell_near(origin: Vector2i, radius: int) -> Dictionary:
	var candidates: Array[Vector2i] = []
	for ring in range(1, radius + 1):
		for x in range(-ring, ring + 1):
			for z in range(-ring, ring + 1):
				if maxi(absi(x), absi(z)) != ring:
					continue
				var candidate := origin + Vector2i(x, z)
				if not _is_clear_ground_cell(candidate):
					continue
				if (
					_horizontal_distance(
						_ground_position(candidate),
						player.global_position
					) < 0.65
				):
					continue
				candidates.append(candidate)
		if not candidates.is_empty():
			candidates.shuffle()
			return {"found": true, "cell": candidates[0]}
	if _is_clear_ground_cell(origin):
		return {"found": true, "cell": origin}
	return {"found": false}


func _is_clear_ground_cell(cell: Vector2i) -> bool:
	if not grid.is_walkable(cell):
		return false
	var state := grid.cell(cell)
	return state != null and state.structures.is_empty()


func _ground_position(cell: Vector2i) -> Vector3:
	return grid.cell_to_world(cell) + Vector3.UP * 0.025


func _turn_toward(direction: Vector3, delta: float, speed: float) -> void:
	var target_yaw := _yaw_for_direction(direction)
	mascot.rotation.y = lerp_angle(
		mascot.rotation.y,
		target_yaw,
		minf(1.0, speed * delta)
	)


func _face_direction(direction: Vector3) -> void:
	mascot.rotation.y = _yaw_for_direction(direction)


func _yaw_for_direction(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


func _set_state(next_state: MovementState) -> void:
	if movement_state == next_state:
		return
	movement_state = next_state
	movement_state_changed.emit(movement_state)


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
