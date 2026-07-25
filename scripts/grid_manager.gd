extends Node
class_name GridManager

signal grid_changed
signal tile_changed(coord: Vector3i)

const CARDINALS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

var data: GameData
var ground: Dictionary = {}
var props: Dictionary = {}
var occupancy: Dictionary = {}
var blocked_cells: Dictionary = {}
var tile_size := 1.8
var tile_height := 0.32
var stack_height := 0.72
var _next_instance_number := 1


func setup(game_data: GameData) -> void:
	data = game_data
	tile_size = float(data.tuning.get("tile_size", tile_size))
	tile_height = float(data.tuning.get("tile_height", tile_height))
	stack_height = float(data.tuning.get("stack_height", stack_height))
	blocked_cells[Vector3i(0, 1, 0)] = "Bloomforge"


func make_initial_island(radius: int) -> void:
	ground.clear()
	props.clear()
	occupancy.clear()
	for x: int in range(-radius, radius + 1):
		for z: int in range(-radius, radius + 1):
			var id := &"ground_grass"
			if abs(x) + abs(z) >= radius * 2:
				id = &"ground_loam"
			elif posmod(x * 13 + z * 7, 11) == 0:
				id = &"ground_stone"
			ground[Vector3i(x, 0, z)] = id
	_next_instance_number = 1
	grid_changed.emit()


func world_position(coord: Vector3i) -> Vector3:
	var y := 0.0 if coord.y == 0 else (float(coord.y - 1) * stack_height + tile_height * 0.5)
	return Vector3(float(coord.x) * tile_size, y, float(coord.z) * tile_size)


func coord_from_world(world: Vector3) -> Vector3i:
	return Vector3i(roundi(world.x / tile_size), 0, roundi(world.z / tile_size))


func footprint_cells(definition: BuildItemDefinition, origin: Vector3i, rotation_quarters: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var size := definition.rotated_footprint(rotation_quarters)
	var x_start := -int(floor(float(size.x - 1) * 0.5))
	var z_start := -int(floor(float(size.y - 1) * 0.5))
	for dx: int in size.x:
		for dz: int in size.y:
			result.append(Vector3i(origin.x + x_start + dx, origin.y, origin.z + z_start + dz))
	return result


func can_place_ground(coord: Vector3i) -> Dictionary:
	var c := Vector3i(coord.x, 0, coord.z)
	if ground.has(c):
		return {"valid": false, "reason": "That patch is already garden ground."}
	for direction: Vector3i in CARDINALS:
		if ground.has(c + direction):
			return {"valid": true, "reason": ""}
	return {"valid": false, "reason": "Ground must touch the garden along one side."}


func can_remove_ground(coord: Vector3i) -> Dictionary:
	var c := Vector3i(coord.x, 0, coord.z)
	if not ground.has(c):
		return {"valid": false, "reason": "There is no ground there."}
	for occ_coord: Vector3i in occupancy:
		if occ_coord.x == c.x and occ_coord.z == c.z:
			return {"valid": false, "reason": "Move the item resting on this ground first."}
	if ground.size() <= 1:
		return {"valid": false, "reason": "The garden needs at least one patch."}
	var remaining := ground.duplicate()
	remaining.erase(c)
	var start: Vector3i = remaining.keys()[0]
	var reached := _flood_ground(start, remaining)
	if reached.size() != remaining.size():
		return {"valid": false, "reason": "Removing this would split the garden."}
	return {"valid": true, "reason": ""}


func can_place_prop(
		definition: BuildItemDefinition,
		origin: Vector3i,
		rotation_quarters: int,
		ignore_instance: String = ""
	) -> Dictionary:
	if definition == null:
		return {"valid": false, "reason": "This item definition is missing."}
	if origin.y < 1:
		return {"valid": false, "reason": "Props need a garden surface."}
	if origin.y > definition.max_stack_height:
		return {"valid": false, "reason": "That stack is too tall for this item."}
	var cells := footprint_cells(definition, origin, rotation_quarters)
	for cell: Vector3i in cells:
		var occupant := str(occupancy.get(cell, ""))
		if not occupant.is_empty() and occupant != ignore_instance:
			return {"valid": false, "reason": "That space is already occupied."}
		if blocked_cells.has(cell):
			return {"valid": false, "reason": "%s is rooted there." % blocked_cells[cell]}
		var base := Vector3i(cell.x, 0, cell.z)
		if origin.y == 1:
			if not ground.has(base):
				return {"valid": false, "reason": "Every part of the item needs ground."}
			if not ("ground" in definition.valid_support_types):
				return {"valid": false, "reason": "This item cannot rest on ground."}
		else:
			if not ("prop" in definition.valid_support_types):
				return {"valid": false, "reason": "This item cannot be stacked."}
			var below := str(occupancy.get(Vector3i(cell.x, cell.y - 1, cell.z), ""))
			if below.is_empty() or below == ignore_instance:
				return {"valid": false, "reason": "The upper layer needs solid support."}
			var below_state: Dictionary = props.get(below, {})
			var below_def := data.item(StringName(str(below_state.get("definition_id", ""))))
			if below_def == null or not below_def.stackability:
				return {"valid": false, "reason": "The item below cannot support a stack."}
	return {"valid": true, "reason": ""}


func place_ground(definition_id: StringName, coord: Vector3i) -> bool:
	var check := can_place_ground(coord)
	if not bool(check.valid):
		return false
	var c := Vector3i(coord.x, 0, coord.z)
	ground[c] = definition_id
	tile_changed.emit(c)
	grid_changed.emit()
	return true


func add_ground_unchecked(definition_id: StringName, coord: Vector3i) -> void:
	var c := Vector3i(coord.x, 0, coord.z)
	ground[c] = definition_id


func remove_ground(coord: Vector3i) -> StringName:
	var c := Vector3i(coord.x, 0, coord.z)
	var id := StringName(str(ground.get(c, "")))
	if id != &"":
		ground.erase(c)
		tile_changed.emit(c)
		grid_changed.emit()
	return id


func allocate_instance_id() -> String:
	var value := "garden-%06d" % _next_instance_number
	_next_instance_number += 1
	return value


func place_prop(
		definition_id: StringName,
		coord: Vector3i,
		rotation_quarters: int,
		instance_id: String = ""
	) -> String:
	var definition := data.item(definition_id)
	var id := instance_id if not instance_id.is_empty() else allocate_instance_id()
	var check := can_place_prop(definition, coord, rotation_quarters, id)
	if not bool(check.valid):
		return ""
	props[id] = {
		"instance_id": id,
		"definition_id": String(definition_id),
		"coord": [coord.x, coord.y, coord.z],
		"rotation": posmod(rotation_quarters, 4),
	}
	_mark_occupancy(id, definition, coord, rotation_quarters)
	grid_changed.emit()
	return id


func remove_prop(instance_id: String) -> Dictionary:
	var state: Dictionary = props.get(instance_id, {})
	if state.is_empty():
		return {}
	_clear_occupancy(instance_id)
	props.erase(instance_id)
	grid_changed.emit()
	return state.duplicate(true)


func restore_prop(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	var coord := array_to_coord(state.get("coord", [0, 1, 0]))
	return not place_prop(
		StringName(str(state.get("definition_id", ""))),
		coord,
		int(state.get("rotation", 0)),
		str(state.get("instance_id", ""))
	).is_empty()


func state_for(instance_id: String) -> Dictionary:
	return (props.get(instance_id, {}) as Dictionary).duplicate(true)


func top_layer_at(x: int, z: int) -> int:
	var layer := 0
	for coord: Vector3i in occupancy:
		if coord.x == x and coord.z == z:
			layer = maxi(layer, coord.y)
	return layer


func is_walkable(coord: Vector3i) -> bool:
	var ground_coord := Vector3i(coord.x, 0, coord.z)
	if not ground.has(ground_coord):
		return false
	var walk := Vector3i(coord.x, 1, coord.z)
	return not occupancy.has(walk) and not blocked_cells.has(walk)


func walkable_cells() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for coord: Vector3i in ground:
		var walk := Vector3i(coord.x, 1, coord.z)
		if is_walkable(walk):
			result.append(walk)
	return result


func reachable_path(start: Vector3i, goal: Vector3i) -> Array[Vector3i]:
	var clean_start := Vector3i(start.x, 1, start.z)
	var clean_goal := Vector3i(goal.x, 1, goal.z)
	if not is_walkable(clean_start) or not is_walkable(clean_goal):
		return []
	var frontier: Array[Vector3i] = [clean_start]
	var came_from: Dictionary = {clean_start: clean_start}
	while not frontier.is_empty():
		var current: Vector3i = frontier.pop_front()
		if current == clean_goal:
			break
		for direction: Vector3i in CARDINALS:
			var next := Vector3i(current.x + direction.x, 1, current.z + direction.z)
			if not came_from.has(next) and is_walkable(next):
				came_from[next] = current
				frontier.append(next)
	if not came_from.has(clean_goal):
		return []
	var path: Array[Vector3i] = []
	var cursor := clean_goal
	while cursor != clean_start:
		path.push_front(cursor)
		cursor = came_from[cursor]
	path.push_front(clean_start)
	return path


func random_reachable_destination(start: Vector3i, rng: RandomNumberGenerator, reserved: Dictionary = {}) -> Vector3i:
	var candidates := walkable_cells()
	candidates.shuffle()
	for candidate: Vector3i in candidates:
		if reserved.has(candidate):
			continue
		if not reachable_path(start, candidate).is_empty():
			return candidate
	return Vector3i(start.x, 1, start.z)


func snapshot() -> Dictionary:
	var ground_rows: Array = []
	for coord: Vector3i in ground:
		ground_rows.append({
			"definition_id": String(ground[coord]),
			"coord": [coord.x, coord.y, coord.z],
		})
	ground_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.coord) < str(b.coord))
	var prop_rows: Array = []
	for id: String in props:
		prop_rows.append((props[id] as Dictionary).duplicate(true))
	prop_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.instance_id) < str(b.instance_id))
	return {
		"ground": ground_rows,
		"props": prop_rows,
		"next_instance_number": _next_instance_number,
	}


func restore_snapshot(state: Dictionary, missing_ids: Array[String] = []) -> void:
	ground.clear()
	props.clear()
	occupancy.clear()
	for row: Variant in state.get("ground", []):
		var id := StringName(str(row.get("definition_id", "")))
		if data.item(id) == null or not data.item(id).is_ground():
			missing_ids.append(String(id))
			continue
		add_ground_unchecked(id, array_to_coord(row.get("coord", [0, 0, 0])))
	for row: Variant in state.get("props", []):
		var id := StringName(str(row.get("definition_id", "")))
		if data.item(id) == null:
			missing_ids.append(String(id))
			continue
		if not restore_prop(row):
			push_warning("Skipped invalid placed item %s during load." % id)
	_next_instance_number = maxi(1, int(state.get("next_instance_number", _derive_next_instance_number())))
	grid_changed.emit()


func _mark_occupancy(
		instance_id: String,
		definition: BuildItemDefinition,
		coord: Vector3i,
		rotation_quarters: int
	) -> void:
	for cell: Vector3i in footprint_cells(definition, coord, rotation_quarters):
		occupancy[cell] = instance_id


func _clear_occupancy(instance_id: String) -> void:
	var keys := occupancy.keys()
	for cell: Vector3i in keys:
		if str(occupancy[cell]) == instance_id:
			occupancy.erase(cell)


func _derive_next_instance_number() -> int:
	var highest := 0
	for id: String in props:
		if id.begins_with("garden-"):
			highest = maxi(highest, int(id.trim_prefix("garden-")))
	return highest + 1


static func array_to_coord(value: Variant) -> Vector3i:
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO


static func _flood_ground(start: Vector3i, available: Dictionary) -> Dictionary:
	var visited: Dictionary = {start: true}
	var queue: Array[Vector3i] = [start]
	while not queue.is_empty():
		var current: Vector3i = queue.pop_front()
		for direction: Vector3i in CARDINALS:
			var next := current + direction
			if available.has(next) and not visited.has(next):
				visited[next] = true
				queue.append(next)
	return visited
