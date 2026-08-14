extends Node
## Captures one asset as the game actually renders it.
##
## Blender review renders answered the wrong question. They shade the glb with
## Blender's own rules, and Godot's differ in exactly the way that mattered: with
## no NORMAL attribute in the file Blender computed flat faces while Godot
## generated averaged ones, so a cabinet that looked crisply facetted in review
## arrived in game rounded and detail-free. The only honest check is the engine's
## own output.
##
## Captures at smoothing 0.0 and at the game-wide default, because the point of
## the authored normals is that the two differ.

const SAVE_PATH := "user://asset_ingame_capture_save.json"
var _asset_id := "prop_gift_wardrobe"

var _main: Main
var _output_dir := "res://artifacts/asset_capture"
## Applied before the model is built. Setting it afterwards changes nothing --
## the studio keeps the mesh it already made -- so each value needs its own run.
var _smoothing := 0.0


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
		if argument.begins_with("--asset="):
			_asset_id = argument.trim_prefix("--asset=")
		if argument.begins_with("--smoothing="):
			_smoothing = float(argument.trim_prefix("--smoothing="))
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	_main.assets.edits.set_default_model_smoothing(_smoothing)
	await _enter_gameplay()
	_main.open_asset_viewer()
	await _settle(20)
	if _main.asset_viewer == null or not _main.asset_viewer.is_open():
		push_error("Asset Viewer did not open.")
		await _finish(1)
		return

	_main.asset_viewer.select_content(_asset_id)
	_main.asset_viewer.set_weather_preset("day")
	_main.asset_viewer.set_light_preset("noon")
	await _settle(45)

	# The prompt re-opens over the studio, and it covers the model.
	if _main.collection_vibe_panel != null:
		_main.collection_vibe_panel.hide()
	await _settle(2)
	await _capture("%s_smoothing_%d.png" % [_asset_id, roundi(_smoothing * 100.0)])
	await _finish(0)


func _enter_gameplay() -> void:
	var creator := _main.character_creator
	if creator == null:
		creator = _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("Could not find the character creator.")
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Asset Keeper"
	creator._finish()
	await get_tree().create_timer(0.7).timeout
	# A fresh save opens on the collection prompt, which sits over the whole
	# screen and would be all the capture showed.
	if _main.collection_vibe_panel != null and _main.collection_vibe_panel.is_open():
		_main.collection_vibe_panel._choose("homestead")
		await get_tree().create_timer(0.5).timeout


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
		push_error("Could not save screenshot: %s" % error_string(error))


func _finish(exit_code: int) -> void:
	if is_instance_valid(_main):
		_main.free()
		_main = null
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	get_tree().paused = false
	get_tree().quit(exit_code)
