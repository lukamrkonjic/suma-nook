extends Node
class_name ForestProgression

signal growth_completed(total_tiles: int, tiles_grown: int)
signal discovery_unlocked(definition_id: StringName, message: String)

const MILESTONES := {
	3: {"id": &"sapling", "message": "The young grove remembers how to grow trees."},
	6: {"id": &"mushroom_ring", "message": "A mushroom circle appears in your field guide."},
	10: {"id": &"root_bench", "message": "The paths feel lived in. A woodland bench is unlocked."},
	15: {"id": &"glow_lantern", "message": "Deep forest light teaches you to craft a lantern."},
	22: {"id": &"root_arch", "message": "An ancient root arch is ready for a grand trail."},
}

var grid: GridManager
var economy: EconomyManager
var storage: StorageManager
var collection: CollectionManager
var tiles_grown := 0
var claimed: Dictionary = {}
var _seed := 0


func setup(
		grid_manager: GridManager,
		economy_manager: EconomyManager,
		storage_manager: StorageManager,
		collection_manager: CollectionManager,
		world_seed: int
	) -> void:
	grid = grid_manager
	economy = economy_manager
	storage = storage_manager
	collection = collection_manager
	_seed = world_seed
	tiles_grown = maxi(0, grid.ground.size() - 9)


func forest_light() -> int:
	return economy.amount(&"meadow_coin")


func can_grow() -> bool:
	return forest_light() > 0


func next_ground_id(target: Vector3i) -> StringName:
	var roll := posmod(
		target.x * 73856093 ^ target.z * 19349663 ^ _seed ^ (tiles_grown + 1) * 83492791,
		100
	)
	if roll < 68:
		return &"ground_grass"
	if roll < 86:
		return &"ground_loam"
	return &"ground_stone"


func complete_growth() -> Dictionary:
	if not economy.spend(&"meadow_coin", 1):
		return {}
	tiles_grown += 1
	growth_completed.emit(grid.ground.size(), tiles_grown)
	var result := {"tiles_grown": tiles_grown}
	if MILESTONES.has(tiles_grown) and not claimed.has(tiles_grown):
		claimed[tiles_grown] = true
		var row: Dictionary = MILESTONES[tiles_grown]
		var definition_id: StringName = row.id
		storage.add(definition_id, 1)
		collection.record_obtained(definition_id)
		result["unlock"] = String(definition_id)
		result["message"] = str(row.message)
		discovery_unlocked.emit(definition_id, str(row.message))
	return result


func next_milestone_text() -> String:
	var milestones: Array = MILESTONES.keys()
	milestones.sort()
	for threshold: int in milestones:
		if tiles_grown < threshold:
			var row: Dictionary = MILESTONES[threshold]
			return "%d more tiles → %s" % [threshold - tiles_grown, str(row.id).replace("_", " ").capitalize()]
	return "The deep woods are open. Keep shaping your story."


func snapshot() -> Dictionary:
	var claimed_rows: Array[int] = []
	for threshold: int in claimed:
		if bool(claimed[threshold]):
			claimed_rows.append(threshold)
	claimed_rows.sort()
	return {"tiles_grown": tiles_grown, "claimed": claimed_rows}


func restore_snapshot(state: Dictionary) -> void:
	tiles_grown = maxi(int(state.get("tiles_grown", maxi(0, grid.ground.size() - 9))), maxi(0, grid.ground.size() - 9))
	claimed.clear()
	for value: Variant in state.get("claimed", []):
		claimed[int(value)] = true
