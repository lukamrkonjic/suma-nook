class_name UiKit
extends RefCounted
## Shared UI vocabulary: warm cream cards, chunky rounded corners, dark warm
## text. Every panel and button in the game is built through these helpers so
## the interface reads as one hand.

const FONT_MEDIUM_PATH := "res://assets/fonts/Fredoka-Medium.ttf"
const FONT_SEMIBOLD_PATH := "res://assets/fonts/Fredoka-SemiBold.ttf"

var palette: CozyPalette
var font: FontFile
var font_bold: FontFile
var theme: Theme


func _init(pal: CozyPalette) -> void:
	palette = pal
	font = load(FONT_MEDIUM_PATH)
	font_bold = load(FONT_SEMIBOLD_PATH)
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(1.0, 0.93, 0.58, 0.12)
	focus.border_color = palette.color("ui_accent").lightened(0.18)
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(10)
	for control_type in [
		"Button",
		"CheckButton",
		"OptionButton",
		"HSlider",
		"VSlider",
		"LineEdit",
		"TextEdit",
	]:
		theme.set_stylebox("focus", control_type, focus)


func panel_style(dark := false, radius := 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = palette.color("ui_panel_dark") if dark else Color(0.95, 0.94, 0.89, 0.96)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(16)
	style.anti_aliasing = true
	return style


func cloud_panel_style(radius := 30) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.965, 0.96, 0.925, 0.98)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(32)
	style.shadow_color = Color(0.12, 0.12, 0.1, 0.18)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 7)
	style.anti_aliasing = true
	return style


func text_color(dark_background := false) -> Color:
	return Color(0.95, 0.94, 0.9) if dark_background else Color(0.23, 0.22, 0.19)


func label(text: String, size := 18, dark_background := false, strong := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold if strong else font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", text_color(dark_background))
	return l


func button(text: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 18)
	var normal := StyleBoxFlat.new()
	normal.bg_color = palette.color("ui_accent").lightened(0.06) if accent else Color(0.88, 0.87, 0.82, 0.82)
	normal.set_corner_radius_all(12)
	normal.set_content_margin_all(11)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	var hover := normal.duplicate()
	hover.bg_color = normal.bg_color.lightened(0.08)
	var pressed := normal.duplicate()
	pressed.bg_color = normal.bg_color.darkened(0.08)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.8, 0.78, 0.73, 0.6)
	var focus := normal.duplicate()
	focus.bg_color = normal.bg_color.lightened(0.04)
	focus.border_color = palette.color("ui_accent").lightened(0.2)
	focus.set_border_width_all(3)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", Color.WHITE if accent else text_color())
	b.add_theme_color_override("font_hover_color", Color.WHITE if accent else text_color())
	b.add_theme_color_override("font_focus_color", Color.WHITE if accent else text_color())
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.47, 0.42))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func choice_button(text: String, selected := false) -> Button:
	var b := button(text, false)
	b.toggle_mode = true
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = palette.color("ui_accent").lightened(0.06)
	selected_style.set_corner_radius_all(12)
	selected_style.set_content_margin_all(11)
	selected_style.content_margin_left = 18
	selected_style.content_margin_right = 18
	b.add_theme_stylebox_override("pressed", selected_style)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.set_pressed_no_signal(selected)
	return b


func library_category_button(text: String, selected := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.custom_minimum_size = Vector2(70, 38)
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 13)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.86, 0.85, 0.79, 0.62)
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate()
	hover.bg_color = Color(0.82, 0.84, 0.75, 0.9)
	var pressed := normal.duplicate()
	pressed.bg_color = palette.color("ui_good").lightened(0.05)
	var focus := pressed.duplicate()
	focus.set_border_width_all(3)
	focus.border_color = palette.color("ui_accent").lightened(0.2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", Color(0.32, 0.31, 0.27))
	b.add_theme_color_override("font_hover_color", Color(0.24, 0.27, 0.2))
	b.add_theme_color_override("font_pressed_color", Color(0.98, 0.97, 0.91))
	b.add_theme_color_override("font_focus_color", Color(0.98, 0.97, 0.91))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.set_pressed_no_signal(selected)
	return b


func library_item_button(display_name: String, count: int) -> Button:
	var b := Button.new()
	b.text = "%s   x%d" % [display_name, count]
	b.custom_minimum_size = Vector2(158, 52)
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 16)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.91, 0.9, 0.85, 0.92)
	normal.set_corner_radius_all(15)
	normal.content_margin_left = 17
	normal.content_margin_right = 17
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate()
	hover.bg_color = Color(0.95, 0.91, 0.82, 1.0)
	hover.shadow_color = Color(0.25, 0.2, 0.14, 0.12)
	hover.shadow_size = 5
	hover.shadow_offset = Vector2(0, 2)
	var pressed := normal.duplicate()
	pressed.bg_color = palette.color("ui_accent").lightened(0.12)
	var focus := hover.duplicate()
	focus.set_border_width_all(3)
	focus.border_color = palette.color("ui_accent").lightened(0.2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", Color(0.28, 0.27, 0.24))
	b.add_theme_color_override("font_hover_color", Color(0.24, 0.23, 0.2))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color(0.24, 0.23, 0.2))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func library_visual_item_button(
	display_name: String,
	count: int
) -> Dictionary:
	var button := Button.new()
	button.custom_minimum_size = Vector2(132, 146)
	button.clip_contents = true
	button.add_theme_font_override("font", font_bold)
	button.focus_mode = Control.FOCUS_ALL

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.91, 0.91, 0.85, 0.94)
	normal.set_corner_radius_all(18)
	normal.set_content_margin_all(0)
	normal.border_color = Color(0.43, 0.5, 0.34, 0.0)
	normal.set_border_width_all(2)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.96, 0.94, 0.85, 1.0)
	hover.border_color = palette.color("ui_good").lightened(0.08)
	hover.shadow_color = Color(0.16, 0.2, 0.12, 0.16)
	hover.shadow_size = 7
	hover.shadow_offset = Vector2(0, 3)
	var pressed := hover.duplicate()
	pressed.bg_color = palette.color("ui_accent").lightened(0.2)
	var focus := hover.duplicate()
	focus.border_color = palette.color("ui_accent").lightened(0.2)
	focus.set_border_width_all(4)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 8
	content.offset_top = 7
	content.offset_right = -8
	content.offset_bottom = -7
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 1)
	button.add_child(content)

	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.custom_minimum_size = Vector2(116, 105)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(preview)

	var name_label := label(display_name, 13, false, true)
	name_label.name = "Name"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_label)

	var badge: PanelContainer
	if count > 1:
		badge = PanelContainer.new()
		badge.name = "CountBadge"
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.position = Vector2(-9, 9)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		var badge_style := StyleBoxFlat.new()
		badge_style.bg_color = palette.color("ui_good").darkened(0.08)
		badge_style.set_corner_radius_all(12)
		badge_style.content_margin_left = 8
		badge_style.content_margin_right = 8
		badge_style.content_margin_top = 4
		badge_style.content_margin_bottom = 4
		badge_style.shadow_color = Color(0.08, 0.1, 0.06, 0.2)
		badge_style.shadow_size = 3
		badge_style.shadow_offset = Vector2(0, 2)
		badge.add_theme_stylebox_override("panel", badge_style)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var count_label := label("×%d" % count, 13, true, true)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(count_label)
		button.add_child(badge)

	return {
		"button": button,
		"preview": preview,
		"badge": badge,
	}


func style_library_scrollbar(scroll: ScrollContainer) -> void:
	var horizontal := scroll.get_h_scroll_bar()
	var vertical := scroll.get_v_scroll_bar()
	horizontal.custom_minimum_size.y = 6
	vertical.custom_minimum_size.x = 7
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.72, 0.72, 0.66, 0.28)
	track.set_corner_radius_all(3)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = palette.color("ui_good").lightened(0.1)
	grabber.set_corner_radius_all(3)
	var grabber_hover := grabber.duplicate()
	grabber_hover.bg_color = palette.color("ui_good").lightened(0.18)
	var grabber_pressed := grabber.duplicate()
	grabber_pressed.bg_color = palette.color("ui_good").darkened(0.05)
	for bar: ScrollBar in [horizontal, vertical]:
		bar.add_theme_stylebox_override("scroll", track)
		bar.add_theme_stylebox_override("scroll_focus", track)
		bar.add_theme_stylebox_override("grabber", grabber)
		bar.add_theme_stylebox_override("grabber_highlight", grabber_hover)
		bar.add_theme_stylebox_override("grabber_pressed", grabber_pressed)


func library_arrow_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(42, 52)
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 22)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.84, 0.83, 0.77, 0.72)
	normal.set_corner_radius_all(16)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.78, 0.81, 0.71, 0.95)
	var pressed := normal.duplicate()
	pressed.bg_color = palette.color("ui_good")
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.84, 0.83, 0.78, 0.28)
	var focus := hover.duplicate()
	focus.border_color = palette.color("ui_accent").lightened(0.2)
	focus.set_border_width_all(3)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", Color(0.33, 0.32, 0.28))
	b.add_theme_color_override("font_hover_color", Color(0.25, 0.28, 0.21))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.44, 0.4, 0.3))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func menu_button(text: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(370, 62)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 26)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0)
	normal.set_corner_radius_all(14)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 13
	normal.content_margin_bottom = 13
	var hover := normal.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.46)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.78, 0.8, 0.73, 0.46)
	var focus := normal.duplicate()
	focus.bg_color = Color(1, 1, 1, 0.3)
	focus.border_color = palette.color("ui_accent").lightened(0.2)
	focus.set_border_width_all(3)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	var color := Color(0.93, 0.94, 0.89) if accent else text_color()
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", color)
	b.add_theme_color_override("font_pressed_color", color)
	b.add_theme_color_override("font_focus_color", color)
	if accent:
		normal.bg_color = palette.color("ui_good").darkened(0.02)
		hover.bg_color = normal.bg_color.lightened(0.06)
		pressed.bg_color = normal.bg_color.darkened(0.06)
		focus.bg_color = normal.bg_color.lightened(0.03)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func section_label(text: String) -> Label:
	var l := label(text.to_upper(), 16, false, true)
	l.add_theme_color_override("font_color", palette.color("ui_good").darkened(0.08))
	return l


func keycap(text: String, minimum_width := 42.0) -> PanelContainer:
	var cap := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.31, 0.24, 0.2)
	style.set_corner_radius_all(7)
	style.set_content_margin_all(5)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.border_width_bottom = 3
	style.border_color = Color(0.13, 0.09, 0.07, 0.7)
	cap.add_theme_stylebox_override("panel", style)
	cap.custom_minimum_size.x = minimum_width
	var l := label(text, 16, true, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(l)
	return cap


func card(minimum := Vector2(0, 0), dark := false) -> PanelContainer:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", panel_style(dark))
	c.custom_minimum_size = minimum
	return c


func window(title: String, size: Vector2) -> Dictionary:
	## Returns {root (centered overlay), card, content (VBox), close (Button)}.
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks behind the panel
	root.theme = theme
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.18, 0.17, 0.14, 0.22)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var c := card(size)
	c.add_theme_stylebox_override("panel", cloud_panel_style())
	center.add_child(c)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	c.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title_label := label(title, 28, false, true)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close := button("✕")
	header.add_child(close)
	return {"root": root, "card": c, "content": content, "close": close}


func surface_style(
	background: Color,
	radius := 16,
	border := Color(0, 0, 0, 0),
	border_width := 0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(14)
	style.border_color = border
	style.set_border_width_all(border_width)
	style.anti_aliasing = true
	return style


func progression_panel_style(accent: Color, radius := 18) -> StyleBoxFlat:
	var style := surface_style(
		Color(0.975, 0.967, 0.92, 0.98),
		radius,
		accent.darkened(0.08),
		2
	)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.shadow_color = Color(0.13, 0.12, 0.09, 0.14)
	style.shadow_size = 9
	style.shadow_offset = Vector2(0, 4)
	return style


func progression_card(minimum: Vector2, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.add_theme_stylebox_override("panel", progression_panel_style(accent))
	return panel


func eyebrow(text: String, accent: Color = Color(0.35, 0.42, 0.24)) -> Label:
	var l := label(text.to_upper(), 12, false, true)
	l.add_theme_color_override("font_color", accent.darkened(0.08))
	l.add_theme_constant_override("letter_spacing", 1)
	return l


func muted_label(text: String, size := 14) -> Label:
	var l := label(text, size)
	l.add_theme_color_override("font_color", Color(0.45, 0.43, 0.37))
	return l


func pill(text: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := surface_style(accent.lightened(0.56), 10, accent.lightened(0.22), 1)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var l := label(text, 12, false, true)
	l.add_theme_color_override("font_color", accent.darkened(0.22))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(l)
	return panel


func monogram(glyph: String, accent: Color, size := 42.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(size, size)
	var style := surface_style(accent, int(size * 0.5))
	style.set_content_margin_all(0)
	style.shadow_color = Color(0.08, 0.08, 0.06, 0.13)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", style)
	var l := label(glyph, int(size * 0.46), true, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(l)
	return panel


func divider(color := Color(0.3, 0.28, 0.22, 0.14)) -> ColorRect:
	var line := ColorRect.new()
	line.color = color
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func progress_bar(fraction: float, color_key := "ui_good", width := 120) -> Control:
	return progress_bar_colored(fraction, palette.color(color_key), width)


func progress_bar_colored(
	fraction: float,
	color: Color,
	width := 120,
	height := 10
) -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(width, height)
	holder.clip_contents = true
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.2, 0.18, 0.14, 0.13)
	back.set_corner_radius_all(height / 2)
	holder.add_theme_stylebox_override("panel", back)
	var fill := PanelContainer.new()
	fill.custom_minimum_size = Vector2(
		maxf(0.0, width * clampf(fraction, 0.0, 1.0)),
		height
	)
	fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.set_corner_radius_all(height / 2)
	fill.add_theme_stylebox_override("panel", fill_style)
	holder.add_child(fill)
	return holder


func rarity_color(rarity: String) -> Color:
	match rarity:
		"rare": return palette.color("ui_rare")
		"uncommon": return palette.color("ui_good")
		_: return Color(0.55, 0.5, 0.42)
