extends Node
## Visual/interaction proof for the reusable in-game Asset Viewer.

const SAVE_PATH := "user://asset_viewer_review_save.json"

var _main: Main
var _output_dir := "res://artifacts/asset_viewer"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	await _enter_gameplay()
	_main.open_asset_viewer()
	await _settle(20)
	if _main.asset_viewer == null or not _main.asset_viewer.is_open():
		push_error("Asset Viewer did not open from the running game.")
		await _finish(1)
		return

	_main.asset_viewer.select_content("tile_grass")
	_main.asset_viewer.set_weather_preset("day")
	_main.asset_viewer.set_light_preset("noon")
	await _settle(45)
	await _capture("asset_viewer_tile_grass_v2_corrected_day.png")

	_main.asset_viewer.select_content("tile_sand")
	_main.asset_viewer.set_weather_preset("day")
	_main.asset_viewer.set_light_preset("noon")
	await _settle(45)
	await _capture("asset_viewer_tile_sand_day.png")

	_main.asset_viewer.select_content("tile_concrete_brutalist")
	_main.asset_viewer.set_weather_preset("day")
	_main.asset_viewer.set_light_preset("noon")
	await _settle(45)
	await _capture("asset_viewer_tile_concrete_brutalist_day.png")

	_main.asset_viewer.select_content("tile_snowfield")
	_main.asset_viewer.set_weather_preset("day")
	_main.asset_viewer.set_light_preset("noon")
	await _settle(45)
	await _capture("asset_viewer_tile_snowfield_day.png")

	_main.asset_viewer.select_content("struct_firepit_polished")
	_main.asset_viewer.set_weather_preset("rain")
	_main.asset_viewer.set_light_preset("sunset")
	await _settle(70)
	await _capture("asset_viewer_firepit_rain.png")

	_main.asset_viewer.close()
	await _settle(5)
	if get_tree().paused or not _main.hud.visible:
		push_error("Asset Viewer did not restore the running game.")
		await _finish(1)
		return
	print(
		"ASSET VIEWER REVIEW CAPTURED — %s"
		% ProjectSettings.globalize_path(_output_dir)
	)
	await _finish(0)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("Asset Viewer review could not find the character creator.")
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Asset Keeper"
	creator._finish()
	await get_tree().create_timer(0.7).timeout


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await get_tree().process_frame


func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var error := get_viewport().get_texture().get_image().save_png(
		absolute_dir.path_join(filename)
	)
	if error != OK:
		push_error("Could not save Asset Viewer screenshot: %s" % error_string(error))


func _finish(exit_code: int) -> void:
	if is_instance_valid(_main):
		_main.free()
		_main = null
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	get_tree().paused = false
	get_tree().quit(exit_code)
