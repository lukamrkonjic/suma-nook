extends Node
## Captures the rebuilt source-derived sand tile through the actual main game.
## An isolated save and the debug showcase island keep the result reproducible.

const SAVE_PATH := "user://sand_tile_ingame_review_save.json"
const SAND_PATCH := [
	Vector2i(-2, 3),
	Vector2i(-1, 3),
	Vector2i(-2, 4),
	Vector2i(-1, 4),
]

var _main: Main
var _output_dir := "res://artifacts/sand_tile_ingame"


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
	for coord: Vector2i in SAND_PATCH:
		_main.core.grid.place_tile(coord, "tile_sand")
	_main.renderer.rebuild_all()
	print("SAND TILE REVIEW WORLD BUILT — %d structures" % placed)

	# The player stands just north of a 2x2 sand patch. The crate and campfire
	# remain on the patch while neighboring planks, grass, stone, snow, water,
	# structures, lighting, and the live HUD establish actual game context.
	_main.player.global_position = (
		_main.core.grid.cell_to_world(Vector2i(-1, 2))
		+ Vector3(0.0, 0.05, 0.0)
	)
	_main.player.rotation.y = PI
	_main.camera_rig._yaw_target = 45.0
	_main.camera_rig.rotation_degrees.y = 45.0
	_main.camera_rig.set_zoom_immediate(18.0)
	_main.camera_rig.global_position = _main.player.global_position

	var sand_visual := _main.renderer.tile_node(Vector2i(-2, 3), 0)
	if sand_visual == null:
		push_error("The live review world did not instantiate its sand tile.")
		await _finish(1)
		return
	var sand_body := sand_visual.find_child(
		"sand_body", true, false
	) as MeshInstance3D
	if sand_body == null:
		push_error("The live sand tile is missing the standardized body.")
		await _finish(1)
		return
	var sand_cap := sand_visual.find_child(
		"sand_cap", true, false
	) as MeshInstance3D
	if sand_cap == null:
		push_error("The live sand tile is missing the source-derived dune cap.")
		await _finish(1)
		return

	await _settle(45)
	await _capture("sand_tile_ingame.png")
	print(
		"SAND TILE IN-GAME REVIEW CAPTURED — %s"
		% ProjectSettings.globalize_path(_output_dir)
	)
	await _finish(0)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("Sand tile review could not find the character creator.")
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Dune Keeper"
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
		push_error("Could not save sand tile in-game screenshot: %s" % error_string(error))


func _finish(exit_code: int) -> void:
	if is_instance_valid(_main):
		_main.free()
		_main = null
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await get_tree().process_frame
	get_tree().quit(exit_code)
