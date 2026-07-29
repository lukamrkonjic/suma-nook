class_name DebugWorldBuilder
extends RefCounted
## Deterministic, save-independent stress-world population. It writes the
## authoritative WorldGrid data in bulk, matching the cost of loading a large
## save instead of deliberately paying thousands of editor-style signals.

const DEFAULT_TILE_COUNT := 5000
const DEFAULT_MODEL_COUNT := 1250
const MAXED_TILE_COUNT := 10000
const MAXED_MODEL_COUNT := 10000
const DEFAULT_SEED := 8675309
const BIOME_PATCH_SIZE := 8


static func populate(
	core: GameCore,
	tile_count := DEFAULT_TILE_COUNT,
	model_count := DEFAULT_MODEL_COUNT,
	seed_value := DEFAULT_SEED
) -> Dictionary:
	var grid := core.grid
	var tile_ids: Array[String] = []
	# The stress world intentionally includes the entire loaded catalog, not
	# only the progression roster, so retired/testable tile render paths cannot
	# hide from performance testing.
	for tile_id: String in core.registries.tiles:
		tile_ids.append(tile_id)
	tile_ids.sort()
	var structure_ids: Array[String] = []
	for structure_id: String in core.registries.structures:
		structure_ids.append(structure_id)
	structure_ids.sort()
	if tile_ids.is_empty():
		return {}

	tile_count = maxi(tile_count, tile_ids.size())
	model_count = clampi(
		maxi(model_count, structure_ids.size()),
		0,
		tile_count
	)
	grid.cells.clear()
	grid.stacked_cells.clear()
	grid.next_instance_id = 1
	grid.home_cell = Vector2i.ZERO
	core.landmarks.active.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var side := ceili(sqrt(float(tile_count)))
	var start := -side / 2
	var coords: Array[Vector2i] = []
	for index in tile_count:
		var local_x := index % side
		var local_y := index / side
		var coord := Vector2i(start + local_x, start + local_y)
		coords.append(coord)
		var chunk := Vector2i(
			floori(float(coord.x) / BIOME_PATCH_SIZE),
			floori(float(coord.y) / BIOME_PATCH_SIZE)
		)
		var patch_hash := absi(
			chunk.x * 92837111
			+ chunk.y * 689287499
			+ seed_value * 31
		)
		var tile_index := patch_hash % tile_ids.size()
		# Mostly coherent biome patches, with enough variation to exercise
		# every material transition and tile batch.
		if rng.randf() < 0.12:
			tile_index = rng.randi_range(0, tile_ids.size() - 1)
		if index < tile_ids.size():
			tile_index = index
		var state := WorldGrid.CellState.new()
		state.tile_id = tile_ids[tile_index]
		state.rotation = rng.randi_range(0, 3)
		grid.cells[coord] = state

	# Guarantee a safe, current grass patch under the latest character without
	# disturbing the all-tile guarantee strip at the far edge.
	var safe_tile := "tile_grass" if tile_ids.has("tile_grass") else tile_ids[0]
	for y in range(-4, 5):
		for x in range(-4, 5):
			var coord := Vector2i(x, y)
			var state := grid.cell(coord)
			if state != null:
				state.tile_id = safe_tile
				state.rotation = 0

	var outer_coords: Array[Vector2i] = []
	var spawn_coords: Array[Vector2i] = []
	for coord: Vector2i in coords:
		if absi(coord.x) <= 2 and absi(coord.y) <= 2:
			spawn_coords.append(coord)
		else:
			outer_coords.append(coord)
	_shuffle_coords(outer_coords, rng)
	_shuffle_coords(spawn_coords, rng)
	var model_coords: Array[Vector2i] = []
	model_coords.append_array(outer_coords)
	model_coords.append_array(spawn_coords)
	for index in model_count:
		# Sparse stress worlds fill the outer cells first, preserving a clear
		# spawn. At maximum density the final 25 entries deliberately fill that
		# area too, guaranteeing exactly one model on every tile.
		var coord := model_coords[index]
		var structure_id := structure_ids[index % structure_ids.size()]
		if (
			model_count == tile_count
			and coord == Vector2i.ZERO
			and structure_ids.has("struct_pot")
		):
			# Preserve a usable player spawn without weakening the density
			# contract: the small pot still occupies the center tile, but sits
			# on a decor socket away from its walkable center.
			structure_id = "struct_pot"
		var definition := core.registries.structure(structure_id)
		var structure := WorldGrid.StructureState.new()
		structure.instance_id = grid.next_instance_id
		grid.next_instance_id += 1
		structure.structure_id = structure_id
		structure.socket_index = (
			0
			if definition != null and definition.socket_type == "structure"
			else 1 + (index % 4)
		)
		structure.rotation = rng.randi_range(0, 3)
		grid.cell(coord).structures.append(structure)

	grid.rebuild_structure_index()
	core._rebuild_resting_anchors()
	core.profile.position = grid.cell_to_world(Vector2i.ZERO)
	core.profile.facing = 0.0
	return {
		"tiles": tile_count,
		"models": model_count,
		"tile_types": tile_ids.size(),
		"model_types": structure_ids.size(),
		"models_on_every_tile": model_count == tile_count,
		"side": side,
		"seed": seed_value,
	}


static func _shuffle_coords(
	coords: Array[Vector2i],
	rng: RandomNumberGenerator
) -> void:
	for index in range(coords.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := coords[index]
		coords[index] = coords[swap_index]
		coords[swap_index] = held
