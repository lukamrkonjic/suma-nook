extends Node
## Reproducible SumaSoftDaylight comparison capture.
## Run:
##   godot --path . tests/lighting_comparison.tscn --disable-vsync \
##     --resolution 1920x1080 -- --shot-dir=<absolute folder>

const SAVE_PATH := "user://lighting_comparison_save.json"
const STAGE_NAMES := {
	"B": "B_neutral_key_only.png",
	"C": "C_cool_ambient.png",
	"D": "D_soft_shadows.png",
	"E": "E_tight_ssao.png",
	"F": "F_agx_grade.png",
	"G": "G_corrected_materials.png",
}

var _main: Main
var _output_dir := "res://docs/lighting_redesign"
var _gpu_results: Dictionary = {}
var _variant_only := ""
var _plain_ground_only := false
var _calibration_sweep := false
var _grade_sweep := false


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
		elif argument.begins_with("--variant-only="):
			_variant_only = argument.trim_prefix("--variant-only=")
		elif argument == "--plain-ground-only":
			_plain_ground_only = true
		elif argument == "--calibration-sweep":
			_calibration_sweep = true
		elif argument == "--grade-sweep":
			_grade_sweep = true
	DirAccess.make_dir_recursive_absolute(_output_dir)
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	await _enter_gameplay()
	_hide_review_ui()
	if _plain_ground_only:
		_isolate_plain_ground()
	await _settle(24)
	RenderingServer.viewport_set_measure_render_time(
		get_viewport().get_viewport_rid(),
		true
	)
	if _calibration_sweep:
		await _capture_plain_ground_calibration_sweep()
	elif _grade_sweep:
		await _capture_grade_sweep()
	elif _variant_only == "":
		await _capture_stages()
		await _capture_variants()
	else:
		_apply_final_material_finish()
		_main.lighting.apply_daylight_variant(_variant_only)
		await _settle(30)
		await _save_viewport("variant_%s.png" % _variant_only)
		_gpu_results[_variant_only] = await _measure_gpu_frame_time(120)
	_main.lighting.apply_daylight_variant("warm")
	await _settle(8)
	_write_manifest()
	print("LIGHTING COMPARISON CAPTURED — %s" % _output_dir)
	_main.free()
	_main = null
	await get_tree().process_frame
	get_tree().quit(0)


func _isolate_plain_ground() -> void:
	var target := _main.renderer.tile_node(Vector2i.ZERO, 0)
	if target == null:
		push_error("Lighting comparison could not find the Plain Ground control.")
		get_tree().quit(1)
		return
	for child in _main.renderer.get_children():
		if child is Node3D:
			(child as Node3D).visible = child == target
	if _main.player != null:
		_main.player.visible = false
	_main.camera_rig.global_position = target.global_position + Vector3(0.0, -0.16, 0.0)
	_main.camera_rig.camera.position.z = 12.0
	# GG's PostProcessLayer owns antialiasing while its Camera explicitly has
	# MSAA disabled. Godot TAA was visibly washing the hard low-poly silhouette;
	# the shipping test path uses native-resolution 8x MSAA without temporal
	# accumulation instead.
	get_viewport().msaa_3d = Viewport.MSAA_8X
	get_viewport().use_taa = false
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


func _capture_plain_ground_calibration_sweep() -> void:
	var extracted_sky := Color(0.8, 0.7411765, 0.7686275)
	var extracted_equator := Color(0.6509804, 0.41960785, 0.37254903)
	var extracted_ground := Color(0.85882354, 0.8, 0.72156864)
	var extracted_sun := Color(1.0, 1.0, 0.9921569)
	for hemisphere_scale: float in [1.0, 1.2, 1.4]:
		for sun_energy: float in [4.5, 5.5, 6.5]:
			var profile := (
				load("res://assets/visual_profiles/suma_soft_daylight_warm.tres")
				as VisualStyleProfile
			).duplicate(true) as VisualStyleProfile
			profile.profile_id = "plain_ground_calibration"
			profile.background_color = Color(0.74, 0.92, 0.84)
			profile.ambient_gradient_enabled = true
			profile.ambient_sky_color = extracted_sky * hemisphere_scale
			profile.ambient_equator_color = extracted_equator * hemisphere_scale
			profile.ambient_ground_color = extracted_ground * hemisphere_scale
			profile.ambient_energy = 1.0
			profile.sun_color = extracted_sun
			profile.sun_energy = sun_energy
			profile.sun_specular = 0.13
			profile.tonemap = "agx"
			profile.exposure = 1.08
			profile.agx_white = 12.0
			profile.agx_contrast = 1.15
			profile.brightness = 1.0
			profile.contrast = 1.0
			profile.saturation = 1.05
			profile.ssao_enabled = false
			profile.ssil_enabled = false
			profile.ssr_enabled = false
			profile.glow_enabled = false
			profile.reflection_probe_enabled = false
			_main.lighting.apply_profile(profile)
			await _settle(8)
			await _save_viewport(
				"plain_h%02d_s%02d.png"
				% [roundi(hemisphere_scale * 10.0), roundi(sun_energy * 10.0)]
			)


func _capture_grade_sweep() -> void:
	var base := (
		load("res://assets/visual_profiles/suma_soft_daylight_warm.tres")
		as VisualStyleProfile
	)
	for tone_mapper: String in ["agx", "filmic", "aces"]:
		for grade_exposure: float in [0.9, 1.0, 1.1]:
			var profile := base.duplicate(true) as VisualStyleProfile
			profile.profile_id = "grade_%s" % tone_mapper
			profile.tonemap = tone_mapper
			profile.exposure = grade_exposure
			profile.contrast = 1.0
			profile.saturation = 1.12
			_main.lighting.apply_profile(profile)
			await _settle(10)
			await _save_viewport(
				"grade_%s_e%02d.png"
				% [tone_mapper, roundi(grade_exposure * 10.0)]
			)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("Lighting comparison could not find the character creator.")
		get_tree().quit(1)
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Light Keeper"
	creator._finish()
	await get_tree().create_timer(0.7).timeout
	if not _main._gameplay_started:
		push_error("Lighting comparison could not enter gameplay.")
		get_tree().quit(1)


func _hide_review_ui() -> void:
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	# Lock the exact settled gameplay camera for every stage and variant.
	_main.camera_rig.set_process(false)


func _capture_stages() -> void:
	_apply_legacy_material_finish()
	for stage_id in ["B", "C", "D", "E", "F"]:
		_main.lighting.apply_profile(_stage_profile(stage_id))
		await _settle(18)
		await _save_viewport(STAGE_NAMES[stage_id])
	_apply_final_material_finish()
	_main.lighting.apply_profile(_stage_profile("G"))
	await _settle(24)
	await _save_viewport(STAGE_NAMES["G"])


func _capture_variants() -> void:
	for variant_id in ["neutral", "warm", "overcast", "fallback"]:
		_main.lighting.apply_daylight_variant(variant_id)
		await _settle(30)
		await _save_viewport("variant_%s.png" % variant_id)
		_gpu_results[variant_id] = await _measure_gpu_frame_time(120)


func _stage_profile(stage_id: String) -> VisualStyleProfile:
	var profile := (
		load("res://assets/visual_profiles/suma_soft_daylight_neutral.tres")
		as VisualStyleProfile
	).duplicate(true) as VisualStyleProfile
	profile.profile_id = "lighting_stage_%s" % stage_id.to_lower()
	# B: neutral key only. Each following stage adds one subsystem.
	profile.ambient_energy = 0.0
	profile.ssao_enabled = false
	profile.ssil_enabled = false
	profile.ssr_enabled = false
	profile.glow_enabled = false
	profile.tonemap = "linear"
	profile.exposure = 1.0
	profile.brightness = 1.0
	profile.contrast = 1.0
	profile.saturation = 1.0
	profile.shadow_cascade_mode = "orthogonal"
	profile.shadow_blend_splits = false
	profile.shadow_opacity = 1.0
	profile.shadow_blur = 1.0
	profile.sun_angular_distance = 0.65
	profile.reflection_probe_enabled = false
	if stage_id in ["C", "D", "E", "F", "G"]:
		profile.ambient_energy = 0.48
	if stage_id in ["D", "E", "F", "G"]:
		profile.shadow_cascade_mode = "pssm_2"
		profile.shadow_blend_splits = true
		profile.shadow_opacity = 0.56
		profile.shadow_blur = 1.25
		profile.sun_angular_distance = 1.8
	if stage_id in ["E", "F", "G"]:
		profile.ssao_enabled = true
	if stage_id in ["F", "G"]:
		profile.tonemap = "agx"
		profile.exposure = 0.95
		profile.saturation = 0.98
		profile.reflection_probe_enabled = true
	return profile


func _apply_legacy_material_finish() -> void:
	for cache_key: String in _main.materials._materials:
		var live: Material = _main.materials._materials[cache_key]
		var key := cache_key.get_slice("|", 0)
		if live is StandardMaterial3D:
			var finish := _legacy_finish(key)
			(live as StandardMaterial3D).roughness = finish.x
			(live as StandardMaterial3D).metallic_specular = finish.y
	var water := _main.materials.material("water") as ShaderMaterial
	water.set_shader_parameter("water_roughness", 0.24)
	water.set_shader_parameter("water_specular", 0.32)
	water.set_shader_parameter("scene_lighting_response", 0.0)


func _apply_final_material_finish() -> void:
	for cache_key: String in _main.materials._materials:
		var live: Material = _main.materials._materials[cache_key]
		var key := cache_key.get_slice("|", 0)
		if live is StandardMaterial3D and _main.palette.colors.has(key):
			var finish := _main.materials.material_parameters(key)
			(live as StandardMaterial3D).roughness = float(finish["roughness"])
			(live as StandardMaterial3D).metallic_specular = float(finish["specular"])
	var water := _main.materials.material("water") as ShaderMaterial
	water.set_shader_parameter("water_roughness", 0.42)
	water.set_shader_parameter("water_specular", 0.18)
	water.set_shader_parameter("scene_lighting_response", 1.0)


func _legacy_finish(key: String) -> Vector2:
	if key in ["warm_white", "ivory_highlight"]:
		return Vector2(0.82, 0.2)
	if _contains_any(key, ["grass", "moss", "leaf", "foliage", "pine", "olive", "flora", "reed"]):
		return Vector2(0.8, 0.2)
	if _contains_any(key, ["earth", "soil", "sand"]):
		return Vector2(0.9, 0.08)
	if _contains_any(key, ["stone", "rock", "sage_gray"]):
		return Vector2(0.74, 0.28)
	if _contains_any(key, ["wood", "cardboard"]):
		return Vector2(0.76, 0.24)
	if _contains_any(key, ["terracotta", "coral", "burnt_red"]):
		return Vector2(0.7, 0.3)
	if _contains_any(key, ["fabric", "skin", "hair", "petal", "flower", "mushroom", "cream_fabric"]):
		return Vector2(0.9, 0.14)
	if _contains_any(key, ["gold", "metal"]):
		return Vector2(0.66, 0.3)
	return Vector2(0.82, 0.22)


func _contains_any(value: String, tokens: Array[String]) -> bool:
	for token in tokens:
		if value.contains(token):
			return true
	return false


func _settle(frame_count: int) -> void:
	for frame in frame_count:
		await get_tree().process_frame


func _save_viewport(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _output_dir.path_join(file_name)
	var image := get_viewport().get_texture().get_image()
	GGCaptureEncode.encode_srgb(image)
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save lighting capture %s (error %d)." % [path, error])
	else:
		print("  [lighting shot] %s" % path)


func _measure_gpu_frame_time(frame_count: int) -> Dictionary:
	var viewport_rid := get_viewport().get_viewport_rid()
	var samples: Array[float] = []
	for frame in frame_count:
		await RenderingServer.frame_post_draw
		var milliseconds := RenderingServer.viewport_get_measured_render_time_gpu(
			viewport_rid
		)
		if milliseconds > 0.0:
			samples.append(milliseconds)
	if samples.is_empty():
		return {"median_ms": 0.0, "p95_ms": 0.0, "samples": 0}
	samples.sort()
	var p95_index := mini(samples.size() - 1, int(ceil(samples.size() * 0.95)) - 1)
	return {
		"median_ms": snappedf(samples[samples.size() / 2], 0.001),
		"p95_ms": snappedf(samples[p95_index], 0.001),
		"samples": samples.size(),
	}


func _write_manifest() -> void:
	var manifest := {
		"renderer": RenderingServer.get_rendering_device().get_device_name(),
		"viewport": get_viewport().get_visible_rect().size,
		"camera": _main.camera_rig.runtime_manifest(),
		"gpu_frame_time": _gpu_results,
		"shipping_profile": "warm",
		"shipping_manifest": _main.lighting.runtime_manifest(),
	}
	var file := FileAccess.open(_output_dir.path_join("measurements.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
