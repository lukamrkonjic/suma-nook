class_name GamePanels
extends CanvasLayer
## All modal panels. One panel open at a time; Esc closes. Compact — the
## world stays visible around every card.

signal panel_toggled(panel_name: String, open: bool)
signal landmark_resolution_chosen(landmark_id: String, resolution: String)

var core: GameCore
var kit: UiKit
var settings_bridge: Node   # main.gd — exposes audio volumes / profile toggle

var _open_panel: Control
var _open_name := ""


func setup(game_core: GameCore, ui_kit: UiKit, bridge: Node) -> void:
	core = game_core
	kit = ui_kit
	settings_bridge = bridge


func is_open() -> bool:
	return _open_panel != null


func close() -> void:
	if _open_panel != null:
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
		"debug": win = _debug_panel()
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


func _scroll_list(height := 380.0) -> Dictionary:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, height)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	for tile_id: String in core.stock.tiles:
		var tile := core.registries.tile(tile_id)
		if tile == null:
			continue
		list.add_child(kit.label("⬢ %s ×%d" % [tile.display_name, core.stock.tile_count(tile_id)], 16))
	if core.stock.tiles.is_empty():
		list.add_child(kit.label("No unplaced tiles yet. The ferry brings Land Parcels.", 14))
	list.add_child(kit.label("Build Library", 20))
	for structure_id: String in core.stock.structures:
		var structure := core.registries.structure(structure_id)
		if structure == null:
			continue
		list.add_child(kit.label("⌂ %s ×%d" % [structure.display_name, core.stock.structure_count(structure_id)], 16))
	if core.stock.structures.is_empty():
		list.add_child(kit.label("No stored decorations yet.", 14))
	list.add_child(kit.label("Press B to place anything from either library.", 14))
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


# ------------------------------------------------------------------ skills

func _skills_panel() -> Dictionary:
	var win := kit.window("Skills", Vector2(520, 540))
	var parts := _scroll_list(420.0)
	win["content"].add_child(parts["scroll"])
	var list: VBoxContainer = parts["list"]
	for skill_id: String in core.registries.skills:
		var def := core.registries.skill(skill_id)
		var card := kit.card()
		var col := VBoxContainer.new()
		card.add_child(col)
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 8)
		col.add_child(header)
		header.add_child(kit.label(def.icon_glyph, 22))
		var title := kit.label("%s — level %d" % [def.display_name, core.skills.level(skill_id)], 18)
		if def.future:
			title.text = "%s — coming soon" % def.display_name
		header.add_child(title)
		if not def.future:
			var progress := core.skills.xp_progress(skill_id)
			col.add_child(kit.progress_bar(progress["fraction"], "ui_good", 300))
			col.add_child(kit.label("%d / %d xp" % [progress["current"], progress["needed"]], 13))
		var desc := kit.label(def.description, 14)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 420
		col.add_child(desc)
		for unlock in core.skills.upcoming_unlocks(skill_id):
			col.add_child(kit.label("  lvl %d → %s" % [int(unlock["level"]), String(unlock.get("note", ""))], 13))
		list.add_child(card)
	return win


# ------------------------------------------------------------------ character

func _character_panel() -> Dictionary:
	var win := kit.window("%s the Keeper" % core.profile.display_name, Vector2(500, 560))
	var parts := _scroll_list(430.0)
	win["content"].add_child(parts["scroll"])
	var list: VBoxContainer = parts["list"]
	list.add_child(kit.label("Equipped", 19))
	for slot in EquipmentManager.SLOTS:
		if not core.registries.feature("combat_enabled", false) and slot != "tool":
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
		if not core.registries.feature("combat_enabled", false) and def.slot != "tool":
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
	var win := kit.window("Collection — %d discoveries" % core.collection.total_discovered(), Vector2(540, 560))
	var parts := _scroll_list(440.0)
	win["content"].add_child(parts["scroll"])
	var list: VBoxContainer = parts["list"]
	var categories := [
		["Land tiles", "tiles", core.registries.tiles.size()],
		["Structures", "structures", core.registries.structures.size()],
		["Fish", "fish", 3],
		["Woodland notes", "woodland", 3],
	]
	for section in categories:
		var found := core.collection.discovered_in(section[1])
		var total := int(section[2])
		var header_text: String = section[0] + ("  %d/%d" % [found.size(), total] if total > 0 else "  %d" % found.size())
		list.add_child(kit.label(header_text, 19))
		for id in found:
			var display := _display_name_for(section[1], id)
			var entry := core.collection.entry(section[1], id)
			var row_label := kit.label("• %s  ×%d" % [display, int(entry.get("count", 0))], 15)
			row_label.tooltip_text = "first found %s" % String(entry.get("first_time", ""))
			list.add_child(row_label)
		if total > found.size():
			var mystery := kit.label("  … and %d still hidden" % (total - found.size()), 13)
			mystery.add_theme_color_override("font_color", Color(0.55, 0.5, 0.42))
			list.add_child(mystery)
	return win


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
	var weather_button := kit.button("Toggle weather (day / mist / rain)")
	weather_button.pressed.connect(func(): settings_bridge.call("toggle_weather"))
	list.add_child(weather_button)
	var hold_check := CheckButton.new()
	hold_check.text = "Auto-repeat skill actions"
	hold_check.set_pressed_no_signal(true)
	hold_check.add_theme_font_override("font", kit.font)
	list.add_child(hold_check)
	list.add_child(kit.label("Camera: ←/→ or Q/X rotate · ↑/↓ or wheel zoom · H return home", 14))
	return win


# ------------------------------------------------------------------ debug (dev builds only)

func _debug_panel() -> Dictionary:
	var win := kit.window("Admin Debug Controls", Vector2(660, 720))
	var parts := _scroll_list(590.0)
	win["content"].add_child(parts["scroll"])
	var list: VBoxContainer = parts["list"]
	var asset_world := kit.button("Open Asset World", true)
	asset_world.name = "OpenAssetWorldButton"
	asset_world.tooltip_text = "Browse the curated tile and large-placeable library."
	asset_world.pressed.connect(func():
		settings_bridge.call_deferred("debug_open_asset_world")
	)
	list.add_child(asset_world)
	var asset_world_hint := kit.label(
		"Tiles and substantial placeables get one clear slot each. Small scatter stays hidden.",
		14
	)
	asset_world_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(asset_world_hint)
	list.add_child(kit.label("Content library", 20))
	for action in [
		["Get every item ×99", func(): settings_bridge.call("debug_grant_all_items")],
		["Get every tile ×10", func(): settings_bridge.call("debug_grant_all_tiles")],
		["Get every structure ×10", func(): settings_bridge.call("debug_grant_all_structures")],
		["Get absolutely everything", func(): settings_bridge.call("debug_grant_all_content")],
	]:
		var content_button := kit.button(action[0], action[0] == "Get absolutely everything")
		content_button.pressed.connect(action[1])
		list.add_child(content_button)

	var lighting := settings_bridge.get("lighting") as LightingRig
	if lighting != null:
		_debug_choice_row(list, "Weather", [
			["Day", "day"],
			["Mist", "mist"],
			["Rain", "rain"],
			["Leaves", "leaves"],
			["Snow", "snow"],
			["Blossom", "blossom"],
		], "debug_set_weather", lighting.weather_id())
		_debug_choice_row(list, "Time of day", [
			["Morning", "morning"],
			["Noon", "noon"],
			["Sunset", "sunset"],
			["Night", "night"],
		], "debug_set_time_of_day", lighting.time_of_day_id)
		_debug_choice_row(list, "Background", [
			["Profile", "profile"],
			["Cream", "cream"],
			["Mist", "mist"],
			["Dusk", "dusk"],
			["Night", "night"],
		], "debug_set_background", lighting.background_preset_id)
		_debug_choice_row(list, "Particle quality", [
			["Low", "low"],
			["Medium", "medium"],
			["High", "high"],
		], "debug_set_particle_quality", lighting.particle_quality_id)
		var reset_visuals := kit.button("Reset visual overrides")
		reset_visuals.pressed.connect(func(): settings_bridge.call("debug_reset_visuals"))
		list.add_child(reset_visuals)

	list.add_child(kit.label("World and progression", 20))
	var actions := [
		["Trigger ferry arrival", func(): core.arrivals.trigger_arrival()],
		["Force ferry delivery/departure", func(): settings_bridge.call("debug_force_ferry_departure")],
		["Grant parcel at dock", func(): settings_bridge.call("debug_grant_dock_parcel")],
		["Speed arrival timer ×60", func(): core.arrivals.debug_speed_multiplier = 60.0],
		["Pause / resume arrival timer", func(): core.arrivals.paused = not core.arrivals.paused],
		["Switch ferry / postcard", func(): settings_bridge.call("debug_toggle_arrival_presentation")],
		["Grant 100 Fishing XP", func(): core.skills.add_xp("fishing", 100)],
		["Grant 100 Woodland Tending XP", func(): core.skills.add_xp("woodcutting", 100)],
		["Speed regen (all groves)", _debug_speed_regen],
		["Save now", func(): core.save()],
		["Reload save", func(): settings_bridge.call("reload_from_save")],
		["Reset world (delete save)", func(): settings_bridge.call("reset_world")],
	]
	for action in actions:
		var b := kit.button(action[0])
		b.pressed.connect(action[1])
		list.add_child(b)
	list.add_child(kit.label("Arrival: %s · %.1fs · presentation: %s · parcels opened: %d" % [
		core.arrivals.state, core.arrivals.time_until_next,
		core.arrivals.presentation_id, core.parcels.opened_count], 13))
	list.add_child(kit.label("Combat=%s · monsters=%s · material loot=%s" % [
		str(core.registries.feature("combat_enabled")),
		str(core.registries.feature("monsters_enabled")),
		str(core.registries.feature("legacy_material_loot_enabled"))], 13))
	list.add_child(kit.label("Seed: %d" % core.rng.world_seed, 13))
	return win


func _debug_choice_row(
	list: VBoxContainer,
	title: String,
	choices: Array,
	method_name: String,
	active_id: String
) -> void:
	list.add_child(kit.label(title, 20))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("separation", 6)
	list.add_child(row)
	for choice in choices:
		var preset_id := String(choice[1])
		var button := kit.button(String(choice[0]), preset_id == active_id)
		button.pressed.connect(_debug_apply_visual_choice.bind(method_name, preset_id))
		row.add_child(button)


func _debug_apply_visual_choice(method_name: String, preset_id: String) -> void:
	settings_bridge.call(method_name, preset_id)


func _debug_speed_regen() -> void:
	for coord: Vector2i in core.grid.cells:
		core.grid.cell(coord).anchor_regen_left = 0.5


# ------------------------------------------------------------------ landmark resolve dialog

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
