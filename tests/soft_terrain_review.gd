extends Node
## Real-scene visual QA for soft-terrain grounding and footprint persistence.
## Captures one clean gameplay frame per responsive surface.

const REVIEW_CASES := [
	{
		"tile_id": "tile_snowfield",
		"filename": "soft_terrain_snow.png",
		"keeper_name": "Snow Keeper",
	},
	{
		"tile_id": "tile_sand",
		"filename": "soft_terrain_sand.png",
		"keeper_name": "Dune Keeper",
	},
]

var _main: Main
var _output_dir := "res://artifacts/soft_terrain_review"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	for review_case: Dictionary in REVIEW_CASES:
		await _capture_case(review_case)
	print(
		"SOFT TERRAIN REVIEW CAPTURED - %s"
		% ProjectSettings.globalize_path(_output_dir)
	)
	get_tree().quit(0)


func _capture_case(review_case: Dictionary) -> void:
	var tile_id := String(review_case["tile_id"])
	var save_path := "user://soft_terrain_%s_review.json" % tile_id
	for path in [save_path, save_path + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = save_path
	add_child(_main)
	await get_tree().create_timer(0.5).timeout

	var creator := _main.find_child(
		"Creator", false, false
	) as CharacterCreator
	if creator == null:
		push_error("Soft terrain review could not find the character creator.")
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = String(review_case["keeper_name"])
	creator._finish()
	await get_tree().create_timer(1.1).timeout
	_main.arrival_picker.select(tile_id)
	await get_tree().create_timer(1.5).timeout

	# The onboarding-held water tile is irrelevant to this review. Leave the
	# stock transaction untouched and close its presentation cleanly.
	_main.placement.cancel_click()
	_main.placement.cancel_click()
	if not _main._hud_hidden:
		_main.toggle_all_hud()

	_main.camera_rig._yaw = 0.0
	_main.camera_rig._yaw_target = 0.0
	_main.camera_rig.rotation_degrees.y = 0.0
	_main.camera_rig.set_zoom_immediate(14.0)
	_main.player.global_position = (
		_main.core.grid.cell_to_world(Vector2i(-1, 0))
		+ Vector3(0.0, 0.28, 0.0)
	)
	_main.player.velocity = Vector3.ZERO
	_main.player.state = PlayerController.State.FREE
	_main.player.move_locked = false
	_main.camera_rig.global_position = _main.player.global_position
	await _settle_physics(20)

	# Walk across the complete soft patch through the real movement/animation
	# path, leaving alternating sole impressions behind.
	Input.action_press("move_right")
	await get_tree().create_timer(1.0).timeout
	Input.action_release("move_right")
	await _settle_physics(18)

	_main.camera_rig._yaw = 45.0
	_main.camera_rig._yaw_target = 45.0
	_main.camera_rig.rotation_degrees.y = 45.0
	_main.camera_rig.global_position = _main.player.global_position
	await _settle_physics(18)
	await _capture(String(review_case["filename"]))

	_main.free()
	_main = null
	for path in [save_path, save_path + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await get_tree().process_frame


func _settle_physics(frame_count: int) -> void:
	for _frame in frame_count:
		await get_tree().physics_frame


func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var error := get_viewport().get_texture().get_image().save_png(
		absolute_dir.path_join(filename)
	)
	if error != OK:
		push_error("Could not save soft terrain review: %s" % error_string(error))
	else:
		print("SOFT TERRAIN CAPTURE ", filename)
