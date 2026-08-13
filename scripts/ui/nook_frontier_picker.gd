class_name NookFrontierPicker
extends CanvasLayer
## A compact world-anchored requirements card for frontier glows. Hovering a
## dot explains the exact gathering goal; controller players see the same card
## at their deterministic world cursor. There are no terrain-generation choices.

signal frontier_activated(coord: Vector2i)
signal panel_toggled(open: bool)

const NO_COORD := Vector2i(2147483647, 2147483647)
const MOUSE_LEAVE_GRACE := 0.24
const PANEL_GAP := 18.0
const VIEWPORT_MARGIN := 12.0

var core: GameCore
var kit: UiKit
var markers: NookFrontierMarkers
var placement: PlacementController

var _input_service: InputDeviceService
var _root: Control
var _panel: PanelContainer
var _title_label: Label
var _state_label: Label
var _requirements_row: HBoxContainer
var _action_button: Button
var _target_coord := NO_COORD
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
	core.projects.project_progressed.connect(func(project: Dictionary, _slot: Dictionary):
		_refresh_if_current(project)
	)
	core.projects.project_completed.connect(func(project: Dictionary):
		_refresh_if_current(project)
	)
	core.projects.tracked_project_changed.connect(func(_project: Dictionary):
		_refresh_content()
	)
	core.frontiers.frontier_became_ready.connect(
		func(_frontier: Dictionary, project: Dictionary):
			_refresh_if_current(project)
	)


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
	_suppressed_controller_coord = NO_COORD
	_show_for_coord(marker.get("nook", NO_COORD))
	if _input_service != null:
		_input_service.focus_first(_panel, _action_button)
	return true


func close_controller_focus() -> void:
	if _target_coord != NO_COORD:
		_suppressed_controller_coord = _target_coord
	if _input_service != null:
		_input_service.release_focus_in(_panel)
	_hide_panel()


func refresh() -> void:
	_refresh_content()


func _process(delta: float) -> void:
	if not _interaction_enabled or markers == null or placement == null:
		return
	if has_focus():
		_position_panel()
		return
	if (
		_input_service != null
		and _input_service.is_controller()
		and placement.controller_cursor_active()
	):
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


func _build_panel() -> void:
	_root = Control.new()
	_root.name = "FrontierRequirementsRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = kit.theme
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.name = "FrontierRequirements"
	_panel.custom_minimum_size = Vector2(314.0, 150.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := kit.panel_style(false, 16)
	style.set_content_margin_all(11)
	style.border_width_top = 3
	style.border_color = kit.collection_accent("land")
	_panel.add_theme_stylebox_override("panel", style)
	_panel.visible = false
	_root.add_child(_panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	_panel.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	content.add_child(header)
	_title_label = kit.utility_label(
		"FRONTIER", 11, kit.collection_accent("land")
	)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_color_override(
		"font_color", kit.text_color()
	)
	header.add_child(_title_label)
	_state_label = kit.utility_label("LOCKED", 10)
	header.add_child(_state_label)

	_requirements_row = HBoxContainer.new()
	_requirements_row.name = "Requirements"
	_requirements_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_requirements_row.add_theme_constant_override("separation", 7)
	content.add_child(_requirements_row)

	_action_button = kit.button("Track requirements", true)
	_action_button.name = "FrontierAction"
	_action_button.custom_minimum_size = Vector2(0.0, 38.0)
	_action_button.add_theme_font_size_override("font_size", 14)
	_action_button.pressed.connect(_activate_target)
	content.add_child(_action_button)


func _show_for_coord(coord: Vector2i) -> void:
	if coord == NO_COORD or core.frontiers.status(coord).is_empty():
		return
	var was_open := is_open()
	if coord != _target_coord:
		_target_coord = coord
		_refresh_content()
	_panel.visible = true
	_position_panel()
	if not was_open:
		panel_toggled.emit(true)


func _hide_panel() -> void:
	if not is_open():
		return
	if _input_service != null:
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
	var panel_position := marker_position - Vector2(
		panel_size.x * 0.5, panel_size.y + PANEL_GAP
	)
	panel_position.x = clampf(
		panel_position.x,
		VIEWPORT_MARGIN,
		maxf(VIEWPORT_MARGIN, viewport_size.x - panel_size.x - VIEWPORT_MARGIN)
	)
	panel_position.y = clampf(
		panel_position.y,
		VIEWPORT_MARGIN,
		maxf(VIEWPORT_MARGIN, viewport_size.y - panel_size.y - VIEWPORT_MARGIN)
	)
	_panel.position = panel_position


func _refresh_if_current(project: Dictionary) -> void:
	if _target_coord == NO_COORD:
		return
	var frontier := core.frontiers.frontier_for_coord(_target_coord)
	if String(frontier.get("project_id", "")) == String(project.get("id", "")):
		_refresh_content()


func _refresh_content() -> void:
	if _target_coord == NO_COORD or _requirements_row == null:
		return
	var frontier_status := core.frontiers.status(_target_coord)
	if frontier_status.is_empty():
		_hide_panel()
		return
	var project: Dictionary = frontier_status.get("project", {})
	for child in _requirements_row.get_children():
		_requirements_row.remove_child(child)
		child.queue_free()
	for slot: Dictionary in project.get("slots", []):
		_requirements_row.add_child(_requirement_card(slot))

	var ready := bool(frontier_status.get("ready", false))
	var tracked := bool(frontier_status.get("tracked", false))
	var missing_total := int(frontier_status.get("missing_total", 0))
	_title_label.text = String(project.get("name", "Frontier")).to_upper()
	if ready:
		_action_button.disabled = false
		_action_button.focus_mode = Control.FOCUS_ALL
		_state_label.text = "READY"
		_state_label.add_theme_color_override(
			"font_color", kit.text_color()
		)
		_action_button.text = "Unfold land"
		_action_button.tooltip_text = (
			"All requirements are complete. Unfold the reserved natural land. "
			+ _accept_prompt("Unfold land")
		)
	elif tracked:
		_action_button.disabled = true
		_action_button.focus_mode = Control.FOCUS_NONE
		_state_label.text = "TRACKING"
		_state_label.add_theme_color_override(
			"font_color", kit.text_color()
		)
		_action_button.text = "%d remaining" % missing_total
		_action_button.tooltip_text = (
			_requirement_summary(project) + " Gathering now contributes here."
		)
	else:
		_action_button.disabled = false
		_action_button.focus_mode = Control.FOCUS_ALL
		_state_label.text = "LOCKED"
		_state_label.add_theme_color_override(
			"font_color", kit.text_color()
		)
		_action_button.text = "Track requirements"
		_action_button.tooltip_text = (
			_requirement_summary(project) + " "
			+ _accept_prompt("Track this frontier")
		)


func _requirement_card(slot: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Requirement_%s" % String(slot.get("id", "unknown"))
	card.custom_minimum_size = Vector2(70.0, 58.0)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var current := int(slot.get("current", 0))
	var required := int(slot.get("required", 1))
	var complete := current >= required
	var accent := (
		kit.palette.color("ui_good")
		if complete else kit.palette.color("ui_accent")
	)
	var style := kit.surface_style(
		Color(accent, 0.1), UiKit.CORNER_SMALL, accent, 1
	)
	style.set_content_margin_all(5)
	card.add_theme_stylebox_override("panel", style)
	var remaining := maxi(0, required - current)
	card.tooltip_text = "%s: %d of %d%s" % [
		String(slot.get("name", "Requirement")),
		current,
		required,
		" · complete" if remaining == 0 else " · %d left" % remaining,
	]

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(28.0, 28.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_path := String(slot.get("icon", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	column.add_child(icon)
	var count := kit.label("%d/%d" % [current, required], 13, false, true)
	count.name = "Count"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(count)
	return card


func _requirement_summary(project: Dictionary) -> String:
	var parts: Array[String] = []
	for slot: Dictionary in project.get("slots", []):
		var current := int(slot.get("current", 0))
		var required := int(slot.get("required", 1))
		var remaining := maxi(0, required - current)
		parts.append("%s %d/%d%s" % [
			String(slot.get("name", "Requirement")),
			current,
			required,
			"" if remaining == 0 else " (%d left)" % remaining,
		])
	return " · ".join(parts)


func _accept_prompt(description: String) -> String:
	if _input_service == null:
		return description
	return _input_service.format_action(&"ui_accept", description)


func _activate_target() -> void:
	if _target_coord == NO_COORD:
		return
	var frontier_status := core.frontiers.status(_target_coord)
	var ready := bool(frontier_status.get("ready", false))
	var coord := _target_coord
	if ready:
		_hide_panel()
	frontier_activated.emit(coord)
	if not ready:
		_refresh_content()
