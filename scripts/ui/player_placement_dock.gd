class_name PlayerPlacementDock
extends TextureButton
## Pegman-style keeper handle. It owns the cross-Control pointer capture so a
## drag that begins in the HUD remains continuous after entering the 3D world.

signal activated
signal drag_started(screen_position: Vector2)
signal drag_moved(screen_position: Vector2)
signal drag_released(screen_position: Vector2)

const DRAG_THRESHOLD := 7.0

var deployed := false
var _pointer_down := false
var _dragging := false
var _press_position := Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(66, 74)
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	set_process_input(false)


func set_deployed(value: bool) -> void:
	deployed = value
	modulate = Color(0.82, 0.82, 0.82) if deployed else Color.WHITE
	mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND if deployed else Control.CURSOR_DRAG
	)
	tooltip_text = (
		"Click to recall your keeper"
		if deployed else "Drag your keeper onto a walkable tile"
	)


func cancel_gesture() -> void:
	_pointer_down = false
	_dragging = false
	set_process_input(false)


func _gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		and (event as InputEventMouseButton).pressed
	):
		_begin_pointer(get_viewport().get_mouse_position())
		accept_event()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_begin_pointer((event as InputEventScreenTouch).position)
		accept_event()


func _input(event: InputEvent) -> void:
	if not _pointer_down:
		return
	var pointer := Vector2.ZERO
	var released := false
	var moved := false
	if event is InputEventMouseMotion:
		pointer = (event as InputEventMouseMotion).position
		moved = true
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		pointer = mouse.position
		released = not mouse.pressed
	elif event is InputEventScreenDrag:
		pointer = (event as InputEventScreenDrag).position
		moved = true
	elif event is InputEventScreenTouch:
		pointer = (event as InputEventScreenTouch).position
		released = not (event as InputEventScreenTouch).pressed
	else:
		return
	if moved and not deployed:
		if not _dragging and pointer.distance_to(_press_position) >= DRAG_THRESHOLD:
			_dragging = true
			drag_started.emit(pointer)
		if _dragging:
			drag_moved.emit(pointer)
	if released:
		if _dragging and not deployed:
			drag_released.emit(pointer)
		else:
			activated.emit()
		cancel_gesture()
	get_viewport().set_input_as_handled()


func _begin_pointer(screen_position: Vector2) -> void:
	_pointer_down = true
	_dragging = false
	_press_position = screen_position
	set_process_input(true)
