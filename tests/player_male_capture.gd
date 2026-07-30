extends Node3D
## Focused visual regression for modular head-socket alignment and palette tint.

const OUTPUT_DIR := "res://artifacts/player_male_review"

var _visual: PlayerVisual
var _camera: Camera3D
var _ground: MeshInstance3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_build_stage()
	await _settle(12)
	_print_ground_diagnostics()
	await _capture("player_idle_aligned.png")
	_camera.position = Vector3(0.0, 0.82, -2.5)
	_camera.size = 1.52
	_camera.look_at(Vector3(0.0, 0.55, 0.0))
	await _settle(4)
	await _capture("player_front_aligned.png")
	_camera.position = Vector3(1.55, 1.32, -2.15)
	_camera.size = 1.75
	_camera.look_at(Vector3(0.0, 0.54, 0.0))

	for _frame in 54:
		_visual.set_walk(1.0, 1.0 / 60.0)
		await get_tree().process_frame
	await _capture("player_walk_aligned.png")

	var profile := PlayerProfile.new()
	profile.skin_index = 2
	profile.hair_color_index = 5
	profile.hair_style = 2
	profile.eye_index = 2
	profile.mouth_index = 2
	profile.nose_index = 3
	_visual.apply_profile(profile)
	await _settle(6)
	await _capture("player_palette_bun.png")

	profile.skin_index = 0
	profile.hair_color_index = 0
	profile.hair_style = 0
	profile.eye_index = 0
	profile.mouth_index = 0
	profile.nose_index = 0
	_visual.apply_profile(profile)
	var core := GameCore.new()
	if not core.setup():
		push_error("Could not load equipment for player capture.")
		get_tree().quit(1)
		return
	core.equipment.acquire("cosmetic_cowboy_vest")
	core.equipment.equip("cosmetic_cowboy_vest")
	_visual.apply_equipment(core.equipment)
	await _settle(8)
	await _capture("player_legacy_vest_skipped.png")

	_visual._animation_player.stop()
	_visual._skeleton.reset_bone_poses()
	_visual._body.rotation = _visual._body_base_rotation
	var rest_bounds := _visual._visual_bounds_in(_visual._body)
	_visual._body.position.y = -rest_bounds.position.y * _visual._body.scale.y
	_ground.visible = false
	_camera.position = Vector3(0.0, 0.82, -2.5)
	_camera.size = 1.52
	_camera.look_at(Vector3(0.0, 0.55, 0.0))
	await _settle(5)
	await _capture("player_front_tpose.png")
	get_tree().quit(0)


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#d9d2bd")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#fff2d4")
	settings.ambient_light_energy = 0.82
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_color = Color("#ffe3b7")
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	add_child(sun)

	_ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 4.0)
	_ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#758d57")
	ground_material.roughness = 0.96
	_ground.material_override = ground_material
	add_child(_ground)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 1.75
	_camera.position = Vector3(1.55, 1.32, -2.15)
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.54, 0.0))
	_camera.current = true

	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	_visual = PlayerVisual.new()
	add_child(_visual)
	_visual.build(assets, palette)
	var profile := PlayerProfile.new()
	profile.skin_index = 0
	profile.hair_color_index = 0
	profile.hair_style = 0
	profile.eye_index = 0
	_visual.apply_profile(profile)


## Where do the feet actually land relative to the stage ground (y = 0)?
func _print_ground_diagnostics() -> void:
	var skeleton := _visual._skeleton
	var body := _visual._body
	var mesh := body.find_child("PlayerMaleBody", true, false) as MeshInstance3D
	print("PLAYER_GROUND body_position=", body.position, " scale=", body.scale)
	if mesh != null:
		print("PLAYER_GROUND mesh_aabb=", mesh.get_aabb())
	for toe_name in ["mixamorigLeftToeBase", "mixamorigRightToeBase"]:
		var toe_index := skeleton.find_bone(toe_name)
		var rest := skeleton.get_bone_global_rest(toe_index).origin
		var pose := skeleton.get_bone_global_pose(toe_index).origin
		var world := (
			skeleton.global_transform * pose
		)
		print(
			"PLAYER_GROUND ", toe_name,
			" rest=", rest, " pose=", pose, " world=", world
		)


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await get_tree().process_frame


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	GGCaptureEncode.encode_srgb(image)
	var path := OUTPUT_DIR.path_join(file_name)
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save player capture %s (error %d)." % [path, error])
		get_tree().quit(1)
	else:
		print("PLAYER_CAPTURE ", path)
