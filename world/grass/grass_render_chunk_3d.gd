@tool
class_name GrassRenderChunk3D
extends Node3D
## One render chunk of the continuous grass carpet.
##
## A chunk is a CULLING AND REBUILD unit, not an art unit. Nothing about where
## its boundaries fall may be visible: it draws one continuous ArrayMesh whose
## every vertex is evaluated from world-space functions, so two neighbouring
## chunks agree about the shared edge because they sampled the same function at
## the same coordinate — not because anyone stitched them afterwards. The
## logical 1.35 m gameplay grid is likewise invisible here; cells decide only
## WHICH ground exists, never how it is drawn.
##
## Structure built under this node:
##
##   SurfaceMesh        one continuous ArrayMesh (vertex/normal/colour/index)
##   ExposedEdgeSkirt   generated ONLY where the region meets the void
##   DenseCarpet_A/B/C  MultiMesh plush micro-tufts — the carpet itself
##   FlexibleTufts_A/B  MultiMesh taller tufts — the visible wind
##   StaticBody3D       one chunk-level collider, never per-tuft collision
##   Debug              chunk bounds, drawn only when asked
##
## Three traps are worth naming because each one has already cost a rebuild:
##
## WINDING. The engine's front face for an upward quad is a->b->c. The reverse
## order backface-culls the entire surface while the skirt keeps drawing, which
## on screen looks like a missing mesh rather than a flipped one.
##
## SHARED VERTICES. Boundary samples are keyed by GLOBAL sample coordinate, so a
## vertex on a cell or chunk edge is created once and reused. Duplicate vertices
## are what let position, normal and colour drift apart and draw the grid back.
##
## NORMALS FROM THE FIELD. Normals come from finite differences of the height
## function, never from face averaging. A face-averaged normal at a chunk border
## only knows that chunk's triangles, so the two sides disagree and the join
## shows as a shading line even when the positions match perfectly.

enum DetailState {
	NEAR, ## Full carpet, full flexible layer.
	MID,  ## Thinned carpet, sparse flexible layer.
	FAR,  ## Surface mesh only.
}

## Finite-difference step for surface normals, in metres. A world-space
## constant, which is what makes the normal seam-free: both chunks sampling a
## shared boundary vertex step the same distance to the same neighbours and get
## bit-identical results. Small enough to keep the swells crisp.
const NORMAL_SAMPLE_DISTANCE := 0.045

## Cardinal neighbours in cell space, in the order used for corner pairing
## below (each entry is adjacent to the next, wrapping).
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]

## Shared across every chunk so the whole field is one material and one batch.
## Per-chunk materials would multiply draw calls by chunk count for no visual
## gain whatsoever.
static var _surface_material: ShaderMaterial
static var _tuft_material: ShaderMaterial


@export var profile: GrassFieldProfile:
	set(value):
		profile = value
		_request_rebuild()

## Which chunk of the field this is. Only ever set by GrassFieldManager; it
## decides the node's world anchor and which cells belong here.
@export var chunk_coord := Vector2i.ZERO:
	set(value):
		chunk_coord = value
		_request_rebuild()

@export_group("Editor Actions")
@export var rebuild_surface_action := false:
	set(value):
		if value:
			rebuild_surface()
		rebuild_surface_action = false
@export var rebuild_grass_action := false:
	set(value):
		if value:
			rebuild_grass()
		rebuild_grass_action = false
@export var rebuild_all_action := false:
	set(value):
		if value:
			rebuild_all()
		rebuild_all_action = false
@export var randomize_seed_action := false:
	set(value):
		if value and profile != null:
			profile.random_seed = randi() % 100000
			rebuild_all()
		randomize_seed_action = false

@export_group("Debug View")
@export var show_surface_only := false:
	set(value):
		show_surface_only = value
		_apply_visibility()
@export var show_dense_carpet_only := false:
	set(value):
		show_dense_carpet_only = value
		_apply_visibility()
@export var show_flexible_tufts_only := false:
	set(value):
		show_flexible_tufts_only = value
		_apply_visibility()
@export var show_chunk_bounds := false:
	set(value):
		show_chunk_bounds = value
		_apply_visibility()
@export var show_clearance := false:
	set(value):
		show_clearance = value
		_apply_visibility()


## Every grass cell in the whole connected region, not just this chunk's. The
## skirt has to ask "is my neighbour grass?" about cells that belong to the NEXT
## chunk, and answering that wrong is exactly how a wall appears in the middle
## of a lawn.
var _region_cells: Dictionary = {}
## This chunk's own cells, the only ones it draws.
var _cells: Array[Vector2i] = []
## Snapshots of GrassClearance3D markers: {position: Vector2, radius: float,
## retain: float, softness: float}. Snapshotted rather than queried live so a
## density pass can run thousands of samples without touching the scene tree.
var _clearances: Array[Dictionary] = []

var _origin := Vector2.ZERO
var _height_noise: FastNoiseLite
var _tone_noise: FastNoiseLite
var _density_noise: FastNoiseLite

var _detail_state := DetailState.NEAR
var _dense_nodes: Array[MultiMeshInstance3D] = []
var _flexible_nodes: Array[MultiMeshInstance3D] = []
var _surface_node: MeshInstance3D
var _skirt_node: MeshInstance3D
var _debug_node: Node3D
var _body: StaticBody3D

var _rebuild_pending := false
var _surface_triangles := 0
var _skirt_triangles := 0
var _dense_instances := 0
var _flexible_instances := 0


func _ready() -> void:
	if profile == null:
		profile = GrassFieldProfile.new()
	if _region_cells.is_empty():
		# Standalone editor use: fill the chunk so dropping the node into a
		# scene shows something immediately rather than an empty transform.
		_fill_self()
	rebuild_all()


# --- configuration -----------------------------------------------------------


## Called by GrassFieldManager before the chunk builds anything. Passing the
## whole region's cell set (not a copy of just this chunk's) is deliberate — see
## _region_cells.
func configure(
	field_profile: GrassFieldProfile,
	coord: Vector2i,
	region_cells: Dictionary,
	clearances: Array[Dictionary]
) -> void:
	profile = field_profile
	chunk_coord = coord
	_region_cells = region_cells
	_clearances = clearances
	_collect_cells()
	_rebuild_pending = false


func _fill_self() -> void:
	var span: int = maxi(profile.chunk_size_in_tiles, 1)
	_region_cells = {}
	for row in span:
		for column in span:
			_region_cells[Vector2i(chunk_coord.x * span + column, chunk_coord.y * span + row)] = true
	_collect_cells()


func _collect_cells() -> void:
	var span: int = maxi(profile.chunk_size_in_tiles, 1)
	_cells.clear()
	for cell: Vector2i in _region_cells:
		if _chunk_of(cell, span) == chunk_coord:
			_cells.append(cell)
	# Sorted so a rebuild produces byte-identical output for identical input;
	# Dictionary iteration order is not something to rely on for that.
	_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	_origin = Vector2(chunk_coord) * profile.chunk_size_in_metres() \
		- Vector2.ONE * profile.tile_size * 0.5
	position = Vector3(_origin.x, 0.0, _origin.y)


static func _chunk_of(cell: Vector2i, span: int) -> Vector2i:
	return Vector2i(floori(float(cell.x) / span), floori(float(cell.y) / span))


func _request_rebuild() -> void:
	# Inspector edits arrive one property at a time; rebuilding on each would
	# regenerate the whole chunk several times per keystroke.
	if not is_inside_tree() or _rebuild_pending:
		return
	_rebuild_pending = true
	await get_tree().process_frame
	_rebuild_pending = false
	rebuild_all()


# --- world-space fields ------------------------------------------------------
#
# Everything below is a PURE FUNCTION OF WORLD XZ. That is the entire seam
# strategy: no chunk index, no cell index, no local coordinate appears in any of
# them, so there is no way for two chunks to disagree about a shared point.


func _ensure_noise() -> void:
	if _height_noise == null:
		_height_noise = profile.create_height_noise()
	if _tone_noise == null:
		_tone_noise = profile.create_tone_noise()
	if _density_noise == null:
		_density_noise = profile.create_density_noise()


## Broad rolling ground. The two sine terms are not decoration — pure FBM noise
## alone reads as random lumpiness, while a couple of long, gently skewed waves
## underneath it give the field a direction the eye can follow, which is what
## makes it read as landscape instead of as texture.
func height_at(world: Vector2) -> float:
	_ensure_noise()
	var broad := _height_noise.get_noise_2d(world.x, world.y)
	var wave_a := sin(world.x * 0.31 + world.y * 0.17 + 0.8)
	var wave_b := sin(world.x * -0.16 + world.y * 0.28 + 2.1)
	# Weights sum to 1, so surface_height_amplitude is a true peak bound; the
	# three terms rarely align, leaving typical variation near 40% of it.
	return (broad * 0.638 + wave_a * 0.213 + wave_b * 0.149) \
		* profile.surface_height_amplitude


func normal_at(world: Vector2) -> Vector3:
	var d := NORMAL_SAMPLE_DISTANCE
	var left := height_at(world - Vector2(d, 0.0))
	var right := height_at(world + Vector2(d, 0.0))
	var back := height_at(world - Vector2(0.0, d))
	var front := height_at(world + Vector2(0.0, d))
	return Vector3(left - right, d * 2.0, back - front).normalized()


func tone_at(world: Vector2) -> float:
	_ensure_noise()
	return clampf(_tone_noise.get_noise_2d(world.x, world.y) * 0.5 + 0.5, 0.0, 1.0)


func colour_at(world: Vector2) -> Color:
	return profile.surface_colour(tone_at(world))


## Broad density multiplier around 1.0. Never returns zero: a density field that
## can reach zero produces bald patches, and bald patches inside a carpet read
## as damage rather than as variation.
func density_at(world: Vector2) -> float:
	_ensure_noise()
	var value := _density_noise.get_noise_2d(world.x, world.y)
	return clampf(1.0 + value * profile.density_variation, 0.25, 1.75)


## Combined retention from every clearance marker. Multiplied, not min()'d, so
## two overlapping props open a slightly wider gap than either alone instead of
## one silently masking the other.
func clearance_at(world: Vector2, dense: bool) -> float:
	var weight := 1.0
	for clearance in _clearances:
		var single := GrassClearance3D.clearance_weight(
			world,
			clearance["position"],
			clearance["radius"],
			clearance["softness"]
		)
		if dense:
			single = lerpf(float(clearance["retain"]), 1.0, single)
		weight *= single
	return weight


# --- deterministic hashing ---------------------------------------------------


## Stable value in 0..1 from a lattice coordinate. Deterministic per world
## position rather than drawn from a sequence, so a chunk rebuilt on its own
## produces exactly the instances it had before — and so a placement never
## depends on how many chunks were built first.
static func _hash_unit(x: int, y: int, salt: int) -> float:
	var h: int = x * 73856093
	h ^= y * 19349663
	h ^= salt * 83492791
	h = (h ^ (h >> 13)) * 1274126177
	h ^= h >> 16
	return float(h & 0xFFFFFF) / float(0xFFFFFF)


# --- surface -----------------------------------------------------------------


func rebuild_all() -> void:
	rebuild_surface()
	rebuild_grass()
	_rebuild_debug()
	_apply_visibility()


func rebuild_surface() -> void:
	if profile == null or _cells.is_empty():
		return
	_ensure_nodes()
	var mesh := _build_surface_mesh()
	_surface_node.mesh = mesh
	_surface_node.material_override = _get_surface_material()
	_skirt_node.mesh = _build_skirt_mesh()
	_skirt_node.material_override = _get_surface_material()
	_rebuild_collision(mesh)


func _build_surface_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var lookup: Dictionary = {}
	var segments: int = maxi(profile.surface_segments_per_tile, 1)

	for cell in _cells:
		for row in segments:
			for column in segments:
				var a := _surface_vertex(cell, column, row, lookup, vertices, normals, colours)
				var b := _surface_vertex(cell, column + 1, row, lookup, vertices, normals, colours)
				var c := _surface_vertex(cell, column + 1, row + 1, lookup, vertices, normals, colours)
				var d := _surface_vertex(cell, column, row + 1, lookup, vertices, normals, colours)
				# a->b->c is the front face for an upward quad. Reversing it
				# culls the whole surface and looks like a missing mesh.
				indices.append_array([a, b, c, a, c, d])

	_surface_triangles = indices.size() / 3
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


## Resolves a sample to a vertex index, creating it only the first time any cell
## asks for it. The key is the GLOBAL sample coordinate, so the sample shared by
## two adjacent cells — or by two adjacent chunks — is one vertex with one
## normal and one colour, and there is physically nothing there to seam.
func _surface_vertex(
	cell: Vector2i,
	column: int,
	row: int,
	lookup: Dictionary,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colours: PackedColorArray
) -> int:
	var segments: int = maxi(profile.surface_segments_per_tile, 1)
	var key := Vector2i(cell.x * segments + column, cell.y * segments + row)
	if lookup.has(key):
		return lookup[key]
	var world := _sample_world(key)
	var index := vertices.size()
	var local := world - _origin
	vertices.append(Vector3(local.x, height_at(world), local.y))
	normals.append(normal_at(world))
	colours.append(colour_at(world))
	lookup[key] = index
	return index


func _sample_world(key: Vector2i) -> Vector2:
	var step := profile.surface_step()
	return Vector2(
		float(key.x) * step - profile.tile_size * 0.5,
		float(key.y) * step - profile.tile_size * 0.5
	)


# --- exposed edge skirt ------------------------------------------------------


## Vertical geometry ONLY where the region actually ends. Between two grass
## cells there is no wall, no bevel and no outline — drawing one there is
## precisely how a lawn turns back into a tray of tiles.
func _build_skirt_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var segments: int = maxi(profile.surface_segments_per_tile, 1)
	var half := profile.tile_size * 0.5
	var bevel := profile.skirt_bevel
	var depth := profile.skirt_height

	for cell in _cells:
		var centre := Vector2(cell) * profile.tile_size
		for direction_index in DIRECTIONS.size():
			var step_cell: Vector2i = DIRECTIONS[direction_index]
			if _region_cells.has(cell + step_cell):
				continue
			var outward := Vector2(step_cell)
			var along := Vector2(-outward.y, outward.x)
			var edge_centre := centre + outward * half
			for segment in segments:
				var t0 := (float(segment) / segments - 0.5) * profile.tile_size
				var t1 := (float(segment + 1) / segments - 0.5) * profile.tile_size
				var p0 := edge_centre + along * t0
				var p1 := edge_centre + along * t1
				_skirt_strip(p0, p1, outward, bevel, depth,
					vertices, normals, colours, indices)
			# A convex corner leaves a wedge between the two chamfers, which
			# from a low angle is a hole straight through the rim.
			var next_cell: Vector2i = DIRECTIONS[(direction_index + 1) % DIRECTIONS.size()]
			if not _region_cells.has(cell + next_cell):
				_skirt_corner(centre, outward, Vector2(next_cell), half, bevel, depth,
					vertices, normals, colours, indices)

	_skirt_triangles = indices.size() / 3
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


## One segment of rim: a chamfer from the exact boundary down to an inset lip,
## then a wall dropping from that lip. The top edge still lands precisely on the
## boundary, so the surface never stops short and leaves the pale sliver that an
## inset cap produces; the wall simply tucks under the overhang.
func _skirt_strip(
	p0: Vector2,
	p1: Vector2,
	outward: Vector2,
	bevel: float,
	depth: float,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colours: PackedColorArray,
	indices: PackedInt32Array
) -> void:
	var h0 := height_at(p0)
	var h1 := height_at(p1)
	var inset0 := p0 - outward * bevel
	var inset1 := p1 - outward * bevel
	var side := Vector3(outward.x, 0.0, outward.y)
	var chamfer_normal := (side + Vector3.UP).normalized()

	var top_colour0 := colour_at(p0).darkened(profile.skirt_darken)
	var top_colour1 := colour_at(p1).darkened(profile.skirt_darken)
	# The base sits deeper in shade than the rim; without it the wall reads as a
	# flat printed band rather than as a solid edge with thickness.
	var base_colour0 := top_colour0.darkened(0.25)
	var base_colour1 := top_colour1.darkened(0.25)

	var t0 := _push(vertices, normals, colours,
		Vector3(p0.x, h0, p0.y) - _origin3(), chamfer_normal, top_colour0)
	var t1 := _push(vertices, normals, colours,
		Vector3(p1.x, h1, p1.y) - _origin3(), chamfer_normal, top_colour1)
	var c0 := _push(vertices, normals, colours,
		Vector3(inset0.x, h0 - bevel, inset0.y) - _origin3(), chamfer_normal, top_colour0)
	var c1 := _push(vertices, normals, colours,
		Vector3(inset1.x, h1 - bevel, inset1.y) - _origin3(), chamfer_normal, top_colour1)
	var b0 := _push(vertices, normals, colours,
		Vector3(inset0.x, h0 - depth, inset0.y) - _origin3(), side, base_colour0)
	var b1 := _push(vertices, normals, colours,
		Vector3(inset1.x, h1 - depth, inset1.y) - _origin3(), side, base_colour1)

	indices.append_array([t0, t1, c1, t0, c1, c0])
	indices.append_array([c0, c1, b1, c0, b1, b0])


## Fills the wedge where two exposed edges meet. Winding is decided by testing
## the face normal against the outward direction rather than by working it out
## per case, because the four corner orientations are exactly the kind of thing
## that gets one case wrong and shows up as a single black triangle.
func _skirt_corner(
	centre: Vector2,
	outward_a: Vector2,
	outward_b: Vector2,
	half: float,
	bevel: float,
	depth: float,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colours: PackedColorArray,
	indices: PackedInt32Array
) -> void:
	var corner := centre + (outward_a + outward_b) * half
	var h := height_at(corner)
	var inset_a := corner - outward_a * bevel
	var inset_b := corner - outward_b * bevel
	var diagonal := (outward_a + outward_b).normalized()
	var face_normal := (Vector3(diagonal.x, 0.0, diagonal.y) + Vector3.UP).normalized()
	var top_colour := colour_at(corner).darkened(profile.skirt_darken)
	var base_colour := top_colour.darkened(0.25)

	var t := _push(vertices, normals, colours,
		Vector3(corner.x, h, corner.y) - _origin3(), face_normal, top_colour)
	var ca := _push(vertices, normals, colours,
		Vector3(inset_a.x, h - bevel, inset_a.y) - _origin3(), face_normal, top_colour)
	var cb := _push(vertices, normals, colours,
		Vector3(inset_b.x, h - bevel, inset_b.y) - _origin3(), face_normal, top_colour)
	var ba := _push(vertices, normals, colours,
		Vector3(inset_a.x, h - depth, inset_a.y) - _origin3(),
		Vector3(diagonal.x, 0.0, diagonal.y), base_colour)
	var bb := _push(vertices, normals, colours,
		Vector3(inset_b.x, h - depth, inset_b.y) - _origin3(),
		Vector3(diagonal.x, 0.0, diagonal.y), base_colour)

	_append_oriented(indices, vertices, t, ca, cb, diagonal)
	_append_oriented(indices, vertices, ca, ba, bb, diagonal)
	_append_oriented(indices, vertices, ca, bb, cb, diagonal)


func _append_oriented(
	indices: PackedInt32Array,
	vertices: PackedVector3Array,
	a: int,
	b: int,
	c: int,
	outward: Vector2
) -> void:
	var normal := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
	if normal.dot(Vector3(outward.x, 0.0, outward.y)) < 0.0:
		indices.append_array([a, c, b])
	else:
		indices.append_array([a, b, c])


func _push(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colours: PackedColorArray,
	position_value: Vector3,
	normal: Vector3,
	colour: Color
) -> int:
	var index := vertices.size()
	vertices.append(position_value)
	normals.append(normal)
	colours.append(colour)
	return index


func _origin3() -> Vector3:
	return Vector3(_origin.x, 0.0, _origin.y)


# --- tuft placement ----------------------------------------------------------


func rebuild_grass() -> void:
	if profile == null or _cells.is_empty():
		return
	_ensure_nodes()
	var dense_meshes := profile.micro_tuft_mesh_list()
	var flexible_meshes := profile.flexible_tuft_mesh_list()
	var dense := _place(profile.dense_instances_per_square_metre, dense_meshes.size(), true, 101)
	var flexible := _place(profile.flexible_instances_per_square_metre, flexible_meshes.size(), false, 307)
	_dense_instances = 0
	_flexible_instances = 0
	for slot in 3:
		var mesh: Mesh = dense_meshes[slot] if slot < dense_meshes.size() else null
		var placements: Array = dense[slot] if slot < dense.size() else []
		_dense_instances += _fill_multimesh(_dense_nodes[slot], mesh, placements)
	for slot in 2:
		var mesh: Mesh = flexible_meshes[slot] if slot < flexible_meshes.size() else null
		var placements: Array = flexible[slot] if slot < flexible.size() else []
		_flexible_instances += _fill_multimesh(_flexible_nodes[slot], mesh, placements)
	_apply_detail_state()


## Jittered world-space lattice. The lattice is anchored to WORLD ORIGIN, not to
## the chunk or the cell, so the pattern simply continues across every boundary
## — the single most important property here, because a distribution that
## restarts anywhere draws that line on screen no matter how good the meshes are.
func _place(density: float, slots: int, dense: bool, salt: int) -> Array:
	var buckets: Array = []
	for slot in maxi(slots, 1):
		buckets.append([])
	if slots <= 0 or density <= 0.0:
		return buckets

	var spacing := 1.0 / sqrt(maxf(density, 0.001))
	var bounds := _cell_bounds()
	var low := Vector2i(
		floori((bounds.position.x) / spacing) - 1,
		floori((bounds.position.y) / spacing) - 1
	)
	var high := Vector2i(
		ceili((bounds.position.x + bounds.size.x) / spacing) + 1,
		ceili((bounds.position.y + bounds.size.y) / spacing) + 1
	)
	var jitter := profile.placement_jitter
	var cell_lookup: Dictionary = {}
	for cell in _cells:
		cell_lookup[cell] = true

	for ly in range(low.y, high.y + 1):
		for lx in range(low.x, high.x + 1):
			var jx := (_hash_unit(lx, ly, salt) - 0.5) * jitter
			var jy := (_hash_unit(lx, ly, salt + 1) - 0.5) * jitter
			var world := Vector2((float(lx) + 0.5 + jx) * spacing, (float(ly) + 0.5 + jy) * spacing)
			# Ownership is by CELL, so every lattice point belongs to exactly one
			# chunk. Testing against the chunk's rectangle instead would double
			# up along shared borders and leave a visibly denser stripe there.
			var cell := Vector2i(
				roundi(world.x / profile.tile_size),
				roundi(world.y / profile.tile_size)
			)
			if not cell_lookup.has(cell):
				continue
			if _hash_unit(lx, ly, salt + 2) > density_at(world):
				continue
			if _hash_unit(lx, ly, salt + 3) > clearance_at(world, dense):
				continue

			var slot := int(_hash_unit(lx, ly, salt + 4) * slots) % slots
			var scale_min := profile.dense_scale_min if dense else profile.flexible_scale_min
			var scale_max := profile.dense_scale_max if dense else profile.flexible_scale_max
			var sink_min := profile.dense_sink_min if dense else profile.flexible_sink_min
			var sink_max := profile.dense_sink_max if dense else profile.flexible_sink_max
			var wind_min := profile.dense_wind_amount_min if dense else profile.flexible_wind_amount_min
			var wind_max := profile.dense_wind_amount_max if dense else profile.flexible_wind_amount_max
			var sink := lerpf(sink_min, sink_max, _hash_unit(lx, ly, salt + 7))
			# Tufts take most of their tone from the ground they stand in, so a
			# tuft never contrasts with the surface directly beneath it; the
			# remaining quarter is per-instance so neighbours still differ.
			var blend := clampf(tone_at(world) * 0.75 + _hash_unit(lx, ly, salt + 9) * 0.25, 0.0, 1.0)
			(buckets[slot] as Array).append({
				"world": world,
				"y": height_at(world) - sink,
				"yaw": _hash_unit(lx, ly, salt + 5) * TAU,
				"scale": lerpf(scale_min, scale_max, _hash_unit(lx, ly, salt + 6)),
				"wind_amount": lerpf(wind_min, wind_max, _hash_unit(lx, ly, salt + 8)),
				"wind_phase": _hash_unit(lx, ly, salt + 10),
				"blend": blend,
				"order": _hash_unit(lx, ly, salt + 11),
			})

	# Shuffled by hash so that trimming to visible_instance_count for MID detail
	# removes a spatially uniform scatter. Left in lattice order it would erase a
	# band across the chunk instead, which reads as a mown stripe.
	for bucket: Array in buckets:
		bucket.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["order"]) < float(b["order"]))
	return buckets


func _cell_bounds() -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var half := profile.tile_size * 0.5
	for cell in _cells:
		var centre := Vector2(cell) * profile.tile_size
		low = low.min(centre - Vector2.ONE * half)
		high = high.max(centre + Vector2.ONE * half)
	return Rect2(low, high - low)


func _fill_multimesh(node: MultiMeshInstance3D, mesh: Mesh, placements: Array) -> int:
	if node == null:
		return 0
	if mesh == null or placements.is_empty():
		node.multimesh = null
		return 0
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	# Both flags must be set BEFORE instance_count: Godot allocates the instance
	# buffer on that assignment, and a custom-data array requested afterwards is
	# silently absent, leaving every tuft with INSTANCE_CUSTOM = 0 — one rigid,
	# uniformly phased field.
	multi.use_custom_data = true
	multi.mesh = mesh
	multi.instance_count = placements.size()
	for index in placements.size():
		var placement: Dictionary = placements[index]
		var world: Vector2 = placement["world"]
		var basis := Basis(Vector3.UP, float(placement["yaw"]))
		basis = basis.scaled(Vector3.ONE * float(placement["scale"]))
		var local := Vector3(world.x - _origin.x, float(placement["y"]), world.y - _origin.y)
		multi.set_instance_transform(index, Transform3D(basis, local))
		multi.set_instance_custom_data(index, Color(
			float(placement["wind_phase"]),
			float(placement["wind_amount"]),
			float(placement["blend"]),
			1.0
		))
	node.multimesh = multi
	node.material_override = _get_tuft_material()
	return placements.size()


# --- nodes, materials, state -------------------------------------------------


func _ensure_nodes() -> void:
	if _surface_node == null:
		_surface_node = _adopt("SurfaceMesh", MeshInstance3D) as MeshInstance3D
	if _skirt_node == null:
		_skirt_node = _adopt("ExposedEdgeSkirt", MeshInstance3D) as MeshInstance3D
	if _dense_nodes.is_empty():
		for suffix in ["A", "B", "C"]:
			var node := _adopt("DenseCarpet_%s" % suffix, MultiMeshInstance3D) as MultiMeshInstance3D
			# Thousands of tiny shadow casters produce noise, not shading, and
			# cost a shadow pass each. The surface and the flexible layer carry
			# the readable shadows instead.
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.extra_cull_margin = _cull_margin()
			_dense_nodes.append(node)
	if _flexible_nodes.is_empty():
		for suffix in ["A", "B"]:
			var node := _adopt("FlexibleTufts_%s" % suffix, MultiMeshInstance3D) as MultiMeshInstance3D
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.extra_cull_margin = _cull_margin()
			_flexible_nodes.append(node)
	if _body == null:
		_body = _adopt("StaticBody3D", StaticBody3D) as StaticBody3D
	if _debug_node == null:
		_debug_node = _adopt("Debug", Node3D) as Node3D


## The wind shader displaces vertices, and the engine culls against the
## UNDISPLACED bounds. Too small a margin makes grass vanish at the screen edge
## exactly when the gust peaks. Sized from the actual shader maximum rather than
## left at a guessed constant.
func _cull_margin() -> float:
	return maxf(0.08, (profile.wind_strength + profile.gust_strength) * 4.0)


func _adopt(node_name: String, type: Variant) -> Node:
	var existing := get_node_or_null(NodePath(node_name))
	if existing != null:
		return existing
	var node: Node = type.new()
	node.name = node_name
	add_child(node)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		node.owner = get_tree().edited_scene_root
	return node


func _get_surface_material() -> ShaderMaterial:
	if _surface_material == null:
		_surface_material = ShaderMaterial.new()
		_surface_material.shader = load("res://world/grass/grass_surface.gdshader")
	return _surface_material


func _get_tuft_material() -> ShaderMaterial:
	if _tuft_material == null:
		_tuft_material = ShaderMaterial.new()
		_tuft_material.shader = load("res://world/grass/grass_tuft.gdshader")
	if profile != null:
		_tuft_material.set_shader_parameter("grass_deep", profile.tuft_deep)
		_tuft_material.set_shader_parameter("grass_main", profile.tuft_primary)
		_tuft_material.set_shader_parameter("grass_light", profile.tuft_light)
		_tuft_material.set_shader_parameter("wind_direction", profile.wind_direction)
		_tuft_material.set_shader_parameter("wind_speed", profile.wind_speed)
		_tuft_material.set_shader_parameter("wind_world_scale", profile.wind_world_scale)
		_tuft_material.set_shader_parameter("base_wind_strength", profile.wind_strength)
		_tuft_material.set_shader_parameter("gust_wind_strength", profile.gust_strength)
	return _tuft_material


func _rebuild_collision(surface: ArrayMesh) -> void:
	if _body == null:
		return
	for child in _body.get_children():
		child.queue_free()
	if surface == null:
		return
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	# One trimesh for the whole chunk. Grass is never a collider: per-tuft
	# shapes would add thousands of bodies for something the player can walk
	# straight through.
	shape.shape = surface.create_trimesh_shape()
	_body.add_child(shape)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		shape.owner = get_tree().edited_scene_root


## Detail is applied through visible_instance_count, so changing LOD costs no
## rebuild, no allocation and no garbage — which is what makes it safe to do
## while the camera moves.
func set_detail_state(state: DetailState) -> void:
	if _detail_state == state:
		return
	_detail_state = state
	_apply_detail_state()


func _apply_detail_state() -> void:
	var dense_fraction := 1.0
	var flexible_fraction := 1.0
	match _detail_state:
		DetailState.MID:
			dense_fraction = profile.mid_dense_fraction
			flexible_fraction = profile.mid_flexible_fraction
		DetailState.FAR:
			dense_fraction = 0.0
			flexible_fraction = 0.0
	_scale_group(_dense_nodes, dense_fraction)
	_scale_group(_flexible_nodes, flexible_fraction)
	_apply_visibility()


func _scale_group(nodes: Array[MultiMeshInstance3D], fraction: float) -> void:
	for node in nodes:
		if node == null or node.multimesh == null:
			continue
		node.multimesh.visible_instance_count = \
			int(round(node.multimesh.instance_count * clampf(fraction, 0.0, 1.0)))


func _apply_visibility() -> void:
	if _surface_node == null:
		return
	var solo_dense := show_dense_carpet_only
	var solo_flexible := show_flexible_tufts_only
	var solo_surface := show_surface_only
	var any_solo := solo_dense or solo_flexible or solo_surface
	_surface_node.visible = not any_solo or solo_surface
	if _skirt_node != null:
		_skirt_node.visible = _surface_node.visible
	for node in _dense_nodes:
		if node != null:
			node.visible = (not any_solo or solo_dense) and _detail_state != DetailState.FAR
	for node in _flexible_nodes:
		if node != null:
			node.visible = (not any_solo or solo_flexible) and _detail_state != DetailState.FAR
	if _debug_node != null:
		_debug_node.visible = show_chunk_bounds or show_clearance


func _rebuild_debug() -> void:
	if _debug_node == null:
		return
	for child in _debug_node.get_children():
		child.queue_free()
	var bounds := _cell_bounds()
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.35, 0.85)
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for corner: Vector2 in [
		bounds.position,
		bounds.position + Vector2(bounds.size.x, 0.0),
		bounds.position + bounds.size,
		bounds.position + Vector2(0.0, bounds.size.y),
		bounds.position,
	]:
		var local := corner - _origin
		mesh.surface_add_vertex(Vector3(local.x, height_at(corner) + 0.02, local.y))
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.name = "ChunkBounds"
	node.mesh = mesh
	_debug_node.add_child(node)

	if show_clearance:
		for clearance in _clearances:
			_debug_node.add_child(_clearance_ring(clearance))


func _clearance_ring(clearance: Dictionary) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.25, 0.85, 1.0)
	var centre: Vector2 = clearance["position"]
	var radius: float = clearance["radius"]
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for step in 33:
		var angle := TAU * float(step) / 32.0
		var point := centre + Vector2(cos(angle), sin(angle)) * radius
		var local := point - _origin
		mesh.surface_add_vertex(Vector3(local.x, height_at(point) + 0.02, local.y))
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.name = "Clearance"
	node.mesh = mesh
	return node


# --- reporting ---------------------------------------------------------------


## Feeds validation deliverable 13 (triangle and instance counts per chunk).
func statistics() -> Dictionary:
	var dense_triangles := 0
	for node in _dense_nodes:
		if node != null and node.multimesh != null and node.multimesh.mesh != null:
			dense_triangles += _mesh_triangles(node.multimesh.mesh) * node.multimesh.instance_count
	var flexible_triangles := 0
	for node in _flexible_nodes:
		if node != null and node.multimesh != null and node.multimesh.mesh != null:
			flexible_triangles += _mesh_triangles(node.multimesh.mesh) * node.multimesh.instance_count
	return {
		"chunk": chunk_coord,
		"cells": _cells.size(),
		"surface_triangles": _surface_triangles,
		"skirt_triangles": _skirt_triangles,
		"dense_instances": _dense_instances,
		"flexible_instances": _flexible_instances,
		"dense_triangles": dense_triangles,
		"flexible_triangles": flexible_triangles,
		"total_triangles": _surface_triangles + _skirt_triangles + dense_triangles + flexible_triangles,
	}


static func _mesh_triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices is PackedInt32Array:
			total += (indices as PackedInt32Array).size() / 3
		else:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total
