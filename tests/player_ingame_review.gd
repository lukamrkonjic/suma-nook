extends Node
## Captures the modular default player through the actual main game: idle,
## walking, and every authored gameplay action from the real gameplay camera.
## Action clips are paused and scrubbed deterministically so the full garment
## deformation envelope is reviewed instead of whichever pose happens to land
## on a wall-clock screenshot.

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

	_main.toggle_all_hud()
	_main.camera_rig.set_zoom_immediate(7.5)
	_main.camera_rig.global_position = _main.player.global_position
	await _settle(8)
	await _capture_action_sequence(
		"chop",
		[0.0, 0.16, 0.32, 0.48, 0.64, 0.80, 0.98]
	)
	await _capture_action_sequence(
		"fish_cast",
		[0.0, 0.16, 0.32, 0.48, 0.64, 0.80, 0.98]
	)
	await _capture_action_sequence(
		"fish_wait",
		[0.0, 0.16, 0.32, 0.48, 0.64, 0.80, 0.98]
	)
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
	creator.profile.skin_index = 0
	creator.profile.hair_style = 0
	creator.profile.hair_color_index = 0
	creator._preview()
	creator._name_edit.text = "Suma Keeper"
	creator._finish()
	await get_tree().create_timer(0.7).timeout


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await get_tree().process_frame


func _capture_action_sequence(action: String, samples: Array) -> void:
	var visual := _main.player_visual
	var animation_player: AnimationPlayer = visual._animation_player
	visual.play(action)
	await get_tree().process_frame
	if not animation_player.has_animation(action):
		push_error("Player review could not find authored action: %s" % action)
		return
	var animation := animation_player.get_animation(action)
	# The production call above intentionally blends into an authored action.
	# Remove that blend only for deterministic scrubbing; otherwise pausing on
	# the next frame freezes the previous locomotion clip at blend weight 1.
	animation_player.play(action, 0.0, 1.0)
	animation_player.pause()
	for sample_index in samples.size():
		var normalized_time: float = float(samples[sample_index])
		animation_player.seek(animation.length * normalized_time, true)
		await _settle(1)
		await _capture(
			"player_ingame_%s_%02d.png" % [action, sample_index]
		)
	visual.play("idle")
	await _settle(8)


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
