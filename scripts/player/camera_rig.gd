class_name CameraRig
extends Node3D
## Narrow-perspective diorama camera with quarter-turn yaw, a 40° pitch,
## smooth follow, and bounded zoom. _size_target remains the visible vertical
## span so saves and input tests stay projection-independent; it is converted
## to the matching camera distance for the 15° lens.

var core: GameCore
var target: Node3D
var camera: Camera3D

var _yaw := 45.0
var _yaw_target := 45.0
var _size_target := 8.8
var _pitch_node: Node3D
var _rotating := false


func setup(game_core: GameCore, follow_target: Node3D) -> void:
	core = game_core
	target = follow_target
	_yaw = core.registries.tunef("camera_default_yaw_deg", 45.0)
	_yaw_target = _yaw
	_size_target = core.registries.tunef("camera_default_size", 8.8)
	rotation_degrees.y = _yaw

	_pitch_node = Node3D.new()
	_pitch_node.name = "Pitch"
	add_child(_pitch_node)
	_pitch_node.rotation_degrees.x = core.registries.tunef("camera_pitch_deg", -34.0)

	camera = Camera3D.new()
	camera.name = "ReferencePerspectiveCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = core.registries.tunef("camera_fov_deg", 15.0)
	camera.position = Vector3(0, 0, _distance_for_size(_size_target))
	camera.near = 5.0
	camera.far = 100.0
	_pitch_node.add_child(camera)
	camera.current = true


func _process(delta: float) -> void:
	if target != null:
		var goal := target.global_position
		global_position = global_position.lerp(goal, minf(1.0, core.registries.tunef("camera_follow_speed", 4.5) * delta))
	rotation_degrees.y = lerp_angle(deg_to_rad(rotation_degrees.y), deg_to_rad(_yaw_target), minf(1.0, 10.0 * delta)) * 180.0 / PI
	camera.position.z = lerpf(camera.position.z, _distance_for_size(_size_target), minf(1.0, 8.0 * delta))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_rotate_left"):
		_yaw_target += 90.0
	elif event.is_action_pressed("camera_rotate_right"):
		_yaw_target -= 90.0
	elif event.is_action_pressed("camera_zoom_in"):
		_zoom_by(-core.registries.tunef("camera_wheel_zoom_step", 1.0))
	elif event.is_action_pressed("camera_zoom_out"):
		_zoom_by(core.registries.tunef("camera_wheel_zoom_step", 1.0))
	elif event is InputEventMouseButton and event.pressed:
		var wheel := event as InputEventMouseButton
		var wheel_amount := maxf(0.1, wheel.factor)
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(-core.registries.tunef("camera_wheel_zoom_step", 1.0) * wheel_amount)
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(core.registries.tunef("camera_wheel_zoom_step", 1.0) * wheel_amount)
	elif event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		_zoom_by((1.0 - magnify.factor) * core.registries.tunef("camera_pinch_zoom_speed", 6.0))
	elif event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		# Vertical two-finger travel zooms; horizontal travel is left untouched
		# so diagonal trackpad gestures do not cause surprising scale changes.
		if absf(pan.delta.y) > absf(pan.delta.x):
			_zoom_by(pan.delta.y * core.registries.tunef("camera_trackpad_zoom_speed", 0.28))


func _zoom_by(amount: float) -> void:
	_size_target = clampf(
		_size_target + amount,
		core.registries.tunef("camera_min_size", 6.0),
		core.registries.tunef("camera_max_size", 28.0)
	)


func set_zoom_immediate(framing_size: float) -> void:
	_size_target = framing_size
	if camera != null:
		camera.position.z = _distance_for_size(_size_target)


func _distance_for_size(framing_size: float) -> float:
	var fov := camera.fov if camera != null else core.registries.tunef("camera_fov_deg", 15.0)
	return framing_size / (2.0 * tan(deg_to_rad(fov * 0.5)))


## Camera-relative movement basis projected to the ground plane.
func horizontal_basis() -> Basis:
	var yaw_rad := deg_to_rad(rotation_degrees.y)
	var forward := Vector3(-sin(yaw_rad), 0, -cos(yaw_rad))
	var right := Vector3(cos(yaw_rad), 0, -sin(yaw_rad))
	return Basis(right, Vector3.UP, -forward)


func set_build_mode(enabled: bool) -> void:
	var base := core.registries.tunef("camera_default_size", 8.8)
	_size_target = base + (core.registries.tunef("build_mode_size_bonus", 3.2) if enabled else 0.0)


func zoom_for_creator() -> void:
	_size_target = 6.0


func restore_gameplay_zoom() -> void:
	_size_target = core.registries.tunef("camera_default_size", 8.8)


func save_state() -> Dictionary:
	return {"yaw": _yaw_target, "size": _size_target}


func restore_state(data: Dictionary) -> void:
	_yaw_target = float(data.get("yaw", 45.0))
	rotation_degrees.y = _yaw_target
	_size_target = clampf(
		float(data.get("size", core.registries.tunef("camera_default_size", 10.5))),
		core.registries.tunef("camera_min_size", 7.5),
		core.registries.tunef("camera_max_size", 18.5)
	)
	set_zoom_immediate(_size_target)
