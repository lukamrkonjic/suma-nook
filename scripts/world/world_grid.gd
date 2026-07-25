class_name WorldGrid
extends RefCounted
## Authoritative model of the constructed world. Pure data — no scene nodes —
## so the whole thing round-trips through the save and runs in headless tests.
## Grid coordinates (Vector2i) exist for PLACEMENT ONLY; the player's transform
## is continuous and never quantized here.

signal cell_changed(coord: Vector2i)
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
var next_instance_id: int = 1
var home_cell := Vector2i.ZERO

var tile_size: float:
	get: return registries.tunef("tile_size", 2.0)


func _init(regs: Registries) -> void:
	registries = regs


# ------------------------------------------------------------------ queries

func has_cell(coord: Vector2i) -> bool:
	return cells.has(coord)


func cell(coord: Vector2i) -> CellState:
	return cells.get(coord)


func tile_def(coord: Vector2i) -> Defs.TileDefinition:
	var state := cell(coord)
	return registries.tile(state.tile_id) if state else null


func placed_tile_count() -> int:
	var count := 0
	for state: CellState in cells.values():
		if not state.starter and state.landmark_id == "":
			count += 1
	return count


func is_walkable(coord: Vector2i) -> bool:
	var state := cell(coord)
	if state == null:
		return false
	var def := registries.tile(state.tile_id)
	return def != null and def.walkable


func is_adjacent_to_world(coord: Vector2i) -> bool:
	for offset: Vector2i in NEIGHBORS:
		if cells.has(coord + offset):
			return true
	return false


func can_place_tile(coord: Vector2i) -> bool:
	return not cells.has(coord) and is_adjacent_to_world(coord)


func world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(roundi(world_pos.x / tile_size), roundi(world_pos.z / tile_size))


func cell_to_world(coord: Vector2i) -> Vector3:
	return Vector3(coord.x * tile_size, 0.0, coord.y * tile_size)


## Deterministic local socket offsets inside a cell (socket 0 = major center).
func socket_offset(socket_index: int) -> Vector3:
	match socket_index:
		0: return Vector3.ZERO
		1: return Vector3(-0.55, 0.0, -0.55)
		2: return Vector3(0.6, 0.0, -0.5)
		3: return Vector3(-0.5, 0.0, 0.6)
		_: return Vector3(0.55, 0.0, 0.55)


func free_socket(coord: Vector2i, socket_type: String) -> int:
	var state := cell(coord)
	var def := tile_def(coord)
	if state == null or def == null or state.landmark_id != "":
		return -1
	var taken := {}
	for s in state.structures:
		taken[s.socket_index] = true
	if socket_type == "structure":
		return -1 if taken.has(0) else 0
	for index in range(1, def.decor_sockets + 1):
		if not taken.has(index):
			return index
	return -1


# ------------------------------------------------------------------ mutation

func place_tile(coord: Vector2i, tile_id: String, rotation: int = 0, starter := false) -> CellState:
	var state := CellState.new()
	state.tile_id = tile_id
	state.rotation = posmod(rotation, 4)
	state.starter = starter
	cells[coord] = state
	cell_changed.emit(coord)
	grid_changed.emit()
	return state


func remove_tile(coord: Vector2i) -> CellState:
	var state := cell(coord)
	if state == null:
		return null
	cells.erase(coord)
	cell_changed.emit(coord)
	grid_changed.emit()
	return state


func move_tile(from: Vector2i, to: Vector2i) -> bool:
	var state := cell(from)
	if state == null or cells.has(to):
		return false
	cells.erase(from)
	cells[to] = state
	cell_changed.emit(from)
	cell_changed.emit(to)
	grid_changed.emit()
	return true


func add_structure(coord: Vector2i, structure_id: String, socket_index: int, rotation: int = 0) -> StructureState:
	var state := cell(coord)
	if state == null:
		return null
	var s := StructureState.new()
	s.instance_id = next_instance_id
	next_instance_id += 1
	s.structure_id = structure_id
	s.socket_index = socket_index
	s.rotation = posmod(rotation, 4)
	state.structures.append(s)
	cell_changed.emit(coord)
	return s


func remove_structure(coord: Vector2i, instance_id: int) -> StructureState:
	var state := cell(coord)
	if state == null:
		return null
	for i in state.structures.size():
		if state.structures[i].instance_id == instance_id:
			var s := state.structures[i]
			state.structures.remove_at(i)
			cell_changed.emit(coord)
			return s
	return null


func find_structure(instance_id: int) -> Dictionary:
	for coord: Vector2i in cells:
		for s in cells[coord].structures:
			if s.instance_id == instance_id:
				return {"coord": coord, "structure": s}
	return {}


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
	for coord: Vector2i in cells:
		var entry: Dictionary = cells[coord].to_dict()
		entry["x"] = coord.x
		entry["y"] = coord.y
		cell_list.append(entry)
	return {"cells": cell_list, "next_iid": next_instance_id, "home": [home_cell.x, home_cell.y]}


func from_save_dict(data: Dictionary) -> void:
	cells.clear()
	for entry in data.get("cells", []):
		var coord := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		var state := CellState.from_dict(entry)
		if registries.tile(state.tile_id) == null and state.landmark_id == "":
			push_warning("WorldGrid: dropping cell with unknown tile '%s'" % state.tile_id)
			continue
		cells[coord] = state
	next_instance_id = int(data.get("next_iid", 1))
	var home: Array = data.get("home", [0, 0])
	home_cell = Vector2i(int(home[0]), int(home[1]))
	grid_changed.emit()
