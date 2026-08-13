class_name CollectionDivider
extends HBoxContainer
## Quiet collection identity: hairline, tiny coloured symbol, hairline.

var marker: Button


func setup(kit: UiKit, section_name: String, accent: Color, glyph := "◆") -> void:
	name = "CollectionDivider"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", kit.tokens.divider_gap)

	var left := kit.divider()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(left)

	marker = Button.new()
	marker.name = "CollectionMarker"
	marker.text = glyph
	marker.tooltip_text = section_name
	marker.focus_mode = Control.FOCUS_ALL
	marker.mouse_filter = Control.MOUSE_FILTER_STOP
	marker.custom_minimum_size = Vector2.ONE * kit.tokens.marker_hit_size
	marker.add_theme_font_override("font", kit.font_bold)
	marker.add_theme_font_size_override(
		"font_size", kit.tokens.marker_visual_size
	)
	for state in ["normal", "hover", "pressed", "disabled"]:
		marker.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(kit.ui_color("paper"), 0.0)
	focus.border_color = Color(kit.ui_color("focus"), 0.72)
	focus.set_border_width_all(kit.tokens.focus_width)
	focus.set_corner_radius_all(kit.tokens.control_corner_radius)
	marker.add_theme_stylebox_override("focus", focus)
	for color_name in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
	]:
		marker.add_theme_color_override(color_name, accent)
	add_child(marker)

	var right := kit.divider()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(right)
