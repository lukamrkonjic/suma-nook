extends Node
## Real-game visual review for the procedural void clouds. Captures matching
## on/off frames at normal and maximum gameplay zoom so cloud contribution is
## never confused with the background gradient.

const SAVE_PATH := "user://void_cloud_visual_capture_save.json"

var _main: Main
var _output_dir := "res://artifacts/void_cloud_visual"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1600, 900)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await _wait(0.6)
	await _enter_gameplay()
	_main.debug_build_mock_world()
	_main.player.global_position = Vector3.ZERO
	_main.camera_rig.global_position = Vector3.ZERO
	_hide_ui()
	_main.lighting.set_weather("day")
	_main.lighting.set_time_of_day("noon")
	await _wait(3.0)

	for zoom in [24.0, 37.0, 52.0, 70.0]:
		_main.camera_rig.set_zoom_immediate(zoom)
		await _wait(0.8)
		_main.lighting.void_clouds.set_clouds_enabled(true)
		await _wait(0.3)
		await _capture("clouds_on_zoom_%02d" % int(zoom))
		_main.lighting.void_clouds.set_clouds_enabled(false)
		await _wait(0.2)
		await _capture("clouds_off_zoom_%02d" % int(zoom))
	_main.lighting.void_clouds.set_clouds_enabled(true)
	print("VOID CLOUD VISUAL CAPTURED — %s" % _output_dir)
	_main.queue_free()
	for _frame in 3:
		await get_tree().process_frame
	get_tree().quit(0)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Cloud Keeper"
	creator._finish()
	await _wait(0.8)


func _hide_ui() -> void:
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false


func _capture(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	GGCaptureEncode.encode_srgb(image)
	var path := _output_dir.path_join(shot_name + ".png")
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save %s (error %d)." % [path, error])
	else:
		print("  [cloud visual] %s" % path)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
