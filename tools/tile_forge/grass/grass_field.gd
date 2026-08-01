@tool
class_name GrassField
extends RefCounted
## Builds a connected grass region as CONTINUOUS CHUNK MESHES.
##
## The failure this replaces: one visible cap per logical cell. However well the
## foliage read, the ground underneath was 25 flat squares, and every seam,
## bevel and ambient-occlusion crack drew the gameplay grid back onto the
## screen. Colour tricks cannot hide that — the geometry has to stop being
## per-tile.
##
## So the logical grid keeps placement, saving, collision, ownership and terrain
## type, and contributes exactly one thing to rendering: which cells are grass.
## Everything visible is evaluated in WORLD SPACE and built per chunk:
##
##   * one surface mesh per chunk, vertices SHARED across internal cell
##     boundaries, so an internal edge has no gap, no bevel, no vertical face,
##     no colour change and nothing for ambient occlusion to catch;
##   * height, tone and vegetation density are continuous functions of world
##     position, so they cross cell and chunk boundaries without a seam and
##     never restart at a tile origin;
##   * skirts only where the region genuinely ends.
##
## Two neighbouring chunks agree because they sample the same functions at the
## same world coordinates — not because their edges were stitched afterwards.

const CELL := 1.35
## Surface samples per cell edge. Eight gives ~0.17 m spacing: fine enough for
## broad swells, coarse enough that a 5x5 region stays about 3k triangles.
const SAMPLES_PER_CELL := 8
## Cells per render chunk. Chunks are the culling unit, so they stay local
## rather than one mesh for the whole world.
const CHUNK_CELLS := 5

## Terrain tones. Three closely related greens, at most ~9% apart in value, so
## the ground has rhythm without ever reading as patches.
const TONE_DARK := Color("#5F7C36")
const TONE_LIGHT := Color("#8CAA55")
## The exposed side sits only ~12% under the top — never near-black.
const SIDE_TONE := Color("#4E682D")
const SIDE_HEIGHT := 0.27
const EDGE_BEVEL := 0.045


class Region:
	extends RefCounted
	## One connected set of grass cells plus the deterministic world-space
	## fields derived from it. Centres are seeded from the region, not from any
	## tile, which is what stops the composition repeating per cell.
	var cells: Dictionary = {}
	var swells: Array[Vector3] = []      # x, z, radius
	var swell_heights: PackedFloat32Array = PackedFloat32Array()
	var tone_blobs: Array[Vector3] = []
	var tone_weights: PackedFloat32Array = PackedFloat32Array()
	var density_blobs: Array[Vector3] = []
	var density_weights: PackedFloat32Array = PackedFloat32Array()

	func has(cell: Vector2i) -> bool:
		return cells.has(cell)


## Smooth radial falloff. Low-frequency analytic forms only — no noise anywhere
## in this file, because noise is what turns broad sculpting into bumpiness.
static func smooth_blob(point: Vector2, centre: Vector2, radius: float) -> float:
	var normalized := point.distance_to(centre) / maxf(radius, 0.001)
	if normalized >= 1.0:
		return 0.0
	var t := 1.0 - normalized
	return t * t * (3.0 - 2.0 * t)


## Lays out a region's swells, tone blobs and vegetation patches across the
## whole footprint. Radii are large relative to a cell on purpose: a form must
## span several cells or it will read as belonging to one.
static func build_region(cells: Array, seed_value: int) -> Region:
	var region := Region.new()
	for cell: Vector2i in cells:
		region.cells[cell] = true

	var bounds := _cell_bounds(cells)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# 3-5 broad swells and 2-3 shallow hollows over a 5x5 area, scaled with the
	# region so a larger island gets more rather than bigger forms.
	var area := maxf(bounds.size.x * bounds.size.y, 1.0)
	var swell_count := clampi(int(round(area / 6.0)) + 3, 3, 9)
	for index in swell_count:
		var point := _random_in(bounds, rng)
		region.swells.append(Vector3(point.x, point.y, rng.randf_range(1.20, 2.80)))
		region.swell_heights.append(rng.randf_range(0.045, 0.095))
	# One hero swell allowed to reach a little higher than the rest.
	if region.swell_heights.size() > 0:
		region.swell_heights[0] = rng.randf_range(0.105, 0.135)
	var hollow_count := clampi(int(round(area / 9.0)) + 2, 2, 6)
	for index in hollow_count:
		var point := _random_in(bounds, rng)
		region.swells.append(Vector3(point.x, point.y, rng.randf_range(1.05, 1.60)))
		region.swell_heights.append(-rng.randf_range(0.026, 0.052))

	for index in clampi(int(round(area / 5.0)) + 3, 3, 10):
		var point := _random_in(bounds, rng)
		region.tone_blobs.append(Vector3(point.x, point.y, rng.randf_range(1.20, 3.00)))
		region.tone_weights.append(rng.randf_range(-0.34, 0.40))

	# 6-10 broad vegetation regions across a 5x5 area. Some overlap, some cells
	# fall between them and stay open — density is a property of the field, not
	# of a tile.
	# 6-10 broad patches, biased AWAY from the perimeter. Sampling the full
	# rectangle put most centres near the edges, which drew a ring of grass
	# around an empty middle — the opposite of a composed field.
	var inner := bounds.grow(-minf(bounds.size.x, bounds.size.y) * 0.22)
	for index in clampi(int(round(area / 5.5)) + 3, 6, 10):
		var point := _random_in(inner, rng)
		region.density_blobs.append(Vector3(point.x, point.y, rng.randf_range(0.62, 1.30)))
		region.density_weights.append(rng.randf_range(0.70, 1.0))
	return region


static func _cell_bounds(cells: Array) -> Rect2:
	if cells.is_empty():
		return Rect2(Vector2.ZERO, Vector2(CELL, CELL))
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for cell: Vector2i in cells:
		var centre := Vector2(float(cell.x) * CELL, float(cell.y) * CELL)
		low = low.min(centre - Vector2(CELL, CELL) * 0.5)
		high = high.max(centre + Vector2(CELL, CELL) * 0.5)
	return Rect2(low, high - low)


static func _random_in(bounds: Rect2, rng: RandomNumberGenerator) -> Vector2:
	return Vector2(
		rng.randf_range(bounds.position.x, bounds.end.x),
		rng.randf_range(bounds.position.y, bounds.end.y)
	)


## Terrain height at a world XZ. Continuous everywhere, so two chunks sampling
## the same coordinate get the same answer and their edges cannot disagree.
static func height_at(region: Region, world: Vector2) -> float:
	var height := 0.0
	for index in region.swells.size():
		var blob := region.swells[index]
		height += region.swell_heights[index] * smooth_blob(
			world, Vector2(blob.x, blob.y), blob.z
		)
	return height


## Broad ground tone in 0..1. Large soft regions 1.2-3.0 m across, never aligned
## to a cell and never per-vertex.
static func tone_at(region: Region, world: Vector2) -> float:
	var tone := 0.48
	for index in region.tone_blobs.size():
		var blob := region.tone_blobs[index]
		tone += region.tone_weights[index] * smooth_blob(
			world, Vector2(blob.x, blob.y), blob.z
		)
	return clampf(tone, 0.0, 1.0)


static func density_at(region: Region, world: Vector2) -> float:
	var density := 0.0
	for index in region.density_blobs.size():
		var blob := region.density_blobs[index]
		density = maxf(density, region.density_weights[index] * smooth_blob(
			world, Vector2(blob.x, blob.y), blob.z
		))
	return clampf(density, 0.0, 1.0)


# --- surface ----------------------------------------------------------------


## One continuous mesh for the cells in `chunk_cells`.
##
## Vertices are keyed by their integer sample coordinate, so a sample on a cell
## boundary is created ONCE and shared by the quads on both sides. That single
## property is what removes the internal seam: there is no second vertex to
## drift, no second normal to disagree, and no crack for ambient occlusion.
static func build_surface(region: Region, chunk_cells: Array) -> ArrayMesh:
	if chunk_cells.is_empty():
		return null
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var lookup: Dictionary = {}

	for cell: Vector2i in chunk_cells:
		for row in SAMPLES_PER_CELL:
			for column in SAMPLES_PER_CELL:
				var a := _vertex(region, cell, column, row, lookup, vertices, normals, colours)
				var b := _vertex(region, cell, column + 1, row, lookup, vertices, normals, colours)
				var c := _vertex(region, cell, column + 1, row + 1, lookup, vertices, normals, colours)
				var d := _vertex(region, cell, column, row + 1, lookup, vertices, normals, colours)
				# Winding matters: the engine's front face for an upward quad is
				# a->b->c, and the reverse order culls the whole surface while the
				# skirt still draws — which looks like a missing mesh, not a flip.
				indices.append_array([a, b, c, a, c, d])

	if vertices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Global sample index, so the same world position always resolves to the same
## vertex regardless of which cell asked for it.
static func _vertex(
	region: Region,
	cell: Vector2i,
	column: int,
	row: int,
	lookup: Dictionary,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colours: PackedColorArray
) -> int:
	var key := Vector2i(
		cell.x * SAMPLES_PER_CELL + column,
		cell.y * SAMPLES_PER_CELL + row
	)
	if lookup.has(key):
		return lookup[key]
	var step := CELL / float(SAMPLES_PER_CELL)
	var world := Vector2(
		float(key.x) * step - CELL * 0.5,
		float(key.y) * step - CELL * 0.5
	)
	var index := vertices.size()
	vertices.append(Vector3(world.x, height_at(region, world), world.y))
	normals.append(normal_at(region, world, step))
	colours.append(TONE_DARK.lerp(TONE_LIGHT, tone_at(region, world)))
	lookup[key] = index
	return index


## Normals come from the continuous height function rather than from face
## averaging, so a vertex on a chunk boundary gets an identical normal in both
## chunks and the join cannot show as a shading line.
static func normal_at(region: Region, world: Vector2, step: float) -> Vector3:
	var dx := height_at(region, world + Vector2(step, 0.0)) \
		- height_at(region, world - Vector2(step, 0.0))
	var dz := height_at(region, world + Vector2(0.0, step)) \
		- height_at(region, world - Vector2(0.0, step))
	return Vector3(-dx, 2.0 * step, -dz).normalized()


## Vertical skirt around genuinely exposed edges only. An internal boundary
## between two grass cells never reaches this function.
static func build_skirt(region: Region) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var step := CELL / float(SAMPLES_PER_CELL)
	var directions := {
		Vector2i(0, -1): Vector2(0.0, -1.0),
		Vector2i(1, 0): Vector2(1.0, 0.0),
		Vector2i(0, 1): Vector2(0.0, 1.0),
		Vector2i(-1, 0): Vector2(-1.0, 0.0),
	}

	for cell: Vector2i in region.cells:
		for offset: Vector2i in directions:
			if region.has(cell + offset):
				continue
			var outward: Vector2 = directions[offset]
			var along := Vector2(-outward.y, outward.x)
			var centre := Vector2(float(cell.x) * CELL, float(cell.y) * CELL)
			var edge_centre := centre + outward * (CELL * 0.5)
			for sample in SAMPLES_PER_CELL:
				var t0 := (float(sample) / SAMPLES_PER_CELL - 0.5) * CELL
				var t1 := (float(sample + 1) / SAMPLES_PER_CELL - 0.5) * CELL
				var p0 := edge_centre + along * t0
				var p1 := edge_centre + along * t1
				var h0 := height_at(region, p0)
				var h1 := height_at(region, p1)
				# A small lip on the exposed rim only. Connected edges are
				# untouched, which is the whole point.
				var l0 := p0 - outward * EDGE_BEVEL
				var l1 := p1 - outward * EDGE_BEVEL
				_wall_quad(vertices, normals, colours,
					Vector3(l0.x, h0, l0.y), Vector3(l1.x, h1, l1.y),
					Vector3(p1.x, h1 - EDGE_BEVEL, p1.y),
					Vector3(p0.x, h0 - EDGE_BEVEL, p0.y), outward, 0.55)
				_wall_quad(vertices, normals, colours,
					Vector3(p0.x, h0 - EDGE_BEVEL, p0.y),
					Vector3(p1.x, h1 - EDGE_BEVEL, p1.y),
					Vector3(p1.x, -SIDE_HEIGHT, p1.y),
					Vector3(p0.x, -SIDE_HEIGHT, p0.y), outward, 1.0)
	if vertices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _wall_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colours: PackedColorArray,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	outward: Vector2,
	shade: float
) -> void:
	var normal := Vector3(outward.x, 0.0, outward.y)
	var colour := TONE_DARK.lerp(SIDE_TONE, shade)
	for point in [a, b, c, a, c, d]:
		vertices.append(point)
		normals.append(normal)
		colours.append(colour)


# --- world-space field composition ------------------------------------------
#
# Placement is sampled across the whole region on one jittered lattice and
# accepted against the density field. Nothing restarts at a cell boundary and
# no cell has its own seed, so a lush area can span four tiles and the tile
# beside it can be almost bare — which is what stops every cell looking like it
# contains the same arrangement.

enum Layer { GROUND, CARPET, MEDIUM, ACCENT }

## Lattice pitch in metres. Roughly half a ground-mat width, so accepted
## candidates overlap into continuous mats rather than dotting the surface.
const PLACE_PITCH := 0.21


static func place_foliage(region: Region, seed_value: int) -> Array:
	## Hundreds of small pieces read as confetti no matter how good each piece
	## is. So placement now works PATCH FIRST: every density blob becomes a
	## broad overlapping mat group, and only inside those groups do medium tufts
	## appear. Three scales exist and nothing else — large mats, medium tufts,
	## rare accents — so there is never a lone speck to notice.
	var result: Array = []
	if region.cells.is_empty():
		return result
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	for index in region.density_blobs.size():
		var blob := region.density_blobs[index]
		var centre := Vector2(blob.x, blob.y)
		var radius: float = blob.z
		var weight := region.density_weights[index]

		# Large mats form the body of the patch: a handful of very broad pieces
		# overlapping by roughly half their footprint.
		var mats := clampi(int(round(radius * 4.2 * weight)), 3, 9)
		for member in mats:
			var angle := rng.randf() * TAU
			var reach := radius * sqrt(rng.randf()) * 0.86
			var world := centre + Vector2(cos(angle), sin(angle)) * reach
			var mat_scale := rng.randf_range(1.70, 2.35)
			if not _inside(region, world, 0.22 * mat_scale):
				continue
			result.append({
				"layer": Layer.GROUND,
				"position": Vector3(world.x, height_at(region, world), world.y),
				"yaw": rng.randf() * TAU,
				"scale": mat_scale,
			})

		# Medium tufts read as the focal forms sitting on the mats.
		var tufts := clampi(int(round(radius * 2.1 * weight)), 2, 6)
		for member in tufts:
			var angle := rng.randf() * TAU
			var reach := radius * sqrt(rng.randf()) * 0.70
			var world := centre + Vector2(cos(angle), sin(angle)) * reach
			var tuft_scale := rng.randf_range(1.55, 2.05)
			if not _inside(region, world, 0.16 * tuft_scale):
				continue
			result.append({
				"layer": Layer.MEDIUM,
				"position": Vector3(world.x, height_at(region, world), world.y),
				"yaw": rng.randf() * TAU,
				"scale": tuft_scale,
			})

		# At most one accent per patch, and only in the strongest ones.
		if weight > 0.86 and rng.randf() < 0.55:
			var angle := rng.randf() * TAU
			var world := centre + Vector2(cos(angle), sin(angle)) * radius * 0.45
			if _inside(region, world, 0.17 * 1.7):
				result.append({
					"layer": Layer.ACCENT,
					"position": Vector3(world.x, height_at(region, world), world.y),
					"yaw": rng.randf() * TAU,
					"scale": rng.randf_range(1.30, 1.70),
				})
	return result


static func _inside(region: Region, world: Vector2, reach := 0.0) -> bool:
	## `reach` is the placed piece's half-footprint. Testing only the origin let
	## a large mat near the rim hang its lobes over the void, so every corner of
	## the footprint has to land on an occupied cell too.
	for offset: Vector2 in [
		Vector2.ZERO,
		Vector2(reach, 0.0), Vector2(-reach, 0.0),
		Vector2(0.0, reach), Vector2(0.0, -reach),
		Vector2(reach, reach) * 0.71, Vector2(-reach, reach) * 0.71,
		Vector2(reach, -reach) * 0.71, Vector2(-reach, -reach) * 0.71,
	]:
		var point := world + offset
		var cell := Vector2i(
			int(floor(point.x / CELL + 0.5)), int(floor(point.y / CELL + 0.5))
		)
		if not region.has(cell):
			return false
	return true


## Fringe along genuinely exposed edges only, and only on part of them. A fully
## decorated perimeter reads as a border; leaving stretches clean is what makes
## the island feel crafted rather than trimmed.
static func place_fringe(region: Region, seed_value: int) -> Array:
	var result: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var directions := {
		Vector2i(0, -1): Vector2(0.0, -1.0),
		Vector2i(1, 0): Vector2(1.0, 0.0),
		Vector2i(0, 1): Vector2(0.0, 1.0),
		Vector2i(-1, 0): Vector2(-1.0, 0.0),
	}
	for cell: Vector2i in region.cells:
		for offset: Vector2i in directions:
			if region.has(cell + offset):
				continue
			# Roughly half the exposed perimeter carries fringe.
			if rng.randf() > 0.55:
				continue
			var outward: Vector2 = directions[offset]
			var along := Vector2(-outward.y, outward.x)
			var centre := Vector2(float(cell.x) * CELL, float(cell.y) * CELL)
			var edge := centre + outward * (CELL * 0.5)
			for index in rng.randi_range(1, 2):
				var t := rng.randf_range(-0.44, 0.44) * CELL
				var point := edge + along * t - outward * rng.randf_range(0.20, 0.34)
				result.append({
					"layer": Layer.GROUND if rng.randf() < 0.65 else Layer.CARPET,
					"position": Vector3(point.x, height_at(region, point), point.y),
					# Leaning slightly outward so a few lobes break the rim line.
					"yaw": atan2(outward.y, outward.x) + rng.randf_range(-0.7, 0.7),
					"scale": rng.randf_range(1.45, 1.90),
				})
	return result
