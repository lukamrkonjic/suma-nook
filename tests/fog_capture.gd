extends Node
## Focused visual regression for world-space mist. It captures the same
## profile with and without layer density, then a night/light interaction
## frame after sweeping the player through the wisps.

const SAVE_PATH := "user://fog_capture_save.json"

var _main: Main
var _output_dir := "res://artifacts/fog_review"


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
	_main.camera_rig.set_zoom_immediate(36.0)
	_hide_ui()
	await _settle(30)

	_main.lighting.set_weather("mist")
	await _settle_time(0.4)
	await _save_viewport("mist_layers_on.png")
	await _settle_time(3.0)
	await _save_viewport("mist_flow_later.png")

	var mist := _main.lighting.mist_profile
	var authored_density := mist.ground_fog_density
	mist.ground_fog_density = 0.0
	_main.lighting.apply_profile(mist)
	await _settle(12)
	await _save_viewport("mist_layers_off_control.png")
	mist.ground_fog_density = authored_density
	_main.lighting.apply_profile(mist)
	await _settle(8)

	var start := _main.player.global_position
	for index in 18:
		_main.player.global_position = start + Vector3(
			(float(index) - 9.0) * 0.16,
			0.0,
			(float(index) - 9.0) * 0.08
		)
		await get_tree().create_timer(0.055).timeout
	_main.lighting.set_time_of_day("night")
	await _settle_time(0.8)
	await _save_viewport("fog_night_actor_wake.png")

	if not _verify_jump_does_not_move_mist():
		get_tree().quit(1)
		return
	var manifest: Dictionary = _main.lighting.runtime_manifest()["fog"]
	print("FOG_CAPTURE_MANIFEST ", JSON.stringify(manifest))
	print("FOG CAPTURED — %s" % _output_dir)
	get_tree().quit(0)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("Fog capture could not find the character creator.")
		get_tree().quit(1)
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Fog Keeper"
	creator._finish()
	await get_tree().create_timer(0.7).timeout
	if not _main._gameplay_started:
		push_error("Fog capture could not enter gameplay.")
		get_tree().quit(1)


func _hide_ui() -> void:
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	_main.camera_rig.set_process(false)


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await get_tree().process_frame


func _settle_time(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await _settle(8)


func _save_viewport(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _output_dir.path_join(file_name)
	var image := get_viewport().get_texture().get_image()
	GGCaptureEncode.encode_srgb(image)
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save fog capture %s (error %d)." % [path, error])
	else:
		print("  [fog shot] %s" % path)


func _verify_jump_does_not_move_mist() -> bool:
	var fog: CozyGroundFog = _main.lighting._ground_fog
	var original_position := _main.player.global_position
	var original_velocity := _main.player.velocity
	var ground_height := fog.global_position.y
	_main.player.global_position.y += 3.0
	_main.player.velocity.y = 4.0
	fog._update_anchor_and_player()
	var jump_layer_height := fog.global_position.y
	var stayed_grounded := is_equal_approx(jump_layer_height, ground_height)
	_main.player.global_position = original_position
	_main.player.velocity = original_velocity
	fog._update_anchor_and_player()
	if not stayed_grounded:
		push_error(
			"Mist followed a jumping actor from %.3f to %.3f."
			% [ground_height, jump_layer_height]
		)
		return false
	print("  [fog regression] jump keeps layer Y at %.3f" % ground_height)
	return true
