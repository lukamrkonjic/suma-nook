class_name DebugMenu
extends CanvasLayer
## Compact, debug-build-only tools that stay over the live world. New tools
## register into named sections instead of growing another one-off admin page.

const CARD_WIDTH := 286.0
const SMALL_BUTTON_HEIGHT := 30.0

var core: GameCore
var kit: UiKit
var bridge: Main
var _input_service: InputDeviceService
var _root: Control
var _card: PanelContainer
var _body: VBoxContainer
var _toggle: Button
var _status: Label
var _first_action: Button
var _sections: Dictionary = {}
var _expanded := true


func setup(game_core: GameCore, ui_kit: UiKit, main_bridge: Main) -> void:
	core = game_core
	kit = ui_kit
	bridge = main_bridge
	_input_service = InputDeviceService.shared()
	layer = 126
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_register_builtin_actions()
	visible = false


func show_for_gameplay() -> void:
	visible = true


func show_and_focus() -> void:
	show_for_gameplay()
	set_expanded(true)
	if _input_service != null:
		_input_service.focus_first(_body, _first_action)


func set_expanded(expanded: bool) -> void:
	_expanded = expanded
	if _body != null:
		_body.visible = expanded
	if _toggle != null:
		_toggle.text = "−" if expanded else "+"
		_toggle.tooltip_text = (
			"Collapse debug tools" if expanded else "Expand debug tools"
		)
	if not expanded and _input_service != null and _body != null:
		_input_service.release_focus_in(_body)


func is_expanded() -> bool:
	return _expanded


func blocks_world_pointer(screen_position: Vector2) -> bool:
	return visible and _card != null and _card.get_global_rect().has_point(screen_position)


## Public extension point for future debug tools. Reusing a section id appends
## another compact action to that section's wrapping row.
func register_action(
	section_id: String,
	section_title: String,
	label: String,
	tooltip: String,
	stable_name: String,
	action: Callable
) -> Button:
	var action_row := _section(section_id, section_title)
	var button := _small_button(label)
	button.name = stable_name
	button.tooltip_text = tooltip
	button.pressed.connect(func(): action.call())
	action_row.add_child(button)
	if _first_action == null:
		_first_action = button
	return button


func set_status(message: String, good := true) -> void:
	if _status == null:
		return
	_status.text = message
	_status.add_theme_color_override(
		"font_color", kit.text_color()
	)


func _build() -> void:
	_root = Control.new()
	_root.name = "DebugMenuRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = kit.theme
	add_child(_root)

	_card = PanelContainer.new()
	_card.name = "DebugMenuCard"
	_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.offset_left = -UiKit.HUD_MARGIN - CARD_WIDTH
	_card.offset_top = -UiKit.HUD_MARGIN
	_card.offset_right = -UiKit.HUD_MARGIN
	_card.offset_bottom = -UiKit.HUD_MARGIN
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var card_style := kit.hud_dock_style()
	card_style.set_content_margin_all(10)
	_card.add_theme_stylebox_override("panel", card_style)
	_root.add_child(_card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_card.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	column.add_child(header)
	var title := kit.utility_label("DEBUG", 11, kit.palette.color("ui_accent"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", kit.text_color())
	header.add_child(title)
	_toggle = _small_button("−")
	_toggle.name = "DebugMenuToggle"
	_toggle.custom_minimum_size = Vector2(28, 26)
	_toggle.tooltip_text = "Collapse debug tools"
	_toggle.pressed.connect(func(): set_expanded(not _expanded))
	header.add_child(_toggle)

	_body = VBoxContainer.new()
	_body.name = "DebugMenuBody"
	_body.add_theme_constant_override("separation", 7)
	column.add_child(_body)

	_status = kit.label("Ready", 11)
	_status.name = "DebugMenuStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 26)
	_status.add_theme_color_override(
		"font_color", kit.text_color()
	)
	_body.add_child(_status)


func _register_builtin_actions() -> void:
	register_action(
		"world", "World",
		"Skyfall now",
		"Prepare and open a wish immediately; choosing a collection drops one piece.",
		"DebugSkyfallNow",
		func() -> void:
			var ready := bridge.debug_prompt_skyfall()
			set_status("Wish ready." if ready else "Could not prepare a wish.", ready)
	)
	register_action(
		"library", "Build Bag",
		"Items ×99",
		"Add 99 of every registered inventory item.",
		"DebugGrantItems99",
		func() -> void:
			var count := bridge.debug_grant_all_items(99)
			set_status("Added ×99 to %d item kinds." % count)
	)
	register_action(
		"library", "Build Bag",
		"Tiles ×99",
		"Add 99 of every obtainable tile to the Build Bag.",
		"DebugGrantTiles99",
		func() -> void:
			var count := bridge.debug_grant_all_tiles(99)
			set_status("Added ×99 to %d tile kinds." % count)
	)
	register_action(
		"library", "Build Bag",
		"Models ×99",
		"Add 99 of every registered model and decoration to the Build Bag.",
		"DebugGrantModels99",
		func() -> void:
			var count := bridge.debug_grant_all_models(99)
			set_status("Added ×99 to %d model kinds." % count)
	)
	# Status belongs below every section even when future actions are appended.
	_body.move_child(_status, _body.get_child_count() - 1)


func _section(section_id: String, title: String) -> HFlowContainer:
	if _sections.has(section_id):
		return _sections[section_id] as HFlowContainer
	var section := VBoxContainer.new()
	section.name = "DebugSection" + section_id.to_pascal_case()
	section.add_theme_constant_override("separation", 3)
	var heading := kit.utility_label(title, 9)
	heading.add_theme_color_override(
		"font_color", kit.text_color()
	)
	section.add_child(heading)
	var row := HFlowContainer.new()
	row.name = "Actions"
	row.add_theme_constant_override("h_separation", 5)
	row.add_theme_constant_override("v_separation", 5)
	section.add_child(row)
	# Keep the status at the bottom while actions are registered later.
	var status_index := _status.get_index() if _status != null else _body.get_child_count()
	_body.add_child(section)
	if _status != null:
		_body.move_child(section, status_index)
	_sections[section_id] = row
	return row


func _small_button(text: String) -> Button:
	return kit.compact_button(text, SMALL_BUTTON_HEIGHT)
