class_name CharacterCreator
extends CanvasLayer
## Compact new-game customization. The live character stands in the world
## behind the panel and updates instantly with every choice. No stats, no
## classes — identity only.

signal creation_finished(profile: PlayerProfile)

var kit: UiKit
var palette: CozyPalette
var profile := PlayerProfile.new()
var _preview_callback: Callable
var _root: Control
var _name_edit: LineEdit


func setup(ui_kit: UiKit, pal: CozyPalette, preview_callback: Callable) -> void:
	kit = ui_kit
	palette = pal
	_preview_callback = preview_callback
	_build()
	_preview()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var card := kit.card(Vector2(340, 0))
	card.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	card.position.x = 40
	card.grow_horizontal = Control.GROW_DIRECTION_END
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)
	col.add_child(kit.label("A tiny world is waiting.", 24))
	col.add_child(kit.label("Who tends it?", 16))

	col.add_child(kit.label("Name", 15))
	_name_edit = LineEdit.new()
	_name_edit.text = "Keeper"
	_name_edit.max_length = 18
	_name_edit.add_theme_font_override("font", kit.font)
	col.add_child(_name_edit)

	col.add_child(_swatch_row("Skin", palette.skin_tones, func(i): profile.skin_index = i))
	col.add_child(_choice_row("Hair style", ["Bowl", "Crop", "Bun", "Long"], func(i): profile.hair_style = i))
	col.add_child(_swatch_row("Hair color", palette.hair_colors, func(i): profile.hair_color_index = i))
	col.add_child(_choice_row("Eyes", ["Wide", "Sleepy", "Bright"], func(i): profile.eye_index = i))
	col.add_child(_swatch_row("Outfit", palette.outfit_colors, func(i): profile.outfit_index = i))

	var begin := kit.button("Begin", true)
	begin.pressed.connect(_finish)
	col.add_child(begin)


func _swatch_row(label_text: String, colors: PackedColorArray, setter: Callable) -> Control:
	var col := VBoxContainer.new()
	col.add_child(kit.label(label_text, 15))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(34, 34)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var style := StyleBoxFlat.new()
		style.bg_color = colors[i]
		style.set_corner_radius_all(17)
		style.border_width_bottom = 2
		style.border_color = Color(0, 0, 0, 0.2)
		b.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.border_color = Color(1, 1, 1, 0.8)
		hover.set_border_width_all(2)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)
		var index := i
		b.pressed.connect(func():
			setter.call(index)
			_preview())
		row.add_child(b)
	return col


func _choice_row(label_text: String, names: Array, setter: Callable) -> Control:
	var col := VBoxContainer.new()
	col.add_child(kit.label(label_text, 15))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	for i in names.size():
		var b := kit.button(names[i])
		var index := i
		b.pressed.connect(func():
			setter.call(index)
			_preview())
		row.add_child(b)
	return col


func _preview() -> void:
	if _preview_callback.is_valid():
		_preview_callback.call(profile)


func _finish() -> void:
	profile.display_name = _name_edit.text.strip_edges()
	if profile.display_name == "":
		profile.display_name = "Keeper"
	_root.queue_free()
	creation_finished.emit(profile)
	queue_free()
