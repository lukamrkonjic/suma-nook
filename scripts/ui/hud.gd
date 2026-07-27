class_name Hud
extends CanvasLayer
## Persistent interface: skill chips, health, context prompt, toasts, build
## bar, tutorial hints. Modal panels live in GamePanels; the parcel reveal in
## ParcelReveal. World stays visible — no giant menus.

signal open_parcel_requested
signal build_piece_selected(kind: String, id: String)
signal pause_requested

var core: GameCore
var kit: UiKit
var placement: PlacementController

var _skill_chips: Dictionary = {}    # skill_id -> {level_label, bar_holder, chip}
var _toast_box: VBoxContainer
var _prompt_label: Label
var _hint_label: Label
var _health_box: HBoxContainer
var _build_bar: PanelContainer
var _build_category_scroll: ScrollContainer
var _build_category_strip: HBoxContainer
var _build_item_scroll: ScrollContainer
var _build_strip: HBoxContainer
var _build_previous_button: Button
var _build_next_button: Button
var _build_category_group: ButtonGroup
var _selected_build_category := ""
var _context_column: VBoxContainer
var _parcel_button: Button
var _bottom_buttons: HBoxContainer
var _hover_tooltip: PanelContainer
var _hover_name_label: Label
var _hover_collection_label: Label

const BUILD_CATEGORIES := [
	{"id": "ground", "label": "Ground"},
	{"id": "woodland", "label": "Woodland"},
	{"id": "stone", "label": "Stone"},
	{"id": "nature", "label": "Nature"},
	{"id": "furniture", "label": "Furniture"},
	{"id": "boundaries", "label": "Borders"},
	{"id": "utilities", "label": "Utilities"},
	{"id": "buildings", "label": "Buildings"},
	{"id": "storage", "label": "Storage"},
	{"id": "deeds", "label": "Deeds"},
]


func setup(game_core: GameCore, ui_kit: UiKit, placement_controller: PlacementController) -> void:
	core = game_core
	kit = ui_kit
	placement = placement_controller
	_build_layout()
	core.skills.xp_gained.connect(_on_xp_gained)
	core.skills.level_up.connect(_on_level_up)
	core.inventory.items_changed.connect(_refresh_parcel_button)
	core.stock.stock_changed.connect(_refresh_build_strip)
	if core.registries.feature("combat_enabled", false):
		core.combat.health_changed.connect(_on_health_changed)
	core.notified.connect(func(message, tone): toast(message, tone))
	placement.mode_changed.connect(_on_build_mode)
	placement.action_result.connect(_on_action_result)
	placement.hover_changed.connect(set_hover_tooltip)
	_refresh_all()


func _build_layout() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Skill chips — top left.
	var chips := VBoxContainer.new()
	chips.position = Vector2(14, 14)
	chips.add_theme_constant_override("separation", 6)
	root.add_child(chips)
	for skill_id: String in core.registries.skills:
		var def := core.registries.skill(skill_id)
		if def.future:
			continue
		var chip := kit.card()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		chip.add_child(row)
		row.add_child(kit.label(def.icon_glyph, 20))
		var col := VBoxContainer.new()
		row.add_child(col)
		var level_label := kit.label("%s  %d" % [def.display_name, 1], 15)
		col.add_child(level_label)
		var bar_holder := Control.new()
		bar_holder.custom_minimum_size = Vector2(120, 10)
		col.add_child(bar_holder)
		chips.add_child(chip)
		_skill_chips[skill_id] = {"level": level_label, "bar": bar_holder, "chip": chip}

	# Health hearts — top center, hidden while safe and full.
	_health_box = HBoxContainer.new()
	_health_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_health_box.position.y = 16
	_health_box.add_theme_constant_override("separation", 4)
	_health_box.visible = false
	root.add_child(_health_box)

	# Build hover identity — compact and centered, so the world remains the
	# dominant surface while every tile/object still has a clear name.
	_hover_tooltip = kit.card(Vector2(260, 0))
	_hover_tooltip.name = "PlaceableHoverTooltip"
	_hover_tooltip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hover_tooltip.position.y = 14
	_hover_tooltip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hover_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_tooltip.visible = false
	root.add_child(_hover_tooltip)
	var hover_col := VBoxContainer.new()
	hover_col.add_theme_constant_override("separation", 0)
	_hover_tooltip.add_child(hover_col)
	_hover_name_label = kit.label("", 18, false, true)
	_hover_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hover_col.add_child(_hover_name_label)
	_hover_collection_label = kit.label("", 13)
	_hover_collection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_collection_label.add_theme_color_override(
		"font_color",
		Color(0.42, 0.4, 0.34)
	)
	hover_col.add_child(_hover_collection_label)

	# Toasts — top right.
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toast_box.position += Vector2(-14, 14)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast_box.add_theme_constant_override("separation", 6)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_box)

	# Context prompt + tutorial hint — bottom center.
	_context_column = VBoxContainer.new()
	_context_column.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_context_column.position.y = -86
	_context_column.alignment = BoxContainer.ALIGNMENT_END
	_context_column.add_theme_constant_override("separation", 8)
	_context_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_context_column)
	_hint_label = kit.label("", 18)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", Color(0.35, 0.31, 0.24))
	_context_column.add_child(_hint_label)
	_prompt_label = kit.label("", 20)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context_column.add_child(_prompt_label)

	# Bottom-left action buttons.
	_bottom_buttons = HBoxContainer.new()
	_bottom_buttons.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_bottom_buttons.position += Vector2(14, -14)
	_bottom_buttons.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom_buttons.add_theme_constant_override("separation", 8)
	root.add_child(_bottom_buttons)
	var menu_button := kit.button("Menu  [Esc]")
	menu_button.pressed.connect(func(): pause_requested.emit())
	_bottom_buttons.add_child(menu_button)
	var build_button := kit.button("Shape Land  [B]", true)
	build_button.pressed.connect(func(): placement.toggle())
	_bottom_buttons.add_child(build_button)
	_parcel_button = kit.button("Open Land Parcel ✨", true)
	_parcel_button.visible = false
	_parcel_button.pressed.connect(func(): open_parcel_requested.emit())
	_bottom_buttons.add_child(_parcel_button)

	# Build library — a compact category shelf inspired by a physical tray.
	# Both rows use real scroll containers, so large collections remain usable
	# with a mouse wheel, trackpad, scrollbar, keyboard focus, or arrow paging.
	_build_bar = kit.card(Vector2(1060, 0))
	_build_bar.name = "BuildLibrary"
	_build_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build_bar.position.y = -14
	_build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_bar.visible = false
	root.add_child(_build_bar)
	var bar_col := VBoxContainer.new()
	bar_col.add_theme_constant_override("separation", 8)
	_build_bar.add_child(bar_col)

	var library_header := HBoxContainer.new()
	bar_col.add_child(library_header)
	_build_category_scroll = ScrollContainer.new()
	_build_category_scroll.name = "BuildCategories"
	_build_category_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_category_scroll.custom_minimum_size.y = 44
	_build_category_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_build_category_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_build_category_scroll.scroll_deadzone = 8
	_build_category_scroll.gui_input.connect(
		func(event): _on_library_scroll_input(event, _build_category_scroll)
	)
	kit.style_library_scrollbar(_build_category_scroll)
	library_header.add_child(_build_category_scroll)
	_build_category_strip = HBoxContainer.new()
	_build_category_strip.add_theme_constant_override("separation", 5)
	_build_category_scroll.add_child(_build_category_strip)

	var item_row := HBoxContainer.new()
	item_row.add_theme_constant_override("separation", 7)
	bar_col.add_child(item_row)
	_build_previous_button = kit.library_arrow_button("<")
	_build_previous_button.name = "BuildPreviousPage"
	_build_previous_button.tooltip_text = "Previous items"
	_build_previous_button.pressed.connect(func(): _page_build_items(-1))
	item_row.add_child(_build_previous_button)
	_build_item_scroll = ScrollContainer.new()
	_build_item_scroll.name = "BuildItems"
	_build_item_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_item_scroll.custom_minimum_size.y = 62
	_build_item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_build_item_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_build_item_scroll.scroll_deadzone = 8
	_build_item_scroll.follow_focus = true
	_build_item_scroll.gui_input.connect(
		func(event): _on_library_scroll_input(event, _build_item_scroll)
	)
	kit.style_library_scrollbar(_build_item_scroll)
	item_row.add_child(_build_item_scroll)
	_build_strip = HBoxContainer.new()
	_build_strip.name = "BuildItemStrip"
	_build_strip.add_theme_constant_override("separation", 6)
	_build_item_scroll.add_child(_build_strip)
	_build_next_button = kit.library_arrow_button(">")
	_build_next_button.name = "BuildNextPage"
	_build_next_button.tooltip_text = "More items"
	_build_next_button.pressed.connect(func(): _page_build_items(1))
	item_row.add_child(_build_next_button)
	var build_hint := kit.label(
		"Click to place  ·  wheel, scrollbar or arrows to browse  ·  R rotate  ·  X store  ·  Esc close",
		12
	)
	build_hint.add_theme_color_override("font_color", Color(0.45, 0.4, 0.33))
	bar_col.add_child(build_hint)
	_build_category_group = ButtonGroup.new()
	get_viewport().size_changed.connect(_resize_build_library)
	_resize_build_library()


# ------------------------------------------------------------------ refresh

func _refresh_all() -> void:
	for skill_id: String in _skill_chips:
		_refresh_skill(skill_id)
	_refresh_parcel_button()
	_refresh_build_strip()
	if core.registries.feature("combat_enabled", false):
		_on_health_changed(core.combat.health, core.combat.max_health)
	else:
		_health_box.visible = false


func _refresh_skill(skill_id: String) -> void:
	var chip: Dictionary = _skill_chips[skill_id]
	var def := core.registries.skill(skill_id)
	chip["level"].text = "%s  %d" % [def.display_name, core.skills.level(skill_id)]
	var holder: Control = chip["bar"]
	for child in holder.get_children():
		child.queue_free()
	var progress := core.skills.xp_progress(skill_id)
	holder.add_child(kit.progress_bar(progress["fraction"]))


func _refresh_parcel_button() -> void:
	_parcel_button.visible = core.parcels.has_pending()
	if _parcel_button.visible:
		_parcel_button.text = "Resume Land Parcel reveal ✨"


func _refresh_build_strip() -> void:
	var entries_by_category := _collect_build_entries()
	var available_categories: Array[String] = []
	for category: Dictionary in BUILD_CATEGORIES:
		var category_id := String(category["id"])
		if not (entries_by_category[category_id] as Array).is_empty():
			available_categories.append(category_id)

	if not available_categories.has(_selected_build_category):
		_selected_build_category = available_categories[0] if not available_categories.is_empty() else ""

	_clear_container(_build_category_strip)
	for category: Dictionary in BUILD_CATEGORIES:
		var category_id := String(category["id"])
		var entries: Array = entries_by_category[category_id]
		if entries.is_empty():
			continue
		var category_button := kit.library_category_button(
			"%s  %d" % [category["label"], entries.size()],
			category_id == _selected_build_category
		)
		category_button.name = "BuildCategory_%s" % category_id
		category_button.button_group = _build_category_group
		category_button.pressed.connect(func(): _select_build_category(category_id))
		_build_category_strip.add_child(category_button)

	_refresh_build_items(entries_by_category)
	call_deferred("_update_build_scroll_buttons")


func _collect_build_entries() -> Dictionary:
	var result := {}
	for category: Dictionary in BUILD_CATEGORIES:
		result[String(category["id"])] = []

	for tile_id: String in core.stock.tiles:
		var definition := core.registries.tile(tile_id)
		var count := core.stock.tile_count(tile_id)
		if definition == null or count <= 0:
			continue
		var category_id := category_for_tile(definition)
		result[category_id].append({
			"kind": "tile",
			"id": tile_id,
			"name": definition.display_name,
			"count": count,
			"tooltip": definition.special_trait,
		})

	for structure_id: String in core.stock.structures:
		var definition := core.registries.structure(structure_id)
		var count := core.stock.structure_count(structure_id)
		if definition == null or count <= 0:
			continue
		var category_id := category_for_structure(definition)
		result[category_id].append({
			"kind": "structure",
			"id": structure_id,
			"name": definition.display_name,
			"count": count,
			"tooltip": "%s · click to place" % _build_category_label(category_id),
		})

	var deed_counts := {}
	for landmark_id: String in core.stock.landmark_deeds:
		deed_counts[landmark_id] = int(deed_counts.get(landmark_id, 0)) + 1
	for landmark_id: String in deed_counts:
		var definition := core.registries.landmark(landmark_id)
		if definition == null:
			continue
		result["deeds"].append({
			"kind": "deed",
			"id": landmark_id,
			"name": definition.display_name,
			"count": int(deed_counts[landmark_id]),
			"tooltip": "Packed landmark · click to place",
		})

	for category_id: String in result:
		(result[category_id] as Array).sort_custom(
			func(a: Dictionary, b: Dictionary): return String(a["name"]) < String(b["name"])
		)
	return result


func _refresh_build_items(entries_by_category: Dictionary) -> void:
	for child in _build_strip.get_children():
		_build_strip.remove_child(child)
		child.queue_free()
	_build_item_scroll.scroll_horizontal = 0

	if _selected_build_category == "":
		var empty_label := kit.label(
			"Your library is empty — the next ferry will bring a Land Parcel.",
			15
		)
		empty_label.add_theme_color_override("font_color", Color(0.45, 0.42, 0.36))
		_build_strip.add_child(empty_label)
		return

	var entries: Array = entries_by_category[_selected_build_category]
	for entry: Dictionary in entries:
		var item_button := kit.library_item_button(
			String(entry["name"]),
			int(entry["count"])
		)
		item_button.name = "BuildItem_%s" % entry["id"]
		item_button.tooltip_text = String(entry["tooltip"])
		var kind := String(entry["kind"])
		var content_id := String(entry["id"])
		item_button.pressed.connect(
			func(): build_piece_selected.emit(kind, content_id)
		)
		_build_strip.add_child(item_button)


func _select_build_category(category_id: String) -> void:
	if category_id == _selected_build_category:
		return
	_selected_build_category = category_id
	var entries_by_category := _collect_build_entries()
	for button in _build_category_strip.get_children():
		if button is Button:
			(button as Button).set_pressed_no_signal(
				button.name == "BuildCategory_%s" % category_id
			)
	_refresh_build_items(entries_by_category)
	call_deferred("_update_build_scroll_buttons")


static func category_for_tile(definition: Defs.TileDefinition) -> String:
	match definition.family:
		"living_grove":
			return "woodland"
		"stonebound":
			return "stone"
		_:
			return "ground"


static func category_for_structure(definition: Defs.StructureDefinition) -> String:
	var tags := definition.placement_tags
	if tags.has("tree") or tags.has("plant"):
		return "nature"
	if tags.has("furniture"):
		return "furniture"
	if tags.has("barrier") or tags.has("sign"):
		return "boundaries"
	if tags.has("storage") or tags.has("container"):
		return "storage"
	if definition.kind == "building" or tags.has("building"):
		return "buildings"
	return "utilities"


func _build_category_label(category_id: String) -> String:
	for category: Dictionary in BUILD_CATEGORIES:
		if category["id"] == category_id:
			return String(category["label"])
	return category_id.capitalize()


func _clear_container(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _on_library_scroll_input(event: InputEvent, scroll: ScrollContainer) -> void:
	var delta := 0.0
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
				delta = -86.0 * event.factor
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
				delta = 86.0 * event.factor
	elif event is InputEventPanGesture:
		delta = (event.delta.x + event.delta.y) * 72.0
	if is_zero_approx(delta):
		return
	var bar := scroll.get_h_scroll_bar()
	scroll.scroll_horizontal = clampi(
		scroll.scroll_horizontal + int(round(delta)),
		0,
		maxi(0, int(ceil(bar.max_value - bar.page)))
	)
	scroll.accept_event()
	if scroll == _build_item_scroll:
		_update_build_scroll_buttons()


func _page_build_items(direction: int) -> void:
	var amount := maxi(180, int(_build_item_scroll.size.x * 0.72))
	var bar := _build_item_scroll.get_h_scroll_bar()
	_build_item_scroll.scroll_horizontal = clampi(
		_build_item_scroll.scroll_horizontal + amount * direction,
		0,
		maxi(0, int(ceil(bar.max_value - bar.page)))
	)
	_update_build_scroll_buttons()


func _update_build_scroll_buttons() -> void:
	if _build_item_scroll == null or _build_previous_button == null:
		return
	var bar := _build_item_scroll.get_h_scroll_bar()
	var maximum := maxi(0, int(ceil(bar.max_value - bar.page)))
	_build_previous_button.disabled = _build_item_scroll.scroll_horizontal <= 0
	_build_next_button.disabled = _build_item_scroll.scroll_horizontal >= maximum
	_build_previous_button.visible = maximum > 0
	_build_next_button.visible = maximum > 0


func _resize_build_library() -> void:
	if _build_bar == null:
		return
	var viewport_width := get_viewport().get_visible_rect().size.x
	_build_bar.custom_minimum_size.x = clampf(viewport_width - 40.0, 620.0, 1060.0)
	if _build_bar.visible:
		call_deferred("_position_context_above_build_library")


func _position_context_above_build_library() -> void:
	if _context_column == null:
		return
	_context_column.position.y = (
		-_build_bar.size.y - 28.0
		if _build_bar.visible
		else -86.0
	)


# ------------------------------------------------------------------ events

func _on_xp_gained(skill_id: String, _amount: int, _total: int) -> void:
	if _skill_chips.has(skill_id):
		_refresh_skill(skill_id)


func _on_level_up(skill_id: String, new_level: int, _unlocks: Array) -> void:
	if not _skill_chips.has(skill_id):
		return
	_refresh_skill(skill_id)
	var chip: PanelContainer = _skill_chips[skill_id]["chip"]
	var tween := chip.create_tween()
	tween.tween_property(chip, "scale", Vector2(1.12, 1.12), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(chip, "scale", Vector2.ONE, 0.2)
	var def := core.registries.skill(skill_id)
	toast("✨ %s level %d!" % [def.display_name if def != null else skill_id, new_level], "levelup")


func _on_health_changed(current: int, maximum: int) -> void:
	for child in _health_box.get_children():
		child.queue_free()
	_health_box.visible = current < maximum or _enemies_near()
	for i in maximum:
		var heart := kit.label("♥", 22)
		heart.add_theme_color_override("font_color", Color(0.78, 0.32, 0.28) if i < current else Color(0.4, 0.37, 0.33, 0.5))
		_health_box.add_child(heart)


func _enemies_near() -> bool:
	return get_tree().get_node_count_in_group("enemies") > 0


func _on_build_mode(active: bool) -> void:
	_build_bar.visible = active
	_bottom_buttons.visible = not active
	if active:
		_refresh_build_strip()
		call_deferred("_position_context_above_build_library")
	else:
		_position_context_above_build_library()


func _on_action_result(ok: bool, message: String, _kind: String) -> void:
	if message != "":
		toast(message, "good" if ok else "warn")


# ------------------------------------------------------------------ prompt / hints / toasts

func set_prompt(text: String) -> void:
	_prompt_label.text = text


func set_hint(text: String) -> void:
	_hint_label.text = text


func set_tutorial_enabled(enabled: bool) -> void:
	_hint_label.visible = enabled


func set_hover_tooltip(display_name: String, collection_name: String) -> void:
	if _hover_tooltip == null:
		return
	_hover_name_label.text = display_name
	_hover_collection_label.text = collection_name
	_hover_tooltip.visible = display_name != ""


## Keeps unboxed world-space guidance legible across the pale day and dark
## rain backdrops without adding a large UI panel over the diorama.
func apply_weather_contrast(rain_enabled: bool) -> void:
	var hint_color := Color(0.92, 0.89, 0.8) if rain_enabled else Color(0.35, 0.31, 0.24)
	var prompt_color := Color(0.97, 0.94, 0.86) if rain_enabled else kit.text_color()
	for entry in [[_hint_label, hint_color], [_prompt_label, prompt_color]]:
		var label := entry[0] as Label
		label.add_theme_color_override("font_color", entry[1])
		label.add_theme_color_override("font_outline_color", Color(0.12, 0.15, 0.12, 0.8))
		label.add_theme_constant_override("outline_size", 3 if rain_enabled else 0)


func toast(message: String, tone := "common") -> void:
	var card := kit.card()
	var l := kit.label(message, 15)
	match tone:
		"rare", "levelup":
			l.add_theme_color_override("font_color", Color(0.62, 0.45, 0.1))
		"warn":
			l.add_theme_color_override("font_color", Color(0.62, 0.28, 0.22))
		"good":
			l.add_theme_color_override("font_color", Color(0.35, 0.42, 0.16))
	card.add_child(l)
	card.modulate.a = 0.0
	_toast_box.add_child(card)
	_toast_box.move_child(card, 0)
	while _toast_box.get_child_count() > 6:
		_toast_box.get_child(_toast_box.get_child_count() - 1).free()
	var tween := card.create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.15)
	tween.tween_interval(2.6 if tone == "common" else 3.6)
	tween.tween_property(card, "modulate:a", 0.0, 0.5)
	tween.tween_callback(card.queue_free)


## Derives the current opening hint straight from progression state.
func update_tutorial() -> void:
	if core.arrivals.has_waiting_package():
		set_hint("A Land Parcel is waiting at the northern dock.")
	elif core.skills.lifetime_actions.get("fishing", 0) == 0:
		set_hint("Try catch-and-release fishing along the northern water. (walk close, then E)")
	elif core.parcels.has_pending():
		set_hint("Choose one finished tile from the Land Parcel.")
	elif core.grid.placed_tile_count() == 0 and core.stock.total_tiles() > 0:
		set_hint("Place your new land beside the world you have. (B for build mode)")
	elif core.grid.placed_tile_count() > 0 and core.skills.lifetime_actions.get("woodcutting", 0) == 0:
		if _has_placed_tree():
			set_hint("Tend your placed tree — it will rest, then regrow.")
		elif _stored_tree_count() > 0:
			set_hint("Place your tree from the Build Library, then tend it.")
		else:
			set_hint("")
	else:
		set_hint("")


func _has_placed_tree() -> bool:
	for slot: Dictionary in core.grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			var definition := core.registries.structure(structure.structure_id)
			if definition != null and definition.anchor_id == "grove_anchor":
				return true
	return false


func _stored_tree_count() -> int:
	var count := 0
	for structure_id: String in core.stock.structures:
		var definition := core.registries.structure(structure_id)
		if definition != null and definition.anchor_id == "grove_anchor":
			count += core.stock.structure_count(structure_id)
	return count
