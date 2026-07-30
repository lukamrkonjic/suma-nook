extends Node
## Visual and behavior review for the fixed-budget high cloud layer.

const SAVE_PATH := "user://cloud_capture_save.json"

var _main: Main
var _output_dir := "res://artifacts/cloud_review"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	await _enter_gameplay()
	_main.debug_build_mock_world()
	_main.player.global_position = Vector3.ZERO
	_main.camera_rig.global_position = Vector3.ZERO
	_hide_ui()
	_main.lighting.set_weather("day")
	await _settle(24)

	_main.camera_rig.set_zoom_immediate(24.0)
	await _settle(18)
	await _save_viewport("clouds_close_clear.png")

	_main.camera_rig.set_zoom_immediate(52.0)
	await _settle(24)
	await _save_viewport("clouds_wide_gameplay.png")

	_main.camera_rig.set_zoom_immediate(70.0)
	await _settle(30)
	_main.clouds.set_process(false)
	await _save_viewport("clouds_far_shadows_on.png")

	_main.clouds.set_shadows_enabled(false)
	await _settle(12)
	await _save_viewport("clouds_far_shadows_off.png")

	var manifest: Dictionary = _main.clouds.runtime_manifest()
	if (
		int(manifest["clouds"]) <= 0
		or int(manifest["visible_volumes"]) <= 0
		or int(manifest["shadow_layers"]) <= 0
	):
		push_error("Cloud review did not populate its volume and shadow layer.")
		get_tree().quit(1)
		return
	if bool(manifest["shadows_enabled"]):
		push_error("Cloud shadow toggle did not disable the shadow pass.")
		get_tree().quit(1)
		return
	print("CLOUD_CAPTURE_MANIFEST ", JSON.stringify(manifest))
	print("CLOUD CAPTURED — %s" % _output_dir)
	get_tree().quit(0)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("Cloud capture could not find the character creator.")
		get_tree().quit(1)
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Cloud Keeper"
	creator._finish()
	await get_tree().create_timer(0.7).timeout
	if not _main._gameplay_started:
		push_error("Cloud capture could not enter gameplay.")
		get_tree().quit(1)


func _hide_ui() -> void:
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await get_tree().process_frame


func _save_viewport(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _output_dir.path_join(file_name)
	var image := get_viewport().get_texture().get_image()
	GGCaptureEncode.encode_srgb(image)
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save cloud capture %s (error %d)." % [path, error])
	else:
		print("  [cloud shot] %s" % path)
