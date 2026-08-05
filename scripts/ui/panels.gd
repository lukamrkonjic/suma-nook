class_name GamePanels
extends CanvasLayer
## All modal panels. One panel open at a time; Esc closes. Compact — the
## world stays visible around every card.

signal panel_toggled(panel_name: String, open: bool)
signal landmark_resolution_chosen(landmark_id: String, resolution: String)
signal basket_tile_bundle_taken(haul_id: int, entry_index: int)
signal basket_model_taken(haul_id: int, entry_index: int)

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
		if tile == null:
			continue
		visible_tile_count += 1
		list.add_child(kit.label("⬢ %s ×%d" % [tile.display_name, core.stock.tile_count(tile_id)], 16))
	if visible_tile_count == 0:
		list.add_child(kit.label("No unplaced tiles yet. Fish from an exposed edge to find one.", 14))
	list.add_child(kit.label("Build Library", 20))
	for structure_id: String in core.stock.structures:
		var structure := core.registries.structure(structure_id)
		if structure == null:
			continue
		list.add_child(kit.label("⌂ %s ×%d" % [structure.display_name, core.stock.structure_count(structure_id)], 16))
	if core.stock.structures.is_empty():
		list.add_child(kit.label("No stored decorations yet.", 14))
	list.add_child(kit.label(
		"Use the persistent Build Bag below to place anything from either library.",
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
	cost_label.add_theme_color_override("font_color", kit.palette.color("ui_cost"))
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
	var accent := kit.palette.color("ui_good")
	if skill_id == "fishing":
		accent = kit.palette.color("ui_info")
	elif skill_id == "mining":
		accent = kit.palette.color("ui_neutral")
	if def.future:
		accent = kit.palette.color("ui_future")
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
		else "Biomes shape discoveries",
		accent
	))
	var actions := core.progression.actions_done(skill_id)
	header.add_child(kit.pill("%d sessions" % actions, accent))

	var desc := kit.muted_label(def.description, 14)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	if def.future:
		return card

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
			return kit.palette.color("ui_journal_tiles")
		"structures":
			return kit.palette.color("ui_journal_structures")
		"fish":
			return kit.palette.color("ui_journal_fish")
		"woodland":
			return kit.palette.color("ui_journal_woodland")
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
			var color := kit.palette.color("ui_map_default")
			if state.landmark_id != "":
				color = kit.palette.color("ui_map_empty")
			elif def != null:
				match def.family:
					"living_grove": color = kit.palette.color("ui_map_grove")
					"stonebound": color = kit.palette.color("ui_map_stone")
					"waterside": color = kit.palette.color("ui_map_water")
			draw_rect(Rect2(pos + Vector2.ONE, Vector2(cell_px - 2, cell_px - 2)), color)
			if coord == core.grid.home_cell:
				draw_circle(
					pos + Vector2(cell_px, cell_px) * 0.5,
					cell_px * 0.18,
					kit.palette.color("ui_map_landmark")
				)
		for state in core.landmarks.active:
			if state.phase == LandmarkManager.PHASE_SILHOUETTE:
				for cell in core.landmarks.footprint_cells(state):
					var pos := origin + Vector2(cell - rect.position) * cell_px
					draw_rect(
						Rect2(pos + Vector2.ONE, Vector2(cell_px - 2, cell_px - 2)),
						kit.palette.color("ui_map_unexplored")
					)
		var player_cell := core.grid.world_to_cell(core.profile.position)
		var player_pos := origin + (Vector2(player_cell - rect.position) + Vector2(0.5, 0.5)) * cell_px
		draw_circle(
			player_pos,
			cell_px * 0.22,
			kit.palette.color("ui_map_player")
		)


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

# ------------------------------------------------------------------ catch basket

func show_catch_basket() -> void:
	close()
	var win := kit.window("Catch Basket", Vector2(680, 580))
	_open_panel = win["root"]
	_open_name = "catch_basket"
	win["close"].pressed.connect(close)
	add_child(_open_panel)
	var col: VBoxContainer = win["content"]

	var basket: CatchBasketAdapter = core.fishing.basket
	col.add_child(kit.eyebrow(
		"%d OF %d HAULS WAITING" % [basket.haul_count(), basket.capacity()],
		kit.palette.color("ui_accent")
	))

	var parts := _scroll_list(430.0)
	col.add_child(parts["scroll"])
	var list: VBoxContainer = parts["list"]
	list.add_theme_constant_override("separation", 9)
	for haul: FishingHaul in basket.hauls:
		list.add_child(_basket_haul_card(haul))
	if basket.haul_count() == 0:
		var empty := kit.progression_card(
			Vector2(0, 110),
			kit.palette.color("ui_future")
		)
		var note := kit.muted_label(
			"The basket is empty. Fish from any exposed edge and the void's hauls will wait here.",
			14
		)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_child(note)
		list.add_child(empty)
	panel_toggled.emit("catch_basket", true)
	focus_default()


func _basket_haul_card(haul: FishingHaul) -> Control:
	var card := kit.progression_card(Vector2.ZERO, kit.palette.color("ui_accent"))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	card.add_child(column)
	var size_names := {
		FishingHaul.SIZE_SINGLE: "Catch",
		FishingHaul.SIZE_RICH: "Rich Catch",
		FishingHaul.SIZE_BOUNTIFUL: "Bountiful Catch",
	}
	column.add_child(kit.eyebrow(
		String(size_names.get(haul.catch_size, "Catch")).to_upper(),
		kit.palette.color("ui_accent")
	))
	for entry_index in haul.entries.size():
		var entry: FishingReward = haul.entries[entry_index]
		column.add_child(_basket_entry_row(haul, entry_index, entry))
	if haul.keepsake != null:
		column.add_child(_basket_keepsake_row(haul))
	var discard_row := HBoxContainer.new()
	discard_row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(discard_row)
	var discard := kit.button("Return to the void")
	discard.tooltip_text = "Let this whole haul go. The void keeps what it takes back."
	discard.pressed.connect(func():
		core.fishing.basket.discard_haul(haul.haul_id)
		show_catch_basket()
	)
	discard_row.add_child(discard)
	return card


func _basket_entry_row(
	haul: FishingHaul,
	entry_index: int,
	entry: FishingReward
) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	var display_name := entry.building_id
	if entry.form == FishingReward.FORM_TILE_BUNDLE:
		var tile := core.registries.tile(entry.building_id)
		if tile != null:
			display_name = tile.display_name
		copy.add_child(kit.label(
			"%s × %d" % [display_name, entry.quantity], 16, false, true
		))
		copy.add_child(kit.eyebrow(
			"TILE BUNDLE · %s" % entry.rarity.to_upper(),
			kit.palette.color("ui_accent")
		))
		var place := kit.button("Place tiles")
		place.disabled = entry.quantity <= 0
		place.tooltip_text = "Take the bundle into tile placement. Unplaced tiles return here."
		place.pressed.connect(func():
			basket_tile_bundle_taken.emit(haul.haul_id, entry_index)
		)
		row.add_child(place)
	else:
		var structure := core.registries.structure(entry.building_id)
		if structure != null:
			display_name = structure.display_name
		copy.add_child(kit.label(display_name, 16, false, true))
		copy.add_child(kit.eyebrow(
			"MODEL · %s" % entry.rarity.to_upper(),
			kit.palette.color("ui_accent")
		))
		var place := kit.button("Place it")
		place.tooltip_text = "Take this model into placement mode."
		place.pressed.connect(func():
			basket_model_taken.emit(haul.haul_id, entry_index)
		)
		row.add_child(place)
	return row


func _basket_keepsake_row(haul: FishingHaul) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	var definition := core.registries.keepsake(haul.keepsake.building_id)
	var display_name := (
		definition.display_name if definition != null else haul.keepsake.building_id
	)
	copy.add_child(kit.label("%s ❖" % display_name, 16, false, true))
	var hint := kit.muted_label(
		definition.description if definition != null else "", 13
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(hint)
	var activate := kit.button("Activate", true)
	activate.tooltip_text = "Wake the keepsake. Its gift stays with you forever."
	activate.pressed.connect(func():
		var keepsake_id: String = core.fishing.activate_keepsake_from_basket(haul.haul_id)
		if keepsake_id != "":
			core.notified.emit("%s hums to life." % display_name, "levelup")
		show_catch_basket()
	)
	row.add_child(activate)
	return row


# ------------------------------------------------------------------ spirit pouch

func show_spirit_pouch() -> void:
	close()
	var win := kit.window("Spirit Pouch", Vector2(560, 470))
	_open_panel = win["root"]
	_open_name = "spirit_pouch"
	win["close"].pressed.connect(close)
	add_child(_open_panel)
	var col: VBoxContainer = win["content"]

	var pouch: SpiritPouchService = core.fishing.pouch
	var armed := pouch.armed_index()

	var wild_card := kit.progression_card(Vector2(0, 74), kit.palette.color("ui_accent"))
	var wild_row := HBoxContainer.new()
	wild_row.add_theme_constant_override("separation", 10)
	wild_card.add_child(wild_row)
	var wild_copy := VBoxContainer.new()
	wild_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wild_row.add_child(wild_copy)
	wild_copy.add_child(kit.label("Wild Cast", 16, false, true))
	wild_copy.add_child(kit.eyebrow(
		"NO CHARM · THE VOID DECIDES" + (" · ARMED" if armed < 0 else ""),
		kit.palette.color("ui_accent")
	))
	var wild_button := kit.button("Fish wild", armed < 0)
	wild_button.disabled = armed < 0
	wild_button.pressed.connect(func():
		core.fishing.pouch.select_wild_cast()
		show_spirit_pouch()
	)
	wild_row.add_child(wild_button)
	col.add_child(wild_card)

	var slots := pouch.slots()
	for slot_index in pouch.capacity():
		var card := kit.progression_card(Vector2(0, 68), kit.palette.color("ui_accent"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		if slot_index < slots.size():
			var spirit := core.registries.spirit(slots[slot_index])
			var spirit_name := spirit.display_name if spirit != null else slots[slot_index]
			copy.add_child(kit.label(spirit_name, 16, false, true))
			copy.add_child(kit.eyebrow(
				("ARMED FOR THE NEXT CATCH" if slot_index == armed else "RESTING IN ITS SLOT"),
				kit.palette.color("ui_accent")
			))
			var arm := kit.button("Arm" if slot_index != armed else "Armed", slot_index != armed)
			arm.disabled = slot_index == armed
			arm.pressed.connect(func():
				core.fishing.pouch.arm_slot(slot_index)
				show_spirit_pouch()
			)
			row.add_child(arm)
		else:
			copy.add_child(kit.muted_label("An empty charm slot.", 14))
		col.add_child(card)
	panel_toggled.emit("spirit_pouch", true)
	focus_default()


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
		hint.add_theme_color_override("font_color", kit.palette.color("ui_cost"))
		col.add_child(hint)
	focus_default()
