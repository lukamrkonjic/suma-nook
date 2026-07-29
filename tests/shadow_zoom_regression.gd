extends Node
## Ensures camera zoom never mutates the directional shadow projection.

const SAVE_PATH := "user://shadow_zoom_regression_save.json"

var _main: Main
var _output_dir := "res://artifacts/shadow_zoom_review"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	await _enter_gameplay()
	_main.debug_build_mock_world()
	_main.player.global_position = Vector3.ZERO
	_main.camera_rig.global_position = Vector3.ZERO
	_hide_ui()
	_main.lighting.set_weather("day")
	await _settle(30)

	for weather in ["day", "mist", "rain"]:
		_main.lighting.set_weather(weather)
		await _settle(3)
		if not _verify_zoom_invariant(weather):
			get_tree().quit(1)
			return

	_main.lighting.set_weather("day")
	_main.camera_rig.set_zoom_immediate(20.0)
	await _settle(12)
	await _save_viewport("shadow_zoom_close.png")
	if not await _smooth_zoom_and_verify(70.0, 100):
		get_tree().quit(1)
		return
	await _save_viewport("shadow_zoom_far.png")
	if not await _smooth_zoom_and_verify(20.0, 100):
		get_tree().quit(1)
		return

	var light: Dictionary = _main.lighting.runtime_manifest()["directional_light"]
	print("SHADOW_ZOOM_MANIFEST ", JSON.stringify(light))
	print("SHADOW ZOOM REGRESSION PASSED — %s" % _output_dir)
	get_tree().quit(0)


func _verify_zoom_invariant(label: String) -> bool:
	var before := _shadow_distance()
	for distance in [14.0, 20.0, 32.0, 42.0, 70.0, 14.0]:
		_main.lighting.set_camera_shadow_distance(distance)
		var after := _shadow_distance()
		if not is_equal_approx(before, after):
			push_error(
				"%s shadow envelope changed during zoom: %.3f -> %.3f."
				% [label, before, after]
			)
			return false
	print("  [shadow regression] %s holds envelope %.1f" % [label, before])
	return true


func _smooth_zoom_and_verify(target_distance: float, frames: int) -> bool:
	var expected := _shadow_distance()
	_main.camera_rig._size_target = target_distance
	_main.camera_rig.zoom_changed.emit(target_distance)
	for _frame in frames:
		await get_tree().process_frame
		if not is_equal_approx(_shadow_distance(), expected):
			push_error(
				"Shadow envelope changed while camera eased toward %.1f."
				% target_distance
			)
			return false
	return true


func _shadow_distance() -> float:
	return float(
		_main.lighting.runtime_manifest()["directional_light"]["shadow_max_distance"]
	)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("Shadow regression could not find the character creator.")
		get_tree().quit(1)
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Shadow Keeper"
	creator._finish()
	await get_tree().create_timer(0.7).timeout
	if not _main._gameplay_started:
		push_error("Shadow regression could not enter gameplay.")
		get_tree().quit(1)


func _hide_ui() -> void:
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await get_tree().process_frame


func _save_viewport(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _output_dir.path_join(file_name)
	var image := get_viewport().get_texture().get_image()
	GGCaptureEncode.encode_srgb(image)
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save shadow capture %s (error %d)." % [path, error])
	else:
		print("  [shadow shot] %s" % path)
