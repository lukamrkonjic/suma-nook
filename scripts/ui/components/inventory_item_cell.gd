class_name InventoryItemCell
extends Button
## A miniature-first inventory cell. Names live in tooltips; quantities and
## status use tiny corner indicators so the object remains the visual focus.

var preview: TextureRect
var quantity_label: Label
var status_dot: ColorRect
var _kit: UiKit
var _selected := false
var _available := true
var _pointer_inside := false
var _preview_tween: Tween


func setup(
	kit: UiKit,
	display_name: String,
	count: int,
	selected := false,
	available := true
) -> void:
	_kit = kit
	_selected = selected
	_available = available
	text = ""
	clip_contents = false
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = kit.tokens.reference_cell_size
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme = kit.theme
	tooltip_text = display_name

	preview = TextureRect.new()
	preview.name = "ItemPreview"
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.offset_left = 13
	preview.offset_top = 11
	preview.offset_right = -13
	preview.offset_bottom = -11
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.pivot_offset = kit.tokens.reference_cell_size * 0.5
	add_child(preview)

	quantity_label = kit.label(_quantity_text(count), kit.tokens.quantity_font_size)
	quantity_label.name = "QuantityLabel"
	quantity_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	quantity_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	quantity_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	quantity_label.position = Vector2(-9, -7)
	quantity_label.add_theme_color_override(
		"font_color", kit.text_color()
	)
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_label.visible = count != 0
	add_child(quantity_label)

	status_dot = ColorRect.new()
	status_dot.name = "StatusDot"
	status_dot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_dot.position = Vector2(9, -12)
	status_dot.custom_minimum_size = Vector2(5, 5)
	status_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_dot.visible = false
	add_child(status_dot)

	mouse_entered.connect(_on_pointer_entered)
	mouse_exited.connect(_on_pointer_exited)
	focus_entered.connect(_refresh_lift)
	focus_exited.connect(_refresh_lift)
	button_down.connect(_on_button_down)
	button_up.connect(_refresh_lift)
	_apply_style()


func set_preview(texture: Texture2D) -> void:
	preview.texture = texture


func set_status(color: Color, description := "") -> void:
	status_dot.color = color
	status_dot.visible = color.a > 0.0
	if description != "":
		tooltip_text += "\n%s" % description


func set_selected(value: bool) -> void:
	_selected = value
	_apply_style()


func set_available(value: bool) -> void:
	_available = value
	modulate = Color.WHITE if value else Color(1, 1, 1, 0.48)
	_apply_style()


func _quantity_text(count: int) -> String:
	return "∞" if count < 0 else str(count)


func _apply_style() -> void:
	if _kit == null:
		return
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(
			state,
			_kit.inventory_cell_style(
				state,
				_selected,
				_available
			)
		)


func _on_pointer_entered() -> void:
	_pointer_inside = true
	_refresh_lift()


func _on_pointer_exited() -> void:
	_pointer_inside = false
	_refresh_lift()


func _on_button_down() -> void:
	_animate_preview(_kit.tokens.pressed_scale)


func _refresh_lift() -> void:
	_animate_preview(
		_kit.tokens.hover_scale
		if _pointer_inside or has_focus()
		else 1.0
	)


func _animate_preview(target_scale: float) -> void:
	if preview == null or _kit == null:
		return
	preview.pivot_offset = preview.size * 0.5
	if _preview_tween != null and _preview_tween.is_valid():
		_preview_tween.kill()
	var duration := _kit.motion_duration(_kit.tokens.hover_duration)
	if is_zero_approx(duration):
		preview.scale = Vector2.ONE * target_scale
		return
	_preview_tween = create_tween()
	_preview_tween.set_trans(Tween.TRANS_QUAD)
	_preview_tween.set_ease(Tween.EASE_OUT)
	_preview_tween.tween_property(
		preview,
		"scale",
		Vector2.ONE * target_scale,
		duration
	)
