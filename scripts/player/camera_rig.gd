class_name CameraRig
extends Node3D
## Orthographic diorama camera: 45° yaw steps, ~34° pitch, smooth follow,
## bounded zoom. Frames the world; follows the player gently. Movement input
## stays camera-relative through every rotation (horizontal_basis()).

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
	camera.name = "OrthoCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _size_target
	camera.position = Vector3(0, 0, 42.0)
	camera.near = 0.1
	camera.far = 140.0
	_pitch_node.add_child(camera)
	camera.current = true


func _process(delta: float) -> void:
	if target != null:
		var goal := target.global_position
		global_position = global_position.lerp(goal, minf(1.0, core.registries.tunef("camera_follow_speed", 4.5) * delta))
	rotation_degrees.y = lerp_angle(deg_to_rad(rotation_degrees.y), deg_to_rad(_yaw_target), minf(1.0, 10.0 * delta)) * 180.0 / PI
	camera.size = lerpf(camera.size, _size_target, minf(1.0, 8.0 * delta))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_rotate_left"):
		_yaw_target += 90.0
	elif event.is_action_pressed("camera_rotate_right"):
		_yaw_target -= 90.0
	elif event is InputEventMouseButton and event.pressed:
		var wheel := event as InputEventMouseButton
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			_size_target = clampf(_size_target - 1.2, core.registries.tunef("camera_min_size", 6.0), core.registries.tunef("camera_max_size", 28.0))
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_size_target = clampf(_size_target + 1.2, core.registries.tunef("camera_min_size", 6.0), core.registries.tunef("camera_max_size", 28.0))


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
	_size_target = float(data.get("size", core.registries.tunef("camera_default_size", 8.8)))
	camera.size = _size_target
