class_name DiscoveryReveal
extends CanvasLayer
## A single immediate reveal shared by void fishing, local skills, ferry gifts,
## and the duplicate exchange. Rewards are granted before presentation and
## remain queued in the save until acknowledged.

signal reveal_finished(entry: Dictionary)
signal reveal_started(entry: Dictionary)

var core: GameCore
var kit: UiKit
var _input_service: InputDeviceService
var _thumbnail_renderer: BuildThumbnailRenderer
var _root: Control
var _accept_button: Button


func setup(
	game_core: GameCore,
	ui_kit: UiKit,
	asset_library: AssetLibrary = null
) -> void:
	core = game_core
	kit = ui_kit
	_input_service = InputDeviceService.shared()
	if asset_library != null:
		_thumbnail_renderer = BuildThumbnailRenderer.new()
		_thumbnail_renderer.name = "DiscoveryThumbnailRenderer"
		add_child(_thumbnail_renderer)
		_thumbnail_renderer.setup(core, asset_library)


func is_open() -> bool:
	return _root != null


func open_pending() -> void:
	if is_open() or not core.progression.discovery.has_pending():
		return
	_show(core.progression.discovery.peek_pending())


func _show(entry: Dictionary) -> void:
	reveal_started.emit(entry.duplicate(true))
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = kit.theme
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = kit.palette.color("ui_reveal_scrim")
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var accent := _accent(entry)
	var card := kit.progression_card(Vector2(330, 470), accent)
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)

	var source := String(entry.get("source", "void"))
	var eyebrow_text := "THE VOID ANSWERED"
	match source:
		"local": eyebrow_text = _pool_name(entry).to_upper()
		"exchange": eyebrow_text = "THE VOID RETURNED"
		"delivery": eyebrow_text = "A FERRY DISCOVERY"
		"migration": eyebrow_text = "A SAVED DISCOVERY"
	var eyebrow := kit.eyebrow(eyebrow_text, accent)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(eyebrow)

	var definition: Variant = _definition(entry)
	var display_name: String = (
		definition.display_name
		if definition != null
		else String(entry.get("id", "")).capitalize()
	)
	var title := kit.label(display_name, 28, true, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)

	var status := (
		"NEW DISCOVERY"
		if bool(entry.get("was_new", false))
		else "ANOTHER COPY"
	)
	var status_center := CenterContainer.new()
	status_center.add_child(kit.pill(status, accent))
	col.add_child(status_center)
	col.add_child(_piece_preview(
		String(entry.get("kind", "")),
		String(entry.get("id", "")),
		accent
	))

	var description := kit.muted_label(_description(entry), 14)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(description)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	_accept_button = kit.button("Add to Build Bag", true)
	_accept_button.pressed.connect(_accept)
	col.add_child(_accept_button)

	card.modulate.a = 0.0
	card.scale = Vector2(0.88, 0.88)
	card.pivot_offset = card.custom_minimum_size * 0.5
	var tween := card.create_tween()
	tween.tween_interval(0.12)
	tween.tween_property(card, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(card, "scale", Vector2.ONE, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	focus_default()


func _piece_preview(
	kind: String,
	content_id: String,
	accent: Color
) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(286, 220)
	var style := kit.surface_style(
		accent.lightened(0.61),
		15,
		accent.lightened(0.26),
		1
	)
	style.set_content_margin_all(4)
	frame.add_theme_stylebox_override("panel", style)
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(278, 212)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(preview)
	if _thumbnail_renderer != null:
		_thumbnail_renderer.request(kind, content_id, func(texture):
			if is_instance_valid(preview):
				preview.texture = texture
		)
	return frame


func _definition(entry: Dictionary) -> Variant:
	var content_id := String(entry.get("id", ""))
	return (
		core.registries.tile(content_id)
		if String(entry.get("kind", "")) == DiscoverySystem.KIND_TILE
		else core.registries.structure(content_id)
	)


func _pool_name(entry: Dictionary) -> String:
	var pool := core.registries.discovery_pool(
		String(entry.get("pool_id", ""))
	)
	return pool.display_name if pool != null else "A nearby biome answered"


func _accent(entry: Dictionary) -> Color:
	var pool := core.registries.discovery_pool(
		String(entry.get("pool_id", ""))
	)
	return pool.color if pool != null else kit.palette.color("ui_accent")


func _description(entry: Dictionary) -> String:
	match String(entry.get("source", "void")):
		"local":
			var pool := core.registries.discovery_pool(
				String(entry.get("pool_id", ""))
			)
			return (
				pool.description
				if pool != null
				else "Your constructed surroundings shaped this discovery."
			)
		"exchange":
			return "Three spare copies vanished. A different piece of the same Build Bag category came back."
		"delivery":
			return "A distant discovery has reached your shore."
	return "You cast beyond the edge of your world and pulled back a piece of possibility."


func _accept() -> void:
	var entry := core.progression.discovery.acknowledge_next()
	if entry.is_empty():
		return
	if _accept_button != null:
		_accept_button.disabled = true
	var root := _root
	var tween := root.create_tween()
	tween.tween_property(root, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func():
		_close()
		reveal_finished.emit(entry)
	)


func _close() -> void:
	if _thumbnail_renderer != null:
		_thumbnail_renderer.discard_pending()
	if _root != null:
		_input_service.release_focus_in(_root)
		_root.queue_free()
		_root = null
	_accept_button = null


func focus_default() -> void:
	if _root != null and _accept_button != null:
		_input_service.focus_first(_root, _accept_button)
