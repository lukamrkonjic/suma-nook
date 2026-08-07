class_name Hud
extends CanvasLayer
## Persistent interface: health, context prompts, toasts, the Build Bag, and
## tutorial hints. Discovery presentation and modal panels live elsewhere.

signal catch_basket_requested
signal spirit_pouch_requested
signal token_pouch_requested
signal build_piece_selected(kind: String, id: String)
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
const PlayerPlacementDockScript := preload(
	"res://scripts/ui/player_placement_dock.gd"
)

var core: GameCore
var kit: UiKit
var placement: PlacementController

var _prompt_label: Label
var _hint_label: Label
var _hint_panel: PanelContainer
var _health_box: HBoxContainer
var _token_pouch_button: Button
var _build_bar: PanelContainer
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
var _selected_build_category := ""
var _selected_build_entry: Dictionary = {}
var _build_library_expanded := false
var _build_library_pinned := false
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
	_token_pouch_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_token_pouch_button.position = Vector2(16, 16)
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
		kit.palette.color("ui_collection_text")
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
	_hint_panel.visible = false
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_context_column.add_child(_hint_panel)
	_hint_label = kit.label("", 17, true)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size.x = 400
	_hint_label.add_theme_color_override("font_color", kit.palette.color("ui_hint_dark"))
	_hint_panel.add_child(_hint_label)
	_prompt_label = kit.label("", 20)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context_column.add_child(_prompt_label)
	_position_context_above_build_library.call_deferred()

	# Build Bag — a quiet chevron at rest, expanding upward while hovered.
	# The expanded shelf can be pinned when the player wants to keep browsing.
	_build_bar = PanelContainer.new()
	_build_bar.name = "BuildLibrary"
	_build_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build_bar.position.y = -18
	_build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_build_bar.custom_minimum_size = Vector2(54, 0)
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
	_build_compact_row.custom_minimum_size = Vector2(54, 42)
	_build_compact_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_build_bar_column.add_child(_build_compact_row)
	_build_expand_button = Button.new()
	_build_expand_button.name = "BuildExpandLibrary"
	_build_expand_button.custom_minimum_size = Vector2(50, 38)
	_build_expand_button.icon = load(BUILD_ICON_DIRECTORY + "chevron_up.svg")
	_build_expand_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_expand_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_expand_button.expand_icon = false
	_build_expand_button.tooltip_text = "Build Bag"
	_build_expand_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_build_expand_button.focus_mode = Control.FOCUS_ALL
	var bag_normal := StyleBoxFlat.new()
	bag_normal.bg_color = kit.palette.color("ui_bag_surface")
	bag_normal.border_color = kit.palette.color("ui_bag_border")
	bag_normal.set_border_width_all(1)
	bag_normal.set_corner_radius_all(19)
	bag_normal.shadow_color = kit.palette.color("ui_bag_shadow")
	bag_normal.shadow_size = 6
	bag_normal.shadow_offset = Vector2(0, 3)
	var bag_hover := bag_normal.duplicate()
	bag_hover.bg_color = kit.palette.color("ui_white")
	bag_hover.border_color = kit.palette.color("ui_bag_hover")
	bag_hover.shadow_size = 9
	bag_hover.shadow_offset = Vector2(0, 4)
	var bag_pressed := bag_hover.duplicate()
	bag_pressed.bg_color = kit.palette.color("ui_bag_pressed")
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

	# A clipped plain Control does not inherit its children's minimum height,
	# allowing the shelf to animate rather than pop between layouts.
	_build_expanded_clip = Control.new()
	_build_expanded_clip.name = "BuildLibraryExpansion"
	_build_expanded_clip.clip_contents = true
	_build_expanded_clip.custom_minimum_size.y = 410
	_build_bar_column.add_child(_build_expanded_clip)
	_build_expanded_content = VBoxContainer.new()
	_build_expanded_content.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_build_expanded_content.offset_bottom = 404
	_build_expanded_content.add_theme_constant_override("separation", 8)
	_build_expanded_clip.add_child(_build_expanded_content)

	var build_header := HBoxContainer.new()
	build_header.name = "BuildLibraryHeader"
	build_header.add_theme_constant_override("separation", 7)
	_build_expanded_content.add_child(build_header)

	_build_search = LineEdit.new()
	_build_search.name = "BuildLibrarySearch"
	_build_search.placeholder_text = "Search your Build Bag..."
	_build_search.clear_button_enabled = true
	_build_search.custom_minimum_size.y = 42
	_build_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_search.tooltip_text = "Find owned tiles, furniture, structures, or deeds by name"
	_build_search.add_theme_font_override("font", kit.font)
	_build_search.add_theme_font_size_override("font_size", 16)
	var search_style := StyleBoxFlat.new()
	search_style.bg_color = kit.palette.color("ui_search_surface")
	search_style.border_color = kit.palette.color("ui_search_border")
	search_style.set_border_width_all(1)
	search_style.set_corner_radius_all(12)
	search_style.content_margin_left = 15
	search_style.content_margin_right = 12
	_build_search.add_theme_stylebox_override("normal", search_style)
	_build_search.add_theme_stylebox_override("read_only", search_style)
	var search_focus := search_style.duplicate() as StyleBoxFlat
	search_focus.border_color = kit.palette.color("ui_accent").lightened(0.15)
	search_focus.set_border_width_all(2)
	_build_search.add_theme_stylebox_override("focus", search_focus)
	_build_search.text_changed.connect(_on_build_search_changed)
	build_header.add_child(_build_search)

	_build_pin_button = kit.library_arrow_button("")
	_build_pin_button.name = "BuildLibraryPin"
	_build_pin_button.custom_minimum_size = Vector2(42, 42)
	_build_pin_button.icon = load(BUILD_ICON_DIRECTORY + "pin.svg")
	_build_pin_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_pin_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_pin_button.toggle_mode = true
	_build_pin_button.tooltip_text = "Keep Build Bag open"
	_build_pin_button.toggled.connect(_on_build_library_pin_toggled)
	build_header.add_child(_build_pin_button)

	_build_close_button = kit.library_arrow_button("")
	_build_close_button.name = "BuildLibraryClose"
	_build_close_button.custom_minimum_size = Vector2(42, 42)
	_build_close_button.icon = load(BUILD_ICON_DIRECTORY + "chevron_down.svg")
	_build_close_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_close_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_close_button.tooltip_text = "Close Build Bag"
	_build_close_button.pressed.connect(_close_build_library)
	build_header.add_child(_build_close_button)

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
	_build_hint_label.add_theme_color_override(
		"font_color",
		kit.palette.color("ui_hint_medium")
	)
	_build_expanded_content.add_child(_build_hint_label)

	_build_drop_overlay = PanelContainer.new()
	_build_drop_overlay.name = "BuildLibraryStoreDrop"
	_build_drop_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_drop_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_build_drop_overlay.visible = false
	_build_drop_overlay.gui_input.connect(_on_build_drop_overlay_input)
	var drop_style := StyleBoxFlat.new()
	drop_style.bg_color = kit.palette.color("ui_drop_surface")
	drop_style.border_color = kit.palette.color("ui_drop_border")
	drop_style.set_border_width_all(4)
	drop_style.set_corner_radius_all(16)
	drop_style.shadow_color = kit.palette.color("ui_drop_shadow")
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
	store_normal.bg_color = kit.palette.color("ui_store_surface")
	store_normal.border_color = kit.palette.color("ui_store_border")
	store_normal.set_border_width_all(2)
	store_normal.set_corner_radius_all(24)
	store_normal.content_margin_left = 22
	store_normal.content_margin_right = 22
	store_normal.content_margin_top = 13
	store_normal.content_margin_bottom = 13
	store_normal.shadow_color = kit.palette.color("ui_store_shadow")
	store_normal.shadow_size = 10
	store_normal.shadow_offset = Vector2(0, 5)
	var store_hover := store_normal.duplicate()
	store_hover.bg_color = kit.palette.color("ui_white")
	store_hover.border_color = kit.palette.color("ui_store_hover")
	store_hover.shadow_size = 13
	var store_pressed := store_hover.duplicate()
	store_pressed.bg_color = kit.palette.color("ui_store_pressed")
	store_pressed.shadow_size = 5
	store_pressed.shadow_offset = Vector2(0, 2)
	_store_bubble.add_theme_stylebox_override("normal", store_normal)
	_store_bubble.add_theme_stylebox_override("hover", store_hover)
	_store_bubble.add_theme_stylebox_override("pressed", store_pressed)
	_store_bubble.add_theme_stylebox_override("focus", store_hover)
	_store_bubble.add_theme_color_override(
		"font_color",
		kit.palette.color("ui_store_text")
	)
	_store_bubble.add_theme_color_override(
		"font_hover_color", kit.palette.color("ui_store_text_active")
	)
	_store_bubble.add_theme_color_override(
		"font_pressed_color", kit.palette.color("ui_store_text_active")
	)
	_store_bubble.add_theme_color_override(
		"font_focus_color", kit.palette.color("ui_store_text_active")
	)
	_store_bubble.visible = false
	_store_bubble.pressed.connect(_store_held_from_bubble)
	_store_bubble.gui_input.connect(_on_store_bubble_input)
	root.add_child(_store_bubble)

	# The keeper is a draggable world tool, mirroring the compact person dock
	# used by map applications. It stays available after placement so one click
	# can recall the active keeper through their portal animation.
	_player_dock_panel = PanelContainer.new()
	_player_dock_panel.name = "PlayerPlacementDockPanel"
	_player_dock_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_player_dock_panel.offset_left = -142
	_player_dock_panel.offset_top = -142
	_player_dock_panel.offset_right = -18
	_player_dock_panel.offset_bottom = -18
	var player_dock_style := kit.cloud_panel_style(22)
	player_dock_style.content_margin_left = 14
	player_dock_style.content_margin_right = 14
	player_dock_style.content_margin_top = 10
	player_dock_style.content_margin_bottom = 9
	player_dock_style.shadow_size = 11
	_player_dock_panel.add_theme_stylebox_override("panel", player_dock_style)
	root.add_child(_player_dock_panel)
	var player_dock_column := VBoxContainer.new()
	player_dock_column.alignment = BoxContainer.ALIGNMENT_CENTER
	player_dock_column.add_theme_constant_override("separation", 0)
	_player_dock_panel.add_child(player_dock_column)
	_player_dock = PlayerPlacementDockScript.new()
	_player_dock.name = "PlayerPlacementDock"
	_player_dock.texture_normal = load(
		"res://assets/ui/icons/player_dock.svg"
	)
	_player_dock.drag_started.connect(_on_player_dock_drag_started)
	_player_dock.drag_moved.connect(_on_player_dock_drag_moved)
	_player_dock.drag_released.connect(_on_player_dock_drag_released)
	_player_dock.activated.connect(func(): player_dock_activated.emit())
	player_dock_column.add_child(_player_dock)
	_player_dock_label = kit.label("Drag keeper", 13, false, true)
	_player_dock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_dock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_dock_column.add_child(_player_dock_label)

	_player_drag_icon = TextureRect.new()
	_player_drag_icon.name = "PlayerDockDragIcon"
	_player_drag_icon.texture = _player_dock.texture_normal
	_player_drag_icon.custom_minimum_size = Vector2(48, 56)
	_player_drag_icon.size = Vector2(48, 56)
	_player_drag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_player_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_drag_icon.z_index = 100
	_player_drag_icon.visible = false
	root.add_child(_player_drag_icon)

	_build_category_group = ButtonGroup.new()
	_thumbnail_renderer = BuildThumbnailRendererScript.new()
	_thumbnail_renderer.name = "BuildThumbnailRenderer"
	add_child(_thumbnail_renderer)
	_thumbnail_renderer.setup(core, placement.assets)
	get_viewport().size_changed.connect(_resize_build_library)
	_resize_build_library()
	set_player_deployed(false)


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
	_thumbnail_renderer.discard_pending()
	for child in _build_strip.get_children():
		_build_strip.remove_child(child)
		child.queue_free()
	_build_item_scroll.scroll_vertical = 0

	if _selected_build_category == "":
		var empty_label := kit.label(
			(
				"No owned pieces match “%s”. Clear the search to see everything."
				% _build_search.text.strip_edges()
				if not _build_search_query().is_empty()
				else "Your Build Bag is empty — fish from an exposed edge to find a piece."
			),
			15
		)
		empty_label.add_theme_color_override(
			"font_color",
			kit.palette.color("ui_empty_text")
		)
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
		_add_harvest_badge(item_button, String(entry.get("harvest_icon", "")))
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


func _add_harvest_badge(button: Button, icon_id: String) -> void:
	var filename := String(HARVEST_ICON_FILES.get(icon_id, ""))
	if filename == "":
		return
	var badge := PanelContainer.new()
	badge.name = "HarvestBadge_%s" % icon_id
	badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	badge.position = Vector2(9, 9)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = kit.palette.color("ui_card").lightened(0.08)
	style.set_corner_radius_all(11)
	style.set_content_margin_all(5)
	style.shadow_color = kit.palette.color("ui_badge_shadow")
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
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
	var bottom_gap := (
		_build_bar.size.y + 28.0
		if _build_bar.visible
		else 86.0
	)
	var viewport_size := get_viewport().get_visible_rect().size
	var content_size := _context_column.get_combined_minimum_size()
	_context_column.size = content_size
	_context_column.position = Vector2(
		(viewport_size.x - content_size.x) * 0.5,
		viewport_size.y - bottom_gap - content_size.y
	)


func set_build_library_expanded(expanded: bool, animate := true) -> void:
	if _build_expanded_clip == null:
		return
	if not expanded and _build_library_pinned:
		_build_library_pinned = false
		if _build_pin_button != null:
			_build_pin_button.set_pressed_no_signal(false)
			_build_pin_button.tooltip_text = "Keep Build Bag open"
	var target_height := 410.0 if expanded else 0.0
	var target_width := _build_library_expanded_width() if expanded else 54.0
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
	if _build_expand_button == null:
		return
	if _build_bag_idle_tween != null and _build_bag_idle_tween.is_valid():
		_build_bag_idle_tween.kill()
	_build_expand_button.scale = Vector2.ONE


func _animate_build_bag_open() -> void:
	if (
		_build_library_expanded
		or _build_bag_open_pending
		or not _build_hover_expand_armed
	):
		return
	_build_bag_open_pending = true
	set_build_library_expanded(true)


func request_build_library_open() -> void:
	if not placement.active:
		return
	set_build_library_expanded(true)


func build_library_collapsed() -> bool:
	return _build_bar != null and _build_bar.visible and not _build_library_expanded


func blocks_world_pointer(screen_position: Vector2) -> bool:
	# Geometry is authoritative here. Relying only on gui_get_hovered_control()
	# leaves empty Container space transparent to world picking on some layouts.
	for candidate in [
		_build_bar,
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
	_build_library_pinned = pinned
	_build_mouse_exit_pending = false
	_build_pin_button.tooltip_text = (
		"Let Build Bag close when the pointer leaves"
		if pinned
		else "Keep Build Bag open"
	)


func _close_build_library() -> void:
	_build_library_pinned = false
	if _build_pin_button != null:
		_build_pin_button.set_pressed_no_signal(false)
	set_build_library_expanded(false)


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
	if _build_library_pinned:
		_build_mouse_exit_pending = false
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
		or _build_library_pinned
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
	_build_bar.visible = active
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
		if _build_search != null and not _build_search.text.is_empty():
			_build_search.clear()
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
	var hint_color := (
		kit.palette.color("ui_hint_rain")
		if rain_enabled
		else kit.palette.color("ui_hint_dark")
	)
	var prompt_color := (
		kit.palette.color("ui_prompt_rain") if rain_enabled else kit.text_color()
	)
	for entry in [[_hint_label, hint_color], [_prompt_label, prompt_color]]:
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
	if not _player_deployed and not core.onboarding.is_active():
		set_hint("Drag your keeper from the lower-right onto a clear tile.")
		return
	if core.fishing.basket.is_full():
		set_hint("The Catch Basket is full — place or return a haul to fish again.")
	elif core.progression.actions_done("fishing") == 0:
		set_hint(
			"Fish from an exposed edge. What you build nearby shapes the catch. (%s)"
			% InputDeviceService.shared().format_action(&"interact", "when close")
		)
	elif core.grid.placed_tile_count() == 0 and core.stock.total_tiles() > 0:
		set_hint("Place your new land in any empty grid space from the Build Bag below.")
	elif core.grid.placed_tile_count() > 0 and core.progression.actions_done("woodcutting") == 0:
		if _has_placed_tree():
			set_hint("Tend your placed tree — it will rest, then regrow.")
		elif _stored_tree_count() > 0:
			set_hint("Place your tree from the Build Library, then tend it.")
		else:
			set_hint("")
	else:
		set_hint("")


func _is_structure_placed(structure_id: String) -> bool:
	for slot: Dictionary in core.grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			if structure.structure_id == structure_id:
				return true
	return false


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
	_build_hint_label.text = (
		"%s  ·  %s  ·  %s  ·  %s"
		% [
			InputDeviceService.shared().format_action(&"ui_accept", "choose"),
			InputDeviceService.shared().format_action(&"build_mode", "browse world"),
			InputDeviceService.shared().format_action(&"rotate_piece", "rotate"),
			InputDeviceService.shared().format_action(&"cancel", "back"),
		]
		if InputDeviceService.shared().is_controller()
		else "%s  ·  wheel scrolls  ·  Right Click rotates  ·  drag moved pieces here to store"
		% [
			InputDeviceService.shared().format_action(&"interact", "choose"),
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
