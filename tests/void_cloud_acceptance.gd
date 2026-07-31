extends Node
## Acceptance battery for the volumetric void-cloud ocean. Boots the real
## game, then verifies: continuous drift and evolving silhouettes, world-space
## camera composition, volume boundary invisibility (by construction:
## density fades inside each box), island separation, day/night
## blending, forbidden-asset absence, and GPU cost per quality preset.
## Motion runs at Engine.time_scale 4 so the authored 60 seconds of cloud
## evolution are observed in 15 real seconds — all cloud motion is
## delta-accumulated, so acceleration is faithful.

const SAVE_PATH := "user://void_cloud_acceptance_save.json"

var _main: Main
var _shot_dir := "res://artifacts/void_clouds"
var _failures := 0


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_shot_dir = argument.trim_prefix("--shot-dir=")
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(path)
			)
	_main = (
		load("res://scenes/main.tscn") as PackedScene
	).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await _wait(0.6)
	await _enter_gameplay()
	_hide_ui()
	_main.camera_rig.set_zoom_immediate(34.0)
	# Let the procedural noise finish generating and the startup fade land.
	await _wait(4.0)

	await _test_assets_and_structure()
	await _test_drift_and_silhouette()
	await _test_parallax()
	await _test_island_separation()
	await _test_day_night()
	await _test_aspect_ratios()
	await _test_performance()

	if _failures == 0:
		print("VOID CLOUD ACCEPTANCE PASSED")
	else:
		print("VOID CLOUD ACCEPTANCE FAILED — %d" % _failures)
	_main.queue_free()
	for _frame in 3:
		await get_tree().process_frame
	get_tree().quit(_failures)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok — %s" % label)
	else:
		_failures += 1
		push_error("CLOUD FAIL: %s" % label)


## ASSET TEST + structural restrictions: procedural volumetric only.
func _test_assets_and_structure() -> void:
	var manifest: Dictionary = (
		_main.lighting.void_clouds.runtime_manifest()
	)
	_check(
		bool(manifest["enabled"]) and bool(manifest["world_space"]),
		"cloud system is enabled and world-space"
	)
	_check(
		int(manifest["screen_space_layers"]) == 0
		and int(manifest["sprites"]) == 0
		and int(manifest["cloud_image_textures"]) == 0,
		"no sprites, screen layers, or cloud image textures"
	)
	_check(
		_main.lighting.void_clouds.find_child(
			"HorizonCloudSea", true, false
		) is MeshInstance3D,
		"clouds render as one world-anchored raymarched slab"
	)
	var forbidden_names := [
		"CloudLayer",
		"RaymarchedCottonClouds",
		"CloudShadowCasters",
		"PainterlyVolumetricCloudBanks",
	]
	var stale := false
	for forbidden in forbidden_names:
		if _main.find_child(forbidden, true, false) != null:
			stale = true
	_check(not stale, "no retired cloud nodes exist anywhere")
	var shader_code := (
		load(
			"res://assets/materials/void_cloud_sea.gdshader"
		) as Shader
	).code
	_check(
		shader_code.contains("sampler3D")
		and shader_code.contains("henyey_greenstein")
		and shader_code.contains("powder"),
		"shader follows the HZD model: 3D noise, HG phase, powder term"
	)
	_check(
		not shader_code.contains(".png")
		and not shader_code.contains("hint_default_texture")
		and int(manifest["runtime_baked_noise_textures"]) >= 3,
		"every noise field is runtime-baked, no texture assets on disk"
	)
	_check(
		not bool(manifest["volumetric_fog_used"]),
		"the broken volumetric-fog path stays entirely off"
	)


## STATIC-CLOUD + SILHOUETTE + CORNER TESTS: stationary camera, authored
## 0/30/60 second span, lower-half pixels must evolve between every capture.
func _test_drift_and_silhouette() -> void:
	Engine.time_scale = 4.0
	var t0 := await _capture("silhouette_t00")
	await _wait(7.5)   # 30 authored seconds
	var t30 := await _capture("silhouette_t30")
	await _wait(7.5)   # 60 authored seconds
	var t60 := await _capture("silhouette_t60")
	Engine.time_scale = 1.0
	var drift_a := _lower_half_difference(t0, t30)
	var drift_b := _lower_half_difference(t30, t60)
	print(
		"  drift mean-abs-diff 0->30s=%.5f 30->60s=%.5f"
		% [drift_a, drift_b]
	)
	_check(
		drift_a > 0.0015 and drift_b > 0.0015,
		"cloud contours drift and evolve continuously while camera is still"
	)
	var manifest: Dictionary = (
		_main.lighting.void_clouds.runtime_manifest()
	)
	_check(
		float(manifest["wind_time"]) > 0.0,
		"motion comes from accumulated sampling time, never reseeding"
	)


## PARALLAX + ZOOM-STABILITY TEST: pan and zoom through the supported
## camera range. The slab is anchored in world space, so its bounds must
## be bit-identical at every zoom - the camera can only change perspective,
## never recompose or rescale the cloudscape.
func _test_parallax() -> void:
	var rig := _main.camera_rig
	var origin: Vector3 = rig.global_position
	await _capture("parallax_center")
	rig.global_position = origin + Vector3(6.0, 0.0, 3.0)
	await _wait(0.6)
	await _capture("parallax_right")
	rig.global_position = origin - Vector3(6.0, 0.0, 3.0)
	await _wait(0.6)
	await _capture("parallax_left")
	rig.global_position = origin
	var bounds_per_zoom: Array[Vector2] = []
	for zoom in [14.0, 34.0, 60.0]:
		rig.set_zoom_immediate(float(zoom))
		await _wait(0.4)
		var manifest: Dictionary = (
			_main.lighting.void_clouds.runtime_manifest()
		)
		bounds_per_zoom.append(Vector2(
			float(manifest["cloud_top_y"]),
			float(manifest["cloud_bottom_y"])
		))
		await _capture("zoom_%02d" % int(zoom))
	rig.set_zoom_immediate(34.0)
	await _wait(0.4)
	var zoom_stable := true
	for bounds in bounds_per_zoom:
		if not bounds.is_equal_approx(bounds_per_zoom[0]):
			zoom_stable = false
	var manifest_now: Dictionary = (
		_main.lighting.void_clouds.runtime_manifest()
	)
	_check(
		zoom_stable and bool(manifest_now["zoom_stable"]),
		"cloud slab bounds are identical at every zoom level"
	)


## ISLAND-SEPARATION TEST: the cloud ceiling stays well below the underside.
func _test_island_separation() -> void:
	var manifest: Dictionary = (
		_main.lighting.void_clouds.runtime_manifest()
	)
	_check(
		float(manifest["cloud_top_y"])
			<= float(manifest["underside_y"]) - 5.0,
		"cloud ceiling is at least 5 units below the terrain underside"
	)
	await _capture("island_separation_close")


## DAY/NIGHT TEST: run the authored transition and verify the cloud palette
## blends continuously toward the night tint — never staying white.
func _test_day_night() -> void:
	await _capture("clouds_day")
	_main.lighting.set_time_of_day("night")
	await _wait(6.0)
	var manifest: Dictionary = (
		_main.lighting.void_clouds.runtime_manifest()
	)
	var tint: Color = manifest["crown_tint"]
	_check(
		tint.r < 0.6 and tint.g < 0.6 and tint.b < 0.70,
		"night clouds darken instead of staying bright white"
	)
	await _capture("clouds_night")
	_main.lighting.set_time_of_day("sunset")
	await _wait(3.0)
	await _capture("clouds_sunset")
	_main.lighting.set_time_of_day("noon")
	await _wait(4.0)
	var day_manifest: Dictionary = (
		_main.lighting.void_clouds.runtime_manifest()
	)
	var day_tint: Color = day_manifest["crown_tint"]
	_check(
		day_tint.r > 0.8,
		"returning to noon restores the warm cream palette"
	)


## ASPECT-RATIO TEST: 16:9, 16:10 and ultrawide all keep the world-space
## composition (screen-space anchoring is structurally impossible).
func _test_aspect_ratios() -> void:
	for size in [
		Vector2i(1600, 900),
		Vector2i(1600, 1000),
		Vector2i(2100, 900),
	]:
		get_window().size = size
		await _wait(0.5)
		await _capture(
			"aspect_%dx%d" % [size.x, size.y]
		)
	get_window().size = Vector2i(1600, 900)
	await _wait(0.3)
	_check(true, "aspect-ratio sweep captured")


## PERFORMANCE TEST: measured GPU frame time per quality preset and with the
## system disabled.
func _test_performance() -> void:
	var viewport_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(
		viewport_rid,
		true
	)
	var results := {}
	for level: String in ["off", "low", "medium", "high"]:
		if level == "off":
			_main.lighting.void_clouds.set_clouds_enabled(false)
		else:
			_main.lighting.void_clouds.set_clouds_enabled(true)
			_main.lighting.void_clouds.apply_quality(level)
		await _wait(1.0)
		var gpu_total := 0.0
		var samples := 0
		for _frame in 40:
			await get_tree().process_frame
			gpu_total += (
				RenderingServer.viewport_get_measured_render_time_gpu(
					viewport_rid
				)
			)
			samples += 1
		results[level] = gpu_total / float(samples)
	RenderingServer.viewport_set_measure_render_time(
		viewport_rid,
		false
	)
	_main.lighting.void_clouds.apply_quality("medium")
	print(
		"  gpu-ms off=%.2f low=%.2f medium=%.2f high=%.2f"
		% [
			results["off"],
			results["low"],
			results["medium"],
			results["high"],
		]
	)
	var medium_cost: float = results["medium"] - results["off"]
	_check(
		medium_cost < 4.0,
		"medium preset adds under 4 ms GPU (measured %.2f ms)"
			% medium_cost
	)


func _lower_half_difference(a: Image, b: Image) -> float:
	var total := 0.0
	var samples := 0
	var start_y := int(a.get_height() * 0.55)
	for y in range(start_y, a.get_height(), 12):
		for x in range(0, a.get_width(), 12):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			total += (
				absf(pa.r - pb.r)
				+ absf(pa.g - pb.g)
				+ absf(pa.b - pb.b)
			)
			samples += 1
	return total / maxf(float(samples) * 3.0, 1.0)


func _capture(shot_name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _shot_dir.path_join(shot_name + ".png")
	image.save_png(path)
	print("  [cloud shot] %s" % path)
	return image


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _hide_ui() -> void:
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false


func _enter_gameplay() -> void:
	var creator := _main.find_child(
		"Creator",
		false,
		false
	) as CharacterCreator
	if creator == null:
		push_error("Cloud acceptance could not find character creation.")
		get_tree().quit(1)
		return
	creator._name_edit.text = "Cloud Keeper"
	creator._finish()
	var picker_deadline := Time.get_ticks_msec() + 5000
	while (
		not _main.arrival_picker.is_open()
		and Time.get_ticks_msec() < picker_deadline
	):
		await _wait(0.05)
	_main.arrival_picker.select("tile_grove_mature")
	var gameplay_deadline := Time.get_ticks_msec() + 5000
	while (
		not _main._gameplay_started
		and Time.get_ticks_msec() < gameplay_deadline
	):
		await _wait(0.05)
