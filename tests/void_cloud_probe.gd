extends Node
## Temporary visual check: boots the real game and captures the cloudscape
## and sky at gameplay zoom across every time of day.

const SAVE_PATH := "user://void_cloud_probe_save.json"

var _main: Main
var _dir := "res://artifacts/void_clouds"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_dir = argument.trim_prefix("--shot-dir=")
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(_dir)
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
	var creator := _main.find_child("Creator", false, false)
	creator._name_edit.text = "Probe"
	creator._finish()
	while not _main.arrival_picker.is_open():
		await _wait(0.05)
	_main.arrival_picker.select("tile_grove_mature")
	while not _main._gameplay_started:
		await _wait(0.05)
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	_main.camera_rig.set_zoom_immediate(34.0)
	await _wait(4.0)
	await _shot("sky_noon")
	for time_id in ["morning", "sunset", "night"]:
		_main.lighting.set_time_of_day(time_id)
		await _wait(6.0)
		await _shot("sky_%s" % time_id)
	print("PROBE DONE")
	get_tree().quit(0)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_dir.path_join(shot_name + ".png"))
	print("PROBE_SHOT ", shot_name)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
