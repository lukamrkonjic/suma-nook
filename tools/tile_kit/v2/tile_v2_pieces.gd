class_name TileV2Pieces
extends RefCounted
## Solid piece builders for assembly-built V2 tiles — the GG method.
##
## Garden-Galaxy-style tiles are ASSEMBLIES: discrete chunky solids (stones,
## bark chunks, snow caps, sand strokes, moss cushions) packed over a block
## bed. Each solid here is a closed lofted volume with its own silhouette,
## a real overhang where the material wants one, per-vertex tone (lit top →
## contact-shadowed base — the baked grounding GG pieces read by), and
## smooth or firm curvature per material.

const HALF := 0.85


## One lofted solid from a closed 2D outline:
##   spec = {
##     style: "cushion" | "stone",
##     rx, rz: half extents; height: top height above the bed
##     corner: rounding for stone outlines (blob outlines use scallop)
##     points: outline sample count (blob) / corner segments (stone)
##     scallop: blob outline irregularity 0..0.3
##     belly: max outward bulge scale at the waist (>1 = overhang)
##     top_scale: plan scale of the top cap
##     color: main tone; color_top optional lighter cap tone
##     sink: fraction of height pressed into the bed
##     tilt: radians of random lean
##     clip: clamp the outline inside the tile footprint (edge-cut stones)
##   }
static func add_solid(batch: TileV2Mesher.Batch, field: TileV2Field,
		at: Vector2, yaw: float, spec: Dictionary,
		rng: RandomNumberGenerator) -> void:
	var style := String(spec.get("style", "cushion"))
	var rx: float = spec.get("rx", 0.2)
	var rz: float = spec.get("rz", rx)
	var height: float = spec.get("height", 0.1)
	var color: Color = spec.get("color", Color.MAGENTA)
	var color_top: Color = spec.get("color_top", color.lightened(0.10))
	var contact := color.darkened(0.34)
	var sink: float = spec.get("sink", 0.16)
	var belly: float = spec.get("belly", 1.05 if style == "cushion" else 1.0)
	var top_scale: float = spec.get("top_scale",
		0.52 if style == "cushion" else 0.80)

	# Outline in local space.
	var outline := PackedVector2Array()
	if style == "stone":
		var segments: int = spec.get("points", 5)
		var data: Array = TileKitMeshUtils.rounded_rect_outline(
			1.0, clampf(float(spec.get("corner", 0.42)), 0.05, 0.95), segments)
		for point: Vector2 in data[0]:
			outline.append(Vector2(point.x * rx, point.y * rz))
	else:
		var points: int = spec.get("points", 18)
		var radii := TileKitMeshUtils.soft_blob_outline(rng, points,
			clampf(float(spec.get("scallop", 0.14)), 0.0, 0.3), 3)
		for index in points:
			var angle := TAU * float(index) / float(points)
			outline.append(Vector2(
				cos(angle) * rx * radii[index], sin(angle) * rz * radii[index]))

	# Placement frame: settle onto the bed, mild slope alignment, lean.
	var tilt: float = spec.get("tilt", 0.0)
	var frame := TileV2Structures.surface_frame(field, at, yaw, 0.45)
	if tilt != 0.0:
		frame.basis = frame.basis * Basis(Vector3.FORWARD, tilt)
	frame.origin += Vector3.UP * (-height * sink)

	# Optional footprint clip: stones meeting the tile edge get cut flush.
	var do_clip := bool(spec.get("clip", false))

	# Loft rings bottom → top. Ring spec: [t (0..1 of height), plan scale,
	# tone toward top (0 contact → 1 lit)].
	var profile: Array
	if style == "stone":
		profile = [
			[0.0, 0.985, 0.0],
			[0.42, 1.0, 0.35],
			[0.80, 0.995, 0.72],
			[0.93, 0.92, 0.92],
			[1.0, top_scale, 1.0],
		]
	else:
		profile = [
			[0.0, lerpf(1.0, belly, 0.5) * 0.94, 0.0],
			[0.22, belly, 0.30],
			[0.52, lerpf(belly, top_scale, 0.35), 0.62],
			[0.78, lerpf(belly, top_scale, 0.72), 0.86],
			[1.0, top_scale, 1.0],
		]

	var count := outline.size()
	var ring_count := profile.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for ring in ring_count:
		var entry: Array = profile[ring]
		var t: float = entry[0]
		var scale: float = entry[1]
		var tone: float = entry[2]
		var ring_color := contact.lerp(
			color.lerp(color_top, maxf(tone - 0.72, 0.0) / 0.28), tone)
		for index in count:
			var local2 := outline[index] * scale
			var world := frame * Vector3(local2.x, height * t, local2.y)
			if do_clip:
				world.x = clampf(world.x, -HALF + 0.004, HALF - 0.004)
				world.z = clampf(world.z, -HALF + 0.004, HALF - 0.004)
			vertices.append(world)
			colors.append(ring_color)
			normals.append(Vector3.UP)
	# Numeric smooth normals over the loft.
	for ring in ring_count:
		var below := maxi(ring - 1, 0)
		var above := mini(ring + 1, ring_count - 1)
		for index in count:
			var vertical := vertices[above * count + index] \
				- vertices[below * count + index]
			var around := vertices[ring * count + (index + 1) % count] \
				- vertices[ring * count + (index + count - 1) % count]
			var normal := vertical.cross(around)
			if normal.length_squared() < 0.000000001:
				normal = Vector3.UP
			normals[ring * count + index] = normal.normalized()
	for ring in ring_count - 1:
		var a0 := ring * count
		var b0 := (ring + 1) * count
		for index in count:
			var next := (index + 1) % count
			indices.append_array([
				a0 + index, a0 + next, b0 + next,
				a0 + index, b0 + next, b0 + index,
			])
	# Top cap fan.
	var top_first := vertices.size()
	var apex_local := Vector3(0.0, height, 0.0)
	vertices.append(frame * apex_local)
	normals.append((frame.basis * Vector3.UP).normalized())
	colors.append(color_top)
	var last0 := (ring_count - 1) * count
	for index in count:
		indices.append_array([top_first, last0 + index,
			last0 + (index + 1) % count])
	batch.add_patch(vertices, normals, colors, indices)


## A crisp raised sand stroke: a tapered round-profile loft along a curved
## path, resting ON the bed with a clean contact line — the GG sand swoosh.
static func add_stroke(batch: TileV2Mesher.Batch, field: TileV2Field,
		start: Vector2, end: Vector2, bow: float, width: float, height: float,
		color: Color, color_high: Color) -> void:
	var contact := color.darkened(0.22)
	var mid := (start + end) * 0.5
	var direction := (end - start).normalized()
	var side2 := Vector2(-direction.y, direction.x)
	var control := mid + side2 * bow
	var length_rings := 14
	var arc_segments := 7
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for ring in length_rings + 1:
		var t := float(ring) / float(length_rings)
		var u := 1.0 - t
		var p2 := start * (u * u) + control * (2.0 * u * t) + end * (t * t)
		var tangent2 := (control - start) * u + (end - control) * t
		if tangent2.length_squared() < 0.000001:
			tangent2 = direction
		tangent2 = tangent2.normalized()
		var across2 := Vector2(-tangent2.y, tangent2.x)
		var taper := sin(clampf(t, 0.03, 0.97) * PI)
		taper = pow(taper, 0.62)
		var half_width := width * 0.5 * taper
		var rise := height * taper
		var bed := field.height(p2) - 0.004
		for segment in arc_segments + 1:
			var arc := PI * float(segment) / float(arc_segments)
			var across := cos(arc)
			var lift := sin(arc)
			var p3 := Vector3(p2.x, bed, p2.y) \
				+ Vector3(across2.x, 0.0, across2.y) * (across * half_width) \
				+ Vector3.UP * (lift * rise)
			vertices.append(p3)
			var normal := (Vector3(across2.x, 0.0, across2.y) * across
				+ Vector3.UP * lift).normalized()
			normals.append(normal)
			colors.append(contact.lerp(
				color.lerp(color_high, maxf(lift - 0.55, 0.0) / 0.45),
				clampf(lift * 1.5, 0.12, 1.0)))
	var stride := arc_segments + 1
	for ring in length_rings:
		var a0 := ring * stride
		var b0 := (ring + 1) * stride
		for segment in arc_segments:
			indices.append_array([
				a0 + segment, b0 + segment, b0 + segment + 1,
				a0 + segment, b0 + segment + 1, a0 + segment + 1,
			])
	batch.add_patch(vertices, normals, colors, indices)
