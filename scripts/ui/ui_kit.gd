class_name UiKit
extends RefCounted
## The single player-facing visual language. Screens own content and behavior;
## this kit owns typography, spacing, paper, hairlines, focus, and accents.
## Large HUD changes should start here instead of restyling individual panels.

const FONT_BODY_PATH := "res://assets/fonts/Manrope-Variable.ttf"
const FONT_DISPLAY_PATH := "res://assets/fonts/LibreBaskerville-Variable.ttf"

const HUD_MARGIN := 22.0
const HUD_GAP := 10
const PANEL_GAP := 18
const HAIRLINE := 1
const FOCUS_LINE := 2
const CORNER_SMALL := 2
const CORNER_SHEET := 6
const PAPER_ALPHA := 0.985

var palette: CozyPalette
var font: Font
var font_bold: Font
var font_display: Font
var font_display_bold: Font
var theme: Theme


func _init(pal: CozyPalette) -> void:
	palette = pal
	font = _font_variation(load(FONT_BODY_PATH), 430)
	font_bold = _font_variation(load(FONT_BODY_PATH), 650)
	font_display = _font_variation(load(FONT_DISPLAY_PATH), 400)
	font_display_bold = _font_variation(load(FONT_DISPLAY_PATH), 600)
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 16
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(palette.color("ui_surface"), 0.72)
	focus.border_color = palette.color("ui_accent")
	focus.set_border_width_all(FOCUS_LINE)
	focus.set_corner_radius_all(CORNER_SMALL)
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


func _font_variation(base: Font, weight: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = base
	variation.variation_opentype = {"wght": weight}
	return variation


func panel_style(dark := false, radius := 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var background := (
		palette.color("ui_panel_dark") if dark
		else palette.color("ui_surface")
	)
	style.bg_color = Color(background, background.a if dark else PAPER_ALPHA)
	style.set_corner_radius_all(mini(radius, CORNER_SHEET))
	style.set_content_margin_all(16)
	style.border_color = (
		Color(palette.color("ui_text_inverse"), 0.26)
		if dark else hairline_color()
	)
	style.set_border_width_all(HAIRLINE)
	style.anti_aliasing = true
	return style


func cloud_panel_style(radius := 30) -> StyleBoxFlat:
	var style := panel_style(false, mini(radius, CORNER_SHEET))
	style.bg_color = Color(palette.color("ui_surface_raised"), 0.985)
	style.set_content_margin_all(32)
	return style


func text_color(dark_background := false) -> Color:
	return palette.color("ui_text_inverse" if dark_background else "ui_text_primary")


func hairline_color() -> Color:
	return Color(palette.color("ui_text_primary"), 0.24)


func paper_color(alpha := PAPER_ALPHA) -> Color:
	return Color(palette.color("ui_surface"), alpha)


func label(text: String, size := 18, dark_background := false, strong := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold if strong else font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", text_color(dark_background))
	return l


func display_label(
	text: String,
	size := 30,
	dark_background := false,
	strong := false
) -> Label:
	var l := label(text, size, dark_background, false)
	l.add_theme_font_override(
		"font", font_display_bold if strong else font_display
	)
	l.add_theme_constant_override("line_spacing", maxi(0, int(size * 0.08)))
	return l


func utility_label(text: String, size := 12, accent := Color.TRANSPARENT) -> Label:
	var l := label(text.to_upper(), size, false, true)
	l.add_theme_color_override(
		"font_color",
		palette.color("ui_text_secondary") if accent.a <= 0.0 else accent
	)
	l.add_theme_constant_override("letter_spacing", 1)
	return l


func button(text: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 15)
	var normal := StyleBoxFlat.new()
	normal.bg_color = (
		palette.color("ui_accent") if accent
		else Color(palette.color("ui_surface"), 0.0)
	)
	normal.set_corner_radius_all(CORNER_SMALL)
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.border_color = (
		palette.color("ui_accent") if accent else hairline_color()
	)
	normal.set_border_width_all(HAIRLINE)
	var hover := normal.duplicate()
	hover.bg_color = (
		normal.bg_color.lightened(0.06)
		if accent else Color(palette.color("ui_surface_soft"), 0.48)
	)
	var pressed := normal.duplicate()
	pressed.bg_color = (
		normal.bg_color.darkened(0.08)
		if accent else Color(palette.color("ui_surface_soft"), 0.72)
	)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(palette.color("ui_surface_disabled"), 0.24)
	disabled.border_color = Color(hairline_color(), 0.45)
	var focus := normal.duplicate()
	focus.bg_color = (
		normal.bg_color.lightened(0.04)
		if accent else Color(palette.color("ui_surface"), 0.78)
	)
	focus.border_color = palette.color("ui_accent")
	focus.set_border_width_all(FOCUS_LINE)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", palette.color("ui_white") if accent else text_color())
	b.add_theme_color_override("font_hover_color", palette.color("ui_white") if accent else text_color())
	b.add_theme_color_override("font_focus_color", palette.color("ui_white") if accent else text_color())
	b.add_theme_color_override("font_disabled_color", palette.color("ui_text_disabled"))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func icon_button(symbol := "×", size := 42.0) -> Button:
	var b := button(symbol)
	b.custom_minimum_size = Vector2(size, size)
	b.add_theme_font_size_override("font_size", int(size * 0.48))
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


func compact_button(text: String, height := 30.0) -> Button:
	var b := button(text)
	b.custom_minimum_size.y = height
	b.add_theme_font_size_override("font_size", 12)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var source := b.get_theme_stylebox(state)
		if source == null:
			continue
		var style := source.duplicate() as StyleBoxFlat
		style.set_corner_radius_all(CORNER_SMALL)
		style.content_margin_left = 9
		style.content_margin_right = 9
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		b.add_theme_stylebox_override(state, style)
	return b


func hud_chip(text: String, accent: Color) -> Button:
	var b := button(text)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(260, 46)
	b.add_theme_font_size_override("font_size", 14)
	apply_hud_chip_style(b, accent)
	return b


func apply_hud_chip_style(button_node: Button, accent: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := hud_chip_style(accent, state)
		button_node.add_theme_stylebox_override(state, style)


func place_hud_chip(
	control: Control,
	right_side := false,
	width := 260.0,
	height := 46.0
) -> void:
	## All persistent corner HUD uses one shared safe margin and footprint.
	control.set_anchors_preset(
		Control.PRESET_TOP_RIGHT if right_side else Control.PRESET_TOP_LEFT
	)
	control.offset_top = HUD_MARGIN
	control.offset_bottom = HUD_MARGIN + height
	if right_side:
		control.offset_left = -HUD_MARGIN - width
		control.offset_right = -HUD_MARGIN
	else:
		control.offset_left = HUD_MARGIN
		control.offset_right = HUD_MARGIN + width


func hud_chip_style(accent: Color, state := "normal") -> StyleBoxFlat:
	var style := panel_style(false, CORNER_SMALL)
	style.bg_color = paper_color(
		1.0 if state in ["hover", "focus"] else 0.985
	)
	style.set_content_margin_all(10)
	style.content_margin_left = 16
	style.border_color = accent if state != "disabled" else hairline_color()
	style.set_border_width_all(0)
	style.border_width_left = 4
	style.border_width_bottom = HAIRLINE
	if state == "focus":
		style.border_width_top = FOCUS_LINE
		style.border_width_right = FOCUS_LINE
		style.border_width_bottom = FOCUS_LINE
	return style


func hud_dock_style() -> StyleBoxFlat:
	var style := panel_style(false, CORNER_SHEET)
	style.bg_color = Color(palette.color("ui_surface_raised"), 0.995)
	style.set_content_margin_all(22)
	style.border_color = hairline_color()
	style.set_border_width_all(HAIRLINE)
	style.border_width_top = 2
	return style


func hud_tooltip_style(accent := Color.TRANSPARENT) -> StyleBoxFlat:
	var style := panel_style(false, CORNER_SMALL)
	style.bg_color = paper_color(0.975)
	style.set_content_margin_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.set_border_width_all(0)
	style.border_width_bottom = HAIRLINE
	style.border_color = hairline_color() if accent.a <= 0.0 else accent
	return style


func controller_hint_style() -> StyleBoxFlat:
	var style := hud_tooltip_style()
	style.bg_color = paper_color(0.985)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func drop_target_style() -> StyleBoxFlat:
	var style := hud_dock_style()
	style.bg_color = Color(palette.color("ui_drop_surface"), 0.96)
	style.border_color = palette.color("ui_drop_border")
	style.set_border_width_all(FOCUS_LINE)
	style.set_corner_radius_all(CORNER_SMALL)
	return style


func badge_style(accent: Color, padding := 5) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = accent
	style.set_corner_radius_all(CORNER_SMALL)
	style.set_content_margin_all(padding)
	return style


func style_line_edit(line_edit: LineEdit) -> void:
	line_edit.add_theme_font_override("font", font)
	line_edit.add_theme_font_size_override("font_size", 15)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(palette.color("ui_surface"), 0.22)
	normal.set_corner_radius_all(0)
	normal.content_margin_left = 4
	normal.content_margin_right = 4
	normal.content_margin_top = 9
	normal.content_margin_bottom = 9
	normal.border_color = hairline_color()
	normal.border_width_bottom = HAIRLINE
	line_edit.add_theme_stylebox_override("normal", normal)
	line_edit.add_theme_stylebox_override("read_only", normal)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = palette.color("ui_accent")
	focus.border_width_bottom = FOCUS_LINE
	line_edit.add_theme_stylebox_override("focus", focus)


func accent_square(color: Color, size := 9.0) -> ColorRect:
	var square := ColorRect.new()
	square.color = color
	square.custom_minimum_size = Vector2(size, size)
	square.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return square


func collection_accent(collection_id: String) -> Color:
	var key := collection_id.to_lower()
	if "fish" in key or "water" in key or "shore" in key:
		return palette.color("ui_journal_fish")
	if "stone" in key or "mountain" in key or "relic" in key:
		return palette.color("ui_journal_structures")
	if "wood" in key or "grove" in key or "nature" in key:
		return palette.color("ui_journal_woodland")
	if "land" in key or "tile" in key:
		return palette.color("ui_journal_tiles")
	return palette.color("ui_accent")


func choice_button(text: String, selected := false) -> Button:
	var b := button(text, false)
	b.toggle_mode = true
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = palette.color("ui_accent")
	selected_style.set_corner_radius_all(CORNER_SMALL)
	selected_style.set_content_margin_all(11)
	selected_style.content_margin_left = 18
	selected_style.content_margin_right = 18
	selected_style.border_color = palette.color("ui_accent")
	selected_style.set_border_width_all(HAIRLINE)
	b.add_theme_stylebox_override("pressed", selected_style)
	b.add_theme_color_override("font_pressed_color", palette.color("ui_white"))
	b.set_pressed_no_signal(selected)
	return b


func library_category_button(text: String, selected := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.custom_minimum_size = Vector2(70, 34)
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 13)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(palette.color("ui_surface"), 0.0)
	normal.set_corner_radius_all(0)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	normal.border_color = Color(hairline_color(), 0.0)
	normal.border_width_bottom = 2
	var hover := normal.duplicate()
	hover.bg_color = Color(palette.color("ui_category_hover"), 0.34)
	hover.border_color = hairline_color()
	var pressed := normal.duplicate()
	pressed.bg_color = Color(palette.color("ui_surface"), 0.0)
	pressed.border_color = palette.color("ui_good")
	var focus := pressed.duplicate()
	focus.set_border_width_all(FOCUS_LINE)
	focus.border_color = palette.color("ui_accent")
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", palette.color("ui_text_primary"))
	b.add_theme_color_override("font_hover_color", palette.color("ui_text_primary"))
	b.add_theme_color_override("font_pressed_color", palette.color("ui_text_primary"))
	b.add_theme_color_override("font_focus_color", palette.color("ui_text_primary"))
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
	normal.bg_color = Color(palette.color("ui_card"), 0.32)
	normal.set_corner_radius_all(CORNER_SMALL)
	normal.content_margin_left = 17
	normal.content_margin_right = 17
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate()
	hover.bg_color = Color(palette.color("ui_card_hover"), 0.6)
	hover.border_color = hairline_color()
	hover.set_border_width_all(HAIRLINE)
	var pressed := normal.duplicate()
	pressed.bg_color = palette.color("ui_accent").lightened(0.12)
	var focus := hover.duplicate()
	focus.set_border_width_all(FOCUS_LINE)
	focus.border_color = palette.color("ui_accent")
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", palette.color("ui_text_primary"))
	b.add_theme_color_override("font_hover_color", palette.color("ui_text_primary"))
	b.add_theme_color_override("font_pressed_color", palette.color("ui_white"))
	b.add_theme_color_override("font_focus_color", palette.color("ui_text_primary"))
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
	normal.bg_color = Color(palette.color("ui_visual_card"), 0.28)
	normal.set_corner_radius_all(CORNER_SMALL)
	normal.set_content_margin_all(0)
	normal.border_color = hairline_color()
	normal.set_border_width_all(HAIRLINE)
	var hover := normal.duplicate()
	hover.bg_color = Color(palette.color("ui_surface_selected"), 0.7)
	hover.border_color = palette.color("ui_good")
	var pressed := hover.duplicate()
	pressed.bg_color = palette.color("ui_accent").lightened(0.2)
	var focus := hover.duplicate()
	focus.border_color = palette.color("ui_accent")
	focus.set_border_width_all(FOCUS_LINE)
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

	# A visible ×1 matters: without it, the last owned piece reads as an
	# unlimited catalogue recipe instead of finite inventory.
	var badge := PanelContainer.new()
	badge.name = "CountBadge"
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.position = Vector2(-9, 9)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = palette.color("ui_good")
	badge_style.set_corner_radius_all(CORNER_SMALL)
	badge_style.content_margin_left = 8
	badge_style.content_margin_right = 8
	badge_style.content_margin_top = 4
	badge_style.content_margin_bottom = 4
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
	track.bg_color = Color(palette.color("ui_track"), 0.42)
	track.set_corner_radius_all(0)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = palette.color("ui_good")
	grabber.set_corner_radius_all(0)
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
	normal.bg_color = Color(palette.color("ui_arrow"), 0.28)
	normal.set_corner_radius_all(CORNER_SMALL)
	normal.border_color = hairline_color()
	normal.set_border_width_all(HAIRLINE)
	var hover := normal.duplicate()
	hover.bg_color = palette.color("ui_arrow_hover")
	var pressed := normal.duplicate()
	pressed.bg_color = palette.color("ui_good")
	var disabled := normal.duplicate()
	disabled.bg_color = palette.color("ui_arrow_disabled")
	var focus := hover.duplicate()
	focus.border_color = palette.color("ui_accent")
	focus.set_border_width_all(FOCUS_LINE)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", palette.color("ui_text_primary"))
	b.add_theme_color_override("font_hover_color", palette.color("ui_text_primary"))
	b.add_theme_color_override("font_pressed_color", palette.color("ui_white"))
	b.add_theme_color_override(
		"font_disabled_color",
		Color(palette.color("ui_text_disabled"), 0.3)
	)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func menu_button(text: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(370, 62)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", font_display)
	b.add_theme_font_size_override("font_size", 24)
	var normal := StyleBoxFlat.new()
	normal.bg_color = palette.color("ui_transparent")
	normal.set_corner_radius_all(CORNER_SMALL)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 13
	normal.content_margin_bottom = 13
	normal.border_color = hairline_color()
	normal.border_width_bottom = HAIRLINE
	var hover := normal.duplicate()
	hover.bg_color = palette.color("ui_menu_hover")
	var pressed := normal.duplicate()
	pressed.bg_color = palette.color("ui_surface_pressed")
	var focus := normal.duplicate()
	focus.bg_color = palette.color("ui_menu_focus")
	focus.border_color = palette.color("ui_accent")
	focus.set_border_width_all(FOCUS_LINE)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	var color := palette.color("ui_text_inverse") if accent else text_color()
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", color)
	b.add_theme_color_override("font_pressed_color", color)
	b.add_theme_color_override("font_focus_color", color)
	if accent:
		normal.bg_color = palette.color("ui_good")
		hover.bg_color = normal.bg_color.lightened(0.06)
		pressed.bg_color = normal.bg_color.darkened(0.06)
		focus.bg_color = normal.bg_color.lightened(0.03)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func section_label(text: String) -> Label:
	var l := utility_label(text, 12)
	l.add_theme_color_override("font_color", palette.color("ui_text_secondary"))
	return l


func keycap(text: String, minimum_width := 42.0) -> PanelContainer:
	var cap := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = palette.color("ui_tooltip")
	style.set_corner_radius_all(CORNER_SMALL)
	style.set_content_margin_all(5)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.border_width_bottom = 2
	style.border_color = palette.color("ui_border_dark")
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
	scrim.color = palette.color("ui_scrim")
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
	var title_label := display_label(title, 30)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close := icon_button("×")
	header.add_child(close)
	return {"root": root, "card": c, "content": content, "close": close}


func surface_style(
	background: Color,
	radius := 16,
	border := Color.TRANSPARENT,
	border_width := 0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.set_corner_radius_all(mini(radius, CORNER_SHEET))
	style.set_content_margin_all(14)
	style.border_color = border
	style.set_border_width_all(border_width)
	style.anti_aliasing = true
	return style


func progression_panel_style(accent: Color, radius := 18) -> StyleBoxFlat:
	var style := surface_style(
		Color(palette.color("ui_progression_surface"), 0.5),
		mini(radius, CORNER_SMALL),
		hairline_color(),
		HAIRLINE
	)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.border_width_top = 3
	style.border_color = accent
	return style


func progression_card(minimum: Vector2, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.add_theme_stylebox_override("panel", progression_panel_style(accent))
	return panel


func eyebrow(text: String, accent := Color.TRANSPARENT) -> Label:
	if accent.a <= 0.0:
		accent = palette.color("ui_eyebrow")
	var l := utility_label(text, 11, accent.darkened(0.08))
	return l


func muted_label(text: String, size := 14) -> Label:
	var l := label(text, size)
	l.add_theme_color_override("font_color", palette.color("ui_text_secondary"))
	return l


func pill(text: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := surface_style(accent, CORNER_SMALL, accent, HAIRLINE)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var l := label(text, 11, true, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(l)
	return panel


func monogram(glyph: String, accent: Color, size := 42.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(size, size)
	var style := surface_style(accent, CORNER_SMALL)
	style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", style)
	var l := label(glyph, int(size * 0.46), true, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(l)
	return panel


func divider(color := Color.TRANSPARENT) -> ColorRect:
	var line := ColorRect.new()
	line.color = palette.color("ui_divider") if color.a <= 0.0 else color
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
	back.bg_color = palette.color("ui_progress_track")
	back.set_corner_radius_all(0)
	holder.add_theme_stylebox_override("panel", back)
	var fill := PanelContainer.new()
	fill.custom_minimum_size = Vector2(
		maxf(0.0, width * clampf(fraction, 0.0, 1.0)),
		height
	)
	fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.set_corner_radius_all(0)
	fill.add_theme_stylebox_override("panel", fill_style)
	holder.add_child(fill)
	return holder


func rarity_color(rarity: String) -> Color:
	match rarity:
		"rare": return palette.color("ui_rare")
		"uncommon": return palette.color("ui_good")
		_: return palette.color("ui_rarity_common")
