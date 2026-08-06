class_name GameCore
extends RefCounted
## Composition root for all gameplay state. Pure RefCounted — no scene tree —
## so the entire game logic runs in headless tests. Scene-side controllers
## (renderer, player, placement, HUD, audio) receive this object and subscribe
## to manager signals; they never own state.

signal world_grown(coord: Vector2i)
signal notified(message: String, tone: String)   # lightweight toast channel
signal before_save
signal anchor_regenerated(coord: Vector2i, elevation: int, instance_id: int)
signal onboarding_guidance_ready(kind: String, content_id: String)

const GameContentCatalogScript := preload("res://scripts/core/game_content_catalog.gd")
const CampingModuleScript := preload(
	"res://scripts/features/camping/camping_module.gd"
)
const InteractionRegistryScript := preload(
	"res://scripts/core/interaction_registry.gd"
)
const FireSystemScript := preload(
	"res://scripts/features/fire/fire_system.gd"
)
const FireInteractionsScript := preload(
	"res://scripts/features/fire/fire_interactions.gd"
)
const CurrentSaveValidatorScript := preload(
	"res://scripts/systems/current_save_validator.gd"
)
const FishingModuleScript := preload(
	"res://scripts/features/fishing/fishing_module.gd"
)
const BuildRewardServiceScript := preload(
	"res://scripts/features/rewards/build_reward_service.gd"
)
const HarvestingModuleScript := preload(
	"res://scripts/features/harvesting/harvesting_module.gd"
)
const VisitorModuleScript := preload(
	"res://scripts/features/visitors/visitor_module.gd"
)

var registries: Registries
var rng: RngService
var grid: WorldGrid
var profile: PlayerProfile
var inventory: InventoryManager
var stock: StockManager
var collection: CollectionManager
var progression: ProgressionModule
var onboarding: OnboardingState
var rewards: RewardManager
var arrivals: ArrivalScheduler
var crafting: CraftingManager
var equipment: EquipmentManager
var landmarks: LandmarkManager
var combat: CombatManager
var save_manager: SaveManager
var camping
var fire
var fishing
var build_rewards
var harvesting
var visitors
var interactions

var autosave_timer := 0.0
var autosave_paused := false
var play_seconds := 0.0
var view_state: Dictionary = {"yaw": 45.0, "distance": 37.0, "pan": [0.0, 0.0]}
var visual_state: Dictionary = {
	"weather": "day",
	"time_of_day": "noon",
	"background": "profile",
	"particle_quality": "high",
}
var _dirty := false
var _anchor_tick_accum := 0.0
var _resting_anchors: Dictionary = {}
var _resting_anchor_slots: Dictionary = {}
var _autosave_thread: Thread
var _autosave_in_flight := false

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
	fire = FireSystemScript.new(registries, grid)
	interactions = InteractionRegistryScript.new()
	interactions.register_provider(
		"fire",
		FireInteractionsScript.new(fire)
	)
	interactions.register_provider("camping", camping.interactions)
	collection = CollectionManager.new(registries)
	rewards = RewardManager.new(registries, rng, inventory, stock, collection)
	build_rewards = BuildRewardServiceScript.new(
		registries, rng, stock, collection
	)
	harvesting = HarvestingModuleScript.new(
		registries, rng, grid, build_rewards
	)
	visitors = VisitorModuleScript.new(
		registries, rng, grid, build_rewards
	)
	equipment = EquipmentManager.new(registries)
	progression = ProgressionModule.new(registries, rng, grid, stock, collection, equipment)
	fishing = FishingModuleScript.new(
		registries, rng, grid, stock, collection, progression
	)
	onboarding = OnboardingState.new()
	arrivals = ArrivalScheduler.new(registries, rng)
	crafting = CraftingManager.new(registries, inventory, stock, progression, equipment, collection)
	landmarks = LandmarkManager.new(registries, rng, grid, stock, rewards, equipment, collection)
	combat = CombatManager.new(registries, landmarks, rewards, equipment, collection)
	save_manager = SaveManager.new(registries)

	# Managers are RefCounted children of this composition root. Their signals
	# must not retain the root, otherwise root -> manager -> callable -> root
	# forms a permanent reference cycle each time a game session is rebuilt.
	var owner_ref: WeakRef = weakref(self)
	fishing.session.haul_committed.connect(func(haul):
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._on_fishing_haul_committed(haul)
	)
	fishing.basket.basket_changed.connect(func():
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._dirty = true
	)
	fishing.pouch.pouch_changed.connect(func():
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._dirty = true
	)
	progression.milestones.milestone_reached.connect(func(milestone_id, rewards_granted):
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._on_milestone_reached(milestone_id, rewards_granted)
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
	grid.slot_changed.connect(func(coord, elevation):
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._sync_resting_anchor_slot(coord, elevation)
	)
	harvesting.source_state_changed.connect(func(instance_id, state, status):
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._on_harvest_source_state_changed(instance_id, state, status)
	)
	harvesting.reward_granted.connect(func(instance_id, reward):
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._on_harvest_reward_granted(instance_id, reward)
	)
	harvesting.hit_landed.connect(func(_instance_id, hit):
		var owner := owner_ref.get_ref() as GameCore
		if owner != null and not bool(hit.get("final", false)):
			owner.autosave_soon()
	)
	visitors.visitor_available.connect(func(_event):
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			# Persist the selected look, cell, and pre-rolled gift immediately;
			# quitting can never reroll an already-arrived visitor.
			owner.save()
	)
	visitors.visitor_collected.connect(func(event, reward):
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._on_visitor_collected(event, reward)
	)
	onboarding.stage_changed.connect(func(stage):
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner._on_onboarding_stage_changed(stage)
	)
	harvesting.reward_granted.connect(func(_instance_id, _reward):
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner.save()
	)
	visitors.visitor_collected.connect(func(_event, _reward):
		var owner := owner_ref.get_ref() as GameCore
		if owner != null:
			owner.save()
	)
	fire.burning_changed.connect(func(_instance_id, _burning):
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
	fishing.reset()
	onboarding.set_stage(OnboardingState.COMPLETE)
	_compose_starting_world()
	grid.home_cell = Vector2i.ZERO
	profile.position = grid.cell_to_world(Vector2i.ZERO)
	# Starter kit: rod + axe owned, plus the current body-slot wardrobe sample.
	equipment.acquire("tool_rod_basic")
	equipment.acquire("tool_axe_basic")
	equipment.equip("tool_rod_basic")
	_ensure_default_body_item()
	# Trees begin unplaced in the Build Bag for established/non-authored starts.
	stock.add_structure("struct_pine")
	_ensure_showcase_placeables()
	collection.record("gear", "tool_rod_basic")
	collection.record("gear", "tool_axe_basic")
	for coord: Vector2i in grid.cells:
		collection.record("tiles", grid.cell(coord).tile_id, 0)
	save()


## Authored first-session start. Unlike new_game(), this deliberately creates
## no land yet: the keeper arrives into an empty world and chooses the first
## tile during the portal sequence.
func begin_onboarding_game(new_profile: PlayerProfile) -> void:
	begin_build_onboarding(new_profile)


## Build-first opening: the world exists immediately and the only owned model
## is one stateful young tree waiting in the Build Library.
func begin_build_onboarding(new_profile: PlayerProfile) -> void:
	profile = new_profile
	camping.reset()
	fishing.reset()
	_compose_onboarding_world()
	grid.home_cell = Vector2i.ZERO
	profile.position = grid.cell_to_world(Vector2i.ZERO)
	stock.tiles.clear()
	stock.structures.clear()
	stock.structure_instances.clear()
	stock.add_structure("struct_pine_young")
	# The keeper is deliberately absent from the opening presentation, but its
	# normal wardrobe and tools are already safe for the moment the player
	# chooses to deploy it after onboarding.
	equipment.acquire("tool_rod_basic")
	equipment.acquire("tool_axe_basic")
	equipment.equip("tool_rod_basic")
	_ensure_default_body_item()
	collection.record("gear", "tool_rod_basic")
	collection.record("gear", "tool_axe_basic")
	onboarding.begin("struct_pine_young")
	visitors.arrival_allowed = false
	for coord: Vector2i in grid.cells:
		collection.record("tiles", grid.cell(coord).tile_id, 0)
	save()


func choose_onboarding_land(tile_id: String) -> bool:
	return false


## Called after a successful placement. It verifies the live world state
## before advancing and returns the next guaranteed piece for presentation.
func advance_onboarding_after_placement() -> Dictionary:
	match onboarding.stage:
		OnboardingState.PLACE_TREE:
			var instance_id := _newest_placed_structure(onboarding.guided_id)
			if not onboarding.tree_placed(instance_id):
				return {}
			save()
			return {"message": "Turn the world while your tree grows."}
		OnboardingState.PLACE_FOREST_REWARD:
			onboarding.set_stage(OnboardingState.WAIT_VISITOR)
			save()
			return {"message": "Your tree will return. Something else may visit soon."}
		OnboardingState.PLACE_VISITOR_REWARD:
			onboarding.set_stage(OnboardingState.COMPLETE)
			save()
			return {"message": "Harvest for themed finds. Visitors bring surprises from everywhere."}
	return {}


## Every committed haul autosaves; during onboarding the first catch also
## hands its piece to the guided placement lesson (the tutorial performs the
## basket "take" for the player).
func _on_fishing_haul_committed(haul) -> void:
	autosave_soon()


## Repairs an interrupted guided placement after load without duplicating a
## piece that is already stored or placed.
func ensure_onboarding_guided_piece() -> Dictionary:
	if not onboarding.requires_guided_placement():
		return {}
	var kind := onboarding.guided_kind
	var content_id := onboarding.guided_id
	if kind == "" or content_id == "":
		return {}
	_ensure_guided_stock(kind, content_id)
	return {"kind": kind, "id": content_id}


func _ensure_guided_stock(kind: String, content_id: String) -> void:
	match kind:
		DiscoverySystem.KIND_TILE:
			if stock.tile_count(content_id) < 1:
				stock.add_tile(content_id)
		DiscoverySystem.KIND_STRUCTURE:
			if stock.structure_count(content_id) < 1:
				stock.add_structure(content_id)


func _placed_tile_count(tile_id: String) -> int:
	var count := 0
	for slot: Dictionary in grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		if state.tile_id == tile_id:
			count += 1
	return count


func _is_structure_placed(structure_id: String) -> bool:
	for slot: Dictionary in grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			if structure.structure_id == structure_id:
				return true
	return false


## Established/non-authored starts use the same floating 3x3 grammar.
func _compose_starting_world() -> void:
	grid.cells.clear()
	grid.stacked_cells.clear()
	var land_id := profile.starter_land_id
	if registries.tile(land_id) == null or not registries.is_tile_active(land_id):
		land_id = "tile_grass"
	var layout := {
		Vector2i(-1, -1): [land_id, 0],
		Vector2i(0, -1): [land_id, 0],
		Vector2i(1, -1): [land_id, 0],
		Vector2i(-1, 0): [land_id, 0],
		Vector2i(0, 0): [land_id, 0],
		Vector2i(1, 0): [land_id, 0],
		Vector2i(-1, 1): [land_id, 0],
		Vector2i(0, 1): [land_id, 0],
		Vector2i(1, 1): [land_id, 0],
	}
	for coord: Vector2i in layout:
		grid.place_tile(
			coord,
			layout[coord][0],
			layout[coord][1],
			true,
			false
		)
	# Opening furniture is independent from its terrain. Trees/vegetation do
	# not spawn by default; the first tree waits in the Build Library.
	grid.add_structure(Vector2i(-1, 1), "struct_bench", 2, 1)
	grid.add_structure(Vector2i(1, 0), "struct_chest", 2, 0)
	for coord: Vector2i in grid.cells:
		for s in grid.cell(coord).structures:
			collection.record("structures", s.structure_id, 0)
	grid.rebuild_structure_index()


func _compose_onboarding_world() -> void:
	grid.cells.clear()
	grid.stacked_cells.clear()
	grid.next_instance_id = 1
	for x in range(-1, 2):
		for y in range(-1, 2):
			grid.place_tile(
				Vector2i(x, y), "tile_grass", 0, true, false
			)
	grid.rebuild_structure_index()


func _newest_placed_structure(structure_id: String) -> int:
	var newest := 0
	for slot: Dictionary in grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			if structure.structure_id == structure_id:
				newest = maxi(newest, structure.instance_id)
	return newest


func _on_harvest_source_state_changed(
	instance_id: int,
	state: String,
	_status: Dictionary
) -> void:
	if state == HarvestingModule.STATE_READY and onboarding.tree_ready(instance_id):
		autosave_soon()


func _on_harvest_reward_granted(
	instance_id: int,
	reward: Dictionary
) -> void:
	if (
		onboarding.stage != OnboardingState.HARVEST_TREE
		or instance_id != onboarding.starter_tree_instance_id
	):
		return
	var kind := String(reward.get("kind", ""))
	var content_id := String(reward.get("id", ""))
	if kind not in ["tile", "structure"] or content_id == "":
		return
	onboarding.guide_piece(
		OnboardingState.PLACE_FOREST_REWARD, kind, content_id
	)
	onboarding_guidance_ready.emit(kind, content_id)


func _on_visitor_collected(event: Dictionary, reward: Dictionary) -> void:
	if onboarding.stage != OnboardingState.WAIT_VISITOR:
		return
	var kind := String(reward.get("kind", ""))
	var content_id := String(reward.get("id", ""))
	if kind not in ["tile", "structure"] or content_id == "":
		return
	onboarding.guide_piece(
		OnboardingState.PLACE_VISITOR_REWARD, kind, content_id
	)
	onboarding_guidance_ready.emit(kind, content_id)


func _on_onboarding_stage_changed(stage: String) -> void:
	visitors.arrival_allowed = stage in [
		OnboardingState.WAIT_VISITOR,
		OnboardingState.PLACE_VISITOR_REWARD,
		OnboardingState.COMPLETE,
	]


# ------------------------------------------------------------------ flow hooks

func _on_milestone_reached(milestone_id: String, rewards_granted: Array) -> void:
	var definition := registries.milestone(milestone_id)
	if definition != null:
		for reward in rewards_granted:
			var note := String(reward.get("note", ""))
			if note != "":
				notified.emit("%s — %s" % [definition.display_name, note], "levelup")
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
	_poll_autosave()
	play_seconds += delta
	fishing.tick(delta)
	harvesting.tick(delta)
	visitors.tick(delta)
	arrivals.tick(delta)
	if registries.feature("combat_enabled", false):
		combat.tick(delta)
	_tick_anchors(delta)
	if autosave_paused:
		return
	autosave_timer += delta
	if autosave_timer >= registries.tunef("autosave_interval", 40.0) and _dirty:
		_start_autosave()


func _tick_anchors(delta: float) -> void:
	_anchor_tick_accum += delta
	if _anchor_tick_accum < 0.2:
		return
	var elapsed := _anchor_tick_accum
	_anchor_tick_accum = 0.0
	for object_id: int in _resting_anchors.keys():
		var entry: Dictionary = _resting_anchors[object_id]
		var runtime: RefCounted = entry["runtime"]
		if runtime == null or not bool(runtime.get("anchor_resting")):
			_resting_anchors.erase(object_id)
			continue
		runtime.set(
			"anchor_regen_left",
			float(runtime.get("anchor_regen_left")) - elapsed
		)
		if float(runtime.get("anchor_regen_left")) > 0.0:
			continue
		runtime.set("anchor_resting", false)
		runtime.set("anchor_actions_done", 0)
		var coord: Vector2i = entry["coord"]
		var elevation := int(entry["elevation"])
		var instance_id := int(entry["instance_id"])
		grid.slot_changed.emit(coord, elevation)
		if instance_id == 0:
			grid.cell_changed.emit(coord)
		anchor_regenerated.emit(coord, elevation, instance_id)


func track_resting_structure(instance_id: int) -> void:
	var found := grid.find_structure(instance_id)
	if not found.is_empty():
		_sync_resting_anchor_slot(
			found["coord"],
			int(found["elevation"])
		)


func _sync_resting_anchor_slot(coord: Vector2i, elevation: int) -> void:
	var slot_key := grid.slot_key(coord, elevation)
	for object_id: int in _resting_anchor_slots.get(slot_key, []):
		_resting_anchors.erase(object_id)
	var active_ids: Array[int] = []
	var state := grid.cell_at(coord, elevation)
	if state != null:
		if state.anchor_resting:
			var state_id := int(state.get_instance_id())
			active_ids.append(state_id)
			_resting_anchors[state_id] = {
				"runtime": state,
				"coord": coord,
				"elevation": elevation,
				"instance_id": 0,
			}
		for structure: WorldGrid.StructureState in state.structures:
			if not structure.anchor_resting:
				continue
			var structure_id := int(structure.get_instance_id())
			active_ids.append(structure_id)
			_resting_anchors[structure_id] = {
				"runtime": structure,
				"coord": coord,
				"elevation": elevation,
				"instance_id": structure.instance_id,
			}
	if active_ids.is_empty():
		_resting_anchor_slots.erase(slot_key)
	else:
		_resting_anchor_slots[slot_key] = active_ids


func _rebuild_resting_anchors() -> void:
	_resting_anchors.clear()
	_resting_anchor_slots.clear()
	for slot: Dictionary in grid.all_cell_slots():
		_sync_resting_anchor_slot(
			slot["coord"],
			int(slot["elevation"])
		)


func autosave_soon() -> void:
	autosave_timer = registries.tunef("autosave_interval", 40.0)
	_dirty = true


func save() -> bool:
	_finish_autosave()
	before_save.emit()
	autosave_timer = 0.0
	var saved := save_manager.write(_save_payload())
	_dirty = not saved
	return saved


func _save_payload() -> Dictionary:
	return {
		"rng": rng.to_save_dict(),
		"profile": profile.to_save_dict(),
		"grid": grid.to_save_dict(),
		"inventory": inventory.to_save_dict(),
		"stock": stock.to_save_dict(),
		"collection": collection.to_save_dict(),
		"progression": progression.to_save_dict(),
		"onboarding": onboarding.to_save_dict(),
		"arrivals": arrivals.to_save_dict(),
		"equipment": equipment.to_save_dict(),
		"landmarks": landmarks.to_save_dict(),
		"combat": combat.to_save_dict(),
		"features": {
			"camping": camping.to_save_dict(),
			"fishing": fishing.to_save_dict(),
			"harvesting": harvesting.to_save_dict(),
			"visitors": visitors.to_save_dict(),
		},
		"view": view_state.duplicate(true),
		"visual": visual_state.duplicate(true),
		"play_seconds": play_seconds,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
	}


func _start_autosave() -> void:
	if _autosave_in_flight:
		return
	before_save.emit()
	autosave_timer = 0.0
	var payload := _save_payload()
	# Changes made after this snapshot set _dirty again through the existing
	# manager/grid signals and are picked up by the next autosave.
	_dirty = false
	_autosave_thread = Thread.new()
	var error := _autosave_thread.start(
		save_manager.write_background.bind(payload)
	)
	if error != OK:
		_autosave_thread = null
		_dirty = true
		return
	_autosave_in_flight = true


func _poll_autosave() -> void:
	if not _autosave_in_flight or _autosave_thread.is_alive():
		return
	var succeeded := bool(_autosave_thread.wait_to_finish())
	_autosave_thread = null
	_autosave_in_flight = false
	save_manager.finish_background(succeeded)
	if not succeeded:
		_dirty = true


func _finish_autosave() -> void:
	if not _autosave_in_flight:
		return
	var succeeded := bool(_autosave_thread.wait_to_finish())
	_autosave_thread = null
	_autosave_in_flight = false
	save_manager.finish_background(succeeded)
	if not succeeded:
		_dirty = true


func load_game() -> bool:
	var raw_data := save_manager.read()
	if raw_data.is_empty():
		return false
	# Progression v1 payloads migrate BEFORE strict validation: retired shapes
	# become v2 (preserved verbatim under progression.archived_v1), then the
	# validator applies its normal no-aliases strictness to the result.
	var data: Dictionary = ProgressionModule.migrate_save_payload(raw_data)
	var save_errors := CurrentSaveValidatorScript.validate(data, registries)
	if not save_errors.is_empty():
		var reason := "development save references retired content: " + save_errors[0]
		save_manager.load_failed.emit(reason)
		push_warning("SaveManager: " + reason)
		return false
	rng.from_save_dict(data.get("rng", {}))
	profile.from_save_dict(data.get("profile", {}))
	grid.from_save_dict(data.get("grid", {}))
	_rebuild_resting_anchors()
	inventory.from_save_dict(data.get("inventory", {}))
	stock.from_save_dict(data.get("stock", {}))
	harvesting.from_save_dict(
		(data.get("features", {}) as Dictionary).get("harvesting", {})
	)
	visitors.from_save_dict(
		(data.get("features", {}) as Dictionary).get("visitors", {})
	)
	camping.from_save_dict(
		(data.get("features", {}) as Dictionary).get("camping", {})
	)
	fishing.from_save_dict(
		(data.get("features", {}) as Dictionary).get("fishing", {})
	)
	collection.from_save_dict(data.get("collection", {}))
	progression.from_save_dict(data.get("progression", {}))
	onboarding.from_save_dict(data.get("onboarding", {}))
	arrivals.from_save_dict(data.get("arrivals", {}))
	equipment.from_save_dict(data.get("equipment", {}))
	landmarks.from_save_dict(data.get("landmarks", {}))
	combat.from_save_dict(data.get("combat", {}))
	var wardrobe_migrated := _ensure_default_body_item()
	var showcase_placeables_migrated := (
		_ensure_showcase_placeables()
		if not onboarding.is_active()
		else false
	)
	view_state = data.get("view", view_state).duplicate(true)
	visual_state = data.get("visual", visual_state).duplicate(true)
	play_seconds = float(data.get("play_seconds", 0.0))
	_apply_offline_recovery(int(data.get("saved_at_unix", 0)))
	if not grid.is_traversable(grid.world_to_cell(profile.position)):
		profile.position = grid.cell_to_world(grid.nearest_walkable(grid.world_to_cell(profile.position)))
	_dirty = wardrobe_migrated or showcase_placeables_migrated
	return true


## Trees and other resting anchors recover in real time even while away:
## a returning player walks into a rested grove, never a punishment.
func _apply_offline_recovery(saved_at_unix: int) -> void:
	if saved_at_unix <= 0:
		return
	var elapsed := float(int(Time.get_unix_time_from_system()) - saved_at_unix)
	if elapsed <= 0.0:
		return
	for object_id: int in _resting_anchors.keys():
		var entry: Dictionary = _resting_anchors[object_id]
		var runtime: RefCounted = entry["runtime"]
		if runtime == null or not bool(runtime.get("anchor_resting")):
			continue
		runtime.set(
			"anchor_regen_left",
			float(runtime.get("anchor_regen_left")) - elapsed
		)
		if float(runtime.get("anchor_regen_left")) > 0.0:
			continue
		runtime.set("anchor_resting", false)
		runtime.set("anchor_actions_done", 0)
		var coord: Vector2i = entry["coord"]
		var elevation := int(entry["elevation"])
		var instance_id := int(entry["instance_id"])
		grid.slot_changed.emit(coord, elevation)
		if instance_id == 0:
			grid.cell_changed.emit(coord)
		anchor_regenerated.emit(coord, elevation, instance_id)
	_rebuild_resting_anchors()


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
