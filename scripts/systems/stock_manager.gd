class_name StockManager
extends RefCounted
## Unplaced world pieces: tiles chosen from parcels, crafted structures, and
## packed landmark deeds. Anything stored here is placeable later and can
## never disappear — storing a placed piece returns it to stock.

signal stock_changed

var registries: Registries
var tiles: Dictionary = {}        # tile_id -> count
var structures: Dictionary = {}   # structure_id -> total count
# Stable iid -> serialized WorldGrid.StructureState. Only definitions that
# explicitly preserve instance state enter this collection; ordinary pieces
# remain cheap anonymous counts.
var structure_instances: Dictionary = {}
var landmark_deeds: Array[String] = []


func _init(definition_registries: Registries = null) -> void:
	registries = definition_registries


func tile_count(tile_id: String) -> int:
	return int(tiles.get(tile_id, 0))


func structure_count(structure_id: String) -> int:
	return int(structures.get(structure_id, 0))


func add_tile(tile_id: String, amount := 1) -> void:
	tiles[tile_id] = tile_count(tile_id) + amount
	stock_changed.emit()


func take_tile(tile_id: String) -> bool:
	if tile_count(tile_id) < 1:
		return false
	tiles[tile_id] -= 1
	if tiles[tile_id] <= 0:
		tiles.erase(tile_id)
	stock_changed.emit()
	return true


func add_structure(structure_id: String, amount := 1) -> void:
	structures[structure_id] = structure_count(structure_id) + amount
	stock_changed.emit()


func add_structure_instance(state: WorldGrid.StructureState) -> void:
	if state == null:
		return
	var definition := registries.structure(state.structure_id) if registries != null else null
	if definition == null or not definition.preserve_instance_state:
		add_structure(state.structure_id)
		return
	var stored := state.to_dict()
	stored["parent"] = 0
	stored["support"] = ""
	stored["socket"] = 0
	structure_instances[state.instance_id] = stored
	structures[state.structure_id] = structure_count(state.structure_id) + 1
	stock_changed.emit()


## Removes one piece and returns the instance payload to restore. An empty
## `state` means this was a newly crafted/anonymous piece.
func take_structure_token(structure_id: String, preferred_iid := 0) -> Dictionary:
	if structure_count(structure_id) < 1:
		return {}
	var chosen_iid := preferred_iid
	if chosen_iid <= 0 or not structure_instances.has(chosen_iid):
		chosen_iid = 0
		var candidates: Array[int] = []
		for raw_iid: int in structure_instances:
			if String(structure_instances[raw_iid].get("id", "")) == structure_id:
				candidates.append(raw_iid)
		candidates.sort()
		if not candidates.is_empty():
			chosen_iid = candidates[0]
	var state: Dictionary = {}
	if chosen_iid > 0:
		state = (structure_instances[chosen_iid] as Dictionary).duplicate(true)
		structure_instances.erase(chosen_iid)
	structures[structure_id] = structure_count(structure_id) - 1
	if structures[structure_id] <= 0:
		structures.erase(structure_id)
	stock_changed.emit()
	return {"structure_id": structure_id, "state": state}


func return_structure_token(token: Dictionary) -> void:
	var structure_id := String(token.get("structure_id", ""))
	if structure_id == "":
		return
	var state: Dictionary = token.get("state", {})
	if state.is_empty():
		add_structure(structure_id)
		return
	var instance := WorldGrid.StructureState.from_dict(state)
	add_structure_instance(instance)


func take_structure(structure_id: String) -> bool:
	return not take_structure_token(structure_id).is_empty()


func has_structure_instance(instance_id: int) -> bool:
	return structure_instances.has(instance_id)


func add_landmark_deed(landmark_id: String) -> void:
	landmark_deeds.append(landmark_id)
	stock_changed.emit()


func take_landmark_deed(landmark_id: String) -> bool:
	var index := landmark_deeds.find(landmark_id)
	if index < 0:
		return false
	landmark_deeds.remove_at(index)
	stock_changed.emit()
	return true


func total_tiles() -> int:
	var total := 0
	for count in tiles.values():
		total += int(count)
	return total


func to_save_dict() -> Dictionary:
	var instances: Array = []
	for instance_id: int in structure_instances:
		instances.append((structure_instances[instance_id] as Dictionary).duplicate(true))
	instances.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("iid", 0)) < int(b.get("iid", 0))
	)
	return {
		"tiles": tiles.duplicate(),
		"structures": structures.duplicate(),
		"structure_instances": instances,
		"deeds": landmark_deeds.duplicate(),
	}


func from_save_dict(data: Dictionary) -> void:
	tiles.clear()
	for raw_id: String in data.get("tiles", {}):
		var amount := int(data["tiles"][raw_id])
		if amount <= 0:
			continue
		tiles[raw_id] = amount
	structures.clear()
	for raw_id: String in data.get("structures", {}):
		var amount := int(data["structures"][raw_id])
		if amount <= 0:
			continue
		structures[raw_id] = amount
	structure_instances.clear()
	for raw_state in data.get("structure_instances", []):
		if not raw_state is Dictionary:
			continue
		var state := WorldGrid.StructureState.from_dict(raw_state)
		var definition := registries.structure(state.structure_id) if registries != null else null
		if (
			state.instance_id <= 0
			or definition == null
			or not definition.preserve_instance_state
			or structure_instances.has(state.instance_id)
		):
			continue
		structure_instances[state.instance_id] = state.to_dict()
	landmark_deeds.clear()
	for deed in data.get("deeds", []):
		var landmark_id := String(deed)
		landmark_deeds.append(landmark_id)
	stock_changed.emit()
