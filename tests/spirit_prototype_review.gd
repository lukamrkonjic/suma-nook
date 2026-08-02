extends Node
## Focused visual review for the lightweight physics-driven player.

const SAVE_PATH := "user://spirit_prototype_review_save.json"

var _main: Main
var _output_dir := "res://artifacts/spirit_prototype_review"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	_remove_test_saves()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	await _enter_gameplay()
	if not _main._gameplay_started:
		get_tree().quit(1)
		return
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	_main.player.global_position = _main.core.grid.cell_to_world(Vector2i.ZERO)
	_main.player.velocity = Vector3.ZERO
	if is_instance_valid(_main.pigeon_mascot):
		_main.pigeon_mascot.global_position = Vector3(5.0, 0.0, 5.0)
	_main.camera_rig.global_position = _main.player.global_position
	_main.camera_rig.set_zoom_immediate(8.5)
	await _settle(30)
	await _capture("spirit_idle.png")

	var prototype := _main.player_visual.find_child(
		"SpiritPhysicsPrototype", false, false
	)
	if prototype != null:
		prototype.set("_idle_time", 6.1)
	await get_tree().create_timer(0.45).timeout
	await _capture("spirit_wave.png")

	Input.action_press("move_right")
	Input.action_press("sprint")
	await get_tree().create_timer(0.10).timeout
	await _capture("spirit_run_a.png")
	await get_tree().create_timer(0.10).timeout
	await _capture("spirit_run_b.png")
	await get_tree().create_timer(0.10).timeout
	await _capture("spirit_run.png")
	Input.action_release("sprint")
	Input.action_release("move_right")
	await _finish(0)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("Spirit review could not find character creation.")
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Pocket Spirit"
	creator._finish()
	await get_tree().create_timer(1.1).timeout
	if _main.arrival_picker.is_open():
		_main.arrival_picker.select("tile_sand")
		await get_tree().create_timer(1.5).timeout
	if not _main._gameplay_started:
		push_error(
			"Spirit review could not enter gameplay (picker open: %s)."
			% _main.arrival_picker.is_open()
		)


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	GGCaptureEncode.encode_srgb(image)
	var path := _output_dir.path_join(file_name)
	var error := image.save_png(path)
	if error != OK:
		push_error("Spirit review could not save %s: %s" % [path, error_string(error)])
	else:
		print("SPIRIT REVIEW SHOT: %s" % path)


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await get_tree().process_frame


func _finish(exit_code: int) -> void:
	_remove_test_saves()
	get_tree().quit(exit_code)


func _remove_test_saves() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
