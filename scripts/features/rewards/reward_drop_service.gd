class_name RewardDropService
extends RefCounted
## Dedicated landed Falling Object state. Rewards are not owned until this
## interactable is claimed, and the saved structure instance is never movable.

signal reward_landed(instance_id: int, entry: Dictionary)
signal reward_claimed(instance_id: int, reward: Dictionary)

const STRUCTURE_ID := "struct_reward_drop"
const RUNTIME_KEY := "reward_drop"

var registries: Registries
var rng: RngService
var grid: WorldGrid
var rewards: BuildRewardService
var landing_sequence := 0


func _init(
	content: Registries,
	rng_service: RngService,
	world_grid: WorldGrid,
	reward_service: BuildRewardService
) -> void:
	registries = content
	rng = rng_service
	grid = world_grid
	rewards = reward_service


func land(entry: Dictionary, preferred_coord := Vector2i.ZERO) -> Dictionary:
	if entry.is_empty() or has_unclaimed():
		return {"accepted": false, "reason": "event_already_active"}
	var content_id := String(entry.get("id", ""))
	var kind := String(entry.get("kind", ""))
	if (
		(kind == "tile" and registries.tile(content_id) == null)
		or (kind == "structure" and registries.structure(content_id) == null)
	):
		return {"accepted": false, "reason": "invalid_reward"}
	landing_sequence += 1
	for coord: Vector2i in safe_landing_candidates(preferred_coord):
		var elevation := grid.top_elevation(coord)
		var state := grid.add_structure(coord, STRUCTURE_ID, 1, 0, elevation)
		if state == null:
			continue
		var saved := entry.duplicate(true)
		saved["claimed"] = false
		saved["landing_sequence"] = landing_sequence
		saved["landed_coord"] = [coord.x, coord.y]
		state.runtime_state[RUNTIME_KEY] = saved
		reward_landed.emit(state.instance_id, saved.duplicate(true))
		return {
			"accepted": true,
			"instance_id": state.instance_id,
			"coord": coord,
			"entry": saved.duplicate(true),
		}
	return {"accepted": false, "reason": "no_safe_landing"}


func safe_landing_candidates(preferred_coord: Vector2i) -> Array[Vector2i]:
	var strict: Array[Dictionary] = []
	var fallback: Array[Dictionary] = []
	for coord: Vector2i in grid.cells:
		var elevation := grid.top_elevation(coord)
		var state := grid.cell_at(coord, elevation)
		var definition := grid.tile_def_at(coord, elevation)
		if (
			state == null
			or definition == null
			or not definition.walkable
			or definition.surface_kind == "water"
			or not state.structures.is_empty()
			or state.landmark_id != ""
		):
			continue
		var neighbors := 0
		for direction: Vector2i in WorldGrid.NEIGHBORS:
			if grid.has_cell(coord + direction):
				neighbors += 1
		var score := coord.distance_squared_to(preferred_coord) + rng.randf_range(
			"reward_drop_landing:%d:%d:%d" % [landing_sequence, coord.x, coord.y],
			0.0,
			4.0
		)
		var candidate := {"coord": coord, "score": score}
		fallback.append(candidate)
		if neighbors >= 2:
			strict.append(candidate)
	var source := strict if not strict.is_empty() else fallback
	source.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) < float(b["score"])
	)
	var result: Array[Vector2i] = []
	for candidate: Dictionary in source:
		result.append(candidate["coord"])
	return result


func entry_for_instance(instance_id: int) -> Dictionary:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return {}
	var structure: WorldGrid.StructureState = found["structure"]
	if structure.structure_id != STRUCTURE_ID:
		return {}
	var entry: Dictionary = structure.runtime_state.get(RUNTIME_KEY, {})
	return (
		entry.duplicate(true)
		if not entry.is_empty() and not bool(entry.get("claimed", false))
		else {}
	)


func claim(instance_id: int) -> Dictionary:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return {"accepted": false, "reason": "missing"}
	var structure: WorldGrid.StructureState = found["structure"]
	var entry: Dictionary = structure.runtime_state.get(RUNTIME_KEY, {})
	if entry.is_empty() or bool(entry.get("claimed", false)):
		return {"accepted": false, "reason": "already_claimed"}
	entry["claimed"] = true
	var granted := (
		entry.duplicate(true)
		if bool(entry.get("pregranted", false))
		else rewards.grant(entry)
	)
	if granted.is_empty():
		entry["claimed"] = false
		return {"accepted": false, "reason": "grant_failed"}
	grid.remove_structure(found["coord"], instance_id, int(found["elevation"]))
	reward_claimed.emit(instance_id, granted.duplicate(true))
	return {"accepted": true, "reward": granted}


func has_unclaimed() -> bool:
	for slot: Dictionary in grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			if structure.structure_id != STRUCTURE_ID:
				continue
			var entry: Dictionary = structure.runtime_state.get(RUNTIME_KEY, {})
			if not entry.is_empty() and not bool(entry.get("claimed", false)):
				return true
	return false


func to_save_dict() -> Dictionary:
	return {"landing_sequence": landing_sequence}


func from_save_dict(data: Dictionary) -> void:
	landing_sequence = maxi(0, int(data.get("landing_sequence", 0)))
