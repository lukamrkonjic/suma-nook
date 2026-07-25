extends Node
class_name StorageManager

signal changed(definition_id: StringName, amount: int)

var data: GameData
var counts: Dictionary = {}


func setup(game_data: GameData) -> void:
	data = game_data


func amount(definition_id: StringName) -> int:
	return int(counts.get(definition_id, 0))


func add(definition_id: StringName, quantity: int = 1) -> bool:
	if data.item(definition_id) == null or quantity <= 0:
		return false
	counts[definition_id] = amount(definition_id) + quantity
	changed.emit(definition_id, amount(definition_id))
	return true


func take(definition_id: StringName, quantity: int = 1) -> bool:
	if quantity <= 0 or amount(definition_id) < quantity:
		return false
	var remaining := amount(definition_id) - quantity
	if remaining <= 0:
		counts.erase(definition_id)
	else:
		counts[definition_id] = remaining
	changed.emit(definition_id, remaining)
	return true


func snapshot() -> Dictionary:
	var serialized: Dictionary = {}
	for id: StringName in counts:
		serialized[String(id)] = int(counts[id])
	return serialized


func restore_snapshot(state: Dictionary, missing_ids: Array[String] = []) -> void:
	counts.clear()
	for key: Variant in state:
		var id := StringName(str(key))
		if data.item(id) == null:
			missing_ids.append(String(id))
			continue
		var quantity := maxi(0, int(state[key]))
		if quantity > 0:
			counts[id] = quantity
			changed.emit(id, quantity)

