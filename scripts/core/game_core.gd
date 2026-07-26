class_name GameCore
extends RefCounted
## Composition root for all gameplay state. Pure RefCounted — no scene tree —
## so the entire game logic runs in headless tests. Scene-side controllers
## (renderer, player, placement, HUD, audio) receive this object and subscribe
## to manager signals; they never own state.

signal world_grown(coord: Vector2i)
signal notified(message: String, tone: String)   # lightweight toast channel
signal before_save

var registries: Registries
var rng: RngService
var grid: WorldGrid
var profile: PlayerProfile
var inventory: InventoryManager
var stock: StockManager
var collection: CollectionManager
var skills: SkillManager
var rewards: RewardManager
var parcels: ParcelManager
var arrivals: ArrivalScheduler
var crafting: CraftingManager
var equipment: EquipmentManager
var landmarks: LandmarkManager
var combat: CombatManager
var save_manager: SaveManager
var content_compatibility: ContentCompatibility
var save_migrator: SaveMigrator
var world_reconciler: WorldStateReconciler

var autosave_timer := 0.0
var autosave_paused := false
var play_seconds := 0.0
var view_state: Dictionary = {"yaw": 45.0, "distance": 40.0}
var visual_state: Dictionary = {
	"weather": "day",
	"time_of_day": "noon",
	"background": "profile",
	"particle_quality": "high",
}
var _dirty := false
var legacy_inventory: Dictionary = {}


func setup(data_path := "res://data", seed_value := 0) -> bool:
	registries = Registries.new()
	var ok := registries.load_all(data_path)
	for error: String in ContentValidator.validate(registries):
		push_error("ContentValidator: " + error)
		ok = false
	content_compatibility = ContentCompatibility.new()
	if not content_compatibility.load_from(data_path + "/content_compat.json"):
		for error in content_compatibility.load_errors:
			push_error("ContentCompatibility: " + error)
		ok = false
	if content_compatibility.revision != registries.tunei("content_revision", 0):
		push_error(
			"ContentCompatibility: catalog revision %d does not match tuning revision %d"
			% [
				content_compatibility.revision,
				registries.tunei("content_revision", 0),
			]
		)
		ok = false
	save_migrator = SaveMigrator.new(registries, content_compatibility)
	world_reconciler = WorldStateReconciler.new(registries)
	rng = RngService.new(seed_value)
	grid = WorldGrid.new(registries)
	profile = PlayerProfile.new()
	inventory = InventoryManager.new(registries)
	stock = StockManager.new(registries)
	collection = CollectionManager.new(registries)
	skills = SkillManager.new(registries)
	rewards = RewardManager.new(registries, rng, inventory, stock, collection)
	parcels = ParcelManager.new(registries, rng, inventory, stock, collection, skills)
	arrivals = ArrivalScheduler.new(registries, rng)
	equipment = EquipmentManager.new(registries)
	crafting = CraftingManager.new(registries, inventory, stock, skills, equipment, collection)
	landmarks = LandmarkManager.new(registries, rng, grid, stock, rewards, equipment, collection)
	combat = CombatManager.new(registries, landmarks, rewards, equipment, collection)
	save_manager = SaveManager.new(registries)

	skills.level_up.connect(_on_level_up)
	if registries.feature("legacy_material_loot_enabled", false):
		inventory.item_gained.connect(func(item_id, count, _rare): _record_material(item_id, count))
	grid.grid_changed.connect(func(): _dirty = true)
	grid.slot_changed.connect(func(_coord, _elevation): _dirty = true)
	inventory.items_changed.connect(func(): _dirty = true)
	stock.stock_changed.connect(func(): _dirty = true)
	equipment.equipment_changed.connect(func(): _dirty = true)
	return ok


# ------------------------------------------------------------------ new game

func new_game(new_profile: PlayerProfile) -> void:
	profile = new_profile
	_compose_starting_world()
	grid.home_cell = Vector2i.ZERO
	profile.position = grid.cell_to_world(Vector2i.ZERO)
	# Starter kit: rod + axe owned; rod visible; starter outfit is the profile.
	equipment.acquire("tool_rod_basic")
	equipment.acquire("tool_axe_basic")
	equipment.equip("tool_rod_basic")
	collection.record("gear", "tool_rod_basic")
	collection.record("gear", "tool_axe_basic")
	for coord: Vector2i in grid.cells:
		collection.record("tiles", grid.cell(coord).tile_id, 0)
	save()


## The composed 3×3: six land tiles and one continuous northern water edge.
func _compose_starting_world() -> void:
	grid.cells.clear()
	grid.stacked_cells.clear()
	var layout := {
		Vector2i(-1, -1): ["tile_open_water", 0],
		Vector2i(0, -1): ["tile_open_water", 0],
		Vector2i(1, -1): ["tile_open_water", 0],
		Vector2i(-1, 0): ["tile_grass", 0],
		Vector2i(0, 0): ["tile_grass", 0],
		Vector2i(1, 0): ["tile_grass_flower", 0],
		Vector2i(-1, 1): ["tile_grass_flower", 2],
		Vector2i(0, 1): ["tile_path", 0],
		Vector2i(1, 1): ["tile_grass", 0],
	}
	for coord: Vector2i in layout:
		grid.place_tile(coord, layout[coord][0], layout[coord][1], true)
	# A resting place, storage, and a few pretty props — composed, not scattered.
	grid.add_structure(Vector2i(-1, 1), "struct_bench", 2, 1)
	grid.add_structure(Vector2i(1, 0), "struct_chest", 2, 0)
	grid.add_structure(Vector2i(1, 0), "struct_pot", 1, 0)
	grid.add_structure(Vector2i(1, 1), "struct_lantern", 3, 0)
	grid.add_structure(Vector2i(-1, 0), "struct_pine", 3, 0)
	grid.add_structure(Vector2i(-1, 0), "struct_bush", 2, 0)
	for coord: Vector2i in grid.cells:
		for s in grid.cell(coord).structures:
			collection.record("structures", s.structure_id, 0)


# ------------------------------------------------------------------ flow hooks

func _on_level_up(skill_id: String, new_level: int, unlocks: Array) -> void:
	var grants := rewards.on_level_unlocks(unlocks)
	for unlock in unlocks:
		var note := String(unlock.get("note", ""))
		if note != "":
			notified.emit("%s %d — %s" % [registries.skill(skill_id).display_name, new_level, note], "levelup")
	_dirty = true
	autosave_soon()


func place_tile_from_stock(
	coord: Vector2i,
	tile_id: String,
	rotation: int,
	elevation: int = 0
) -> bool:
	if not grid.can_place_tile_at(coord, elevation, tile_id) or not stock.take_tile(tile_id):
		return false
	grid.place_tile_at(coord, elevation, tile_id, rotation)
	collection.record_placed("tiles", tile_id)
	if elevation == 0 and registries.feature("hostile_landmarks_enabled", false):
		landmarks.on_world_grown()
	world_grown.emit(coord)
	autosave_soon()
	return true


func _record_material(item_id: String, count: int) -> void:
	var def := registries.item(item_id)
	if def == null:
		return
	var category := "fish" if def.tags.has("fish") else def.category + "s"
	collection.record(category, item_id, count)


# ------------------------------------------------------------------ tick & persistence

func tick(delta: float) -> void:
	play_seconds += delta
	arrivals.tick(delta)
	if registries.feature("combat_enabled", false):
		combat.tick(delta)
	_tick_anchors(delta)
	if autosave_paused:
		return
	autosave_timer += delta
	if autosave_timer >= registries.tunef("autosave_interval", 40.0) and _dirty:
		save()


func _tick_anchors(delta: float) -> void:
	for coord: Vector2i in grid.cells:
		var state := grid.cell(coord)
		if not state.anchor_resting:
			continue
		state.anchor_regen_left -= delta
		if state.anchor_regen_left <= 0.0:
			state.anchor_resting = false
			state.anchor_actions_done = 0
			grid.slot_changed.emit(coord, 0)
			grid.cell_changed.emit(coord)


func autosave_soon() -> void:
	autosave_timer = registries.tunef("autosave_interval", 40.0)
	_dirty = true


func save() -> bool:
	before_save.emit()
	autosave_timer = 0.0
	var saved := save_manager.write({
		"rng": rng.to_save_dict(),
		"profile": profile.to_save_dict(),
		"grid": grid.to_save_dict(),
		"inventory": inventory.to_save_dict(),
		"legacy_inventory": legacy_inventory.duplicate(true),
		"stock": stock.to_save_dict(),
		"collection": collection.to_save_dict(),
		"skills": skills.to_save_dict(),
		"rewards": rewards.to_save_dict(),
		"parcels": parcels.to_save_dict(),
		"arrivals": arrivals.to_save_dict(),
		"equipment": equipment.to_save_dict(),
		"landmarks": landmarks.to_save_dict(),
		"combat": combat.to_save_dict(),
		"view": view_state.duplicate(true),
		"visual": visual_state.duplicate(true),
		"play_seconds": play_seconds,
	})
	_dirty = not saved
	return saved


func load_game() -> bool:
	var raw_data := save_manager.read()
	if raw_data.is_empty():
		return false
	var migration := save_migrator.migrate(raw_data)
	var data: Dictionary = migration["data"]
	for warning: String in migration["warnings"]:
		push_warning("SaveMigrator: " + warning)
	rng.from_save_dict(data.get("rng", {}))
	profile.from_save_dict(data.get("profile", {}))
	grid.from_save_dict(data.get("grid", {}))
	legacy_inventory = data.get("legacy_inventory", {}).duplicate(true)
	inventory.from_save_dict(data.get("inventory", {}))
	stock.from_save_dict(data.get("stock", {}))
	collection.from_save_dict(data.get("collection", {}))
	skills.from_save_dict(data.get("skills", {}))
	rewards.from_save_dict(data.get("rewards", {}))
	parcels.from_save_dict(data.get("parcels", {}))
	arrivals.from_save_dict(data.get("arrivals", {}))
	equipment.from_save_dict(data.get("equipment", {}))
	landmarks.from_save_dict(data.get("landmarks", {}))
	combat.from_save_dict(data.get("combat", {}))
	var reconciliation := world_reconciler.reconcile(grid, stock)
	for warning: String in reconciliation["warnings"]:
		push_warning("WorldStateReconciler: " + warning)
	view_state = data.get("view", view_state).duplicate(true)
	visual_state = data.get("visual", visual_state).duplicate(true)
	play_seconds = float(data.get("play_seconds", 0.0))
	if not grid.is_walkable(grid.world_to_cell(profile.position)):
		profile.position = grid.cell_to_world(grid.nearest_walkable(grid.world_to_cell(profile.position)))
	_dirty = bool(migration["changed"]) or bool(reconciliation["changed"])
	return true
