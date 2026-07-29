@tool
class_name CharacterLab
extends Node3D
## Internal fitting room for the modular character system. Assembles an
## AppearancePreset on neutral ground with front / three-quarter / gameplay
## cameras, an optional turntable, socket markers, and per-slot toggles.
## Not a player-facing customization menu.
##
## Editor: toggling "rebuild" reassembles after editing the preset or a part
## definition — no game launch needed.
##
## Run keys: 1 front · 2 three-quarter · 3 gameplay · T turntable ·
## M socket markers · H/E/B/N/U/O toggle hair/eyes/brows/nose/moustache/mouth.

const SLOT_KEYS := {
	KEY_H: "HAIR",
	KEY_E: "EYES",
	KEY_B: "EYEBROWS",
	KEY_N: "NOSE",
	KEY_U: "MOUSTACHE",
	KEY_O: "MOUTH",
}

@export var preset: CharacterAppearancePreset:
	set(value):
		preset = value
		if is_inside_tree():
			_rebuild()
@export var rebuild := false:
	set(value):
		rebuild = false
		_rebuild()
@export var show_sockets := false:
	set(value):
		show_sockets = value
		_refresh_socket_markers()
@export var turntable := false
@export var turntable_seconds := 8.0
@export var play_idle := true

var assembler := CharacterAssembler.new()

var _character: Node3D
var _cameras: Dictionary = {}
var _socket_markers: Array[Node3D] = []
var _slot_visible: Dictionary = {}
var _warning_label: Label


func _ready() -> void:
	if preset == null:
		preset = load(
			"res://assets/characters/presets/default_male_appearance.tres"
		) as CharacterAppearancePreset
	_build_stage()
	_rebuild()


func _process(delta: float) -> void:
	if turntable and _character != null:
		_character.rotate_y(delta * TAU / maxf(turntable_seconds, 0.5))


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_activate_camera("front")
		KEY_2:
			_activate_camera("three_quarter")
		KEY_3:
			_activate_camera("game")
		KEY_T:
			turntable = not turntable
		KEY_M:
			show_sockets = not show_sockets
		_:
			if SLOT_KEYS.has(key.keycode):
				var slot := String(SLOT_KEYS[key.keycode])
				_slot_visible[slot] = not bool(_slot_visible.get(slot, true))
				assembler.set_slot_visible(slot, _slot_visible[slot])


func _rebuild() -> void:
	if _character != null:
		_character.queue_free()
		_character = null
	_socket_markers.clear()
	if preset == null:
		_report(["no preset selected"])
		return
	_character = assembler.assemble(preset)
	if _character == null:
		_report(assembler.last_warnings)
		return
	add_child(_character)
	_character.position = Vector3.ZERO
	# Ground against the animated pose: clips follow the Mixamo convention of
	# a lifted hips baseline, so a raw AABB drop would leave the feet mid-air.
	var bounds := _visual_bounds(_character)
	_character.position.y = -bounds.position.y
	if play_idle and not Engine.is_editor_hint():
		var player := _character.find_child(
			"AnimationPlayer", true, false
		) as AnimationPlayer
		if player != null and player.has_animation("idle_relaxed"):
			var idle := player.get_animation("idle_relaxed")
			idle.loop_mode = Animation.LOOP_LINEAR
			player.play("idle_relaxed")
			player.seek(0.0, true)
			_character.position.y = -_animated_floor_offset(bounds)
	_slot_visible.clear()
	_refresh_socket_markers()
	_report(assembler.last_warnings)


func _report(warnings: PackedStringArray) -> void:
	if _warning_label == null:
		return
	if warnings.is_empty():
		_warning_label.text = "OK: no assembler warnings"
		_warning_label.modulate = Color(0.65, 0.9, 0.65)
	else:
		_warning_label.text = "WARNINGS:\n- " + "\n- ".join(warnings)
		_warning_label.modulate = Color(1.0, 0.72, 0.55)


func _refresh_socket_markers() -> void:
	for marker in _socket_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_socket_markers.clear()
	if not show_sockets or _character == null:
		return
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.008
	marker_mesh.height = 0.016
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = Color(1.0, 0.25, 0.55)
	marker_mesh.material = marker_material
	for socket_name in assembler.socket_names():
		var socket := assembler.socket_node(socket_name)
		if socket == null:
			continue
		var marker := MeshInstance3D.new()
		marker.name = "Marker_%s" % socket_name
		marker.mesh = marker_mesh
		socket.add_child(marker)
		_socket_markers.append(marker)


func _build_stage() -> void:
	if get_node_or_null("StageEnvironment") != null:
		_warning_label = get_node_or_null("WarningOverlay/WarningLabel")
		_collect_cameras()
		return
	var environment := WorldEnvironment.new()
	environment.name = "StageEnvironment"
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#dfd9c9")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#fff4dd")
	settings.ambient_light_energy = 0.75
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.name = "StageSun"
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_color = Color("#ffe9c4")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	ground.name = "StageGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(6.0, 6.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#a8a08c")
	ground_material.roughness = 0.95
	ground.material_override = ground_material
	add_child(ground)

	_add_camera("front", Vector3(0.0, 0.62, 2.6), Vector3(0.0, 0.55, 0.0), 1.4)
	_add_camera(
		"three_quarter", Vector3(1.8, 1.25, 2.1), Vector3(0.0, 0.5, 0.0), 1.6
	)
	# Matches CameraRig: 15 degree lens, -34 degree pitch, 45 degree yaw.
	var game_camera := Camera3D.new()
	game_camera.name = "Camera_game"
	game_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	game_camera.fov = 15.0
	var yaw := deg_to_rad(45.0)
	var distance := 7.0
	var pitch := deg_to_rad(34.0)
	game_camera.position = Vector3(
		distance * cos(pitch) * sin(yaw),
		0.55 + distance * sin(pitch),
		distance * cos(pitch) * cos(yaw)
	)
	add_child(game_camera)
	game_camera.look_at_from_position(
		game_camera.position, Vector3(0.0, 0.45, 0.0), Vector3.UP
	)
	_cameras["game"] = game_camera

	var overlay := CanvasLayer.new()
	overlay.name = "WarningOverlay"
	add_child(overlay)
	_warning_label = Label.new()
	_warning_label.name = "WarningLabel"
	_warning_label.position = Vector2(12.0, 12.0)
	_warning_label.add_theme_font_size_override("font_size", 14)
	overlay.add_child(_warning_label)

	_activate_camera("front")


func _add_camera(
	camera_name: String, position: Vector3, target: Vector3, size: float
) -> void:
	var camera := Camera3D.new()
	camera.name = "Camera_%s" % camera_name
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = size
	camera.position = position
	add_child(camera)
	camera.look_at_from_position(position, target, Vector3.UP)
	_cameras[camera_name] = camera


func _collect_cameras() -> void:
	for camera_name in ["front", "three_quarter", "game"]:
		var camera := get_node_or_null("Camera_%s" % camera_name)
		if camera is Camera3D:
			_cameras[camera_name] = camera


func _activate_camera(camera_name: String) -> void:
	var camera := _cameras.get(camera_name) as Camera3D
	if camera != null and not Engine.is_editor_hint():
		camera.current = true


## Mirrors PlayerVisual._animated_ground_offset: keep the authored sole
## thickness below the toe bones while grounding against the animated pose.
func _animated_floor_offset(bounds: AABB) -> float:
	var skeleton := _character.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return bounds.position.y
	var lowest_rest := INF
	var animated_for_lowest := 0.0
	for toe_name in ["mixamorigLeftToeBase", "mixamorigRightToeBase"]:
		var toe_index := skeleton.find_bone(toe_name)
		if toe_index < 0:
			continue
		var rest_y := skeleton.get_bone_global_rest(toe_index).origin.y
		if rest_y < lowest_rest:
			lowest_rest = rest_y
			animated_for_lowest = skeleton.get_bone_global_pose(
				toe_index
			).origin.y
	if is_inf(lowest_rest):
		return bounds.position.y
	var sole_margin := bounds.position.y - lowest_rest
	return animated_for_lowest + sole_margin


func _visual_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var has_point := false
	var inverse := root.global_transform.affine_inverse()
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var relative := inverse * mesh_instance.global_transform
		var mesh_bounds := mesh_instance.get_aabb()
		for corner in 8:
			var point := relative * mesh_bounds.get_endpoint(corner)
			if has_point:
				bounds = bounds.expand(point)
			else:
				bounds = AABB(point, Vector3.ZERO)
				has_point = true
	return bounds
