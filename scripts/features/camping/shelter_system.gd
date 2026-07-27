class_name ShelterSystem
extends RefCounted
## Mutable camping state keyed by generic world structure instance id.

signal state_changed(instance_id: int)

class ShelterInstanceState:
	extends RefCounted
	var instance_id: int
	var durability: float
	var occupants: Array[String] = []
	var construction_progress := 1.0

	func to_save_dict() -> Dictionary:
		return {
			"iid": instance_id,
			"durability": durability,
			"occupants": occupants.duplicate(),
			"construction_progress": construction_progress,
		}

	static func from_dict(data: Dictionary):
		var state := ShelterInstanceState.new()
		state.instance_id = int(data.get("iid", 0))
		state.durability = float(data.get("durability", 0.0))
		for actor_id in data.get("occupants", []):
			state.occupants.append(String(actor_id))
		state.construction_progress = clampf(
			float(data.get("construction_progress", 1.0)), 0.0, 1.0
		)
		return state


var grid: WorldGrid
var stock: StockManager
var definitions
var states: Dictionary = {}


func _init(
	world_grid: WorldGrid,
	camping_definitions,
	stock_manager: StockManager
) -> void:
	grid = world_grid
	definitions = camping_definitions
	stock = stock_manager


func reset() -> void:
	states.clear()


func state_for(instance_id: int, create := true):
	if states.has(instance_id):
		return states[instance_id]
	if not create:
		return null
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return null
	var structure: WorldGrid.StructureState = found["structure"]
	var definition: Variant = definitions.structure(structure.structure_id)
	if definition == null or definition.shelter == null:
		return null
	var state := ShelterInstanceState.new()
	state.instance_id = instance_id
	state.durability = (
		definition.durability.maximum if definition.durability != null else 1.0
	)
	states[instance_id] = state
	return state


func can_occupy(instance_id: int, actor_id: String) -> Dictionary:
	var state: Variant = state_for(instance_id)
	if state == null:
		return {"ok": false, "reason": "This object is not a shelter."}
	var found := grid.find_structure(instance_id)
	var structure: WorldGrid.StructureState = found.get("structure")
	var definition: Variant = (
		definitions.structure(structure.structure_id) if structure != null else null
	)
	if definition == null or definition.shelter == null:
		return {"ok": false, "reason": "This object is not a shelter."}
	if state.construction_progress < 1.0:
		return {"ok": false, "reason": "Finish building this shelter first."}
	if state.durability <= 0.0:
		return {"ok": false, "reason": "This shelter needs repairing."}
	if state.occupants.has(actor_id):
		return {"ok": true, "reason": ""}
	if state.occupants.size() >= definition.shelter.capacity:
		return {"ok": false, "reason": "This shelter is full."}
	return {"ok": true, "reason": ""}


func add_occupant(instance_id: int, actor_id: String) -> bool:
	var check := can_occupy(instance_id, actor_id)
	if not bool(check["ok"]):
		return false
	var state: ShelterInstanceState = state_for(instance_id)
	if not state.occupants.has(actor_id):
		state.occupants.append(actor_id)
		state_changed.emit(instance_id)
	return true


func remove_occupant(instance_id: int, actor_id: String) -> void:
	var state: ShelterInstanceState = state_for(instance_id, false)
	if state == null:
		return
	var index := state.occupants.find(actor_id)
	if index >= 0:
		state.occupants.remove_at(index)
		state_changed.emit(instance_id)


func set_construction_progress(instance_id: int, progress: float) -> bool:
	var state: ShelterInstanceState = state_for(instance_id)
	if state == null:
		return false
	state.construction_progress = clampf(progress, 0.0, 1.0)
	state_changed.emit(instance_id)
	return true


func damage(instance_id: int, amount: float) -> bool:
	var state: ShelterInstanceState = state_for(instance_id)
	if state == null or amount <= 0.0:
		return false
	state.durability = maxf(0.0, state.durability - amount)
	state_changed.emit(instance_id)
	return true


func to_save_dict() -> Dictionary:
	var rows: Array = []
	for instance_id: int in states:
		rows.append((states[instance_id] as ShelterInstanceState).to_save_dict())
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["iid"]) < int(b["iid"])
	)
	return {"shelters": rows}


func from_save_dict(data: Dictionary) -> void:
	states.clear()
	for raw_state in data.get("shelters", []):
		if not raw_state is Dictionary:
			continue
		var state: ShelterInstanceState = ShelterInstanceState.from_dict(raw_state)
		if state.instance_id <= 0:
			continue
		var found := grid.find_structure(state.instance_id)
		if found.is_empty() and not stock.has_structure_instance(state.instance_id):
			continue
		var structure_id := ""
		if not found.is_empty():
			structure_id = (found["structure"] as WorldGrid.StructureState).structure_id
		else:
			structure_id = String(
				(stock.structure_instances[state.instance_id] as Dictionary).get("id", "")
			)
		var definition: Variant = definitions.structure(structure_id)
		if definition == null or definition.shelter == null:
			continue
		var maximum: float = (
			definition.durability.maximum if definition.durability != null else 1.0
		)
		state.durability = clampf(state.durability, 0.0, maximum)
		states[state.instance_id] = state
