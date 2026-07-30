extends Node3D
## Focused visual regression for the first-pass female body, shared face
## catalog, palette tint, grounding, and retargeted locomotion.

const OUTPUT_DIR := "res://artifacts/player_female_review"

var _visual: PlayerVisual
var _camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_build_stage()
	await _settle(12)
	await _capture("female_idle_front.png")

	_camera.position = Vector3(1.55, 1.32, -2.15)
	_camera.size = 1.75
	_camera.look_at(Vector3(0.0, 0.54, 0.0))
	for _frame in 54:
		_visual.set_walk(1.0, 1.0 / 60.0)
		await get_tree().process_frame
	await _capture("female_walk_three_quarter.png")

	for _frame in 30:
		_visual.set_walk(0.0, 1.0 / 60.0)
		await get_tree().process_frame
	_visual.play("idle")
	_camera.position = Vector3(0.0, 0.82, -2.5)
	_camera.size = 1.52
	_camera.look_at(Vector3(0.0, 0.55, 0.0))
	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var creator := CharacterCreator.new()
	add_child(creator)
	creator.profile.body_index = 1
	creator.setup(
		UiKit.new(palette),
		palette,
		func(profile): _visual.apply_profile(profile)
	)
	await _settle(8)
	await _capture("female_creator_menu.png")
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

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 4.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#758d57")
	ground_material.roughness = 0.96
	ground.material_override = ground_material
	add_child(ground)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 1.52
	_camera.position = Vector3(0.0, 0.82, -2.5)
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.55, 0.0))
	_camera.current = true

	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	_visual = PlayerVisual.new()
	add_child(_visual)
	_visual.build(assets, palette)
	var profile := PlayerProfile.new()
	profile.body_index = 1
	profile.skin_index = 2
	profile.hair_color_index = 5
	profile.hair_style = 3
	profile.eye_index = 5
	profile.mouth_index = 1
	profile.nose_index = 1
	_visual.apply_profile(profile)


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
		push_error(
			"Could not save female player capture %s (error %d)."
			% [path, error]
		)
		get_tree().quit(1)
	else:
		print("PLAYER_FEMALE_CAPTURE ", path)
