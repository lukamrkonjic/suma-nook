class_name InputDeviceService
extends Node
## Single source of truth for the active input method, connected controllers,
## human-readable action prompts, and controller focus hand-off.
##
## Gameplay code consumes semantic InputMap actions. UI code asks this service
## how to present those actions; it never checks a controller brand directly.

signal input_method_changed(method: int)
signal controller_connection_changed(device: int, connected: bool)
signal active_controller_changed(device: int)
signal focused_control_changed(control: Control)

enum InputMethod { KEYBOARD_MOUSE, CONTROLLER }
enum ControllerFamily { XBOX, PLAYSTATION, NINTENDO, GENERIC }

const CONTROLLER_SWITCH_DEADZONE := 0.55
const MOUSE_SWITCH_DISTANCE := 3.0

## Player-facing actions that must retain a controller binding. The headless
## suite enforces this list so a future feature cannot silently become
## keyboard-only.
const REQUIRED_CONTROLLER_ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"move_up",
	&"move_down",
	&"sprint",
	&"interact",
	&"jump",
	&"dodge",
	&"build_mode",
	&"build_confirm",
	&"build_cursor_left",
	&"build_cursor_right",
	&"build_cursor_up",
	&"build_cursor_down",
	&"rotate_piece",
	&"store_piece",
	&"camera_rotate_left",
	&"camera_rotate_right",
	&"camera_zoom_in",
	&"camera_zoom_out",
	&"cancel",
	&"pause",
	&"panel_inventory",
	&"panel_character",
	&"panel_skills",
	&"panel_collection",
	&"panel_map",
	&"panel_previous",
	&"panel_next",
	&"return_home",
	&"toggle_hud",
	&"undo",
	&"redo",
	&"look_left",
	&"look_right",
	&"look_up",
	&"look_down",
]

var input_method := InputMethod.KEYBOARD_MOUSE
var active_controller_device := -1

var _last_mouse_position := Vector2.INF
var _last_focused_control: Control


static var _instance: InputDeviceService


static func shared() -> InputDeviceService:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		return (main_loop as SceneTree).root.get_node_or_null(
			"InputService"
		) as InputDeviceService
	return null


func _ready() -> void:
	_instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var connected := Input.get_connected_joypads()
	if not connected.is_empty():
		active_controller_device = int(connected[0])
		input_method = InputMethod.CONTROLLER
	_set_pointer_visibility()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _process(_delta: float) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == _last_focused_control:
		return
	_last_focused_control = focused
	focused_control_changed.emit(focused)


func _input(event: InputEvent) -> void:
	var detected := classify_event(event)
	if detected < 0:
		return
	if detected == InputMethod.CONTROLLER:
		var device := _event_device(event)
		if device >= 0:
			_set_active_controller(device)
		_set_input_method(InputMethod.CONTROLLER)
		return
	if event is InputEventMouseMotion:
		var mouse_position := (event as InputEventMouseMotion).position
		if (
			_last_mouse_position != Vector2.INF
			and mouse_position.distance_to(_last_mouse_position)
				< MOUSE_SWITCH_DISTANCE
		):
			_last_mouse_position = mouse_position
			return
		_last_mouse_position = mouse_position
	_set_input_method(InputMethod.KEYBOARD_MOUSE)


static func classify_event(event: InputEvent) -> int:
	if event is InputEventJoypadButton:
		return (
			InputMethod.CONTROLLER
			if (event as InputEventJoypadButton).pressed
			else -1
		)
	if event is InputEventJoypadMotion:
		return (
			InputMethod.CONTROLLER
			if absf((event as InputEventJoypadMotion).axis_value)
				>= CONTROLLER_SWITCH_DEADZONE
			else -1
		)
	if event is InputEventKey:
		var key := event as InputEventKey
		return InputMethod.KEYBOARD_MOUSE if key.pressed and not key.echo else -1
	if event is InputEventMouseButton:
		return (
			InputMethod.KEYBOARD_MOUSE
			if (event as InputEventMouseButton).pressed
			else -1
		)
	if event is InputEventMouseMotion:
		return InputMethod.KEYBOARD_MOUSE
	return -1


func is_controller() -> bool:
	return input_method == InputMethod.CONTROLLER


func connected_controller_count() -> int:
	return Input.get_connected_joypads().size()


func active_controller_name() -> String:
	if active_controller_device < 0:
		return "Controller"
	var controller_name := Input.get_joy_name(active_controller_device)
	return controller_name if controller_name != "" else "Controller"


func controller_family() -> int:
	return controller_family_for_name(active_controller_name())


static func controller_family_for_name(controller_name: String) -> int:
	var normalized := controller_name.to_lower()
	if (
		"playstation" in normalized
		or "dualshock" in normalized
		or "dualsense" in normalized
		or "sony" in normalized
	):
		return ControllerFamily.PLAYSTATION
	if (
		"nintendo" in normalized
		or "switch" in normalized
		or "joy-con" in normalized
		or "joycon" in normalized
	):
		return ControllerFamily.NINTENDO
	if (
		"xbox" in normalized
		or "xinput" in normalized
		or "microsoft" in normalized
	):
		return ControllerFamily.XBOX
	return ControllerFamily.GENERIC


func prompt_for_action(
	action: StringName,
	method_override := -1
) -> String:
	if not InputMap.has_action(action):
		return String(action).replace("_", " ").capitalize()
	var method := input_method if method_override < 0 else method_override
	for event in InputMap.action_get_events(action):
		if method == InputMethod.CONTROLLER and _is_controller_event(event):
			return _controller_event_prompt(event)
		if method == InputMethod.KEYBOARD_MOUSE and _is_keyboard_mouse_event(event):
			return _keyboard_mouse_event_prompt(event)
	return String(action).replace("_", " ").capitalize()


func format_action(
	action: StringName,
	description: String,
	method_override := -1
) -> String:
	return "[%s] %s" % [
		prompt_for_action(action, method_override),
		description,
	]


func action_has_controller_binding(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if _is_controller_event(event):
			return true
	return false


func focus_first(root: Node, preferred: Control = null) -> void:
	call_deferred("_focus_first_deferred", root, preferred)


func release_focus_in(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and (focused == root or root.is_ancestor_of(focused)):
		get_viewport().gui_release_focus()


func _focus_first_deferred(root: Node, preferred: Control) -> void:
	if not is_controller() or root == null or not is_instance_valid(root):
		return
	if (
		preferred != null
		and is_instance_valid(preferred)
		and _is_focus_candidate(preferred)
	):
		preferred.grab_focus()
		return
	var candidates: Array[Control] = []
	_collect_focus_candidates(root, candidates)
	if not candidates.is_empty():
		candidates[0].grab_focus()


func _collect_focus_candidates(node: Node, result: Array[Control]) -> void:
	var control := node as Control
	if control != null and _is_focus_candidate(control):
		result.append(control)
	for child in node.get_children():
		_collect_focus_candidates(child, result)


func _is_focus_candidate(control: Control) -> bool:
	if (
		not control.is_visible_in_tree()
		or control.focus_mode == Control.FOCUS_NONE
	):
		return false
	var button := control as BaseButton
	return button == null or not button.disabled


func _set_input_method(method: int) -> void:
	if input_method == method:
		return
	input_method = method
	_set_pointer_visibility()
	input_method_changed.emit(input_method)


func _set_pointer_visibility() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = (
		Input.MOUSE_MODE_HIDDEN
		if is_controller()
		else Input.MOUSE_MODE_VISIBLE
	)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	controller_connection_changed.emit(device, connected)
	if connected:
		_set_active_controller(device)
		_set_input_method(InputMethod.CONTROLLER)
		return
	if device != active_controller_device:
		return
	var controllers := Input.get_connected_joypads()
	if controllers.is_empty():
		_set_active_controller(-1)
		_set_input_method(InputMethod.KEYBOARD_MOUSE)
	else:
		_set_active_controller(int(controllers[0]))


func _set_active_controller(device: int) -> void:
	if active_controller_device == device:
		return
	active_controller_device = device
	active_controller_changed.emit(active_controller_device)


func _event_device(event: InputEvent) -> int:
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).device
	if event is InputEventJoypadMotion:
		return (event as InputEventJoypadMotion).device
	return -1


func _is_controller_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


func _is_keyboard_mouse_event(event: InputEvent) -> bool:
	return (
		event is InputEventKey
		or event is InputEventMouseButton
		or event is InputEventMouseMotion
	)


func _keyboard_mouse_event_prompt(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var parts := PackedStringArray()
		if key.ctrl_pressed or key.meta_pressed:
			parts.append("Ctrl")
		if key.alt_pressed:
			parts.append("Alt")
		if key.shift_pressed:
			parts.append("Shift")
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		var key_name := OS.get_keycode_string(code)
		parts.append("Esc" if key_name == "Escape" else key_name)
		return "+".join(parts)
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				return "Left Click"
			MOUSE_BUTTON_RIGHT:
				return "Right Click"
			MOUSE_BUTTON_MIDDLE:
				return "Middle Mouse"
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				return "Wheel"
	return "Mouse"


func _controller_event_prompt(event: InputEvent) -> String:
	if event is InputEventJoypadMotion:
		match (event as InputEventJoypadMotion).axis:
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
				return "Left Stick"
			JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y:
				return "Right Stick"
			JOY_AXIS_TRIGGER_LEFT:
				return "L2" if controller_family() == ControllerFamily.PLAYSTATION else "LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "R2" if controller_family() == ControllerFamily.PLAYSTATION else "RT"
		return "Stick"
	var button := (event as InputEventJoypadButton).button_index
	match button:
		JOY_BUTTON_A:
			return _face_button_label(0)
		JOY_BUTTON_B:
			return _face_button_label(1)
		JOY_BUTTON_X:
			return _face_button_label(2)
		JOY_BUTTON_Y:
			return _face_button_label(3)
		JOY_BUTTON_BACK:
			return (
				"Create"
				if controller_family() == ControllerFamily.PLAYSTATION
				else "View"
			)
		JOY_BUTTON_START:
			return "Options" if controller_family() == ControllerFamily.PLAYSTATION else "Menu"
		JOY_BUTTON_LEFT_STICK:
			return "L3"
		JOY_BUTTON_RIGHT_STICK:
			return "R3"
		JOY_BUTTON_LEFT_SHOULDER:
			return "L1" if controller_family() == ControllerFamily.PLAYSTATION else "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "R1" if controller_family() == ControllerFamily.PLAYSTATION else "RB"
		JOY_BUTTON_DPAD_UP:
			return "D-pad Up"
		JOY_BUTTON_DPAD_DOWN:
			return "D-pad Down"
		JOY_BUTTON_DPAD_LEFT:
			return "D-pad Left"
		JOY_BUTTON_DPAD_RIGHT:
			return "D-pad Right"
	return "Button %d" % button


func _face_button_label(position: int) -> String:
	match controller_family():
		ControllerFamily.PLAYSTATION:
			return ["Cross", "Circle", "Square", "Triangle"][position]
		ControllerFamily.NINTENDO:
			return ["B", "A", "Y", "X"][position]
		_:
			return ["A", "B", "X", "Y"][position]
