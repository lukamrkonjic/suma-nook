class_name VisionReveal
extends CanvasLayer
## The three-card Vision reveal: the well releases a Vision, options rise one
## by one, new discoveries get a flourish, choosing settles the piece into
## build stock. Tiles and structures share the same ritual. If a reveal was
## pending in the save, reopening resumes it — no loss.

signal reveal_finished(entry: Dictionary)
signal reveal_started(options: Array)
signal card_revealed(entry: Dictionary, index: int)

var core: GameCore
var kit: UiKit
var _input_service: InputDeviceService
var _thumbnail_renderer: BuildThumbnailRenderer

var _root: Control
var _cards: Array[Control] = []
var _choice_buttons: Array[Button] = []


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
		_thumbnail_renderer.name = "VisionThumbnailRenderer"
		add_child(_thumbnail_renderer)
		_thumbnail_renderer.setup(core, asset_library)


func is_open() -> bool:
	return _root != null


## Claim the well's oldest banked Vision, or resume a pending reveal.
func open_from_well() -> void:
	if is_open():
		return
	var options := core.progression.visions.claim_from_well(core.progression.inspiration)
	if options.is_empty():
		return
	_show(options)


## Show whatever reveal is already pending (delivered gift, coin draw, or a
## reveal restored from the save).
func open_pending() -> void:
	if is_open() or not core.progression.visions.has_pending():
		return
	_show(core.progression.visions.pending_options.duplicate())


func _show(options: Array[Dictionary]) -> void:
	reveal_started.emit(options.duplicate())
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = kit.theme
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.10, 0.11, 0.08, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	var accent := _reveal_accent()
	var ritual := kit.eyebrow("Wishing well", accent.lightened(0.3))
	ritual.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ritual.add_theme_color_override("font_color", accent.lightened(0.34))
	col.add_child(ritual)
	var title := kit.label(_title_text(), 32, true, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var subtitle := kit.label("Choose one shape for your Build Bag.", 15, true)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.87, 0.86, 0.79))
	col.add_child(subtitle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	_cards.clear()
	_choice_buttons.clear()
	for index in options.size():
		var card := _option_card(options[index], index)
		row.add_child(card)
		_cards.append(card)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)
	var hint := kit.label(
		"%s  ·  The other two return to the well."
		% _input_service.format_action(&"ui_accept", "Choose"),
		13,
		true
	)
	hint.add_theme_color_override("font_color", Color(0.84, 0.83, 0.76))
	footer.add_child(hint)

	# Staggered rise-in.
	for index in _cards.size():
		var card := _cards[index]
		card.modulate.a = 0.0
		card.position.y += 30
		var tween := card.create_tween()
		# Safe reference timing: 0.15 s gift pause, 0.50 s first reveal,
		# then 0.10 s spacing between successive cards.
		tween.tween_interval(0.1 * index + 0.15)
		tween.tween_property(card, "modulate:a", 1.0, 0.22)
		tween.parallel().tween_property(card, "position:y", card.position.y - 30, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func(): card_revealed.emit(options[index], index))
	focus_default()


func _title_text() -> String:
	var context := core.progression.visions.reveal_context()
	if bool(context.get("wild", false)):
		return "A Wild Vision"
	var domain := core.registries.inspiration_domain(String(context.get("domain_id", "")))
	if domain != null:
		return "%s Vision" % domain.display_name
	return "A New Vision"


func _reveal_accent() -> Color:
	var context := core.progression.visions.reveal_context()
	var domain := core.registries.inspiration_domain(
		String(context.get("domain_id", ""))
	)
	return domain.color if domain != null else kit.palette.color("ui_accent")


func animation_manifest() -> Dictionary:
	return {
		"card_reveal": {
			"duration_first_card": 0.5,
			"queue_spacing": 0.1,
			"gift_pause": 0.15,
			"events": [
				{"name": "reveal_started", "time": 0.0},
				{"name": "card_revealed", "time": 0.5, "repeats_every": 0.1},
			],
			"tracks": {
				"position.y": [
					{"time": 0.15, "offset": 30.0},
					{"time": 0.5, "offset": 0.0, "curve": "back_out"},
				],
				"modulate.a": [
					{"time": 0.15, "value": 0.0},
					{"time": 0.37, "value": 1.0, "curve": "linear"},
				],
			},
		},
		"selection": {
			"duration": 0.42,
			"events": [{"name": "reveal_finished", "time": 0.42}],
			"chosen_scale_curve": [
				{"time": 0.0, "value": 1.0},
				{"time": 0.14, "value": 1.1, "curve": "back_out"},
			],
			"chosen_fade_seconds": 0.24,
			"unchosen_fade_seconds": 0.3,
		},
	}


func _option_card(entry: Dictionary, index: int) -> Control:
	match String(entry.get("kind", "")):
		VisionSystem.KIND_TILE:
			return _tile_card(String(entry["id"]), index)
		VisionSystem.KIND_STRUCTURE:
			return _structure_card(String(entry["id"]), index)
	push_error("VisionReveal: unknown option kind '%s'" % String(entry.get("kind", "")))
	return Control.new()


func _tile_card(tile_id: String, index: int) -> Control:
	var def := core.registries.tile(tile_id)
	if def == null:
		push_error("VisionReveal: unknown tile '%s'" % tile_id)
		return Control.new()
	var is_new := not core.collection.is_discovered("tiles", tile_id)
	var domain := core.registries.domain_for_family(def.family)
	var accent := domain.color if domain != null else kit.palette.color("ui_good")
	var card := kit.progression_card(Vector2(246, 360), accent)
	var col := _card_column(card, is_new, accent)
	var title := kit.label(def.display_name, 20, false, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var family_text := (
		domain.display_name
		if domain != null
		else def.family.replace("_", " ").capitalize()
	)
	col.add_child(_centered(kit.pill(
		"%s  ·  %s" % [family_text, def.rarity.capitalize()],
		accent
	)))
	col.add_child(_piece_preview(VisionSystem.KIND_TILE, tile_id, accent, "LAND"))
	if def.anchor_id != "":
		var anchor := core.registries.anchor(def.anchor_id)
		var skill := core.registries.skill(anchor.skill_id) if anchor != null else null
		if anchor != null and skill != null:
			var anchor_label := kit.label(
				"◆ %s · %s" % [anchor.display_name, skill.display_name],
				13
			)
			anchor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(anchor_label)
	if def.special_trait != "":
		var trait_label := kit.muted_label(def.special_trait, 12)
		trait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		trait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(trait_label)
	_finish_card(card, col, def.display_name, index)
	return card


func _structure_card(structure_id: String, index: int) -> Control:
	var def := core.registries.structure(structure_id)
	if def == null:
		push_error("VisionReveal: unknown structure '%s'" % structure_id)
		return Control.new()
	var is_new := not core.collection.is_discovered("structures", structure_id)
	var domain := core.progression.refunds.domain_of(
		VisionSystem.KIND_STRUCTURE,
		structure_id
	)
	var accent := domain.color if domain != null else kit.palette.color("ui_accent")
	var card := kit.progression_card(Vector2(246, 360), accent)
	var col := _card_column(card, is_new, accent)
	var title := kit.label(def.display_name, 20, false, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var kind_text := (
		"%s  ·  %s" % [domain.display_name, def.kind.capitalize()]
		if domain != null
		else def.kind.capitalize()
	)
	col.add_child(_centered(kit.pill(kind_text, accent)))
	col.add_child(_piece_preview(
		VisionSystem.KIND_STRUCTURE,
		structure_id,
		accent,
		"BUILD"
	))
	_finish_card(card, col, def.display_name, index)
	return card


func _card_column(card: Control, is_new: bool, accent: Color) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	card.add_child(col)
	if is_new:
		col.add_child(_centered(kit.pill("NEW DISCOVERY", accent)))
	else:
		var known := kit.eyebrow("Found before", accent)
		known.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(known)
	return col


func _finish_card(card: Control, col: VBoxContainer, display_name: String, index: int) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var choose := kit.button("Keep this shape", true)
	choose.tooltip_text = "Choose %s for your build library." % display_name
	choose.pressed.connect(func(): _choose(index))
	col.add_child(choose)
	_choice_buttons.append(choose)


func _centered(control: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.add_child(control)
	return center


func _piece_preview(
	kind: String,
	content_id: String,
	accent: Color,
	fallback_text: String
) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(208, 150)
	var style := kit.surface_style(
		accent.lightened(0.61),
		15,
		accent.lightened(0.26),
		1
	)
	style.set_content_margin_all(4)
	frame.add_theme_stylebox_override("panel", style)

	var fallback_center := CenterContainer.new()
	frame.add_child(fallback_center)
	var fallback := kit.pill(fallback_text, accent)
	fallback_center.add_child(fallback)

	var preview := TextureRect.new()
	preview.name = "PiecePreview"
	preview.custom_minimum_size = Vector2(200, 142)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(preview)
	if _thumbnail_renderer != null:
		_thumbnail_renderer.request(kind, content_id, func(texture):
			if not is_instance_valid(preview):
				return
			if texture != null:
				preview.texture = texture
				fallback.visible = false)
	return frame


func _choose(index: int) -> void:
	var result := core.progression.visions.choose(index)
	if result.is_empty():
		return
	var chosen: Dictionary = result["entry"]
	# Chosen card pops; the rest dissolve.
	for i in _cards.size():
		var card := _cards[i]
		var tween := card.create_tween()
		if i == index:
			card.pivot_offset = card.size * 0.5
			tween.tween_property(card, "scale", Vector2(1.1, 1.1), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(card, "modulate:a", 0.0, 0.24)
		else:
			tween.tween_property(card, "modulate:a", 0.0, 0.3)
	get_tree().create_timer(0.42).timeout.connect(func():
		_close()
		reveal_finished.emit(chosen))


func _close() -> void:
	if _thumbnail_renderer != null:
		_thumbnail_renderer.discard_pending()
	if _root != null:
		_input_service.release_focus_in(_root)
		_root.queue_free()
		_root = null
	_cards.clear()
	_choice_buttons.clear()


func focus_default() -> void:
	if _root != null and not _choice_buttons.is_empty():
		_input_service.focus_first(_root, _choice_buttons[0])
