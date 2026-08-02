class_name CharacterCreator
extends CanvasLayer
## Full-screen new-game customization. The world does not exist yet — the
## live character stands alone against the soft sky and updates instantly
## with every choice. The final step is the arrival land pick: the world
## literally begins from that choice. No stats, no classes — identity only.

signal creation_finished(profile: PlayerProfile)

const PART_CATALOG: CharacterPartCatalog = preload(
	"res://assets/characters/parts/catalog_male.tres"
)
const BODY_CATALOG: CharacterBodyCatalog = preload(
	"res://assets/characters/body_catalog.tres"
)

var kit: UiKit
var palette: CozyPalette
var _input_service: InputDeviceService
var profile := PlayerProfile.new()
var _preview_callback: Callable
var _land_options: Array = []   # [{id, label, description}]
var _root: Control
var _name_edit: LineEdit
var _first_choice: Control


func setup(
	ui_kit: UiKit,
	pal: CozyPalette,
	preview_callback: Callable,
	land_options: Array = []
) -> void:
	kit = ui_kit
	palette = pal
	_input_service = InputDeviceService.shared()
	_preview_callback = preview_callback
	_land_options = land_options
	if not _land_options.is_empty():
		profile.starter_land_id = String(_land_options[0].get("id", "tile_grass"))
	_build()
	_preview()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = kit.theme
	add_child(_root)
	_first_choice = null

	var card := kit.card(Vector2(448, 0))
	card.name = "KeeperProfileCard"
	card.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	card.offset_left = 32
	card.offset_top = 28
	card.offset_right = 480
	card.offset_bottom = -28
	card.add_theme_stylebox_override("panel", kit.cloud_panel_style(24))
	_root.add_child(card)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 13)
	card.add_child(shell)
	shell.add_child(kit.eyebrow("Keeper profile", palette.color("ui_accent")))
	shell.add_child(kit.label("Who tends this world?", 28, false, true))
	var intro := kit.muted_label(
		"Shape your keeper, then choose the first patch of land to call home.",
		14
	)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shell.add_child(intro)
	shell.add_child(kit.divider())

	var scroll := ScrollContainer.new()
	scroll.name = "CreatorOptions"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	kit.style_library_scrollbar(scroll)
	shell.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 13)
	scroll.add_child(form)

	form.add_child(_section_header("About you"))
	form.add_child(kit.label("Name", 14, false, true))
	_name_edit = LineEdit.new()
	_name_edit.name = "KeeperName"
	_name_edit.text = "Keeper"
	_name_edit.placeholder_text = "Keeper name"
	_name_edit.max_length = 18
	_name_edit.custom_minimum_size.y = 48
	_name_edit.add_theme_font_override("font", kit.font)
	_name_edit.add_theme_font_size_override("font_size", 17)
	_style_text_field(_name_edit)
	form.add_child(_name_edit)

	form.add_child(_section_header("Appearance"))
	form.add_child(_choice_dropdown(
		"Body",
		BODY_CATALOG.display_names(),
		profile.body_index,
		func(i): profile.body_index = i
	))
	form.add_child(_swatch_row(
		"Skin",
		(palette as PaletteDefinition).character_swatches("skin"),
		profile.skin_index,
		func(i): profile.skin_index = i
	))
	form.add_child(_choice_dropdown(
		"Hair style",
		PART_CATALOG.display_names(CharacterSlots.HAIR),
		profile.hair_style,
		func(i): profile.hair_style = i
	))
	form.add_child(_swatch_row(
		"Hair color",
		(palette as PaletteDefinition).character_swatches("hair"),
		profile.hair_color_index,
		func(i): profile.hair_color_index = i
	))
	form.add_child(_choice_dropdown(
		"Eyes",
		PART_CATALOG.display_names(CharacterSlots.EYES),
		profile.eye_index,
		func(i): profile.eye_index = i
	))
	form.add_child(_choice_dropdown(
		"Mouth",
		PART_CATALOG.display_names(CharacterSlots.MOUTH),
		profile.mouth_index,
		func(i): profile.mouth_index = i
	))
	form.add_child(_choice_dropdown(
		"Nose",
		PART_CATALOG.display_names(CharacterSlots.NOSE),
		profile.nose_index,
		func(i): profile.nose_index = i
	))
	form.add_child(_swatch_row(
		"Outfit",
		(palette as PaletteDefinition).character_swatches("outfit"),
		profile.outfit_index,
		func(i): profile.outfit_index = i
	))

	if not _land_options.is_empty():
		form.add_child(_section_header("Arrival"))
		var land_names := PackedStringArray()
		for option: Dictionary in _land_options:
			land_names.append(String(option.get("label", option.get("id", ""))))
		form.add_child(_choice_dropdown(
			"First land",
			land_names,
			0,
			func(i): profile.starter_land_id = String(_land_options[i].get("id", "tile_grass"))
		))
		var arrival_note := kit.muted_label(
			"This choice shapes the little island beneath your first steps.",
			13
		)
		arrival_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		form.add_child(arrival_note)

	shell.add_child(kit.divider())
	var begin := kit.button("Begin your world", true)
	begin.name = "BeginWorld"
	begin.custom_minimum_size.y = 50
	begin.tooltip_text = "Arrive — your first land takes shape beneath you."
	begin.pressed.connect(_finish)
	shell.add_child(begin)
	var change_note := kit.muted_label("Your appearance can be changed later.", 12)
	change_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell.add_child(change_note)
	focus_default()


func _section_header(text: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	col.add_child(kit.eyebrow(text, palette.color("ui_good")))
	col.add_child(kit.divider(palette.color("ui_good").lightened(0.28)))
	return col


func _style_text_field(field: LineEdit) -> void:
	var normal := kit.surface_style(palette.color("ui_creator_surface"), 12)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var hover := normal.duplicate()
	hover.bg_color = palette.color("ui_creator_hover")
	var focus := hover.duplicate()
	focus.border_color = palette.color("ui_accent").lightened(0.15)
	focus.set_border_width_all(3)
	field.add_theme_stylebox_override("normal", normal)
	field.add_theme_stylebox_override("read_only", normal)
	field.add_theme_stylebox_override("focus", focus)
	field.add_theme_color_override("font_color", kit.text_color())
	field.add_theme_color_override("caret_color", palette.color("ui_accent"))
	field.add_theme_color_override(
		"selection_color",
		palette.color("ui_accent").lightened(0.3)
	)


func _swatch_row(
	label_text: String,
	colors: PackedColorArray,
	selected_index: int,
	setter: Callable
) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.add_child(kit.label(label_text, 14, false, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for i in colors.size():
		var b := Button.new()
		b.name = "%sSwatch%d" % [label_text.replace(" ", ""), i]
		b.custom_minimum_size = Vector2(40, 40)
		b.toggle_mode = true
		b.button_group = group
		b.set_pressed_no_signal(i == selected_index)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = "%s %d of %d" % [
			label_text,
			i + 1,
			colors.size(),
		]
		var style := StyleBoxFlat.new()
		style.bg_color = colors[i]
		style.set_corner_radius_all(20)
		style.set_border_width_all(2)
		style.border_color = palette.color("ui_creator_border")
		b.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.border_color = palette.color("ui_creator_selected")
		hover.set_border_width_all(3)
		b.add_theme_stylebox_override("hover", hover)
		var selected := style.duplicate()
		selected.border_color = palette.color("ui_accent").lightened(0.12)
		selected.set_border_width_all(4)
		b.add_theme_stylebox_override("pressed", selected)
		b.add_theme_stylebox_override("hover_pressed", selected)
		var focus := selected.duplicate()
		focus.border_color = palette.color("ui_accent")
		focus.set_border_width_all(4)
		b.add_theme_stylebox_override("focus", focus)
		var index := i
		b.pressed.connect(func():
			setter.call(index)
			_preview())
		row.add_child(b)
		if _first_choice == null:
			_first_choice = b
	return col


func _choice_dropdown(
	label_text: String,
	names: PackedStringArray,
	selected_index: int,
	setter: Callable
) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.add_child(kit.label(label_text, 14, false, true))
	var selector := OptionButton.new()
	selector.custom_minimum_size = Vector2(250, 46)
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.add_theme_font_override("font", kit.font_bold)
	selector.add_theme_font_size_override("font_size", 16)
	selector.tooltip_text = "Choose %s" % label_text.to_lower()
	for option_name in names:
		selector.add_item(option_name)
	if not names.is_empty():
		selector.select(clampi(selected_index, 0, names.size() - 1))
	selector.item_selected.connect(func(index: int):
		setter.call(index)
		_preview())
	_style_selector(selector)
	col.add_child(selector)
	if _first_choice == null:
		_first_choice = selector
	return col


func _style_selector(selector: OptionButton) -> void:
	var normal := kit.surface_style(palette.color("ui_creator_surface"), 12)
	normal.content_margin_left = 14
	normal.content_margin_right = 12
	var hover := normal.duplicate()
	hover.bg_color = palette.color("ui_creator_hover")
	var pressed := hover.duplicate()
	pressed.bg_color = palette.color("ui_accent").lightened(0.34)
	var focus := hover.duplicate()
	focus.border_color = palette.color("ui_accent").lightened(0.15)
	focus.set_border_width_all(3)
	selector.add_theme_stylebox_override("normal", normal)
	selector.add_theme_stylebox_override("hover", hover)
	selector.add_theme_stylebox_override("pressed", pressed)
	selector.add_theme_stylebox_override("focus", focus)
	selector.add_theme_color_override("font_color", kit.text_color())
	selector.add_theme_color_override("font_hover_color", kit.text_color())
	selector.add_theme_color_override("font_pressed_color", kit.text_color())
	selector.add_theme_color_override("font_focus_color", kit.text_color())


func _preview() -> void:
	if _preview_callback.is_valid():
		_preview_callback.call(profile)


func focus_default() -> void:
	if _root != null:
		_input_service.focus_first(_root, _first_choice)


func _finish() -> void:
	profile.display_name = _name_edit.text.strip_edges()
	if profile.display_name == "":
		profile.display_name = "Keeper"
	_input_service.release_focus_in(_root)
	_root.queue_free()
	creation_finished.emit(profile)
	queue_free()
