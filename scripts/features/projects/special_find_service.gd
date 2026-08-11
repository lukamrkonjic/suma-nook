class_name SpecialFindService
extends RefCounted
## Global, persistent rare opportunities. Scheduling is one world clock with a
## small active cap; adding 500 rocks never makes this clock run faster.

signal special_find_spawned(instance_id: int, find_id: String)
signal special_find_collected(instance_id: int, find_id: String)

const RUNTIME_KEY := "special_find"

var registries: Registries
var rng: RngService
var grid: WorldGrid
var finds: FindsReserveService
var seconds_until_opportunity := -1.0
var sequence := 0
## At most `active_cap()` ids live here. This keeps the per-frame scheduler
## independent of world size; the full grid is scanned only when an actual
## opportunity is due or once while hydrating a save.
var _active_instance_ids: Dictionary = {}


func _init(
	content: Registries,
	rng_service: RngService,
	world_grid: WorldGrid,
	finds_reserve: FindsReserveService
) -> void:
	registries = content
	rng = rng_service
	grid = world_grid
	finds = finds_reserve
	var self_ref: WeakRef = weakref(self)
	grid.slot_changed.connect(func(coord: Vector2i, elevation: int):
		var service := self_ref.get_ref() as SpecialFindService
		if service != null:
			service._on_slot_changed(coord, elevation)
	)
	_schedule_next()


func tick(delta: float) -> void:
	if active_count() >= active_cap():
		return
	seconds_until_opportunity = maxf(0.0, seconds_until_opportunity - delta)
	if seconds_until_opportunity > 0.0:
		return
	spawn_global_opportunity()
	_schedule_next()


func spawn_global_opportunity() -> bool:
	if active_count() >= active_cap():
		return false
	var candidates := _eligible_instances()
	if candidates.is_empty():
		return false
	sequence += 1
	var instance_id := int(candidates[
		rng.randi_range("special_find_host:%d" % sequence, 0, candidates.size() - 1)
	])
	var definitions: Array[Dictionary] = []
	for definition in registries.special_finds.values():
		definitions.append({"definition": definition, "weight": definition.weight})
	var chosen := rng.weighted("special_find_kind:%d" % sequence, definitions)
	var definition = chosen.get("definition")
	return definition != null and spawn_for_instance(instance_id, definition.id)


func spawn_for_new_land(plan) -> bool:
	if active_count() >= active_cap() or plan == null:
		return false
	var candidates: Array[int] = []
	for feature: Dictionary in plan.features:
		var instance_id := int(feature.get("instance_id", 0))
		if instance_id > 0 and _is_eligible(instance_id):
			candidates.append(instance_id)
	if candidates.is_empty():
		return false
	# New land is the deliberate high-weight route. Alternate crystal/relic so
	# both special frontier examples remain reachable without spam harvesting.
	var find_id := "crystal" if sequence % 2 == 0 else "relic_fragment"
	sequence += 1
	return spawn_for_instance(candidates[0], find_id)


func spawn_for_instance(instance_id: int, find_id: String) -> bool:
	if active_count() >= active_cap() or registries.special_find(find_id) == null:
		return false
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return false
	var structure: WorldGrid.StructureState = found["structure"]
	var existing: Dictionary = structure.runtime_state.get(RUNTIME_KEY, {})
	if not existing.is_empty() and not bool(existing.get("collected", false)):
		return false
	structure.runtime_state[RUNTIME_KEY] = {
		"id": find_id,
		"collected": false,
		"opportunity_id": "find:%d" % sequence,
		"seed": absi(hash("find|%d|%d" % [rng.world_seed, sequence])),
	}
	_active_instance_ids[instance_id] = true
	special_find_spawned.emit(instance_id, find_id)
	return true


func active_for_instance(instance_id: int) -> Dictionary:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return {}
	var structure: WorldGrid.StructureState = found["structure"]
	var state: Dictionary = structure.runtime_state.get(RUNTIME_KEY, {})
	return (
		state.duplicate(true)
		if not state.is_empty() and not bool(state.get("collected", false))
		else {}
	)


func collect(instance_id: int) -> Dictionary:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return {"accepted": false, "reason": "missing"}
	var structure: WorldGrid.StructureState = found["structure"]
	var state: Dictionary = structure.runtime_state.get(RUNTIME_KEY, {})
	if state.is_empty() or bool(state.get("collected", false)):
		return {"accepted": false, "reason": "already_collected"}
	var find_id := String(state.get("id", ""))
	# Mark first: duplicate signals or rapid clicks can never deposit twice.
	state["collected"] = true
	if not finds.add(find_id, 1):
		state["collected"] = false
		return {"accepted": false, "reason": "invalid_find"}
	_active_instance_ids.erase(instance_id)
	special_find_collected.emit(instance_id, find_id)
	return {"accepted": true, "find_id": find_id, "amount": 1}


func active_count() -> int:
	_prune_active_index()
	return _active_instance_ids.size()


func active_cap() -> int:
	return maxi(1, registries.tunei("special_find_active_cap", 2))


func to_save_dict() -> Dictionary:
	return {
		"seconds_until_opportunity": seconds_until_opportunity,
		"sequence": sequence,
	}


func from_save_dict(data: Dictionary) -> void:
	seconds_until_opportunity = maxf(
		0.0,
		float(data.get("seconds_until_opportunity", seconds_until_opportunity))
	)
	sequence = maxi(0, int(data.get("sequence", 0)))
	_rebuild_active_index()


func _on_slot_changed(coord: Vector2i, elevation: int) -> void:
	_prune_active_index()
	var state := grid.cell_at(coord, elevation)
	if state == null:
		return
	for structure: WorldGrid.StructureState in state.structures:
		var find: Dictionary = structure.runtime_state.get(RUNTIME_KEY, {})
		if not find.is_empty() and not bool(find.get("collected", false)):
			_active_instance_ids[structure.instance_id] = true


func _prune_active_index() -> void:
	for raw_instance_id: Variant in _active_instance_ids.keys():
		var instance_id := int(raw_instance_id)
		var found := grid.find_structure(instance_id)
		if found.is_empty():
			_active_instance_ids.erase(instance_id)
			continue
		var structure: WorldGrid.StructureState = found["structure"]
		var find: Dictionary = structure.runtime_state.get(RUNTIME_KEY, {})
		if find.is_empty() or bool(find.get("collected", false)):
			_active_instance_ids.erase(instance_id)


func _rebuild_active_index() -> void:
	_active_instance_ids.clear()
	for slot: Dictionary in grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			var find: Dictionary = structure.runtime_state.get(RUNTIME_KEY, {})
			if not find.is_empty() and not bool(find.get("collected", false)):
				_active_instance_ids[structure.instance_id] = true


func _eligible_instances() -> Array[int]:
	var result: Array[int] = []
	for slot: Dictionary in grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			if _is_eligible(structure.instance_id):
				result.append(structure.instance_id)
	return result


func _is_eligible(instance_id: int) -> bool:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return false
	var structure: WorldGrid.StructureState = found["structure"]
	var definition := registries.structure(structure.structure_id)
	if definition == null or not definition.has_capability("harvest_source"):
		return false
	var state: Dictionary = structure.runtime_state.get(RUNTIME_KEY, {})
	return state.is_empty() or bool(state.get("collected", false))


func _schedule_next() -> void:
	var minimum := registries.tunef("special_find_min_seconds", 480.0)
	var maximum := registries.tunef("special_find_max_seconds", 900.0)
	seconds_until_opportunity = rng.randf_range(
		"special_find_schedule:%d" % sequence,
		minimum,
		maxf(minimum, maximum)
	)
