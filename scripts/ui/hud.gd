class_name Hud
extends CanvasLayer
## Persistent interface: skill chips, health, context prompt, toasts, build
## bar, tutorial hints. Modal panels live in GamePanels; the parcel reveal in
## ParcelReveal. World stays visible — no giant menus.

signal open_parcel_requested
signal build_piece_selected(kind: String, id: String)

var core: GameCore
var kit: UiKit
var placement: PlacementController

var _skill_chips: Dictionary = {}    # skill_id -> {level_label, bar_holder, chip}
var _toast_box: VBoxContainer
var _prompt_label: Label
var _hint_label: Label
var _health_box: HBoxContainer
var _build_bar: PanelContainer
var _build_strip: HBoxContainer
var _parcel_button: Button
var _bottom_buttons: HBoxContainer


func setup(game_core: GameCore, ui_kit: UiKit, placement_controller: PlacementController) -> void:
	core = game_core
	kit = ui_kit
	placement = placement_controller
	_build_layout()
	core.skills.xp_gained.connect(_on_xp_gained)
	core.skills.level_up.connect(_on_level_up)
	core.inventory.item_gained.connect(_on_item_gained)
	core.inventory.items_changed.connect(_refresh_parcel_button)
	core.stock.stock_changed.connect(_refresh_build_strip)
	if core.registries.feature("combat_enabled", false):
		core.combat.health_changed.connect(_on_health_changed)
	core.notified.connect(func(message, tone): toast(message, tone))
	placement.mode_changed.connect(_on_build_mode)
	placement.action_result.connect(_on_action_result)
	_refresh_all()


func _build_layout() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Skill chips — top left.
	var chips := VBoxContainer.new()
	chips.position = Vector2(14, 14)
	chips.add_theme_constant_override("separation", 6)
	root.add_child(chips)
	for skill_id: String in core.registries.skills:
		var def := core.registries.skill(skill_id)
		if def.future:
			continue
		var chip := kit.card()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		chip.add_child(row)
		row.add_child(kit.label(def.icon_glyph, 20))
		var col := VBoxContainer.new()
		row.add_child(col)
		var level_label := kit.label("%s  %d" % [def.display_name, 1], 15)
		col.add_child(level_label)
		var bar_holder := Control.new()
		bar_holder.custom_minimum_size = Vector2(120, 10)
		col.add_child(bar_holder)
		chips.add_child(chip)
		_skill_chips[skill_id] = {"level": level_label, "bar": bar_holder, "chip": chip}

	# Health hearts — top center, hidden while safe and full.
	_health_box = HBoxContainer.new()
	_health_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_health_box.position.y = 16
	_health_box.add_theme_constant_override("separation", 4)
	_health_box.visible = false
	root.add_child(_health_box)

	# Toasts — top right.
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toast_box.position += Vector2(-14, 14)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast_box.add_theme_constant_override("separation", 6)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_box)

	# Context prompt + tutorial hint — bottom center.
	var center_col := VBoxContainer.new()
	center_col.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	center_col.position.y = -86
	center_col.alignment = BoxContainer.ALIGNMENT_END
	center_col.add_theme_constant_override("separation", 8)
	center_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center_col)
	_hint_label = kit.label("", 18)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", Color(0.35, 0.31, 0.24))
	center_col.add_child(_hint_label)
	_prompt_label = kit.label("", 20)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_col.add_child(_prompt_label)

	# Bottom-left action buttons.
	_bottom_buttons = HBoxContainer.new()
	_bottom_buttons.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_bottom_buttons.position += Vector2(14, -14)
	_bottom_buttons.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom_buttons.add_theme_constant_override("separation", 8)
	root.add_child(_bottom_buttons)
	var build_button := kit.button("Build (B)", true)
	build_button.pressed.connect(func(): placement.toggle())
	_bottom_buttons.add_child(build_button)
	_parcel_button = kit.button("Open Land Parcel ✨", true)
	_parcel_button.visible = false
	_parcel_button.pressed.connect(func(): open_parcel_requested.emit())
	_bottom_buttons.add_child(_parcel_button)

	# Build bar — bottom strip with stock pieces (hidden outside build mode).
	_build_bar = kit.card()
	_build_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_build_bar.position.y = -14
	_build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_build_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_build_bar.visible = false
	root.add_child(_build_bar)
	var bar_col := VBoxContainer.new()
	_build_bar.add_child(bar_col)
	_build_strip = HBoxContainer.new()
	_build_strip.add_theme_constant_override("separation", 6)
	bar_col.add_child(_build_strip)
	var build_hint := kit.label("click place · R rotate · click a placed piece to move it · X store · Ctrl/Cmd+Z undo · Esc done", 13)
	build_hint.add_theme_color_override("font_color", Color(0.45, 0.4, 0.33))
	bar_col.add_child(build_hint)


# ------------------------------------------------------------------ refresh

func _refresh_all() -> void:
	for skill_id: String in _skill_chips:
		_refresh_skill(skill_id)
	_refresh_parcel_button()
	_refresh_build_strip()
	if core.registries.feature("combat_enabled", false):
		_on_health_changed(core.combat.health, core.combat.max_health)
	else:
		_health_box.visible = false


func _refresh_skill(skill_id: String) -> void:
	var chip: Dictionary = _skill_chips[skill_id]
	var def := core.registries.skill(skill_id)
	chip["level"].text = "%s  %d" % [def.display_name, core.skills.level(skill_id)]
	var holder: Control = chip["bar"]
	for child in holder.get_children():
		child.queue_free()
	var progress := core.skills.xp_progress(skill_id)
	holder.add_child(kit.progress_bar(progress["fraction"]))


func _refresh_parcel_button() -> void:
	_parcel_button.visible = core.parcels.has_pending()
	if _parcel_button.visible:
		_parcel_button.text = "Resume Land Parcel reveal ✨"


func _refresh_build_strip() -> void:
	for child in _build_strip.get_children():
		child.queue_free()
	var empty := true
	for tile_id: String in core.stock.tiles:
		empty = false
		var def := core.registries.tile(tile_id)
		var b := kit.button("⬢ %s ×%d" % [def.display_name, core.stock.tiles[tile_id]])
		b.pressed.connect(func(): build_piece_selected.emit("tile", tile_id))
		_build_strip.add_child(b)
	for structure_id: String in core.stock.structures:
		empty = false
		var def := core.registries.structure(structure_id)
		var b := kit.button("⌂ %s ×%d" % [def.display_name, core.stock.structures[structure_id]])
		b.pressed.connect(func(): build_piece_selected.emit("structure", structure_id))
		_build_strip.add_child(b)
	for landmark_id: String in core.stock.landmark_deeds:
		empty = false
		var def := core.registries.landmark(landmark_id)
		var b := kit.button("🏛 %s (deed)" % def.display_name, true)
		b.pressed.connect(func(): build_piece_selected.emit("deed", landmark_id))
		_build_strip.add_child(b)
	if empty:
		_build_strip.add_child(kit.label("Your libraries are empty — the next ferry will bring a Land Parcel.", 14))


# ------------------------------------------------------------------ events

func _on_xp_gained(skill_id: String, _amount: int, _total: int) -> void:
	if _skill_chips.has(skill_id):
		_refresh_skill(skill_id)


func _on_level_up(skill_id: String, new_level: int, _unlocks: Array) -> void:
	if not _skill_chips.has(skill_id):
		return
	_refresh_skill(skill_id)
	var chip: PanelContainer = _skill_chips[skill_id]["chip"]
	var tween := chip.create_tween()
	tween.tween_property(chip, "scale", Vector2(1.12, 1.12), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(chip, "scale", Vector2.ONE, 0.2)
	toast("✨ %s level %d!" % [core.registries.skill(skill_id).display_name, new_level], "levelup")


func _on_item_gained(item_id: String, count: int, rare: bool) -> void:
	var def := core.registries.item(item_id)
	if def == null:
		return
	if not core.registries.feature("legacy_material_loot_enabled", false):
		return
	toast("+%d %s" % [count, def.display_name], "rare" if rare or def.rarity == "rare" else "common")
	_refresh_parcel_button()


func _on_health_changed(current: int, maximum: int) -> void:
	for child in _health_box.get_children():
		child.queue_free()
	_health_box.visible = current < maximum or _enemies_near()
	for i in maximum:
		var heart := kit.label("♥", 22)
		heart.add_theme_color_override("font_color", Color(0.78, 0.32, 0.28) if i < current else Color(0.4, 0.37, 0.33, 0.5))
		_health_box.add_child(heart)


func _enemies_near() -> bool:
	return get_tree().get_node_count_in_group("enemies") > 0


func _on_build_mode(active: bool) -> void:
	_build_bar.visible = active
	_bottom_buttons.visible = not active
	if active:
		_refresh_build_strip()


func _on_action_result(ok: bool, message: String, _kind: String) -> void:
	if message != "":
		toast(message, "good" if ok else "warn")


# ------------------------------------------------------------------ prompt / hints / toasts

func set_prompt(text: String) -> void:
	_prompt_label.text = text


func set_hint(text: String) -> void:
	_hint_label.text = text


## Keeps unboxed world-space guidance legible across the pale day and dark
## rain backdrops without adding a large UI panel over the diorama.
func apply_weather_contrast(rain_enabled: bool) -> void:
	var hint_color := Color(0.92, 0.89, 0.8) if rain_enabled else Color(0.35, 0.31, 0.24)
	var prompt_color := Color(0.97, 0.94, 0.86) if rain_enabled else kit.text_color()
	for entry in [[_hint_label, hint_color], [_prompt_label, prompt_color]]:
		var label := entry[0] as Label
		label.add_theme_color_override("font_color", entry[1])
		label.add_theme_color_override("font_outline_color", Color(0.12, 0.15, 0.12, 0.8))
		label.add_theme_constant_override("outline_size", 3 if rain_enabled else 0)


func toast(message: String, tone := "common") -> void:
	var card := kit.card()
	var l := kit.label(message, 15)
	match tone:
		"rare", "levelup":
			l.add_theme_color_override("font_color", Color(0.62, 0.45, 0.1))
		"warn":
			l.add_theme_color_override("font_color", Color(0.62, 0.28, 0.22))
		"good":
			l.add_theme_color_override("font_color", Color(0.35, 0.42, 0.16))
	card.add_child(l)
	card.modulate.a = 0.0
	_toast_box.add_child(card)
	_toast_box.move_child(card, 0)
	while _toast_box.get_child_count() > 6:
		_toast_box.get_child(_toast_box.get_child_count() - 1).free()
	var tween := card.create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.15)
	tween.tween_interval(2.6 if tone == "common" else 3.6)
	tween.tween_property(card, "modulate:a", 0.0, 0.5)
	tween.tween_callback(card.queue_free)


## Derives the current opening hint straight from progression state.
func update_tutorial() -> void:
	if core.arrivals.has_waiting_package():
		set_hint("A Land Parcel is waiting at the northern dock.")
	elif core.skills.lifetime_actions.get("fishing", 0) == 0:
		set_hint("Try catch-and-release fishing along the northern water. (walk close, then E)")
	elif core.parcels.has_pending():
		set_hint("Choose one finished tile from the Land Parcel.")
	elif core.grid.placed_tile_count() == 0 and core.stock.total_tiles() > 0:
		set_hint("Place your new land beside the world you have. (B for build mode)")
	elif core.grid.placed_tile_count() > 0 and core.skills.lifetime_actions.get("woodcutting", 0) == 0:
		set_hint("Tend your new grove — it will rest, then regrow.")
	else:
		set_hint("")
