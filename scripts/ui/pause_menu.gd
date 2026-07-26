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

var _root: Control
var _card: PanelContainer
var _content: VBoxContainer
var _page := "menu"
var _status_label: Label


func setup(game_core: GameCore, ui_kit: UiKit, bridge: Main) -> void:
	core = game_core
	kit = ui_kit
	settings_bridge = bridge
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80
	_build_shell()
	load_preferences_from_core()


func load_preferences_from_core() -> void:
	preferences.from_dict(core.visual_state.get("preferences", {}))
	preferences.apply(get_viewport(), settings_bridge.lighting, settings_bridge.hud)


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
	_root.visible = false
	get_tree().paused = false
	_play("panel_close")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not event.is_action_pressed("cancel"):
		return
	if _page == "menu":
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
	scrim.color = Color(0.18, 0.18, 0.15, 0.54)
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
	footer.add_theme_color_override("font_color", Color(0.82, 0.8, 0.72))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(footer)
	_root.visible = false


func _show_page(page: String) -> void:
	_page = page if page in ["menu", "settings", "controls", "exit"] else "menu"
	_clear_page()
	_status_label = null
	match _page:
		"settings":
			_build_settings_page()
		"controls":
			_build_controls_page()
		"exit":
			_build_exit_page()
		_:
			_build_menu_page()
	_card.scale = Vector2(0.96, 0.96)
	var tween := _card.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_card, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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
	_card.custom_minimum_size = Vector2(500, 550)
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
	var save := kit.menu_button("Save Game")
	save.name = "PauseSaveButton"
	save.pressed.connect(_save_game)
	_content.add_child(save)
	var exit := kit.menu_button("Save & Exit")
	exit.name = "PauseExitButton"
	exit.pressed.connect(_request_page.bind("exit"))
	_content.add_child(exit)

	_status_label = kit.label("", 15)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size.y = 24
	_status_label.add_theme_color_override("font_color", kit.palette.color("ui_good").darkened(0.12))
	_content.add_child(_status_label)
	resume.call_deferred("grab_focus")


func _build_settings_page() -> void:
	_card.custom_minimum_size = Vector2(700, 760)
	_add_page_header("SETTINGS", "Keep only what helps the garden feel good.")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 555)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	apply.call_deferred("grab_focus")


func _build_controls_page() -> void:
	_card.custom_minimum_size = Vector2(720, 780)
	_add_page_header("CONTROLS", "Everything you need to tend, shape, and explore.")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 620)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	list.add_child(kit.section_label("Keeper"))
	for entry in [
		["Move", ["W", "A", "S", "D"], "Walk freely across connected land."],
		["Interact", ["E"], "Use the focused pond, parcel, or grove."],
		["Shape land", ["B"], "Open build mode and your tile library."],
		["Rotate piece", ["R"], "Turn the held tile or decoration."],
		["Store piece", ["X"], "Return a held piece to its library."],
		["Undo / redo", ["Ctrl+Z", "Ctrl+Shift+Z"], "Reverse recent building changes."],
	]:
		list.add_child(_control_row(entry[0], entry[1], entry[2]))

	list.add_child(kit.section_label("Camera"))
	for entry in [
		["Zoom", ["Wheel", "Up", "Down"], "Move from full-diorama view to close inspection."],
		["Rotate view", ["Q", "X", "Left", "Right"], "Orbit by a quarter turn."],
		["Return home", ["H"], "Walk back to the home tile."],
	]:
		list.add_child(_control_row(entry[0], entry[1], entry[2]))

	list.add_child(kit.section_label("Journal"))
	for entry in [
		["Tile library", ["I"], "See stored land and decorations."],
		["Keeper", ["C"], "Review equipment and appearance."],
		["Skills", ["K"], "Check hobby levels and unlocks."],
		["Collection", ["J"], "Review everything discovered."],
		["Map", ["M"], "See the shape of your world."],
		["Pause / back", ["Esc"], "Open this menu or return one page."],
	]:
		list.add_child(_control_row(entry[0], entry[1], entry[2]))

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
	sub.add_theme_color_override("font_color", Color(0.46, 0.45, 0.4))
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
	sub.add_theme_color_override("font_color", Color(0.48, 0.47, 0.42))
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
	note.add_theme_color_override("font_color", Color(0.49, 0.48, 0.43))
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
	note.add_theme_color_override("font_color", Color(0.49, 0.48, 0.43))
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
	preferences.apply(get_viewport(), settings_bridge.lighting, settings_bridge.hud)


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
