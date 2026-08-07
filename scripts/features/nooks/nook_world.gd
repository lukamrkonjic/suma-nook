class_name NookWorld
extends RefCounted
## Sparse chunk registry for the Unfolding World. A chunk IS a Nook: the
## world is a map of chunk coords to per-Nook meta. Cells themselves live in
## WorldGrid; this holds what the grid cannot know — biome, mood, seed,
## name, treasure assignments, dormant state, fired Firsts, activity.
##
## The world is logically infinite; only revealed chunks exist here.

signal nook_added(coord: Vector2i)
signal nook_updated(coord: Vector2i)


class NookRecord:
	extends RefCounted
	var coord := Vector2i.ZERO
	var biome_id: String = ""
	var mood_id: String = ""
	var density: String = "seeded"
	var seed_value: int = 0
	var stamp_ids: PackedStringArray = PackedStringArray()
	var display_name: String = ""
	var revealed_unix: float = 0.0
	var starter := false
	## Fired First ids (chunk-scoped bookkeeping).
	var firsts_fired: PackedStringArray = PackedStringArray()
	## local "x:y" cell key -> {"pool": String, "host_tag": String,
	## "found": bool} — rolled at generation, invisible until the qualifying
	## clear. Deterministic and save-safe: no farming exploits.
	var treasures: Dictionary = {}
	## Dormant mystery state; empty when this Nook rolled none.
	## {"id": String, "cell": [x, y], "instance_id": int, "score": float,
	##  "pending_wake": bool, "woken": bool}
	var dormant: Dictionary = {}
	## Soft frontier rhythm: placements/clears since reveal.
	var activity := 0

	func to_dict() -> Dictionary:
		return {
			"coord": [coord.x, coord.y],
			"biome": biome_id,
			"mood": mood_id,
			"density": density,
			"seed": seed_value,
			"stamps": Array(stamp_ids),
			"name": display_name,
			"revealed_unix": revealed_unix,
			"starter": starter,
			"firsts": Array(firsts_fired),
			"treasures": treasures.duplicate(true),
			"dormant": dormant.duplicate(true),
			"activity": activity,
		}

	static func from_dict(d: Dictionary) -> NookRecord:
		var record := NookRecord.new()
		var raw_coord: Variant = d.get("coord", [0, 0])
		if raw_coord is Array and (raw_coord as Array).size() >= 2:
			record.coord = Vector2i(int(raw_coord[0]), int(raw_coord[1]))
		record.biome_id = String(d.get("biome", ""))
		record.mood_id = String(d.get("mood", ""))
		record.density = String(d.get("density", "seeded"))
		record.seed_value = int(d.get("seed", 0))
		for stamp: Variant in d.get("stamps", []):
			record.stamp_ids.append(String(stamp))
		record.display_name = String(d.get("name", ""))
		record.revealed_unix = float(d.get("revealed_unix", 0.0))
		record.starter = bool(d.get("starter", false))
		for first: Variant in d.get("firsts", []):
			record.firsts_fired.append(String(first))
		# JSON round-trips numbers as floats; normalize so a reloaded record
		# is bit-identical to the one that was saved.
		var raw_treasures: Dictionary = d.get("treasures", {})
		for key: Variant in raw_treasures:
			var assignment: Dictionary = raw_treasures[key]
			record.treasures[String(key)] = {
				"pool": String(assignment.get("pool", "")),
				"host_tag": String(assignment.get("host_tag", "any")),
				"found": bool(assignment.get("found", false)),
			}
		var raw_dormant: Dictionary = d.get("dormant", {})
		if not raw_dormant.is_empty():
			var raw_cell: Variant = raw_dormant.get("cell", [0, 0])
			record.dormant = {
				"id": String(raw_dormant.get("id", "")),
				"cell": [int(raw_cell[0]), int(raw_cell[1])] \
					if raw_cell is Array and (raw_cell as Array).size() >= 2 \
					else [0, 0],
				"instance_id": int(raw_dormant.get("instance_id", 0)),
				"score": float(raw_dormant.get("score", 0.0)),
				"pending_wake": bool(raw_dormant.get("pending_wake", false)),
				"woken": bool(raw_dormant.get("woken", false)),
			}
		record.activity = int(d.get("activity", 0))
		return record


var registries: Registries
var nooks: Dictionary = {}   # Vector2i -> NookRecord
var _saved_nook_size := 0


func _init(regs: Registries) -> void:
	registries = regs


var nook_size: int:
	get:
		if _saved_nook_size > 0:
			return _saved_nook_size
		return maxi(4, int(registries.nook_config.get("nook_size", 4)))

var origin_cell: Vector2i:
	get:
		var raw: Variant = registries.nook_config.get("origin_cell", [0, 0])
		if raw is Array and (raw as Array).size() >= 2:
			return Vector2i(int(raw[0]), int(raw[1]))
		return Vector2i.ZERO


func has_nook(coord: Vector2i) -> bool:
	return nooks.has(coord)


func nook(coord: Vector2i) -> NookRecord:
	return nooks.get(coord)


func add_nook(record: NookRecord) -> void:
	if _saved_nook_size <= 0:
		_saved_nook_size = maxi(
			4,
			int(registries.nook_config.get("nook_size", 4))
		)
	nooks[record.coord] = record
	nook_added.emit(record.coord)


func touch(coord: Vector2i) -> void:
	if nooks.has(coord):
		nook_updated.emit(coord)


func count() -> int:
	return nooks.size()


## Chunk coord -> world cell of its top-left corner.
func chunk_origin(coord: Vector2i) -> Vector2i:
	return origin_cell + coord * nook_size


## World cell -> owning chunk coord.
func chunk_of_cell(cell: Vector2i) -> Vector2i:
	var local := cell - origin_cell
	return Vector2i(
		int(floor(float(local.x) / float(nook_size))),
		int(floor(float(local.y) / float(nook_size)))
	)


func local_cell(chunk: Vector2i, world_cell: Vector2i) -> Vector2i:
	return world_cell - chunk_origin(chunk)


static func cell_key(local: Vector2i) -> String:
	return "%d:%d" % [local.x, local.y]


## Coords adjacent to revealed Nooks but not yet revealed — the frontier the
## next offer expands into.
func frontier_coords() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord: Vector2i in nooks:
		for offset: Vector2i in WorldGrid.NEIGHBORS:
			var candidate: Vector2i = coord + offset
			if not nooks.has(candidate) and not result.has(candidate):
				result.append(candidate)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.length_squared() < b.length_squared() \
			or (a.length_squared() == b.length_squared() and (a.y < b.y \
			or (a.y == b.y and a.x < b.x)))
	)
	return result


func revealed_neighbors(coord: Vector2i) -> Array[NookRecord]:
	var result: Array[NookRecord] = []
	for offset: Vector2i in WorldGrid.NEIGHBORS:
		var neighbor: NookRecord = nooks.get(coord + offset)
		if neighbor != null:
			result.append(neighbor)
	return result


func to_save_dict() -> Dictionary:
	var records: Array = []
	for coord: Vector2i in nooks:
		records.append((nooks[coord] as NookRecord).to_dict())
	return {"nook_size": nook_size, "nooks": records}


func from_save_dict(data: Dictionary) -> void:
	nooks.clear()
	var raw_records: Array = data.get("nooks", [])
	# Saves made before Nook size became explicit were generated as 8x8.
	# Preserve their coordinate system so loading never shifts or overlaps an
	# existing creative world; only newly started worlds use the compact size.
	_saved_nook_size = int(data.get(
		"nook_size",
		8 if not raw_records.is_empty() else 0
	))
	for raw: Variant in raw_records:
		if raw is Dictionary:
			var record := NookRecord.from_dict(raw)
			nooks[record.coord] = record
