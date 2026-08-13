extends Node
## Captures the reworked props through the running game's own material,
## lighting, and weather stack.
##
## Blender contact sheets prove the mesh changed; they cannot prove what the
## game draws, because runtime smoothing and MaterialLibrary rebinding both
## happen after export. Only an in-engine capture settles that.
##
## NOTE: get_viewport().get_texture().get_image() returns the buffer raw, so
## these PNGs read darker than the screen. Judge shading and silhouette here,
## never absolute brightness -- see docs and tests/gg_capture_encode.gd.

const SAVE_PATH := "user://prop_style_review_save.json"
const SUBJECTS := [
	"struct_shrooms",
	"struct_fir",
	"struct_stone_pine",
	"struct_leafy_bush",
]

var _main: Main
var _output_dir := "res://artifacts/prop_style_review"


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

	await _settle(60)
	for content_id in SUBJECTS:
		## Selecting once only swaps the category on a cold viewer; the stage
		## rebuilds on the following selection, so ask twice and settle between.
		_main.asset_viewer.select_content(content_id)
		await _settle(30)
		_main.asset_viewer.select_content(content_id)
		_main.asset_viewer.set_weather_preset("day")
		_main.asset_viewer.set_light_preset("noon")
		await _settle(60)
		await _capture("%s.png" % content_id)

	_main.asset_viewer.close()
	await _settle(5)
	print(
		"PROP STYLE REVIEW CAPTURED — %s"
		% ProjectSettings.globalize_path(_output_dir)
	)
	await _finish(0)


func _enter_gameplay() -> void:
	## The blank-canvas start replaced the character creator with a collection
	## prompt, and it covers the Asset Studio viewport until it is answered.
	for _attempt in 40:
		if _main.collection_vibe_panel != null and _main.collection_vibe_panel.is_open():
			_main.collection_vibe_panel._choose("meadow")
			await get_tree().create_timer(0.7).timeout
			return
		await get_tree().process_frame
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
		push_error("Could not save review screenshot: %s" % error_string(error))


func _finish(exit_code: int) -> void:
	if is_instance_valid(_main):
		_main.free()
		_main = null
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	get_tree().paused = false
	get_tree().quit(exit_code)
