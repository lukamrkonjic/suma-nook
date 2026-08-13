class_name BuildBagSheet
extends PanelContainer
## Presentation shell for the Build Bag. Inventory ownership and placement
## rules remain in GameCore/Hud; this component owns only the sheet layout.

signal close_requested
signal search_changed(query: String)

var toolbar: HBoxContainer
var focus_detail: Label
var search_button: Button
var search_field: LineEdit
var close_button: Button
var scroll: ScrollContainer
var sections: VBoxContainer
var _kit: UiKit


func setup(kit: UiKit) -> void:
	_kit = kit
	name = "BuildBagSheet"
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = kit.theme
	add_theme_stylebox_override("panel", kit.sheet_style())

	var content := VBoxContainer.new()
	content.name = "BuildBagContent"
	content.add_theme_constant_override("separation", 8)
	add_child(content)

	toolbar = HBoxContainer.new()
	toolbar.name = "BuildBagToolbar"
	toolbar.custom_minimum_size.y = 34
	toolbar.add_theme_constant_override("separation", 6)
	content.add_child(toolbar)

	focus_detail = kit.muted_label("", kit.tokens.tooltip_font_size)
	focus_detail.name = "BuildBagFocusDetail"
	focus_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	focus_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toolbar.add_child(focus_detail)

	search_field = LineEdit.new()
	search_field.name = "BuildBagSearch"
	search_field.placeholder_text = "Search the collection"
	search_field.clear_button_enabled = true
	search_field.custom_minimum_size = Vector2(260, 34)
	search_field.visible = false
	kit.style_line_edit(search_field)
	search_field.text_changed.connect(func(query: String): search_changed.emit(query))
	toolbar.add_child(search_field)

	search_button = kit.minimal_icon_button("⌕", "Search Build Bag")
	search_button.name = "BuildBagSearchToggle"
	search_button.pressed.connect(toggle_search)
	toolbar.add_child(search_button)

	close_button = kit.minimal_icon_button("×", "Close Build Bag")
	close_button.name = "BuildBagClose"
	close_button.pressed.connect(func(): close_requested.emit())
	toolbar.add_child(close_button)

	scroll = ScrollContainer.new()
	scroll.name = "BuildBagScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.scroll_deadzone = 8
	kit.style_minimal_scrollbar(scroll)
	content.add_child(scroll)

	sections = VBoxContainer.new()
	sections.name = "CollectionSections"
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override("separation", kit.tokens.section_gap)
	scroll.add_child(sections)


func toggle_search() -> void:
	search_field.visible = not search_field.visible
	search_button.visible = not search_field.visible
	if search_field.visible:
		search_field.grab_focus()
	else:
		search_field.clear()


func hide_search() -> void:
	if search_field == null:
		return
	search_field.visible = false
	search_button.visible = true
	if not search_field.text.is_empty():
		search_field.clear()


func show_focus_detail(text: String) -> void:
	if focus_detail == null:
		return
	focus_detail.text = text.replace("\n", "  ·  ")


func apply_viewport(viewport_size: Vector2) -> void:
	var target := _kit.tokens.sheet_size(viewport_size)
	custom_minimum_size = target
	size = target
	position = Vector2(
		(viewport_size.x - target.x) * 0.5,
		viewport_size.y - target.y - _kit.tokens.sheet_bottom_margin
	)
