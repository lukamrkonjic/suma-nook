extends Node
## Captures the GG-exact lighting pipeline from settled gameplay.
## Run:
##   godot --path . tests/gg_exact_capture.tscn --resolution 1920x1080 \
##     --disable-vsync -- --shot-dir=<absolute folder>

const SAVE_PATH := "user://gg_exact_capture_save.json"

var _main: Main
var _output_dir := "res://artifacts/gg_exact"


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
	_hide_ui()
	# The admin showcase island: every tile family, stacked elevation, water
	# wrap, and a broad structure spread — a GG-complexity scene. Pull the
	# camera to GG's inspected diorama distance so the whole island frames.
	_main.debug_build_mock_world()
	_main.camera_rig._size_target = 42.0
	_main.camera_rig.camera.position.z = 42.0
	await _settle(30)
	await _save_viewport("gg_exact_noon.png")
	_main.lighting.set_time_of_day("night")
	await _settle_time(0.8)
	await _save_viewport("gg_exact_night.png")
	_main.lighting.set_time_of_day("sunset")
	await _settle_time(0.8)
	await _save_viewport("gg_exact_sunset.png")
	_main.lighting.set_time_of_day("noon")
	await _settle_time(0.8)
	_main.lighting.set_weather("mist")
	await _settle_time(1.8)
	await _save_viewport("gg_exact_mist_regression.png")
	print("GG EXACT CAPTURED — %s" % _output_dir)
	_main.free()
	_main = null
	await get_tree().process_frame
	get_tree().quit(0)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("GG capture could not find the character creator.")
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
		push_error("GG capture could not enter gameplay.")
		get_tree().quit(1)


func _hide_ui() -> void:
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	_main.camera_rig.set_process(false)


func _settle(frame_count: int) -> void:
	for frame in frame_count:
		await get_tree().process_frame


## Lighting transitions run on wall-clock tweens; with vsync disabled a frame
## count elapses much faster than the tween, so wait on time then let the
## renderer settle a few frames.
func _settle_time(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await _settle(8)


func _save_viewport(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _output_dir.path_join(file_name)
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save GG capture %s (error %d)." % [path, error])
	else:
		print("  [gg shot] %s" % path)
