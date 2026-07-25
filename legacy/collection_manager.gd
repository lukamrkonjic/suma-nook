extends Node
# legacy-disabled class_name CollectionManager

signal discovered(definition_id: StringName, first_time: bool)
signal changed(definition_id: StringName)

var data: GameData
var discoveries: Dictionary = {}
var total_obtained: Dictionary = {}
var new_markers: Dictionary = {}


func setup(game_data: GameData) -> void:
	data = game_data


func record_obtained(definition_id: StringName, quantity: int = 1) -> bool:
	if data.item(definition_id) == null or quantity <= 0:
		return false
	var first := not bool(discoveries.get(definition_id, false))
	discoveries[definition_id] = true
	total_obtained[definition_id] = int(total_obtained.get(definition_id, 0)) + quantity
	if first:
		new_markers[definition_id] = true
	discovered.emit(definition_id, first)
	changed.emit(definition_id)
	return first


func is_discovered(definition_id: StringName) -> bool:
	return bool(discoveries.get(definition_id, false))


func total(definition_id: StringName) -> int:
	return int(total_obtained.get(definition_id, 0))


func mark_seen(definition_id: StringName) -> void:
	new_markers.erase(definition_id)
	changed.emit(definition_id)


func current_owned(definition_id: StringName, grid: GridManager, storage: StorageManager) -> int:
	var count := storage.amount(definition_id)
	if data.item(definition_id).is_ground():
		for id: StringName in grid.ground.values():
			if id == definition_id:
				count += 1
	else:
		for state: Dictionary in grid.props.values():
			if StringName(str(state.get("definition_id", ""))) == definition_id:
				count += 1
	return count


func snapshot() -> Dictionary:
	var found: Array[String] = []
	var totals: Dictionary = {}
	var fresh: Array[String] = []
	for id: StringName in discoveries:
		if bool(discoveries[id]):
			found.append(String(id))
	for id: StringName in total_obtained:
		totals[String(id)] = int(total_obtained[id])
	for id: StringName in new_markers:
		fresh.append(String(id))
	return {"discoveries": found, "total_obtained": totals, "new_markers": fresh}


func restore_snapshot(state: Dictionary, missing_ids: Array[String] = []) -> void:
	discoveries.clear()
	total_obtained.clear()
	new_markers.clear()
	for raw_id: Variant in state.get("discoveries", []):
		var id := StringName(str(raw_id))
		if data.item(id) == null:
			missing_ids.append(String(id))
			continue
		discoveries[id] = true
	for raw_id: Variant in state.get("total_obtained", {}):
		var id := StringName(str(raw_id))
		if data.item(id) != null:
			total_obtained[id] = maxi(0, int((state.total_obtained as Dictionary)[raw_id]))
	for raw_id: Variant in state.get("new_markers", []):
		var id := StringName(str(raw_id))
		if data.item(id) != null:
			new_markers[id] = true

