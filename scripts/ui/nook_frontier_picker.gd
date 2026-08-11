class_name NookFrontierPicker
extends CanvasLayer
## A tiny world-anchored choice panel for frontier glows. Mouse players reveal
## it by hovering a dot; controller players reveal it with the deterministic
## build cursor and enter it with build_confirm.

signal generation_requested(coord: Vector2i, preferences: Dictionary)
signal panel_toggled(open: bool)

const NO_COORD := Vector2i(2147483647, 2147483647)
const MOUSE_LEAVE_GRACE := 0.24
const PANEL_GAP := 18.0
const VIEWPORT_MARGIN := 12.0
const SHAPES: Array[Dictionary] = [
	{
		"label": "Natural",
		"id": "natural",
		"tooltip": "Original varied terrain, shaped by the world.",
	},
	{"label": "Flat", "id": "flat", "tooltip": "Quiet, level ground."},
	{"label": "Rolling", "id": "rolling", "tooltip": "Soft hills and low terraces."},
	{"label": "Peaks", "id": "mountains", "tooltip": "High ridges and steep terraces."},
]
const BIOMES: Array[Dictionary] = [
	{"label": "Natural", "id": ""},
	{"label": "Forest", "id": "nook_biome_forest"},
	{"label": "Meadow", "id": "nook_biome_meadow"},
	{"label": "Stone", "id": "nook_biome_stonefell"},
	{"label": "Dunes", "id": "nook_biome_dunes"},
	{"label": "Tundra", "id": "nook_biome_tundra"},
]

var core: GameCore
var kit: UiKit
var markers: NookFrontierMarkers
var placement: PlacementController

var _input_service: InputDeviceService
var _root: Control
var _panel: PanelContainer
var _shape_buttons: Array[Button] = []
var _biome_button: Button
var _grow_button: Button
var _target_coord := NO_COORD
var _terrain_shape := "natural"
var _biome_index := 0
var _leave_time := 0.0
var _interaction_enabled := true
var _suppressed_controller_coord := NO_COORD


func setup(
	game_core: GameCore,
	ui_kit: UiKit,
	frontier_markers: NookFrontierMarkers,
	placement_controller: PlacementController
) -> void:
	core = game_core
	kit = ui_kit
	markers = frontier_markers
	placement = placement_controller
	_input_service = InputDeviceService.shared()
	_build_panel()


func is_open() -> bool:
	return _panel != null and _panel.visible


func has_focus() -> bool:
	if not is_open() or get_viewport() == null:
		return false
	var focused := get_viewport().gui_get_focus_owner()
	return focused != null and (
		focused == _panel or _panel.is_ancestor_of(focused)
	)


func blocks_world_pointer(screen_position: Vector2) -> bool:
	return is_open() and _panel.get_global_rect().has_point(screen_position)


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	if not enabled:
		_hide_panel()


func show_for_screen(screen_position: Vector2) -> bool:
	if not _interaction_enabled or markers == null:
		return false
	var marker := markers.marker_at_screen(screen_position)
	if marker.is_empty():
		return false
	_show_for_coord(marker.get("nook", NO_COORD))
	_leave_time = MOUSE_LEAVE_GRACE
	return true


func focus_for_cell(cell: Vector2i) -> bool:
	if not _interaction_enabled or markers == null:
		return false
	var marker := markers.marker_at_cell(cell)
	if marker.is_empty():
		return false
	var coord: Vector2i = marker.get("nook", NO_COORD)
	_suppressed_controller_coord = NO_COORD
	_show_for_coord(coord)
	var preferred := _selected_shape_button()
	_input_service.focus_first(_panel, preferred)
	return true


func close_controller_focus() -> void:
	if _target_coord != NO_COORD:
		_suppressed_controller_coord = _target_coord
	_input_service.release_focus_in(_panel)
	_hide_panel()


func _process(delta: float) -> void:
	if not _interaction_enabled or markers == null or placement == null:
		return
	if has_focus():
		_position_panel()
		return
	if _input_service.is_controller() and placement.controller_cursor_active():
		var controller_marker := markers.marker_at_cell(
			placement.controller_cursor_cell()
		)
		if controller_marker.is_empty():
			_suppressed_controller_coord = NO_COORD
			_hide_panel()
			return
		var controller_coord: Vector2i = controller_marker.get("nook", NO_COORD)
		if controller_coord == _suppressed_controller_coord:
			_hide_panel()
			return
		_suppressed_controller_coord = NO_COORD
		_show_for_coord(controller_coord)
		_position_panel()
		return

	_suppressed_controller_coord = NO_COORD
	var mouse_position := get_viewport().get_mouse_position()
	var marker := markers.marker_at_screen(mouse_position)
	if not marker.is_empty():
		_show_for_coord(marker.get("nook", NO_COORD))
		_leave_time = MOUSE_LEAVE_GRACE
	elif blocks_world_pointer(mouse_position):
		_leave_time = MOUSE_LEAVE_GRACE
	elif is_open():
		_leave_time -= delta
		if _leave_time <= 0.0:
			_hide_panel()
	_position_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not has_focus() or not event.is_action_pressed("cancel"):
		return
	close_controller_focus()
	get_viewport().set_input_as_handled()
	panel_toggled.emit(false)


func _build_panel() -> void:
	_root = Control.new()
	_root.name = "FrontierPickerRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = kit.theme
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.name = "FrontierPicker"
	_panel.custom_minimum_size = Vector2(356.0, 130.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := kit.panel_style(false, 16)
	style.set_content_margin_all(11)
	style.shadow_color = kit.palette.color("ui_shadow")
	style.shadow_size = 10
	style.shadow_offset = Vector2(0.0, 5.0)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.visible = false
	_root.add_child(_panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	_panel.add_child(content)
	var title := kit.label("NEW LAND", 12, false, true)
	title.add_theme_color_override(
		"font_color", kit.palette.color("ui_text_muted")
	)
	content.add_child(title)

	var shape_row := HBoxContainer.new()
	shape_row.add_theme_constant_override("separation", 6)
	content.add_child(shape_row)
	var group := ButtonGroup.new()
	for shape: Dictionary in SHAPES:
		var button := kit.choice_button(
			String(shape["label"]), shape["id"] == _terrain_shape
		)
		button.name = "Shape%s" % String(shape["label"])
		button.button_group = group
		button.custom_minimum_size = Vector2(78.0, 36.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 14)
		button.tooltip_text = String(shape["tooltip"])
		button.pressed.connect(_select_shape.bind(String(shape["id"])))
		shape_row.add_child(button)
		_shape_buttons.append(button)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 7)
	content.add_child(action_row)
	_biome_button = kit.button("")
	_biome_button.name = "Biome"
	_biome_button.custom_minimum_size = Vector2(190.0, 38.0)
	_biome_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_biome_button.add_theme_font_size_override("font_size", 14)
	_biome_button.tooltip_text = "Choose a biome. Natural follows nearby land."
	_biome_button.pressed.connect(_cycle_biome)
	action_row.add_child(_biome_button)
	_grow_button = kit.button("Grow", true)
	_grow_button.name = "Grow"
	_grow_button.custom_minimum_size = Vector2(83.0, 38.0)
	_grow_button.add_theme_font_size_override("font_size", 14)
	_grow_button.tooltip_text = "Unfold this Nook."
	_grow_button.pressed.connect(_request_generation)
	action_row.add_child(_grow_button)
	_update_biome_label()
	_wire_focus_neighbors()


func _wire_focus_neighbors() -> void:
	for index in _shape_buttons.size():
		var button := _shape_buttons[index]
		button.focus_neighbor_left = button.get_path_to(
			_shape_buttons[maxi(0, index - 1)]
		)
		button.focus_neighbor_right = button.get_path_to(
			_shape_buttons[mini(_shape_buttons.size() - 1, index + 1)]
		)
		button.focus_neighbor_bottom = button.get_path_to(_biome_button)
	_biome_button.focus_neighbor_top = _biome_button.get_path_to(
		_selected_shape_button()
	)
	_biome_button.focus_neighbor_right = _biome_button.get_path_to(_grow_button)
	_grow_button.focus_neighbor_left = _grow_button.get_path_to(_biome_button)
	_grow_button.focus_neighbor_top = _grow_button.get_path_to(
		_shape_buttons[_shape_buttons.size() - 1]
	)


func _show_for_coord(coord: Vector2i) -> void:
	if coord == NO_COORD:
		return
	var was_open := is_open()
	if coord != _target_coord:
		_target_coord = coord
		_reset_choices()
	_panel.visible = true
	_position_panel()
	if not was_open:
		panel_toggled.emit(true)


func _hide_panel() -> void:
	if not is_open():
		return
	_input_service.release_focus_in(_panel)
	_panel.visible = false
	_target_coord = NO_COORD
	panel_toggled.emit(false)


func _position_panel() -> void:
	if not is_open() or _target_coord == NO_COORD or markers == null:
		return
	var marker_position := markers.marker_screen_position(_target_coord)
	if marker_position.x < 0.0:
		return
	var panel_size := _panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		panel_size = _panel.custom_minimum_size
	var viewport_size := get_viewport().get_visible_rect().size
	var position := marker_position - Vector2(
		panel_size.x * 0.5, panel_size.y + PANEL_GAP
	)
	position.x = clampf(
		position.x,
		VIEWPORT_MARGIN,
		maxf(VIEWPORT_MARGIN, viewport_size.x - panel_size.x - VIEWPORT_MARGIN)
	)
	position.y = clampf(
		position.y,
		VIEWPORT_MARGIN,
		maxf(VIEWPORT_MARGIN, viewport_size.y - panel_size.y - VIEWPORT_MARGIN)
	)
	_panel.position = position


func _reset_choices() -> void:
	_terrain_shape = "natural"
	_biome_index = 0
	for index in _shape_buttons.size():
		_shape_buttons[index].set_pressed_no_signal(index == 0)
	_update_biome_label()


func _select_shape(shape_id: String) -> void:
	_terrain_shape = NookGenerator.normalize_terrain_shape(shape_id)
	if _biome_button != null:
		_biome_button.focus_neighbor_top = _biome_button.get_path_to(
			_selected_shape_button()
		)


func _cycle_biome() -> void:
	if BIOMES.is_empty():
		return
	_biome_index = (_biome_index + 1) % BIOMES.size()
	_update_biome_label()


func _update_biome_label() -> void:
	if _biome_button == null or BIOMES.is_empty():
		return
	_biome_button.text = "Biome · %s  ›" % String(
		BIOMES[_biome_index]["label"]
	)


func _selected_shape_button() -> Button:
	for index in SHAPES.size():
		if String(SHAPES[index]["id"]) == _terrain_shape:
			return _shape_buttons[index]
	return _shape_buttons[0]


func _request_generation() -> void:
	if _target_coord == NO_COORD:
		return
	var coord := _target_coord
	var biome_id := String(BIOMES[_biome_index]["id"])
	var preferences := {"terrain_shape": _terrain_shape}
	if biome_id != "":
		preferences["biome"] = biome_id
	_hide_panel()
	generation_requested.emit(coord, preferences)
