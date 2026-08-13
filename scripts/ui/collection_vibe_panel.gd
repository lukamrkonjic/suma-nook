class_name CollectionVibePanel
extends CanvasLayer
## One-time, non-skippable first-save question. The answer seeds early
## Worldheart vocabulary; it is a creative direction, not a permanent lock.

signal vibe_selected(collection_id: String)

var core: GameCore
var kit: UiKit
var _input_service: InputDeviceService
var _root: Control
var _first_button: Button


func setup(game_core: GameCore, ui_kit: UiKit) -> void:
	core = game_core
	kit = ui_kit
	_input_service = InputDeviceService.shared()


func is_open() -> bool:
	return _root != null


func open() -> void:
	if is_open():
		return
	_root = Control.new()
	_root.name = "CollectionVibeChoice"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = kit.theme
	add_child(_root)
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = kit.overlay_scrim()
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var card := kit.card(Vector2(920, 640))
	card.name = "CollectionVibeSheet"
	card.add_theme_stylebox_override("panel", kit.sheet_style())
	center.add_child(card)
	var shell := VBoxContainer.new()
	shell.custom_minimum_size = Vector2(860, 560)
	shell.alignment = BoxContainer.ALIGNMENT_CENTER
	shell.add_theme_constant_override("separation", 14)
	card.add_child(shell)
	var eyebrow := kit.eyebrow(
		"Your first direction", kit.palette.color("ui_arrival_border")
	)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell.add_child(eyebrow)
	var title := kit.display_label("What kind of place are you dreaming of?", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell.add_child(title)
	var subtitle := kit.label(
		"The Worldheart will favor this collection at first. You can discover and attune to every vibe later.",
		15
	)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shell.add_child(subtitle)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(860, 410)
	scroll.follow_focus = true
	kit.style_minimal_scrollbar(scroll)
	shell.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var definitions: Array = core.registries.creative_collections.values()
	definitions.sort_custom(func(a, b):
		return String(a.display_name).naturalnocasecmp_to(String(b.display_name)) < 0
	)
	for definition in definitions:
		var button := kit.button(
			"%s\n%s" % [definition.display_name, definition.description]
		)
		button.name = "Vibe_%s" % definition.id
		button.custom_minimum_size = Vector2(270, 126)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.tooltip_text = "Begin with %s-flavored Worldheart gifts" % definition.display_name
		button.pressed.connect(_choose.bind(String(definition.id)))
		grid.add_child(button)
		if _first_button == null:
			_first_button = button
	call_deferred("focus_default")


func focus_default() -> void:
	if _root != null and _first_button != null:
		_input_service.focus_first(_root, _first_button)


func blocks_world_pointer(_screen_position: Vector2) -> bool:
	return is_open()


func _choose(collection_id: String) -> void:
	if _root == null:
		return
	_input_service.release_focus_in(_root)
	var old := _root
	_root = null
	_first_button = null
	old.queue_free()
	vibe_selected.emit(collection_id)
