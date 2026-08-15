class_name Hud
extends CanvasLayer
## Persistent interface: health, context prompts, toasts, the Build Bag, and
## tutorial hints. Discovery presentation and modal panels live elsewhere.

signal catch_basket_requested
signal spirit_pouch_requested
signal token_pouch_requested
signal build_piece_selected(kind: String, id: String)
signal worldheart_offer_requested(kind: String, id: String)
signal build_world_browse_requested
signal build_store_requested
signal pause_requested
signal player_dock_activated
signal player_dock_drag_started(screen_position: Vector2)
signal player_dock_drag_moved(screen_position: Vector2)
signal player_dock_drag_released(screen_position: Vector2)

const BuildThumbnailRendererScript := preload(
	"res://scripts/ui/build_thumbnail_renderer.gd"
)
var core: GameCore
var kit: UiKit
var placement: PlacementController

var _prompt_label: Label
var _hint_label: Label
var _hint_panel: PanelContainer
var _health_box: HBoxContainer
var _token_pouch_button: Button
var _build_bar: BuildBagSheet
var _build_bar_column: VBoxContainer
var _build_compact_row: HBoxContainer
var _build_expand_button: Button
var _build_pin_button: Button
var _build_close_button: Button
var _build_expanded_clip: Control
var _build_expanded_content: VBoxContainer
var _build_search: LineEdit
var _build_category_before_search := ""
var _build_previous_search_query := ""
var _build_category_scroll: ScrollContainer
var _build_category_strip: HBoxContainer
var _build_item_scroll: ScrollContainer
var _build_strip: GridContainer
var _build_previous_button: Button
var _build_next_button: Button
var _build_category_group: ButtonGroup
var _build_sections: VBoxContainer
var _build_section_nodes: Dictionary = {}
var _build_item_buttons: Array[Button] = []
var _build_scroll_memory := 0
var _selected_build_category := ""
var _selected_build_entry: Dictionary = {}
## Distance from the bottom edge to the hover strip, and how long the pointer
## may be off the sheet before it closes. The grace exists because moving
## between the sheet's own child controls briefly reports an exit.
const BAG_STRIP_MARGIN := 10
const BAG_HOVER_CLOSE_GRACE := 0.18
## Slack around the sheet so the pointer may cross the gap to the strip, or
## clip a rounded corner, without the bag reading it as having left.
const BAG_HOVER_SLACK := 12.0
## The bag opens showing one and a half rows: a full row to use, and the top of
## the next one cut off by the sheet edge, which is what tells the player there
## is more without a scrollbar having to. Scrolling grows it by two more rows.
## The sheet travels its own height from below the screen edge, not the 12px
## nudge the shared open_offset token gives every other panel -- at 12px the
## overshoot measured 0.6px, which is invisible. A full-height slide needs its
## own duration too, or a scroll unrolling looks like a snap.
const BAG_SLIDE_OPEN := 0.34
const BAG_SLIDE_CLOSE := 0.26
const BAG_ROWS_COMPACT := 1.5
const BAG_ROWS_SCROLLED := 3.5
var _bag_rows := BAG_ROWS_COMPACT
var _build_library_expanded := false
var _build_library_pinned := false
var _build_hover_expand_armed := true
var _build_mouse_exit_pending := false
var _build_library_tween: Tween
var _build_bag_button_tween: Tween
var _build_bag_idle_tween: Tween
var _build_bag_open_pending := false
var _bag_hover_strip: PanelContainer
var _bag_hover_close_timer: Timer
## Last pointer position seen on a motion event. Viewport.get_mouse_position()
## reports the OS cursor, which synthetic events do not move, so reading it
## made the bag untestable -- and it is the same number in play.
var _pointer_position := Vector2.ZERO
var _pointer_seen := false
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
var _build_hint_label: Label
var _player_dock_panel: PanelContainer
var _player_dock: TextureButton
var _player_dock_label: Label
var _player_drag_icon: TextureRect
var _player_deployed := false
var _hover_tooltip: PanelContainer
var _hover_name_label: Label
var _hover_collection_label: Label
var _prompt_action := &""
var _prompt_description := ""
var _prompt_secondary: Array[Dictionary] = []

const BUILD_CATEGORIES := BuildCategoryResolver.CATEGORIES
const BUILD_ICON_DIRECTORY := BuildCategoryResolver.ICON_DIRECTORY
const HARVEST_ICON_FILES := {
	"axe": "harvest_axe.svg",
	"pickaxe": "harvest_pickaxe.svg",
	"sickle": "harvest_sickle.svg",
	"crack": "harvest_crack.svg",
}
const HARVEST_ICON_LABELS := {
	"axe": "Choppable",
	"pickaxe": "Mineable",
	"sickle": "Gatherable",
	"crack": "Breakable",
}


func setup(game_core: GameCore, ui_kit: UiKit, placement_controller: PlacementController) -> void:
	core = game_core
	kit = ui_kit
	placement = placement_controller
	_build_layout()
	core.onboarding.stage_changed.connect(func(_stage): update_tutorial())
	core.stock.stock_changed.connect(func():
		_refresh_build_strip()
	)
	core.token_pouch.balance_changed.connect(func(_token_id, _amount):
		_refresh_token_pouch()
	)
	if core.registries.feature("combat_enabled", false):
		core.combat.health_changed.connect(_on_health_changed)
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
	# World-space overlays live on canvas layer 0; the persistent HUD stays on
	# layer 1 so selection/click effects can never draw through its panels.
	layer = 1
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Health hearts — top center, hidden while safe and full.
	_health_box = HBoxContainer.new()
	_health_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_health_box.position.y = 16
	_health_box.add_theme_constant_override("separation", 4)
	_health_box.visible = false
	root.add_child(_health_box)

	# Biome-token wallet. It stays compact but makes every harvest payout
	# immediately legible; the same panel opens from the inventory action for
	# keyboard and controller players.
	# Calm HUD: the wallet surfaces only for a few breaths after a payout,
	# then leaves the screen to the world. The inventory action keeps it one
	# press away at all times.
	_token_pouch_button = kit.button("", false)
	_token_pouch_button.name = "TokenPouch"
	kit.place_hud_chip(_token_pouch_button, false, 210.0, 42.0)
	kit.apply_hud_chip_style(
		_token_pouch_button, kit.collection_accent("collections")
	)
	_token_pouch_button.custom_minimum_size = Vector2(210, 42)
	_token_pouch_button.add_theme_font_size_override("font_size", 15)
	_token_pouch_button.focus_mode = Control.FOCUS_NONE
	_token_pouch_button.pressed.connect(func(): token_pouch_requested.emit())
	_token_pouch_button.visible = false
	_token_pouch_button.modulate.a = 0.0
	root.add_child(_token_pouch_button)

	# Build hover identity — compact and centered, so the world remains the
	# dominant surface while every tile/object still has a clear name.
	_hover_tooltip = kit.card(Vector2(260, 0))
	_hover_tooltip.name = "PlaceableHoverTooltip"
	_hover_tooltip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hover_tooltip.position.y = 14
	_hover_tooltip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hover_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_tooltip.visible = false
	_hover_tooltip.add_theme_stylebox_override(
		"panel", kit.hud_tooltip_style(kit.collection_accent("land"))
	)
	root.add_child(_hover_tooltip)
	var hover_col := VBoxContainer.new()
	hover_col.add_theme_constant_override("separation", 0)
	_hover_tooltip.add_child(hover_col)
	_hover_name_label = kit.display_label("", 18)
	_hover_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hover_col.add_child(_hover_name_label)
	_hover_collection_label = kit.utility_label("", 11)
	_hover_collection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_collection_label.add_theme_color_override(
		"font_color", kit.text_color()
	)
	hover_col.add_child(_hover_collection_label)

	# Context prompt + tutorial hint — bottom center.
	_context_column = VBoxContainer.new()
	_context_column.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_context_column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_context_column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_context_column.alignment = BoxContainer.ALIGNMENT_END
	_context_column.add_theme_constant_override("separation", 8)
	_context_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_context_column)
	_hint_panel = kit.card(Vector2(440, 0))
	_hint_panel.add_theme_stylebox_override(
		"panel", kit.hud_tooltip_style(kit.palette.color("ui_accent"))
	)
	_hint_panel.visible = false
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_context_column.add_child(_hint_panel)
	_hint_label = kit.label("", 15)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size.x = 400
	_hint_label.add_theme_color_override(
		"font_color", kit.text_color()
	)
	_hint_panel.add_child(_hint_label)
	_prompt_label = kit.label("", 20)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context_column.add_child(_prompt_label)
	_position_context_above_build_library.call_deferred()

	# Build Bag — one calm, bottom slide-up collection sheet. It is a view over stock;
	# all ownership, placement, and save rules remain in their existing systems.
	_build_bar = BuildBagSheet.new()
	_build_bar.setup(kit)
	_build_bar.visible = false
	_build_bar.close_requested.connect(_close_build_library)
	_build_bar.search_changed.connect(_on_build_search_changed)
	_build_bar.category_selected.connect(_select_build_category)
	_build_bar.gui_input.connect(_on_build_library_input)
	root.add_child(_build_bar)
	_build_search = _build_bar.search_field
	_build_close_button = _build_bar.close_button
	_build_item_scroll = _build_bar.scroll
	_build_item_scroll.gui_input.connect(_on_build_scroll_input)
	_build_sections = _build_bar.sections
	_build_item_scroll.gui_input.connect(
		func(event): _on_library_scroll_input(event, _build_item_scroll)
	)
	_build_item_scroll.get_v_scroll_bar().value_changed.connect(
		func(value: float):
			_build_scroll_memory = int(round(value))
			_sync_build_category_to_scroll()
	)

	# A tiny world-facing handle is all that remains after choosing a piece.
	# It has a generous hit target without becoming a second panel.
	_build_expand_button = kit.minimal_icon_button("⌃", "Open Build Bag", 38.0)
	_build_expand_button.name = "BuildBagHandle"
	_build_expand_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build_expand_button.position.y = -18
	_build_expand_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_expand_button.visible = false
	_build_expand_button.pressed.connect(
		func(): set_build_library_expanded(true)
	)
	root.add_child(_build_expand_button)

	# A quiet strip along the bottom edge that opens the bag on hover. Text and
	# not a glyph: the design system carries this interface on warm paper and
	# dark ink, and a symbol here would be the only icon on the HUD.
	_bag_hover_strip = PanelContainer.new()
	_bag_hover_strip.name = "BuildBagHoverStrip"
	_bag_hover_strip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bag_hover_strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bag_hover_strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bag_hover_strip.position.y = -BAG_STRIP_MARGIN
	_bag_hover_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_bag_hover_strip.add_theme_stylebox_override(
		"panel", kit.hud_tooltip_style()
	)
	_bag_hover_strip.add_child(kit.utility_label("Build Bag"))
	_bag_hover_strip.mouse_entered.connect(_on_bag_strip_mouse_entered)
	_bag_hover_strip.mouse_exited.connect(_on_bag_strip_mouse_exited)
	root.add_child(_bag_hover_strip)

	_bag_hover_close_timer = Timer.new()
	_bag_hover_close_timer.name = "BuildBagHoverClose"
	_bag_hover_close_timer.one_shot = true
	_bag_hover_close_timer.wait_time = BAG_HOVER_CLOSE_GRACE
	_bag_hover_close_timer.timeout.connect(
		_collapse_build_library_after_mouse_exit
	)
	add_child(_bag_hover_close_timer)


	_build_drop_overlay = PanelContainer.new()
	_build_drop_overlay.name = "BuildLibraryStoreDrop"
	_build_drop_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_drop_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_build_drop_overlay.visible = false
	_build_drop_overlay.gui_input.connect(_on_build_drop_overlay_input)
	_build_drop_overlay.add_theme_stylebox_override(
		"panel", kit.drop_target_style()
	)
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
	kit.apply_hud_chip_style(
		_store_bubble, kit.collection_accent("build_bag")
	)
	_store_bubble.visible = false
	_store_bubble.pressed.connect(_store_held_from_bubble)
	_store_bubble.gui_input.connect(_on_store_bubble_input)
	root.add_child(_store_bubble)

	_thumbnail_renderer = BuildThumbnailRendererScript.new()
	_thumbnail_renderer.name = "BuildThumbnailRenderer"
	add_child(_thumbnail_renderer)
	_thumbnail_renderer.setup(core, placement.assets)
	get_viewport().size_changed.connect(_resize_build_library)
	_resize_build_library()


# ------------------------------------------------------------------ refresh

func _refresh_all() -> void:
	refresh_fishing_buttons()
	_refresh_token_pouch()
	_refresh_build_strip()
	if core.registries.feature("combat_enabled", false):
		_on_health_changed(core.combat.health, core.combat.max_health)
	else:
		_health_box.visible = false


var _pouch_fade_tween: Tween
var _last_pouch_signature := ""


func _refresh_token_pouch() -> void:
	if _token_pouch_button == null:
		return
	var forest: int = core.token_pouch.balance("token_forest")
	var rock: int = core.token_pouch.balance("token_rock")
	_token_pouch_button.text = "Pouch   Forest %d   ·   Rock %d" % [forest, rock]
	_token_pouch_button.tooltip_text = "Open Pouch & Boxes · %s" % (
		InputDeviceService.shared().format_action(&"panel_inventory", "open")
	)
	# Surface briefly on change, then fade back out of the way.
	var signature := "%d:%d" % [forest, rock]
	if signature == _last_pouch_signature:
		return
	var first_reading := _last_pouch_signature == ""
	_last_pouch_signature = signature
	if first_reading:
		return
	if _pouch_fade_tween != null and _pouch_fade_tween.is_valid():
		_pouch_fade_tween.kill()
	_token_pouch_button.visible = true
	_pouch_fade_tween = _token_pouch_button.create_tween()
	_pouch_fade_tween.tween_property(_token_pouch_button, "modulate:a", 1.0, 0.22)
	_pouch_fade_tween.tween_interval(3.6)
	_pouch_fade_tween.tween_property(_token_pouch_button, "modulate:a", 0.0, 0.8)
	_pouch_fade_tween.tween_callback(func():
		if _token_pouch_button != null:
			_token_pouch_button.visible = false
	)


func set_player_deployed(deployed: bool) -> void:
	if _player_dock == null:
		return
	_player_deployed = deployed
	_player_dock.set_deployed(deployed)
	_player_dock_label.text = "Recall keeper" if deployed else "Drag keeper"
	_player_drag_icon.visible = false


func set_player_drop_valid(valid: bool) -> void:
	if _player_drag_icon == null:
		return
	_player_drag_icon.modulate = Color.WHITE if valid else Color(1.0, 0.42, 0.36, 0.88)


func player_dock_visible() -> bool:
	return _player_dock_panel != null and _player_dock_panel.visible


func set_player_dock_visible(visible: bool) -> void:
	if _player_dock_panel != null:
		_player_dock_panel.visible = visible


func _on_player_dock_drag_started(screen_position: Vector2) -> void:
	_player_drag_icon.visible = true
	_move_player_drag_icon(screen_position)
	player_dock_drag_started.emit(screen_position)


func _on_player_dock_drag_moved(screen_position: Vector2) -> void:
	_move_player_drag_icon(screen_position)
	player_dock_drag_moved.emit(screen_position)


func _on_player_dock_drag_released(screen_position: Vector2) -> void:
	_player_drag_icon.visible = false
	player_dock_drag_released.emit(screen_position)


func _move_player_drag_icon(screen_position: Vector2) -> void:
	if _player_drag_icon == null:
		return
	_player_drag_icon.position = screen_position - _player_drag_icon.size * 0.5


func refresh_fishing_buttons() -> void:
	# Fishing storage no longer owns persistent HUD buttons.
	pass


func _refresh_build_strip() -> void:
	var entries_by_category := _collect_build_entries()
	_thumbnail_renderer.discard_pending()
	_clear_container(_build_sections)
	_build_section_nodes.clear()
	_build_item_buttons.clear()
	_build_strip = null
	var populated := 0
	var columns := _build_columns()
	for category: Dictionary in BUILD_CATEGORIES:
		var category_id := String(category["id"])
		var entries: Array = entries_by_category[category_id]
		if entries.is_empty():
			continue
		if _selected_build_category == "":
			_selected_build_category = category_id
		var section := CollectionSection.new()
		section.setup(
			kit,
			category_id,
			String(category["label"]),
			_build_category_accent(category_id),
			_build_category_glyph(category_id),
			columns
		)
		_build_sections.add_child(section)
		_build_section_nodes[category_id] = section
		if _build_strip == null:
			_build_strip = section.grid
		for entry: Dictionary in entries:
			_add_build_item_cell(section, entry, category_id)
		populated += 1
	_refresh_build_categories()
	if populated == 0:
		var empty := kit.muted_label(
			(
				"Nothing in the collection matches “%s”."
				% _build_search.text.strip_edges()
				if not _build_search_query().is_empty()
				else "Your Build Bag is empty — collect a surfaced Worldheart gift."
			),
			14
		)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size.y = 120
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_build_sections.add_child(empty)
	_refresh_compact_build_dock()
	call_deferred("_restore_build_scroll")


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
		):
			continue
		var category_id := category_for_tile(definition)
		if not _build_entry_matches_search(
			definition.display_name, tile_id, category_id
		):
			continue
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
		if not _build_entry_matches_search(
			definition.display_name, structure_id, category_id
		):
			continue
		var harvest_icon := ""
		var harvest_label := ""
		if definition.has_capability("harvest_source"):
			var profile_id := String(
				definition.capability("harvest_source").get("profile_id", "")
			)
			var harvest_profile := core.registries.harvest_profile(profile_id)
			if harvest_profile != null:
				harvest_icon = harvest_profile.tool_icon
				harvest_label = String(
					HARVEST_ICON_LABELS.get(harvest_icon, harvest_profile.verb.capitalize())
				)
		result[category_id].append({
			"kind": "structure",
			"id": structure_id,
			"name": definition.display_name,
			"count": count,
			"harvest_icon": harvest_icon,
			"tooltip": "%s%s · %s" % [
				("%s · " % harvest_label if harvest_label != "" else ""),
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
		if not _build_entry_matches_search(
			definition.display_name, landmark_id, "deeds"
		):
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


func _on_build_search_changed(query: String) -> void:
	var had_query := not _build_previous_search_query.is_empty()
	var has_query := not query.strip_edges().is_empty()
	if not had_query and has_query:
		_build_category_before_search = _selected_build_category
	elif had_query and not has_query:
		_selected_build_category = _build_category_before_search
		_build_category_before_search = ""
	_build_previous_search_query = query.strip_edges()
	_build_scroll_memory = 0
	_refresh_build_strip()


func _build_search_query() -> String:
	return _build_search.text.strip_edges().to_lower() if _build_search != null else ""


func _build_entry_matches_search(
	display_name: String,
	content_id: String,
	category_id: String
) -> bool:
	var query := _build_search_query()
	if query.is_empty():
		return true
	var searchable := "%s %s %s" % [
		display_name.to_lower(),
		content_id.to_lower().replace("_", " "),
		_build_category_label(category_id).to_lower(),
	]
	for term in query.split(" ", false):
		if String(term) not in searchable:
			return false
	return true


func _refresh_build_items(entries_by_category: Dictionary) -> void:
	# Kept as a compatibility seam for callers that previously refreshed one
	# selected category. The collection sheet always renders every section.
	_refresh_build_strip()


func _add_build_item_cell(
	section: CollectionSection,
	entry: Dictionary,
	category_id: String
) -> void:
	var kind := String(entry["kind"])
	var content_id := String(entry["id"])
	var selected := (
		String(_selected_build_entry.get("kind", "")) == kind
		and String(_selected_build_entry.get("id", "")) == content_id
	)
	var item_button := InventoryItemCell.new()
	item_button.setup(
		kit,
		String(entry["name"]),
		int(entry["count"]),
		selected
	)
	var cell_extent := _build_cell_extent()
	item_button.custom_minimum_size = Vector2(cell_extent, cell_extent)
	item_button.name = "BuildItem_%s" % content_id
	var tooltip_parts := PackedStringArray([
		String(entry["name"]),
		"%s · %d available" % [
			_build_category_label(category_id),
			int(entry["count"]),
		],
	])
	var detail := String(entry.get("tooltip", ""))
	if detail != "":
		tooltip_parts.append(detail)
	tooltip_parts.append(InputDeviceService.shared().format_action(
		&"ui_accept" if InputDeviceService.shared().is_controller() else &"interact",
		"place"
	))
	if core.diorama.enabled and core.diorama.worldheart.can_offer(kind, content_id):
		tooltip_parts.append(InputDeviceService.shared().format_action(
			&"offer_to_worldheart", "offer this spare"
		))
	item_button.tooltip_text = "\n".join(tooltip_parts)
	var harvest_icon := String(entry.get("harvest_icon", ""))
	if harvest_icon != "":
		item_button.set_status(
			_build_category_accent(category_id),
			String(HARVEST_ICON_LABELS.get(harvest_icon, "Interactive"))
		)
	item_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	item_button.pressed.connect(func(): _on_build_piece_pressed(entry))
	item_button.gui_input.connect(_on_build_item_input.bind(entry))
	item_button.focus_entered.connect(
		func(): _build_bar.show_focus_detail(item_button.tooltip_text)
	)
	item_button.focus_exited.connect(func(): _build_bar.show_focus_detail(""))
	item_button.mouse_entered.connect(
		func(): _build_bar.show_focus_detail(item_button.tooltip_text)
	)
	item_button.mouse_exited.connect(func(): _build_bar.show_focus_detail(""))
	section.add_item(item_button)
	_build_item_buttons.append(item_button)
	_thumbnail_renderer.request(
		kind,
		content_id,
		Callable(self, "_apply_build_thumbnail").bind(
			kind,
			content_id,
			item_button.preview.get_instance_id()
		)
	)


func _build_category_accent(category_id: String) -> Color:
	match category_id:
		"ground": return kit.collection_accent("land")
		"woodland", "nature": return kit.collection_accent("woodland")
		"stone", "boundaries": return kit.collection_accent("stone")
		"winter": return kit.palette.color("ui_info").lightened(0.15)
		"furniture", "storage": return kit.palette.color("ui_journal_structures")
		"utilities": return kit.palette.color("ui_accent_muted")
		"buildings", "deeds": return kit.palette.color("ui_rare")
	return kit.ui_color("accent")


func _build_category_glyph(category_id: String) -> String:
	return {
		"ground": "●",
		"woodland": "◆",
		"stone": "◇",
		"winter": "✦",
		"nature": "●",
		"furniture": "◆",
		"boundaries": "■",
		"utilities": "✧",
		"buildings": "▲",
		"storage": "◇",
		"deeds": "▼",
	}.get(category_id, "◆")


func _build_columns() -> int:
	return kit.tokens.columns_for(
		_build_library_expanded_width()
	)


func _build_cell_extent() -> float:
	var columns := _build_columns()
	var usable_width := (
		_build_library_expanded_width()
		- float(kit.tokens.sheet_padding * 2)
		- float(kit.tokens.scrollbar_width)
		- float(kit.tokens.cell_gap * (columns - 1))
	)
	return maxf(
		kit.tokens.reference_cell_size.x,
		floor(usable_width / float(columns))
	)


func _restore_build_scroll() -> void:
	if _build_item_scroll == null:
		return
	var bar := _build_item_scroll.get_v_scroll_bar()
	_build_item_scroll.scroll_vertical = clampi(
		_build_scroll_memory,
		0,
		maxi(0, int(ceil(bar.max_value - bar.page)))
	)


func _add_harvest_badge(button: Button, icon_id: String) -> void:
	var filename := String(HARVEST_ICON_FILES.get(icon_id, ""))
	if filename == "":
		return
	var badge := PanelContainer.new()
	badge.name = "HarvestBadge_%s" % icon_id
	badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	badge.position = Vector2(9, 9)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := kit.badge_style(
		kit.collection_accent(icon_id), 5
	)
	badge.add_theme_stylebox_override("panel", style)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(22, 22)
	icon.texture = load(BUILD_ICON_DIRECTORY + filename)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(icon)
	button.add_child(badge)


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


func _on_build_item_input(event: InputEvent, entry: Dictionary) -> void:
	if not core.diorama.enabled:
		return
	var requested := event.is_action_pressed("offer_to_worldheart")
	if event is InputEventMouseButton:
		requested = event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	if not requested:
		return
	var kind := String(entry.get("kind", ""))
	var content_id := String(entry.get("id", ""))
	if not core.diorama.worldheart.can_offer(kind, content_id):
		toast("Only true spares can be offered; your last copy is protected.", "warn")
	else:
		worldheart_offer_requested.emit(kind, content_id)
	get_viewport().set_input_as_handled()
	call_deferred("focus_build_library")


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


## The category row, built from the sections that actually exist.
##
## Offering a tab for a category the bag cannot fill would be a dead control, so
## the row is derived from _build_section_nodes rather than from the full
## category table.
func _refresh_build_categories() -> void:
	if _build_bar == null:
		return
	var entries: Array = []
	for category: Dictionary in BUILD_CATEGORIES:
		var category_id := String(category["id"])
		if not _build_section_nodes.has(category_id):
			continue
		entries.append({
			"id": category_id,
			"label": _build_category_label(category_id),
			"icon": _build_category_icon(category_id),
			"accent": _build_category_accent(category_id),
		})
	if not _build_section_nodes.has(_selected_build_category):
		_selected_build_category = (
			String(entries[0]["id"]) if not entries.is_empty() else ""
		)
	_build_bar.set_categories(entries, _selected_build_category)


## Marks whichever section the scroll has actually reached.
##
## The tabs scroll rather than filter, so the highlight has to follow the view or
## it would keep pointing at the last tab clicked while the player is looking
## somewhere else entirely.
func _sync_build_category_to_scroll() -> void:
	if _build_item_scroll == null or _build_bar == null:
		return
	if _build_section_nodes.is_empty():
		return
	var view_top := float(_build_item_scroll.scroll_vertical)
	var current := _selected_build_category
	var best := INF
	for category_id: String in _build_section_nodes:
		var section := _build_section_nodes[category_id] as Control
		if section == null or not is_instance_valid(section):
			continue
		# Nearest section top at or above the viewport top: the one whose items
		# fill the view.
		var distance := absf(section.position.y - view_top)
		if section.position.y <= view_top + 8.0 and distance < best:
			best = distance
			current = category_id
	if current != _selected_build_category:
		_selected_build_category = current
		_build_bar.set_active_category(current)


func _build_category_icon(category_id: String) -> Texture2D:
	var path := BuildCategoryResolver.icon_path(category_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _select_build_category(category_id: String) -> void:
	_selected_build_category = category_id
	if _build_bar != null:
		_build_bar.set_active_category(category_id)
	call_deferred("_scroll_to_build_category", category_id)


func _scroll_to_build_category(category_id: String) -> void:
	if _build_item_scroll == null:
		return
	var section := _build_section_nodes.get(category_id) as Control
	if section != null:
		_build_item_scroll.ensure_control_visible(section)


static func category_for_tile(definition: Defs.TileDefinition) -> String:
	return BuildCategoryResolver.category_for_tile(definition)


static func category_for_structure(definition: Defs.StructureDefinition) -> String:
	return BuildCategoryResolver.category_for_structure(definition)


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
	var vertical_bar := scroll.get_v_scroll_bar()
	scroll.scroll_vertical = clampi(
		scroll.scroll_vertical + int(round(delta)),
		0,
		maxi(0, int(ceil(vertical_bar.max_value - vertical_bar.page)))
	)
	scroll.accept_event()
	_build_scroll_memory = scroll.scroll_vertical


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
	# The collection sheet deliberately has one native scrollbar and no paging
	# chrome. Keep this compatibility seam for callers in older test fixtures.
	pass


## One place the sheet's size is decided, so the row count can never be
## bypassed by a caller that only knows about the viewport.
func _apply_bag_viewport(animate_height := false) -> void:
	if _build_bar == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var target_height := _build_bar.height_for_rows(_bag_rows, _build_cell_extent())
	if not animate_height or not _build_bar.visible:
		_build_bar.apply_viewport(viewport_size, target_height)
		return
	# Growing on scroll keeps the bottom edge planted and lifts the top, which
	# is how a sheet gains room without appearing to jump.
	var from_height := _build_bar.size.y
	var grow := create_tween()
	grow.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	grow.tween_method(
		func(height: float) -> void:
			_build_bar.apply_viewport(viewport_size, height),
		from_height,
		target_height,
		kit.motion_duration(0.20)
	)


func _set_bag_rows(rows: float) -> void:
	if is_equal_approx(_bag_rows, rows):
		return
	_bag_rows = rows
	_apply_bag_viewport(true)
	call_deferred("_position_context_above_build_library")


func _on_build_scroll_input(event: InputEvent) -> void:
	# Any scroll gesture is a request for more room, not just a wheel: the
	# player has told us one and a half rows is not enough.
	var wheel := event as InputEventMouseButton
	var pan := event as InputEventPanGesture
	if pan != null or (
		wheel != null
		and wheel.pressed
		and wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
	):
		_set_bag_rows(BAG_ROWS_SCROLLED)


func _resize_build_library() -> void:
	if _build_bar == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_apply_bag_viewport()
	var columns := _build_columns()
	for section_value in _build_section_nodes.values():
		var section := section_value as CollectionSection
		if section != null:
			section.set_columns(columns)
	if _build_bar.visible:
		call_deferred("_position_context_above_build_library")


func _build_library_expanded_width() -> float:
	return kit.tokens.sheet_size(get_viewport().get_visible_rect().size).x


func _position_context_above_build_library() -> void:
	if _context_column == null:
		return
	_context_column.visible = not build_library_expanded()
	if not _context_column.visible:
		return
	var bottom_gap := 86.0
	var viewport_size := get_viewport().get_visible_rect().size
	var content_size := _context_column.get_combined_minimum_size()
	_context_column.size = content_size
	_context_column.position = Vector2(
		(viewport_size.x - content_size.x) * 0.5,
		viewport_size.y - bottom_gap - content_size.y
	)


func set_build_library_expanded(expanded: bool, animate := true) -> void:
	if _build_bar == null:
		return
	if _build_library_expanded == expanded and _build_bar.visible == expanded:
		if expanded and InputDeviceService.shared().is_controller():
			call_deferred("focus_build_library")
		return
	_build_library_expanded = expanded
	_build_scroll_memory = (
		_build_item_scroll.scroll_vertical if _build_item_scroll != null else 0
	)
	_build_bag_open_pending = false
	_build_library_pinned = false
	_build_mouse_exit_pending = false
	if _build_library_tween != null and _build_library_tween.is_valid():
		_build_library_tween.kill()
	var placement_active := placement != null and placement.active
	var duration := kit.motion_duration(
		kit.tokens.open_duration if expanded else kit.tokens.close_duration
	)
	if not expanded:
		release_build_focus()
	_build_expand_button.visible = placement_active and not expanded
	if _bag_hover_strip != null:
		_bag_hover_strip.visible = not expanded
	if expanded:
		_refresh_build_strip()
		_build_bar.visible = true
		_apply_bag_viewport()
		var resting_position := _build_bar.position
		var travel := _build_bar.size.y + float(kit.tokens.sheet_bottom_margin)
		_build_bar.modulate.a = 0.0 if animate and duration > 0.0 else 1.0
		_build_bar.position = (
			resting_position + Vector2(0, travel)
			if animate and duration > 0.0
			else resting_position
		)
		_restore_build_scroll.call_deferred()
		if animate and duration > 0.0:
			# Unrolls like a scroll: it starts fully below its resting place
			# and rises past it before settling. TRANS_BACK supplies that
			# overshoot; the fade is quicker than the travel so the sheet is
			# already solid while it is still moving, which reads as weight
			# rather than as a fading panel.
			_build_library_tween = create_tween().set_parallel(true)
			var slide := kit.motion_duration(BAG_SLIDE_OPEN)
			_build_library_tween.tween_property(
				_build_bar, "modulate:a", 1.0, slide * 0.35
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_build_library_tween.tween_property(
				_build_bar, "position", resting_position, slide
			).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if InputDeviceService.shared().is_controller():
			call_deferred("focus_build_library")
	elif not animate or duration <= 0.0 or not _build_bar.visible:
		_finish_build_bag_collapse()
	else:
		# The same motion in reverse: it gathers upward a little before rolling
		# back down, so closing feels like the opposite of opening rather than
		# like the sheet being switched off.
		_build_library_tween = create_tween().set_parallel(true)
		var slide_out := kit.motion_duration(BAG_SLIDE_CLOSE)
		_build_library_tween.tween_property(
			_build_bar, "modulate:a", 0.0, slide_out
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_build_library_tween.tween_property(
			_build_bar,
			"position",
			_build_bar.position
				+ Vector2(0, _build_bar.size.y + float(kit.tokens.sheet_bottom_margin)),
			slide_out
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		_build_library_tween.chain().tween_callback(_finish_build_bag_collapse)
	_position_context_above_build_library()


func _finish_build_bag_collapse() -> void:
	if _build_library_expanded:
		return
	_build_bar.visible = false
	_build_bar.modulate.a = 1.0
	_bag_rows = BAG_ROWS_COMPACT
	_apply_bag_viewport()
	_build_expand_button.visible = placement != null and placement.active
	if _bag_hover_strip != null:
		_bag_hover_strip.visible = true
	_start_build_bag_idle()
	_position_context_above_build_library()


func _start_build_bag_idle() -> void:
	if _build_expand_button == null:
		return
	if _build_bag_idle_tween != null and _build_bag_idle_tween.is_valid():
		_build_bag_idle_tween.kill()
	_build_expand_button.scale = Vector2.ONE


func _animate_build_bag_open() -> void:
	if _build_library_expanded or _build_bag_open_pending:
		return
	_build_bag_open_pending = true
	set_build_library_expanded(true)


func request_build_library_open() -> void:
	if not placement.active:
		return
	set_build_library_expanded(true)


func build_library_collapsed() -> bool:
	return (
		_build_expand_button != null
		and _build_expand_button.visible
		and not _build_library_expanded
	)


func build_library_expanded() -> bool:
	return _build_bar != null and _build_bar.visible and _build_library_expanded


func blocks_world_pointer(screen_position: Vector2) -> bool:
	# Geometry is authoritative here. Relying only on gui_get_hovered_control()
	# leaves empty Container space transparent to world picking on some layouts.
	for candidate in [
		_build_bar,
		_build_expand_button,
		_store_bubble,
		_player_dock_panel,
		_hint_panel,
		_prompt_label,
		_health_box,
		_token_pouch_button,
	]:
		var control := candidate as Control
		if (
			control != null
			and control.is_visible_in_tree()
			and control.get_global_rect().has_point(screen_position)
		):
			return true
	return false


func _on_build_library_pin_toggled(pinned: bool) -> void:
	# Kept for compatibility with older scenes; the reference sheet has no pin.
	_build_library_pinned = pinned


func _close_build_library() -> void:
	_build_library_pinned = false
	if _build_bar != null:
		_build_bar.hide_search()
	set_build_library_expanded(false)


func _on_bag_strip_mouse_entered() -> void:
	_cancel_bag_hover_close()
	set_build_library_expanded(true)


func _on_bag_strip_mouse_exited() -> void:
	# Leaving the strip upward lands on the sheet, which cancels this again.
	_queue_bag_hover_close()


## Whether the pointer is over the bag, judged by rectangle rather than by the
## sheet's mouse_entered/mouse_exited signals.
##
## Those signals cannot answer this question. Godot fires mouse_exited on a
## container the moment the pointer moves onto a child that stops mouse input,
## and fires no matching mouse_entered back on the container -- so hovering an
## item, dragging the scrollbar or clicking into the search field all reported
## "the pointer left the bag" and closed it. Measured: moving from the sheet's
## own padding onto its first item button produced exits=1, enters=0, and the
## sheet shut.
func _pointer_over_bag() -> bool:
	if _build_bar == null or not _build_bar.visible:
		return false
	var pointer := (
		_pointer_position if _pointer_seen else get_viewport().get_mouse_position()
	)
	if _build_bar.get_global_rect().grow(BAG_HOVER_SLACK).has_point(pointer):
		return true
	# The strip's rect counts even while it is hidden. It is hidden precisely
	# BECAUSE the bag is open, and the pointer that opened it is still sitting
	# there -- below the sheet's resting rect while the sheet is still rising
	# into place, which read as "outside" and shut it again immediately.
	return (
		_bag_hover_strip != null
		and _bag_hover_strip.get_global_rect().grow(BAG_HOVER_SLACK).has_point(pointer)
	)


func _update_bag_hover_close() -> void:
	if not _build_library_expanded:
		return
	# The sheet's rect is meaningless mid-slide: it is still below its resting
	# place, so any pointer reads as outside it.
	if _build_library_tween != null and _build_library_tween.is_valid():
		_cancel_bag_hover_close()
		return
	# Typing is not idling: a search field with focus keeps the bag open even
	# though the pointer may be nowhere near it.
	if (
		_build_library_pinned
		or _build_drop_active
		or (_build_search != null and _build_search.has_focus())
		or InputDeviceService.shared().is_controller()
	):
		_cancel_bag_hover_close()
		return
	if _pointer_over_bag():
		_cancel_bag_hover_close()
	else:
		_queue_bag_hover_close()


func _cancel_bag_hover_close() -> void:
	_build_mouse_exit_pending = false
	if _bag_hover_close_timer != null:
		_bag_hover_close_timer.stop()


func _queue_bag_hover_close() -> void:
	if not _build_library_expanded or _build_library_pinned:
		return
	# Already counting down: restarting every frame would hold the timer at
	# full and it would never fire.
	if _build_mouse_exit_pending:
		return
	_build_mouse_exit_pending = true
	if _bag_hover_close_timer != null:
		_bag_hover_close_timer.start(BAG_HOVER_CLOSE_GRACE)


func _collapse_build_library_after_mouse_exit() -> void:
	if not _build_mouse_exit_pending or _build_library_pinned:
		_build_mouse_exit_pending = false
		return
	_build_mouse_exit_pending = false
	set_build_library_expanded(false)


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
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		if not placement.held.is_empty():
			placement.cancel_click()
		set_build_library_expanded(true)
		_build_bar.accept_event()


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		_pointer_position = motion.global_position
		_pointer_seen = true


func _process(_delta: float) -> void:
	_update_bag_hover_close()
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
	var over_library := (
		_build_bar != null
		and _build_bar.visible
		and _build_bar.get_global_rect().has_point(pointer)
	)
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
	_store_bubble.scale = Vector2.ONE
	if animate:
		_store_bubble_tween = create_tween()
		_store_bubble_tween.set_trans(Tween.TRANS_QUAD)
		_store_bubble_tween.set_ease(Tween.EASE_OUT)
		_store_bubble_tween.tween_property(
			_store_bubble,
			"modulate:a",
			1.0,
			kit.motion_duration(kit.tokens.open_duration)
		)
		_store_bubble_tween.chain().tween_callback(
			_start_store_bubble_idle
		)


func _start_store_bubble_idle() -> void:
	if _store_bubble == null or not _store_bubble.visible:
		return
	_store_bubble.scale = Vector2.ONE


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

func _on_health_changed(current: int, maximum: int) -> void:
	for child in _health_box.get_children():
		child.queue_free()
	_health_box.visible = current < maximum or _enemies_near()
	for i in maximum:
		var heart := kit.label("♥", 22)
		heart.add_theme_color_override(
			"font_color",
			kit.palette.color("ui_health")
			if i < current
			else kit.palette.color("ui_health_empty")
		)
		_health_box.add_child(heart)


func _enemies_near() -> bool:
	return get_tree().get_node_count_in_group("enemies") > 0


func _on_build_mode(active: bool) -> void:
	if active:
		_refresh_build_strip()
		_build_library_expanded = false
		set_build_library_expanded(true, false)
		call_deferred("_position_context_above_build_library")
		if InputDeviceService.shared().is_controller() and placement.held.is_empty():
			focus_build_library()
	else:
		set_build_library_expanded(false, false)
		if _build_bar != null:
			_build_bar.hide_search()
		_build_expand_button.visible = false
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
	_hint_panel.visible = text != "" and _hint_label.visible
	_position_context_above_build_library.call_deferred()


func set_tutorial_enabled(enabled: bool) -> void:
	_hint_label.visible = enabled
	_hint_panel.visible = enabled and _hint_label.text != ""


func set_hover_tooltip(display_name: String, collection_name: String) -> void:
	if _hover_tooltip == null:
		return
	_hover_name_label.text = display_name
	_hover_collection_label.text = collection_name
	_hover_tooltip.visible = display_name != ""


## Keeps unboxed world-space guidance legible across the pale day and dark
## rain backdrops without adding a large UI panel over the diorama.
func apply_weather_contrast(rain_enabled: bool) -> void:
	for entry in [[_hint_label, kit.text_color()], [_prompt_label, kit.text_color()]]:
		var label := entry[0] as Label
		label.add_theme_color_override("font_color", entry[1])
		label.add_theme_color_override(
			"font_outline_color",
			kit.palette.color("ui_rain_outline")
		)
		label.add_theme_constant_override("outline_size", 3 if rain_enabled else 0)


func toast(_message: String, _tone := "common") -> void:
	# The top-right notification stack was intentionally retired. Gameplay
	# state remains visible through the world, collection reveal, and bag UI.
	pass


## Derives the current opening hint straight from discovery state.
func update_tutorial() -> void:
	match core.onboarding.stage:
		OnboardingState.PLACE_TREE:
			set_hint("Place your first tree. (%s)" % InputDeviceService.shared().format_action(&"build_confirm", "place"))
			return
		OnboardingState.WAIT_TREE:
			set_hint("Turn the world while your tree grows.")
			return
		OnboardingState.HARVEST_TREE:
			set_hint("Harvest the tree — three satisfying hits. (%s)" % InputDeviceService.shared().format_action(&"build_confirm", "hit"))
			return
		OnboardingState.OPEN_FOREST_BOX:
			set_hint(
				"Spend your Forest Tokens on a Forest Box in the Pouch. (%s)"
				% InputDeviceService.shared().format_action(
					&"panel_inventory", "open pouch"
				)
			)
			return
		OnboardingState.PLACE_FOREST_REWARD:
			set_hint(
				"Add the forest discovery to your world. (%s)"
				% InputDeviceService.shared().format_action(
					&"build_confirm", "place"
				)
			)
			return
		OnboardingState.WAIT_VISITOR:
			set_hint("")
			return
		OnboardingState.PLACE_VISITOR_REWARD:
			set_hint("Place the visitor's gift — a first step beyond the forest.")
			return
	# The frontier dots and direct manipulation are self-explanatory in free
	# play. Keep the guidance card reserved for active onboarding steps.
	set_hint("")


func _is_structure_placed(structure_id: String) -> bool:
	for slot: Dictionary in core.grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			if structure.structure_id == structure_id:
				return true
	return false


func focus_build_library() -> void:
	if not InputDeviceService.shared().is_controller():
		return
	if not _build_library_expanded:
		if _build_expand_button != null and _build_expand_button.visible:
			_build_expand_button.grab_focus()
		return
	var preferred: Control
	for item_button in _build_item_buttons:
		var button := item_button as BaseButton
		if button != null and not button.disabled:
			preferred = button
			break
	if preferred == null:
		preferred = _build_close_button
	InputDeviceService.shared().focus_first(_build_bar, preferred)


func release_build_focus() -> void:
	if _build_bar != null:
		InputDeviceService.shared().release_focus_in(_build_bar)
	if _build_expand_button != null and _build_expand_button.has_focus():
		_build_expand_button.release_focus()


func focus_default() -> void:
	if build_library_expanded() or build_library_collapsed():
		focus_build_library()


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
	_refresh_prompt()
	update_tutorial()
	if placement.active:
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
