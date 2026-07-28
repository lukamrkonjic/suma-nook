class_name GameCore
extends RefCounted
## Composition root for all gameplay state. Pure RefCounted — no scene tree —
## so the entire game logic runs in headless tests. Scene-side controllers
## (renderer, player, placement, HUD, audio) receive this object and subscribe
## to manager signals; they never own state.

signal world_grown(coord: Vector2i)
signal notified(message: String, tone: String)   # lightweight toast channel
signal before_save

const GameContentCatalogScript := preload("res://scripts/core/game_content_catalog.gd")
const CampingModuleScript := preload(
	"res://scripts/features/camping/camping_module.gd"
)
const CurrentSaveValidatorScript := preload(
	"res://scripts/systems/current_save_validator.gd"
)

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
var camping

var autosave_timer := 0.0
var autosave_paused := false
var play_seconds := 0.0
var view_state: Dictionary = {"yaw": 45.0, "distance": 32.0, "pan": [0.0, 0.0]}
var visual_state: Dictionary = {
	"weather": "day",
	"time_of_day": "noon",
	"background": "profile",
	"particle_quality": "high",
}
var _dirty := false

const FIRST_WATER_COORD := Vector2i(-1, -1)
const STARTER_DOCK_COORD := Vector2i(0, -1)
const DEFAULT_BODY_ITEM_ID := "cosmetic_cowboy_vest"
const SHOWCASE_STRUCTURE_IDS := [
	"struct_stone_wall_polished",
	"struct_firepit_polished",
]


func setup(data_path := "res://data", seed_value := 0) -> bool:
	registries = GameContentCatalogScript.create()
	var ok := registries.load_all(data_path)
	rng = RngService.new(seed_value)
	grid = WorldGrid.new(registries)
	profile = PlayerProfile.new()
	inventory = InventoryManager.new(registries)
	stock = StockManager.new(registries)
	camping = CampingModuleScript.new(registries, grid, stock)
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

	# Managers are RefCounted children of this composition root. Their signals
	# must not retain the root, otherwise root -> manager -> callable -> root
	# forms a permanent reference cycle each time a game session is rebuilt.
	var owner_ref: WeakRef = weakref(self)
	skills.level_up.connect(func(skill_id, new_level, unlocks):
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._on_level_up(skill_id, new_level, unlocks)
	)
	grid.grid_changed.connect(func():
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._dirty = true
	)
	grid.slot_changed.connect(func(_coord, _elevation):
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._dirty = true
	)
	inventory.items_changed.connect(func():
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._dirty = true
	)
	stock.stock_changed.connect(func():
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._dirty = true
	)
	equipment.equipment_changed.connect(func():
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._dirty = true
	)
	return ok


# ------------------------------------------------------------------ new game

func new_game(new_profile: PlayerProfile) -> void:
	profile = new_profile
	camping.reset()
	_compose_starting_world()
	grid.home_cell = Vector2i.ZERO
	profile.position = grid.cell_to_world(Vector2i.ZERO)
	# Starter kit: rod + axe owned, plus the current body-slot wardrobe sample.
	equipment.acquire("tool_rod_basic")
	equipment.acquire("tool_axe_basic")
	equipment.equip("tool_rod_basic")
	_ensure_default_body_item()
	# Trees begin unplaced in the Build Library. The storage chest is the only
	# progression utility deliberately authored into the opening world.
	stock.add_structure("struct_pine")
	_ensure_showcase_placeables()
	collection.record("gear", "tool_rod_basic")
	collection.record("gear", "tool_axe_basic")
	for coord: Vector2i in grid.cells:
		collection.record("tiles", grid.cell(coord).tile_id, 0)
	save()


## The composed opening zone: a continuous three-tile northern water edge and
## two deliberately repeated forest/path/forest rows. Only the first water
## block is movement-locked; every other opening tile uses the normal move flow.
func _compose_starting_world() -> void:
	grid.cells.clear()
	grid.stacked_cells.clear()
	var layout := {
		Vector2i(-1, -1): ["tile_open_water", 0],
		Vector2i(0, -1): ["tile_open_water", 0],
		Vector2i(1, -1): ["tile_open_water", 0],
		Vector2i(-1, 0): ["tile_grass", 0],
		Vector2i(0, 0): ["tile_plain_ground", 0],
		Vector2i(1, 0): ["tile_grass", 0],
		Vector2i(-1, 1): ["tile_grass", 0],
		Vector2i(0, 1): ["tile_plain_ground", 0],
		Vector2i(1, 1): ["tile_grass", 0],
	}
	for coord: Vector2i in layout:
		grid.place_tile(
			coord,
			layout[coord][0],
			layout[coord][1],
			true,
			coord == FIRST_WATER_COORD
		)
	# Opening furniture is independent from its terrain. Trees/vegetation do
	# not spawn by default; the first tree waits in the Build Library.
	grid.add_structure(Vector2i(-1, 1), "struct_bench", 2, 1)
	grid.add_structure(Vector2i(1, 0), "struct_chest", 2, 0)
	grid.add_structure(STARTER_DOCK_COORD, "struct_dock", 0, 2)
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
	for slot: Dictionary in grid.all_cell_slots():
		var cell_state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in cell_state.structures:
			if not structure.anchor_resting:
				continue
			structure.anchor_regen_left -= delta
			if structure.anchor_regen_left <= 0.0:
				structure.anchor_resting = false
				structure.anchor_actions_done = 0
				grid.slot_changed.emit(
					slot["coord"],
					int(slot["elevation"])
				)


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
		"stock": stock.to_save_dict(),
		"collection": collection.to_save_dict(),
		"skills": skills.to_save_dict(),
		"parcels": parcels.to_save_dict(),
		"arrivals": arrivals.to_save_dict(),
		"equipment": equipment.to_save_dict(),
		"landmarks": landmarks.to_save_dict(),
		"combat": combat.to_save_dict(),
		"features": {
			"camping": camping.to_save_dict(),
		},
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
	var data: Dictionary = raw_data
	var save_errors := CurrentSaveValidatorScript.validate(data, registries)
	if not save_errors.is_empty():
		var reason := "development save references retired content: " + save_errors[0]
		save_manager.load_failed.emit(reason)
		push_warning("SaveManager: " + reason)
		return false
	rng.from_save_dict(data.get("rng", {}))
	profile.from_save_dict(data.get("profile", {}))
	grid.from_save_dict(data.get("grid", {}))
	inventory.from_save_dict(data.get("inventory", {}))
	stock.from_save_dict(data.get("stock", {}))
	camping.from_save_dict(
		(data.get("features", {}) as Dictionary).get("camping", {})
	)
	collection.from_save_dict(data.get("collection", {}))
	skills.from_save_dict(data.get("skills", {}))
	parcels.from_save_dict(data.get("parcels", {}))
	arrivals.from_save_dict(data.get("arrivals", {}))
	equipment.from_save_dict(data.get("equipment", {}))
	landmarks.from_save_dict(data.get("landmarks", {}))
	combat.from_save_dict(data.get("combat", {}))
	var wardrobe_migrated := _ensure_default_body_item()
	var showcase_placeables_migrated := _ensure_showcase_placeables()
	view_state = data.get("view", view_state).duplicate(true)
	visual_state = data.get("visual", visual_state).duplicate(true)
	play_seconds = float(data.get("play_seconds", 0.0))
	if not grid.is_traversable(grid.world_to_cell(profile.position)):
		profile.position = grid.cell_to_world(grid.nearest_walkable(grid.world_to_cell(profile.position)))
	_dirty = wardrobe_migrated or showcase_placeables_migrated
	return true


func _ensure_default_body_item() -> bool:
	var changed := false
	if not equipment.owns(DEFAULT_BODY_ITEM_ID):
		equipment.acquire(DEFAULT_BODY_ITEM_ID)
		collection.record("gear", DEFAULT_BODY_ITEM_ID)
		changed = true
	if equipment.equipped_in("body") == null:
		changed = equipment.equip(DEFAULT_BODY_ITEM_ID) or changed
	return changed


## New authored showcase objects should be immediately discoverable in Build
## mode without replacing their legacy counterparts. Existing saves receive
## one only when that object is neither stored nor already placed.
func _ensure_showcase_placeables() -> bool:
	var changed := false
	for structure_id: String in SHOWCASE_STRUCTURE_IDS:
		if stock.structure_count(structure_id) > 0:
			continue
		var is_placed := false
		for slot: Dictionary in grid.all_cell_slots():
			var state: WorldGrid.CellState = slot["state"]
			for structure: WorldGrid.StructureState in state.structures:
				if structure.structure_id == structure_id:
					is_placed = true
					break
			if is_placed:
				break
		if is_placed:
			continue
		stock.add_structure(structure_id)
		changed = true
	return changed
