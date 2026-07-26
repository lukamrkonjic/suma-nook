class_name WorldGrid
extends RefCounted
## Authoritative model of the constructed world. Pure data — no scene nodes —
## so the whole thing round-trips through the save and runs in headless tests.
## Grid coordinates (Vector2i) exist for PLACEMENT ONLY; the player's transform
## is continuous and never quantized here.

signal cell_changed(coord: Vector2i)
signal slot_changed(coord: Vector2i, elevation: int)
signal grid_changed

const NEIGHBORS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i(0, 1), Vector2i(0, -1)]


class StructureState:
	extends RefCounted
	var instance_id: int
	var structure_id: String
	var socket_index: int = 0   # 0 = major/center, 1..n = decor sockets
	var rotation: int = 0       # quarter turns

	func to_dict() -> Dictionary:
		return {"iid": instance_id, "id": structure_id, "socket": socket_index, "rot": rotation}

	static func from_dict(d: Dictionary) -> StructureState:
		var s := StructureState.new()
		s.instance_id = int(d.get("iid", 0))
		s.structure_id = String(d.get("id", ""))
		s.socket_index = int(d.get("socket", 0))
		s.rotation = int(d.get("rot", 0))
		return s


class CellState:
	extends RefCounted
	var tile_id: String
	var rotation: int = 0
	var starter := false        # part of the original 3×3 — never removable
	var landmark_id: String = ""  # non-empty when a landmark occupies this cell
	# Resource anchor runtime state (only used when the tile def has an anchor)
	var anchor_actions_done: int = 0
	var anchor_resting := false
	var anchor_regen_left: float = 0.0
	var anchor_upgrade: int = 0
	var structures: Array[StructureState] = []

	func to_dict() -> Dictionary:
		var structs: Array = []
		for s in structures:
			structs.append(s.to_dict())
		return {
			"tile": tile_id, "rot": rotation, "starter": starter, "landmark": landmark_id,
			"a_done": anchor_actions_done, "a_rest": anchor_resting,
			"a_regen": anchor_regen_left, "a_up": anchor_upgrade, "structs": structs,
		}

	static func from_dict(d: Dictionary) -> CellState:
		var c := CellState.new()
		c.tile_id = String(d.get("tile", ""))
		c.rotation = int(d.get("rot", 0))
		c.starter = bool(d.get("starter", false))
		c.landmark_id = String(d.get("landmark", ""))
		c.anchor_actions_done = int(d.get("a_done", 0))
		c.anchor_resting = bool(d.get("a_rest", false))
		c.anchor_regen_left = float(d.get("a_regen", 0.0))
		c.anchor_upgrade = int(d.get("a_up", 0))
		for raw in d.get("structs", []):
			c.structures.append(StructureState.from_dict(raw))
		return c


var registries: Registries
var cells: Dictionary = {}          # Vector2i -> CellState
var stacked_cells: Dictionary = {}  # Vector3i(x, elevation, grid_y) -> CellState
var next_instance_id: int = 1
var home_cell := Vector2i.ZERO

var tile_size: float:
	get: return registries.tunef("tile_size", 2.0)

var block_depth: float:
	get: return registries.tunef("block_depth", 0.9)

var max_stack_elevation: int:
	get: return registries.tunei("max_stack_elevation", 6)


func _init(regs: Registries) -> void:
	registries = regs


# ------------------------------------------------------------------ queries

func has_cell(coord: Vector2i) -> bool:
	return cells.has(coord)


func cell(coord: Vector2i) -> CellState:
	return cells.get(coord)


func slot_key(coord: Vector2i, elevation: int) -> Vector3i:
	return Vector3i(coord.x, elevation, coord.y)


func has_cell_at(coord: Vector2i, elevation: int) -> bool:
	return cells.has(coord) if elevation == 0 else stacked_cells.has(slot_key(coord, elevation))


func cell_at(coord: Vector2i, elevation: int) -> CellState:
	return cells.get(coord) if elevation == 0 else stacked_cells.get(slot_key(coord, elevation))


func tile_def(coord: Vector2i) -> Defs.TileDefinition:
	var state := cell(coord)
	return registries.tile(state.tile_id) if state else null


func tile_def_at(coord: Vector2i, elevation: int) -> Defs.TileDefinition:
	var state := cell_at(coord, elevation)
	return registries.tile(state.tile_id) if state else null


func top_elevation(coord: Vector2i) -> int:
	for elevation in range(max_stack_elevation, 0, -1):
		if has_cell_at(coord, elevation):
			return elevation
	return 0 if has_cell(coord) else -1


func top_cell(coord: Vector2i) -> CellState:
	var elevation := top_elevation(coord)
	return cell_at(coord, elevation) if elevation >= 0 else null


func top_tile_def(coord: Vector2i) -> Defs.TileDefinition:
	var elevation := top_elevation(coord)
	return tile_def_at(coord, elevation) if elevation >= 0 else null


func all_cell_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for coord: Vector2i in cells:
		result.append({"coord": coord, "elevation": 0, "state": cells[coord]})
	for key: Vector3i in stacked_cells:
		result.append({
			"coord": Vector2i(key.x, key.z),
			"elevation": key.y,
			"state": stacked_cells[key],
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["elevation"]) != int(b["elevation"]):
			return int(a["elevation"]) < int(b["elevation"])
		var coord_a: Vector2i = a["coord"]
		var coord_b: Vector2i = b["coord"]
		return coord_a.y < coord_b.y if coord_a.x == coord_b.x else coord_a.x < coord_b.x
	)
	return result


func highest_elevation() -> int:
	var highest := 0
	for key: Vector3i in stacked_cells:
		highest = maxi(highest, key.y)
	return highest


func placed_tile_count() -> int:
	var count := 0
	for state: CellState in cells.values():
		if not state.starter and state.landmark_id == "":
			count += 1
	return count


func stacked_tile_count() -> int:
	var count := 0
	for state: CellState in stacked_cells.values():
		if state.landmark_id == "":
			count += 1
	return count


func total_tile_count() -> int:
	return cells.size() + stacked_cells.size()


func is_walkable(coord: Vector2i) -> bool:
	var state := cell(coord)
	if state == null:
		return false
	var def := registries.tile(state.tile_id)
	# A raised column is a deliberate piece of elevation. Until a stair/ramp
	# surface connects to it, pathfinding must not route through its solid side.
	return def != null and def.walkable and top_elevation(coord) == 0


func is_adjacent_to_world(coord: Vector2i) -> bool:
	for offset: Vector2i in NEIGHBORS:
		if cells.has(coord + offset):
			return true
	return false


func can_place_tile(coord: Vector2i) -> bool:
	return not cells.has(coord) and is_adjacent_to_world(coord)


func can_place_tile_at(coord: Vector2i, elevation: int, tile_id: String) -> bool:
	if elevation == 0:
		return can_place_tile(coord)
	var placed_def := registries.tile(tile_id)
	if (
		placed_def == null
		or not placed_def.stackable
		or elevation > max_stack_elevation
		or has_cell_at(coord, elevation)
		or top_elevation(coord) != elevation - 1
	):
		return false
	var support := cell_at(coord, elevation - 1)
	var support_def := tile_def_at(coord, elevation - 1)
	return (
		support != null
		and support_def != null
		and support.landmark_id == ""
		and support.structures.is_empty()
		and support_def.supports_tiles
		and support_def.surface_kind == "flat"
	)


func stack_target_elevation(coord: Vector2i, tile_id: String) -> int:
	var elevation := top_elevation(coord) + 1
	return elevation if elevation > 0 and can_place_tile_at(coord, elevation, tile_id) else -1


func world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(roundi(world_pos.x / tile_size), roundi(world_pos.z / tile_size))


func cell_to_world(coord: Vector2i, elevation: int = 0) -> Vector3:
	return Vector3(coord.x * tile_size, elevation * block_depth, coord.y * tile_size)


## Deterministic local socket offsets inside a cell (socket 0 = major center).
func socket_offset(socket_index: int) -> Vector3:
	match socket_index:
		0: return Vector3.ZERO
		1: return Vector3(-0.55, 0.0, -0.55)
		2: return Vector3(0.6, 0.0, -0.5)
		3: return Vector3(-0.5, 0.0, 0.6)
		_: return Vector3(0.55, 0.0, 0.55)


func free_socket(coord: Vector2i, socket_type: String, elevation: int = 0) -> int:
	var state := cell_at(coord, elevation)
	var def := tile_def_at(coord, elevation)
	if state == null or def == null or state.landmark_id != "":
		return -1
	var taken := {}
	for s in state.structures:
		taken[s.socket_index] = true
	if socket_type == "structure":
		return -1 if def.structure_sockets <= 0 or taken.has(0) else 0
	for index in range(1, def.decor_sockets + 1):
		if not taken.has(index):
			return index
	return -1


func can_place_structure_at(coord: Vector2i, elevation: int, structure_id: String) -> bool:
	var tile := tile_def_at(coord, elevation)
	var structure := registries.structure(structure_id)
	if tile == null or structure == null or not tile.supports_decor:
		return false
	if elevation > 0 and not structure.allow_elevated:
		return false
	return free_socket(coord, structure.socket_type, elevation) >= 0


# ------------------------------------------------------------------ mutation

func place_tile(coord: Vector2i, tile_id: String, rotation: int = 0, starter := false) -> CellState:
	return place_tile_at(coord, 0, tile_id, rotation, starter)


func place_tile_at(
	coord: Vector2i,
	elevation: int,
	tile_id: String,
	rotation: int = 0,
	starter := false
) -> CellState:
	var state := CellState.new()
	state.tile_id = tile_id
	state.rotation = posmod(rotation, 4)
	state.starter = starter
	restore_cell_at(coord, elevation, state)
	return state


func remove_tile(coord: Vector2i) -> CellState:
	return remove_tile_at(coord, 0)


func remove_tile_at(coord: Vector2i, elevation: int) -> CellState:
	var state := cell_at(coord, elevation)
	if state == null or top_elevation(coord) > elevation:
		return null
	if elevation == 0:
		cells.erase(coord)
	else:
		stacked_cells.erase(slot_key(coord, elevation))
	_emit_slot_changed(coord, elevation)
	grid_changed.emit()
	return state


func move_tile(from: Vector2i, to: Vector2i) -> bool:
	return move_tile_at(from, 0, to, 0)


func move_tile_at(from: Vector2i, from_elevation: int, to: Vector2i, to_elevation: int) -> bool:
	var state := cell_at(from, from_elevation)
	if state == null or has_cell_at(to, to_elevation) or top_elevation(from) > from_elevation:
		return false
	if to_elevation == 0:
		if not can_place_tile(to):
			return false
	elif not can_place_tile_at(to, to_elevation, state.tile_id):
		return false
	if from_elevation == 0:
		cells.erase(from)
	else:
		stacked_cells.erase(slot_key(from, from_elevation))
	if to_elevation == 0:
		cells[to] = state
	else:
		stacked_cells[slot_key(to, to_elevation)] = state
	_emit_slot_changed(from, from_elevation)
	_emit_slot_changed(to, to_elevation)
	grid_changed.emit()
	return true


func restore_cell_at(coord: Vector2i, elevation: int, state: CellState) -> void:
	if elevation == 0:
		cells[coord] = state
	else:
		stacked_cells[slot_key(coord, elevation)] = state
	_emit_slot_changed(coord, elevation)
	grid_changed.emit()


func add_structure(
	coord: Vector2i,
	structure_id: String,
	socket_index: int,
	rotation: int = 0,
	elevation: int = 0
) -> StructureState:
	var state := cell_at(coord, elevation)
	if state == null:
		return null
	var s := StructureState.new()
	s.instance_id = next_instance_id
	next_instance_id += 1
	s.structure_id = structure_id
	s.socket_index = socket_index
	s.rotation = posmod(rotation, 4)
	state.structures.append(s)
	_emit_slot_changed(coord, elevation)
	return s


func remove_structure(coord: Vector2i, instance_id: int, elevation: int = -1) -> StructureState:
	if elevation < 0:
		var found := find_structure(instance_id)
		if found.is_empty():
			return null
		elevation = int(found["elevation"])
	var state := cell_at(coord, elevation)
	if state == null:
		return null
	for i in state.structures.size():
		if state.structures[i].instance_id == instance_id:
			var s := state.structures[i]
			state.structures.remove_at(i)
			_emit_slot_changed(coord, elevation)
			return s
	return null


func find_structure(instance_id: int) -> Dictionary:
	for slot: Dictionary in all_cell_slots():
		var state: CellState = slot["state"]
		for s in state.structures:
			if s.instance_id == instance_id:
				return {
					"coord": slot["coord"],
					"elevation": slot["elevation"],
					"structure": s,
				}
	return {}


func _emit_slot_changed(coord: Vector2i, elevation: int) -> void:
	slot_changed.emit(coord, elevation)
	cell_changed.emit(coord)


# ------------------------------------------------------------------ connectivity & safety

## True when every walkable cell can still reach `anchor_cell` after
## hypothetically removing `removed` (pass an invalid coord for pure checks).
func connected_without(removed: Vector2i, anchor_cell: Vector2i) -> bool:
	if not cells.has(anchor_cell) or anchor_cell == removed:
		return false
	var visited := {anchor_cell: true}
	var queue: Array[Vector2i] = [anchor_cell]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_back()
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = current + offset
			if next == removed or visited.has(next) or not cells.has(next):
				continue
			visited[next] = true
			queue.append(next)
	for coord: Vector2i in cells:
		if coord != removed and not visited.has(coord):
			return false
	return true


## Nearest walkable cell to a coordinate (breadth-first, deterministic order).
func nearest_walkable(from: Vector2i, excluding := Vector2i(9999, 9999)) -> Vector2i:
	if is_walkable(from) and from != excluding:
		return from
	var visited := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = current + offset
			if visited.has(next):
				continue
			visited[next] = true
			if next != excluding and is_walkable(next):
				return next
			if cells.has(next):
				queue.append(next)
	return home_cell


func bounds() -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var first: Vector2i = cells.keys()[0]
	var rect := Rect2i(first, Vector2i.ONE)
	for coord: Vector2i in cells:
		rect = rect.expand(coord)
	return rect


# ------------------------------------------------------------------ persistence

func to_save_dict() -> Dictionary:
	var cell_list: Array = []
	for slot: Dictionary in all_cell_slots():
		var coord: Vector2i = slot["coord"]
		var entry: Dictionary = (slot["state"] as CellState).to_dict()
		entry["x"] = coord.x
		entry["y"] = coord.y
		entry["e"] = int(slot["elevation"])
		cell_list.append(entry)
	return {"cells": cell_list, "next_iid": next_instance_id, "home": [home_cell.x, home_cell.y]}


func from_save_dict(data: Dictionary) -> void:
	cells.clear()
	stacked_cells.clear()
	for entry in data.get("cells", []):
		var coord := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var elevation := int(entry.get("e", 0))
		var state := CellState.from_dict(entry)
		if registries.tile(state.tile_id) == null and state.landmark_id == "":
			registries.ensure_compatibility_definition("tiles", state.tile_id)
			push_warning("WorldGrid: preserving unknown tile '%s' with a compatibility visual" % state.tile_id)
		for structure: StructureState in state.structures:
			if registries.structure(structure.structure_id) == null:
				registries.ensure_compatibility_definition("structures", structure.structure_id)
		if elevation == 0:
			cells[coord] = state
		else:
			stacked_cells[slot_key(coord, elevation)] = state
	next_instance_id = int(data.get("next_iid", 1))
	var home: Array = data.get("home", [0, 0])
	home_cell = Vector2i(int(home[0]), int(home[1]))
	grid_changed.emit()
