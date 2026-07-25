extends Node3D
class_name TilegardenCameraRig

signal rotated

var camera: Camera3D
var target := Vector3.ZERO
var yaw := PI * 0.25
var target_yaw := PI * 0.25
var pitch := deg_to_rad(34.0)
var ortho_size := 8.4
var target_ortho_size := 8.4
var distance := 24.0
var panning := false
var _last_mouse := Vector2.ZERO


func setup() -> void:
	camera = Camera3D.new()
	camera.name = "IsoCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ortho_size
	camera.near = 0.05
	camera.far = 120.0
	add_child(camera)
	_update_camera(1.0)


func _process(delta: float) -> void:
	yaw = lerp_angle(yaw, target_yaw, 1.0 - exp(-10.0 * delta))
	ortho_size = lerpf(ortho_size, target_ortho_size, 1.0 - exp(-12.0 * delta))
	_update_camera(delta)


func _update_camera(_delta: float) -> void:
	if camera == null:
		return
	var direction := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	var aim := target + Vector3(0, 0.5, 0)
	camera.position = aim + direction * distance
	camera.look_at(aim, Vector3.UP)
	camera.size = ortho_size


func rotate_quarter(direction: int) -> void:
	target_yaw += float(direction) * PI * 0.5
	rotated.emit()


func zoom_by(wheel_steps: float) -> void:
	target_ortho_size = clampf(target_ortho_size + wheel_steps * 1.15, 6.5, 22.0)


func begin_pan(mouse_position: Vector2) -> void:
	panning = true
	_last_mouse = mouse_position


func update_pan(mouse_position: Vector2) -> void:
	if not panning or camera == null:
		return
	var delta := mouse_position - _last_mouse
	_last_mouse = mouse_position
	var right := camera.global_transform.basis.x
	var flat_right := Vector3(right.x, 0, right.z).normalized()
	var forward := -camera.global_transform.basis.z
	var flat_forward := Vector3(forward.x, 0, forward.z).normalized()
	var viewport_height := maxf(1.0, get_viewport().get_visible_rect().size.y)
	var units_per_pixel := ortho_size / viewport_height
	target += (-flat_right * delta.x + flat_forward * delta.y) * units_per_pixel
	target.x = clampf(target.x, -14.0, 14.0)
	target.z = clampf(target.z, -14.0, 14.0)


func end_pan() -> void:
	panning = false


func focus_world() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "target", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "target_ortho_size", 8.4, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func screen_to_ground(screen: Vector2, plane_y := 0.08) -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if absf(direction.y) < 0.0001:
		return Vector3.ZERO
	var distance_to_plane := (plane_y - origin.y) / direction.y
	return origin + direction * distance_to_plane


func world_to_screen(world: Vector3) -> Vector2:
	return camera.unproject_position(world)


func snapshot() -> Dictionary:
	return {
		"target": [target.x, target.y, target.z],
		"yaw": target_yaw,
		"zoom": target_ortho_size,
	}


func restore_snapshot(state: Dictionary) -> void:
	var pos: Array = state.get("target", [0.0, 0.0, 0.0])
	if pos.size() >= 3:
		target = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	yaw = float(state.get("yaw", PI * 0.25))
	target_yaw = yaw
	ortho_size = clampf(float(state.get("zoom", 8.4)), 6.5, 22.0)
	target_ortho_size = ortho_size
