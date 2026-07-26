class_name CameraRig
extends Node3D
## Narrow-perspective diorama camera with the confirmed 15° lens, 40–70 unit
## distance range, five-unit zoom steps, and quarter-turn orbit. _size_target
## retains its historical name but now stores literal camera distance.

signal orbit_started(target_yaw: float)
signal orbit_finished(yaw: float)
signal zoom_changed(distance: float)

var core: GameCore
var target: Node3D
var camera: Camera3D

var _yaw := 45.0
var _yaw_target := 45.0
var _size_target := 40.0
var _pitch_node: Node3D
var _rotating := false


func setup(game_core: GameCore, follow_target: Node3D) -> void:
	core = game_core
	target = follow_target
	_yaw = core.registries.tunef("camera_default_yaw_deg", 45.0)
	_yaw_target = _yaw
	_size_target = core.registries.tunef("camera_default_size", 40.0)
	rotation_degrees.y = _yaw

	_pitch_node = Node3D.new()
	_pitch_node.name = "Pitch"
	add_child(_pitch_node)
	_pitch_node.rotation_degrees.x = core.registries.tunef("camera_pitch_deg", -34.0)

	camera = Camera3D.new()
	camera.name = "ReferencePerspectiveCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = core.registries.tunef("camera_fov_deg", 15.0)
	camera.position = Vector3(0, 0, _size_target)
	camera.near = 5.0
	camera.far = 100.0
	_pitch_node.add_child(camera)
	camera.current = true


func _process(delta: float) -> void:
	if target != null:
		var goal := target.global_position
		global_position = global_position.lerp(goal, minf(1.0, core.registries.tunef("camera_follow_speed", 4.5) * delta))
	var yaw_difference := absf(angle_difference(rotation.y, deg_to_rad(_yaw_target)))
	if yaw_difference > deg_to_rad(0.25) and not _rotating:
		_rotating = true
		orbit_started.emit(_yaw_target)
	rotation.y = rotate_toward(
		rotation.y,
		deg_to_rad(_yaw_target),
		deg_to_rad(core.registries.tunef("camera_rotate_speed_deg", 360.0)) * delta
	)
	camera.position.z = lerpf(camera.position.z, _size_target, minf(1.0, 8.0 * delta))
	if _rotating and absf(angle_difference(rotation.y, deg_to_rad(_yaw_target))) <= deg_to_rad(0.25):
		rotation_degrees.y = _yaw_target
		_rotating = false
		orbit_finished.emit(_yaw_target)
	core.view_state = save_state()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_rotate_left"):
		_yaw_target += 90.0
		core.autosave_soon()
	elif event.is_action_pressed("camera_rotate_right"):
		_yaw_target -= 90.0
		core.autosave_soon()
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
	core.autosave_soon()
	zoom_changed.emit(_size_target)


func set_zoom_immediate(framing_size: float) -> void:
	_size_target = clampf(
		framing_size,
		core.registries.tunef("camera_min_size", 40.0),
		core.registries.tunef("camera_max_size", 70.0)
	)
	if camera != null:
		camera.position.z = _size_target
	core.view_state = save_state()
	zoom_changed.emit(_size_target)


## Camera-relative movement basis projected to the ground plane.
func horizontal_basis() -> Basis:
	var yaw_rad := deg_to_rad(rotation_degrees.y)
	var forward := Vector3(-sin(yaw_rad), 0, -cos(yaw_rad))
	var right := Vector3(cos(yaw_rad), 0, -sin(yaw_rad))
	return Basis(right, Vector3.UP, -forward)


func set_build_mode(enabled: bool) -> void:
	var base := core.registries.tunef("camera_default_size", 40.0)
	_size_target = base + (core.registries.tunef("build_mode_size_bonus", 5.0) if enabled else 0.0)
	zoom_changed.emit(_size_target)


func zoom_for_creator() -> void:
	# Creator framing intentionally sits inside the gameplay distance bounds.
	_size_target = 24.0
	zoom_changed.emit(_size_target)


func restore_gameplay_zoom() -> void:
	_size_target = core.registries.tunef("camera_default_size", 40.0)
	zoom_changed.emit(_size_target)


func zoom_distance() -> float:
	return _size_target


func save_state() -> Dictionary:
	return {"yaw": _yaw_target, "distance": _size_target}


## Machine-readable description of the live camera and its control envelope.
## Kept on the rig so diagnostics report instantiated values rather than merely
## repeating configuration files.
func runtime_manifest() -> Dictionary:
	return {
		"projection": "perspective" if camera.projection == Camera3D.PROJECTION_PERSPECTIVE else "other",
		"fov_degrees": camera.fov,
		"near_clip": camera.near,
		"far_clip": camera.far,
		"pitch_degrees": _pitch_node.rotation_degrees.x,
		"yaw_degrees": rotation_degrees.y,
		"target_yaw_degrees": _yaw_target,
		"distance": camera.position.z,
		"target_distance": _size_target,
		"zoom_limits": {
			"minimum": core.registries.tunef("camera_min_size", 40.0),
			"maximum": core.registries.tunef("camera_max_size", 70.0),
			"wheel_step": core.registries.tunef("camera_wheel_zoom_step", 5.0),
			"trackpad_speed": core.registries.tunef("camera_trackpad_zoom_speed", 1.4),
			"pinch_speed": core.registries.tunef("camera_pinch_zoom_speed", 25.0),
			"build_mode_bonus": core.registries.tunef("build_mode_size_bonus", 5.0),
		},
		"motion": {
			"follow_damping_per_second": core.registries.tunef("camera_follow_speed", 10.0),
			"orbit_speed_degrees_per_second": core.registries.tunef("camera_rotate_speed_deg", 360.0),
			"orbit_step_degrees": 90.0,
			"settle_epsilon_degrees": 0.25,
		},
	}


func restore_state(data: Dictionary) -> void:
	_yaw_target = float(data.get("yaw", 45.0))
	rotation_degrees.y = _yaw_target
	var stored_distance := float(data.get("distance", data.get("size", core.registries.tunef("camera_default_size", 40.0))))
	# Migrate experimental saves that stored an orthographic-equivalent span.
	if not data.has("distance") and stored_distance < 25.0:
		stored_distance /= 2.0 * tan(deg_to_rad(core.registries.tunef("camera_fov_deg", 15.0) * 0.5))
	_size_target = clampf(
		stored_distance,
		core.registries.tunef("camera_min_size", 40.0),
		core.registries.tunef("camera_max_size", 70.0)
	)
	set_zoom_immediate(_size_target)
