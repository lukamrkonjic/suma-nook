class_name TileV2Structures
extends RefCounted
## Discrete material-structure pieces for V2 tiles: the chunky embedded
## elements a height field cannot express crisply (bark chips, gravel).
##
## Every piece SETTLES: it samples the sculpt field under its centre,
## aligns to the local slope, and sinks part of its height into the ground,
## so structure reads as material embedded in the tile — never as objects
## sprinkled on top. Placement comes exclusively from curated cluster
## templates in the library; nothing here scatters.

const SLOPE_PROBE := 0.05


## Local surface frame at a plan point: origin on the surface, Y along the
## surface normal (eased toward world-up), yaw applied around local up.
## Right-handed by construction: x × y = z.
static func surface_frame(field: TileV2Field, at: Vector2, yaw: float,
		align := 0.6) -> Transform3D:
	var h := field.height(at)
	var hx := field.height(at + Vector2(SLOPE_PROBE, 0.0))
	var hx2 := field.height(at - Vector2(SLOPE_PROBE, 0.0))
	var hz := field.height(at + Vector2(0.0, SLOPE_PROBE))
	var hz2 := field.height(at - Vector2(0.0, SLOPE_PROBE))
	var slope_normal := Vector3(hx2 - hx, 2.0 * SLOPE_PROBE, hz2 - hz).normalized()
	var up := Vector3.UP.slerp(slope_normal, clampf(align, 0.0, 1.0)).normalized()
	var reference := Vector3.RIGHT.rotated(Vector3.UP, yaw)
	var forward := (reference - up * reference.dot(up))
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	return Transform3D(Basis(forward, up, forward.cross(up)),
		Vector3(at.x, h, at.y))


## One chunky bark chip / stone chip: an irregular 5–6 sided prism with hard
## planar sides, a small bevel band, and a flat (slightly tilted) top face.
## Angular but never razor-edged — every exposed edge carries the bevel.
static func add_chip(batch: TileV2Mesher.Batch, color: Color,
		field: TileV2Field, at: Vector2, length: float, width: float,
		height: float, yaw: float, rng: RandomNumberGenerator,
		sink_fraction := 0.38) -> void:
	var points := 5 + (rng.randi() % 2)
	var frame := surface_frame(field, at, yaw, 0.55)
	frame.origin += Vector3.UP * (-height * sink_fraction)
	# Irregular convex plan: jittered angles and radii around an ellipse.
	var plan := PackedVector2Array()
	for index in points:
		var angle := TAU * (float(index) + rng.randf_range(-0.18, 0.18)) \
			/ float(points)
		var radius := rng.randf_range(0.82, 1.12)
		plan.append(Vector2(
			cos(angle) * length * 0.5 * radius,
			sin(angle) * width * 0.5 * radius))
	var bevel := minf(0.007, height * 0.35)
	var tilt := Vector2(rng.randf_range(-0.14, 0.14), rng.randf_range(-0.14, 0.14))
	var top_shrink := rng.randf_range(0.80, 0.90)
	var top_at := func(index: int) -> Vector3:
		var p := plan[index] * top_shrink
		return Vector3(p.x, height + p.x * tilt.x + p.y * tilt.y, p.y)
	var bevel_at := func(index: int) -> Vector3:
		var p := plan[index] * (top_shrink + 0.10)
		return Vector3(
			p.x, height - bevel + p.x * tilt.x + p.y * tilt.y, p.y)

	# Hard planar side facets (flat shading — deliberate, per the reference's
	# angular litter), soft bevel band, flat top fan.
	for index in points:
		var next := (index + 1) % points
		var a := frame * Vector3(plan[index].x, 0.0, plan[index].y)
		var b := frame * Vector3(plan[next].x, 0.0, plan[next].y)
		var c: Vector3 = frame * bevel_at.call(next)
		var d: Vector3 = frame * bevel_at.call(index)
		_flat_quad(batch, color, a, b, c, d)
	var top_centre := Vector3.ZERO
	for index in points:
		top_centre += top_at.call(index)
	top_centre = frame * (top_centre / float(points))
	var top_normal_local := Vector3(-tilt.x, 1.0, -tilt.y).normalized()
	var top_normal := (frame.basis * top_normal_local).normalized()
	var top_color := color.lightened(0.06)
	for index in points:
		var next := (index + 1) % points
		# Bevel band: blends side-facing into top-facing.
		var lower_a: Vector3 = frame * bevel_at.call(index)
		var lower_b: Vector3 = frame * bevel_at.call(next)
		var upper_b: Vector3 = frame * top_at.call(next)
		var upper_a: Vector3 = frame * top_at.call(index)
		var out_a := lower_a - frame.origin
		out_a.y = 0.0
		var out_b := lower_b - frame.origin
		out_b.y = 0.0
		var na := (out_a.normalized() * 0.6 + top_normal * 0.75).normalized()
		var nb := (out_b.normalized() * 0.6 + top_normal * 0.75).normalized()
		batch.add_triangle(lower_a, lower_b, upper_b, na, nb, top_normal,
			color, color, top_color)
		batch.add_triangle(lower_a, upper_b, upper_a, na, top_normal,
			top_normal, color, top_color, top_color)
		# Top fan (flat).
		batch.add_triangle(upper_a, upper_b, top_centre,
			top_normal, top_normal, top_normal,
			top_color, top_color, top_color)


## Small smooth settled pebble: a squashed dome pressed into the surface.
static func add_pebble(batch: TileV2Mesher.Batch, color: Color,
		field: TileV2Field, at: Vector2, radius: float, height: float,
		yaw: float, rng: RandomNumberGenerator) -> void:
	var frame := surface_frame(field, at, yaw, 0.7)
	frame.origin += Vector3.UP * (-height * 0.22)
	var stretch := rng.randf_range(0.8, 1.25)
	var rings := 4
	var segments := 10
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.append(frame * (Vector3.UP * height))
	normals.append((frame.basis * Vector3.UP).normalized())
	colors.append(color)
	# Rings descend from just under the apex to the ground contact.
	for ring in rings:
		var pitch := (PI / 2.0) * float(ring + 1) / float(rings)
		var ring_radius := sin(pitch)
		var ring_height := cos(pitch)
		for segment in segments:
			var angle := TAU * float(segment) / float(segments)
			var local := Vector3(
				cos(angle) * radius * stretch * ring_radius,
				height * ring_height,
				sin(angle) * radius / stretch * ring_radius)
			vertices.append(frame * local)
			var normal_local := Vector3(
				cos(angle) * ring_radius / maxf(radius * stretch, 0.0001),
				ring_height / maxf(height, 0.0001),
				sin(angle) * ring_radius / maxf(radius / stretch, 0.0001))
			normals.append((frame.basis * normal_local).normalized())
			colors.append(color)
	for segment in segments:
		indices.append_array([0, 1 + segment, 1 + (segment + 1) % segments])
	# Strip pattern is (lower, lower_next, upper_next) — ring r+1 is LOWER.
	for ring in rings - 1:
		var upper0 := 1 + ring * segments
		var lower0 := 1 + (ring + 1) * segments
		for segment in segments:
			var next := (segment + 1) % segments
			indices.append_array([
				lower0 + segment, lower0 + next, upper0 + next,
				lower0 + segment, upper0 + next, upper0 + segment,
			])
	batch.add_patch(vertices, normals, colors, indices)


static func _flat_quad(batch: TileV2Mesher.Batch, color: Color,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# Outward side facet under the clockwise front-face rule (winding matches
	# the ring-shell convention: lower → lower_next → upper_next).
	var normal := (c - a).cross(b - a)
	if normal.length_squared() < 0.000000001:
		return
	normal = normal.normalized()
	batch.add_triangle(a, b, c, normal, normal, normal, color, color, color)
	batch.add_triangle(a, c, d, normal, normal, normal, color, color, color)
