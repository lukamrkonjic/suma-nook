class_name DiscoveryJournal
extends RefCounted
## Single source of truth for Unfolding World discovery output: unlocked
## pattern sets and the entry log behind the journal/atlas UI. Unlocked
## means unlimited copies forever — unlocks gate *kinds*, never quantities.
##
## Kept separate from world state so a future "new world, keep collection"
## feature is a save-layout decision, not a refactor.

signal entry_added(entry: Dictionary)
signal unlocked_changed

var registries: Registries
var stock: StockManager

## Unlocked pattern ids by kind. Membership is the unlock.
var unlocked_structures: Dictionary = {}
var unlocked_tiles: Dictionary = {}
## Chronological discovery entries:
## {"kind": "first"|"treasure"|"dormant"|"keepsake", "id": String,
##  "text": String, "nook": [x, y], "unix": float}
var entries: Array[Dictionary] = []


func _init(regs: Registries, player_stock: StockManager) -> void:
	registries = regs
	stock = player_stock


func is_structure_unlocked(structure_id: String) -> bool:
	return unlocked_structures.has(structure_id)


func is_tile_unlocked(tile_id: String) -> bool:
	return unlocked_tiles.has(tile_id)


## Unlocking also grants one physical copy so the discovery is immediately
## placeable; the unlock set itself is what makes copies unlimited.
func unlock_structure(structure_id: String) -> void:
	if registries.structure(structure_id) == null:
		return
	if not unlocked_structures.has(structure_id):
		unlocked_structures[structure_id] = true
		stock.add_structure(structure_id)
		unlocked_changed.emit()


func unlock_tile(tile_id: String) -> void:
	if registries.tile(tile_id) == null:
		return
	if not unlocked_tiles.has(tile_id):
		unlocked_tiles[tile_id] = true
		stock.add_tile(tile_id)
		unlocked_changed.emit()


func add_entry(
	kind: String, id: String, text: String, nook: Vector2i,
	unix_time: float
) -> Dictionary:
	var entry := {
		"kind": kind,
		"id": id,
		"text": text,
		"nook": [nook.x, nook.y],
		"unix": unix_time,
	}
	entries.append(entry)
	entry_added.emit(entry.duplicate(true))
	return entry


func entries_of_kind(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if String(entry.get("kind", "")) == kind:
			result.append(entry.duplicate(true))
	return result


## World breadth, if anything ever wants it, is just entry count crossing
## thresholds — never a separate progression currency.
func entry_count() -> int:
	return entries.size()


func to_save_dict() -> Dictionary:
	return {
		"unlocked_structures": unlocked_structures.keys(),
		"unlocked_tiles": unlocked_tiles.keys(),
		"entries": entries.duplicate(true),
	}


func from_save_dict(data: Dictionary) -> void:
	unlocked_structures.clear()
	unlocked_tiles.clear()
	entries.clear()
	for id: Variant in data.get("unlocked_structures", []):
		unlocked_structures[String(id)] = true
	for id: Variant in data.get("unlocked_tiles", []):
		unlocked_tiles[String(id)] = true
	for raw: Variant in data.get("entries", []):
		if raw is Dictionary:
			entries.append((raw as Dictionary).duplicate(true))
