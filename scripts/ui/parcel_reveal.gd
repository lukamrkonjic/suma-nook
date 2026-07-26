class_name ParcelReveal
extends CanvasLayer
## The three-card land reveal: parcel unfolds, options rise one by one, new
## discoveries get a flourish, choosing settles the tile into build stock.
## If a reveal was pending in the save, reopening resumes it — no loss.

signal reveal_finished(tile_id: String)
signal reveal_started(tile_ids: Array[String])
signal card_revealed(tile_id: String, index: int)

var core: GameCore
var kit: UiKit

var _root: Control
var _cards: Array[Control] = []


func setup(game_core: GameCore, ui_kit: UiKit) -> void:
	core = game_core
	kit = ui_kit


func is_open() -> bool:
	return _root != null


## Open a fresh parcel (consumes it) or resume a pending reveal.
func open_best_available() -> void:
	if is_open():
		return
	var options: Array[String] = []
	if core.parcels.has_pending():
		options = core.parcels.pending_options
	else:
		for parcel_id in ["parcel_wild", "parcel_grove", "parcel_meadow", "parcel_stone"]:
			if core.parcels.can_open(parcel_id):
				options = core.parcels.open(parcel_id)
				break
	if options.is_empty():
		return
	_show(options)


func _show(options: Array[String]) -> void:
	reveal_started.emit(options)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.15, 0.13, 0.1, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	var title := kit.label("New land wants a shape…", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	_cards.clear()
	for index in options.size():
		var card := _tile_card(options[index], index)
		row.add_child(card)
		_cards.append(card)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	col.add_child(footer)
	if core.parcels.can_reroll():
		var reroll := kit.button("Reroll (3 Pattern Dust)")
		reroll.pressed.connect(func():
			var fresh := core.parcels.reroll()
			_close()
			_show(fresh))
		footer.add_child(reroll)
	var hint := kit.label("Unchosen shapes drift back into the wild — nothing is wasted.", 14)
	hint.add_theme_color_override("font_color", Color(0.92, 0.89, 0.8))
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


func _tile_card(tile_id: String, index: int) -> Control:
	var def := core.registries.tile(tile_id)
	var is_new := not core.collection.is_discovered("tiles", tile_id)
	var card := kit.card(Vector2(210, 270))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	if is_new:
		var new_tag := kit.label("✨ NEW", 15)
		new_tag.add_theme_color_override("font_color", Color(0.72, 0.55, 0.12))
		new_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(new_tag)
	var title := kit.label(def.display_name, 19)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var family := kit.label(def.family.replace("_", " ").capitalize(), 13)
	family.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	family.add_theme_color_override("font_color", kit.rarity_color(def.rarity))
	col.add_child(family)
	col.add_child(_preview_swatch(def))
	if def.anchor_id != "":
		var anchor := core.registries.anchor(def.anchor_id)
		var anchor_label := kit.label("◈ %s (%s)" % [anchor.display_name, core.registries.skill(anchor.skill_id).display_name], 13)
		anchor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(anchor_label)
	if def.special_trait != "":
		var trait_label := kit.label(def.special_trait, 12)
		trait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		trait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		trait_label.add_theme_color_override("font_color", Color(0.5, 0.46, 0.38))
		col.add_child(trait_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var choose := kit.button("Choose", true)
	choose.pressed.connect(func(): _choose(index))
	col.add_child(choose)
	return card


## Simple color-block preview of the tile family (real 3D previews are a
## post-MVP nicety; the swatch communicates family + rarity clearly).
func _preview_swatch(def: Defs.TileDefinition) -> Control:
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(170, 74)
	match def.family:
		"living_grove": swatch.color = Color(0.33, 0.4, 0.2)
		"stonebound": swatch.color = Color(0.66, 0.6, 0.5)
		_: swatch.color = Color(0.72, 0.74, 0.28)
	if def.water_cells.size() > 0:
		swatch.color = swatch.color.lerp(Color(0.56, 0.68, 0.67), 0.45)
	return swatch


func _choose(index: int) -> void:
	var chosen := core.parcels.choose(index)
	if chosen == "":
		return
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
	if _root != null:
		_root.queue_free()
		_root = null
	_cards.clear()
