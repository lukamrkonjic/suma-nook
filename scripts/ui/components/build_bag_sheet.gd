class_name BuildBagSheet
extends PanelContainer
## Presentation shell for the Build Bag. Inventory ownership and placement
## rules remain in GameCore/Hud; this component owns only the sheet layout.

signal close_requested
signal search_changed(query: String)
signal category_selected(category_id: String)

## Widest the search field opens to, and how long it takes. It animates its
## width rather than appearing at full size, and its height is pinned to the
## toolbar's so revealing it cannot make the sheet taller.
const SEARCH_WIDTH := 240.0
const SEARCH_SLIDE_SECONDS := 0.16
const TOOLBAR_HEIGHT := 34.0

var toolbar: HBoxContainer
var categories: HBoxContainer
var focus_detail: Label
var search_button: Button
var search_field: LineEdit
var close_button: Button
var scroll: ScrollContainer
var sections: VBoxContainer
var _kit: UiKit
var _search_tween: Tween
var _category_tabs: Dictionary = {}


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
	toolbar.custom_minimum_size.y = TOOLBAR_HEIGHT
	# Fixed height. Without this the row grows to whatever its tallest child asks
	# for, and opening the search pushed the whole sheet taller.
	toolbar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toolbar.clip_contents = true
	toolbar.add_theme_constant_override("separation", 6)
	content.add_child(toolbar)

	categories = HBoxContainer.new()
	categories.name = "BuildBagCategories"
	categories.add_theme_constant_override("separation", 2)
	categories.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	categories.visible = false
	toolbar.add_child(categories)

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
	# Starts collapsed to zero width and is clipped, so the toolbar's layout is
	# unchanged until it opens.
	search_field.custom_minimum_size = Vector2(0.0, TOOLBAR_HEIGHT)
	search_field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	search_field.clip_contents = true
	search_field.visible = false
	kit.style_line_edit(search_field)
	# style_line_edit pads 9px top and bottom around a 15px font, which puts the
	# field's own minimum height near 38 -- above the toolbar's 34, so revealing
	# it stretched the row and with it the whole sheet. Tightened here rather
	# than globally, since every other line edit sits in a taller container.
	for state: String in ["normal", "read_only", "focus"]:
		var box := search_field.get_theme_stylebox(state) as StyleBoxFlat
		if box == null:
			continue
		var compact := box.duplicate() as StyleBoxFlat
		compact.content_margin_top = 4
		compact.content_margin_bottom = 4
		search_field.add_theme_stylebox_override(state, compact)
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
	if search_field.visible:
		hide_search()
	else:
		_open_search()


func _open_search() -> void:
	search_field.visible = true
	search_button.visible = false
	search_field.grab_focus()
	_slide_search(SEARCH_WIDTH)


func hide_search() -> void:
	if search_field == null:
		return
	search_button.visible = true
	if not search_field.text.is_empty():
		search_field.clear()
	if not search_field.visible:
		return
	_slide_search(0.0, func(): search_field.visible = false)


## Animates only the field's width. Tweening custom_minimum_size.x rather than
## fading or scaling keeps the neighbouring buttons in place and the sheet the
## same height throughout.
func _slide_search(target_width: float, on_finished := Callable()) -> void:
	if _search_tween != null and _search_tween.is_valid():
		_search_tween.kill()
	var duration := _kit.motion_duration(SEARCH_SLIDE_SECONDS)
	if duration <= 0.0:
		search_field.custom_minimum_size.x = target_width
		if on_finished.is_valid():
			on_finished.call()
		return
	_search_tween = create_tween()
	_search_tween.tween_property(
		search_field, "custom_minimum_size:x", target_width, duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if on_finished.is_valid():
		_search_tween.tween_callback(on_finished)


## Rebuilds the category row. Only categories that actually hold something are
## offered, so the row narrows with an empty bag instead of showing eleven
## unusable tabs.
func set_categories(entries: Array, active_id: String) -> void:
	for child in categories.get_children():
		child.queue_free()
	_category_tabs.clear()
	categories.visible = entries.size() > 1
	for entry: Dictionary in entries:
		var category_id := String(entry.get("id", ""))
		var tab := _kit.category_tab(
			entry.get("icon") as Texture2D,
			String(entry.get("label", category_id)),
			entry.get("accent", Color.WHITE) as Color,
			category_id == active_id
		)
		tab.name = "CategoryTab_%s" % category_id
		tab.pressed.connect(
			func() -> void: category_selected.emit(category_id)
		)
		categories.add_child(tab)
		_category_tabs[category_id] = tab


func set_active_category(category_id: String) -> void:
	for known_id: String in _category_tabs:
		_kit.set_category_tab_selected(
			_category_tabs[known_id], known_id == category_id
		)


func show_focus_detail(text: String) -> void:
	if focus_detail == null:
		return
	focus_detail.text = text.replace("\n", "  ·  ")


## Height for a given number of item rows, everything above the grid included.
## A fractional count is the point: at 1.5 the second row is cut by the sheet's
## edge, which says "there is more here" without a scrollbar having to say it.
func height_for_rows(rows: float, cell_extent: float) -> float:
	var chrome := (
		TOOLBAR_HEIGHT
		+ float(_kit.tokens.sheet_padding * 2)
		+ float(_kit.tokens.cell_gap)
	)
	return chrome + rows * (cell_extent + float(_kit.tokens.cell_gap))


func apply_viewport(viewport_size: Vector2, height_override := 0.0) -> void:
	var target := _kit.tokens.sheet_size(viewport_size)
	if height_override > 0.0:
		target.y = minf(height_override, viewport_size.y - 48.0)
	custom_minimum_size = target
	size = target
	position = Vector2(
		(viewport_size.x - target.x) * 0.5,
		viewport_size.y - target.y - _kit.tokens.sheet_bottom_margin
	)
