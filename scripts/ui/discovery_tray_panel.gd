class_name DiscoveryTrayPanel
extends CanvasLayer
## Persistent three-miniature tray plus a tiny Gift Pocket. Pointer users can
## choose directly; controller users focus it through the discovery_tray action.

signal offer_selected(offer: Dictionary)
signal gift_selected(gift_id: String)
signal focus_changed(focused: bool)

const CARD_SIZE := Vector2(116.0, 122.0)

var core: GameCore
var kit: UiKit
var placement: PlacementController
var _input_service: InputDeviceService
var _thumbnail_renderer: BuildThumbnailRenderer
var _root: Control
var _tray: PanelContainer
var _offer_row: HBoxContainer
var _gift_button: Button
var _buttons: Array[Button] = []
var _last_slot := 0
var _hud_suppressed := false


func setup(
	game_core: GameCore,
	ui_kit: UiKit,
	asset_library: AssetLibrary,
	placement_controller: PlacementController
) -> void:
	core = game_core
	kit = ui_kit
	placement = placement_controller
	_input_service = InputDeviceService.shared()
	layer = 2
	_thumbnail_renderer = BuildThumbnailRenderer.new()
	_thumbnail_renderer.name = "DiscoveryTrayThumbnailRenderer"
	add_child(_thumbnail_renderer)
	_thumbnail_renderer.setup(core, asset_library)
	_build_layout()
	core.diorama.tray.tray_changed.connect(_rebuild)
	core.diorama.gifts.inventory_changed.connect(_refresh_gifts)
	placement.mode_changed.connect(func(active: bool):
		visible = not active and not _hud_suppressed
		if active:
			release_focus()
	)
	_rebuild()
	_refresh_gifts()


func set_hud_suppressed(suppressed: bool) -> void:
	_hud_suppressed = suppressed
	visible = not suppressed and not placement.active
	if suppressed:
		release_focus()


func open_focus() -> void:
	if not visible:
		return
	var preferred: Control = null
	if _last_slot >= 0 and _last_slot < _buttons.size():
		preferred = _buttons[_last_slot]
	elif not _buttons.is_empty():
		preferred = _buttons[0]
	elif _gift_button != null and _gift_button.visible:
		preferred = _gift_button
	if preferred != null:
		_input_service.focus_first(_tray, preferred)
		focus_changed.emit(true)


func release_focus() -> void:
	if _tray != null:
		_input_service.release_focus_in(_tray)
	focus_changed.emit(false)


func has_focus() -> bool:
	if _tray == null or get_viewport() == null:
		return false
	var focused := get_viewport().gui_get_focus_owner()
	return focused != null and (focused == _tray or _tray.is_ancestor_of(focused))


func blocks_world_pointer(screen_position: Vector2) -> bool:
	return visible and _tray != null and _tray.get_global_rect().has_point(screen_position)


func _unhandled_input(event: InputEvent) -> void:
	if has_focus() and event.is_action_pressed("cancel"):
		release_focus()
		get_viewport().set_input_as_handled()


func _build_layout() -> void:
	_root = Control.new()
	_root.name = "DiscoveryTrayRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = kit.theme
	add_child(_root)

	_tray = PanelContainer.new()
	_tray.name = "DiscoveryTray"
	_tray.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_tray.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tray.offset_left = -410.0
	_tray.offset_top = -160.0
	_tray.offset_right = -16.0
	_tray.offset_bottom = -16.0
	_tray.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := kit.cloud_panel_style()
	style.set_content_margin_all(8)
	style.border_width_top = 2
	style.border_color = kit.collection_accent("collections")
	_tray.add_theme_stylebox_override("panel", style)
	_root.add_child(_tray)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_tray.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var label := kit.utility_label("DISCOVERY TRAY", 10, kit.collection_accent("collections"))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	_gift_button = kit.compact_button("Ripple ×0", 26.0)
	_gift_button.name = "GiftPocketExpansionRipple"
	_gift_button.pressed.connect(func():
		release_focus()
		gift_selected.emit("expansion_ripple")
	)
	header.add_child(_gift_button)
	_offer_row = HBoxContainer.new()
	_offer_row.add_theme_constant_override("separation", 7)
	column.add_child(_offer_row)


func _rebuild() -> void:
	if _offer_row == null:
		return
	_thumbnail_renderer.discard_pending()
	for child in _offer_row.get_children():
		_offer_row.remove_child(child)
		child.queue_free()
	_buttons.clear()
	for offer: Dictionary in core.diorama.tray.offers():
		var slot := int(offer.get("slot", _buttons.size()))
		var card := _offer_card(offer, slot)
		_offer_row.add_child(card)
		_buttons.append(card)
	_wire_focus_neighbors()


func _offer_card(offer: Dictionary, slot: int) -> Button:
	var name := _display_name(offer)
	var card_data := kit.library_visual_item_button(name, 1)
	var button: Button = card_data["button"]
	var preview: TextureRect = card_data["preview"]
	button.name = "DiscoveryOffer_%d" % slot
	button.custom_minimum_size = CARD_SIZE
	button.disabled = String(offer.get("state", "available")) != "available"
	button.tooltip_text = "%s · %s" % [
		String(offer.get("role", "piece")).capitalize(),
		_input_service.format_action(&"ui_accept", "place this miniature"),
	]
	# The tray represents one exact offer, not a Stock count.
	var badge := button.get_node_or_null("CountBadge")
	if badge != null:
		badge.visible = false
	button.pressed.connect(_select.bind(slot))
	_thumbnail_renderer.request(
		String(offer.get("kind", "")),
		String(offer.get("id", "")),
		func(texture):
			if is_instance_valid(preview):
				preview.texture = texture
	)
	return button


func _select(slot: int) -> void:
	var offer := core.diorama.tray.begin_hold(slot)
	if offer.is_empty():
		return
	_last_slot = slot
	release_focus()
	offer_selected.emit(offer)


func _refresh_gifts() -> void:
	if _gift_button == null:
		return
	var count := core.diorama.gifts.count("expansion_ripple")
	_gift_button.text = "Ripple ×%d" % count
	_gift_button.visible = count > 0
	_gift_button.disabled = count <= 0
	_gift_button.tooltip_text = _input_service.format_action(
		&"ui_accept", "choose an edge and expand the world"
	)
	_wire_focus_neighbors()


func _wire_focus_neighbors() -> void:
	var controls: Array[Control] = []
	for button in _buttons:
		if is_instance_valid(button) and not button.disabled:
			controls.append(button)
	if _gift_button != null and _gift_button.visible:
		controls.append(_gift_button)
	for index in controls.size():
		var current := controls[index]
		var previous := controls[posmod(index - 1, controls.size())]
		var next := controls[(index + 1) % controls.size()]
		current.focus_neighbor_left = current.get_path_to(previous)
		current.focus_neighbor_right = current.get_path_to(next)


func _display_name(offer: Dictionary) -> String:
	var content_id := String(offer.get("id", ""))
	var definition = (
		core.registries.tile(content_id)
		if offer.get("kind", "") == "tile"
		else core.registries.structure(content_id)
	)
	return definition.display_name if definition != null else content_id.capitalize()
