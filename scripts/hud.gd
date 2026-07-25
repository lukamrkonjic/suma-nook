extends CanvasLayer
class_name TilegardenHUD

signal seed_drag_started(token_id: StringName)
signal seed_drag_released(token_id: StringName, screen_position: Vector2)
signal offer_pressed(token_id: StringName)
signal storage_toggled
signal collection_toggled
signal retrieve_requested(definition_id: StringName)
signal store_requested
signal recycle_requested
signal cancel_requested
signal focus_requested
signal save_requested
signal settings_requested
signal scene_requested

const UI_INK := Color("#514337")
const UI_MUTED := Color("#817466")
const UI_CREAM := Color("#fffaf0")
const UI_CARD := Color(1.0, 0.98, 0.91, 0.94)
const UI_LINE := Color("#d9cdbb")
const UI_LIME := Color("#91a82b")
const UI_ORANGE := Color("#d76c2a")


class CoinGlyph extends Control:
	var color := Color.WHITE
	var accent := Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(30, 30)
		size = Vector2(30, 30)
		queue_redraw()

	func _draw() -> void:
		draw_circle(Vector2(15, 15), 13.0, Color(UI_INK, 0.10))
		draw_circle(Vector2(15, 14), 12.0, color)
		draw_arc(Vector2(15, 14), 9.0, 0, TAU, 24, accent, 2.0, true)
		draw_circle(Vector2(15, 14), 3.3, accent)


var data: GameData
var economy: EconomyManager
var storage: StorageManager
var collection: CollectionManager
var grid: GridManager
var root: Control
var seed_buttons: Dictionary = {}
var offer_button: Button
var storage_panel: PanelContainer
var storage_list: VBoxContainer
var collection_panel: PanelContainer
var collection_list: VBoxContainer
var settings_panel: PanelContainer
var context_panel: PanelContainer
var selected_label: Label
var recycle_bar: ProgressBar
var modifier_badge: Label
var scene_button: Button
var toast: Label
var hint: Label
var drag_glyph: CoinGlyph
var dragging_token := &""
var last_token := &"meadow_coin"
var _toast_tween: Tween


func setup(
		game_data: GameData,
		economy_manager: EconomyManager,
		storage_manager: StorageManager,
		collection_manager: CollectionManager,
		grid_manager: GridManager
	) -> void:
	data = game_data
	economy = economy_manager
	storage = storage_manager
	collection = collection_manager
	grid = grid_manager
	_build_ui()
	economy.tokens_changed.connect(_on_tokens_changed)
	economy.recycle_progress_changed.connect(_on_recycle_progress)
	storage.changed.connect(func(_id: StringName, _amount: int) -> void: rebuild_storage())
	collection.changed.connect(func(_id: StringName) -> void:
		if collection_panel.visible:
			rebuild_collection())
	for token_id: StringName in data.tokens:
		_on_tokens_changed(token_id, economy.amount(token_id))
	_on_recycle_progress(economy.recycle_progress, economy.recycle_target)


func _process(_delta: float) -> void:
	if drag_glyph != null:
		drag_glyph.position = get_viewport().get_mouse_position() - drag_glyph.size * 0.5


func _build_ui() -> void:
	root = Control.new()
	root.name = "HUD"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.theme = _make_theme()

	var coin_card := PanelContainer.new()
	coin_card.position = Vector2(22, 20)
	coin_card.custom_minimum_size = Vector2(0, 54)
	root.add_child(coin_card)
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 7)
	coin_card.add_child(coin_row)
	for token_id: StringName in data.tokens:
		var button := Button.new()
		button.custom_minimum_size = Vector2(158, 40)
		button.tooltip_text = "Drag this coin to the Bloomforge, or select it and press Spend"
		button.gui_input.connect(func(event: InputEvent) -> void:
			_handle_coin_button_input(event, token_id))
		button.pressed.connect(func() -> void:
			last_token = token_id
			offer_button.disabled = economy.amount(last_token) <= 0)
		coin_row.add_child(button)
		seed_buttons[token_id] = button
	offer_button = Button.new()
	offer_button.text = "Spend"
	offer_button.custom_minimum_size = Vector2(78, 40)
	offer_button.tooltip_text = "Spend the selected coin at the Bloomforge"
	offer_button.pressed.connect(func() -> void: offer_pressed.emit(last_token))
	coin_row.add_child(offer_button)

	var right_card := PanelContainer.new()
	right_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_card.position = Vector2(-430, 20)
	right_card.custom_minimum_size = Vector2(408, 54)
	root.add_child(right_card)
	var right_row := HBoxContainer.new()
	right_row.add_theme_constant_override("separation", 6)
	right_card.add_child(right_row)
	var storage_button := _small_button("Storage", "Open stored items")
	storage_button.pressed.connect(func() -> void:
		storage_panel.visible = not storage_panel.visible
		collection_panel.visible = false
		if storage_panel.visible:
			rebuild_storage()
		storage_toggled.emit())
	right_row.add_child(storage_button)
	var collection_button := _small_button("Collection", "Open the themed collection")
	collection_button.pressed.connect(func() -> void:
		collection_panel.visible = not collection_panel.visible
		storage_panel.visible = false
		if collection_panel.visible:
			rebuild_collection()
		collection_toggled.emit())
	right_row.add_child(collection_button)
	scene_button = _small_button("Sunroom", "Cycle lighting, effects, and background")
	scene_button.pressed.connect(func() -> void: scene_requested.emit())
	right_row.add_child(scene_button)
	var settings_button := _small_button("Sound", "Open sound controls")
	settings_button.pressed.connect(func() -> void:
		settings_panel.visible = not settings_panel.visible
		settings_requested.emit())
	right_row.add_child(settings_button)

	hint = Label.new()
	hint.text = "EARN COINS: click a visitor  •  UNLOCK PIECES: spend coins at the Bloomforge"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint.position = Vector2(-270, 88)
	hint.size = Vector2(540, 30)
	hint.add_theme_color_override("font_color", UI_INK)
	hint.add_theme_font_size_override("font_size", 17)
	root.add_child(hint)
	var hint_tween := create_tween()
	hint_tween.tween_interval(14.0)
	hint_tween.tween_property(hint, "modulate:a", 0.0, 1.0)

	modifier_badge = Label.new()
	modifier_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modifier_badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
	modifier_badge.position = Vector2(-250, 120)
	modifier_badge.size = Vector2(500, 28)
	modifier_badge.add_theme_color_override("font_color", UI_ORANGE)
	modifier_badge.add_theme_font_size_override("font_size", 14)
	modifier_badge.visible = false
	root.add_child(modifier_badge)

	toast = Label.new()
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.set_anchors_preset(Control.PRESET_CENTER)
	toast.position = Vector2(-300, -260)
	toast.size = Vector2(600, 42)
	toast.modulate.a = 0.0
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.85))
	toast.add_theme_constant_override("outline_size", 6)
	root.add_child(toast)

	_build_context_panel()
	_build_storage_panel()
	_build_collection_panel()
	_build_settings_panel()


func _build_context_panel() -> void:
	context_panel = PanelContainer.new()
	context_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	context_panel.position = Vector2(-300, -78)
	context_panel.size = Vector2(600, 58)
	context_panel.visible = false
	root.add_child(context_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	context_panel.add_child(row)
	selected_label = Label.new()
	selected_label.custom_minimum_size = Vector2(285, 42)
	selected_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(selected_label)
	var store := _small_button("Store", "Put the held piece in storage")
	store.pressed.connect(func() -> void: store_requested.emit())
	row.add_child(store)
	var sell := _small_button("Sell", "Sell the held piece toward a Meadow Coin")
	sell.pressed.connect(func() -> void: recycle_requested.emit())
	row.add_child(sell)
	var cancel := _small_button("Cancel", "Return the held piece")
	cancel.pressed.connect(func() -> void: cancel_requested.emit())
	row.add_child(cancel)


func _build_storage_panel() -> void:
	storage_panel = PanelContainer.new()
	storage_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	storage_panel.position = Vector2(-402, 92)
	storage_panel.size = Vector2(380, 500)
	storage_panel.visible = false
	root.add_child(storage_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	storage_panel.add_child(box)
	var title := Label.new()
	title.text = "STORAGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var explanation := Label.new()
	explanation.text = "Stored pieces are safe. Selling fills the coin press."
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explanation.add_theme_color_override("font_color", UI_MUTED)
	box.add_child(explanation)
	recycle_bar = ProgressBar.new()
	recycle_bar.custom_minimum_size = Vector2(0, 20)
	recycle_bar.show_percentage = false
	box.add_child(recycle_bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	storage_list = VBoxContainer.new()
	storage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_list.add_theme_constant_override("separation", 6)
	scroll.add_child(storage_list)


func _build_collection_panel() -> void:
	collection_panel = PanelContainer.new()
	collection_panel.set_anchors_preset(Control.PRESET_CENTER)
	collection_panel.position = Vector2(-380, -265)
	collection_panel.size = Vector2(760, 540)
	collection_panel.visible = false
	root.add_child(collection_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	collection_panel.add_child(box)
	var title := Label.new()
	title.text = "YOUR COLLECTION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Discover every piece in the Meadow, Hearth, and Tide sets."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", UI_MUTED)
	box.add_child(subtitle)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	collection_list = VBoxContainer.new()
	collection_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection_list.add_theme_constant_override("separation", 12)
	scroll.add_child(collection_list)


func _build_settings_panel() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	settings_panel.position = Vector2(-350, 92)
	settings_panel.size = Vector2(328, 330)
	settings_panel.visible = false
	root.add_child(settings_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	settings_panel.add_child(box)
	var title := Label.new()
	title.text = "SOUND"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	for bus_name: String in ["Master", "Ambience", "UI", "SFX", "Creatures"]:
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.text = bus_name
		label.custom_minimum_size = Vector2(92, 30)
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = -36.0
		slider.max_value = 0.0
		slider.step = 1.0
		slider.custom_minimum_size = Vector2(185, 30)
		var bus_index := AudioServer.get_bus_index(bus_name)
		slider.value = AudioServer.get_bus_volume_db(bus_index) if bus_index >= 0 else -8.0
		slider.value_changed.connect(func(value: float) -> void:
			var index := AudioServer.get_bus_index(bus_name)
			if index >= 0:
				AudioServer.set_bus_volume_db(index, value))
		row.add_child(slider)
	var close := Button.new()
	close.text = "Done"
	close.pressed.connect(func() -> void: settings_panel.visible = false)
	box.add_child(close)


func _small_button(text_value: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(84, 40)
	return button


func _handle_coin_button_input(event: InputEvent, token_id: StringName) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and economy.amount(token_id) > 0:
			last_token = token_id
			offer_button.disabled = false
			dragging_token = token_id
			drag_glyph = _make_coin_glyph(token_id)
			root.add_child(drag_glyph)
			seed_drag_started.emit(token_id)
		elif not event.pressed and dragging_token == token_id:
			var position := get_viewport().get_mouse_position()
			seed_drag_released.emit(token_id, position)
			finish_seed_drag()


func finish_seed_drag() -> void:
	dragging_token = &""
	if drag_glyph != null:
		drag_glyph.queue_free()
	drag_glyph = null


func animate_seed_collection(start: Vector2, token_id: StringName, callback: Callable) -> void:
	var glyph := _make_coin_glyph(token_id)
	root.add_child(glyph)
	glyph.position = start - glyph.size * 0.5
	var target_button := seed_buttons.get(token_id) as Button
	var target := target_button.global_position + target_button.size * 0.5
	var control := start + Vector2(0, -125)
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		var a := start.lerp(control, t)
		var b := control.lerp(target, t)
		glyph.position = a.lerp(b, t) - glyph.size * 0.5
		glyph.rotation = t * TAU * 1.4
	, 0.0, 1.0, 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void:
		glyph.queue_free()
		_pulse_control(target_button)
		if callback.is_valid():
			callback.call())


func animate_seed_offer(token_id: StringName, target: Vector2, callback: Callable) -> void:
	var source_button := seed_buttons.get(token_id) as Button
	var source := source_button.global_position + source_button.size * 0.5
	var glyph := _make_coin_glyph(token_id)
	root.add_child(glyph)
	glyph.position = source - glyph.size * 0.5
	var control := (source + target) * 0.5 + Vector2(0, -100)
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		var a := source.lerp(control, t)
		var b := control.lerp(target, t)
		glyph.position = a.lerp(b, t) - glyph.size * 0.5
		glyph.scale = Vector2.ONE * (1.0 - 0.30 * t)
		glyph.rotation = t * TAU
	, 0.0, 1.0, 0.46).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		glyph.queue_free()
		if callback.is_valid():
			callback.call())


func set_held(definition_id: StringName) -> void:
	context_panel.visible = definition_id != &""
	if definition_id != &"":
		selected_label.text = "%s\nR rotate  ·  Esc cancel" % data.item(definition_id).display_name


func set_scene_name(value: String) -> void:
	if scene_button != null:
		scene_button.text = value
	var dark_scene := value != "Sunroom"
	if hint != null:
		hint.add_theme_color_override("font_color", UI_CREAM if dark_scene else UI_INK)
	if modifier_badge != null:
		modifier_badge.add_theme_color_override(
			"font_color", Color("#ffd36b") if dark_scene else UI_ORANGE)


func set_modifier_summary(values: PackedStringArray) -> void:
	if modifier_badge == null:
		return
	modifier_badge.visible = not values.is_empty()
	modifier_badge.text = "Loot odds: %s" % "  ·  ".join(values)


func show_toast(message: String, positive := true) -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	toast.text = message
	toast.add_theme_color_override("font_color", UI_LIME if positive else UI_ORANGE)
	toast.modulate.a = 0.0
	toast.position.y = -250
	_toast_tween = create_tween()
	_toast_tween.set_parallel(true)
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.14)
	_toast_tween.tween_property(toast, "position:y", -260.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.chain().tween_interval(1.85)
	_toast_tween.chain().set_parallel(true)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.34)
	_toast_tween.tween_property(toast, "position:y", -274.0, 0.34)


func rebuild_storage() -> void:
	for child: Node in storage_list.get_children():
		child.queue_free()
	if storage.counts.is_empty():
		var empty := Label.new()
		empty.text = "Nothing tucked away yet.\nHold any piece and choose Store."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		storage_list.add_child(empty)
		return
	var ids := storage.counts.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return data.item(a).display_name < data.item(b).display_name)
	for id: StringName in ids:
		var button := Button.new()
		button.text = "%s   ×%d" % [data.item(id).display_name, storage.amount(id)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 42)
		button.pressed.connect(func() -> void: retrieve_requested.emit(id))
		storage_list.add_child(button)


func rebuild_collection() -> void:
	for child: Node in collection_list.get_children():
		child.queue_free()
	for pool: String in ["meadow", "hearth", "tide"]:
		var header := Label.new()
		header.text = "%s SET" % pool.to_upper()
		header.add_theme_font_size_override("font_size", 18)
		header.add_theme_color_override("font_color", _pool_color(pool))
		collection_list.add_child(header)
		var grid_list := GridContainer.new()
		grid_list.columns = 3
		grid_list.add_theme_constant_override("h_separation", 8)
		grid_list.add_theme_constant_override("v_separation", 8)
		collection_list.add_child(grid_list)
		var ids := data.item_ids_for_pool(StringName(pool))
		ids.sort()
		for raw_id: String in ids:
			var id := StringName(raw_id)
			var discovered := collection.is_discovered(id)
			var button := Button.new()
			button.custom_minimum_size = Vector2(220, 62)
			button.disabled = not discovered
			if discovered:
				var owned := collection.current_owned(id, grid, storage)
				var fresh := "  NEW" if collection.new_markers.has(id) else ""
				button.text = "%s%s\n%d owned  ·  %d found" % [
					data.item(id).display_name, fresh, owned, collection.total(id)]
				button.pressed.connect(func() -> void: collection.mark_seen(id))
			else:
				button.text = "Undiscovered\n?"
			grid_list.add_child(button)


func close_panels() -> bool:
	var closed := storage_panel.visible or collection_panel.visible or settings_panel.visible
	storage_panel.visible = false
	collection_panel.visible = false
	settings_panel.visible = false
	return closed


func pointer_over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered != root


func _on_tokens_changed(token_id: StringName, amount: int) -> void:
	var token := data.token(token_id)
	var button := seed_buttons.get(token_id) as Button
	if button != null:
		button.text = "●  %s   %d" % [token.display_name.trim_suffix(" Coin"), amount]
		button.add_theme_color_override("font_color", token.palette[1] if token.palette.size() > 1 else UI_INK)
		button.disabled = amount <= 0
	offer_button.disabled = economy.amount(last_token) <= 0


func _on_recycle_progress(progress: int, target: int) -> void:
	if recycle_bar == null:
		return
	recycle_bar.max_value = target
	recycle_bar.value = progress
	recycle_bar.tooltip_text = "%d / %d sale value toward a Meadow Coin" % [progress, target]


func _make_coin_glyph(token_id: StringName) -> CoinGlyph:
	var token := data.token(token_id)
	var glyph := CoinGlyph.new()
	glyph.color = token.palette[0] if not token.palette.is_empty() else Color.WHITE
	glyph.accent = token.palette[2] if token.palette.size() > 2 else glyph.color.lightened(0.25)
	return glyph


func _pool_color(pool: String) -> Color:
	match pool:
		"hearth": return UI_ORANGE
		"tide": return Color("#4c9690")
		_: return UI_LIME


func _pulse_control(control: Control) -> void:
	control.pivot_offset = control.size * 0.5
	var tween := create_tween()
	tween.tween_property(control, "scale", Vector2.ONE * 1.10, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", UI_INK)
	theme.set_color("font_color", "Button", UI_INK)
	theme.set_color("font_hover_color", "Button", Color("#2f2822"))
	theme.set_color("font_pressed_color", "Button", Color("#2f2822"))
	theme.set_color("font_disabled_color", "Button", Color(UI_MUTED, 0.55))
	theme.set_stylebox("panel", "PanelContainer", _style(UI_CARD, UI_LINE, 14, 12))
	theme.set_stylebox("normal", "Button", _style(Color(1, 1, 1, 0.66), Color(1, 1, 1, 0), 10, 10))
	theme.set_stylebox("hover", "Button", _style(Color("#fff9e9"), Color("#e0cda9"), 10, 10))
	theme.set_stylebox("pressed", "Button", _style(Color("#f2e6cc"), Color("#cfb98e"), 10, 10))
	theme.set_stylebox("disabled", "Button", _style(Color(0.92, 0.89, 0.82, 0.46), Color(1, 1, 1, 0), 10, 10))
	theme.set_stylebox("background", "ProgressBar", _style(Color("#e5ddce"), Color(1, 1, 1, 0), 8, 1))
	theme.set_stylebox("fill", "ProgressBar", _style(Color("#aabc38"), Color(1, 1, 1, 0), 8, 1))
	return theme


func _style(fill: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0.0 else 0)
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box
