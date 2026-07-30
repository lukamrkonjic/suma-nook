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
var _size_target := 32.0
var _pitch_node: Node3D
var _rotating := false
var _pan_offset := Vector3.ZERO
var _middle_panning := false
var _creator_focus := false


func setup(game_core: GameCore, follow_target: Node3D) -> void:
	core = game_core
	target = follow_target
	# The camera already owns render-frame damping in _process(). Keep it out of
	# the physics interpolation system so zoom/orbit writes do not double-filter
	# or trigger interpolation warnings.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_yaw = core.registries.tunef("camera_default_yaw_deg", 45.0)
	_yaw_target = _yaw
	_size_target = core.registries.tunef("camera_default_size", 32.0)
	rotation_degrees.y = _yaw

	_pitch_node = Node3D.new()
	_pitch_node.name = "Pitch"
	_pitch_node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_pitch_node)
	_pitch_node.rotation_degrees.x = core.registries.tunef("camera_pitch_deg", -34.0)

	camera = Camera3D.new()
	camera.name = "ReferencePerspectiveCamera"
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = core.registries.tunef("camera_fov_deg", 15.0)
	camera.position = Vector3(0, 0, _size_target)
	camera.near = 5.0
	camera.far = 90.0
	_pitch_node.add_child(camera)
	camera.current = true


func _process(delta: float) -> void:
	if target != null:
		var goal := core.world_envelope.clamp_world_position(
			target.global_position + _pan_offset,
			core.world_envelope.camera_inset_cells()
		)
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


## Mouse releases can be consumed by UI controls before reaching
## _unhandled_input. Observe an active middle-drag release here as a safety net
## so the camera can never remain stranded away from the player.
func _input(event: InputEvent) -> void:
	if (
		_middle_panning
		and event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE
		and not (event as InputEventMouseButton).pressed
	):
		_middle_panning = false
		reset_pan()


func _unhandled_input(event: InputEvent) -> void:
	if _creator_focus:
		return
	var controller := target as PlayerController
	if (
		event is InputEventJoypadButton
		or event is InputEventJoypadMotion
	):
		if get_viewport().gui_get_focus_owner() != null:
			return
		if (
			controller != null
			and controller.state == PlayerController.State.BUILDING
		):
			# Triggers and shoulders are context actions while constructing.
			return
	if (
		controller != null
		and controller.state == PlayerController.State.BUILDING
		and event.is_action_pressed("store_piece")
	):
		# X is camera-right during exploration and store while constructing.
		return
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
	elif event is InputEventMouseButton:
		var wheel := event as InputEventMouseButton
		if wheel.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_panning = wheel.pressed
			if not wheel.pressed:
				reset_pan()
			get_viewport().set_input_as_handled()
		elif wheel.pressed:
			var wheel_amount := maxf(0.1, wheel.factor)
			if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_by(-core.registries.tunef("camera_wheel_zoom_step", 1.0) * wheel_amount)
			elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_by(core.registries.tunef("camera_wheel_zoom_step", 1.0) * wheel_amount)
	elif event is InputEventMouseMotion and _middle_panning:
		_pan_by_pixels((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		_zoom_by((1.0 - magnify.factor) * core.registries.tunef("camera_pinch_zoom_speed", 6.0))
	elif event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		# Vertical two-finger travel zooms; horizontal travel is left untouched
		# so diagonal trackpad gestures do not cause surprising scale changes.
		if absf(pan.delta.y) > absf(pan.delta.x):
			_zoom_by(pan.delta.y * core.registries.tunef("camera_trackpad_zoom_speed", 0.28))


func _pan_by_pixels(relative: Vector2) -> void:
	var basis := horizontal_basis()
	var world_per_pixel := _size_target * 0.0008
	_pan_offset += (
		basis.x * relative.x * world_per_pixel
		- basis.z * relative.y * world_per_pixel
	)
	_pan_offset.y = 0.0
	if _pan_offset.length() > 30.0:
		_pan_offset = _pan_offset.normalized() * 30.0
	if target != null:
		var clamped_focus := core.world_envelope.clamp_world_position(
			target.global_position + _pan_offset,
			core.world_envelope.camera_inset_cells()
		)
		_pan_offset = clamped_focus - target.global_position
		_pan_offset.y = 0.0


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
		core.registries.tunef("camera_min_size", 14.0),
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
	var base := core.registries.tunef("camera_default_size", 32.0)
	_size_target = base + (core.registries.tunef("build_mode_size_bonus", 3.0) if enabled else 0.0)
	zoom_changed.emit(_size_target)


func zoom_for_creator() -> void:
	# Character creation is a portrait view, not a gameplay establishing shot.
	# Keep it independent of gameplay's minimum distance so the live model is
	# large enough to judge the face, hair, and palette changes. The portrait
	# offset centers the model in the open canvas to the right of the form.
	_creator_focus = true
	_pan_offset = Vector3.ZERO
	_size_target = 8.0
	if _pitch_node != null:
		_pitch_node.rotation_degrees.x = -42.0
	if camera != null:
		camera.position = Vector3(-0.48, 0.42, _size_target)
	zoom_changed.emit(_size_target)


## A close, locked establishing frame for the portal rise and first-land
## choice. It keeps the arrival legible without exposing normal camera input.
func frame_for_arrival() -> void:
	_creator_focus = true
	_pan_offset = Vector3.ZERO
	_size_target = 18.0
	if _pitch_node != null:
		_pitch_node.rotation_degrees.x = -38.0
	if camera != null:
		camera.position = Vector3(0.0, 0.15, _size_target)
	zoom_changed.emit(_size_target)


func restore_gameplay_zoom() -> void:
	_creator_focus = false
	_size_target = core.registries.tunef("camera_default_size", 32.0)
	if _pitch_node != null:
		_pitch_node.rotation_degrees.x = core.registries.tunef(
			"camera_pitch_deg",
			-34.0
		)
	if camera != null:
		camera.position.x = 0.0
		camera.position.y = 0.0
	zoom_changed.emit(_size_target)


func zoom_distance() -> float:
	return _size_target


func save_state() -> Dictionary:
	return {
		"yaw": _yaw_target,
		"distance": _size_target,
		# Middle-drag is a temporary look gesture and is never persisted.
		"pan": [0.0, 0.0],
	}


func reset_pan() -> void:
	_pan_offset = Vector3.ZERO
	core.autosave_soon()


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
			"minimum": core.registries.tunef("camera_min_size", 14.0),
			"maximum": core.registries.tunef("camera_max_size", 70.0),
			"wheel_step": core.registries.tunef("camera_wheel_zoom_step", 5.0),
			"trackpad_speed": core.registries.tunef("camera_trackpad_zoom_speed", 1.4),
			"pinch_speed": core.registries.tunef("camera_pinch_zoom_speed", 25.0),
			"build_mode_bonus": core.registries.tunef("build_mode_size_bonus", 3.0),
		},
		"motion": {
			"follow_damping_per_second": core.registries.tunef("camera_follow_speed", 10.0),
			"orbit_speed_degrees_per_second": core.registries.tunef("camera_rotate_speed_deg", 360.0),
			"orbit_step_degrees": 90.0,
			"settle_epsilon_degrees": 0.25,
		},
		"world_envelope": core.world_envelope.runtime_manifest(),
	}


func restore_state(data: Dictionary) -> void:
	_creator_focus = false
	if _pitch_node != null:
		_pitch_node.rotation_degrees.x = core.registries.tunef(
			"camera_pitch_deg",
			-34.0
		)
	if camera != null:
		camera.position.x = 0.0
		camera.position.y = 0.0
	_yaw_target = float(data.get("yaw", 45.0))
	rotation_degrees.y = _yaw_target
	var stored_distance := float(data.get("distance", data.get("size", core.registries.tunef("camera_default_size", 32.0))))
	# Migrate experimental saves that stored an orthographic-equivalent span.
	if not data.has("distance") and stored_distance < 25.0:
		stored_distance /= 2.0 * tan(deg_to_rad(core.registries.tunef("camera_fov_deg", 15.0) * 0.5))
	_size_target = clampf(
		stored_distance,
		core.registries.tunef("camera_min_size", 14.0),
		core.registries.tunef("camera_max_size", 70.0)
	)
	# Discard legacy persistent framing offsets. Middle-drag now returns to the
	# player on release and must not reopen a save looking away from them.
	_pan_offset = Vector3.ZERO
	set_zoom_immediate(_size_target)
