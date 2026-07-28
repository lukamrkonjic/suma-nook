extends Node
## Captures the rebuilt wooden-plank tile through the actual main game scene.
## The review uses an isolated save and the debug showcase island so the tile
## is visible beside shipping tiles, structures, the player, lighting, and HUD.

const SAVE_PATH := "user://wooden_planks_ingame_review_save.json"

var _main: Main
var _output_dir := "res://artifacts/wooden_planks_ingame"


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

	var placed := _main.debug_build_mock_world()
	_main.renderer.rebuild_all()
	print("WOODEN PLANK REVIEW WORLD BUILT — %d structures" % placed)

	# Frame the plank patch at the south edge of the showcase while retaining
	# the adjacent sand, snow, road, water, props, player, and live game HUD.
	_main.player.global_position = (
		_main.core.grid.cell_to_world(Vector2i(-1, 2))
		+ Vector3(0.0, 0.05, 0.0)
	)
	_main.player.rotation.y = PI
	_main.camera_rig._yaw_target = 45.0
	_main.camera_rig.rotation_degrees.y = 45.0
	_main.camera_rig.set_zoom_immediate(18.0)
	_main.camera_rig.global_position = _main.player.global_position

	var plank_visual := _main.renderer.tile_node(Vector2i(-2, 3), 0)
	if plank_visual == null:
		push_error("The live review world did not instantiate its wooden-plank tile.")
		await _finish(1)
		return
	if plank_visual.find_child("planks_body", true, false) == null:
		push_error("The live wooden-plank tile is missing the standardized body.")
		await _finish(1)
		return
	if plank_visual.find_child("planks_cap", true, false) == null:
		push_error("The live wooden-plank tile is missing the plank-only cap.")
		await _finish(1)
		return

	await _settle(45)
	await _capture("wooden_planks_ingame.png")
	print(
		"WOODEN PLANK IN-GAME REVIEW CAPTURED — %s"
		% ProjectSettings.globalize_path(_output_dir)
	)
	await _finish(0)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("Wooden plank review could not find the character creator.")
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Plank Keeper"
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
		push_error("Could not save wooden plank in-game screenshot: %s" % error_string(error))


func _finish(exit_code: int) -> void:
	if is_instance_valid(_main):
		_main.free()
		_main = null
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await get_tree().process_frame
	get_tree().quit(exit_code)
