class_name UiKit
extends RefCounted
## The single player-facing visual language. Screens own content and behavior;
## this kit owns typography, spacing, paper, hairlines, focus, and accents.
## Large HUD changes should start here instead of restyling individual panels.

const FONT_BODY_PATH := "res://assets/fonts/Fredoka-Medium.ttf"
const FONT_DISPLAY_PATH := "res://assets/fonts/Fredoka-SemiBold.ttf"
const UI_THEME_PATH := "res://assets/ui/suma_ui_theme.tres"

const HUD_MARGIN := 22.0
const HUD_GAP := 10
const PANEL_GAP := 18
const HAIRLINE := 1
const FOCUS_LINE := 2
const CORNER_SMALL := 10
const CORNER_SHEET := 18
const PAPER_ALPHA := 0.985

var palette: CozyPalette
var font: Font
var font_bold: Font
var font_display: Font
var font_display_bold: Font
var theme: Theme
var tokens: SumaUiTheme
var reduced_motion := false


func _init(pal: CozyPalette) -> void:
	palette = pal
	tokens = load(UI_THEME_PATH) as SumaUiTheme
	assert(tokens != null, "Suma UI theme tokens must load")
	font = load(FONT_BODY_PATH)
	font_bold = load(FONT_DISPLAY_PATH)
	font_display = font_bold
	font_display_bold = font_bold
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = tokens.body_font_size
	for control_type in [
		"Label", "Button", "CheckButton", "CheckBox", "OptionButton",
		"LineEdit", "TextEdit", "SpinBox", "TooltipLabel",
	]:
		for color_name in [
			"font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_hover_pressed_color",
			"font_disabled_color", "font_placeholder_color",
			"font_selected_color",
			"font_uneditable_color", "font_readonly_color",
		]:
			theme.set_color(color_name, control_type, ui_color("text"))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(ui_color("paper"), 0.42)
	focus.border_color = Color(ui_color("focus"), 0.82)
	focus.set_border_width_all(tokens.focus_width)
	focus.set_corner_radius_all(tokens.control_corner_radius)
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
	_configure_tooltip_theme()
	_configure_scroll_theme()


func ui_color(role: String, fallback := Color.MAGENTA) -> Color:
	return palette.color(tokens.token(role), fallback)


func motion_duration(duration: float) -> float:
	return 0.0 if reduced_motion else duration


func _configure_tooltip_theme() -> void:
	var tooltip := sheet_style()
	tooltip.bg_color = Color(ui_color("paper_raised"), 0.985)
	tooltip.set_content_margin_all(10)
	tooltip.content_margin_left = 13
	tooltip.content_margin_right = 13
	tooltip.set_border_width_all(0)
	theme.set_stylebox("panel", "TooltipPanel", tooltip)
	theme.set_font("font", "TooltipLabel", font)
	theme.set_font_size("font_size", "TooltipLabel", tokens.tooltip_font_size)
	theme.set_color("font_color", "TooltipLabel", ui_color("text"))


func _configure_scroll_theme() -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = ui_color("scroll_track")
	track.set_corner_radius_all(0)
	var thumb := StyleBoxFlat.new()
	thumb.bg_color = ui_color("scroll_thumb")
	thumb.set_corner_radius_all(0)
	var hover := thumb.duplicate() as StyleBoxFlat
	hover.bg_color = ui_color("scroll_thumb").lightened(0.08)
	for control_type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", control_type, track)
		theme.set_stylebox("scroll_focus", control_type, track)
		theme.set_stylebox("grabber", control_type, thumb)
		theme.set_stylebox("grabber_highlight", control_type, hover)
		theme.set_stylebox("grabber_pressed", control_type, hover)


func _font_variation(base: Font, weight: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = base
	variation.variation_opentype = {"wght": weight}
	return variation


func panel_style(dark := false, radius := 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var background := (
		palette.color("ui_panel_dark") if dark
		else ui_color("paper")
	)
	style.bg_color = Color(background, background.a if dark else PAPER_ALPHA)
	style.set_corner_radius_all(mini(radius, tokens.sheet_corner_radius))
	style.set_content_margin_all(16)
	style.border_color = (
		Color(palette.color("ui_text_inverse"), 0.26)
		if dark else hairline_color()
	)
	style.set_border_width_all(0 if not dark else tokens.hairline_width)
	style.anti_aliasing = true
	style.shadow_size = 0
	style.shadow_color = Color.TRANSPARENT
	return style


func cloud_panel_style(radius := 30) -> StyleBoxFlat:
	var style := sheet_style()
	style.set_corner_radius_all(mini(radius, tokens.sheet_corner_radius))
	style.bg_color = Color(ui_color("paper_raised"), 0.99)
	style.set_content_margin_all(24)
	return style


func text_color(_dark_background := false) -> Color:
	return ui_color("text")


func hairline_color() -> Color:
	return ui_color("divider")


func paper_color(alpha := PAPER_ALPHA) -> Color:
	return Color(ui_color("paper"), alpha)


func sheet_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(ui_color("paper"), 0.99)
	style.set_corner_radius_all(tokens.sheet_corner_radius)
	style.set_content_margin_all(tokens.sheet_padding)
	style.border_color = Color(ui_color("divider"), 0.72)
	style.set_border_width_all(0)
	style.border_width_top = tokens.hairline_width
	style.anti_aliasing = true
	style.shadow_size = 0
	style.shadow_color = Color.TRANSPARENT
	return style


func overlay_scrim(alpha := 0.045) -> Color:
	var source := ui_color("text")
	return Color(source.r, source.g, source.b, alpha)


func inventory_cell_style(
	state: String,
	selected := false,
	available := true
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var color_role := "cell"
	if state in ["hover", "focus"]:
		color_role = "cell_hover"
	elif state == "pressed":
		color_role = "cell_pressed"
	style.bg_color = ui_color(color_role)
	if not available:
		style.bg_color.a *= 0.52
	style.set_corner_radius_all(tokens.cell_corner_radius)
	style.set_content_margin_all(0)
	style.set_border_width_all(0)
	style.shadow_size = 0
	style.shadow_color = Color.TRANSPARENT
	if selected:
		style.border_color = Color(ui_color("selection"), 0.84)
		style.set_border_width_all(tokens.hairline_width)
	elif state == "focus":
		style.border_color = Color(ui_color("focus"), 0.76)
		style.set_border_width_all(tokens.focus_width)
	return style


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
	var l := label(
		text.to_upper(), maxi(size, tokens.utility_font_size), false, true
	)
	l.add_theme_color_override(
		"font_color",
		text_color()
	)
	l.add_theme_constant_override("letter_spacing", 1)
	return l


func button(text: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", tokens.body_font_size)
	var normal := StyleBoxFlat.new()
	normal.bg_color = (
		ui_color("accent") if accent
		else Color(ui_color("paper"), 0.0)
	)
	normal.set_corner_radius_all(tokens.control_corner_radius)
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.border_color = (
		ui_color("accent") if accent else hairline_color()
	)
	normal.set_border_width_all(tokens.hairline_width if accent else 0)
	if not accent:
		normal.border_width_bottom = tokens.hairline_width
	var hover := normal.duplicate()
	hover.bg_color = (
		normal.bg_color.lightened(0.06)
		if accent else Color(ui_color("cell_hover"), 0.82)
	)
	var pressed := normal.duplicate()
	pressed.bg_color = (
		normal.bg_color.darkened(0.08)
		if accent else Color(ui_color("cell_pressed"), 0.9)
	)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(ui_color("cell"), 0.34)
	disabled.border_color = Color(hairline_color(), 0.45)
	var focus := normal.duplicate()
	focus.bg_color = (
		normal.bg_color.lightened(0.04)
		if accent else Color(ui_color("cell_hover"), 0.8)
	)
	focus.border_color = Color(ui_color("focus"), 0.82)
	focus.set_border_width_all(tokens.focus_width)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", focus)
	for color_name in [
		"font_color", "font_hover_color", "font_pressed_color",
		"font_focus_color", "font_disabled_color",
	]:
		b.add_theme_color_override(color_name, text_color())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func icon_button(symbol := "×", size := 42.0) -> Button:
	var b := button(symbol)
	b.custom_minimum_size = Vector2(size, size)
	b.add_theme_font_size_override("font_size", int(size * 0.48))
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


func minimal_icon_button(
	symbol: String,
	description: String,
	hit_size := 34.0
) -> Button:
	var b := Button.new()
	b.text = symbol
	b.tooltip_text = description
	b.custom_minimum_size = Vector2.ONE * hit_size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 19)
	for state in ["normal", "disabled"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(ui_color("cell_hover"), 0.68)
	hover.set_corner_radius_all(tokens.control_corner_radius)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(ui_color("cell_pressed"), 0.8)
	var focus := hover.duplicate() as StyleBoxFlat
	focus.border_color = Color(ui_color("focus"), 0.78)
	focus.set_border_width_all(tokens.focus_width)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	for color_name in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
		"font_disabled_color",
	]:
		b.add_theme_color_override(color_name, text_color())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
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
	var style := sheet_style()
	style.bg_color = Color(ui_color("paper_raised"), 0.995)
	style.set_content_margin_all(tokens.sheet_padding)
	style.border_color = hairline_color()
	style.set_border_width_all(0)
	style.border_width_top = tokens.hairline_width
	return style


func hud_tooltip_style(accent := Color.TRANSPARENT) -> StyleBoxFlat:
	var style := panel_style(false, CORNER_SMALL)
	style.bg_color = paper_color(0.975)
	style.set_content_margin_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.set_border_width_all(0)
	style.shadow_size = 0
	style.shadow_color = Color.TRANSPARENT
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
	normal.bg_color = Color(ui_color("paper"), 0.18)
	normal.set_corner_radius_all(0)
	normal.content_margin_left = 4
	normal.content_margin_right = 4
	normal.content_margin_top = 9
	normal.content_margin_bottom = 9
	normal.border_color = hairline_color()
	normal.border_width_bottom = tokens.hairline_width
	line_edit.add_theme_stylebox_override("normal", normal)
	line_edit.add_theme_stylebox_override("read_only", normal)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = ui_color("focus")
	focus.border_width_bottom = tokens.focus_width
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
	b.add_theme_color_override("font_pressed_color", text_color())
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
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(color_name, text_color())
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
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(color_name, text_color())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func library_visual_item_button(
	display_name: String,
	count: int
) -> Dictionary:
	var button := InventoryItemCell.new()
	button.setup(self, display_name, count)
	return {
		"button": button,
		"preview": button.preview,
		"badge": button.quantity_label,
	}


func style_library_scrollbar(scroll: ScrollContainer) -> void:
	style_minimal_scrollbar(scroll)


func style_minimal_scrollbar(scroll: ScrollContainer) -> void:
	var horizontal := scroll.get_h_scroll_bar()
	var vertical := scroll.get_v_scroll_bar()
	horizontal.custom_minimum_size.y = tokens.scrollbar_width
	vertical.custom_minimum_size.x = tokens.scrollbar_width
	var track := StyleBoxFlat.new()
	track.bg_color = ui_color("scroll_track")
	track.set_corner_radius_all(0)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = ui_color("scroll_thumb")
	grabber.set_corner_radius_all(0)
	var grabber_hover := grabber.duplicate()
	grabber_hover.bg_color = ui_color("scroll_thumb").lightened(0.08)
	var grabber_pressed := grabber.duplicate()
	grabber_pressed.bg_color = ui_color("scroll_thumb").darkened(0.04)
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
	b.add_theme_color_override("font_color", text_color())
	b.add_theme_color_override("font_hover_color", text_color())
	b.add_theme_color_override("font_pressed_color", text_color())
	b.add_theme_color_override(
		"font_disabled_color",
		text_color()
	)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func menu_button(text: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(370, 52)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 22)
	var normal := StyleBoxFlat.new()
	normal.bg_color = palette.color("ui_transparent")
	normal.set_corner_radius_all(CORNER_SMALL)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	normal.border_color = hairline_color()
	normal.border_width_bottom = HAIRLINE
	var hover := normal.duplicate()
	hover.bg_color = Color(ui_color("cell_hover"), 0.72)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(ui_color("cell_pressed"), 0.82)
	var focus := normal.duplicate()
	focus.bg_color = Color(ui_color("cell_hover"), 0.62)
	focus.border_color = ui_color("focus")
	focus.set_border_width_all(tokens.focus_width)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	var color := text_color()
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", color)
	b.add_theme_color_override("font_pressed_color", color)
	b.add_theme_color_override("font_focus_color", color)
	b.add_theme_color_override("font_disabled_color", color)
	if accent:
		normal.bg_color = ui_color("accent")
		hover.bg_color = normal.bg_color.lightened(0.06)
		pressed.bg_color = normal.bg_color.darkened(0.06)
		focus.bg_color = normal.bg_color.lightened(0.03)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func section_label(text: String) -> Label:
	var l := utility_label(text, 12)
	l.add_theme_color_override("font_color", text_color())
	return l


func keycap(text: String, minimum_width := 42.0) -> PanelContainer:
	var cap := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(ui_color("cell"), 0.9)
	style.set_corner_radius_all(CORNER_SMALL)
	style.set_content_margin_all(5)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.border_width_bottom = tokens.hairline_width
	style.border_color = ui_color("divider")
	cap.add_theme_stylebox_override("panel", style)
	cap.custom_minimum_size.x = minimum_width
	var l := label(text, 13, false, true)
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
	scrim.color = overlay_scrim()
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var c := card(size)
	c.add_theme_stylebox_override("panel", sheet_style())
	center.add_child(c)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	c.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title_label := display_label(title, tokens.title_font_size)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close := minimal_icon_button("×", "Close")
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
	style.set_corner_radius_all(mini(radius, tokens.sheet_corner_radius))
	style.set_content_margin_all(14)
	style.border_color = border
	style.set_border_width_all(border_width)
	style.anti_aliasing = true
	style.shadow_size = 0
	style.shadow_color = Color.TRANSPARENT
	return style


func progression_panel_style(accent: Color, radius := 18) -> StyleBoxFlat:
	var style := surface_style(
		Color(ui_color("cell"), 0.56),
		mini(radius, tokens.sheet_corner_radius),
		Color(ui_color("divider"), 0.72),
		tokens.hairline_width
	)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.set_border_width_all(0)
	style.border_width_left = tokens.hairline_width
	style.border_color = Color(accent, 0.46)
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
	l.add_theme_color_override("font_color", text_color())
	return l


func pill(text: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := surface_style(
		Color(accent, 0.08),
		tokens.sheet_corner_radius,
		Color(accent, 0.34),
		tokens.hairline_width
	)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var l := label(text, 11, false, true)
	l.add_theme_color_override("font_color", text_color())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(l)
	return panel


func monogram(glyph: String, accent: Color, size := 42.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(size, size)
	var style := surface_style(Color(accent, 0.1), tokens.sheet_corner_radius)
	style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", style)
	var l := label(glyph, int(size * 0.42), false, true)
	l.add_theme_color_override("font_color", text_color())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(l)
	return panel


func divider(color := Color.TRANSPARENT) -> ColorRect:
	var line := ColorRect.new()
	line.color = ui_color("divider") if color.a <= 0.0 else color
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
