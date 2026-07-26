class_name StockManager
extends RefCounted
## Unplaced world pieces: tiles chosen from parcels, crafted structures, and
## packed landmark deeds. Anything stored here is placeable later and can
## never disappear — storing a placed piece returns it to stock.

signal stock_changed

var registries: Registries
var tiles: Dictionary = {}        # tile_id -> count
var structures: Dictionary = {}   # structure_id -> count
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


func take_structure(structure_id: String) -> bool:
	if structure_count(structure_id) < 1:
		return false
	structures[structure_id] -= 1
	if structures[structure_id] <= 0:
		structures.erase(structure_id)
	stock_changed.emit()
	return true


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
	return {"tiles": tiles.duplicate(), "structures": structures.duplicate(), "deeds": landmark_deeds.duplicate()}


func from_save_dict(data: Dictionary) -> void:
	tiles.clear()
	for raw_id: String in data.get("tiles", {}):
		var amount := int(data["tiles"][raw_id])
		if amount <= 0:
			continue
		if registries != null and registries.tile(raw_id) == null:
			registries.ensure_compatibility_definition("tiles", raw_id)
		tiles[raw_id] = amount
	structures.clear()
	for raw_id: String in data.get("structures", {}):
		var amount := int(data["structures"][raw_id])
		if amount <= 0:
			continue
		if registries != null and registries.structure(raw_id) == null:
			registries.ensure_compatibility_definition("structures", raw_id)
		structures[raw_id] = amount
	landmark_deeds.clear()
	for deed in data.get("deeds", []):
		var landmark_id := String(deed)
		if registries != null and registries.landmark(landmark_id) == null:
			registries.ensure_compatibility_definition("landmarks", landmark_id)
		landmark_deeds.append(landmark_id)
	stock_changed.emit()
