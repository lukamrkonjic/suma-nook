extends Node
## Real-gameplay visual regression for entry splashes, surface deformation,
## swimming wakes, and the fixed world-space waterline.

const SAVE_PATH := "user://water_interaction_capture_save.json"

var _main: Main
var _output_dir := "res://artifacts/water_interaction_review"


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
	_build_water_lab()
	_hide_ui()
	_main.camera_rig.set_zoom_immediate(15.0)
	await _settle(20)

	var system := _main.effects.water_interaction
	var water_level := _main.core.registries.tunef("water_level_y", -0.14)
	var center := _main.core.grid.cell_to_world(Vector2i(20, 20))
	_main.player.set_state(PlayerController.State.FREE)
	_main.player.global_position = center + Vector3(0.0, 2.35, 0.0)
	_main.player.velocity = Vector3(0.35, -2.0, 0.15)
	_main.camera_rig.global_position = center

	var deadline := Time.get_ticks_msec() + 3500
	while (
		_main.player.state != PlayerController.State.SWIMMING
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().process_frame
	if _main.player.state != PlayerController.State.SWIMMING:
		push_error("Player did not enter swimming state during the real fall.")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.08).timeout
	if (
		system._entry_count != 1
		or system.active_impulse_count() < 1
		or not is_equal_approx(system._last_surface_position.y, water_level)
	):
		push_error(
			"Water entry did not create one grounded splash: %s"
			% JSON.stringify(system.runtime_manifest())
		)
		get_tree().quit(1)
		return
	await _save_viewport("water_jump_entry_splash.png")

	Input.action_press("move_right")
	await get_tree().create_timer(1.05).timeout
	if (
		system._movement_impulse_count < 2
		or system._wake_strength <= 0.1
		or not system._movement_splash.emitting
	):
		Input.action_release("move_right")
		push_error(
			"Real swimming did not create a wake and movement spray: %s"
			% JSON.stringify(system.runtime_manifest())
		)
		get_tree().quit(1)
		return
	await _save_viewport("water_swimming_wake.png")
	Input.action_release("move_right")
	# Let the entry and walking history settle so the next capture proves the
	# swim-hop ripple itself instead of showing an older landing ring.
	await get_tree().create_timer(2.35).timeout

	# A swim hop changes the actor's Y, but the interaction surface must remain
	# pinned to the authored world waterline.
	var jump_event := InputEventAction.new()
	jump_event.action = "jump"
	jump_event.pressed = true
	_main.player._unhandled_input(jump_event)
	await get_tree().create_timer(0.22).timeout
	if (
		system._exit_count != 1
		or not is_equal_approx(system._last_surface_position.y, water_level)
	):
		push_error(
			"Swim hop did not create one waterline ripple: %s"
			% JSON.stringify(system.runtime_manifest())
		)
		get_tree().quit(1)
		return
	await _save_viewport("water_swim_hop_ripple.png")

	var material := _main.materials.material("water") as ShaderMaterial
	var impulses: PackedVector4Array = material.get_shader_parameter(
		"interaction_impulses"
	)
	if impulses.size() != WaterInteractionSystem.IMPULSE_COUNT:
		push_error("Water shader impulse budget was not uploaded.")
		get_tree().quit(1)
		return
	print(
		"WATER_INTERACTION_CAPTURE_MANIFEST ",
		JSON.stringify(system.runtime_manifest())
	)
	print("WATER INTERACTION CAPTURED — %s" % _output_dir)
	get_tree().quit(0)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("Water capture could not find character creation.")
		get_tree().quit(1)
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Water Keeper"
	creator._finish()
	await get_tree().create_timer(0.7).timeout
	if not _main._gameplay_started:
		push_error("Water capture could not enter gameplay.")
		get_tree().quit(1)


func _build_water_lab() -> void:
	for z in range(18, 23):
		for x in range(18, 23):
			_main.core.grid.place_tile(Vector2i(x, z), "tile_open_water")
	_main.renderer.rebuild_all()


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
		push_error("Could not save water capture %s (error %d)." % [path, error])
	else:
		print("  [water shot] %s" % path)
