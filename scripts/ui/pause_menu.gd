class_name PauseMenu
extends CanvasLayer
## A calm, save-aware pause flow. It intentionally mirrors the useful shape of
## the reference menu without copying its art: compact landing card, dedicated
## settings and controls pages, and the garden still visible underneath.

signal opened
signal closed

var core: GameCore
var kit: UiKit
var settings_bridge: Main
var preferences := GamePreferences.new()
var _input_service: InputDeviceService

var _root: Control
var _card: PanelContainer
var _content: VBoxContainer
var _page := "menu"
var _status_label: Label


func setup(game_core: GameCore, ui_kit: UiKit, bridge: Main) -> void:
	core = game_core
	kit = ui_kit
	settings_bridge = bridge
	_input_service = InputDeviceService.shared()
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80
	_build_shell()
	load_preferences_from_core()
	_input_service.input_method_changed.connect(_on_input_method_changed)
	_input_service.active_controller_changed.connect(
		func(_device): _on_input_method_changed(_input_service.input_method)
	)


func load_preferences_from_core() -> void:
	preferences.from_dict(core.visual_state.get("preferences", {}))
	preferences.apply(
		get_viewport(),
		settings_bridge.lighting,
		settings_bridge.hud,
		settings_bridge.pixel_look
	)


func is_open() -> bool:
	return _root != null and _root.visible


func current_page() -> String:
	return _page


func open(page := "menu") -> void:
	if _root == null:
		return
	_root.visible = true
	_show_page(page)
	_play("panel_open")
	get_tree().paused = true
	opened.emit()


func close() -> void:
	if not is_open():
		return
	_input_service.release_focus_in(_root)
	_root.visible = false
	get_tree().paused = false
	_play("panel_close")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("pause"):
		close()
	elif not event.is_action_pressed("cancel"):
		return
	elif _page == "menu":
		close()
	else:
		_request_page("menu")
	get_viewport().set_input_as_handled()


func _build_shell() -> void:
	_root = Control.new()
	_root.name = "PauseOverlay"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = kit.theme
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = kit.palette.color("ui_pause_scrim")
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(center)

	_card = kit.card(Vector2(500, 550))
	_card.name = "PauseCard"
	_card.add_theme_stylebox_override("panel", kit.cloud_panel_style())
	center.add_child(_card)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 16)
	_card.add_child(_content)

	var footer := kit.label("SUMA NOOK  |  grow gently, save often", 14, false, true)
	footer.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	footer.position.y = -24
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", kit.palette.color("ui_pause_footer"))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(footer)
	_root.visible = false


func _show_page(page: String) -> void:
	_page = page if page in ["menu", "settings", "controls", "exit", "admin"] else "menu"
	if _page == "admin" and not OS.is_debug_build():
		_page = "menu"
	_clear_page()
	_status_label = null
	match _page:
		"settings":
			_build_settings_page()
		"controls":
			_build_controls_page()
		"exit":
			_build_exit_page()
		"admin":
			_build_admin_page()
		_:
			_build_menu_page()
	_card.scale = Vector2(0.96, 0.96)
	var tween := _card.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_card, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	focus_default()


func focus_default() -> void:
	if is_open():
		_input_service.focus_first(_content)


func _on_input_method_changed(_method: int) -> void:
	if is_open() and _page in ["menu", "controls"]:
		call_deferred("_show_page", _page)


func _request_page(page: String) -> void:
	## Never destroy the button that is currently emitting `pressed`. Waiting
	## until the input callback completes keeps page replacement atomic.
	call_deferred("_show_page", page)


func _clear_page() -> void:
	## Detach the entire old page immediately, then release it safely after the
	## current input dispatch. This prevents partially-cleared menus.
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()


func _build_menu_page() -> void:
	_card.custom_minimum_size = Vector2(500, 660 if OS.is_debug_build() else 590)
	_add_brand_header("PAUSED", "Your nook will wait for you.")

	var resume := kit.menu_button("Resume Garden", true)
	resume.name = "PauseResumeButton"
	resume.pressed.connect(close)
	_content.add_child(resume)
	var settings := kit.menu_button("Settings")
	settings.name = "PauseSettingsButton"
	settings.pressed.connect(_request_page.bind("settings"))
	_content.add_child(settings)
	var controls := kit.menu_button("Controls")
	controls.name = "PauseControlsButton"
	controls.pressed.connect(_request_page.bind("controls"))
	_content.add_child(controls)
	if OS.is_debug_build():
		var admin := kit.menu_button("Admin Controls")
		admin.name = "PauseAdminButton"
		admin.pressed.connect(_request_page.bind("admin"))
		_content.add_child(admin)
	var save := kit.menu_button("Save Game")
	save.name = "PauseSaveButton"
	save.pressed.connect(_save_game)
	_content.add_child(save)
	var exit := kit.menu_button("Save & Exit")
	exit.name = "PauseExitButton"
	exit.pressed.connect(_request_page.bind("exit"))
	_content.add_child(exit)

	var shortcut_helper := kit.label(_shortcut_helper_text(), 14, false, true)
	shortcut_helper.name = "PauseShortcutHelper"
	shortcut_helper.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shortcut_helper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shortcut_helper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shortcut_helper.add_theme_color_override(
		"font_color",
		kit.palette.color("ui_text").darkened(0.28)
	)
	_content.add_child(shortcut_helper)

	_status_label = kit.label("", 15)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size.y = 24
	_status_label.add_theme_color_override("font_color", kit.palette.color("ui_good").darkened(0.12))
	_content.add_child(_status_label)
	resume.call_deferred("grab_focus")


func _shortcut_helper_text() -> String:
	var hud_prompt := _input_service.prompt_for_action(&"toggle_hud")
	var home_prompt := _input_service.prompt_for_action(&"return_home")
	if _input_service.is_controller() and hud_prompt == home_prompt:
		return "%s tap  Hide HUD   •   %s hold  Return home" % [
			hud_prompt,
			home_prompt,
		]
	return "%s  Hide HUD   •   %s  Return home" % [
		hud_prompt,
		home_prompt,
	]


func _build_settings_page() -> void:
	_card.custom_minimum_size = Vector2(700, 760)
	_add_page_header("SETTINGS", "Keep only what helps the garden feel good.")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 555)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	_content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	list.add_child(kit.section_label("Display"))
	var fullscreen_check := _check_button("Fullscreen", preferences.fullscreen)
	list.add_child(_setting_row("Window mode", "Use the current display at native resolution.", fullscreen_check))
	var vsync_check := _check_button("VSync", preferences.vsync)
	list.add_child(_setting_row("VSync", "Prevents visible tearing.", vsync_check))
	var aa_option := OptionButton.new()
	aa_option.add_item("Off")
	aa_option.add_item("Balanced")
	aa_option.add_item("High")
	aa_option.selected = {
		GamePreferences.AA_OFF: 0,
		GamePreferences.AA_BALANCED: 1,
		GamePreferences.AA_HIGH: 2,
	}.get(preferences.anti_aliasing, 2)
	aa_option.custom_minimum_size = Vector2(180, 42)
	aa_option.add_theme_font_override("font", kit.font_bold)
	aa_option.add_theme_font_size_override("font_size", 18)
	list.add_child(_setting_row("Anti-aliasing", "High uses the full smooth-shadow render path.", aa_option))

	list.add_child(kit.section_label("Lighting"))
	var ssao_check := _check_button("SSAO", preferences.ssao)
	list.add_child(_setting_row("Contact shading", "Adds depth where objects meet the ground.", ssao_check))
	var bloom_check := _check_button("Bloom", preferences.bloom)
	list.add_child(_setting_row("Gentle bloom", "Softens bright fires and magical highlights.", bloom_check))

	list.add_child(kit.section_label("Pixel look"))
	var pixel_option := OptionButton.new()
	for option_label in GamePreferences.PIXEL_SIZE_OPTIONS:
		pixel_option.add_item(String(option_label))
	pixel_option.selected = preferences.pixel_size
	pixel_option.custom_minimum_size = Vector2(220, 42)
	pixel_option.add_theme_font_override("font", kit.font_bold)
	pixel_option.add_theme_font_size_override("font_size", 18)
	list.add_child(_setting_row("Pixel size", "Render the world in chunky retro pixels; menus stay crisp.", pixel_option))
	var cel_check := _check_button("Cel colours", preferences.pixel_cel)
	list.add_child(_setting_row("Cel colours", "Step shading into flat hand-painted bands.", cel_check))

	list.add_child(kit.section_label("Sound"))
	var master_control := _volume_control(preferences.master_volume)
	list.add_child(_setting_row("All sounds", "Overall game volume.", master_control["root"]))
	var music_control := _volume_control(preferences.music_volume)
	list.add_child(_setting_row("Music", "Music volume without changing ambience.", music_control["root"]))

	list.add_child(kit.section_label("Guidance"))
	var tutorial_check := _check_button("Hints", preferences.tutorial_hints)
	list.add_child(_setting_row("Garden hints", "Show the next gentle progression prompt.", tutorial_check))

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	_content.add_child(actions)
	var apply := kit.button("Apply Changes", true)
	apply.pressed.connect(func():
		preferences.fullscreen = fullscreen_check.button_pressed
		preferences.vsync = vsync_check.button_pressed
		preferences.anti_aliasing = [
			GamePreferences.AA_OFF,
			GamePreferences.AA_BALANCED,
			GamePreferences.AA_HIGH,
		][aa_option.selected]
		preferences.ssao = ssao_check.button_pressed
		preferences.bloom = bloom_check.button_pressed
		preferences.pixel_size = pixel_option.selected
		preferences.pixel_cel = cel_check.button_pressed
		preferences.master_volume = float(master_control["slider"].value)
		preferences.music_volume = float(music_control["slider"].value)
		preferences.tutorial_hints = tutorial_check.button_pressed
		_apply_preferences()
		_status_label.text = "Settings applied and queued for the next save."
		_play("ui_confirm")
	)
	actions.add_child(apply)
	_status_label = kit.label("", 15)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_content.add_child(_status_label)


func _build_controls_page() -> void:
	_card.custom_minimum_size = Vector2(720, 780)
	_add_page_header("CONTROLS", "Everything you need to tend, shape, and explore.")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 620)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	_content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	list.add_child(kit.section_label("Keeper"))
	var keeper_controls := [
		["Move", ["Click ground"], "Send the keeper across its current island."],
		["Jump", ["Space"], "Clear objects and one raised land layer."],
		[
			"Interact",
			[
				_input_service.prompt_for_action(
					&"interact",
					InputDeviceService.InputMethod.KEYBOARD_MOUSE
				)
			],
			"Use the focused chest, fire, fishing spot, tree, or other usable object.",
		],
		["Build Bag", ["B"], "Open or collapse the persistent piece library."],
		["Rotate piece", ["R"], "Turn the held tile or decoration."],
		["Store piece", ["X"], "Return a held piece to its library."],
		["Undo / redo", ["Ctrl+Z", "Ctrl+Shift+Z"], "Reverse recent building changes."],
	]
	if _input_service.is_controller():
		keeper_controls = [
			["Move / sprint", ["Left Stick", "L3"], "Walk freely; press the stick to sprint."],
			["Jump", [_input_service.prompt_for_action(&"jump")], "Clear objects and one raised land layer."],
			[
				"Interact",
				[_input_service.prompt_for_action(&"interact")],
				"Use a chest, fire, fishing spot, tree, or other usable object.",
			],
			["Shape land", [_input_service.prompt_for_action(&"build_mode")], "Switch between the library and world cursor."],
			["Place / pick up", [_input_service.prompt_for_action(&"build_confirm")], "Use the camera-relative grid cursor."],
			["Rotate piece", [_input_service.prompt_for_action(&"rotate_piece")], "Turn the held tile or decoration."],
			["Store piece", [_input_service.prompt_for_action(&"store_piece")], "Return a moved piece to its library."],
			["Undo / redo", [
				_input_service.prompt_for_action(&"undo"),
				_input_service.prompt_for_action(&"redo"),
			], "Reverse recent building changes."],
		]
	for entry in keeper_controls:
		list.add_child(_control_row(entry[0], entry[1], entry[2]))

	list.add_child(kit.section_label("Camera"))
	var camera_controls := [
		["Zoom", ["Wheel", "Up", "Down"], "Move from full-diorama view to close inspection."],
		["Pan", ["W", "A", "S", "D", "Middle mouse"], "Move across the world and detached islands."],
		["Rotate view", ["Q", "X", "Left", "Right"], "Orbit by a quarter turn."],
		["Hide HUD", ["H"], "Hide or restore every gameplay overlay."],
		["Return home", ["Home"], "Return the keeper and camera to the home tile."],
	]
	if _input_service.is_controller():
		camera_controls = [
			["Pan", [_input_service.prompt_for_action(&"camera_pan_up")], "Move across the world and detached islands."],
			["Zoom", [
				_input_service.prompt_for_action(&"camera_zoom_in"),
				_input_service.prompt_for_action(&"camera_zoom_out"),
			], "Move from full-diorama view to close inspection."],
			["Rotate view", [
				_input_service.prompt_for_action(&"camera_rotate_left"),
				_input_service.prompt_for_action(&"camera_rotate_right"),
			], "Orbit by a quarter turn."],
			["Hide HUD", [_input_service.prompt_for_action(&"toggle_hud")], "Tap to hide or restore every gameplay overlay."],
			["Return home", [_input_service.prompt_for_action(&"return_home")], "Hold to return the keeper and camera to the home tile."],
		]
	for entry in camera_controls:
		list.add_child(_control_row(entry[0], entry[1], entry[2]))

	list.add_child(kit.section_label("Journal"))
	var journal_controls := [
		["Tile library", ["I"], "See stored land and decorations."],
		["Keeper", ["C"], "Review equipment and appearance."],
		["Skills", ["K"], "Check hobby levels and unlocks."],
		["Collection", ["J"], "Review everything discovered."],
		["Map", ["M"], "See the shape of your world."],
		["Pause / back", ["Esc"], "Open this menu or return one page."],
	]
	if _input_service.is_controller():
		journal_controls = [
			["Tile library", [_input_service.prompt_for_action(&"panel_inventory")], "See stored land and decorations."],
			["Keeper", [_input_service.prompt_for_action(&"panel_character")], "Review equipment and appearance."],
			["Skills", [_input_service.prompt_for_action(&"panel_skills")], "Check hobby levels and unlocks."],
			["Collection", [_input_service.prompt_for_action(&"panel_collection")], "Review everything discovered."],
			["Map", [_input_service.prompt_for_action(&"panel_map")], "See the shape of your world."],
			["Change journal page", [
				_input_service.prompt_for_action(&"panel_previous"),
				_input_service.prompt_for_action(&"panel_next"),
			], "Cycle between open journal pages."],
			["Pause / back", [
				_input_service.prompt_for_action(&"pause"),
				_input_service.prompt_for_action(&"cancel"),
			], "Open this menu or return one page."],
		]
	for entry in journal_controls:
		list.add_child(_control_row(entry[0], entry[1], entry[2]))

func _build_admin_page() -> void:
	## Developer shortcuts (debug builds only). Rebuilt from the pre-refactor
	## admin card on the current managers; lighting transitions tick in
	## _process, so visual choices finish blending once the game resumes.
	_card.custom_minimum_size = Vector2(760, 800)
	_add_page_header("ADMIN", "Developer shortcuts. Visual changes finish once you resume.")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 600)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	_content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	var grant_items := func() -> void:
		for item_id in core.registries.items:
			core.inventory.grant(String(item_id), 99, false, true)
		_admin_status("Granted 99 of every item (%d kinds)." % core.registries.items.size())
	var grant_tiles := func() -> void:
		var tile_ids := core.registries.obtainable_tile_ids()
		for tile_id in tile_ids:
			core.stock.add_tile(String(tile_id), 10)
		_admin_status(
			"Stocked 10 of every official tile (%d kinds)." % tile_ids.size()
		)
	var grant_structures := func() -> void:
		for structure_id in core.registries.structures:
			core.stock.add_structure(String(structure_id), 10)
		_admin_status("Stocked 10 of every structure (%d kinds)." % core.registries.structures.size())
	list.add_child(kit.section_label("Content library"))
	_admin_action_row(list, "Every item", "Grant 99 of each registered item, quietly.", "Grant ×99", grant_items)
	_admin_action_row(
		list,
		"Every official tile",
		"Stock 10 of every obtainable tile published through Asset Studio.",
		"Grant ×10",
		grant_tiles,
		"AdminRowEveryTile"
	)
	_admin_action_row(list, "Every structure", "Stock 10 of each structure and decoration.", "Grant ×10", grant_structures)

	var toggle_tuner := func() -> void:
		var now_visible: bool = settings_bridge.toggle_lighting_tuner()
		_admin_status(
			"Lighting tuner overlaid bottom-left — tune live, then Copy or Save."
			if now_visible else "Lighting tuner hidden."
		)
	var lighting := settings_bridge.lighting
	if lighting != null:
		list.add_child(kit.section_label("Visuals"))
		var open_asset_viewer := func() -> void:
			settings_bridge.call_deferred("open_asset_viewer")
		_admin_action_row(
			list,
			"Asset Studio",
			"Edit real tile/model smoothing and materials under live weather. Shortcut: F8.",
			"Open studio",
			open_asset_viewer,
			"AdminRowAssetViewer"
		)
		_admin_action_row(
			list,
			"Performance HUD",
			"Live FPS, milliseconds, draw calls, triangles, memory, chunks, and models. Shortcut: F3.",
			"Toggle profiler",
			func() -> void:
				settings_bridge.toggle_performance_hud()
		)
		_admin_action_row(list, "Lighting tuner",
			"ReShade-style overlay with every lighting slider, bottom-left over the game.",
			"Toggle overlay", toggle_tuner)
		_admin_choice_row(list, "Weather", [
			["Day", "day"], ["Mist", "mist"], ["Rain", "rain"],
			["Leaves", "leaves"], ["Snow", "snow"], ["Bloom", "blossom"],
		], lighting.weather_id(), func(choice_id): lighting.set_weather(choice_id))
		_admin_choice_row(list, "Time of day", [
			["Morning", "morning"], ["Noon", "noon"], ["Sunset", "sunset"], ["Night", "night"],
		], lighting.time_of_day_id, func(choice_id): lighting.set_time_of_day(choice_id))
		_admin_choice_row(list, "Background", [
			["Profile", "profile"], ["Cream", "cream"], ["Mist", "mist"],
			["Dusk", "dusk"], ["Night", "night"],
		], lighting.background_preset_id, func(choice_id): lighting.set_background_preset(choice_id))

	var grant_fishing_discovery := func() -> void:
		var haul = core.fishing.debug_force_catch(core.grid.home_cell)
		_admin_status(
			"Committed one %s haul to the Catch Basket." % haul.catch_size
			if haul != null
			else "The Catch Basket is full — take or return a haul first."
		)
	var grant_woodland_discovery := func() -> void:
		core.progression.on_activity_cycle_completed("woodcutting")
		_admin_status("Completed one tree cycle — a Grove Spirit was offered to the pouch.")
	var save_now := func() -> void:
		_admin_status("Garden saved." if core.save() else "Could not save the garden.")
	var build_mock := func() -> void:
		var placed: int = settings_bridge.debug_build_mock_world()
		_admin_status("Mock world built — %d structures placed. Resume to explore." % placed)
	var build_stress_world := func() -> void:
		var report: Dictionary = settings_bridge.debug_build_performance_world()
		_admin_status(
			"Isolated 5K world built: %d tiles, %d models, %d tile types."
			% [
				int(report.get("tiles", 0)),
				int(report.get("models", 0)),
				int(report.get("tile_types", 0)),
			]
		)
	var build_maxed_world := func() -> void:
		var report: Dictionary = settings_bridge.debug_build_maxed_world()
		_admin_status(
			"Maxed world built: %d tiles and %d models — one model per tile."
			% [
				int(report.get("tiles", 0)),
				int(report.get("models", 0)),
			]
		)
	var reset_save := func() -> void:
		settings_bridge.debug_reset_save()
	list.add_child(kit.section_label("World and progression"))
	_admin_action_row(list, "Mock world", "Rebuild the island as a showcase of every tile family and structure.", "Build", build_mock)
	_admin_action_row(
		list,
		"5K Debug World",
		"Build 5,000 mixed tiles and 1,250 models in an isolated, unsaved stress session.",
		"Build stress test",
		build_stress_world
	)
	_admin_action_row(
		list,
		"10K Maxed World",
		"Extreme density: 10,000 mixed tiles with exactly one model on every tile.",
		"Build maxed test",
		build_maxed_world
	)
	_admin_action_row(list, "Reset save", "Deletes the save and its backup, then restarts the game fresh.", "Reset", reset_save)
	_admin_action_row(list, "Void Fishing", "Generate and commit one full haul to the Catch Basket.", "Catch now", grant_fishing_discovery)
	_admin_action_row(list, "Woodland Tending", "Publish one completed tree cycle (grants a Grove Spirit).", "Complete cycle", grant_woodland_discovery)
	_admin_action_row(
		list, "Habitat sample",
		"Print the 3x3 habitat themes around the keeper's current cell.",
		"Inspect",
		func() -> void:
			var report: Dictionary = core.fishing.debug_habitat_report(
				core.grid.world_to_cell(settings_bridge.player.global_position)
			)
			_admin_status("Habitat %s → %s" % [report["anchor"], report["normalized"]])
	)
	_admin_action_row(
		list, "Spirit Pouch",
		"Fill every free pouch slot with Grove Spirits, or clear it.",
		"Fill pouch",
		func() -> void:
			core.fishing.debug_fill_pouch()
			_admin_status("Spirit Pouch filled.")
	)
	_admin_action_row(
		list, "Catch Basket",
		"Fill the basket with forced catches, or clear all pending hauls.",
		"Fill basket",
		func() -> void:
			core.fishing.debug_fill_basket()
			_admin_status("Catch Basket filled.")
	)
	_admin_action_row(
		list, "Clear fishing state",
		"Empty the Spirit Pouch and the Catch Basket.",
		"Clear both",
		func() -> void:
			core.fishing.debug_clear_pouch()
			core.fishing.debug_clear_basket()
			_admin_status("Pouch and basket cleared.")
	)
	_admin_action_row(
		list, "Fishing simulation",
		"Run 10,000 seeded virtual catches through the live reward services.",
		"Simulate",
		func() -> void:
			var report: Dictionary = core.fishing.run_simulation(1337, 10000)
			_admin_status(
				"10k catches — sizes %s · forms %s · keepsakes %d · fallbacks %d"
				% [
					report["sizes"], report["forms"],
					int(report["keepsakes"]),
					int(report["empty_pool_fallbacks"]),
				]
			)
	)
	_admin_action_row(list, "Save", "Write the garden to disk immediately.", "Save now", save_now)

	_status_label = kit.label("", 15)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size.y = 24
	_status_label.add_theme_color_override("font_color", kit.palette.color("ui_good").darkened(0.12))
	_content.add_child(_status_label)


func _admin_action_row(
	list: VBoxContainer,
	title: String,
	description: String,
	button_text: String,
	action: Callable,
	stable_name := ""
) -> void:
	var button := kit.button(button_text)
	button.name = (
		stable_name
		if not stable_name.is_empty()
		else "AdminRow" + title.to_pascal_case()
	)
	button.pressed.connect(action)
	list.add_child(_setting_row(title, description, button))


func _admin_choice_row(list: VBoxContainer, title: String, choices: Array, active_id: String, on_choice: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for choice in choices:
		var button := kit.button(String(choice[0]), String(choice[1]) == active_id)
		button.custom_minimum_size = Vector2(0, 42)
		var choice_id := String(choice[1])
		var pick := func() -> void:
			on_choice.call(choice_id)
			_request_page("admin")
		button.pressed.connect(pick)
		row.add_child(button)
	list.add_child(_setting_row(title, "", row))


func _admin_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
	_play("ui_confirm")


func _build_exit_page() -> void:
	_card.custom_minimum_size = Vector2(500, 370)
	_add_page_header("LEAVE THE NOOK?", "Your garden will be saved before the game closes.")
	var note := kit.label("Nothing in progress will be lost. You can return to this exact world next time.", 17)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 420
	_content.add_child(note)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 28
	_content.add_child(spacer)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	_content.add_child(actions)
	var back := kit.button("Stay")
	back.pressed.connect(_request_page.bind("menu"))
	actions.add_child(back)
	var exit := kit.button("Save & Exit", true)
	exit.pressed.connect(_save_and_exit)
	actions.add_child(exit)
	back.call_deferred("grab_focus")


func _add_brand_header(kicker: String, subtitle: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_content.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 3)
	row.add_child(text)
	var brand := kit.label("Suma Nook", 32, false, true)
	text.add_child(brand)
	var sub := kit.label(subtitle, 16)
	sub.add_theme_color_override("font_color", kit.palette.color("ui_pause_subtitle"))
	text.add_child(sub)
	var state := kit.section_label(kicker)
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(state)


func _add_page_header(title: String, subtitle: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_content.add_child(row)
	var back := kit.button("Back")
	back.name = "PauseBackButton"
	back.custom_minimum_size = Vector2(80, 46)
	back.pressed.connect(_request_page.bind("menu"))
	row.add_child(back)
	back.call_deferred("grab_focus")
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(kit.label(title, 30, false, true))
	var sub := kit.label(subtitle, 15)
	sub.add_theme_color_override("font_color", kit.palette.color("ui_pause_subtle"))
	text.add_child(sub)


func _setting_row(title: String, description: String, control: Control) -> MarginContainer:
	var holder := MarginContainer.new()
	holder.custom_minimum_size.y = 74
	for side in ["left", "right"]:
		holder.add_theme_constant_override("margin_%s" % side, 14)
	for side in ["top", "bottom"]:
		holder.add_theme_constant_override("margin_%s" % side, 9)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	holder.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 3)
	row.add_child(text)
	text.add_child(kit.label(title, 19, false, true))
	var note := kit.label(description, 14)
	note.add_theme_color_override("font_color", kit.palette.color("ui_pause_note"))
	text.add_child(note)
	row.add_child(control)
	return holder


func _check_button(text: String, pressed: bool) -> CheckButton:
	var check := CheckButton.new()
	check.text = text
	check.button_pressed = pressed
	check.custom_minimum_size = Vector2(150, 40)
	check.add_theme_font_override("font", kit.font_bold)
	check.add_theme_font_size_override("font_size", 17)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		check.add_theme_color_override(color_name, kit.text_color())
	return check


func _volume_control(value: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.custom_minimum_size.x = 250
	row.add_theme_constant_override("separation", 8)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size.x = 190
	row.add_child(slider)
	var amount := kit.label("%d%%" % roundi(value * 100.0), 16, false, true)
	amount.custom_minimum_size.x = 52
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(amount)
	slider.value_changed.connect(func(v): amount.text = "%d%%" % roundi(v * 100.0))
	return {"root": row, "slider": slider, "label": amount}


func _control_row(action: String, keys: Array, description: String) -> MarginContainer:
	var holder := MarginContainer.new()
	holder.custom_minimum_size.y = 72
	for side in ["left", "right"]:
		holder.add_theme_constant_override("margin_%s" % side, 14)
	for side in ["top", "bottom"]:
		holder.add_theme_constant_override("margin_%s" % side, 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	holder.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 3)
	row.add_child(text)
	text.add_child(kit.label(action, 18, false, true))
	var note := kit.label(description, 14)
	note.add_theme_color_override("font_color", kit.palette.color("ui_pause_note"))
	text.add_child(note)
	var caps := HBoxContainer.new()
	caps.alignment = BoxContainer.ALIGNMENT_END
	caps.add_theme_constant_override("separation", 5)
	row.add_child(caps)
	for key_text in keys:
		caps.add_child(kit.keycap(String(key_text), 42.0))
	return holder


func _apply_preferences() -> void:
	core.visual_state["preferences"] = preferences.to_dict()
	core.autosave_soon()
	preferences.apply(
		get_viewport(),
		settings_bridge.lighting,
		settings_bridge.hud,
		settings_bridge.pixel_look
	)


func _save_game() -> void:
	core.visual_state["preferences"] = preferences.to_dict()
	var ok := core.save()
	_status_label.text = "Garden saved." if ok else "Could not save the garden."
	_play("ui_confirm" if ok else "ui_cancel")


func _save_and_exit() -> void:
	core.visual_state["preferences"] = preferences.to_dict()
	if not core.save():
		_request_page("menu")
		_play("ui_cancel")
		return
	get_tree().paused = false
	get_tree().quit()


func _play(event_name: String) -> void:
	if settings_bridge != null and settings_bridge.audio != null:
		settings_bridge.audio.play_event(event_name)
