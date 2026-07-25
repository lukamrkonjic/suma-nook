extends CanvasLayer
class_name TilegardenHUD

const PixelArt := preload("res://scripts/pixel_art.gd")

signal seed_drag_started(token_id: StringName)
signal seed_drag_released(token_id: StringName, screen_position: Vector2)
signal offer_pressed(token_id: StringName)
signal grow_requested
signal character_confirmed(player_name: String, appearance: Dictionary)
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

const UI_INK := Color("#172b24")
const UI_MUTED := Color("#9db69b")
const UI_CREAM := Color("#f3e9c8")
const UI_CARD := Color(0.08, 0.17, 0.12, 0.94)
const UI_LINE := Color("#527044")
const UI_LIME := Color("#a9d65e")
const UI_ORANGE := Color("#e6a75b")


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
var grow_button: Button
var growth_label: Label
var milestone_label: Label
var toast: Label
var hint: Label
var drag_glyph: CoinGlyph
var dragging_token := &""
var last_token := &"meadow_coin"
var _toast_tween: Tween
var character_overlay: Control
var character_preview: TextureRect
var character_name: LineEdit
var character_appearance := {"skin": 1, "hair": 0, "outfit": 0}


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

	var light_card := PanelContainer.new()
	light_card.position = Vector2(24, 22)
	light_card.custom_minimum_size = Vector2(318, 104)
	root.add_child(light_card)
	var light_box := VBoxContainer.new()
	light_box.add_theme_constant_override("separation", 5)
	light_card.add_child(light_box)
	var eyebrow := Label.new()
	eyebrow.text = "✦  FOREST LIGHT"
	eyebrow.add_theme_font_size_override("font_size", 15)
	eyebrow.add_theme_color_override("font_color", UI_ORANGE)
	light_box.add_child(eyebrow)
	var light_row := HBoxContainer.new()
	light_row.add_theme_constant_override("separation", 8)
	light_box.add_child(light_row)
	var meadow_button := Button.new()
	meadow_button.custom_minimum_size = Vector2(118, 42)
	meadow_button.tooltip_text = "Forest wisps carry light. Click a wisp to collect it."
	meadow_button.pressed.connect(func() -> void: grow_requested.emit())
	light_row.add_child(meadow_button)
	seed_buttons[&"meadow_coin"] = meadow_button
	grow_button = Button.new()
	grow_button.text = "GROW TILE  [G]"
	grow_button.custom_minimum_size = Vector2(156, 42)
	grow_button.tooltip_text = "Spend one Forest Light, then choose an empty edge of your world."
	grow_button.pressed.connect(func() -> void: grow_requested.emit())
	light_row.add_child(grow_button)
	for token_id: StringName in data.tokens:
		if token_id == &"meadow_coin":
			continue
		var hidden_button := Button.new()
		hidden_button.visible = false
		hidden_button.position = Vector2(-200, -200)
		root.add_child(hidden_button)
		seed_buttons[token_id] = hidden_button
	offer_button = Button.new()
	offer_button.visible = false
	offer_button.pressed.connect(func() -> void: offer_pressed.emit(last_token))
	root.add_child(offer_button)

	var right_card := PanelContainer.new()
	right_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_card.position = Vector2(-474, 22)
	right_card.custom_minimum_size = Vector2(450, 58)
	root.add_child(right_card)
	var right_row := HBoxContainer.new()
	right_row.add_theme_constant_override("separation", 6)
	right_card.add_child(right_row)
	var storage_button := _small_button("Pack", "Open discovered decorations")
	storage_button.pressed.connect(func() -> void:
		storage_panel.visible = not storage_panel.visible
		collection_panel.visible = false
		if storage_panel.visible:
			rebuild_storage()
		storage_toggled.emit())
	right_row.add_child(storage_button)
	var collection_button := _small_button("Guide", "Open your woodland discoveries")
	collection_button.pressed.connect(func() -> void:
		collection_panel.visible = not collection_panel.visible
		storage_panel.visible = false
		if collection_panel.visible:
			rebuild_collection()
		collection_toggled.emit())
	right_row.add_child(collection_button)
	scene_button = _small_button("Greenwood", "Cycle forest weather and time")
	scene_button.pressed.connect(func() -> void: scene_requested.emit())
	right_row.add_child(scene_button)
	var settings_button := _small_button("Sound", "Open sound controls")
	settings_button.pressed.connect(func() -> void:
		settings_panel.visible = not settings_panel.visible
		settings_requested.emit())
	right_row.add_child(settings_button)

	hint = Label.new()
	hint.text = "WASD / ARROWS walk  •  click a tile to travel  •  click a wisp for light  •  G grows the world"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint.position = Vector2(-410, 102)
	hint.size = Vector2(820, 30)
	hint.add_theme_color_override("font_color", UI_CREAM)
	hint.add_theme_font_size_override("font_size", 16)
	root.add_child(hint)
	var hint_tween := create_tween()
	hint_tween.tween_interval(14.0)
	hint_tween.tween_property(hint, "modulate:a", 0.0, 1.0)

	modifier_badge = Label.new()
	modifier_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modifier_badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
	modifier_badge.position = Vector2(-250, 132)
	modifier_badge.size = Vector2(500, 28)
	modifier_badge.add_theme_color_override("font_color", UI_ORANGE)
	modifier_badge.add_theme_font_size_override("font_size", 14)
	modifier_badge.visible = false
	root.add_child(modifier_badge)

	toast = Label.new()
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.set_anchors_preset(Control.PRESET_CENTER)
	toast.position = Vector2(-360, -258)
	toast.size = Vector2(720, 42)
	toast.modulate.a = 0.0
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_outline_color", UI_INK)
	toast.add_theme_constant_override("outline_size", 8)
	root.add_child(toast)

	var progress_card := PanelContainer.new()
	progress_card.position = Vector2(24, 138)
	progress_card.custom_minimum_size = Vector2(318, 72)
	root.add_child(progress_card)
	var progress_box := VBoxContainer.new()
	progress_box.add_theme_constant_override("separation", 2)
	progress_card.add_child(progress_box)
	growth_label = Label.new()
	growth_label.text = "YOUR NOOK  •  9 TILES"
	growth_label.add_theme_color_override("font_color", UI_LIME)
	progress_box.add_child(growth_label)
	milestone_label = Label.new()
	milestone_label.text = "3 more tiles → Sapling"
	milestone_label.add_theme_color_override("font_color", UI_MUTED)
	milestone_label.add_theme_font_size_override("font_size", 14)
	progress_box.add_child(milestone_label)

	_build_context_panel()
	_build_storage_panel()
	_build_collection_panel()
	_build_settings_panel()
	_build_character_creator()


func _build_character_creator() -> void:
	character_overlay = Control.new()
	character_overlay.name = "CharacterCreator"
	character_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	character_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	character_overlay.visible = false
	root.add_child(character_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color("#10251d")
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	character_overlay.add_child(shade)
	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.position = Vector2(-275, -245)
	frame.size = Vector2(550, 490)
	character_overlay.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	frame.add_child(box)
	var title := Label.new()
	title.text = "WHO WAKES IN THE NOOK?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UI_LIME)
	box.add_child(title)
	var intro := Label.new()
	intro.text = "Choose your tiny forest keeper. You begin on nine tiles,\nthen gather light and grow the world one piece at a time."
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.add_theme_color_override("font_color", UI_CREAM)
	box.add_child(intro)
	character_preview = TextureRect.new()
	character_preview.custom_minimum_size = Vector2(120, 150)
	character_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	character_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	character_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(character_preview)
	character_name = LineEdit.new()
	character_name.placeholder_text = "Your name"
	character_name.text = "Fern"
	character_name.max_length = 16
	character_name.custom_minimum_size = Vector2(0, 44)
	character_name.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(character_name)
	var choices := HBoxContainer.new()
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	choices.add_theme_constant_override("separation", 8)
	box.add_child(choices)
	for row: Array in [["SKIN", "skin", 4], ["HAIR", "hair", 4], ["OUTFIT", "outfit", 4]]:
		var button := Button.new()
		button.text = "%s  ◀ ▶" % row[0]
		button.custom_minimum_size = Vector2(145, 44)
		var key := str(row[1])
		var count := int(row[2])
		button.pressed.connect(func() -> void:
			character_appearance[key] = posmod(int(character_appearance[key]) + 1, count)
			_refresh_character_preview())
		choices.add_child(button)
	var begin := Button.new()
	begin.text = "ENTER THE GREENWOOD"
	begin.custom_minimum_size = Vector2(0, 54)
	begin.add_theme_font_size_override("font_size", 19)
	begin.pressed.connect(func() -> void:
		var chosen_name := character_name.text.strip_edges()
		if chosen_name.is_empty():
			chosen_name = "Fern"
		character_overlay.visible = false
		character_confirmed.emit(chosen_name, character_appearance.duplicate(true)))
	box.add_child(begin)
	_refresh_character_preview()


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
	var sell := _small_button("Recycle", "Recycle the held piece toward Forest Light")
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
	title.text = "WOODLAND PACK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var explanation := Label.new()
	explanation.text = "Milestones add decorations here. Place them anywhere in your growing nook."
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
	title.text = "FIELD GUIDE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Grow farther into the greenwood to remember new plants, paths, and relics."
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
	button.custom_minimum_size = Vector2(96, 40)
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
	var dark_scene := true
	if hint != null:
		hint.add_theme_color_override("font_color", UI_CREAM if dark_scene else UI_INK)
	if modifier_badge != null:
		modifier_badge.add_theme_color_override(
			"font_color", Color("#ffd36b") if dark_scene else UI_ORANGE)


func set_modifier_summary(values: PackedStringArray) -> void:
	if modifier_badge == null:
		return
	modifier_badge.visible = false


func show_character_creator(default_state: Dictionary = {}) -> void:
	if not default_state.is_empty():
		character_name.text = str(default_state.get("name", "Fern"))
		character_appearance = (default_state.get("appearance", character_appearance) as Dictionary).duplicate(true)
	_refresh_character_preview()
	character_overlay.visible = true


func set_forest_progress(light: int, total_tiles: int, next_milestone: String) -> void:
	if grow_button != null:
		grow_button.disabled = light <= 0
	if growth_label != null:
		growth_label.text = "YOUR NOOK  •  %d TILES" % total_tiles
	if milestone_label != null:
		milestone_label.text = next_milestone


func _refresh_character_preview() -> void:
	if character_preview != null:
		character_preview.texture = PixelArt.character_texture(character_appearance)


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
		empty.text = "Your pack is empty.\nGrow three new tiles to unlock your first sapling."
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
		header.text = "%s MEMORIES" % pool.to_upper()
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
		button.text = "✦  %d" % amount if token_id == &"meadow_coin" else str(amount)
		button.add_theme_color_override("font_color", UI_ORANGE if token_id == &"meadow_coin" else UI_INK)
		button.disabled = amount <= 0
	offer_button.disabled = economy.amount(last_token) <= 0
	if grow_button != null:
		grow_button.disabled = economy.amount(&"meadow_coin") <= 0


func _on_recycle_progress(progress: int, target: int) -> void:
	if recycle_bar == null:
		return
	recycle_bar.max_value = target
	recycle_bar.value = progress
	recycle_bar.tooltip_text = "%d / %d reclaimed value toward one Forest Light" % [progress, target]


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
	theme.default_font = load("res://assets/fonts/Knightwood.ttf")
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", UI_CREAM)
	theme.set_color("font_color", "Button", UI_CREAM)
	theme.set_color("font_color", "LineEdit", UI_CREAM)
	theme.set_color("font_hover_color", "Button", Color("#fff3a3"))
	theme.set_color("font_pressed_color", "Button", UI_LIME)
	theme.set_color("font_disabled_color", "Button", Color(UI_MUTED, 0.42))
	theme.set_stylebox("panel", "PanelContainer", _style(UI_CARD, UI_LINE, 0, 12))
	theme.set_stylebox("normal", "Button", _style(Color("#274432"), Color("#527044"), 0, 10))
	theme.set_stylebox("hover", "Button", _style(Color("#355a3a"), UI_LIME, 0, 10))
	theme.set_stylebox("pressed", "Button", _style(Color("#1c3428"), UI_ORANGE, 0, 10))
	theme.set_stylebox("disabled", "Button", _style(Color(0.09, 0.16, 0.12, 0.72), Color("#354d39"), 0, 10))
	theme.set_stylebox("normal", "LineEdit", _style(Color("#132a20"), UI_LINE, 0, 10))
	theme.set_stylebox("focus", "LineEdit", _style(Color("#183426"), UI_LIME, 0, 10))
	theme.set_stylebox("background", "ProgressBar", _style(Color("#172b24"), Color("#354d39"), 0, 1))
	theme.set_stylebox("fill", "ProgressBar", _style(UI_LIME, UI_LIME, 0, 1))
	return theme


func _style(fill: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2 if border.a > 0.0 else 0)
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	return box
