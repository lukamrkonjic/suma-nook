class_name GamePanels
extends CanvasLayer
## All modal panels. One panel open at a time; Esc closes. Compact — the
## world stays visible around every card.

signal panel_toggled(panel_name: String, open: bool)
signal landmark_resolution_chosen(landmark_id: String, resolution: String)

const PANEL_ORDER := [
	"inventory",
	"character",
	"skills",
	"collection",
	"map",
]

var core: GameCore
var kit: UiKit
var _input_service: InputDeviceService
var settings_bridge: Node   # main.gd — exposes audio volumes / profile toggle

var _open_panel: Control
var _open_name := ""


func setup(game_core: GameCore, ui_kit: UiKit, bridge: Node) -> void:
	core = game_core
	kit = ui_kit
	_input_service = InputDeviceService.shared()
	settings_bridge = bridge


func is_open() -> bool:
	return _open_panel != null


func close() -> void:
	if _open_panel != null:
		_input_service.release_focus_in(_open_panel)
		_open_panel.queue_free()
		_open_panel = null
		panel_toggled.emit(_open_name, false)
		_open_name = ""


func toggle(panel_name: String) -> void:
	if _open_name == panel_name:
		close()
		return
	close()
	var win: Dictionary
	match panel_name:
		"inventory": win = _inventory_panel()
		"crafting": win = _crafting_panel()
		"skills": win = _skills_panel()
		"character": win = _character_panel()
		"collection": win = _collection_panel()
		"map": win = _map_panel()
		"settings": win = _settings_panel()
		_: return
	_open_panel = win["root"]
	_open_name = panel_name
	win["close"].pressed.connect(close)
	add_child(_open_panel)
	var card: Control = win["card"]
	card.scale = Vector2(0.92, 0.92)
	card.pivot_offset = card.size * 0.5
	var tween := card.create_tween()
	tween.tween_property(card, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	panel_toggled.emit(panel_name, true)
	focus_default()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("cancel"):
		close()
	elif event.is_action_pressed("panel_previous"):
		_cycle_panel(-1)
	elif event.is_action_pressed("panel_next"):
		_cycle_panel(1)
	else:
		return
	get_viewport().set_input_as_handled()


func _cycle_panel(direction: int) -> void:
	if _open_name not in PANEL_ORDER:
		return
	var index := PANEL_ORDER.find(_open_name)
	toggle(PANEL_ORDER[posmod(index + direction, PANEL_ORDER.size())])


func focus_default() -> void:
	if _open_panel != null:
		_input_service.focus_first(_open_panel)


func _scroll_list(height := 380.0) -> Dictionary:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, height)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return {"scroll": scroll, "list": list}


# ------------------------------------------------------------------ inventory

func _inventory_panel() -> Dictionary:
	var win := kit.window("Tile & Build Libraries", Vector2(500, 520))
	var parts := _scroll_list()
	win["content"].add_child(parts["scroll"])
	var list: VBoxContainer = parts["list"]
	list.add_child(kit.label("Tile Library", 20))
	var visible_tile_count := 0
	for tile_id: String in core.stock.tiles:
		var tile := core.registries.tile(tile_id)
		if tile == null or not core.registries.is_tile_active(tile_id):
			continue
		visible_tile_count += 1
		list.add_child(kit.label("⬢ %s ×%d" % [tile.display_name, core.stock.tile_count(tile_id)], 16))
	if visible_tile_count == 0:
		list.add_child(kit.label("No unplaced tiles yet. The ferry brings Land Parcels.", 14))
	list.add_child(kit.label("Build Library", 20))
	for structure_id: String in core.stock.structures:
		var structure := core.registries.structure(structure_id)
		if structure == null:
			continue
		list.add_child(kit.label("⌂ %s ×%d" % [structure.display_name, core.stock.structure_count(structure_id)], 16))
	if core.stock.structures.is_empty():
		list.add_child(kit.label("No stored decorations yet.", 14))
	list.add_child(kit.label(
		"%s to place anything from either library."
		% _input_service.format_action(&"build_mode", "Open build mode"),
		14
	))
	return win


# ------------------------------------------------------------------ crafting

func _crafting_panel() -> Dictionary:
	var win := kit.window("Crafting", Vector2(540, 560))
	if not core.registries.feature("material_crafting_enabled", false):
		win["content"].add_child(kit.label("Material-based crafting is not part of this peaceful world-building iteration.", 16))
		return win
	var parts := _scroll_list(430.0)
	win["content"].add_child(parts["scroll"])
	var list: VBoxContainer = parts["list"]
	var by_category: Dictionary = {}
	for recipe: Defs.RecipeDefinition in core.crafting.available_recipes():
		if not by_category.has(recipe.category):
			by_category[recipe.category] = []
		by_category[recipe.category].append(recipe)
	for category in ["land", "buildings", "decorations", "tools", "equipment"]:
		if not by_category.has(category):
			continue
		list.add_child(kit.label(category.capitalize(), 19))
		for recipe: Defs.RecipeDefinition in by_category[category]:
			list.add_child(_recipe_row(recipe))
	return win


func _recipe_row(recipe: Defs.RecipeDefinition) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(kit.label(recipe.display_name, 16))
	var costs: PackedStringArray = []
	for input_id: String in recipe.inputs:
		var item := core.registries.item(input_id)
		var have := core.inventory.count(input_id)
		var need := int(recipe.inputs[input_id])
		costs.append("%s %d/%d" % [item.display_name if item else input_id, have, need])
	var cost_label := kit.label(", ".join(costs), 13)
	cost_label.add_theme_color_override("font_color", Color(0.5, 0.46, 0.38))
	col.add_child(cost_label)
	var craft_button := kit.button("Craft", true)
	craft_button.disabled = not core.crafting.can_craft(recipe.id)
	craft_button.pressed.connect(func():
		if core.crafting.craft(recipe.id):
			toggle("crafting")
			toggle("crafting"))
	row.add_child(craft_button)
	return row


# ------------------------------------------------------------------ activities

func _skills_panel() -> Dictionary:
	var win := kit.window("Field Notes", Vector2(700, 650))
	var summary := kit.progression_card(
		Vector2(0, 82),
		kit.palette.color("ui_good")
	)
	var summary_row := HBoxContainer.new()
	summary_row.add_theme_constant_override("separation", 14)
	summary.add_child(summary_row)
	summary_row.add_child(kit.monogram("✦", kit.palette.color("ui_good"), 48))
	var summary_copy := VBoxContainer.new()
	summary_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_row.add_child(summary_copy)
	summary_copy.add_child(kit.eyebrow("Practice, not levels"))
	summary_copy.add_child(kit.label(
		"Every session leaves a useful trail.",
		18,
		false,
		true
	))
	var total_sessions := 0
	for skill_id: String in core.registries.skills:
		total_sessions += core.progression.actions_done(skill_id)
	summary_row.add_child(kit.pill(
		"%d sessions" % total_sessions,
		kit.palette.color("ui_good")
	))
	win["content"].add_child(summary)

	var parts := _scroll_list(450.0)
	win["content"].add_child(parts["scroll"])
	var list: VBoxContainer = parts["list"]
	list.add_theme_constant_override("separation", 12)
	for skill_id: String in core.registries.skills:
		var def := core.registries.skill(skill_id)
		list.add_child(_activity_progress_card(skill_id, def))
	return win


func _activity_progress_card(
	skill_id: String,
	def: Defs.SkillDefinition
) -> Control:
	var domain := core.registries.inspiration_domain(def.domain_id)
	var accent := (
		domain.color
		if domain != null
		else kit.palette.color("ui_good")
	)
	if def.future:
		accent = Color(0.58, 0.56, 0.51)
	var card := kit.progression_card(Vector2.ZERO, accent)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 11)
	col.add_child(header)
	header.add_child(kit.monogram(def.icon_glyph, accent, 46))
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(identity)
	identity.add_child(kit.label(def.display_name, 20, false, true))
	identity.add_child(kit.eyebrow(
		"Coming soon"
		if def.future
		else "%s current" % (
			domain.display_name if domain != null else "Practice"
		),
		accent
	))
	var actions := core.progression.actions_done(skill_id)
	header.add_child(kit.pill("%d sessions" % actions, accent))

	var desc := kit.muted_label(def.description, 14)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	if def.future:
		return card

	if domain != null:
		var meter := core.progression.inspiration.meter_progress(domain.id)
		var meter_head := HBoxContainer.new()
		col.add_child(meter_head)
		var meter_name := kit.label(
			"%s Inspiration" % domain.display_name,
			14,
			false,
			true
		)
		meter_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meter_head.add_child(meter_name)
		meter_head.add_child(kit.muted_label(
			"%d / %d" % [roundi(meter["current"]), roundi(meter["cost"])],
			13
		))
		col.add_child(kit.progress_bar_colored(
			meter["fraction"],
			accent,
			610,
			11
		))

	col.add_child(kit.divider(accent.lightened(0.3)))
	col.add_child(kit.eyebrow("Next trail markers", accent))
	var upcoming_entries := core.progression.milestones.upcoming_for_activity(
		skill_id,
		actions
	)
	if upcoming_entries.is_empty():
		col.add_child(kit.muted_label(
			"Every recorded trail marker is complete.",
			13
		))
	for upcoming in upcoming_entries:
		var milestone: Defs.MilestoneDefinition = upcoming["milestone"]
		var milestone_row := PanelContainer.new()
		var milestone_style := kit.surface_style(
			accent.lightened(0.62),
			12,
			accent.lightened(0.32),
			1
		)
		milestone_style.content_margin_top = 9
		milestone_style.content_margin_bottom = 9
		milestone_row.add_theme_stylebox_override("panel", milestone_style)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		milestone_row.add_child(row)
		row.add_child(kit.pill(
			"%d more" % int(upcoming["remaining"]),
			accent
		))
		var milestone_copy := VBoxContainer.new()
		milestone_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(milestone_copy)
		milestone_copy.add_child(kit.label(
			milestone.display_name,
			14,
			false,
			true
		))
		var reward_note := _milestone_reward_note(milestone)
		if reward_note != "":
			milestone_copy.add_child(kit.muted_label(reward_note, 12))
		col.add_child(milestone_row)
	return card


func _milestone_reward_note(milestone: Defs.MilestoneDefinition) -> String:
	for reward in milestone.rewards:
		if String(reward.get("note", "")) != "":
			return String(reward["note"])
	return milestone.display_name


# ------------------------------------------------------------------ character

func _character_panel() -> Dictionary:
	var win := kit.window("%s the Keeper" % core.profile.display_name, Vector2(500, 560))
	var parts := _scroll_list(430.0)
	win["content"].add_child(parts["scroll"])
	var list: VBoxContainer = parts["list"]
	list.add_child(kit.label("Equipped", 19))
	for slot in EquipmentManager.SLOTS:
		if (
			not core.registries.feature("combat_enabled", false)
			and slot not in ["tool", "body"]
		):
			continue
		var def := core.equipment.equipped_in(slot)
		var row := HBoxContainer.new()
		var slot_label := kit.label("%s: %s" % [slot.capitalize(), def.display_name if def else "—"], 16)
		slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slot_label)
		if def != null and slot != "tool":
			var off := kit.button("Unequip")
			off.pressed.connect(func():
				core.equipment.unequip(slot)
				toggle("character")
				toggle("character"))
			row.add_child(off)
		list.add_child(row)
	list.add_child(kit.label("Owned", 19))
	for item_id: String in core.equipment.owned:
		var def := core.registries.item(item_id)
		if def == null:
			continue
		if (
			not core.registries.feature("combat_enabled", false)
			and def.slot not in ["tool", "body"]
		):
			continue
		var row := HBoxContainer.new()
		var name_label := kit.label(def.display_name, 16)
		name_label.add_theme_color_override("font_color", kit.rarity_color(def.rarity))
		name_label.tooltip_text = def.description
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		if def.slot != "" and core.equipment.equipped.get(def.slot, "") != item_id:
			var on := kit.button("Equip", true)
			on.pressed.connect(func():
				core.equipment.equip(item_id)
				toggle("character")
				toggle("character"))
			row.add_child(on)
		list.add_child(row)
	if core.registries.feature("combat_enabled", false):
		var stats := kit.label("damage %d · defense %d" % [core.combat.attack_damage(), core.combat.defense()], 14)
		list.add_child(stats)
	return win


# ------------------------------------------------------------------ collection

func _collection_panel() -> Dictionary:
	var win := kit.window("Discovery Journal", Vector2(700, 650))
	var journal_head := kit.progression_card(
		Vector2(0, 76),
		kit.palette.color("ui_accent")
	)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 13)
	journal_head.add_child(head_row)
	head_row.add_child(kit.monogram("✧", kit.palette.color("ui_accent"), 46))
	var head_copy := VBoxContainer.new()
	head_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(head_copy)
	head_copy.add_child(kit.eyebrow("A record of your world", kit.palette.color("ui_accent")))
	head_copy.add_child(kit.label(
		"%d discoveries remembered" % core.collection.total_discovered(),
		19,
		false,
		true
	))
	win["content"].add_child(journal_head)

	var parts := _scroll_list(460.0)
	win["content"].add_child(parts["scroll"])
	var list: VBoxContainer = parts["list"]
	list.add_theme_constant_override("separation", 12)
	var categories := [
		["Land tiles", "tiles", core.registries.active_tile_ids().size()],
		["Structures", "structures", core.registries.structures.size()],
		["Fish", "fish", 3],
		["Woodland notes", "woodland", 3],
	]
	for section in categories:
		var found := core.collection.discovered_in(section[1])
		if section[1] == "tiles":
			var active_found: Array = []
			for tile_id: String in found:
				if core.registries.is_tile_active(tile_id):
					active_found.append(tile_id)
			found = active_found
		var total := int(section[2])
		var accent := _journal_accent(String(section[1]))
		var category_card := kit.progression_card(Vector2.ZERO, accent)
		var category_col := VBoxContainer.new()
		category_col.add_theme_constant_override("separation", 8)
		category_card.add_child(category_col)
		var category_head := HBoxContainer.new()
		category_col.add_child(category_head)
		var category_name := kit.label(String(section[0]), 19, false, true)
		category_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		category_head.add_child(category_name)
		category_head.add_child(kit.pill(
			"%d / %d" % [found.size(), total]
			if total > 0
			else "%d found" % found.size(),
			accent
		))
		if total > 0:
			category_col.add_child(kit.progress_bar_colored(
				float(found.size()) / float(maxi(1, total)),
				accent,
				610,
				9
			))
		category_col.add_child(kit.divider(accent.lightened(0.3)))
		for id in found:
			var display := _display_name_for(section[1], id)
			var entry := core.collection.entry(section[1], id)
			var entry_row := HBoxContainer.new()
			var marker := kit.label("◆", 11)
			marker.add_theme_color_override("font_color", accent)
			entry_row.add_child(marker)
			var row_label := kit.label(display, 15, false, true)
			row_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row_label.tooltip_text = "first found %s" % String(entry.get("first_time", ""))
			entry_row.add_child(row_label)
			entry_row.add_child(kit.muted_label(
				"seen ×%d" % int(entry.get("count", 0)),
				13
			))
			category_col.add_child(entry_row)
		if total > found.size():
			var mystery := kit.muted_label(
				"◇  %d entries still wait to be found" % (total - found.size()),
				13
			)
			category_col.add_child(mystery)
		list.add_child(category_card)
	return win


func _journal_accent(category: String) -> Color:
	match category:
		"tiles":
			return Color(0.39, 0.51, 0.25)
		"structures":
			return Color(0.59, 0.40, 0.26)
		"fish":
			return Color(0.29, 0.49, 0.67)
		"woodland":
			return Color(0.31, 0.46, 0.28)
	return kit.palette.color("ui_accent")


func _display_name_for(category: String, id: String) -> String:
	match category:
		"tiles": return core.registries.tile(id).display_name if core.registries.tile(id) else id
		"structures": return core.registries.structure(id).display_name if core.registries.structure(id) else id
		"landmarks": return core.registries.landmark(id).display_name if core.registries.landmark(id) else id
		"creatures": return core.registries.enemy(id).display_name if core.registries.enemy(id) else id
		_: return core.registries.item(id).display_name if core.registries.item(id) else id.replace("_", " ").capitalize()


# ------------------------------------------------------------------ map

func _map_panel() -> Dictionary:
	var win := kit.window("Your World", Vector2(520, 540))
	var map := _WorldMap.new()
	map.core = core
	map.kit = kit
	map.custom_minimum_size = Vector2(460, 420)
	win["content"].add_child(map)
	return win


class _WorldMap:
	extends Control
	var core: GameCore
	var kit: UiKit

	func _draw() -> void:
		if core == null or core.grid.cells.is_empty():
			return
		var rect := core.grid.bounds().grow(3)
		var cell_px := minf(size.x / rect.size.x, size.y / rect.size.y)
		var origin := (size - Vector2(rect.size) * cell_px) * 0.5
		for coord: Vector2i in core.grid.cells:
			var state := core.grid.cell(coord)
			var def := core.grid.tile_def(coord)
			var pos := origin + Vector2(coord - rect.position) * cell_px
			var color := Color(0.7, 0.72, 0.3)
			if state.landmark_id != "":
				color = Color(0.55, 0.5, 0.44)
			elif def != null:
				match def.family:
					"living_grove": color = Color(0.35, 0.42, 0.2)
					"stonebound": color = Color(0.62, 0.57, 0.48)
					"waterside": color = Color(0.47, 0.65, 0.65)
			draw_rect(Rect2(pos + Vector2.ONE, Vector2(cell_px - 2, cell_px - 2)), color)
			if coord == core.grid.home_cell:
				draw_circle(pos + Vector2(cell_px, cell_px) * 0.5, cell_px * 0.18, Color(0.9, 0.75, 0.3))
		for state in core.landmarks.active:
			if state.phase == LandmarkManager.PHASE_SILHOUETTE:
				for cell in core.landmarks.footprint_cells(state):
					var pos := origin + Vector2(cell - rect.position) * cell_px
					draw_rect(Rect2(pos + Vector2.ONE, Vector2(cell_px - 2, cell_px - 2)), Color(0.3, 0.32, 0.28, 0.6))
		var player_cell := core.grid.world_to_cell(core.profile.position)
		var player_pos := origin + (Vector2(player_cell - rect.position) + Vector2(0.5, 0.5)) * cell_px
		draw_circle(player_pos, cell_px * 0.22, Color(0.85, 0.4, 0.3))


# ------------------------------------------------------------------ settings

func _settings_panel() -> Dictionary:
	var win := kit.window("Settings", Vector2(460, 460))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	win["content"].add_child(list)
	for bus_info in [["Master", "Master"], ["Music", "Music"], ["Ambience", "Ambience"], ["Effects", "SFX"], ["UI", "UI"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var bus_label: Label = kit.label(bus_info[0], 16)
		bus_label.custom_minimum_size.x = 110
		row.add_child(bus_label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.custom_minimum_size.x = 220
		var bus_index := AudioServer.get_bus_index(bus_info[1])
		slider.value = db_to_linear(AudioServer.get_bus_volume_db(bus_index)) if bus_index >= 0 else 1.0
		slider.value_changed.connect(func(v):
			if bus_index >= 0:
				AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(v, 0.001))))
		row.add_child(slider)
		list.add_child(row)
	var hold_check := CheckButton.new()
	hold_check.text = "Auto-repeat skill actions"
	hold_check.set_pressed_no_signal(true)
	hold_check.add_theme_font_override("font", kit.font)
	list.add_child(hold_check)
	list.add_child(kit.label(
		"Camera: %s  ·  %s  ·  %s"
		% [
			_input_service.format_action(&"camera_rotate_left", "Rotate"),
			_input_service.format_action(&"camera_zoom_in", "Zoom"),
			_input_service.format_action(&"return_home", "Return home"),
		],
		14
	))
	return win


# ------------------------------------------------------------------ landmark resolve dialog

# ------------------------------------------------------------------ well & shrine

## Offer an owned duplicate to the well. Only refundable pieces (owned, with
## a home domain) are listed — the well never tempts you with your last of
## anything special; what it accepts, it keeps.
func show_refund_picker() -> void:
	close()
	var win := kit.window("Offer to the Well", Vector2(660, 540))
	_open_panel = win["root"]
	_open_name = "refund"
	win["close"].pressed.connect(close)
	add_child(_open_panel)
	var col: VBoxContainer = win["content"]
	var intro_card := kit.progression_card(
		Vector2(0, 76),
		Color(0.43, 0.58, 0.67)
	)
	var intro_row := HBoxContainer.new()
	intro_row.add_theme_constant_override("separation", 12)
	intro_card.add_child(intro_row)
	intro_row.add_child(kit.monogram("◇", Color(0.43, 0.58, 0.67), 46))
	var intro_copy := VBoxContainer.new()
	intro_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro_row.add_child(intro_copy)
	intro_copy.add_child(kit.eyebrow("Carvings become promised coins"))
	var intro := kit.muted_label(
		"Offer three stored pieces from one current to earn a guaranteed Vision.",
		14
	)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_copy.add_child(intro)
	col.add_child(intro_card)

	var carving_row := HBoxContainer.new()
	carving_row.add_theme_constant_override("separation", 9)
	carving_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var shown_carvings := 0
	for domain_id: String in core.registries.inspiration_domains:
		var domain := core.registries.inspiration_domain(domain_id)
		if domain.wildcard:
			continue
		var meter := core.progression.refunds.meter(domain_id)
		var coins := core.progression.refunds.coin_count(domain_id)
		if meter > 0 or coins > 0:
			carving_row.add_child(_carving_meter_card(domain))
			shown_carvings += 1
	if shown_carvings > 0:
		col.add_child(carving_row)

	var warning := kit.muted_label(
		"Stored pieces are removed when offered. Placed pieces and your final copy stay safe.",
		12
	)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(warning)
	var parts := _scroll_list(250.0)
	col.add_child(parts["scroll"])
	var list: VBoxContainer = parts["list"]
	list.add_theme_constant_override("separation", 9)
	var listed := 0
	for entry: Dictionary in _refundable_entries():
		var kind := String(entry["kind"])
		var content_id := String(entry["id"])
		var domain := core.progression.refunds.domain_of(kind, content_id)
		var entry_card := kit.progression_card(Vector2.ZERO, domain.color)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		entry_card.add_child(row)
		row.add_child(kit.monogram(domain.icon_glyph, domain.color, 40))
		var entry_copy := VBoxContainer.new()
		entry_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(entry_copy)
		entry_copy.add_child(kit.label(String(entry["name"]), 16, false, true))
		entry_copy.add_child(kit.eyebrow(
			"%s · %d stored" % [domain.display_name, int(entry["count"])],
			domain.color
		))
		var offer := kit.button("Offer one")
		offer.tooltip_text = "Give one %s to the well." % String(entry["name"])
		offer.pressed.connect(func():
			if core.progression.refunds.refund(kind, content_id):
				show_refund_picker())   # rebuild with fresh counts and carvings
		row.add_child(offer)
		list.add_child(entry_card)
		listed += 1
	if listed == 0:
		var empty := kit.progression_card(
			Vector2(0, 92),
			Color(0.58, 0.56, 0.51)
		)
		var empty_label := kit.muted_label(
			"No eligible duplicates are waiting in your Build Bag.",
			14
		)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_child(empty_label)
		list.add_child(empty)
	panel_toggled.emit("refund", true)
	focus_default()


func _carving_meter_card(
	domain: Defs.InspirationDomainDefinition
) -> Control:
	var card := kit.progression_card(Vector2(126, 0), domain.color)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	card.add_child(col)
	var heading := kit.label(
		"%s  %s" % [domain.icon_glyph, domain.display_name],
		13,
		false,
		true
	)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(heading)
	var marks := HBoxContainer.new()
	marks.alignment = BoxContainer.ALIGNMENT_CENTER
	marks.add_theme_constant_override("separation", 6)
	col.add_child(marks)
	var meter := core.progression.refunds.meter(domain.id)
	for index in core.progression.refunds.meter_size():
		var mark := PanelContainer.new()
		mark.custom_minimum_size = Vector2(20, 20)
		var mark_style := kit.surface_style(
			domain.color
			if index < meter
			else domain.color.lightened(0.66),
			10,
			domain.color.lightened(0.22),
			1
		)
		mark_style.set_content_margin_all(0)
		mark.add_theme_stylebox_override("panel", mark_style)
		marks.add_child(mark)
	var coins := core.progression.refunds.coin_count(domain.id)
	if coins > 0:
		col.add_child(kit.pill("%d coin waiting" % coins, domain.color))
	else:
		var meter_label := kit.muted_label(
			"%d of %d carvings" % [
				meter,
				core.progression.refunds.meter_size(),
			],
			11
		)
		meter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(meter_label)
	return card


func _refundable_entries() -> Array:
	var entries: Array = []
	for tile_id: String in core.stock.tiles:
		if core.progression.refunds.can_refund("tile", tile_id):
			entries.append({
				"kind": "tile", "id": tile_id,
				"name": core.registries.tile(tile_id).display_name,
				"count": core.stock.tile_count(tile_id),
			})
	for structure_id: String in core.stock.structures:
		if core.progression.refunds.can_refund("structure", structure_id):
			entries.append({
				"kind": "structure", "id": structure_id,
				"name": core.registries.structure(structure_id).display_name,
				"count": core.stock.structure_count(structure_id),
			})
	entries.sort_custom(func(a, b): return a["name"] < b["name"])
	return entries


## Release a waiting coin: a guaranteed in-domain Vision.
func show_coin_picker() -> void:
	close()
	var win := kit.window("Promised Visions", Vector2(580, 400))
	_open_panel = win["root"]
	_open_name = "coins"
	win["close"].pressed.connect(close)
	add_child(_open_panel)
	var col: VBoxContainer = win["content"]
	var intro := kit.muted_label(
		"Each coin remembers the current that shaped it. Release one for a guaranteed three-choice Vision.",
		14
	)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(intro)
	var parts := _scroll_list(220.0)
	col.add_child(parts["scroll"])
	var list: VBoxContainer = parts["list"]
	list.add_theme_constant_override("separation", 10)
	var any_coin := false
	for domain_id: String in core.registries.inspiration_domains:
		var coins := core.progression.refunds.coin_count(domain_id)
		if coins < 1:
			continue
		var is_first := not any_coin
		any_coin = true
		var domain := core.registries.inspiration_domain(domain_id)
		var coin_card := kit.progression_card(Vector2(0, 112), domain.color)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		coin_card.add_child(row)
		row.add_child(kit.monogram(domain.icon_glyph, domain.color, 54))
		var coin_copy := VBoxContainer.new()
		coin_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(coin_copy)
		coin_copy.add_child(kit.eyebrow("Promised coin", domain.color))
		coin_copy.add_child(kit.label(
			"%s Vision" % domain.display_name,
			18,
			false,
			true
		))
		coin_copy.add_child(kit.muted_label(
			"%d waiting · three in-current choices" % coins,
			12
		))
		var b := kit.button("Release Vision", is_first)
		b.custom_minimum_size.y = 46
		b.tooltip_text = "A guaranteed %s vision." % (
			domain.display_name.to_lower()
		)
		b.pressed.connect(func():
			if core.progression.refunds.spend_coin(domain_id):
				close())
		row.add_child(b)
		list.add_child(coin_card)
	if not any_coin:
		var empty := kit.progression_card(
			Vector2(0, 120),
			Color(0.52, 0.57, 0.60)
		)
		var empty_copy := VBoxContainer.new()
		empty_copy.alignment = BoxContainer.ALIGNMENT_CENTER
		empty.add_child(empty_copy)
		var empty_title := kit.label(
			"No promised coins yet",
			18,
			false,
			true
		)
		empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_copy.add_child(empty_title)
		var empty_note := kit.muted_label(
			"Offer three duplicate pieces from one current to mint one.",
			13
		)
		empty_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_copy.add_child(empty_note)
		list.add_child(empty)
	panel_toggled.emit("coins", true)
	focus_default()


## Set the shrine's focus: any discovered piece; draws lean toward it.
func show_shrine_picker() -> void:
	close()
	var win := kit.window("Shrine Focus", Vector2(660, 620))
	_open_panel = win["root"]
	_open_name = "shrine"
	win["close"].pressed.connect(close)
	add_child(_open_panel)
	var col: VBoxContainer = win["content"]
	var current_focus := (
		core.progression.shrine.focus()
		if core.progression.shrine.has_focus()
		else {}
	)
	var focus_accent := kit.palette.color("ui_accent")
	if not current_focus.is_empty():
		var current_domain := _domain_for_piece(
			String(current_focus["kind"]),
			String(current_focus["id"])
		)
		if current_domain != null:
			focus_accent = current_domain.color
	var focus_card := kit.progression_card(Vector2(0, 84), focus_accent)
	var focus_row := HBoxContainer.new()
	focus_row.add_theme_constant_override("separation", 12)
	focus_card.add_child(focus_row)
	focus_row.add_child(kit.monogram("✦", focus_accent, 46))
	var focus_copy := VBoxContainer.new()
	focus_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_row.add_child(focus_copy)
	focus_copy.add_child(kit.eyebrow("The shrine is listening", focus_accent))
	focus_copy.add_child(kit.label(
		_shrine_entry_name(
			String(current_focus["kind"]),
			String(current_focus["id"])
		)
		if not current_focus.is_empty()
		else "No focus chosen",
		19,
		false,
		true
	))
	if not current_focus.is_empty():
		focus_copy.add_child(kit.muted_label(
			"Future Vision draws lean toward this piece and its family.",
			12
		))
	col.add_child(focus_card)

	var intro := kit.muted_label(
		"Choose any discovered piece to guide the well. A focus improves the odds; it never removes variety.",
		14
	)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(intro)
	var parts := _scroll_list(360.0)
	col.add_child(parts["scroll"])
	var list: VBoxContainer = parts["list"]
	list.add_theme_constant_override("separation", 9)
	for entry: Dictionary in _shrine_candidates():
		var kind := String(entry["kind"])
		var content_id := String(entry["id"])
		var domain := _domain_for_piece(kind, content_id)
		var accent := (
			domain.color
			if domain != null
			else kit.palette.color("ui_good")
		)
		var candidate := kit.progression_card(Vector2.ZERO, accent)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		candidate.add_child(row)
		row.add_child(kit.monogram(
			domain.icon_glyph if domain != null else "◆",
			accent,
			40
		))
		var candidate_copy := VBoxContainer.new()
		candidate_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(candidate_copy)
		candidate_copy.add_child(kit.label(
			String(entry["name"]),
			16,
			false,
			true
		))
		candidate_copy.add_child(kit.eyebrow(
			"%s · %s" % [
				domain.display_name if domain != null else "Unbound",
				kind.capitalize(),
			],
			accent
		))
		var selected := (
			not current_focus.is_empty()
			and String(current_focus["kind"]) == kind
			and String(current_focus["id"]) == content_id
		)
		var focus_button := kit.button(
			"Focused" if selected else "Set focus",
			not selected
		)
		focus_button.disabled = selected
		focus_button.tooltip_text = "Lean the well's visions toward %s." % String(entry["name"])
		focus_button.pressed.connect(func():
			if core.progression.shrine.set_focus(kind, content_id):
				close())
		row.add_child(focus_button)
		list.add_child(candidate)
	if list.get_child_count() == 0:
		list.add_child(kit.muted_label(
			"Discover a land shape or structure before asking the shrine to remember it.",
			14
		))
	panel_toggled.emit("shrine", true)
	focus_default()


func _shrine_candidates() -> Array:
	var entries: Array = []
	for tile_id: String in core.collection.discovered_in("tiles"):
		if core.progression.shrine.can_focus("tile", tile_id):
			entries.append({
				"kind": "tile", "id": tile_id,
				"name": core.registries.tile(tile_id).display_name,
			})
	for structure_id: String in core.collection.discovered_in("structures"):
		if core.progression.shrine.can_focus("structure", structure_id):
			entries.append({
				"kind": "structure", "id": structure_id,
				"name": core.registries.structure(structure_id).display_name,
			})
	entries.sort_custom(func(a, b): return a["name"] < b["name"])
	return entries


func _shrine_entry_name(kind: String, content_id: String) -> String:
	match kind:
		"tile":
			var tile := core.registries.tile(content_id)
			return tile.display_name if tile != null else content_id
		"structure":
			var structure := core.registries.structure(content_id)
			return structure.display_name if structure != null else content_id
	return content_id


func _domain_for_piece(
	kind: String,
	content_id: String
) -> Defs.InspirationDomainDefinition:
	match kind:
		VisionSystem.KIND_TILE:
			var tile := core.registries.tile(content_id)
			if tile != null:
				return core.registries.domain_for_family(tile.family)
		VisionSystem.KIND_STRUCTURE:
			return core.progression.refunds.domain_of(kind, content_id)
	return null


func show_landmark_choice(landmark_id: String) -> void:
	close()
	var def := core.registries.landmark(landmark_id)
	if def == null:
		return
	var win := kit.window(def.display_name + " is yours", Vector2(520, 360))
	_open_panel = win["root"]
	_open_name = "landmark"
	win["close"].pressed.connect(close)
	add_child(_open_panel)
	var col: VBoxContainer = win["content"]
	var intro := kit.label("The thornlings are gone. What would you like to do with it?", 16)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(intro)
	var options := [
		["Keep it here", "kept", "It stays part of your world, right where you found it."],
		["Pack into a Deed", "packed", "Store it and rebuild it anywhere beside your world."],
		["Salvage it", "salvaged", "Take its stone, metal, and relics — the land returns to the wild."],
	]
	for option in options:
		var b := kit.button(option[0], option[1] == "kept")
		b.tooltip_text = option[2]
		b.pressed.connect(func():
			landmark_resolution_chosen.emit(landmark_id, option[1])
			close())
		col.add_child(b)
		var hint := kit.label(option[2], 13)
		hint.add_theme_color_override("font_color", Color(0.5, 0.46, 0.38))
		col.add_child(hint)
	focus_default()
