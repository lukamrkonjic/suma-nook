class_name TileKitMeshUtils
extends RefCounted
## Geometry helpers shared by every Tile Kit layer builder.
##
## Everything here returns raw vertex/index data or writes into a MeshBatch —
## one accumulating surface per palette key — so a whole layer collapses to
## one ArrayMesh with one surface per material. That is what keeps the editing
## preview at a handful of draw calls (one MeshInstance3D per layer) while the
## builders stay free to emit as many little forms as they like.


## One material's accumulating buffers. A real object, deliberately: packed
## arrays extracted from a Dictionary are copy-on-write temporaries, and
## appending to `(dict[k] as PackedVector3Array)` silently mutates a copy the
## dictionary never sees. Object fields don't have that trap.
class SurfacePool:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()


## Accumulates triangles per palette key, then commits one ArrayMesh with one
## surface per key. Positions carry their own analytic normals: the builders
## know the exact surface they are sweeping, and computed normals are what
## make the rounded forms read as soft instead of faceted.
class MeshBatch:
	var _surfaces: Dictionary = {}

	func _pool(key: String) -> SurfacePool:
		if not _surfaces.has(key):
			_surfaces[key] = SurfacePool.new()
		return _surfaces[key]

	## Appends an indexed patch. `vertices` and `normals` must be equal length;
	## `indices` reference into the appended patch (0-based).
	func add(key: String, vertices: PackedVector3Array,
			normals: PackedVector3Array, indices: PackedInt32Array) -> void:
		var pool := _pool(key)
		var offset := pool.vertices.size()
		pool.vertices.append_array(vertices)
		pool.normals.append_array(normals)
		for index in indices:
			pool.indices.append(index + offset)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for key: String in _surfaces:
			var pool: SurfacePool = _surfaces[key]
			if pool.vertices.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = pool.vertices
			arrays[Mesh.ARRAY_NORMAL] = pool.normals
			arrays[Mesh.ARRAY_INDEX] = pool.indices
			var surface := mesh.get_surface_count()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(surface, TileKitPalette.material(key))
		return mesh

	func triangle_count() -> int:
		var total := 0
		for key: String in _surfaces:
			total += (_surfaces[key] as SurfacePool).indices.size() / 3
		return total


# --- soft blob outlines ------------------------------------------------------


## Smooth irregular closed outline: a circle whose per-point radius is jittered
## then neighbour-averaged. The averaging passes are the whole trick — raw
## jitter gives a polygon with corners, two or three smoothing passes give the
## soft hand-cut silhouette the dressing patches need.
static func soft_blob_outline(
	rng: RandomNumberGenerator,
	points: int,
	irregularity: float,
	smoothing_passes: int
) -> PackedFloat32Array:
	var radii := PackedFloat32Array()
	for index in points:
		radii.append(1.0 + rng.randf_range(-irregularity, irregularity))
	for pass_index in smoothing_passes:
		var smoothed := PackedFloat32Array()
		smoothed.resize(points)
		for index in points:
			var previous := radii[(index + points - 1) % points]
			var next := radii[(index + 1) % points]
			smoothed[index] = (previous + radii[index] * 2.0 + next) * 0.25
		radii = smoothed
	return radii


## Flat filled blob at `height`, fanned from its centroid. Radial outlines are
## star-shaped around their centre, so the fan is always a valid fill.
static func add_flat_blob(
	batch: MeshBatch,
	key: String,
	centre: Vector3,
	radius_x: float,
	radius_z: float,
	yaw: float,
	radii: PackedFloat32Array
) -> void:
	var points := radii.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.append(centre)
	normals.append(Vector3.UP)
	var basis := Basis(Vector3.UP, yaw)
	for index in points:
		var angle := TAU * float(index) / float(points)
		var local := Vector3(
			cos(angle) * radius_x * radii[index],
			0.0,
			sin(angle) * radius_z * radii[index]
		)
		vertices.append(centre + basis * local)
		normals.append(Vector3.UP)
	# Godot's front face is CLOCKWISE: the right-hand-rule normal of a front
	# face points AWAY from the viewer. Every fan and strip in this file is
	# wound for that convention — flip any of them and the surface silently
	# renders inside-out while vertex normals still claim otherwise.
	for index in points:
		indices.append_array([0, 1 + index, 1 + (index + 1) % points])
	batch.add(key, vertices, normals, indices)


## Soft raised patch draped over the cap surface: a shallow organic cushion
## with a rolled edge, not a painted circle. Every rim vertex takes its height
## from the cap function so the patch hugs relief and bevels; interior rings
## rise on a superellipse profile whose edge tangent goes vertical, which is
## what makes moss, snow, and soil patches read as soft material RESTING on
## the ground — a form with its own light and shadow — rather than a stain.
##
## `cushion` is the peak height. Zero (or near) degenerates gracefully into
## the old flat sheen for deliberately flat marks such as wet mud, and those
## keep UP normals for the decal read. `softness` 0..1 trades a tight rolled
## shoulder for a broad soft dome.
static func add_cushion_blob(
	batch: MeshBatch,
	key: String,
	centre: Vector2,
	lift: float,
	radius_x: float,
	radius_z: float,
	yaw: float,
	radii: PackedFloat32Array,
	cap_height: Callable,
	cushion := 0.0,
	softness := 0.55
) -> void:
	var points := radii.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var height_at := func(point: Vector2) -> float:
		return float(cap_height.call(point)) if cap_height.is_valid() else 0.0
	var rotation := Basis(Vector3.UP, yaw)
	var outline_point := func(index: int, shrink: float) -> Vector2:
		var angle := TAU * float(index) / float(points)
		var local := rotation * Vector3(
			cos(angle) * radius_x * radii[index] * shrink, 0.0,
			sin(angle) * radius_z * radii[index] * shrink)
		return centre + Vector2(local.x, local.z)

	if cushion <= 0.002:
		# Flat sheen fallback: one fan, sky-lit, hugging the surface.
		vertices.append(Vector3(centre.x, height_at.call(centre) + lift, centre.y))
		normals.append(Vector3.UP)
		for index in points:
			var world: Vector2 = outline_point.call(index, 1.0)
			vertices.append(Vector3(world.x, height_at.call(world) + lift, world.y))
			normals.append(Vector3.UP)
		for index in points:
			indices.append_array([0, 1 + index, 1 + (index + 1) % points])
		batch.add(key, vertices, normals, indices)
		return

	# Superellipse cushion profile: f(s) = (1 - s^a)^e over s = 0 (centre) to
	# 1 (contact rim). e < 1 gives a vertical edge tangent — the rolled lip.
	var a := lerpf(3.0, 2.2, softness)
	var e := lerpf(0.52, 0.78, softness)
	var profile := func(s: float) -> float:
		return pow(maxf(0.0, 1.0 - pow(s, a)), e)
	# Ring spacing biased toward the rim, where the roll needs resolution.
	var ring_s := PackedFloat32Array()
	var ring_count := 5
	for ring in ring_count:
		ring_s.append(sin((float(ring + 1) / float(ring_count)) * PI * 0.5))

	# Centre vertex.
	var base_y := float(height_at.call(centre)) + lift
	vertices.append(Vector3(centre.x, base_y + cushion, centre.y))
	normals.append(Vector3.UP)
	# Rings outward. Vertex height follows the profile above the CENTRE's cap
	# height for interior rings, blending to the rim's own cap height at s = 1
	# so the contact ring always meets the real ground.
	for ring in ring_count:
		var s := ring_s[ring]
		var factor: float = profile.call(s)
		# Analytic slope of the profile for the normal pitch.
		var slope := 0.0
		if s > 0.0001 and factor > 0.0001:
			slope = e * a * pow(s, a - 1.0) * pow(1.0 - pow(s, a), e - 1.0)
		for index in points:
			var world: Vector2 = outline_point.call(index, s)
			var ground := float(height_at.call(world)) + lift
			var blended := lerpf(base_y, ground, s)
			vertices.append(Vector3(world.x, blended + factor * cushion, world.y))
			var outward := (world - centre)
			var reach: float = maxf(outward.length(), 0.0001)
			var radial := outward / reach
			# dh/dr in world units: profile slope scaled by cushion over the
			# patch's local radius at this angle.
			var local_radius: float = maxf(reach / maxf(s, 0.0001), 0.0001)
			var gradient := slope * cushion / local_radius
			normals.append(Vector3(
				radial.x * gradient, 1.0, radial.y * gradient
			).normalized())

	# Fan the centre to ring 0, stitch consecutive rings.
	for index in points:
		indices.append_array([0, 1 + index, 1 + (index + 1) % points])
	for ring in ring_count - 1:
		var a0 := 1 + ring * points
		var b0 := 1 + (ring + 1) * points
		for index in points:
			var next := (index + 1) % points
			indices.append_array([
				a0 + index, b0 + index, b0 + next,
				a0 + index, b0 + next, a0 + next,
			])
	batch.add(key, vertices, normals, indices)


# --- rounded-rectangle shells ------------------------------------------------


## CCW rounded-rectangle outline of half-extent `half` with corner radius
## `corner`, plus matching outward normals. Corner point count is fixed by
## `corner_segments`, so outlines with different insets pair up ring-to-ring.
static func rounded_rect_outline(
	half: float,
	corner: float,
	corner_segments: int
) -> Array:
	var points := PackedVector2Array()
	var outwards := PackedVector2Array()
	var r := clampf(corner, 0.0015, half - 0.001)
	var inner := half - r
	var corners := [
		[Vector2(inner, -inner), -PI / 2.0],
		[Vector2(inner, inner), 0.0],
		[Vector2(-inner, inner), PI / 2.0],
		[Vector2(-inner, -inner), PI],
	]
	for corner_data: Array in corners:
		var centre: Vector2 = corner_data[0]
		var start: float = corner_data[1]
		for step in corner_segments + 1:
			var angle := start + (PI / 2.0) * float(step) / float(corner_segments)
			var outward := Vector2(cos(angle), sin(angle))
			points.append(centre + outward * r)
			outwards.append(outward)
	return [points, outwards]


## Sweeps a shell from stacked rings of the same outline: each ring is
## (inset, y, normal_pitch), where normal_pitch 0 = fully sideways and
## PI/2 = straight up. Consecutive rings are stitched with quads; smooth
## normals come from the analytic pitch, so bevels read as continuous curves
## while a pitch jump between duplicated rings gives a deliberate hard edge.
static func add_ring_shell(
	batch: MeshBatch,
	key: String,
	half: float,
	corner: float,
	corner_segments: int,
	rings: Array
) -> void:
	var outline: Array = rounded_rect_outline(half, corner, corner_segments)
	var base_points: PackedVector2Array = outline[0]
	var base_outwards: PackedVector2Array = outline[1]
	var count := base_points.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for ring: Array in rings:
		var inset: float = ring[0]
		var y: float = ring[1]
		var pitch: float = ring[2]
		for index in count:
			var point := base_points[index] - base_outwards[index] * inset
			var outward := base_outwards[index]
			vertices.append(Vector3(point.x, y, point.y))
			normals.append(Vector3(
				outward.x * cos(pitch), sin(pitch), outward.y * cos(pitch)
			).normalized())

	# Ring 0 is the LOWER ring; the outline advances so that on the +X face z
	# increases. Under Godot's clockwise front-face rule the outward winding
	# is lower -> lower_next -> upper_next — the reverse faces every wall
	# inward and turns the tile into a bathtub.
	for ring_index in rings.size() - 1:
		var a0 := ring_index * count
		var b0 := (ring_index + 1) * count
		for index in count:
			var next := (index + 1) % count
			indices.append_array([
				a0 + index, a0 + next, b0 + next,
				a0 + index, b0 + next, b0 + index,
			])
	batch.add(key, vertices, normals, indices)


## Flat cap filling a rounded-rect outline at `inset`, facing up or down.
static func add_rect_cap(
	batch: MeshBatch,
	key: String,
	half: float,
	corner: float,
	corner_segments: int,
	inset: float,
	y: float,
	facing_up: bool
) -> void:
	var outline: Array = rounded_rect_outline(half, corner, corner_segments)
	var base_points: PackedVector2Array = outline[0]
	var base_outwards: PackedVector2Array = outline[1]
	var count := base_points.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var normal := Vector3.UP if facing_up else Vector3.DOWN
	vertices.append(Vector3(0.0, y, 0.0))
	normals.append(normal)
	for index in count:
		var point := base_points[index] - base_outwards[index] * inset
		vertices.append(Vector3(point.x, y, point.y))
		normals.append(normal)
	for index in count:
		var next := (index + 1) % count
		if facing_up:
			indices.append_array([0, 1 + index, 1 + next])
		else:
			indices.append_array([0, 1 + next, 1 + index])
	batch.add(key, vertices, normals, indices)


# --- water dressing ----------------------------------------------------------


## Flat ring band following a rounded-rect outline: the water's meniscus
## highlight — the thin lit line where a still surface meets its container.
static func add_flat_ring(
	batch: MeshBatch,
	key: String,
	half: float,
	corner: float,
	corner_segments: int,
	inset: float,
	width: float,
	y: float
) -> void:
	var outline: Array = rounded_rect_outline(half, corner, corner_segments)
	var points: PackedVector2Array = outline[0]
	var outwards: PackedVector2Array = outline[1]
	var count := points.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for index in count:
		var outer := points[index] - outwards[index] * inset
		var inner := points[index] - outwards[index] * (inset + width)
		vertices.append(Vector3(outer.x, y, outer.y))
		normals.append(Vector3.UP)
		vertices.append(Vector3(inner.x, y, inner.y))
		normals.append(Vector3.UP)
	for index in count:
		var next := (index + 1) % count
		var a := index * 2
		var b := index * 2 + 1
		var c := next * 2 + 1
		var d := next * 2
		indices.append_array([a, d, c, a, c, b])
	batch.add(key, vertices, normals, indices)


## The shared still-water treatment: one or two broad, softly modelled wave
## ridges drifting across the surface, plus the meniscus ring. Geometry only —
## calm and toy-like, readable in silhouette and lighting, no shader tricks.
static func add_water_dressing(
	batch: MeshBatch,
	rng: RandomNumberGenerator,
	region_half: float,
	corner: float,
	inset: float,
	level: float,
	ripple_key: String,
	ripple_count: int = 2,
	rim_width: float = 0.022
) -> void:
	if rim_width > 0.0:
		add_flat_ring(batch, ripple_key, region_half, corner, 6, inset,
			rim_width, level + 0.0025)
	var reach := region_half - inset - rim_width - 0.10
	if reach <= 0.12:
		return
	for ripple in ripple_count:
		var yaw := rng.randf() * TAU
		var axis := Vector3(cos(yaw), 0.0, sin(yaw))
		var across := Vector3(-axis.z, 0.0, axis.x)
		var centre3 := Vector3(
			rng.randf_range(-reach * 0.5, reach * 0.5), level,
			rng.randf_range(-reach * 0.5, reach * 0.5))
		var length := rng.randf_range(reach * 0.7, reach * 1.4)
		var bow := across * length * rng.randf_range(0.10, 0.22) \
			* (1.0 if rng.randf() < 0.5 else -1.0)
		var p0 := centre3 - axis * length * 0.5
		var p3 := centre3 + axis * length * 0.5
		add_ridge(batch, ripple_key,
			p0, p0.lerp(centre3 + bow, 0.55), p3.lerp(centre3 + bow, 0.55), p3,
			rng.randf_range(0.065, 0.100), rng.randf_range(0.010, 0.016))


# --- free-standing slabs -----------------------------------------------------


## A small rounded-rectangle slab anywhere on the tile: paver stones, planks,
## stepping flags. Same construction as the tile shell — rounded outline,
## vertical wall, small top bevel, flat cap — shrunk to stone size, so pavers
## read as miniature siblings of the tile itself.
static func add_slab(
	batch: MeshBatch,
	key: String,
	centre: Vector3,
	half_x: float,
	half_z: float,
	corner: float,
	slab_height: float,
	yaw: float,
	bevel: float = 0.016,
	corner_segments: int = 4
) -> void:
	bevel = minf(bevel, slab_height * 0.6)
	var outline := _slab_outline(half_x, half_z, corner, corner_segments)
	var points: PackedVector2Array = outline[0]
	var outwards: PackedVector2Array = outline[1]
	var count := points.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var rotation := Basis(Vector3.UP, yaw)

	# Rings bottom-up: base, shoulder start, rolled shoulder, top rim (inset),
	# matching the tile shell's winding contract. The extra shoulder ring is
	# what turns a chamfered box into a softly pressed pillow stone — the
	# highlight rolls around the edge instead of snapping across one facet.
	var rings := [
		[0.0, 0.0, 0.0],
		[0.0, slab_height - bevel, 0.30],
		[bevel * 0.45, slab_height - bevel * 0.28, 0.80],
		[bevel, slab_height, 1.25],
	]
	for ring: Array in rings:
		var inset: float = ring[0]
		var y: float = ring[1]
		var pitch: float = ring[2]
		for index in count:
			var point := points[index] - outwards[index] * inset
			var world := rotation * Vector3(point.x, 0.0, point.y)
			var outward := rotation * Vector3(outwards[index].x, 0.0, outwards[index].y)
			vertices.append(centre + Vector3(world.x, y, world.z))
			normals.append((outward * cos(pitch) + Vector3.UP * sin(pitch)).normalized())
	for ring_index in rings.size() - 1:
		var a0 := ring_index * count
		var b0 := (ring_index + 1) * count
		for index in count:
			var next := (index + 1) % count
			indices.append_array([
				a0 + index, a0 + next, b0 + next,
				a0 + index, b0 + next, b0 + index,
			])
	# Flat top cap.
	var top_first := vertices.size()
	vertices.append(centre + Vector3(0.0, slab_height, 0.0))
	normals.append(Vector3.UP)
	for index in count:
		var point := points[index] - outwards[index] * bevel
		var world := rotation * Vector3(point.x, 0.0, point.y)
		vertices.append(centre + Vector3(world.x, slab_height, world.z))
		normals.append(Vector3.UP)
	for index in count:
		var next := (index + 1) % count
		indices.append_array([top_first, top_first + 1 + index,
			top_first + 1 + next])
	batch.add(key, vertices, normals, indices)


## Rounded-rect outline for an arbitrary half-extent pair. The tile-shell
## outline assumes a square; slabs need rectangles for planks.
static func _slab_outline(half_x: float, half_z: float, corner: float,
		corner_segments: int) -> Array:
	var points := PackedVector2Array()
	var outwards := PackedVector2Array()
	var r := clampf(corner, 0.0015, minf(half_x, half_z) - 0.001)
	var inner_x := half_x - r
	var inner_z := half_z - r
	var corners := [
		[Vector2(inner_x, -inner_z), -PI / 2.0],
		[Vector2(inner_x, inner_z), 0.0],
		[Vector2(-inner_x, inner_z), PI / 2.0],
		[Vector2(-inner_x, -inner_z), PI],
	]
	for corner_data: Array in corners:
		var centre: Vector2 = corner_data[0]
		var start: float = corner_data[1]
		for step in corner_segments + 1:
			var angle := start + (PI / 2.0) * float(step) / float(corner_segments)
			var outward := Vector2(cos(angle), sin(angle))
			points.append(centre + outward * r)
			outwards.append(outward)
	return [points, outwards]


# --- rounded organic solids --------------------------------------------------


## A soft multi-lobed cushion mound: the turf-cluster / drift-bed primitive.
##
## One continuous parametric surface — never intersecting domes — whose plan
## outline is a circle modulated by two low-frequency lobe waves and whose
## height profile is a superellipse with a rolled edge, so the form reads as a
## thick soft mass RESTING on the ground: wider than tall, lumpy in silhouette,
## with a highlight that rolls over each lobe instead of snapping at a facet.
## This is what lets grass read as sculpted turf, leaf litter as a raked drift,
## and snow as a settled pillow, all from one primitive.
static func add_lobed_mound(
	batch: MeshBatch,
	key: String,
	centre: Vector3,
	radius_x: float,
	radius_z: float,
	height: float,
	yaw: float,
	rng: RandomNumberGenerator,
	lobe_depth := 0.20,
	rings: int = 5,
	segments: int = 18,
	softness := 0.6
) -> void:
	# Two incommensurate angular waves give a hand-modelled outline; a single
	# wave reads as a gear, pure jitter reads as noise.
	var phase_a := rng.randf() * TAU
	var phase_b := rng.randf() * TAU
	var weight_a := rng.randf_range(0.55, 0.85)
	var lobes_a := 2 + (rng.randi() % 2)
	var lobes_b := 3 + (rng.randi() % 3)
	var radius_at := func(angle: float) -> float:
		return 1.0 + lobe_depth * (
			weight_a * sin(angle * lobes_a + phase_a)
			+ (1.0 - weight_a) * sin(angle * lobes_b + phase_b)
		)
	# Superellipse height profile with a rolled shoulder (see add_cushion_blob).
	var a := lerpf(3.0, 2.2, softness)
	var e := lerpf(0.55, 0.75, softness)
	var profile := func(s: float) -> float:
		return pow(maxf(0.0, 1.0 - pow(minf(s, 1.0), a)), e)
	var basis := Basis(Vector3.UP, yaw)
	var point_at := func(s: float, angle: float) -> Vector3:
		var factor: float = radius_at.call(angle)
		var local := Vector3(
			cos(angle) * radius_x * factor * s,
			height * float(profile.call(s)),
			sin(angle) * radius_z * factor * s
		)
		return centre + basis * local

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.append(centre + Vector3.UP * height)
	normals.append(Vector3.UP)
	# Ring spacing biased toward the rim, where the roll needs resolution.
	for ring in rings:
		var s := sin((float(ring + 1) / float(rings)) * PI * 0.5)
		for segment in segments:
			var angle := TAU * float(segment) / float(segments)
			var position: Vector3 = point_at.call(s, angle)
			# Numeric normal from the parametric tangents: exact enough at any
			# lobe depth, and it keeps the surface reading as one soft form.
			var ds: Vector3 = (point_at.call(minf(s + 0.04, 1.0), angle)
				- point_at.call(maxf(s - 0.04, 0.0), angle))
			var da: Vector3 = (point_at.call(maxf(s, 0.02), angle + 0.18)
				- point_at.call(maxf(s, 0.02), angle - 0.18))
			var normal := da.cross(ds)
			if normal.length_squared() < 0.000001 or normal.y < 0.0:
				normal = Vector3.UP
			normals.append(normal.normalized())
			vertices.append(position)
	for segment in segments:
		indices.append_array([0, 1 + segment, 1 + (segment + 1) % segments])
	for ring in rings - 1:
		var a0 := 1 + ring * segments
		var b0 := 1 + (ring + 1) * segments
		for segment in segments:
			var next := (segment + 1) % segments
			indices.append_array([
				a0 + segment, b0 + segment, b0 + next,
				a0 + segment, b0 + next, a0 + next,
			])
	batch.add(key, vertices, normals, indices)


## A soft swept ridge: a half-elliptical cross-section carried along a ground
## Bezier, tapering to nothing at both ends. Water gets its broad calm wave
## forms from this; snow and sand get directional drift accents; forest floors
## get half-buried roots. The profile stays broad and shallow by construction.
static func add_ridge(
	batch: MeshBatch,
	key: String,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	p3: Vector3,
	width: float,
	height: float,
	length_rings: int = 10,
	arc_segments: int = 6
) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for ring in length_rings + 1:
		var t := float(ring) / float(length_rings)
		var centre := _bezier(p0, p1, p2, p3, t)
		var tangent := _bezier_tangent(p0, p1, p2, p3, t)
		tangent.y = 0.0
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.RIGHT
		tangent = tangent.normalized()
		var side := tangent.cross(Vector3.UP).normalized()
		# Sine taper along the sweep: full body mid-run, feathered ends.
		var taper := sin(t * PI)
		var half_width := width * 0.5 * lerpf(0.35, 1.0, taper)
		var rise := height * taper
		for segment in arc_segments + 1:
			var arc := PI * float(segment) / float(arc_segments)
			var across := cos(arc)
			var lift := sin(arc)
			vertices.append(centre + side * (across * half_width)
				+ Vector3.UP * (lift * rise))
			var normal := (side * across
				+ Vector3.UP * (lift * maxf(half_width, 0.0001)
					/ maxf(rise, 0.0001))).normalized() if rise > 0.0005 \
				else Vector3.UP
			# Pull toward UP so the ridge takes most light from the sky — the
			# calm read; hard side shading made test waves look like hoses.
			normals.append((normal * 0.55 + Vector3.UP * 0.45).normalized())
	var stride := arc_segments + 1
	for ring in length_rings:
		var a0 := ring * stride
		var b0 := (ring + 1) * stride
		for segment in arc_segments:
			indices.append_array([
				a0 + segment, b0 + segment, b0 + segment + 1,
				a0 + segment, b0 + segment + 1, a0 + segment + 1,
			])
	batch.add(key, vertices, normals, indices)


## Squashed hemisphere dome. `flatness` 0 = full half-sphere, 1 = nearly flat
## disc. The workhorse for nubs, dots with slight relief, and lobed clumps.
static func add_dome(
	batch: MeshBatch,
	key: String,
	centre: Vector3,
	radius_x: float,
	radius_z: float,
	height: float,
	yaw: float,
	rings: int = 5,
	segments: int = 14
) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var basis := Basis(Vector3.UP, yaw)
	# Inverse transpose for normals of the non-uniform scale; for a diagonal
	# scale that is just the reciprocal per axis.
	var inv := Vector3(1.0 / maxf(radius_x, 0.0001), 1.0 / maxf(height, 0.0001),
		1.0 / maxf(radius_z, 0.0001))
	for ring in rings + 1:
		var pitch := (PI / 2.0) * float(ring) / float(rings)
		var ring_radius := cos(pitch)
		var ring_height := sin(pitch)
		for segment in segments:
			var angle := TAU * float(segment) / float(segments)
			var unit := Vector3(cos(angle) * ring_radius, ring_height,
				sin(angle) * ring_radius)
			vertices.append(centre + basis * Vector3(
				unit.x * radius_x, unit.y * height, unit.z * radius_z))
			normals.append((basis * (unit * inv)).normalized())
	for ring in rings:
		var a0 := ring * segments
		var b0 := (ring + 1) * segments
		for segment in segments:
			var next := (segment + 1) % segments
			indices.append_array([
				a0 + segment, a0 + next, b0 + next,
				a0 + segment, b0 + next, b0 + segment,
			])
	batch.add(key, vertices, normals, indices)


## One smooth grass blade: an elliptical cross-section swept along a cubic
## Bezier, tapering to a rounded tip.
##
## The profile is everything here. The rejected shapes bracket it from both
## sides — pure cushions read as pebbles, thin straight taper reads as straw —
## and this is the middle: a broad soft leaf that keeps most of its width
## through the body, then closes over the last rings into a rounded point
## rather than ending at a spike.
static func add_blade(
	batch: MeshBatch,
	key: String,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	p3: Vector3,
	width: float,
	thickness_ratio: float,
	length_rings: int = 8,
	ring_segments: int = 9,
	tip_rings: int = 2
) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var total_rings := length_rings + tip_rings

	# Width profile along the blade: full a third of the way up, then a long
	# smooth taper to roughly half width before the tip cap closes it. The
	# taper is what separates slender curved foliage from the fat-petal tulip
	# read; the wide rounded finish keeps it from ever becoming a spike or a
	# straight cone.
	var ring_data: Array = []
	for ring in total_rings + 1:
		var t := float(ring) / float(total_rings)
		var width_factor: float
		if ring <= length_rings:
			var body := float(ring) / float(length_rings)
			if body < 0.32:
				width_factor = lerpf(0.86, 1.0, body / 0.32)
			else:
				width_factor = lerpf(1.0, 0.52, pow((body - 0.32) / 0.68, 1.15))
		else:
			var tip := float(ring - length_rings) / float(tip_rings)
			# Hemispherical close over the tip rings: a rounded end, like a
			# fingertip, never a point.
			width_factor = 0.52 * cos(tip * PI / 2.0)
		ring_data.append([t, maxf(width_factor, 0.05)])

	var up := Vector3.UP
	for entry: Array in ring_data:
		var t: float = entry[0]
		var width_factor: float = entry[1]
		var centre := _bezier(p0, p1, p2, p3, t)
		var tangent := _bezier_tangent(p0, p1, p2, p3, t).normalized()
		var side := tangent.cross(up)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var binormal := side.cross(tangent).normalized()
		var half_width := width * width_factor * 0.5
		var half_thickness := half_width * thickness_ratio
		for segment in ring_segments:
			var angle := TAU * float(segment) / float(ring_segments)
			var local := side * (cos(angle) * half_width) \
				+ binormal * (sin(angle) * half_thickness)
			vertices.append(centre + local)
			# Ellipse normal blended toward UP. True surface normals give each
			# leaf a hard lit-and-shaded split that reads as plastic; pulling
			# them upward makes every leaf take most of its light from the sky,
			# which is the flat pastel foliage shading the art style runs on.
			var normal := (side * (cos(angle) / maxf(half_width, 0.0001)) \
				+ binormal * (sin(angle) / maxf(half_thickness, 0.0001))).normalized()
			normals.append((normal * 0.4 + Vector3.UP * 0.6).normalized())

	for ring in total_rings:
		var a0 := ring * ring_segments
		var b0 := (ring + 1) * ring_segments
		for segment in ring_segments:
			var next := (segment + 1) % ring_segments
			indices.append_array([
				a0 + segment, a0 + next, b0 + next,
				a0 + segment, b0 + next, b0 + segment,
			])

	# Tip cap: one vertex just past the last ring, normal along the tangent.
	var tip_centre := _bezier(p0, p1, p2, p3, 1.0)
	var tip_tangent := _bezier_tangent(p0, p1, p2, p3, 0.995).normalized()
	var tip_index := vertices.size()
	vertices.append(tip_centre + tip_tangent * width * 0.02)
	normals.append(tip_tangent)
	var last0 := total_rings * ring_segments
	for segment in ring_segments:
		var next := (segment + 1) % ring_segments
		indices.append_array([last0 + segment, last0 + next, tip_index])

	batch.add(key, vertices, normals, indices)


static func _bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		t: float) -> Vector3:
	var u := 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) \
		+ p2 * (3.0 * u * t * t) + p3 * (t * t * t)


static func _bezier_tangent(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		t: float) -> Vector3:
	var u := 1.0 - t
	return (p1 - p0) * (3.0 * u * u) + (p2 - p1) * (6.0 * u * t) \
		+ (p3 - p2) * (3.0 * t * t)
