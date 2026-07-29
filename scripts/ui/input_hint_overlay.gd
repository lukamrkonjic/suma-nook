class_name InputHintOverlay
extends CanvasLayer
## Controller-only action strip and focus-tooltip presenter. Context owners
## publish semantic actions; this view resolves their current controller names.

var _kit: UiKit
var _input_service: InputDeviceService
var _root: Control
var _panel: PanelContainer
var _tooltip_label: Label
var _action_label: Label
var _context: Array[Dictionary] = []
var _focused_control: Control


func setup(ui_kit: UiKit) -> void:
	_kit = ui_kit
	_input_service = InputDeviceService.shared()
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_input_service.input_method_changed.connect(func(_method): _refresh())
	_input_service.active_controller_changed.connect(func(_device): _refresh())
	_input_service.focused_control_changed.connect(_on_focused_control_changed)
	_refresh()


func set_context(actions: Array[Dictionary]) -> void:
	_context = actions.duplicate(true)
	_refresh()


func clear_context() -> void:
	_context.clear()
	_refresh()


func _build() -> void:
	_root = Control.new()
	_root.name = "InputHintRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = _kit.card(Vector2(420, 0), true)
	_panel.name = "ControllerHints"
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.position.y = -18
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)
	_tooltip_label = _kit.label("", 14, true)
	_tooltip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_label.custom_minimum_size.x = 390
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_tooltip_label)
	_action_label = _kit.label("", 15, true, true)
	_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_action_label)


func _on_focused_control_changed(control: Control) -> void:
	_focused_control = control
	_refresh()


func _refresh() -> void:
	if _root == null:
		return
	_root.visible = _input_service.is_controller()
	if not _root.visible:
		return
	var actions := _context
	var tooltip := ""
	if _focused_control != null and is_instance_valid(_focused_control):
		tooltip = _focused_control.tooltip_text
		var focus_description := "Select"
		if _focused_control is Range or _focused_control is OptionButton:
			focus_description = "Adjust"
		elif _focused_control is LineEdit or _focused_control is TextEdit:
			focus_description = "Edit"
		actions = [
			{"action": &"ui_accept", "label": focus_description},
			{"action": &"cancel", "label": "Back"},
		]
	var rendered := PackedStringArray()
	for entry: Dictionary in actions:
		var action := StringName(entry.get("action", ""))
		var label := String(entry.get("label", ""))
		if action != &"" and label != "":
			rendered.append(_input_service.format_action(action, label))
	_action_label.text = "  ·  ".join(rendered)
	_tooltip_label.text = tooltip
	_tooltip_label.visible = tooltip != ""
	_panel.visible = not rendered.is_empty() or tooltip != ""
