extends Node
## Captures the modular default player through the actual main game: idle and
## walking from the real gameplay camera, plus grounding diagnostics.

const SAVE_PATH := "user://player_ingame_review_save.json"

var _main: Main
var _output_dir := "res://artifacts/player_ingame"


func _ready() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	await _enter_gameplay()

	_main.debug_build_mock_world()
	_main.renderer.rebuild_all()
	_main.player.global_position = (
		_main.core.grid.cell_to_world(Vector2i(-1, 2))
		+ Vector3(0.0, 0.05, 0.0)
	)
	_main.player.rotation.y = PI
	_main.camera_rig._yaw_target = 45.0
	_main.camera_rig.rotation_degrees.y = 45.0
	_main.camera_rig.set_zoom_immediate(18.0)
	_main.camera_rig.global_position = _main.player.global_position

	await _settle(60)
	_print_grounding()
	await _capture("player_ingame_idle.png")
	await _settle(75)
	await _capture("player_ingame_idle_late.png")

	Input.action_press("move_down")
	await _settle(30)
	await _capture("player_ingame_walk.png")
	Input.action_release("move_down")
	await _settle(30)
	_print_grounding()
	await _capture("player_ingame_settled.png")
	print("PLAYER_INGAME_REVIEW_DONE")
	await _finish(0)


func _print_grounding() -> void:
	var player := _main.player
	var visual := _main.player_visual
	var skeleton: Skeleton3D = visual._skeleton
	var toe_index := skeleton.find_bone("mixamorigLeftToeBase")
	var toe_world := (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(toe_index).origin
	)
	print("INGAME_GROUND player_y=", player.global_position.y)
	print("INGAME_GROUND body_local=", visual._body.position)
	print("INGAME_GROUND toe_world_y=", toe_world.y)
	print(
		"INGAME_GROUND head_attachment=",
		visual.find_child("HeadAttachment", true, false) != null
	)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("Player review could not find the character creator.")
		return
	creator.profile.skin_index = 1
	creator.profile.hair_style = 0
	creator.profile.hair_color_index = 0
	creator._preview()
	creator._name_edit.text = "Suma Keeper"
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
		push_error(
			"Could not save player in-game screenshot: %s" % error_string(error)
		)
	else:
		print("PLAYER_INGAME_CAPTURE ", filename)


func _finish(exit_code: int) -> void:
	if is_instance_valid(_main):
		_main.free()
		_main = null
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await get_tree().process_frame
	get_tree().quit(exit_code)
