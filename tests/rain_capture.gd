extends Node
## Visual and behavioral regression for the fixed-budget rain presentation.

const SAVE_PATH := "user://rain_capture_save.json"

var _main: Main
var _output_dir := "res://artifacts/rain_review"


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
	_main.camera_rig.set_zoom_immediate(26.0)
	_hide_ui()
	await _settle(30)

	_main.lighting.set_weather("rain")
	await _settle_time(1.0)
	await _save_viewport("rain_surface_idle.png")

	# Drive the real gameplay input path: this validates grounded detection,
	# alternating steps, expanding rings, and the moving-foot GPU emitter.
	Input.action_press("move_right")
	await get_tree().create_timer(0.9).timeout
	Input.action_release("move_right")
	await get_tree().create_timer(0.12).timeout
	var rain_surface: CozyRainSurface = _main.lighting._rain_surface
	if rain_surface.active_footstep_count() == 0:
		push_error("Real walking did not create any rain footstep ripples.")
		get_tree().quit(1)
		return
	print(
		"  [rain regression] real walking left %d live footstep ripples"
		% rain_surface.active_footstep_count()
	)
	await _save_viewport("rain_walking_interaction.png")

	var rain := _main.lighting.rain_profile
	var authored := [
		rain.rain_surface_wetness,
		rain.rain_puddle_amount,
		rain.rain_ripple_amount,
		rain.rain_walk_splash_amount,
	]
	rain.rain_surface_wetness = 0.0
	rain.rain_puddle_amount = 0.0
	rain.rain_ripple_amount = 0.0
	rain.rain_walk_splash_amount = 0.0
	_main.lighting.apply_profile(rain)
	await _settle(10)
	await _save_viewport("rain_streaks_only_control.png")
	rain.rain_surface_wetness = authored[0]
	rain.rain_puddle_amount = authored[1]
	rain.rain_ripple_amount = authored[2]
	rain.rain_walk_splash_amount = authored[3]
	_main.lighting.apply_profile(rain)
	await _settle(8)

	if not _verify_jump_keeps_surface_grounded():
		get_tree().quit(1)
		return
	print(
		"RAIN_CAPTURE_MANIFEST ",
		JSON.stringify(_main.lighting.runtime_manifest()["rain_surface"])
	)
	print("RAIN CAPTURED — %s" % _output_dir)
	get_tree().quit(0)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("Rain capture could not find the character creator.")
		get_tree().quit(1)
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Rain Keeper"
	creator._finish()
	await get_tree().create_timer(0.7).timeout
	if not _main._gameplay_started:
		push_error("Rain capture could not enter gameplay.")
		get_tree().quit(1)


func _hide_ui() -> void:
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	_main.camera_rig.set_process(false)


func _verify_jump_keeps_surface_grounded() -> bool:
	var rain_surface: CozyRainSurface = _main.lighting._rain_surface
	var original_position := _main.player.global_position
	var original_velocity := _main.player.velocity
	var ground_height := rain_surface.global_position.y
	_main.player.global_position.y += 3.0
	_main.player.velocity.y = 4.0
	rain_surface._update_ground_height()
	rain_surface._update_anchor()
	var jump_surface_height := rain_surface.global_position.y
	var stayed_grounded := is_equal_approx(jump_surface_height, ground_height)
	_main.player.global_position = original_position
	_main.player.velocity = original_velocity
	rain_surface._update_ground_height()
	rain_surface._update_anchor()
	if not stayed_grounded:
		push_error(
			"Rain surface followed a jumping actor from %.3f to %.3f."
			% [ground_height, jump_surface_height]
		)
		return false
	print("  [rain regression] jump keeps surface Y at %.3f" % ground_height)
	return true


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
		push_error("Could not save rain capture %s (error %d)." % [path, error])
	else:
		print("  [rain shot] %s" % path)
