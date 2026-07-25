class_name UiKit
extends RefCounted
## Shared UI vocabulary: warm cream cards, chunky rounded corners, dark warm
## text. Every panel and button in the game is built through these helpers so
## the interface reads as one hand.

const FONT_PATH := "res://assets/fonts/Knightwood.ttf"

var palette: CozyPalette
var font: FontFile
var theme: Theme


func _init(pal: CozyPalette) -> void:
	palette = pal
	font = load(FONT_PATH)
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 17


func panel_style(dark := false, radius := 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = palette.color("ui_panel_dark") if dark else palette.color("ui_panel")
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(14)
	style.border_width_bottom = 3
	style.border_color = Color(0, 0, 0, 0.12)
	return style


func text_color(dark_background := false) -> Color:
	return Color(0.95, 0.93, 0.88) if dark_background else Color(0.24, 0.2, 0.15)


func label(text: String, size := 17, dark_background := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", text_color(dark_background))
	return l


func button(text: String, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 17)
	var normal := StyleBoxFlat.new()
	normal.bg_color = palette.color("ui_accent") if accent else Color(0.88, 0.85, 0.78)
	normal.set_corner_radius_all(9)
	normal.set_content_margin_all(8)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.border_width_bottom = 3
	normal.border_color = Color(0, 0, 0, 0.18)
	var hover := normal.duplicate()
	hover.bg_color = normal.bg_color.lightened(0.08)
	var pressed := normal.duplicate()
	pressed.bg_color = normal.bg_color.darkened(0.08)
	pressed.border_width_bottom = 1
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.8, 0.78, 0.73, 0.6)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", Color.WHITE if accent else text_color())
	b.add_theme_color_override("font_hover_color", Color.WHITE if accent else text_color())
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.47, 0.42))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func card(minimum := Vector2(0, 0), dark := false) -> PanelContainer:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", panel_style(dark))
	c.custom_minimum_size = minimum
	return c


func window(title: String, size: Vector2) -> Dictionary:
	## Returns {root (centered overlay), card, content (VBox), close (Button)}.
	var root := CenterContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks behind the panel
	var c := card(size)
	root.add_child(c)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	c.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title_label := label(title, 24)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close := button("✕")
	header.add_child(close)
	return {"root": root, "card": c, "content": content, "close": close}


func progress_bar(fraction: float, color_key := "ui_good", width := 120) -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(width, 10)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.15)
	back.set_corner_radius_all(5)
	holder.add_theme_stylebox_override("panel", back)
	var fill := ColorRect.new()
	fill.color = palette.color(color_key)
	fill.custom_minimum_size = Vector2(maxf(0.0, width * clampf(fraction, 0.0, 1.0)), 10)
	fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.add_child(fill)
	return holder


func rarity_color(rarity: String) -> Color:
	match rarity:
		"rare": return palette.color("ui_rare")
		"uncommon": return palette.color("ui_good")
		_: return Color(0.55, 0.5, 0.42)
