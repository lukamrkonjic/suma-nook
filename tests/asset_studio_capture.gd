extends Node
## Produces a visual review frame of Asset Studio inside the real game.

const SAVE_PATH := "user://asset_studio_capture_save.json"

var _main: Main
var _content_id := "tile_grass"
var _smoothing := -1.0
var _model_scale := -1.0
var _color_text := ""
var _open_picker := false
var _palette_family_text := ""
var _capture_path := "user://asset_studio_review.png"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--asset="):
			_content_id = argument.trim_prefix("--asset=")
		elif argument.begins_with("--smoothing="):
			_smoothing = float(argument.trim_prefix("--smoothing="))
		elif argument.begins_with("--scale="):
			_model_scale = float(argument.trim_prefix("--scale="))
		elif argument.begins_with("--color="):
			_color_text = argument.trim_prefix("--color=")
		elif argument == "--open-picker":
			_open_picker = true
		elif argument.begins_with("--palette-family="):
			_palette_family_text = argument.trim_prefix(
				"--palette-family="
			)
		elif argument.begins_with("--capture-name="):
			_capture_path = "user://" + argument.trim_prefix(
				"--capture-name="
			)
	_remove_test_saves()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("Asset Studio capture could not enter gameplay.")
		await _finish(1)
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Asset Keeper"
	creator._finish()
	await get_tree().create_timer(0.7).timeout
	_main.open_asset_viewer()
	_main.asset_viewer.select_content(_content_id)
	if _smoothing >= 0.0:
		_main.asset_viewer.set_surface_smoothing(_smoothing)
	if _model_scale >= 0.0:
		_main.asset_viewer.set_model_scale(_model_scale)
	if not _color_text.is_empty():
		var picker := _main.asset_viewer.find_child(
			"AssetStudioMaterialColor",
			true,
			false
		) as ColorPickerButton
		if picker != null:
			var color := Color.from_string(_color_text, Color.WHITE)
			picker.color = color
			picker.color_changed.emit(color)
	if not _palette_family_text.is_empty():
		var family := _main.asset_viewer.find_child(
			"AssetStudioPaletteFamily",
			true,
			false
		) as OptionButton
		if family != null:
			for index in family.item_count:
				if family.get_item_text(index).to_lower().contains(
					_palette_family_text.to_lower()
				):
					family.select(index)
					family.item_selected.emit(index)
					break
	_main.asset_viewer.set_weather_preset("day")
	_main.asset_viewer.set_light_preset("noon")
	for _frame in 30:
		await get_tree().process_frame
	if _open_picker:
		var picker_button := _main.asset_viewer.find_child(
			"AssetStudioMaterialColor",
			true,
			false
		) as ColorPickerButton
		if picker_button != null:
			picker_button.get_popup().popup_centered(Vector2i(620, 760))
			for _frame in 4:
				await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var capture_image := get_viewport().get_texture().get_image()
	var error := capture_image.save_png(
		ProjectSettings.globalize_path(_capture_path)
	)
	capture_image = null
	if error != OK:
		push_error("Asset Studio capture failed: %s" % error_string(error))
		await _finish(1)
		return
	print(
		"ASSET STUDIO CAPTURED: %s"
		% ProjectSettings.globalize_path(_capture_path)
	)
	await _finish(0)


func _finish(exit_code: int) -> void:
	if is_instance_valid(_main):
		_main.queue_free()
		_main = null
	await get_tree().process_frame
	await get_tree().process_frame
	_remove_test_saves()
	get_tree().paused = false
	get_tree().quit(exit_code)


func _remove_test_saves() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
