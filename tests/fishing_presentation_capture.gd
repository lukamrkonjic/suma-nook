extends Node
## Focused visual review for the live fishing presentation. The runner enters
## the real game, uses the current character rig, starts a void cast at a real
## island edge, and saves the settled frame without touching the player's save.

const SAVE_PATH := "user://fishing_presentation_capture_save.json"

var _main: Main
var _output_dir := "res://artifacts/fishing_presentation"
var _shot_name := "fishing_clear"
var _weather := "day"
var _capture_size := Vector2i(1600, 900)


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
		elif argument.begins_with("--shot-name="):
			_shot_name = argument.trim_prefix("--shot-name=")
		elif argument.begins_with("--weather="):
			_weather = argument.trim_prefix("--weather=")
		elif argument.begins_with("--capture-size="):
			var parts := argument.trim_prefix(
				"--capture-size="
			).split("x")
			if parts.size() == 2:
				_capture_size = Vector2i(
					int(parts[0]),
					int(parts[1])
				)
	get_window().mode = Window.MODE_WINDOWED
	get_window().borderless = false
	get_window().content_scale_aspect = (
		Window.CONTENT_SCALE_ASPECT_EXPAND
	)
	get_window().size = _capture_size
	get_window().content_scale_size = _capture_size
	for _frame in 3:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(_output_dir)
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.55).timeout
	await _enter_gameplay()
	_main.core.registries.tuning["fishing_wait_min"] = 20.0
	_main.core.registries.tuning["fishing_wait_max"] = 20.0
	# Hold the session in its waiting state so the capture stays stable.
	_main.core.fishing.balance._data["timing"] = {
		"cast_seconds": 0.4,
		"wait_min_seconds": 20.0,
		"wait_max_seconds": 20.0,
		"bite_window_seconds": 6.0,
		"manual_reel_seconds": 1.8,
		"auto_reel_seconds": 2.6,
		"reveal_seconds": 1.4,
		"recast_pause_seconds": 0.8,
		"total_max_seconds": 40.0,
	}
	_main.player.global_position = (
		_main.core.grid.cell_to_world(Vector2i(1, 0))
		+ Vector3(_main.core.grid.tile_size * 0.42, 0.0, 0.0)
	)
	_main.player.velocity = Vector3.ZERO
	_main.camera_rig.global_position = _main.player.global_position
	_main.camera_rig.set_zoom_immediate(24.0)
	_main.lighting.set_weather(_weather)
	_hide_ui()
	_suspend_thumbnail_renderers()
	_main.player._update_focus()
	await get_tree().create_timer(0.2).timeout
	var focus := _main.player.focus()
	if focus.get("kind", "") != "void_fishing":
		push_error("Fishing capture could not resolve a live void-fishing edge.")
		get_tree().quit(1)
		return
	var player_position_before := _main.player.global_position
	var cast_surface: Vector3 = focus.get(
		"cast_point",
		_main.player.global_position
	)
	var focus_cell: Vector2i = focus.get(
		"coord",
		_main.player.current_cell()
	)
	var focus_cell_origin := _main.core.grid.cell_to_world(
		focus_cell,
		_main.core.grid.top_elevation(focus_cell)
	)
	var to_cast := cast_surface - focus_cell_origin
	to_cast.y = 0.0
	var expected_yaw := atan2(-to_cast.x, -to_cast.z)
	var camera_yaw_before := _main.camera_rig._yaw_target
	var camera_zoom_before := _main.camera_rig.zoom_distance()
	var camera_pan_before := _main.camera_rig._pan_offset
	_main.skill_actions.interact_with(focus)
	var deadline := Time.get_ticks_msec() + 8000
	while (
		not _main.effects.void_fishing.has_visible_line()
		and Time.get_ticks_msec() < deadline
	):
		await get_tree().create_timer(0.05).timeout
	for _frame in 24:
		await get_tree().process_frame
	var live_rod := _main.player_visual._fishing_rod
	var motion_deadline := Time.get_ticks_msec() + 5000
	while (
		is_instance_valid(live_rod)
		and (
			live_rod.bump_count() < 1
			or not _main.effects.void_fishing.shard_crackle_visible()
		)
		and Time.get_ticks_msec() < motion_deadline
	):
		await get_tree().process_frame
	print(
		"FISHING_STAGE current_profile=",
		_main.player_visual._asset_profile.asset_id,
		" seated=",
		_main.player_visual._seated_fishing_active,
		" influence=",
		_main.player_visual._fishing_pose_modifier.influence,
		" active=",
		_main.player_visual._fishing_pose_modifier.active,
		" dock=",
		_main.effects.void_fishing.dock_is_visible(),
		" position_unchanged=",
		_main.player.global_position.is_equal_approx(
			player_position_before
		),
		" facing_cast=",
		absf(angle_difference(
			_main.player.rotation.y,
			expected_yaw
		)) < 0.001,
		" camera_unchanged=",
		(
			absf(_main.camera_rig._yaw_target - camera_yaw_before) < 0.001
			and absf(
				_main.camera_rig.zoom_distance() - camera_zoom_before
			) < 0.001
			and _main.camera_rig._pan_offset.is_equal_approx(
				camera_pan_before
			)
		),
		" bump_count=",
		live_rod.bump_count() if is_instance_valid(live_rod) else -1,
		" crackle=",
		_main.effects.void_fishing.shard_crackle_visible(),
		" viewport=",
		get_viewport().get_visible_rect().size
	)
	await RenderingServer.frame_post_draw
	var output_path := _output_dir.path_join(_shot_name + ".png")
	var image := get_viewport().get_texture().get_image()
	GGCaptureEncode.encode_srgb(image)
	var error := image.save_png(output_path)
	if error != OK:
		push_error(
			"Could not save fishing capture %s (error %d)."
			% [output_path, error]
		)
		get_tree().quit(1)
		return
	print("FISHING_CAPTURE ", output_path)
	_suspend_thumbnail_renderers()
	_main.queue_free()
	for _frame in 3:
		await get_tree().process_frame
	get_tree().quit(0)


func _suspend_thumbnail_renderers() -> void:
	for renderer in _main.find_children(
		"*",
		"BuildThumbnailRenderer",
		true,
		false
	):
		var thumbnail_renderer := (
			renderer as BuildThumbnailRenderer
		)
		thumbnail_renderer.set_process(false)
		thumbnail_renderer.discard_pending()


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		push_error("Fishing capture could not find character creation.")
		get_tree().quit(1)
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Fishing Keeper"
	creator._finish()
	var picker_deadline := Time.get_ticks_msec() + 5000
	while (
		not _main.arrival_picker.is_open()
		and Time.get_ticks_msec() < picker_deadline
	):
		await get_tree().create_timer(0.05).timeout
	if not _main.arrival_picker.is_open():
		push_error(
			"Fishing capture never reached first-land choice (stage %s)."
			% _main.core.onboarding.stage
		)
		return
	_main.arrival_picker.select("tile_grove_mature")
	var gameplay_deadline := Time.get_ticks_msec() + 5000
	while (
		not _main._gameplay_started
		and Time.get_ticks_msec() < gameplay_deadline
	):
		await get_tree().create_timer(0.05).timeout
	if not _main._gameplay_started:
		push_error(
			"Fishing capture could not enter gameplay (stage %s, picker %s)."
			% [_main.core.onboarding.stage, _main.arrival_picker.is_open()]
		)
		get_tree().quit(1)


func _hide_ui() -> void:
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
