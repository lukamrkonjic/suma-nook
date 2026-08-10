class_name WishOfferPanel
extends CanvasLayer
## A quiet, persistent corner prompt. It never interrupts play: the player
## opens it when ready, chooses one of three physical pieces, then calls that
## single copy into the world through the ordinary placement cursor.

signal reveal_finished(entry: Dictionary)
signal reveal_started(entry: Dictionary)
signal panel_toggled(open: bool)

const PANEL_WIDTH := 516.0
const CHOICE_WIDTH := 158.0

var core: GameCore
var kit: UiKit
var _input_service: InputDeviceService
var _thumbnail_renderer: BuildThumbnailRenderer
var _root: Control
var _chip: Button
var _panel: PanelContainer
var _choice_row: HBoxContainer
var _choice_buttons: Array[Button] = []
var _first_button: Button
var _chip_tween: Tween


func setup(
	game_core: GameCore,
	ui_kit: UiKit,
	asset_library: AssetLibrary
) -> void:
	core = game_core
	kit = ui_kit
	_input_service = InputDeviceService.shared()
	layer = 2
	_thumbnail_renderer = BuildThumbnailRenderer.new()
	_thumbnail_renderer.name = "WishThumbnailRenderer"
	add_child(_thumbnail_renderer)
	_thumbnail_renderer.setup(core, asset_library)
	_build_layout()
	core.progression.discovery.wish_ready.connect(
		func(_choices): notify_ready()
	)
	core.progression.discovery.wish_changed.connect(notify_ready)
	core.progression.discovery.discovery_ready.connect(
		func(_entry): call_deferred("notify_ready")
	)
	_input_service.input_method_changed.connect(func(_method): _refresh_prompt())
	notify_ready(false)


func _build_layout() -> void:
	_root = Control.new()
	_root.name = "WishOfferRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = kit.theme
	add_child(_root)

	_chip = kit.button("Wish ready", true)
	_chip.name = "WishReady"
	_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_chip.offset_left = -176.0
	_chip.offset_right = -16.0
	_chip.offset_top = 16.0
	_chip.offset_bottom = 58.0
	_chip.focus_mode = Control.FOCUS_ALL
	_chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_chip.visible = false
	_chip.pressed.connect(toggle)
	_root.add_child(_chip)

	_panel = kit.card(Vector2(PANEL_WIDTH, 0.0))
	_panel.name = "WishChoices"
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -PANEL_WIDTH - 16.0
	_panel.offset_right = -16.0
	_panel.offset_top = 68.0
	_panel.offset_bottom = 264.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	_root.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)

	var eyebrow := kit.eyebrow(
		"A WISH IS READY",
		kit.palette.color("ui_accent")
	)
	column.add_child(eyebrow)
	var heading := kit.label("What should the sky bring?", 18, false, true)
	column.add_child(heading)
	var hint := kit.muted_label("Choose one. The others will drift away.", 13)
	column.add_child(hint)

	_choice_row = HBoxContainer.new()
	_choice_row.add_theme_constant_override("separation", 8)
	column.add_child(_choice_row)
	_refresh_prompt()


func notify_ready(animate := true) -> void:
	var ready := is_ready()
	_chip.visible = ready
	if not ready:
		close()
		return
	_refresh_prompt()
	if not animate or not is_inside_tree():
		return
	if _chip_tween != null and _chip_tween.is_valid():
		_chip_tween.kill()
	_chip.pivot_offset = _chip.size * 0.5
	_chip.scale = Vector2(0.92, 0.92)
	_chip.modulate.a = 0.0
	_chip_tween = _chip.create_tween().set_parallel(true)
	_chip_tween.tween_property(_chip, "scale", Vector2.ONE, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_chip_tween.tween_property(_chip, "modulate:a", 1.0, 0.18)


func is_ready() -> bool:
	return (
		core != null
		and (
			core.progression.discovery.has_wish_offer()
			or core.progression.discovery.has_pending()
		)
	)


func is_open() -> bool:
	return _panel != null and _panel.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open_pending()


func open_pending() -> void:
	if not is_ready() or is_open():
		return
	_rebuild_choices()
	_panel.visible = true
	panel_toggled.emit(true)
	var entries := _entries()
	if not entries.is_empty():
		reveal_started.emit((entries[0] as Dictionary).duplicate(true))
	_panel.modulate.a = 0.0
	_panel.position.y -= 5.0
	var tween := _panel.create_tween().set_parallel(true)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.16)
	tween.tween_property(_panel, "position:y", _panel.position.y + 5.0, 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	focus_default()


func close() -> void:
	if _panel == null or not _panel.visible:
		return
	_input_service.release_focus_in(_panel)
	_panel.visible = false
	_thumbnail_renderer.discard_pending()
	panel_toggled.emit(false)


func focus_default() -> void:
	if is_open():
		_input_service.focus_first(_panel, _first_button)
	elif _chip != null and _chip.visible:
		_input_service.focus_first(_root, _chip)


func blocks_world_pointer(screen_position: Vector2) -> bool:
	if _chip != null and _chip.visible and _chip.get_global_rect().has_point(screen_position):
		return true
	return (
		_panel != null
		and _panel.visible
		and _panel.get_global_rect().has_point(screen_position)
	)


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("cancel"):
		close()
		get_viewport().set_input_as_handled()


func _rebuild_choices() -> void:
	for child in _choice_row.get_children():
		child.queue_free()
	_choice_buttons.clear()
	_first_button = null
	var entries := _entries()
	for index in entries.size():
		var entry: Dictionary = entries[index]
		_choice_row.add_child(_choice(entry, index))


func _entries() -> Array[Dictionary]:
	if core.progression.discovery.has_wish_offer():
		return core.progression.discovery.current_wish_choices()
	if core.progression.discovery.has_pending():
		return [core.progression.discovery.peek_pending()]
	return []


func _choice(entry: Dictionary, index: int) -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = CHOICE_WIDTH
	column.add_theme_constant_override("separation", 4)

	var preview_frame := PanelContainer.new()
	preview_frame.custom_minimum_size = Vector2(CHOICE_WIDTH, 86.0)
	var accent := kit.palette.color("ui_accent")
	var frame_style := kit.surface_style(
		kit.palette.color("ui_surface"),
		10,
		accent.lightened(0.36),
		1
	)
	frame_style.set_content_margin_all(3)
	preview_frame.add_theme_stylebox_override("panel", frame_style)
	column.add_child(preview_frame)
	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_frame.add_child(preview)
	_thumbnail_renderer.request(
		String(entry.get("kind", "")),
		String(entry.get("id", "")),
		func(texture):
			if is_instance_valid(preview):
				preview.texture = texture
	)

	var button := kit.button(_display_name(entry), false)
	button.custom_minimum_size = Vector2(CHOICE_WIDTH, 38.0)
	button.add_theme_font_size_override("font_size", 13)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = "%s %s" % [
		"New" if bool(entry.get("was_new", false)) else "Another",
		"piece of land" if String(entry.get("kind", "")) == "tile" else "model",
	]
	button.pressed.connect(func(): _select(index))
	column.add_child(button)
	_choice_buttons.append(button)
	if _first_button == null:
		_first_button = button
	return column


func _select(index: int) -> void:
	for button in _choice_buttons:
		button.disabled = true
	var entry := (
		core.progression.discovery.choose_wish(index)
		if core.progression.discovery.has_wish_offer()
		else core.progression.discovery.peek_pending()
	)
	if entry.is_empty():
		for button in _choice_buttons:
			button.disabled = false
		return
	var acknowledged := core.progression.discovery.acknowledge_next()
	if not acknowledged.is_empty():
		entry = acknowledged
	core.autosave_soon()
	close()
	notify_ready(false)
	reveal_finished.emit(entry)


func _display_name(entry: Dictionary) -> String:
	var content_id := String(entry.get("id", ""))
	var definition: Variant = (
		core.registries.tile(content_id)
		if String(entry.get("kind", "")) == "tile"
		else core.registries.structure(content_id)
	)
	return definition.display_name if definition != null else content_id.capitalize()


func _refresh_prompt() -> void:
	if _chip == null or _input_service == null:
		return
	_chip.tooltip_text = "%s. Choose one piece to call into your world." % (
		_input_service.format_action(&"wish_menu", "Open wish")
	)
