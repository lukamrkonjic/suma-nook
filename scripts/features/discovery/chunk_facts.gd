class_name ChunkFacts
extends RefCounted
## Read-only chunk queries shared by discovery listeners. Facts are derived
## from world truth (tile defs, structure defs, capabilities) — never from
## content-ID branches — so every future tile/model participates by
## declaring tags and capabilities.


## True when any cell of the chunk carries `tag` — on the tile definition
## (with a "water" surface-kind fallback for legacy tiles) or on any placed
## structure's placement tags. `exclude_cell` lets a listener ask about the
## chunk as it was *before* the triggering change.
static func chunk_has_tag(
	grid: WorldGrid,
	world: NookWorld,
	chunk: Vector2i,
	tag: String,
	exclude_cell := Vector2i(2147483647, 2147483647)
) -> bool:
	var origin := world.chunk_origin(chunk)
	var size := world.nook_size
	for y in size:
		for x in size:
			var cell := origin + Vector2i(x, y)
			if cell == exclude_cell:
				continue
			var elevation := grid.top_elevation(cell)
			if elevation < 0:
				continue
			var tile := grid.tile_def_at(cell, elevation)
			if tile != null:
				if tile.traits.has_tag(tag):
					return true
				if tag == "water" and tile.surface_kind == "water":
					return true
			var state := grid.cell_at(cell, elevation)
			if state == null:
				continue
			for structure: WorldGrid.StructureState in state.structures:
				var definition := grid.registries.structure(
					structure.structure_id
				)
				if definition != null and definition.placement_tags.has(tag):
					return true
	return false


## True when any structure in the chunk has the given capability (for
## example "light" — the warm-glow fact behind keepsake co-occurrence).
static func chunk_has_capability(
	grid: WorldGrid, world: NookWorld, chunk: Vector2i, capability: String
) -> bool:
	var origin := world.chunk_origin(chunk)
	var size := world.nook_size
	for y in size:
		for x in size:
			var cell := origin + Vector2i(x, y)
			var elevation := grid.top_elevation(cell)
			if elevation < 0:
				continue
			var state := grid.cell_at(cell, elevation)
			if state == null:
				continue
			for structure: WorldGrid.StructureState in state.structures:
				var definition := grid.registries.structure(
					structure.structure_id
				)
				if definition != null and definition.has_capability(capability):
					return true
	return false
