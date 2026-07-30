extends Node3D
## Visual regression for clothing imported through the Clothing Lab pipeline.

const OUTPUT_DIR := "res://artifacts/imported_clothing_review"

var _visual: PlayerVisual
var _camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_build_stage()
	if not _equip_imported_outfit():
		get_tree().quit(1)
		return
	await _settle(12)
	await _capture("outfit_idle_three_quarter.png")
	_camera.position = Vector3(0.0, 0.82, -2.5)
	_camera.size = 1.52
	_camera.look_at(Vector3(0.0, 0.55, 0.0))
	await _settle(4)
	await _capture("outfit_idle_front.png")
	_camera.position = Vector3(1.55, 1.32, -2.15)
	_camera.size = 1.75
	_camera.look_at(Vector3(0.0, 0.54, 0.0))
	for _frame in 54:
		_visual.set_walk(1.0, 1.0 / 60.0)
		await get_tree().process_frame
	await _capture("outfit_walk_three_quarter.png")
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


func _equip_imported_outfit() -> bool:
	var base := load(
		"res://assets/characters/presets/default_male_appearance.tres"
	) as CharacterAppearancePreset
	if base == null:
		push_error("Imported clothing capture could not load the base preset.")
		return false
	var preset := CharacterAppearancePreset.new()
	preset.preset_id = "imported_clothing_review"
	preset.body_profile = base.body_profile
	preset.skin_color = base.skin_color
	preset.hair_color = base.hair_color
	preset.brow_color = base.brow_color
	preset.moustache_color = base.moustache_color
	preset.eye_color = base.eye_color
	preset.mouth_color = base.mouth_color
	for part in base.parts:
		if (
			part != null
			and part.slot != CharacterSlots.TOP_INNER
			and part.slot != CharacterSlots.TOP_OUTER
			and part.slot != CharacterSlots.BOTTOM
			and part.slot != CharacterSlots.HEADWEAR
		):
			preset.parts.append(part)
	for path in [
		"res://assets/characters/parts/defs/top_yellow_shirt.tres",
		"res://assets/characters/parts/defs/top_tweed_vest.tres",
		"res://assets/characters/parts/defs/bottom_tweed_trousers.tres",
		"res://assets/characters/parts/defs/headwear_service_cap.tres",
	]:
		var imported := load(path) as CharacterPartDefinition
		if imported == null:
			push_error("Imported clothing capture could not load %s." % path)
			return false
		preset.parts.append(imported)
	if not _visual._appearance_assembler.assemble_onto(
		_visual._body, preset
	):
		push_error(
			"Imported clothing capture could not assemble: %s"
			% ", ".join(_visual._appearance_assembler.last_warnings)
		)
		return false
	_visual._appearance_preset = preset
	return true


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
			"Could not save clothing capture %s (error %d)."
			% [path, error]
		)
		get_tree().quit(1)
	else:
		print("IMPORTED_CLOTHING_CAPTURE ", path)
