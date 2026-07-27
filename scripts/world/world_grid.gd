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
	var parent_instance_id: int = 0  # 0 = directly supported by the tile
	var support_slot_id: String = "" # named slot on parent_instance_id
	# Resource runtime belongs to the placeable instance, not its terrain.
	var anchor_actions_done: int = 0
	var anchor_resting := false
	var anchor_regen_left: float = 0.0
	var anchor_upgrade: int = 0

	func to_dict() -> Dictionary:
		return {
			"iid": instance_id,
			"id": structure_id,
			"socket": socket_index,
			"rot": rotation,
			"parent": parent_instance_id,
			"support": support_slot_id,
			"a_done": anchor_actions_done,
			"a_rest": anchor_resting,
			"a_regen": anchor_regen_left,
			"a_up": anchor_upgrade,
		}

	static func from_dict(d: Dictionary) -> StructureState:
		var s := StructureState.new()
		s.instance_id = int(d.get("iid", 0))
		s.structure_id = String(d.get("id", ""))
		s.socket_index = int(d.get("socket", 0))
		s.rotation = int(d.get("rot", 0))
		s.parent_instance_id = int(d.get("parent", 0))
		s.support_slot_id = String(d.get("support", ""))
		s.anchor_actions_done = int(d.get("a_done", 0))
		s.anchor_resting = bool(d.get("a_rest", false))
		s.anchor_regen_left = float(d.get("a_regen", 0.0))
		s.anchor_upgrade = int(d.get("a_up", 0))
		return s


class CellState:
	extends RefCounted
	var tile_id: String
	var rotation: int = 0
	var starter := false        # part of the original composed opening zone
	var movement_locked := false  # explicit, save-safe exception to tile moving
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
			"tile": tile_id, "rot": rotation, "starter": starter,
			"locked": movement_locked, "landmark": landmark_id,
			"a_done": anchor_actions_done, "a_rest": anchor_resting,
			"a_regen": anchor_regen_left, "a_up": anchor_upgrade, "structs": structs,
		}

	static func from_dict(d: Dictionary) -> CellState:
		var c := CellState.new()
		c.tile_id = String(d.get("tile", ""))
		c.rotation = int(d.get("rot", 0))
		c.starter = bool(d.get("starter", false))
		c.movement_locked = bool(d.get("locked", false))
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
	get: return registries.tunef("tile_size", 1.35)

var block_depth: float:
	get: return registries.tunef("block_depth", 0.5)

var max_stack_elevation: int:
	get: return registries.tunei("max_stack_elevation", 6)

var max_object_stack_depth: int:
	get: return registries.tunei("max_object_stack_depth", 6)


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


## Contiguous tile hierarchy beginning at a selected elevation. Entries keep
## their relative elevation so the whole column can be moved atomically.
func tile_stack_from(coord: Vector2i, base_elevation: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var top := top_elevation(coord)
	if base_elevation < 0 or top < base_elevation:
		return result
	for elevation in range(base_elevation, top + 1):
		var state := cell_at(coord, elevation)
		if state == null:
			break
		result.append({
			"relative_elevation": elevation - base_elevation,
			"state": state,
		})
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


## Physical boundary generation must distinguish a genuine void/water edge
## from a raised but otherwise walkable column. Raised columns stay excluded
## from automatic click routes (they require a deliberate jump), yet their top
## surface must not be sealed behind the same tall wall used at the world edge.
func has_walkable_top_surface(coord: Vector2i) -> bool:
	var elevation := top_elevation(coord)
	if elevation < 0:
		return false
	var definition := tile_def_at(coord, elevation)
	return definition != null and definition.walkable


## Player traversal can also be supplied by an object such as a dock. Keep
## this separate from terrain walkability so home placement and safe-refuge
## logic never mistake water for permanent land.
func has_walkable_structure_surface(coord: Vector2i) -> bool:
	if top_elevation(coord) != 0:
		return false
	var state := cell(coord)
	if state == null:
		return false
	for structure: StructureState in state.structures:
		if structure.parent_instance_id != 0:
			continue
		var definition := registries.structure(structure.structure_id)
		if definition != null and definition.collision_profile == "walkable_surface":
			return true
	return false


func is_traversable(coord: Vector2i) -> bool:
	return is_walkable(coord) or has_walkable_structure_surface(coord)


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


## Every direct tile-root object is centered. Socket ids remain stable
## persistence/type selectors; they no longer encode arbitrary corner offsets.
func socket_offset(_socket_index: int) -> Vector3:
	return Vector3.ZERO


func free_socket(coord: Vector2i, socket_type: String, elevation: int = 0) -> int:
	var state := cell_at(coord, elevation)
	var def := tile_def_at(coord, elevation)
	if (
		state == null
		or def == null
		or state.landmark_id != ""
		or top_elevation(coord) != elevation
	):
		return -1
	for s in state.structures:
		if s.parent_instance_id != 0:
			continue
		# One direct object per tile/elevation. Object children use named support
		# slots and therefore do not consume another tile-root position.
		return -1
	if socket_type == "structure":
		return 0 if def.structure_sockets > 0 else -1
	return 1 if def.decor_sockets > 0 else -1


func can_place_structure_at(coord: Vector2i, elevation: int, structure_id: String) -> bool:
	var tile := tile_def_at(coord, elevation)
	var structure := registries.structure(structure_id)
	if (
		tile == null
		or structure == null
		or top_elevation(coord) != elevation
		or not tile.supports_decor
		or not structure.supports_surface(tile.surface_kind)
	):
		return false
	if elevation > 0 and not structure.allow_elevated:
		return false
	return free_socket(coord, structure.socket_type, elevation) >= 0


func structure_children(instance_id: int) -> Array[StructureState]:
	var result: Array[StructureState] = []
	var found := find_structure(instance_id)
	if found.is_empty():
		return result
	var state: CellState = found["state"]
	for structure: StructureState in state.structures:
		if structure.parent_instance_id == instance_id:
			result.append(structure)
	result.sort_custom(func(a: StructureState, b: StructureState) -> bool:
		return a.instance_id < b.instance_id
	)
	return result


func structure_subtree(instance_id: int) -> Array[StructureState]:
	var result: Array[StructureState] = []
	var pending: Array[int] = [instance_id]
	var seen := {}
	while not pending.is_empty():
		var current: int = pending.pop_front()
		if seen.has(current):
			continue
		seen[current] = true
		var found := find_structure(current)
		if found.is_empty():
			continue
		var structure: StructureState = found["structure"]
		result.append(structure)
		for child: StructureState in structure_children(current):
			pending.append(child.instance_id)
	return result


func structure_depth(instance_id: int) -> int:
	var depth := 0
	var seen := {}
	var found := find_structure(instance_id)
	while not found.is_empty():
		var structure: StructureState = found["structure"]
		if structure.parent_instance_id == 0:
			return depth
		if seen.has(structure.instance_id):
			return max_object_stack_depth
		seen[structure.instance_id] = true
		depth += 1
		found = find_structure(structure.parent_instance_id)
	return max_object_stack_depth


func structure_stack_height(stack: Array[StructureState]) -> int:
	if stack.is_empty():
		return 0
	var root_id := stack[0].instance_id
	var by_id := {}
	for structure: StructureState in stack:
		by_id[structure.instance_id] = structure
	var highest := 0
	for structure: StructureState in stack:
		var depth := 0
		var current := structure
		var seen := {}
		while current.instance_id != root_id:
			if seen.has(current.instance_id) or not by_id.has(current.parent_instance_id):
				return max_object_stack_depth
			seen[current.instance_id] = true
			depth += 1
			current = by_id[current.parent_instance_id]
		highest = maxi(highest, depth)
	return highest


func free_support_slot(
	parent_instance_id: int,
	candidate_structure_id: String,
	requested_slot_id: String = ""
) -> String:
	var parent_found := find_structure(parent_instance_id)
	if parent_found.is_empty():
		return ""
	if top_elevation(parent_found["coord"]) != int(parent_found["elevation"]):
		return ""
	var parent_state: StructureState = parent_found["structure"]
	var parent_def := registries.structure(parent_state.structure_id)
	var candidate_def := registries.structure(candidate_structure_id)
	if (
		parent_def == null
		or candidate_def == null
		or not candidate_def.can_be_stacked
		or structure_depth(parent_instance_id) + 1 >= max_object_stack_depth
	):
		return ""
	var occupied := {}
	var cell_state: CellState = parent_found["state"]
	for structure: StructureState in cell_state.structures:
		if structure.parent_instance_id == parent_instance_id:
			occupied[structure.support_slot_id] = true
	for slot: Defs.SupportSlotDefinition in parent_def.support_slots:
		if (
			(requested_slot_id == "" or slot.id == requested_slot_id)
			and not occupied.has(slot.id)
			and slot.accepts_definition(candidate_def)
		):
			return slot.id
	return ""


func can_place_structure_on(
	parent_instance_id: int,
	candidate_structure_id: String,
	requested_slot_id: String = ""
) -> bool:
	return free_support_slot(
		parent_instance_id,
		candidate_structure_id,
		requested_slot_id
	) != ""


func structure_local_transform(instance_id: int) -> Transform3D:
	var found := find_structure(instance_id)
	if found.is_empty():
		return Transform3D.IDENTITY
	var state: CellState = found["state"]
	var by_id := {}
	for structure: StructureState in state.structures:
		by_id[structure.instance_id] = structure
	return _structure_local_transform_in_state(instance_id, by_id, {})


## Same transform resolver for a temporarily detached cell. Placement ghosts
## use this so supported objects remain visually attached during an atomic
## tile-column move.
func structure_local_transform_in_cell(
	state: CellState,
	instance_id: int
) -> Transform3D:
	if state == null:
		return Transform3D.IDENTITY
	var by_id := {}
	for structure: StructureState in state.structures:
		by_id[structure.instance_id] = structure
	return _structure_local_transform_in_state(instance_id, by_id, {})


func _structure_local_transform_in_state(
	instance_id: int,
	by_id: Dictionary,
	visiting: Dictionary
) -> Transform3D:
	if not by_id.has(instance_id) or visiting.has(instance_id):
		return Transform3D.IDENTITY
	visiting[instance_id] = true
	var structure: StructureState = by_id[instance_id]
	var local_basis := Basis(Vector3.UP, structure.rotation * PI * 0.5)
	if structure.parent_instance_id == 0:
		visiting.erase(instance_id)
		return Transform3D(local_basis, socket_offset(structure.socket_index))
	if not by_id.has(structure.parent_instance_id):
		visiting.erase(instance_id)
		return Transform3D(local_basis, socket_offset(structure.socket_index))
	var parent: StructureState = by_id[structure.parent_instance_id]
	var parent_def := registries.structure(parent.structure_id)
	var slot := (
		parent_def.support_slot(structure.support_slot_id)
		if parent_def != null
		else null
	)
	if slot == null:
		visiting.erase(instance_id)
		return Transform3D(local_basis, socket_offset(structure.socket_index))
	var parent_transform := _structure_local_transform_in_state(
		structure.parent_instance_id,
		by_id,
		visiting
	)
	visiting.erase(instance_id)
	return parent_transform * Transform3D(local_basis, slot.offset)


func support_slot_local_transform(parent_instance_id: int, slot_id: String) -> Transform3D:
	var found := find_structure(parent_instance_id)
	if found.is_empty():
		return Transform3D.IDENTITY
	var parent: StructureState = found["structure"]
	var parent_def := registries.structure(parent.structure_id)
	var slot := parent_def.support_slot(slot_id) if parent_def != null else null
	if slot == null:
		return structure_local_transform(parent_instance_id)
	return structure_local_transform(parent_instance_id) * Transform3D(
		Basis.IDENTITY,
		slot.offset
	)


# ------------------------------------------------------------------ mutation

func place_tile(
	coord: Vector2i,
	tile_id: String,
	rotation: int = 0,
	starter := false,
	movement_locked := false
) -> CellState:
	return place_tile_at(coord, 0, tile_id, rotation, starter, movement_locked)


func place_tile_at(
	coord: Vector2i,
	elevation: int,
	tile_id: String,
	rotation: int = 0,
	starter := false,
	movement_locked := false
) -> CellState:
	var state := CellState.new()
	state.tile_id = tile_id
	state.rotation = posmod(rotation, 4)
	state.starter = starter
	state.movement_locked = movement_locked
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
	var stack := detach_tile_stack(from, from_elevation)
	if stack.is_empty():
		return false
	if restore_tile_stack(to, to_elevation, stack):
		return true
	restore_tile_stack(from, from_elevation, stack, false)
	return false


func can_restore_tile_stack(
	coord: Vector2i,
	base_elevation: int,
	stack: Array
) -> bool:
	if stack.is_empty() or base_elevation < 0:
		return false
	var previous_state: CellState = null
	var expected_relative := 0
	for entry: Dictionary in stack:
		var relative := int(entry.get("relative_elevation", -1))
		var state: CellState = entry.get("state")
		var elevation := base_elevation + relative
		if (
			state == null
			or relative != expected_relative
			or elevation > max_stack_elevation
			or has_cell_at(coord, elevation)
		):
			return false
		var definition := registries.tile(state.tile_id)
		if definition == null:
			return false
		if relative == 0:
			if base_elevation == 0:
				if not can_place_tile(coord):
					return false
			elif not can_place_tile_at(coord, base_elevation, state.tile_id):
				return false
		else:
			var support_def := registries.tile(previous_state.tile_id)
			if (
				not definition.stackable
				or support_def == null
				or not support_def.supports_tiles
				or support_def.surface_kind != "flat"
				or not previous_state.structures.is_empty()
				or previous_state.landmark_id != ""
			):
				return false
		previous_state = state
		expected_relative += 1
	return true


func detach_tile_stack(coord: Vector2i, base_elevation: int) -> Array[Dictionary]:
	var stack := tile_stack_from(coord, base_elevation)
	if stack.is_empty():
		return stack
	for index in range(stack.size() - 1, -1, -1):
		var elevation := base_elevation + int(stack[index]["relative_elevation"])
		if elevation == 0:
			cells.erase(coord)
		else:
			stacked_cells.erase(slot_key(coord, elevation))
		_emit_slot_changed(coord, elevation)
	grid_changed.emit()
	return stack


func restore_tile_stack(
	coord: Vector2i,
	base_elevation: int,
	stack: Array,
	validate := true
) -> bool:
	if validate and not can_restore_tile_stack(coord, base_elevation, stack):
		return false
	if stack.is_empty():
		return false
	for entry: Dictionary in stack:
		var elevation := base_elevation + int(entry["relative_elevation"])
		var state: CellState = entry["state"]
		if elevation == 0:
			cells[coord] = state
		else:
			stacked_cells[slot_key(coord, elevation)] = state
		_emit_slot_changed(coord, elevation)
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
	var tile := tile_def_at(coord, elevation)
	var structure := registries.structure(structure_id)
	if (
		state == null
		or tile == null
		or structure == null
		or top_elevation(coord) != elevation
		or not tile.supports_decor
		or not structure.supports_surface(tile.surface_kind)
		or (elevation > 0 and not structure.allow_elevated)
		or _has_tile_root_structure(state)
	):
		return null
	if structure.socket_type == "structure":
		if socket_index != 0 or tile.structure_sockets <= 0:
			return null
	else:
		if socket_index < 1 or socket_index > tile.decor_sockets:
			return null
	var s := StructureState.new()
	s.instance_id = next_instance_id
	next_instance_id += 1
	s.structure_id = structure_id
	s.socket_index = socket_index
	s.rotation = posmod(rotation, 4)
	s.parent_instance_id = 0
	s.support_slot_id = ""
	state.structures.append(s)
	_emit_slot_changed(coord, elevation)
	return s


func _has_tile_root_structure(state: CellState) -> bool:
	for structure: StructureState in state.structures:
		if structure.parent_instance_id == 0:
			return true
	return false


func add_structure_on(
	parent_instance_id: int,
	structure_id: String,
	support_slot_id: String = "",
	rotation: int = 0
) -> StructureState:
	var parent_found := find_structure(parent_instance_id)
	if parent_found.is_empty():
		return null
	var resolved_slot := free_support_slot(
		parent_instance_id,
		structure_id,
		support_slot_id
	)
	if resolved_slot == "":
		return null
	var structure := StructureState.new()
	structure.instance_id = next_instance_id
	next_instance_id += 1
	structure.structure_id = structure_id
	structure.socket_index = 0
	structure.rotation = posmod(rotation, 4)
	structure.parent_instance_id = parent_instance_id
	structure.support_slot_id = resolved_slot
	var state: CellState = parent_found["state"]
	state.structures.append(structure)
	_emit_slot_changed(parent_found["coord"], int(parent_found["elevation"]))
	return structure


func remove_structure(coord: Vector2i, instance_id: int, elevation: int = -1) -> StructureState:
	if elevation < 0:
		var found := find_structure(instance_id)
		if found.is_empty():
			return null
		elevation = int(found["elevation"])
	var state := cell_at(coord, elevation)
	if state == null:
		return null
	for child: StructureState in state.structures:
		if child.parent_instance_id == instance_id:
			return null
	for i in state.structures.size():
		if state.structures[i].instance_id == instance_id:
			var s := state.structures[i]
			state.structures.remove_at(i)
			_emit_slot_changed(coord, elevation)
			return s
	return null


func detach_structure_stack(instance_id: int) -> Array[StructureState]:
	var found := find_structure(instance_id)
	var removed: Array[StructureState] = []
	if found.is_empty():
		return removed
	var state: CellState = found["state"]
	var subtree := structure_subtree(instance_id)
	var ids := {}
	for structure: StructureState in subtree:
		ids[structure.instance_id] = true
	for structure: StructureState in state.structures:
		if ids.has(structure.instance_id):
			removed.append(structure)
	for index in range(state.structures.size() - 1, -1, -1):
		if ids.has(state.structures[index].instance_id):
			state.structures.remove_at(index)
	_emit_slot_changed(found["coord"], int(found["elevation"]))
	return removed


func restore_structure_stack(
	coord: Vector2i,
	elevation: int,
	stack: Array[StructureState],
	parent_instance_id: int,
	support_slot_id: String,
	socket_index: int,
	rotation: int
) -> bool:
	if stack.is_empty():
		return false
	var root: StructureState = stack[0]
	var subtree_height := structure_stack_height(stack)
	if subtree_height >= max_object_stack_depth:
		return false
	var resolved_support := support_slot_id
	if parent_instance_id == 0:
		var definition := registries.structure(root.structure_id)
		if (
			definition == null
			or not can_place_structure_at(coord, elevation, root.structure_id)
		):
			return false
		if socket_index < 0:
			socket_index = free_socket(coord, definition.socket_type, elevation)
	else:
		var parent_found := find_structure(parent_instance_id)
		if (
			parent_found.is_empty()
			or parent_found["coord"] != coord
			or int(parent_found["elevation"]) != elevation
			or structure_depth(parent_instance_id) + 1 + subtree_height
				>= max_object_stack_depth
		):
			return false
		resolved_support = free_support_slot(
			parent_instance_id,
			root.structure_id,
			support_slot_id
		)
		if resolved_support == "":
			return false
	var state := cell_at(coord, elevation)
	if state == null:
		return false
	root.parent_instance_id = parent_instance_id
	root.support_slot_id = resolved_support if parent_instance_id != 0 else ""
	root.socket_index = socket_index if parent_instance_id == 0 else 0
	root.rotation = posmod(rotation, 4)
	for structure: StructureState in stack:
		state.structures.append(structure)
		next_instance_id = maxi(next_instance_id, structure.instance_id + 1)
	_emit_slot_changed(coord, elevation)
	return true


func find_structure(instance_id: int) -> Dictionary:
	for slot: Dictionary in all_cell_slots():
		var state: CellState = slot["state"]
		for s in state.structures:
			if s.instance_id == instance_id:
				return {
					"coord": slot["coord"],
					"elevation": slot["elevation"],
					"state": state,
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
