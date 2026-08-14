class_name CameraRig
extends Node3D
## Narrow-perspective diorama camera with the confirmed 15° lens, 40–70 unit
## distance range, five-unit zoom steps, and quarter-turn orbit. _size_target
## retains its historical name but now stores literal camera distance.

signal orbit_started(target_yaw: float)
signal orbit_finished(yaw: float)
signal zoom_changed(distance: float)

const ArtStyleSettingsScript := preload(
	"res://scripts/visuals/art_style_settings.gd"
)

var core: GameCore
var target: Node3D
var camera: Camera3D

var _yaw := 45.0
var _yaw_target := 45.0
var _size_target := 37.0
var _pitch_node: Node3D
var _rotating := false
var _pan_offset := Vector3.ZERO
var _middle_panning := false
var _creator_focus := false
var _pointer_edit_locked := false
var _input_blocker := Callable()
var _continuous_pan_armed := false

const CAMERA_PAN_DEADZONE := 0.35


func setup(game_core: GameCore, follow_target: Node3D) -> void:
	core = game_core
	target = follow_target
	# The camera already owns render-frame damping in _process(). Keep it out of
	# the physics interpolation system so zoom/orbit writes do not double-filter
	# or trigger interpolation warnings.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_yaw = core.registries.tunef("camera_default_yaw_deg", 45.0)
	_yaw_target = _yaw
	_size_target = _default_gameplay_distance()
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
	camera.far = 100.0
	_pitch_node.add_child(camera)
	camera.current = true


func _process(delta: float) -> void:
	# A world drag resolves both ends through screen-space rays. Hold the live
	# camera transform steady for that short gesture so an already-settling
	# zoom, orbit, follow, or pan cannot slide the destination under the cursor.
	# Targets keep their intended values and resume damping on release.
	if _pointer_edit_locked:
		core.view_state = save_state()
		return
	_apply_continuous_pan(delta)
	if target != null:
		var goal := target.global_position + _pan_offset
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


## The world point currently framed by the camera. Systems that present an
## event inside the visible diorama use this instead of reaching into the
## camera's private pan state.
func focus_world_position() -> Vector3:
	return target.global_position + _pan_offset if target != null else global_position


## Mouse releases can be consumed by UI controls before reaching
## _unhandled_input. Observe an active middle-drag release here as a safety net
## so a drag can never be left running after the button is up.
func _input(event: InputEvent) -> void:
	if (
		_middle_panning
		and event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE
		and not (event as InputEventMouseButton).pressed
	):
		_end_middle_pan()


## Middle-drag reframes the view and the new framing sticks.
##
## It used to snap back to where the drag started, making it a peek you had to
## hold. Panning somewhere to work there and being thrown back on release is the
## opposite of what the gesture is for. The offset now persists exactly like
## zoom and orbit do, follows the player as a fixed offset, and is saved.
func _end_middle_pan() -> void:
	if not _middle_panning:
		return
	_middle_panning = false
	core.autosave_soon()


func _unhandled_input(event: InputEvent) -> void:
	if _creator_focus or _pointer_edit_locked or _camera_input_blocked():
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
			if wheel.pressed:
				_middle_panning = true
			else:
				_end_middle_pan()
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
	# Middle-drag is deliberately inverted on both axes: dragging the pointer
	# right/down moves the framed world left/up. Keyboard/controller pan remains
	# independent of this mouse-only preference.
	_pan_offset += (
		-basis.x * relative.x * world_per_pixel
		- basis.z * relative.y * world_per_pixel
	)
	_pan_offset.y = 0.0
	_clamp_pan_offset()


func _apply_continuous_pan(delta: float) -> void:
	if _camera_input_blocked():
		_suspend_camera_input()
		return
	if _creator_focus or _middle_panning:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if (
		focused is LineEdit
		or focused is TextEdit
		or (
			focused != null
			and InputDeviceService.shared() != null
			and InputDeviceService.shared().is_controller()
		)
	):
		return
	var input := Input.get_vector(
		"camera_pan_left",
		"camera_pan_right",
		"camera_pan_up",
		"camera_pan_down"
	)
	var input_length := input.length()
	if input_length <= CAMERA_PAN_DEADZONE:
		# UI transitions deliberately disarm held analogue input. The stick must
		# return to neutral once before camera motion may resume, preventing the
		# Build Bag's opening/closing frame from carrying a stale pan into play.
		_continuous_pan_armed = true
		return
	if not _continuous_pan_armed:
		return
	# Apply a second, camera-specific radial deadzone. A connected controller's
	# idle right-stick noise must never drift the diorama while the player is
	# using mouse/keyboard, while deliberate analogue pan remains gradual.
	input = input.normalized() * inverse_lerp(
		CAMERA_PAN_DEADZONE,
		1.0,
		input_length
	)
	var movement_basis := horizontal_basis()
	var direction := movement_basis.x * input.x + movement_basis.z * input.y
	direction.y = 0.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var default_distance := _default_gameplay_distance()
	var zoom_scale := clampf(_size_target / maxf(1.0, default_distance), 0.5, 2.0)
	_pan_offset += direction * core.registries.tunef("camera_pan_speed", 10.0) * zoom_scale * delta
	_clamp_pan_offset()


## Main owns the complete modal/HUD state, so it supplies the single camera
## input gate. Polling it here closes the one-frame gap before controller focus
## is assigned to a newly opened panel.
func set_input_blocker(blocker: Callable) -> void:
	_input_blocker = blocker


func _camera_input_blocked() -> bool:
	return _input_blocker.is_valid() and bool(_input_blocker.call())


func _suspend_camera_input() -> void:
	_continuous_pan_armed = false
	_end_middle_pan()


func _clamp_pan_offset() -> void:
	_pan_offset.y = 0.0
	var limit := core.registries.tunef("camera_pan_limit", 1024.0)
	if limit > 0.0 and _pan_offset.length() > limit:
		_pan_offset = _pan_offset.normalized() * limit


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


func set_build_mode(_enabled: bool) -> void:
	# Editing changes input semantics, not composition. In particular, the
	# compact Worldheart start uses its own 22-unit frame; replacing that with
	# the retired 37/40-unit build frame caused a delayed zoom jump as soon as a
	# tile drag released the camera lock.
	return


func begin_pointer_edit() -> void:
	_pointer_edit_locked = true


func end_pointer_edit() -> void:
	_pointer_edit_locked = false


func pointer_edit_locked() -> bool:
	return _pointer_edit_locked


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
	_size_target = _default_gameplay_distance()
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


func _default_gameplay_distance() -> float:
	if ArtStyleSettingsScript.palette_profile() == "garden_galaxy_reference":
		return 40.0
	return core.registries.tunef("camera_default_size", 37.0)


func save_state() -> Dictionary:
	var persisted_pan := _pan_offset
	return {
		"yaw": _yaw_target,
		"distance": _size_target,
		"pan": [persisted_pan.x, persisted_pan.z],
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
			"pan_speed_units_per_second": core.registries.tunef("camera_pan_speed", 10.0),
			"pan_limit": core.registries.tunef("camera_pan_limit", 1024.0),
			"pan_offset": _pan_offset,
			"orbit_speed_degrees_per_second": core.registries.tunef("camera_rotate_speed_deg", 360.0),
			"orbit_step_degrees": 90.0,
			"settle_epsilon_degrees": 0.25,
		},
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
	var stored_distance := float(data.get(
		"distance",
		data.get(
			"size",
			_default_gameplay_distance()
		)
	))
	# Migrate experimental saves that stored an orthographic-equivalent span.
	if not data.has("distance") and stored_distance < 25.0:
		stored_distance /= 2.0 * tan(deg_to_rad(core.registries.tunef("camera_fov_deg", 15.0) * 0.5))
	_size_target = clampf(
		stored_distance,
		core.registries.tunef("camera_min_size", 14.0),
		core.registries.tunef("camera_max_size", 70.0)
	)
	var stored_pan: Array = data.get("pan", [0.0, 0.0])
	_pan_offset = Vector3(
		float(stored_pan[0]) if stored_pan.size() > 0 else 0.0,
		0.0,
		float(stored_pan[1]) if stored_pan.size() > 1 else 0.0
	)
	_clamp_pan_offset()
	set_zoom_immediate(_size_target)
