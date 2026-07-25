class_name LandmarkManager
extends RefCounted
## Horizon opportunities and landmark lifecycle:
## silhouette (in fog, beyond the world) → revealed (world connected; hostile)
## → reclaimed (guardian down; peaceful, editable) → kept / packed / salvaged.
## Opportunities never overlap land and never block expansion (they occupy a
## finite footprint; all other directions stay open; they can be re-sited).

signal opportunity_appeared(state: LandmarkState)
signal landmark_revealed(state: LandmarkState)
signal landmark_reclaimed(state: LandmarkState)
signal landmark_resolved(state: LandmarkState, resolution: String)  # kept|packed|salvaged

const PHASE_SILHOUETTE := "silhouette"
const PHASE_REVEALED := "revealed"
const PHASE_RECLAIMED := "reclaimed"


class LandmarkState:
	extends RefCounted
	var landmark_id: String
	var origin: Vector2i
	var phase: String = LandmarkManager.PHASE_SILHOUETTE
	var enemies_alive: Array[String] = []   # spawn slot ids like "thornling_stalker:0"
	var guardian_alive := true
	var reward_claimed := false             # idempotent guardian reward gate

	func to_dict() -> Dictionary:
		return {
			"id": landmark_id, "x": origin.x, "y": origin.y, "phase": phase,
			"enemies": enemies_alive.duplicate(), "guardian": guardian_alive, "reward": reward_claimed,
		}

	static func from_dict(d: Dictionary) -> LandmarkState:
		var s := LandmarkState.new()
		s.landmark_id = String(d.get("id", ""))
		s.origin = Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
		s.phase = String(d.get("phase", LandmarkManager.PHASE_SILHOUETTE))
		for e in d.get("enemies", []):
			s.enemies_alive.append(String(e))
		s.guardian_alive = bool(d.get("guardian", true))
		s.reward_claimed = bool(d.get("reward", false))
		return s


var registries: Registries
var rng: RngService
var grid: WorldGrid
var stock: StockManager
var reward_manager: RewardManager
var equipment: EquipmentManager
var collection: CollectionManager

var active: Array[LandmarkState] = []
var resolved_count: Dictionary = {}   # landmark_id -> times fully resolved


func _init(regs: Registries, rng_service: RngService, world_grid: WorldGrid, stock_mgr: StockManager, rewards: RewardManager, equip: EquipmentManager, coll: CollectionManager) -> void:
	registries = regs
	rng = rng_service
	grid = world_grid
	stock = stock_mgr
	reward_manager = rewards
	equipment = equip
	collection = coll


func state_for(landmark_id: String) -> LandmarkState:
	for s in active:
		if s.landmark_id == landmark_id:
			return s
	return null


func footprint_cells(state: LandmarkState) -> Array[Vector2i]:
	var def := registries.landmark(state.landmark_id)
	var result: Array[Vector2i] = []
	if def == null:
		return result
	for offset in def.footprint:
		result.append(state.origin + offset)
	return result


## Called after every tile placement. Spawns a silhouette when progression
## thresholds pass and reveals a landmark once the world touches it.
func on_world_grown() -> void:
	_maybe_spawn_opportunity()
	_check_reveal()


func _maybe_spawn_opportunity() -> void:
	var placed := grid.placed_tile_count()
	var thresholds: Array = registries.tune("horizon_check_tiles", [4])
	var should_have := 0
	for t in thresholds:
		if placed >= int(t):
			should_have += 1
	var existing := active.size() + _total_resolved()
	if existing >= should_have:
		return
	for def: Defs.LandmarkDefinition in registries.landmarks.values():
		if state_for(def.id) != null:
			continue
		if placed < def.min_progress_tiles:
			continue
		var origin := _find_site(def)
		if origin == Vector2i(9999, 9999):
			continue
		var state := LandmarkState.new()
		state.landmark_id = def.id
		state.origin = origin
		for spawn in def.enemies:
			for i in int(spawn.get("count", 1)):
				state.enemies_alive.append("%s:%d" % [spawn.get("enemy"), i])
		active.append(state)
		collection.record("landmarks", def.id, 0)
		opportunity_appeared.emit(state)
		return


## Deterministic site search: ring beyond the world bounds at the definition's
## distance band, in seeded-random direction order. Guaranteed not to overlap
## land, other landmarks, or (min 2 cells) leave no adjacent placement room.
func _find_site(def: Defs.LandmarkDefinition) -> Vector2i:
	var world_bounds := grid.bounds()
	var directions := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var shuffled := directions.duplicate()
	var stream := rng.stream("landmark_site")
	shuffled.shuffle()  # order comes from the seeded global state below instead
	var order_roll := stream.randi_range(0, 3)
	for attempt in 4:
		var dir: Vector2i = directions[(order_roll + attempt) % 4]
		for distance in range(def.min_distance, def.max_distance + 1):
			var origin := _site_origin(world_bounds, dir, distance)
			if _site_clear(def, origin):
				return origin
	return Vector2i(9999, 9999)


func _site_origin(world_bounds: Rect2i, dir: Vector2i, distance: int) -> Vector2i:
	var center := world_bounds.get_center()
	if dir.x != 0:
		var x := (world_bounds.end.x - 1 + distance) if dir.x > 0 else (world_bounds.position.x - distance - 1)
		return Vector2i(x, center.y)
	var y := (world_bounds.end.y - 1 + distance) if dir.y > 0 else (world_bounds.position.y - distance - 1)
	return Vector2i(center.x, y)


func _site_clear(def: Defs.LandmarkDefinition, origin: Vector2i) -> bool:
	for offset in def.footprint:
		var coord: Vector2i = origin + offset
		if grid.has_cell(coord):
			return false
		for other in active:
			if footprint_cells(other).has(coord):
				return false
	return true


func _check_reveal() -> void:
	for state in active:
		if state.phase != PHASE_SILHOUETTE:
			continue
		for cell in footprint_cells(state):
			if grid.is_adjacent_to_world(cell):
				_reveal(state)
				break


func _reveal(state: LandmarkState) -> void:
	state.phase = PHASE_REVEALED
	# The footprint becomes real, walkable landmark ground.
	for cell in footprint_cells(state):
		var placed := grid.place_tile(cell, "tile_stone_ruin", 0, false)
		placed.landmark_id = state.landmark_id
	landmark_revealed.emit(state)


## Combat reports a death here. When the last guardian falls the site turns
## peaceful and the (idempotent) reward is granted exactly once.
func on_enemy_defeated(state: LandmarkState, slot_id: String, is_guardian: bool) -> Array:
	var grants: Array = []
	if is_guardian:
		if state.guardian_alive:
			state.guardian_alive = false
			if not state.reward_claimed:
				state.reward_claimed = true
				var def := registries.landmark(state.landmark_id)
				if def.guardian_reward != "":
					equipment.acquire(def.guardian_reward)
					collection.record("gear", def.guardian_reward)
					grants.append({"item_id": def.guardian_reward, "count": 1, "rare": true})
				grants += reward_manager.roll_table(def.reward_table, "landmark_reward")
			_reclaim(state)
	else:
		state.enemies_alive.erase(slot_id)
	return grants


func _reclaim(state: LandmarkState) -> void:
	state.phase = PHASE_RECLAIMED
	state.enemies_alive.clear()
	collection.record("landmarks", state.landmark_id)
	landmark_reclaimed.emit(state)


## Post-reclaim choice. keep: stays where it is (already true). packed: cells
## return to wild, deed goes to stock for re-placement. salvaged: cells return
## to wild, materials granted.
func resolve(state: LandmarkState, resolution: String) -> void:
	if state.phase != PHASE_RECLAIMED:
		return
	var def := registries.landmark(state.landmark_id)
	match resolution:
		"packed":
			for cell in footprint_cells(state):
				grid.remove_tile(cell)
			stock.add_landmark_deed(state.landmark_id)
			active.erase(state)
		"salvaged":
			for cell in footprint_cells(state):
				grid.remove_tile(cell)
			reward_manager.grant_fixed(def.salvage)
			active.erase(state)
		_:
			resolution = "kept"
	resolved_count[state.landmark_id] = int(resolved_count.get(state.landmark_id, 0)) + 1
	landmark_resolved.emit(state, resolution)


## Re-place a packed landmark deed at a new origin (must be clear + adjacent).
func place_deed(landmark_id: String, origin: Vector2i) -> bool:
	var def := registries.landmark(landmark_id)
	if def == null or not stock.landmark_deeds.has(landmark_id):
		return false
	var adjacent := false
	for offset in def.footprint:
		var coord: Vector2i = origin + offset
		if grid.has_cell(coord):
			return false
		if grid.is_adjacent_to_world(coord):
			adjacent = true
	if not adjacent:
		return false
	stock.take_landmark_deed(landmark_id)
	var state := LandmarkState.new()
	state.landmark_id = landmark_id
	state.origin = origin
	state.phase = PHASE_RECLAIMED
	state.guardian_alive = false
	state.reward_claimed = true
	for cell in footprint_cells(state):
		var placed := grid.place_tile(cell, "tile_stone_ruin", 0, false)
		placed.landmark_id = landmark_id
	active.append(state)
	landmark_reclaimed.emit(state)
	return true


func _total_resolved() -> int:
	var total := 0
	for count in resolved_count.values():
		total += int(count)
	return total


func to_save_dict() -> Dictionary:
	var states: Array = []
	for s in active:
		states.append(s.to_dict())
	return {"active": states, "resolved": resolved_count.duplicate()}


func from_save_dict(data: Dictionary) -> void:
	active.clear()
	for raw in data.get("active", []):
		var s := LandmarkState.from_dict(raw)
		if registries.landmark(s.landmark_id) != null:
			active.append(s)
	resolved_count = data.get("resolved", {}).duplicate()
