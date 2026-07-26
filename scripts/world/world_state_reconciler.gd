class_name WorldStateReconciler
extends RefCounted
## Deterministic post-load repair for world invariants.
##
## Saves are migrated structurally before hydration. This pass then validates
## relationships that only the live grid can know about. Invalid pieces are
## returned to stock; player-owned content is never silently deleted.

var registries: Registries


func _init(definition_registries: Registries) -> void:
	registries = definition_registries


func reconcile(grid: WorldGrid, stock: StockManager) -> Dictionary:
	var warnings := PackedStringArray()
	var changed := false
	changed = _repair_elevation_columns(grid, stock, warnings) or changed
	changed = _repair_structures(grid, stock, warnings) or changed
	changed = _repair_home_cell(grid, warnings) or changed
	return {"changed": changed, "warnings": warnings}


func _repair_elevation_columns(
	grid: WorldGrid,
	stock: StockManager,
	warnings: PackedStringArray
) -> bool:
	var changed := false
	var keys: Array = grid.stacked_cells.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		if a.x != b.x:
			return a.x < b.x
		return a.z < b.z
	)
	for key: Vector3i in keys:
		if not grid.stacked_cells.has(key):
			continue
		var coord := Vector2i(key.x, key.z)
		var state: WorldGrid.CellState = grid.stacked_cells[key]
		var invalid := (
			key.y < 1
			or key.y > grid.max_stack_elevation
			or not grid.has_cell_at(coord, key.y - 1)
		)
		if not invalid:
			continue
		grid.stacked_cells.erase(key)
		_rehome_cell(state, stock)
		warnings.append(
			"returned unsupported tile '%s' at (%d,%d), elevation %d to storage"
			% [state.tile_id, coord.x, coord.y, key.y]
		)
		changed = true
	return changed


func _repair_structures(
	grid: WorldGrid,
	stock: StockManager,
	warnings: PackedStringArray
) -> bool:
	var changed := false
	var used_instance_ids := {}
	var next_id := maxi(1, grid.next_instance_id)
	for slot: Dictionary in grid.all_cell_slots():
		var coord: Vector2i = slot["coord"]
		var elevation := int(slot["elevation"])
		var state: WorldGrid.CellState = slot["state"]
		var tile_def := registries.tile(state.tile_id)
		if tile_def == null:
			tile_def = registries.ensure_compatibility_definition("tiles", state.tile_id)
			changed = true
		var normalized_tile_rotation := posmod(state.rotation, 4)
		if normalized_tile_rotation != state.rotation:
			state.rotation = normalized_tile_rotation
			changed = true
		var accepted: Array[WorldGrid.StructureState] = []
		var occupied := {}
		for structure: WorldGrid.StructureState in state.structures:
			var def := registries.structure(structure.structure_id)
			if def == null:
				def = registries.ensure_compatibility_definition(
					"structures",
					structure.structure_id
				)
				changed = true
			var normalized_structure_rotation := posmod(structure.rotation, 4)
			if normalized_structure_rotation != structure.rotation:
				structure.rotation = normalized_structure_rotation
				changed = true
			var socket := _compatible_socket(
				tile_def,
				def,
				structure.socket_index,
				elevation,
				occupied
			)
			if socket < 0:
				stock.add_structure(structure.structure_id)
				warnings.append(
					"returned '%s' from (%d,%d), elevation %d to storage because its socket is no longer valid"
					% [structure.structure_id, coord.x, coord.y, elevation]
				)
				changed = true
				continue
			if socket != structure.socket_index:
				structure.socket_index = socket
				changed = true
			occupied[socket] = true
			if structure.instance_id <= 0 or used_instance_ids.has(structure.instance_id):
				while used_instance_ids.has(next_id):
					next_id += 1
				structure.instance_id = next_id
				next_id += 1
				changed = true
			used_instance_ids[structure.instance_id] = true
			next_id = maxi(next_id, structure.instance_id + 1)
			accepted.append(structure)
		if accepted.size() != state.structures.size():
			state.structures.assign(accepted)
	if grid.next_instance_id != next_id:
		grid.next_instance_id = next_id
		changed = true
	return changed


func _compatible_socket(
	tile_def: Defs.TileDefinition,
	structure_def: Defs.StructureDefinition,
	requested: int,
	elevation: int,
	occupied: Dictionary
) -> int:
	if (
		tile_def == null
		or structure_def == null
		or not tile_def.supports_decor
		or (elevation > 0 and not structure_def.allow_elevated)
	):
		return -1
	if structure_def.socket_type == "structure":
		return 0 if tile_def.structure_sockets > 0 and not occupied.has(0) else -1
	if requested >= 1 and requested <= tile_def.decor_sockets and not occupied.has(requested):
		return requested
	for socket in range(1, tile_def.decor_sockets + 1):
		if not occupied.has(socket):
			return socket
	return -1


func _repair_home_cell(grid: WorldGrid, warnings: PackedStringArray) -> bool:
	if grid.has_cell(grid.home_cell) and grid.is_walkable(grid.home_cell):
		return false
	var previous_home := grid.home_cell
	var candidates: Array[Vector2i] = []
	for coord: Vector2i in grid.cells:
		if grid.is_walkable(coord):
			candidates.append(coord)
	if candidates.is_empty():
		for coord: Vector2i in grid.cells:
			candidates.append(coord)
	if candidates.is_empty():
		grid.home_cell = Vector2i.ZERO
		return false
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var distance_a := absi(a.x - previous_home.x) + absi(a.y - previous_home.y)
		var distance_b := absi(b.x - previous_home.x) + absi(b.y - previous_home.y)
		if distance_a != distance_b:
			return distance_a < distance_b
		return a.y < b.y if a.x == b.x else a.x < b.x
	)
	grid.home_cell = candidates[0]
	warnings.append("moved the home cell to the nearest valid saved land")
	return true


func _rehome_cell(state: WorldGrid.CellState, stock: StockManager) -> void:
	if state.landmark_id == "":
		stock.add_tile(state.tile_id)
	for structure: WorldGrid.StructureState in state.structures:
		stock.add_structure(structure.structure_id)
