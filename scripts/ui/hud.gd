class_name Hud
extends CanvasLayer
## Persistent interface: skill chips, health, context prompt, toasts, build
## bar, tutorial hints. Modal panels live in GamePanels; the parcel reveal in
## ParcelReveal. World stays visible — no giant menus.

signal open_parcel_requested
signal build_piece_selected(kind: String, id: String)
signal build_world_browse_requested
signal build_store_requested
signal pause_requested

const BuildThumbnailRendererScript := preload(
	"res://scripts/ui/build_thumbnail_renderer.gd"
)

var core: GameCore
var kit: UiKit
var placement: PlacementController

var _skill_chips: Dictionary = {}    # skill_id -> {level_label, bar_holder, chip}
var _toast_box: VBoxContainer
var _prompt_label: Label
var _hint_label: Label
var _health_box: HBoxContainer
var _build_bar: PanelContainer
var _build_bar_column: VBoxContainer
var _build_compact_row: HBoxContainer
var _build_expand_button: Button
var _build_expanded_clip: Control
var _build_expanded_content: VBoxContainer
var _build_category_scroll: ScrollContainer
var _build_category_strip: HBoxContainer
var _build_item_scroll: ScrollContainer
var _build_strip: GridContainer
var _build_previous_button: Button
var _build_next_button: Button
var _build_category_group: ButtonGroup
var _selected_build_category := ""
var _selected_build_entry: Dictionary = {}
var _build_library_expanded := false
var _build_hover_expand_armed := true
var _build_mouse_exit_pending := false
var _build_library_tween: Tween
var _build_bag_button_tween: Tween
var _build_bag_idle_tween: Tween
var _build_bag_open_pending := false
var _build_panel_expanded_style: StyleBoxFlat
var _build_panel_collapsed_style: StyleBoxEmpty
var _build_drop_overlay: PanelContainer
var _build_drop_label: Label
var _build_drop_active := false
var _store_bubble: Button
var _store_bubble_tween: Tween
var _store_bubble_idle_tween: Tween
var _catalogue_pointer_active := false
var _thumbnail_renderer: BuildThumbnailRenderer
var _build_preview_targets: Dictionary = {}
var _context_column: VBoxContainer
var _parcel_button: Button
var _bottom_buttons: HBoxContainer
var _menu_button: Button
var _build_button: Button
var _build_hint_label: Label
var _hover_tooltip: PanelContainer
var _hover_name_label: Label
var _hover_collection_label: Label
var _prompt_action := &""
var _prompt_description := ""
var _prompt_secondary: Array[Dictionary] = []

const BUILD_CATEGORIES := [
	{"id": "ground", "label": "Ground", "icon": "category_ground.svg"},
	{"id": "woodland", "label": "Woodland", "icon": "category_woodland.svg"},
	{"id": "stone", "label": "Stone", "icon": "category_stone.svg"},
	{"id": "winter", "label": "Snow", "icon": "category_winter.svg"},
	{"id": "nature", "label": "Nature", "icon": "category_nature.svg"},
	{"id": "furniture", "label": "Furniture", "icon": "category_furniture.svg"},
	{"id": "boundaries", "label": "Borders", "icon": "category_boundaries.svg"},
	{"id": "utilities", "label": "Utilities", "icon": "category_utilities.svg"},
	{"id": "buildings", "label": "Buildings", "icon": "category_buildings.svg"},
	{"id": "storage", "label": "Storage", "icon": "category_storage.svg"},
	{"id": "deeds", "label": "Deeds", "icon": "category_deeds.svg"},
]

const BUILD_ICON_DIRECTORY := "res://assets/ui/icons/"


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
	placement.held_changed.connect(_on_held_changed)
	placement.action_result.connect(_on_action_result)
	placement.hover_changed.connect(set_hover_tooltip)
	InputDeviceService.shared().input_method_changed.connect(_on_input_method_changed)
	InputDeviceService.shared().active_controller_changed.connect(
		func(_device): _on_input_method_changed(
			InputDeviceService.shared().input_method
		)
	)
	_refresh_all()
	_on_input_method_changed(InputDeviceService.shared().input_method)


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
	_menu_button = kit.button("Menu")
	_menu_button.pressed.connect(func(): pause_requested.emit())
	_bottom_buttons.add_child(_menu_button)
	_build_button = kit.button("Shape Land", true)
	_build_button.pressed.connect(func(): placement.toggle())
	_bottom_buttons.add_child(_build_button)
	_parcel_button = kit.button("Open Land Parcel ✨", true)
	_parcel_button.visible = false
	_parcel_button.pressed.connect(func(): open_parcel_requested.emit())
	_bottom_buttons.add_child(_parcel_button)

	# Build Bag — a single floating icon at rest, expanding upward into the
	# owned-piece browser only while the player is using it.
	_build_bar = PanelContainer.new()
	_build_bar.name = "BuildLibrary"
	_build_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build_bar.position.y = -18
	_build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_bar.custom_minimum_size = Vector2(70, 0)
	_build_panel_collapsed_style = StyleBoxEmpty.new()
	_build_panel_collapsed_style.set_content_margin_all(0)
	_build_panel_expanded_style = kit.cloud_panel_style(28)
	_build_panel_expanded_style.content_margin_left = 24
	_build_panel_expanded_style.content_margin_right = 24
	_build_panel_expanded_style.content_margin_top = 22
	_build_panel_expanded_style.content_margin_bottom = 20
	_build_bar.add_theme_stylebox_override("panel", _build_panel_collapsed_style)
	_build_bar.visible = false
	_build_bar.mouse_entered.connect(_on_build_library_mouse_entered)
	_build_bar.mouse_exited.connect(_on_build_library_mouse_exited)
	_build_bar.gui_input.connect(_on_build_library_input)
	root.add_child(_build_bar)
	_build_bar_column = VBoxContainer.new()
	_build_bar_column.add_theme_constant_override("separation", 7)
	_build_bar.add_child(_build_bar_column)

	_build_compact_row = HBoxContainer.new()
	_build_compact_row.name = "CompactBuildDock"
	_build_compact_row.custom_minimum_size = Vector2(70, 70)
	_build_compact_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_build_bar_column.add_child(_build_compact_row)
	_build_expand_button = Button.new()
	_build_expand_button.name = "BuildExpandLibrary"
	_build_expand_button.custom_minimum_size = Vector2(66, 66)
	_build_expand_button.icon = load(BUILD_ICON_DIRECTORY + "build_bag.svg")
	_build_expand_button.expand_icon = false
	_build_expand_button.tooltip_text = "Build Bag"
	_build_expand_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_build_expand_button.focus_mode = Control.FOCUS_ALL
	var bag_normal := StyleBoxFlat.new()
	bag_normal.bg_color = Color(1.0, 0.995, 0.965, 0.98)
	bag_normal.border_color = Color(0.78, 0.8, 0.7, 0.82)
	bag_normal.set_border_width_all(2)
	bag_normal.set_corner_radius_all(33)
	bag_normal.shadow_color = Color(0.12, 0.15, 0.09, 0.22)
	bag_normal.shadow_size = 10
	bag_normal.shadow_offset = Vector2(0, 5)
	var bag_hover := bag_normal.duplicate()
	bag_hover.bg_color = Color.WHITE
	bag_hover.border_color = Color(0.56, 0.68, 0.38)
	bag_hover.shadow_size = 14
	bag_hover.shadow_offset = Vector2(0, 7)
	var bag_pressed := bag_hover.duplicate()
	bag_pressed.bg_color = Color(0.94, 0.96, 0.88)
	bag_pressed.shadow_size = 5
	bag_pressed.shadow_offset = Vector2(0, 2)
	_build_expand_button.add_theme_stylebox_override("normal", bag_normal)
	_build_expand_button.add_theme_stylebox_override("hover", bag_hover)
	_build_expand_button.add_theme_stylebox_override("pressed", bag_pressed)
	_build_expand_button.add_theme_stylebox_override("focus", bag_hover)
	_build_expand_button.pressed.connect(
		func(): set_build_library_expanded(true)
	)
	_build_compact_row.add_child(_build_expand_button)
	call_deferred("_start_build_bag_idle")

	# A clipped plain Control does not inherit its children's minimum height,
	# allowing the shelf to animate rather than pop between layouts.
	_build_expanded_clip = Control.new()
	_build_expanded_clip.name = "BuildLibraryExpansion"
	_build_expanded_clip.clip_contents = true
	_build_expanded_clip.custom_minimum_size.y = 356
	_build_bar_column.add_child(_build_expanded_clip)
	_build_expanded_content = VBoxContainer.new()
	_build_expanded_content.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_build_expanded_content.offset_bottom = 350
	_build_expanded_content.add_theme_constant_override("separation", 8)
	_build_expanded_clip.add_child(_build_expanded_content)

	_build_category_scroll = ScrollContainer.new()
	_build_category_scroll.name = "BuildCategories"
	_build_category_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_category_scroll.custom_minimum_size.y = 58
	_build_category_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_build_category_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_build_category_scroll.scroll_deadzone = 8
	_build_category_scroll.follow_focus = true
	_build_category_scroll.gui_input.connect(
		func(event): _on_library_scroll_input(event, _build_category_scroll)
	)
	kit.style_library_scrollbar(_build_category_scroll)
	_build_expanded_content.add_child(_build_category_scroll)
	_build_category_strip = HBoxContainer.new()
	_build_category_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_category_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_build_category_strip.add_theme_constant_override("separation", 8)
	_build_category_scroll.add_child(_build_category_strip)

	var item_row := HBoxContainer.new()
	item_row.add_theme_constant_override("separation", 7)
	item_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_expanded_content.add_child(item_row)
	_build_previous_button = kit.library_arrow_button("<")
	_build_previous_button.name = "BuildPreviousPage"
	_build_previous_button.tooltip_text = "Previous row"
	_build_previous_button.pressed.connect(func(): _page_build_items(-1))
	item_row.add_child(_build_previous_button)
	_build_item_scroll = ScrollContainer.new()
	_build_item_scroll.name = "BuildItems"
	_build_item_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_item_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_item_scroll.custom_minimum_size.y = 232
	_build_item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_build_item_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_build_item_scroll.scroll_deadzone = 8
	_build_item_scroll.follow_focus = true
	_build_item_scroll.gui_input.connect(
		func(event): _on_library_scroll_input(event, _build_item_scroll)
	)
	kit.style_library_scrollbar(_build_item_scroll)
	item_row.add_child(_build_item_scroll)
	_build_strip = GridContainer.new()
	_build_strip.name = "BuildItemGrid"
	_build_strip.columns = 7
	_build_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_strip.add_theme_constant_override("h_separation", 9)
	_build_strip.add_theme_constant_override("v_separation", 9)
	_build_item_scroll.add_child(_build_strip)
	_build_next_button = kit.library_arrow_button(">")
	_build_next_button.name = "BuildNextPage"
	_build_next_button.tooltip_text = "Next row"
	_build_next_button.pressed.connect(func(): _page_build_items(1))
	item_row.add_child(_build_next_button)
	_build_hint_label = kit.label("", 12)
	_build_hint_label.add_theme_color_override("font_color", Color(0.45, 0.4, 0.33))
	_build_expanded_content.add_child(_build_hint_label)

	_build_drop_overlay = PanelContainer.new()
	_build_drop_overlay.name = "BuildLibraryStoreDrop"
	_build_drop_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_drop_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_build_drop_overlay.visible = false
	_build_drop_overlay.gui_input.connect(_on_build_drop_overlay_input)
	var drop_style := StyleBoxFlat.new()
	drop_style.bg_color = Color(0.31, 0.43, 0.24, 0.94)
	drop_style.border_color = Color(0.82, 0.91, 0.56)
	drop_style.set_border_width_all(4)
	drop_style.set_corner_radius_all(16)
	drop_style.shadow_color = Color(0.08, 0.12, 0.06, 0.24)
	drop_style.shadow_size = 10
	_build_drop_overlay.add_theme_stylebox_override("panel", drop_style)
	_build_drop_label = kit.label(
		"Release to return this piece to your Build Bag",
		20,
		true,
		true
	)
	_build_drop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_drop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_build_drop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_drop_overlay.add_child(_build_drop_label)
	_build_bar.add_child(_build_drop_overlay)

	# Picking up an existing world piece exposes one small, local action
	# instead of requiring a long drag into the full-width library.
	_store_bubble = kit.button("↓  Store in Bag")
	_store_bubble.name = "StoreHeldWorldPiece"
	_store_bubble.custom_minimum_size = Vector2(190, 52)
	_store_bubble.tooltip_text = "Return this placed piece to storage"
	var store_normal := StyleBoxFlat.new()
	store_normal.bg_color = Color(1.0, 0.995, 0.965, 0.98)
	store_normal.border_color = Color(0.76, 0.79, 0.68, 0.9)
	store_normal.set_border_width_all(2)
	store_normal.set_corner_radius_all(24)
	store_normal.content_margin_left = 22
	store_normal.content_margin_right = 22
	store_normal.content_margin_top = 13
	store_normal.content_margin_bottom = 13
	store_normal.shadow_color = Color(0.13, 0.16, 0.1, 0.2)
	store_normal.shadow_size = 10
	store_normal.shadow_offset = Vector2(0, 5)
	var store_hover := store_normal.duplicate()
	store_hover.bg_color = Color.WHITE
	store_hover.border_color = Color(0.56, 0.67, 0.38)
	store_hover.shadow_size = 13
	var store_pressed := store_hover.duplicate()
	store_pressed.bg_color = Color(0.94, 0.96, 0.88)
	store_pressed.shadow_size = 5
	store_pressed.shadow_offset = Vector2(0, 2)
	_store_bubble.add_theme_stylebox_override("normal", store_normal)
	_store_bubble.add_theme_stylebox_override("hover", store_hover)
	_store_bubble.add_theme_stylebox_override("pressed", store_pressed)
	_store_bubble.add_theme_stylebox_override("focus", store_hover)
	_store_bubble.add_theme_color_override("font_color", Color(0.24, 0.27, 0.19))
	_store_bubble.add_theme_color_override(
		"font_hover_color", Color(0.18, 0.25, 0.12)
	)
	_store_bubble.add_theme_color_override(
		"font_pressed_color", Color(0.18, 0.25, 0.12)
	)
	_store_bubble.add_theme_color_override(
		"font_focus_color", Color(0.18, 0.25, 0.12)
	)
	_store_bubble.visible = false
	_store_bubble.pressed.connect(_store_held_from_bubble)
	_store_bubble.gui_input.connect(_on_store_bubble_input)
	root.add_child(_store_bubble)

	_build_category_group = ButtonGroup.new()
	_thumbnail_renderer = BuildThumbnailRendererScript.new()
	_thumbnail_renderer.name = "BuildThumbnailRenderer"
	add_child(_thumbnail_renderer)
	_thumbnail_renderer.setup(core, placement.assets)
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
		var entries: Array = entries_by_category[category_id]
		if not entries.is_empty():
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
			"",
			category_id == _selected_build_category
		)
		category_button.name = "BuildCategory_%s" % category_id
		category_button.custom_minimum_size = Vector2(54, 50)
		category_button.icon = load(
			BUILD_ICON_DIRECTORY + String(category["icon"])
		)
		category_button.expand_icon = false
		category_button.tooltip_text = "%s · %d owned kinds" % [
			category["label"],
			entries.size(),
		]
		category_button.button_group = _build_category_group
		category_button.pressed.connect(func(): _select_build_category(category_id))
		_build_category_strip.add_child(category_button)

	_refresh_build_items(entries_by_category)
	_refresh_compact_build_dock()
	call_deferred("_update_build_scroll_buttons")


func _collect_build_entries() -> Dictionary:
	var result := {}
	for category: Dictionary in BUILD_CATEGORIES:
		result[String(category["id"])] = []

	for tile_id: String in core.stock.tiles:
		var definition := core.registries.tile(tile_id)
		var count := core.stock.tile_count(tile_id)
		if (
			definition == null
			or count <= 0
			or not core.registries.is_tile_active(tile_id)
		):
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
			"tooltip": "%s · %s" % [
				_build_category_label(category_id),
				InputDeviceService.shared().format_action(&"build_confirm", "place"),
			],
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
			"tooltip": "Packed landmark · %s" % (
				InputDeviceService.shared().format_action(&"build_confirm", "place")
			),
		})

	for category_id: String in result:
		(result[category_id] as Array).sort_custom(
			func(a: Dictionary, b: Dictionary): return String(a["name"]) < String(b["name"])
		)
	return result


func _refresh_build_items(entries_by_category: Dictionary) -> void:
	_thumbnail_renderer.discard_pending()
	for child in _build_strip.get_children():
		_build_strip.remove_child(child)
		child.queue_free()
	_build_item_scroll.scroll_vertical = 0

	if _selected_build_category == "":
		var empty_label := kit.label(
			"Your Build Bag is empty — the next ferry will bring a Land Parcel.",
			15
		)
		empty_label.add_theme_color_override("font_color", Color(0.45, 0.42, 0.36))
		_build_strip.add_child(empty_label)
		return

	var entries: Array = entries_by_category[_selected_build_category]
	for entry: Dictionary in entries:
		var card := kit.library_visual_item_button(
			String(entry["name"]),
			int(entry["count"])
		)
		var item_button: Button = card["button"]
		var preview: TextureRect = card["preview"]
		item_button.name = "BuildItem_%s" % entry["id"]
		var tooltip := String(entry["tooltip"])
		var place_prompt := InputDeviceService.shared().format_action(
			&"ui_accept" if InputDeviceService.shared().is_controller() else &"interact",
			"place"
		)
		item_button.tooltip_text = (
			"%s\n%s" % [tooltip, place_prompt]
			if tooltip != ""
			else place_prompt
		)
		var kind := String(entry["kind"])
		var content_id := String(entry["id"])
		# Activate on press so the same gesture can continue out of the card,
		# across the world, and finish by releasing at the desired tile.
		item_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		item_button.pressed.connect(
			func(): _on_build_piece_pressed(entry)
		)
		_build_strip.add_child(item_button)
		_thumbnail_renderer.request(
			kind,
			content_id,
			Callable(self, "_apply_build_thumbnail").bind(
				kind,
				content_id,
				preview.get_instance_id()
			)
		)


func _on_build_piece_pressed(entry: Dictionary) -> void:
	var starts_pointer_drag := (
		not InputDeviceService.shared().is_controller()
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	)
	_selected_build_entry = entry.duplicate(true)
	set_build_library_expanded(false)
	_refresh_compact_build_dock()
	build_piece_selected.emit(
		String(entry["kind"]),
		String(entry["id"])
	)
	if starts_pointer_drag and placement != null and not placement.held.is_empty():
		_catalogue_pointer_active = true
		placement.begin_pointer_drag_for_held(
			get_viewport().get_mouse_position()
		)


func _apply_build_thumbnail(
	texture: Texture2D,
	kind: String,
	content_id: String,
	target_id: int
) -> void:
	var target := instance_from_id(target_id) as TextureRect
	if target != null:
		target.texture = texture


func _refresh_compact_build_dock() -> void:
	if _build_expand_button == null:
		return
	if _selected_build_entry.is_empty():
		_build_expand_button.tooltip_text = "Build Bag"
		return
	var kind := String(_selected_build_entry.get("kind", ""))
	var content_id := String(_selected_build_entry.get("id", ""))
	var live_count := _owned_build_count(kind, content_id)
	if live_count <= 0 and placement.held.is_empty():
		_selected_build_entry = {}
		_refresh_compact_build_dock()
		return
	_selected_build_entry["count"] = live_count
	_build_expand_button.tooltip_text = (
		"Store %s in Bag"
		if not placement.held.is_empty()
			and placement.held.get("moving") != null
		else "Build Bag · %s ×%d"
	) % (
		[String(_selected_build_entry.get("name", content_id))]
		if not placement.held.is_empty()
			and placement.held.get("moving") != null
		else [String(_selected_build_entry.get("name", content_id)), live_count]
	)


func _owned_build_count(kind: String, content_id: String) -> int:
	match kind:
		"tile":
			return core.stock.tile_count(content_id)
		"structure":
			return core.stock.structure_count(content_id)
		"deed":
			return core.stock.landmark_deeds.count(content_id)
	return 0


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
		"winter":
			return "winter"
		_:
			return "ground"


static func category_for_structure(definition: Defs.StructureDefinition) -> String:
	var tags := definition.placement_tags
	if tags.has("tree") or tags.has("plant") or tags.has("nature"):
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
	if not _build_library_expanded:
		set_build_library_expanded(true)
	if scroll == _build_item_scroll:
		var vertical_bar := scroll.get_v_scroll_bar()
		scroll.scroll_vertical = clampi(
			scroll.scroll_vertical + int(round(delta)),
			0,
			maxi(0, int(ceil(vertical_bar.max_value - vertical_bar.page)))
		)
	else:
		var horizontal_bar := scroll.get_h_scroll_bar()
		scroll.scroll_horizontal = clampi(
			scroll.scroll_horizontal + int(round(delta)),
			0,
			maxi(0, int(ceil(horizontal_bar.max_value - horizontal_bar.page)))
		)
	scroll.accept_event()
	if scroll == _build_item_scroll:
		_update_build_scroll_buttons()


func _page_build_items(direction: int) -> void:
	var amount := maxi(150, int(_build_item_scroll.size.y * 0.78))
	var bar := _build_item_scroll.get_v_scroll_bar()
	_build_item_scroll.scroll_vertical = clampi(
		_build_item_scroll.scroll_vertical + amount * direction,
		0,
		maxi(0, int(ceil(bar.max_value - bar.page)))
	)
	_update_build_scroll_buttons()


func _update_build_scroll_buttons() -> void:
	if _build_item_scroll == null or _build_previous_button == null:
		return
	var bar := _build_item_scroll.get_v_scroll_bar()
	var maximum := maxi(0, int(ceil(bar.max_value - bar.page)))
	_build_previous_button.disabled = _build_item_scroll.scroll_vertical <= 0
	_build_next_button.disabled = _build_item_scroll.scroll_vertical >= maximum
	_build_previous_button.visible = maximum > 0
	_build_next_button.visible = maximum > 0


func _resize_build_library() -> void:
	if _build_bar == null:
		return
	_build_bar.custom_minimum_size.x = (
		_build_library_expanded_width()
		if _build_library_expanded
		else 70.0
	)
	if _build_strip != null:
		_build_strip.columns = clampi(
			int(floor((_build_library_expanded_width() - 128.0) / 141.0)),
			3,
			8
		)
	if _build_bar.visible:
		call_deferred("_position_context_above_build_library")


func _build_library_expanded_width() -> float:
	var viewport_width := get_viewport().get_visible_rect().size.x
	return clampf(viewport_width - 64.0, 560.0, 1180.0)


func _position_context_above_build_library() -> void:
	if _context_column == null:
		return
	_context_column.position.y = (
		-_build_bar.size.y - 28.0
		if _build_bar.visible
		else -86.0
	)


func set_build_library_expanded(expanded: bool, animate := true) -> void:
	if _build_expanded_clip == null:
		return
	var target_height := 356.0 if expanded else 0.0
	var target_width := _build_library_expanded_width() if expanded else 70.0
	var already_settled := (
		_build_library_expanded == expanded
		and is_equal_approx(
			_build_expanded_clip.custom_minimum_size.y,
			target_height
		)
		and _build_expanded_content.visible == expanded
	)
	if already_settled:
		if expanded and InputDeviceService.shared().is_controller():
			call_deferred("focus_build_library")
		return
	_build_library_expanded = expanded
	_build_bag_open_pending = false
	if _build_bag_button_tween != null and _build_bag_button_tween.is_valid():
		_build_bag_button_tween.kill()
	if not expanded:
		_build_hover_expand_armed = false
		release_build_focus()
	else:
		if _build_bag_idle_tween != null and _build_bag_idle_tween.is_valid():
			_build_bag_idle_tween.kill()
		_build_expand_button.scale = Vector2.ONE
		_build_compact_row.visible = false
		_build_bar.add_theme_stylebox_override(
			"panel",
			_build_panel_expanded_style
		)
		# Mouse users open the Bag by hovering the icon. Controller users keep
		# that same icon as a deterministic focus anchor when storage is empty.
		_build_compact_row.visible = InputDeviceService.shared().is_controller()
		_build_expanded_content.visible = true
	_refresh_compact_build_dock()
	if _build_library_tween != null and _build_library_tween.is_valid():
		_build_library_tween.kill()
	if not animate:
		_build_expanded_clip.custom_minimum_size.y = target_height
		_build_bar.custom_minimum_size.x = target_width
		_build_expanded_content.visible = expanded
		_build_compact_row.visible = (
			not expanded
			or InputDeviceService.shared().is_controller()
		)
		_build_bar.add_theme_stylebox_override(
			"panel",
			_build_panel_expanded_style
			if expanded
			else _build_panel_collapsed_style
		)
		if not expanded:
			_start_build_bag_idle()
		_position_context_above_build_library()
	else:
		_build_library_tween = create_tween()
		_build_library_tween.set_parallel(true)
		_build_library_tween.set_trans(Tween.TRANS_QUART)
		_build_library_tween.set_ease(
			Tween.EASE_OUT if expanded else Tween.EASE_IN_OUT
		)
		_build_library_tween.tween_property(
			_build_expanded_clip,
			"custom_minimum_size:y",
			target_height,
			0.24 if expanded else 0.18
		)
		_build_library_tween.tween_property(
			_build_bar,
			"custom_minimum_size:x",
			target_width,
			0.24 if expanded else 0.18
		)
		if not expanded:
			_build_library_tween.chain().tween_callback(
				_finish_build_bag_collapse
			)
	if expanded:
		call_deferred("_update_build_scroll_buttons")
		if InputDeviceService.shared().is_controller():
			call_deferred("focus_build_library")


func _finish_build_bag_collapse() -> void:
	if _build_library_expanded:
		return
	_build_expanded_content.visible = false
	_build_compact_row.visible = true
	_build_bar.add_theme_stylebox_override(
		"panel",
		_build_panel_collapsed_style
	)
	_start_build_bag_idle()
	_position_context_above_build_library()


func _start_build_bag_idle() -> void:
	if (
		_build_expand_button == null
		or not _build_bar.visible
		or _build_library_expanded
	):
		return
	if _build_bag_idle_tween != null and _build_bag_idle_tween.is_valid():
		_build_bag_idle_tween.kill()
	_build_expand_button.pivot_offset = (
		_build_expand_button.size * 0.5
		if _build_expand_button.size != Vector2.ZERO
		else _build_expand_button.custom_minimum_size * 0.5
	)
	_build_expand_button.scale = Vector2.ONE
	_build_bag_idle_tween = create_tween().set_loops()
	_build_bag_idle_tween.set_trans(Tween.TRANS_SINE)
	_build_bag_idle_tween.set_ease(Tween.EASE_IN_OUT)
	_build_bag_idle_tween.tween_property(
		_build_expand_button,
		"scale",
		Vector2(1.035, 1.035),
		0.9
	)
	_build_bag_idle_tween.tween_property(
		_build_expand_button,
		"scale",
		Vector2.ONE,
		0.9
	)


func _animate_build_bag_open() -> void:
	if (
		_build_library_expanded
		or _build_bag_open_pending
		or not _build_hover_expand_armed
	):
		return
	_build_bag_open_pending = true
	if _build_bag_idle_tween != null and _build_bag_idle_tween.is_valid():
		_build_bag_idle_tween.kill()
	if _build_bag_button_tween != null and _build_bag_button_tween.is_valid():
		_build_bag_button_tween.kill()
	_build_expand_button.pivot_offset = _build_expand_button.size * 0.5
	_build_bag_button_tween = create_tween()
	_build_bag_button_tween.set_trans(Tween.TRANS_BACK)
	_build_bag_button_tween.set_ease(Tween.EASE_OUT)
	_build_bag_button_tween.tween_property(
		_build_expand_button,
		"scale",
		Vector2(1.12, 1.12),
		0.1
	)
	_build_bag_button_tween.tween_callback(
		func():
			_build_expand_button.scale = Vector2.ONE
			set_build_library_expanded(true)
	)


func request_build_library_open() -> void:
	if not placement.active:
		return
	set_build_library_expanded(true)


func build_library_collapsed() -> bool:
	return _build_bar != null and _build_bar.visible and not _build_library_expanded


func _on_build_library_mouse_entered() -> void:
	_build_mouse_exit_pending = false
	if (
		not _build_library_expanded
		and _build_hover_expand_armed
		and not placement.pointer_dragging_moved_piece()
		and not placement.pointer_dragging_catalogue_piece()
	):
		_animate_build_bag_open()


func _on_build_library_mouse_exited() -> void:
	_build_hover_expand_armed = true
	if not _build_library_expanded:
		_build_bag_open_pending = false
		if (
			_build_bag_button_tween != null
			and _build_bag_button_tween.is_valid()
		):
			_build_bag_button_tween.kill()
		_build_expand_button.scale = Vector2.ONE
		_start_build_bag_idle()
		return
	# Defer one frame because a child Control taking hover can briefly emit an
	# exit from the parent on some platforms. Only collapse after confirming
	# that the pointer actually left the whole bag.
	_build_mouse_exit_pending = true
	call_deferred("_collapse_build_library_after_mouse_exit")


func _collapse_build_library_after_mouse_exit() -> void:
	if not _build_mouse_exit_pending:
		return
	_build_mouse_exit_pending = false
	if (
		_build_bar == null
		or not _build_bar.visible
		or _build_bar.get_global_rect().has_point(get_viewport().get_mouse_position())
	):
		return
	set_build_library_expanded(false)
	# A genuine trip out of the dock arms the next hover to open it again.
	_build_hover_expand_armed = true


func _on_build_drop_overlay_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
		and _store_dragged_world_piece()
	):
		_build_drop_overlay.accept_event()


func _store_dragged_world_piece() -> bool:
	if placement == null or not placement.pointer_dragging_moved_piece():
		return false
	return _store_current_world_piece()


func _store_current_world_piece() -> bool:
	if (
		placement == null
		or placement.held.is_empty()
		or placement.held.get("moving") == null
	):
		return false
	# The signal is synchronous: Main commits the detached tile/structure to
	# stock before this method returns.
	build_store_requested.emit()
	_set_build_drop_active(false)
	_set_store_bubble_visible(false)
	_refresh_build_strip()
	return true


func _store_held_from_bubble() -> void:
	_store_current_world_piece()


func _on_store_bubble_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
		and placement != null
		and placement.pointer_dragging_moved_piece()
		and _store_current_world_piece()
	):
		_store_bubble.accept_event()


func _on_build_library_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
		and _store_dragged_world_piece()
	):
		_build_bar.accept_event()
	elif (
		not _build_library_expanded
		and (
			event is InputEventPanGesture
			or event is InputEventMouseButton
			and event.pressed
			and event.button_index in [
				MOUSE_BUTTON_WHEEL_UP,
				MOUSE_BUTTON_WHEEL_DOWN,
				MOUSE_BUTTON_WHEEL_LEFT,
				MOUSE_BUTTON_WHEEL_RIGHT,
			]
		)
	):
		set_build_library_expanded(true)
		_build_bar.accept_event()
	elif (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		if not placement.held.is_empty():
			placement.cancel_click()
		set_build_library_expanded(true)
		_build_bar.accept_event()


func _process(_delta: float) -> void:
	if _build_bar != null and _build_bar.visible:
		_position_context_above_build_library()
	if _store_bubble != null and _store_bubble.visible:
		_position_store_bubble()
	if placement == null or not placement.active:
		_set_build_drop_active(false)
		_set_store_bubble_visible(false)
		_catalogue_pointer_active = false
		return
	if placement.pointer_is_down():
		# GUI controls can consume mouse motion after a world drag reaches the
		# dock, or after a catalogue card collapses beneath it. Polling the real
		# pointer keeps both gestures continuous across those boundaries.
		placement.pointer_motion(get_viewport().get_mouse_position())
	var pointer := get_viewport().get_mouse_position()
	var over_library := _build_bar.get_global_rect().has_point(pointer)
	var over_store_bubble := (
		_store_bubble != null
		and _store_bubble.visible
		and _store_bubble.get_global_rect().has_point(pointer)
	)
	if placement.pointer_dragging_moved_piece():
		_set_build_drop_active(over_library)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if over_library or over_store_bubble:
				_store_current_world_piece()
			else:
				placement.pointer_release(pointer)
			_set_build_drop_active(false)
		return
	_set_build_drop_active(false)
	if (
		_catalogue_pointer_active
		and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	):
		if (
			placement.pointer_dragging_catalogue_piece()
			and not over_library
		):
			placement.pointer_release(pointer)
		else:
			placement.cancel_pointer_gesture()
		_catalogue_pointer_active = false


func _set_build_drop_active(active: bool) -> void:
	if _build_drop_active == active or _build_drop_overlay == null:
		return
	_build_drop_active = active
	_build_drop_overlay.visible = active


func _set_store_bubble_visible(visible: bool, animate := true) -> void:
	if _store_bubble == null or _store_bubble.visible == visible:
		return
	if _store_bubble_tween != null and _store_bubble_tween.is_valid():
		_store_bubble_tween.kill()
	if (
		_store_bubble_idle_tween != null
		and _store_bubble_idle_tween.is_valid()
	):
		_store_bubble_idle_tween.kill()
	_store_bubble.visible = visible
	if not visible:
		return
	_position_store_bubble()
	_store_bubble.pivot_offset = _store_bubble.size * 0.5
	_store_bubble.modulate.a = 0.0 if animate else 1.0
	_store_bubble.scale = Vector2(0.82, 0.82) if animate else Vector2.ONE
	if animate:
		_store_bubble_tween = create_tween()
		_store_bubble_tween.set_parallel(true)
		_store_bubble_tween.set_trans(Tween.TRANS_BACK)
		_store_bubble_tween.set_ease(Tween.EASE_OUT)
		_store_bubble_tween.tween_property(
			_store_bubble, "scale", Vector2.ONE, 0.18
		)
		_store_bubble_tween.tween_property(
			_store_bubble, "modulate:a", 1.0, 0.12
		)
		_store_bubble_tween.chain().tween_callback(
			_start_store_bubble_idle
		)


func _start_store_bubble_idle() -> void:
	if _store_bubble == null or not _store_bubble.visible:
		return
	_store_bubble_idle_tween = create_tween().set_loops()
	_store_bubble_idle_tween.set_trans(Tween.TRANS_SINE)
	_store_bubble_idle_tween.set_ease(Tween.EASE_IN_OUT)
	_store_bubble_idle_tween.tween_property(
		_store_bubble, "scale", Vector2(1.025, 1.025), 0.7
	)
	_store_bubble_idle_tween.tween_property(
		_store_bubble, "scale", Vector2.ONE, 0.7
	)


func _position_store_bubble() -> void:
	if _store_bubble == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var bubble_size := Vector2(
		maxf(_store_bubble.size.x, _store_bubble.custom_minimum_size.x),
		maxf(_store_bubble.size.y, _store_bubble.custom_minimum_size.y)
	)
	var bag_top := viewport_size.y - 18.0
	if _build_bar != null and _build_bar.visible:
		bag_top = _build_bar.get_global_rect().position.y
	var target := Vector2(
		(viewport_size.x - bubble_size.x) * 0.5,
		bag_top - bubble_size.y - 18.0
	)
	target.y = maxf(14.0, target.y)
	_store_bubble.position = target


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
		set_build_library_expanded(
			InputDeviceService.shared().is_controller(),
			false
		)
		_build_hover_expand_armed = true
		_refresh_build_strip()
		call_deferred("_position_context_above_build_library")
		if not _build_library_expanded:
			call_deferred("_start_build_bag_idle")
		if InputDeviceService.shared().is_controller() and placement.held.is_empty():
			focus_build_library()
	else:
		_set_store_bubble_visible(false)
		_catalogue_pointer_active = false
		release_build_focus()
		_position_context_above_build_library()


func _on_action_result(ok: bool, message: String, _kind: String) -> void:
	if message != "":
		toast(message, "good" if ok else "warn")


# ------------------------------------------------------------------ prompt / hints / toasts

func set_prompt(
	action: StringName,
	description: String,
	secondary: Array[Dictionary] = []
) -> void:
	_prompt_action = action
	_prompt_description = description
	_prompt_secondary = secondary.duplicate(true)
	_refresh_prompt()


func _refresh_prompt() -> void:
	if _prompt_action == &"" or _prompt_description == "":
		_prompt_label.text = ""
		return
	var parts := PackedStringArray([
		InputDeviceService.shared().format_action(_prompt_action, _prompt_description)
	])
	for entry: Dictionary in _prompt_secondary:
		parts.append(InputDeviceService.shared().format_action(
			StringName(entry.get("action", "")),
			String(entry.get("label", ""))
		))
	_prompt_label.text = "  ·  ".join(parts)


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
		set_hint(
			"Try catch-and-release fishing along the northern water. (%s)"
			% InputDeviceService.shared().format_action(&"interact", "when close")
		)
	elif core.parcels.has_pending():
		set_hint("Choose one finished tile from the Land Parcel.")
	elif core.grid.placed_tile_count() == 0 and core.stock.total_tiles() > 0:
		set_hint(
			"Place your new land beside the world you have. (%s)"
			% InputDeviceService.shared().format_action(&"build_mode", "build mode")
		)
	elif core.grid.placed_tile_count() > 0 and core.skills.lifetime_actions.get("woodcutting", 0) == 0:
		if _has_placed_tree():
			set_hint("Tend your placed tree — it will rest, then regrow.")
		elif _stored_tree_count() > 0:
			set_hint("Place your tree from the Build Library, then tend it.")
		else:
			set_hint("")
	else:
		set_hint("")


func focus_build_library() -> void:
	if not InputDeviceService.shared().is_controller() or not _build_bar.visible:
		return
	if not _build_library_expanded:
		InputDeviceService.shared().focus_first(_build_bar, _build_expand_button)
		return
	var preferred: Control
	for child in _build_strip.get_children():
		var button := child as BaseButton
		if button != null and not button.disabled:
			preferred = button
			break
	if preferred == null:
		for child in _build_category_strip.get_children():
			var category_button := child as BaseButton
			if category_button != null and not category_button.disabled:
				preferred = category_button
				break
	if preferred == null:
		preferred = _build_expand_button
	InputDeviceService.shared().focus_first(_build_bar, preferred)


func release_build_focus() -> void:
	if _build_bar != null:
		InputDeviceService.shared().release_focus_in(_build_bar)


func focus_default() -> void:
	if _build_bar.visible:
		focus_build_library()
	else:
		InputDeviceService.shared().focus_first(_bottom_buttons, _build_button)


func _on_held_changed(value: Dictionary) -> void:
	_refresh_compact_build_dock()
	var moving_world_piece := (
		not value.is_empty()
		and value.get("moving") != null
		and not InputDeviceService.shared().is_controller()
	)
	_set_store_bubble_visible(moving_world_piece)
	if not placement.active or not InputDeviceService.shared().is_controller():
		return
	if (
		value.is_empty()
		and not placement.controller_cursor_active()
		and _build_library_expanded
	):
		focus_build_library()
	else:
		release_build_focus()


func _on_input_method_changed(_method: int) -> void:
	if _menu_button == null:
		return
	_menu_button.text = InputDeviceService.shared().format_action(
		&"pause" if InputDeviceService.shared().is_controller() else &"cancel",
		"Menu"
	)
	_build_button.text = InputDeviceService.shared().format_action(
		&"build_mode",
		"Shape Land"
	)
	_build_hint_label.text = (
		"%s  ·  %s  ·  %s  ·  %s"
		% [
			InputDeviceService.shared().format_action(&"ui_accept", "choose"),
			InputDeviceService.shared().format_action(&"build_mode", "browse world"),
			InputDeviceService.shared().format_action(&"rotate_piece", "rotate"),
			InputDeviceService.shared().format_action(&"cancel", "back"),
		]
		if InputDeviceService.shared().is_controller()
		else "%s  ·  wheel scrolls  ·  %s  ·  drag moved pieces here to store"
		% [
			InputDeviceService.shared().format_action(&"interact", "choose"),
			InputDeviceService.shared().format_action(&"rotate_piece", "rotate"),
		]
	)
	_refresh_prompt()
	update_tutorial()
	if placement.active:
		if _build_library_expanded:
			_build_compact_row.visible = InputDeviceService.shared().is_controller()
		_refresh_build_strip()
		if (
			InputDeviceService.shared().is_controller()
			and placement.held.is_empty()
			and _build_library_expanded
		):
			focus_build_library()
		elif not InputDeviceService.shared().is_controller():
			release_build_focus()


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
