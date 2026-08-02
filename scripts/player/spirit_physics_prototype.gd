class_name SpiritPhysicsPrototype
extends Node3D
## Minimal human driven entirely by live controller physics and spring-linked
## body parts. There are no authored animation clips: ground contact moves the
## feet, the feet pull the legs and pelvis, then the torso, head, and arms
## react with successively softer spring timing.

const BODY_REST := Vector3(0.0, 0.42, 0.0)
const HEAD_REST := Vector3(0.0, 0.65, -0.005)
const BACKPACK_REST := Vector3(0.0, 0.48, 0.11)
const LEFT_FOOT_REST := Vector3(-0.065, 0.055, 0.0)
const RIGHT_FOOT_REST := Vector3(0.065, 0.055, 0.0)
const UPPER_LEG_LENGTH := 0.135
const LOWER_LEG_LENGTH := 0.135
const UPPER_ARM_LENGTH := 0.11
const LOWER_ARM_LENGTH := 0.11

var _controller: CharacterBody3D

var _body_root: Node3D
var _head_root: Node3D
var _backpack_root: Node3D
var _left_hand: Node3D
var _right_hand: Node3D
var _left_elbow: Node3D
var _right_elbow: Node3D
var _left_foot: Node3D
var _right_foot: Node3D
var _left_knee: Node3D
var _right_knee: Node3D

var _left_upper_arm: MeshInstance3D
var _left_lower_arm: MeshInstance3D
var _right_upper_arm: MeshInstance3D
var _right_lower_arm: MeshInstance3D
var _left_thigh: MeshInstance3D
var _left_shin: MeshInstance3D
var _right_thigh: MeshInstance3D
var _right_shin: MeshInstance3D

var _body_velocity := Vector3.ZERO
var _body_rotation_velocity := Vector3.ZERO
var _body_scale_velocity := Vector3.ZERO
var _head_velocity := Vector3.ZERO
var _head_rotation_velocity := Vector3.ZERO
var _backpack_velocity := Vector3.ZERO
var _backpack_rotation_velocity := Vector3.ZERO
var _left_hand_velocity := Vector3.ZERO
var _right_hand_velocity := Vector3.ZERO
var _left_elbow_velocity := Vector3.ZERO
var _right_elbow_velocity := Vector3.ZERO
var _left_foot_velocity := Vector3.ZERO
var _right_foot_velocity := Vector3.ZERO
var _left_knee_velocity := Vector3.ZERO
var _right_knee_velocity := Vector3.ZERO
var _left_foot_scale_velocity := Vector3.ZERO
var _right_foot_scale_velocity := Vector3.ZERO
var _left_foot_rotation_velocity := Vector3.ZERO
var _right_foot_rotation_velocity := Vector3.ZERO
var _previous_local_velocity := Vector3.ZERO

var _gait_phase := 0.0
var _idle_time := 0.0
var _landing_squash := 0.0
var _wave_strength := 0.0
var _was_on_floor := true

func build() -> void:
	if _body_root != null:
		return
	_controller = get_parent().get_parent() as CharacterBody3D

	var body_color := Color("#7fae78")
	var body_shadow := Color("#688f67")
	var face_color := Color("#efd4ae")
	var blush_color := Color("#d98c88")
	var leg_color := Color("#617b65")
	var foot_color := Color("#4a6251")
	var ink := Color("#30352f")

	_body_root = Node3D.new()
	_body_root.name = "SpringTorso"
	_body_root.position = BODY_REST
	add_child(_body_root)
	_add_capsule(
		_body_root, "Torso", Vector3.ZERO,
		Vector3(0.135, 0.145, 0.115), body_color
	)
	_add_sphere(
		_body_root, "SoftWaist", Vector3(0.0, -0.10, 0.0),
		Vector3(0.10, 0.055, 0.09), body_shadow
	)

	_head_root = Node3D.new()
	_head_root.name = "SpringHead"
	_head_root.position = HEAD_REST
	add_child(_head_root)
	_add_capsule(
		_head_root, "Hood", Vector3(0.0, 0.0, 0.012),
		Vector3(0.165, 0.155, 0.145), body_color.lightened(0.04)
	)
	_add_sphere(
		_head_root, "Face", Vector3(0.0, -0.010, -0.143),
		Vector3(0.086, 0.078, 0.014), face_color
	)
	_add_sphere(
		_head_root, "EyeLeft", Vector3(-0.032, 0.004, -0.159),
		Vector3(0.012, 0.022, 0.008), ink
	)
	_add_sphere(
		_head_root, "EyeRight", Vector3(0.032, 0.004, -0.159),
		Vector3(0.012, 0.022, 0.008), ink
	)
	_add_sphere(
		_head_root, "CheekLeft", Vector3(-0.060, -0.032, -0.155),
		Vector3(0.020, 0.010, 0.006), blush_color
	)
	_add_sphere(
		_head_root, "CheekRight", Vector3(0.060, -0.032, -0.155),
		Vector3(0.020, 0.010, 0.006), blush_color
	)
	_add_sphere(
		_head_root, "TinyMouth", Vector3(0.0, -0.050, -0.160),
		Vector3(0.007, 0.009, 0.005), ink
	)

	_backpack_root = Node3D.new()
	_backpack_root.name = "SpringBackpack"
	_backpack_root.position = BACKPACK_REST
	add_child(_backpack_root)

	_left_hand = _make_joint("LeftHand", Vector3(-0.105, 0.42, -0.14), body_color.lightened(0.08), 0.050)
	_right_hand = _make_joint("RightHand", Vector3(0.105, 0.42, -0.14), body_color.lightened(0.08), 0.050)
	_left_elbow = _make_joint("LeftElbow", Vector3(-0.17, 0.45, -0.045), body_color, 0.040)
	_right_elbow = _make_joint("RightElbow", Vector3(0.17, 0.45, -0.045), body_color, 0.040)
	_left_upper_arm = _make_segment("LeftUpperArm", 0.044, body_color)
	_left_lower_arm = _make_segment("LeftLowerArm", 0.039, body_color)
	_right_upper_arm = _make_segment("RightUpperArm", 0.044, body_color)
	_right_lower_arm = _make_segment("RightLowerArm", 0.039, body_color)

	_left_foot = _make_foot("LeftFoot", LEFT_FOOT_REST, foot_color)
	_right_foot = _make_foot("RightFoot", RIGHT_FOOT_REST, foot_color)
	_left_knee = _make_joint("LeftKnee", Vector3(-0.065, 0.19, -0.04), leg_color, 0.029)
	_right_knee = _make_joint("RightKnee", Vector3(0.065, 0.19, -0.04), leg_color, 0.029)
	_left_thigh = _make_segment("LeftThigh", 0.030, leg_color)
	_left_shin = _make_segment("LeftShin", 0.027, leg_color)
	_right_thigh = _make_segment("RightThigh", 0.030, leg_color)
	_right_shin = _make_segment("RightShin", 0.027, leg_color)

	_place_limb_segments()
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	if _controller != null:
		_was_on_floor = _controller.is_on_floor()
	reset_physics_interpolation()


func foot_world_positions() -> Array[Vector3]:
	if _left_foot == null or _right_foot == null:
		return []
	return [
		_left_foot.to_global(Vector3(0.0, -0.043, -0.010)),
		_right_foot.to_global(Vector3(0.0, -0.043, -0.010)),
	]


func _physics_process(delta: float) -> void:
	if not visible or _body_root == null:
		return
	if _controller == null:
		_controller = get_parent().get_parent() as CharacterBody3D
	if _controller == null:
		return
	delta = minf(delta, 1.0 / 30.0)
	var local_velocity := global_basis.inverse() * _controller.velocity
	var horizontal_speed := Vector2(local_velocity.x, local_velocity.z).length()
	var movement_amount := clampf(horizontal_speed / 2.2, 0.0, 1.45)
	var on_floor := _controller.is_on_floor()
	var local_acceleration := (
		(local_velocity - _previous_local_velocity) / maxf(delta, 0.001)
	)
	_previous_local_velocity = local_velocity
	_idle_time += delta
	_gait_phase = fposmod(_gait_phase + horizontal_speed * delta * 6.2, TAU)

	if not _was_on_floor and on_floor:
		var impact := clampf(-local_velocity.y / 7.0, 0.0, 1.0)
		_landing_squash = maxf(_landing_squash, impact)
		_body_velocity.y -= impact * 1.05
		_head_velocity.y += impact * 0.28
		_backpack_velocity += Vector3(0.0, impact * 0.38, 0.04 * impact)
	elif _was_on_floor and not on_floor and local_velocity.y > 0.0:
		_body_velocity.y -= clampf(local_velocity.y * 0.05, 0.0, 0.28)
		_head_velocity.y -= clampf(local_velocity.y * 0.025, 0.0, 0.14)
		_backpack_velocity.y -= clampf(local_velocity.y * 0.035, 0.0, 0.18)
	_was_on_floor = on_floor
	_landing_squash = move_toward(_landing_squash, 0.0, delta * 4.5)

	var idle_enough := on_floor and horizontal_speed < 0.09
	var wave_cycle := fposmod(_idle_time, 9.0)
	var wants_wave := idle_enough and wave_cycle > 5.8 and wave_cycle < 7.9
	_wave_strength = move_toward(
		_wave_strength, 1.0 if wants_wave else 0.0, delta * 3.2
	)

	_update_torso(delta, local_velocity, local_acceleration, movement_amount, on_floor)
	_update_head_and_backpack(delta, local_velocity, local_acceleration, movement_amount)
	_update_feet(delta, horizontal_speed, movement_amount, on_floor)
	_update_legs(delta)
	_update_arms(
		delta,
		local_velocity,
		local_acceleration,
		movement_amount,
		on_floor,
		wave_cycle
	)
	_place_limb_segments()


func _update_torso(
	delta: float,
	local_velocity: Vector3,
	local_acceleration: Vector3,
	movement_amount: float,
	on_floor: bool
) -> void:
	var idle_amount := (
		1.0 - clampf(movement_amount * 2.0, 0.0, 1.0)
	) if on_floor else 0.0
	var stride := sin(_gait_phase)
	var contact_wave := -cos(_gait_phase * 2.0)
	var run_bounce := (
		absf(stride) * 0.045 * movement_amount
		if on_floor else 0.0
	)
	var breathing := sin(_idle_time * 2.0)
	var target_position := BODY_REST + Vector3(
		stride * 0.022 * movement_amount,
		run_bounce + breathing * 0.009 * idle_amount,
		clampf(local_acceleration.z * 0.0012, -0.035, 0.035)
	)
	_body_velocity = _spring_vector(
		_body_root, target_position, _body_velocity, 68.0, 7.0, delta
	)
	var target_rotation := Vector3(
		clampf(
			local_velocity.z * 0.075 + local_acceleration.z * 0.0022,
			-0.34,
			0.34
		),
		stride * 0.075 * movement_amount + sin(_idle_time * 0.7) * 0.025 * idle_amount,
		clampf(
			-local_velocity.x * 0.07
			- local_acceleration.x * 0.002
			- stride * 0.11 * movement_amount,
			-0.34,
			0.34
		)
	)
	_body_rotation_velocity = _spring_rotation(
		_body_root, target_rotation, _body_rotation_velocity, 58.0, 6.5, delta
	)
	var airborne_stretch := (
		clampf(local_velocity.y * 0.025, -0.08, 0.12) if not on_floor else 0.0
	)
	var stride_stretch := contact_wave * 0.045 * movement_amount if on_floor else 0.0
	var target_scale := Vector3(
		1.0 + _landing_squash * 0.15 - airborne_stretch * 0.3 - stride_stretch * 0.38,
		1.0 - _landing_squash * 0.19 + airborne_stretch + stride_stretch,
		1.0 + _landing_squash * 0.15 - airborne_stretch * 0.3 - stride_stretch * 0.38
	)
	_body_scale_velocity = _spring_scale(
		_body_root, target_scale, _body_scale_velocity, 78.0, 8.0, delta
	)


func _update_head_and_backpack(
	delta: float,
	local_velocity: Vector3,
	local_acceleration: Vector3,
	movement_amount: float
) -> void:
	var body_basis := Basis.from_euler(_body_root.rotation)
	var head_target := (
		_body_root.position
		+ body_basis * Vector3(0.0, 0.215, -0.005)
		+ Vector3(
			clampf(-local_acceleration.x * 0.0010, -0.025, 0.025),
			0.0,
			clampf(-local_acceleration.z * 0.0010, -0.025, 0.025)
		)
	)
	_head_velocity = _spring_vector(
		_head_root, head_target, _head_velocity, 45.0, 6.2, delta
	)
	var head_rotation_target := Vector3(
		_body_root.rotation.x * 0.46,
		_body_root.rotation.y * 0.35 - sin(_gait_phase) * 0.035 * movement_amount,
		_body_root.rotation.z * 0.42
	)
	_head_rotation_velocity = _spring_rotation(
		_head_root,
		head_rotation_target,
		_head_rotation_velocity,
		34.0,
		5.6,
		delta
	)

	var backpack_target := (
		_body_root.position
		+ body_basis * Vector3(0.0, 0.055, 0.145)
		+ Vector3(0.0, 0.0, clampf(-local_acceleration.z * 0.0012, -0.03, 0.03))
	)
	_backpack_velocity = _spring_vector(
		_backpack_root,
		backpack_target,
		_backpack_velocity,
		36.0,
		5.4,
		delta
	)
	var backpack_rotation_target := Vector3(
		_body_root.rotation.x * 0.82 - local_velocity.z * 0.015,
		_body_root.rotation.y * 0.75,
		_body_root.rotation.z * 0.78
	)
	_backpack_rotation_velocity = _spring_rotation(
		_backpack_root,
		backpack_rotation_target,
		_backpack_rotation_velocity,
		31.0,
		5.0,
		delta
	)


func _update_feet(
	delta: float, horizontal_speed: float, movement_amount: float, on_floor: bool
) -> void:
	if not on_floor:
		var fall_tuck := clampf(-_controller.velocity.y * 0.018, -0.04, 0.07)
		_left_foot_velocity = _spring_vector(
			_left_foot,
			Vector3(-0.085, 0.13 + fall_tuck, 0.025),
			_left_foot_velocity,
			82.0,
			9.0,
			delta
		)
		_right_foot_velocity = _spring_vector(
			_right_foot,
			Vector3(0.085, 0.13 + fall_tuck, 0.025),
			_right_foot_velocity,
			82.0,
			9.0,
			delta
		)
		_update_foot_scales(
			delta,
			Vector3(0.90, 1.14, 0.90),
			Vector3(0.90, 1.14, 0.90)
		)
		return
	# Reference-matched loop: a foot lifts only while travelling forward, lands
	# at full reach, and pushes backward along the ground. The opposite foot is
	# exactly half a cycle away. This reads clearly at any controller speed and
	# cannot accumulate behind the player like the old world-space plants did.
	var gait_strength := clampf(movement_amount, 0.0, 1.25)
	var stride_length := 0.115 * gait_strength
	var left_phase := _gait_phase
	var right_phase := _gait_phase + PI
	var left_forward := sin(left_phase)
	var right_forward := sin(right_phase)
	var left_lift := maxf(0.0, cos(left_phase)) * 0.09 * gait_strength
	var right_lift := maxf(0.0, cos(right_phase)) * 0.09 * gait_strength
	var left_target := LEFT_FOOT_REST + Vector3(
		0.0, left_lift, -left_forward * stride_length
	)
	var right_target := RIGHT_FOOT_REST + Vector3(
		0.0, right_lift, -right_forward * stride_length
	)
	if horizontal_speed < 0.06:
		left_target = LEFT_FOOT_REST
		right_target = RIGHT_FOOT_REST
	_left_foot_velocity = _spring_vector(
		_left_foot, left_target, _left_foot_velocity, 190.0, 18.0, delta
	)
	_right_foot_velocity = _spring_vector(
		_right_foot, right_target, _right_foot_velocity, 190.0, 18.0, delta
	)
	var left_scale := Vector3(0.94, 1.10, 0.94) if left_lift > 0.01 else Vector3(1.06, 0.92, 1.06)
	var right_scale := Vector3(0.94, 1.10, 0.94) if right_lift > 0.01 else Vector3(1.06, 0.92, 1.06)
	_update_foot_scales(delta, left_scale, right_scale)
	_left_foot_rotation_velocity = _spring_rotation(
		_left_foot,
		Vector3(left_forward * 0.24, 0.0, 0.0),
		_left_foot_rotation_velocity,
		90.0,
		12.0,
		delta
	)
	_right_foot_rotation_velocity = _spring_rotation(
		_right_foot,
		Vector3(right_forward * 0.24, 0.0, 0.0),
		_right_foot_rotation_velocity,
		90.0,
		12.0,
		delta
	)


func _update_legs(delta: float) -> void:
	var body_basis := Basis.from_euler(_body_root.rotation)
	var left_hip := _body_root.position + body_basis * Vector3(-0.055, -0.105, 0.0)
	var right_hip := _body_root.position + body_basis * Vector3(0.055, -0.105, 0.0)
	var forward_hint := body_basis * Vector3(0.0, 0.0, -1.0)
	var left_knee_target := _two_bone_joint(
		left_hip,
		_left_foot.position,
		UPPER_LEG_LENGTH,
		LOWER_LEG_LENGTH,
		(forward_hint + body_basis * Vector3(-0.18, 0.0, 0.0)).normalized()
	)
	var right_knee_target := _two_bone_joint(
		right_hip,
		_right_foot.position,
		UPPER_LEG_LENGTH,
		LOWER_LEG_LENGTH,
		(forward_hint + body_basis * Vector3(0.18, 0.0, 0.0)).normalized()
	)
	_left_knee_velocity = _spring_vector(
		_left_knee, left_knee_target, _left_knee_velocity, 125.0, 13.0, delta
	)
	_right_knee_velocity = _spring_vector(
		_right_knee, right_knee_target, _right_knee_velocity, 125.0, 13.0, delta
	)


func _update_arms(
	delta: float,
	local_velocity: Vector3,
	local_acceleration: Vector3,
	movement_amount: float,
	on_floor: bool,
	wave_cycle: float
) -> void:
	var body_basis := Basis.from_euler(_body_root.rotation)
	var left_shoulder := _body_root.position + body_basis * Vector3(-0.115, 0.065, 0.0)
	var right_shoulder := _body_root.position + body_basis * Vector3(0.115, 0.065, 0.0)
	var stride := sin(_gait_phase)
	var idle_amount := (
		1.0 - clampf(movement_amount * 2.0, 0.0, 1.0)
	) if on_floor else 0.0
	var inertia := Vector3(
		clampf(-local_acceleration.x * 0.0008, -0.018, 0.018),
		0.0,
		clampf(-local_acceleration.z * 0.0008, -0.018, 0.018)
	)
	var left_target := Vector3(
		-0.105 - 0.014 * movement_amount,
		0.42 - stride * 0.035 * movement_amount,
		-0.14 + stride * 0.08 * movement_amount
	) + inertia
	var right_target := Vector3(
		0.105 + 0.014 * movement_amount,
		0.42 + stride * 0.035 * movement_amount,
		-0.14 - stride * 0.08 * movement_amount
	) + inertia
	left_target += Vector3(
		-sin(_idle_time * 1.25) * 0.012,
		sin(_idle_time * 1.8) * 0.016,
		cos(_idle_time * 1.35) * 0.01
	) * idle_amount
	right_target += Vector3(
		sin(_idle_time * 1.15 + 0.8) * 0.012,
		sin(_idle_time * 1.7 + 1.0) * 0.016,
		cos(_idle_time * 1.3 + 0.6) * 0.01
	) * idle_amount
	if not on_floor:
		left_target += Vector3(-0.04, 0.09, 0.04)
		right_target += Vector3(0.04, 0.09, 0.04)
	if _wave_strength > 0.0:
		var wave_phase := (wave_cycle - 5.8) * TAU * 1.6
		var wave_target := Vector3(
			0.22 + sin(wave_phase) * 0.022,
			0.62 + cos(wave_phase * 0.5) * 0.012,
			-0.035
		)
		right_target = right_target.lerp(wave_target, _wave_strength)

	_left_hand_velocity = _spring_vector(
		_left_hand, left_target, _left_hand_velocity, 62.0, 7.0, delta
	)
	_right_hand_velocity = _spring_vector(
		_right_hand, right_target, _right_hand_velocity, 62.0, 7.0, delta
	)
	var left_elbow_target := _two_bone_joint(
		left_shoulder,
		_left_hand.position,
		UPPER_ARM_LENGTH,
		LOWER_ARM_LENGTH,
		(body_basis * Vector3(-0.75, -0.15, -1.0)).normalized()
	)
	var right_elbow_target := _two_bone_joint(
		right_shoulder,
		_right_hand.position,
		UPPER_ARM_LENGTH,
		LOWER_ARM_LENGTH,
		(body_basis * Vector3(0.75, -0.15, -1.0)).normalized()
	)
	_left_elbow_velocity = _spring_vector(
		_left_elbow, left_elbow_target, _left_elbow_velocity, 96.0, 10.0, delta
	)
	_right_elbow_velocity = _spring_vector(
		_right_elbow, right_elbow_target, _right_elbow_velocity, 96.0, 10.0, delta
	)


func _place_limb_segments() -> void:
	if _body_root == null:
		return
	var body_basis := Basis.from_euler(_body_root.rotation)
	var left_shoulder := _body_root.position + body_basis * Vector3(-0.115, 0.065, 0.0)
	var right_shoulder := _body_root.position + body_basis * Vector3(0.115, 0.065, 0.0)
	var left_hip := _body_root.position + body_basis * Vector3(-0.055, -0.105, 0.0)
	var right_hip := _body_root.position + body_basis * Vector3(0.055, -0.105, 0.0)
	_place_segment(_left_upper_arm, left_shoulder, _left_elbow.position)
	_place_segment(_left_lower_arm, _left_elbow.position, _left_hand.position)
	_place_segment(_right_upper_arm, right_shoulder, _right_elbow.position)
	_place_segment(_right_lower_arm, _right_elbow.position, _right_hand.position)
	_place_segment(_left_thigh, left_hip, _left_knee.position)
	_place_segment(_left_shin, _left_knee.position, _left_foot.position)
	_place_segment(_right_thigh, right_hip, _right_knee.position)
	_place_segment(_right_shin, _right_knee.position, _right_foot.position)


func _two_bone_joint(
	start: Vector3,
	end: Vector3,
	upper_length: float,
	lower_length: float,
	bend_hint: Vector3
) -> Vector3:
	var to_end := end - start
	var distance := clampf(
		to_end.length(), 0.001, upper_length + lower_length - 0.001
	)
	var direction := to_end.normalized() if to_end.length_squared() > 0.000001 else Vector3.DOWN
	var along := (
		upper_length * upper_length
		- lower_length * lower_length
		+ distance * distance
	) / (2.0 * distance)
	var height := sqrt(maxf(upper_length * upper_length - along * along, 0.0))
	var bend := bend_hint - direction * bend_hint.dot(direction)
	if bend.length_squared() < 0.0001:
		bend = direction.cross(Vector3.RIGHT)
		if bend.length_squared() < 0.0001:
			bend = direction.cross(Vector3.FORWARD)
	return start + direction * along + bend.normalized() * height


func _make_joint(
	node_name: String, position: Vector3, color: Color, radius: float
) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = position
	add_child(root)
	_add_sphere(root, "Shape", Vector3.ZERO, Vector3.ONE * radius, color)
	return root


func _make_foot(node_name: String, position: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = position
	add_child(root)
	_add_sphere(
		root, "RoundedBoot", Vector3(0.0, 0.0, -0.018),
		Vector3(0.058, 0.043, 0.072), color
	)
	return root


func _make_segment(
	node_name: String, radius: float, color: Color
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 16
	var segment := MeshInstance3D.new()
	segment.name = node_name
	segment.mesh = mesh
	segment.material_override = _material(color)
	segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(segment)
	return segment


func _place_segment(
	segment: MeshInstance3D, start: Vector3, finish: Vector3
) -> void:
	var difference := finish - start
	var length := maxf(difference.length(), 0.001)
	segment.position = (start + finish) * 0.5
	segment.quaternion = Quaternion(Vector3.UP, difference / length)
	segment.scale = Vector3(1.0, length, 1.0)


func _add_sphere(
	parent: Node3D,
	node_name: String,
	position: Vector3,
	scale_value: Vector3,
	color: Color
) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.scale = scale_value
	instance.material_override = _material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	return instance


func _add_capsule(
	parent: Node3D,
	node_name: String,
	position: Vector3,
	scale_value: Vector3,
	color: Color
) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 8
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.scale = scale_value
	instance.material_override = _material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	return material


func _update_foot_scales(
	delta: float, left_scale: Vector3, right_scale: Vector3
) -> void:
	_left_foot_scale_velocity = _spring_scale(
		_left_foot,
		left_scale,
		_left_foot_scale_velocity,
		78.0,
		9.0,
		delta
	)
	_right_foot_scale_velocity = _spring_scale(
		_right_foot,
		right_scale,
		_right_foot_scale_velocity,
		78.0,
		9.0,
		delta
	)


func _spring_vector(
	node: Node3D,
	target: Vector3,
	current_velocity: Vector3,
	stiffness: float,
	damping: float,
	delta: float
) -> Vector3:
	current_velocity += (
		(target - node.position) * stiffness - current_velocity * damping
	) * delta
	node.position += current_velocity * delta
	return current_velocity


func _spring_rotation(
	node: Node3D,
	target: Vector3,
	current_velocity: Vector3,
	stiffness: float,
	damping: float,
	delta: float
) -> Vector3:
	current_velocity += (
		(target - node.rotation) * stiffness - current_velocity * damping
	) * delta
	node.rotation += current_velocity * delta
	return current_velocity


func _spring_scale(
	node: Node3D,
	target: Vector3,
	current_velocity: Vector3,
	stiffness: float,
	damping: float,
	delta: float
) -> Vector3:
	current_velocity += (
		(target - node.scale) * stiffness - current_velocity * damping
	) * delta
	node.scale += current_velocity * delta
	return current_velocity
