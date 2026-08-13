class_name WishOfferPanel
extends CanvasLayer
## A quiet, persistent corner prompt. It never interrupts play: the player
## opens it when ready, chooses one of three collections, then the sky resolves
## one surprise piece from that category and calls it into the world.

signal reveal_finished(entry: Dictionary)
signal reveal_started(entry: Dictionary)
signal panel_toggled(open: bool)

const PANEL_WIDTH := 516.0
const CHOICE_WIDTH := 148.0

var core: GameCore
var kit: UiKit
var _input_service: InputDeviceService
var _thumbnail_renderer: BuildThumbnailRenderer
var _root: Control
var _chip: Button
var _panel: PanelContainer
var _choice_grid: HFlowContainer
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

	_chip = kit.hud_chip(
		"WISH  /  READY", kit.collection_accent("collections")
	)
	_chip.name = "WishReady"
	kit.place_hud_chip(_chip, true, 190.0)
	_chip.focus_mode = Control.FOCUS_ALL
	_chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_chip.visible = false
	_chip.pressed.connect(toggle)
	_root.add_child(_chip)

	_panel = kit.card()
	_panel.name = "WishChoices"
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	_panel.offset_left = -PANEL_WIDTH - 16.0
	_panel.offset_right = -UiKit.HUD_MARGIN
	_panel.offset_top = UiKit.HUD_MARGIN + 56.0
	_panel.offset_bottom = UiKit.HUD_MARGIN + 56.0
	_panel.add_theme_stylebox_override("panel", kit.cloud_panel_style())
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
	var heading := kit.display_label(
		"What kind of thing should the sky bring?", 24
	)
	column.add_child(heading)
	column.add_child(kit.divider())
	var hint := kit.muted_label("Wish for a collection. One surprise will answer.", 13)
	column.add_child(hint)

	_choice_grid = HFlowContainer.new()
	_choice_grid.alignment = FlowContainer.ALIGNMENT_CENTER
	_choice_grid.add_theme_constant_override("h_separation", 8)
	_choice_grid.add_theme_constant_override("v_separation", 8)
	_choice_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_choice_grid)
	_fit_panel_to_content()
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
	_chip.modulate.a = 0.0
	var duration := kit.motion_duration(kit.tokens.open_duration)
	if duration <= 0.0:
		_chip.modulate.a = 1.0
		return
	_chip_tween = _chip.create_tween()
	_chip_tween.tween_property(_chip, "modulate:a", 1.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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
	for child in _choice_grid.get_children():
		child.queue_free()
	_choice_buttons.clear()
	_first_button = null
	var entries := _entries()
	for index in entries.size():
		var entry: Dictionary = entries[index]
		_choice_grid.add_child(_choice(entry, index))
	_fit_panel_to_content()


func _fit_panel_to_content() -> void:
	if not is_instance_valid(_panel):
		return
	var maximum_width := minf(PANEL_WIDTH, maxf(240.0, _root.size.x - 32.0))
	_panel.custom_minimum_size.x = maximum_width
	_panel.offset_left = -maximum_width - UiKit.HUD_MARGIN
	_panel.offset_right = -UiKit.HUD_MARGIN


func _entries() -> Array[Dictionary]:
	if core.progression.discovery.has_wish_offer():
		return core.progression.discovery.current_wish_choices()
	if core.progression.discovery.has_pending():
		var pending := core.progression.discovery.peek_pending()
		var category_id := String(pending.get("category", ""))
		return [{
			"category": category_id,
			"name": String(pending.get(
				"category_name", category_id.capitalize()
			)),
			"icon": BuildCategoryResolver.icon_path(category_id),
			"description": "A concealed piece is waiting to fall.",
			"pending_reward": true,
		}]
	return []


func _choice(entry: Dictionary, index: int) -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = CHOICE_WIDTH
	column.add_theme_constant_override("separation", 4)

	var preview_frame := PanelContainer.new()
	preview_frame.custom_minimum_size = Vector2(CHOICE_WIDTH, 86.0)
	var accent := kit.collection_accent(
		String(entry.get("category", entry.get("kind", "collections")))
	)
	var frame_style := kit.surface_style(
		Color(kit.palette.color("ui_surface"), 0.36),
		UiKit.CORNER_SMALL,
		accent,
		1
	)
	frame_style.set_content_margin_all(3)
	preview_frame.add_theme_stylebox_override("panel", frame_style)
	column.add_child(preview_frame)
	if entry.has("category"):
		var category_column := VBoxContainer.new()
		category_column.alignment = BoxContainer.ALIGNMENT_CENTER
		category_column.add_theme_constant_override("separation", 2)
		preview_frame.add_child(category_column)
		var category_id := String(entry.get("category", ""))
		var icon_path := String(entry.get(
			"icon", BuildCategoryResolver.icon_path(category_id)
		))
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(30.0, 30.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		category_column.add_child(icon)
		var description := kit.muted_label(
			String(entry.get("description", "A surprise from this collection.")),
			10
		)
		description.custom_minimum_size = Vector2(CHOICE_WIDTH - 12.0, 30.0)
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		category_column.add_child(description)
	else:
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
	button.tooltip_text = (
		"Call the concealed %s wish into the world." % _display_name(entry)
		if bool(entry.get("pending_reward", false))
		else "Wish for %s. One fitting piece will fall." % _display_name(entry)
		if entry.has("category")
		else "Call this saved wish into the world."
	)
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
	core.autosave_soon()
	close()
	notify_ready(false)
	reveal_finished.emit(entry)


func _display_name(entry: Dictionary) -> String:
	if entry.has("category"):
		return String(entry.get("name", entry.get("category", "Wish").capitalize()))
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
	_chip.tooltip_text = "%s. Choose a collection to wish for." % (
		_input_service.format_action(&"wish_menu", "Open wish")
	)
