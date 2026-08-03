class_name TileV2GGPieces
extends RefCounted
## Piece vocabulary for the GG construction reboot (see
## docs/TILE_ART_V2_DIRECTION.md). Three chunky builders, nothing round:
##
##   slab   — an N-gon flat-topped solid with a controlled bevel band and
##            an optional SLOPED top plane (wedge): bark slabs, stone
##            slabs, snow sections, terraced sand shelves.
##   tuft   — a clump of 3–7 fused low rounded bumps as ONE mesh: the
##            moss/grass floret cluster. Bumps are squat truncated forms,
##            never spheres.
##
## Every piece settles onto the bed, sinks part of its height, and bakes
## contact darkening into its base vertices — grounded, embedded, layered.

const HALF := 0.85


## spec:
##   sides: int (5–8) | radii: optional explicit per-corner radius factors
##   rx, rz: half extents; height: thickness above the bed
##   bevel: bevel band width (moderate — 0.010..0.022)
##   slope: Vector2 — top-plane gradient (wedge terracing), m per m
##   crown: extra centre lift of the top plane
##   tone: Color; sink: fraction of height buried; tilt: radians
##   clip: clamp inside the tile footprint (edge-cut pieces)
static func add_slab(batch: TileV2Mesher.Batch, field: TileV2Field,
		at: Vector2, yaw: float, spec: Dictionary,
		rng: RandomNumberGenerator) -> void:
	var sides: int = spec.get("sides", 6)
	var rx: float = spec.get("rx", 0.16)
	var rz: float = spec.get("rz", rx * 0.75)
	var height: float = spec.get("height", 0.045)
	var bevel: float = clampf(float(spec.get("bevel", 0.014)), 0.006,
		height * 0.6)
	var slope: Vector2 = spec.get("slope", Vector2.ZERO)
	var crown: float = spec.get("crown", height * 0.06)
	var tone: Color = spec.get("tone", Color.MAGENTA)
	var side_tone := tone.darkened(0.16)
	var contact := tone.darkened(0.34)
	var top_tone := tone.lightened(0.05)

	var plan := PackedVector2Array()
	var radii: Array = spec.get("radii", [])
	for index in sides:
		var angle := TAU * (float(index) + rng.randf_range(-0.10, 0.10)) \
			/ float(sides)
		var radius := float(radii[index]) if index < radii.size() \
			else rng.randf_range(0.86, 1.10)
		plan.append(Vector2(cos(angle) * rx * radius, sin(angle) * rz * radius))

	var frame := TileV2Structures.surface_frame(field, at, yaw, 0.5)
	var tilt: float = spec.get("tilt", 0.0)
	if tilt != 0.0:
		frame.basis = frame.basis * Basis(Vector3.FORWARD, tilt)
	# lift stacks a piece on pieces beneath it (layered sheets).
	frame.origin += Vector3.UP * (float(spec.get("lift", 0.0))
		- height * float(spec.get("sink", 0.18)))
	var do_clip := bool(spec.get("clip", false))

	var top_y := func(local: Vector2) -> float:
		return height + local.x * slope.x + local.y * slope.y
	var to_world := func(local: Vector2, y: float) -> Vector3:
		var world := frame * Vector3(local.x, y, local.y)
		if do_clip:
			world.x = clampf(world.x, -HALF + 0.004, HALF - 0.004)
			world.z = clampf(world.z, -HALF + 0.004, HALF - 0.004)
		return world

	# Side facets: base ring → bevel-start ring (hard planar shading with
	# contact darkening), then the bevel band easing into the top plane.
	var top_plane_normal := (frame.basis * Vector3(-slope.x, 1.0, -slope.y)
		).normalized()
	var top_centre_local := Vector2.ZERO
	for point in plan:
		top_centre_local += point
	top_centre_local /= float(sides)
	var top_centre: Vector3 = to_world.call(top_centre_local * 0.2,
		float(top_y.call(top_centre_local * 0.2)) + crown)
	for index in sides:
		var next := (index + 1) % sides
		var pa := plan[index]
		var pb := plan[next]
		var bevel_a := pa * (1.0 - bevel / maxf(pa.length(), 0.03))
		var bevel_b := pb * (1.0 - bevel / maxf(pb.length(), 0.03))
		var base_a: Vector3 = to_world.call(pa, 0.0)
		var base_b: Vector3 = to_world.call(pb, 0.0)
		var lip_a: Vector3 = to_world.call(pa,
			float(top_y.call(pa)) - bevel * 0.9)
		var lip_b: Vector3 = to_world.call(pb,
			float(top_y.call(pb)) - bevel * 0.9)
		var top_a: Vector3 = to_world.call(bevel_a, float(top_y.call(bevel_a)))
		var top_b: Vector3 = to_world.call(bevel_b, float(top_y.call(bevel_b)))
		# Wall (flat-shaded plane).
		var wall_normal := (lip_a - base_a).cross(base_b - base_a)
		if wall_normal.length_squared() > 0.000000001:
			wall_normal = wall_normal.normalized()
			batch.add_triangle(base_a, base_b, lip_b,
				wall_normal, wall_normal, wall_normal, contact, contact, side_tone)
			batch.add_triangle(base_a, lip_b, lip_a,
				wall_normal, wall_normal, wall_normal, contact, side_tone, side_tone)
		# Bevel band (blends wall normal into the top plane normal).
		var bevel_normal := (wall_normal * 0.55 + top_plane_normal * 0.8
			).normalized()
		batch.add_triangle(lip_a, lip_b, top_b,
			bevel_normal, bevel_normal, top_plane_normal,
			side_tone, side_tone, top_tone)
		batch.add_triangle(lip_a, top_b, top_a,
			bevel_normal, top_plane_normal, top_plane_normal,
			side_tone, top_tone, top_tone)
		# Top fan (near-flat plane with a whisper of crown).
		batch.add_triangle(top_a, top_b, top_centre,
			top_plane_normal, top_plane_normal, top_plane_normal,
			top_tone, top_tone, top_tone)


## A clump of fused squat bumps as one mesh. bumps: Array of
## [offset: Vector2, radius, height]. Bumps overlap; shared contact
## shading at their skirts makes the clump read as one grown mass.
static func add_tuft_clump(batch: TileV2Mesher.Batch, field: TileV2Field,
		at: Vector2, yaw: float, bumps: Array, tone: Color,
		rng: RandomNumberGenerator) -> void:
	var contact := tone.darkened(0.30)
	var top_tone := tone.lightened(0.08)
	var frame := TileV2Structures.surface_frame(field, at, yaw, 0.5)
	var segments := 10
	for bump: Array in bumps:
		var offset: Vector2 = bump[0]
		var radius: float = bump[1]
		var height: float = bump[2]
		var squash := rng.randf_range(0.86, 1.16)
		# Squat truncated loft: wide base, waist, narrow ROUNDED-FLAT top —
		# a floret, not a sphere.
		var rings := [
			[1.00, 0.00, 0.0],
			[1.04, 0.30, 0.35],
			[0.92, 0.66, 0.72],
			[0.62, 0.92, 0.94],
			[0.00, 1.00, 1.0],
		]
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		var start_angle := rng.randf_range(0.0, TAU)
		for ring_index in rings.size():
			var entry: Array = rings[ring_index]
			var scale: float = entry[0]
			var y_t: float = entry[1]
			var tone_t: float = entry[2]
			var ring_color := contact.lerp(
				tone.lerp(top_tone, maxf(tone_t - 0.7, 0.0) / 0.3), tone_t)
			for segment in segments:
				var angle := start_angle + TAU * float(segment) / float(segments)
				var local := Vector3(
					offset.x + cos(angle) * radius * scale * squash,
					height * y_t - height * 0.14,
					offset.y + sin(angle) * radius * scale / squash)
				vertices.append(frame * local)
				normals.append(Vector3.UP)
				colors.append(ring_color)
		for ring_index in rings.size():
			var below := maxi(ring_index - 1, 0)
			var above := mini(ring_index + 1, rings.size() - 1)
			for segment in segments:
				var vertical := vertices[above * segments + segment] \
					- vertices[below * segments + segment]
				var around := vertices[ring_index * segments
					+ (segment + 1) % segments] \
					- vertices[ring_index * segments
					+ (segment + segments - 1) % segments]
				var normal := vertical.cross(around)
				if normal.length_squared() < 0.000000001:
					normal = (frame.basis * Vector3.UP).normalized()
				normals[ring_index * segments + segment] = normal.normalized()
		for ring_index in rings.size() - 1:
			var a0 := ring_index * segments
			var b0 := (ring_index + 1) * segments
			for segment in segments:
				var next := (segment + 1) % segments
				indices.append_array([
					a0 + segment, a0 + next, b0 + next,
					a0 + segment, b0 + next, b0 + segment,
				])
		batch.add_patch(vertices, normals, colors, indices)
