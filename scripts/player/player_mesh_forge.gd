class_name PlayerMeshForge
extends RefCounted
## Authored parametric mesh builders for the V2 player: lathed profile
## surfaces, swept limb tubes, and a profile-following scalp cap. All
## surfaces are closed, indexed, and smooth-shaded — no runtime SDF
## projection is involved anywhere.


## Revolves a smooth curve through (radius, y) control points. The profile
## is Catmull-Rom resampled so sparse authored points yield soft surfaces.
## `shape_scale` turns the circular section elliptical; `face_flatten`
## additionally compresses the -Z (facing) half for flattened face planes.
static func lathe(
	profile: Array,
	radial_segments: int,
	shape_scale: Vector3,
	face_flatten := 1.0,
	row_count := 22
) -> ArrayMesh:
	var rows := _resample_profile(profile, row_count)
	return _grid_mesh(rows, radial_segments, shape_scale, face_flatten)


## Partial lathe for hair: follows the same profile pushed outward by
## `thickness`, and each angular column stops at a hairline height blended
## between the front, side, and rear cut heights.
static func scalp(
	profile: Array,
	thickness: float,
	radial_segments: int,
	shape_scale: Vector3,
	face_flatten: float,
	cut_front: float,
	cut_side: float,
	cut_back: float
) -> ArrayMesh:
	var rows := _resample_profile(profile, 26)
	var top_y: float = rows[rows.size() - 1].y
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var row_steps := 12
	for column in range(radial_segments + 1):
		var phi := TAU * float(column) / float(radial_segments)
		var frontness := maxf(-sin(phi), 0.0)
		var backness := maxf(sin(phi), 0.0)
		var sideness := 1.0 - frontness - backness
		var cut_y := (
			cut_front * frontness + cut_back * backness + cut_side * sideness
		)
		for step in range(row_steps + 1):
			var y := lerpf(top_y - 0.0004, cut_y, float(step) / float(row_steps))
			var radius := _radius_at(rows, y) + thickness
			var point := Vector3(
				radius * cos(phi) * shape_scale.x,
				y * shape_scale.y,
				radius * sin(phi) * shape_scale.z
			)
			if point.z < 0.0:
				point.z *= face_flatten
			vertices.append(point)
	for column in range(radial_segments):
		var row_start := column * (row_steps + 1)
		var next_start := row_start + row_steps + 1
		for step in row_steps:
			var a := row_start + step
			var b := a + 1
			var c := next_start + step
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	return _finalize(vertices, indices)


## Sweeps a round section along a smooth curve through `points` with a
## per-point radius, closing both ends with rounded caps. Rebuilt per frame
## for limbs, so one continuous surface bends at the joints.
static func sweep(
	points: Array,
	radii: Array,
	radial_segments := 10,
	samples := 14
) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var previous_normal := _initial_normal(points)
	var rings: Array = []
	for sample_index in range(samples + 1):
		var t := float(sample_index) / float(samples)
		var center := _curve_point(points, t)
		var tangent := (
			_curve_point(points, minf(t + 0.01, 1.0))
			- _curve_point(points, maxf(t - 0.01, 0.0))
		).normalized()
		# Parallel transport keeps rings from twisting around the spine.
		var normal := (
			previous_normal - tangent * previous_normal.dot(tangent)
		).normalized()
		if not normal.is_finite() or normal.length_squared() < 0.5:
			normal = _initial_normal(points)
		previous_normal = normal
		var binormal := tangent.cross(normal).normalized()
		rings.append({
			"center": center,
			"normal": normal,
			"binormal": binormal,
			"tangent": tangent,
			"radius": _radius_lerp(radii, t),
		})

	var first: Dictionary = rings[0]
	var last: Dictionary = rings[rings.size() - 1]
	var cap_rows := 3
	var all_rows: Array = []
	for cap_step in range(cap_rows):
		var angle := PI * 0.5 * (1.0 - float(cap_step) / float(cap_rows))
		all_rows.append({
			"center": (
				first.center as Vector3
				- (first.tangent as Vector3) * sin(angle) * float(first.radius)
			),
			"normal": first.normal,
			"binormal": first.binormal,
			"radius": float(first.radius) * cos(angle),
		})
	all_rows.append_array(rings)
	for cap_step in range(1, cap_rows + 1):
		var angle := PI * 0.5 * float(cap_step) / float(cap_rows)
		all_rows.append({
			"center": (
				last.center as Vector3
				+ (last.tangent as Vector3) * sin(angle) * float(last.radius)
			),
			"normal": last.normal,
			"binormal": last.binormal,
			"radius": float(last.radius) * cos(angle),
		})

	for row: Dictionary in all_rows:
		for column in range(radial_segments + 1):
			var phi := TAU * float(column) / float(radial_segments)
			vertices.append(
				(row.center as Vector3)
				+ (
					(row.normal as Vector3) * cos(phi)
					+ (row.binormal as Vector3) * sin(phi)
				) * maxf(float(row.radius), 0.0004)
			)
	for row_index in range(all_rows.size() - 1):
		var row_start := row_index * (radial_segments + 1)
		var next_start := row_start + radial_segments + 1
		for column in radial_segments:
			var a := row_start + column
			var b := a + 1
			var c := next_start + column
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	return _finalize(vertices, indices)


static func _resample_profile(profile: Array, row_count: int) -> Array:
	var result: Array = []
	var count := profile.size()
	for row_index in range(row_count + 1):
		var t := float(row_index) / float(row_count) * float(count - 1)
		var segment := clampi(int(floor(t)), 0, count - 2)
		var local_t := t - float(segment)
		var p0: Vector2 = profile[maxi(segment - 1, 0)]
		var p1: Vector2 = profile[segment]
		var p2: Vector2 = profile[segment + 1]
		var p3: Vector2 = profile[mini(segment + 2, count - 1)]
		result.append(_catmull_rom(p0, p1, p2, p3, local_t))
	return result


static func _catmull_rom(
	p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float
) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		2.0 * p1
		+ (p2 - p0) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3
	)


static func _radius_at(rows: Array, y: float) -> float:
	for row_index in range(rows.size() - 1):
		var a: Vector2 = rows[row_index]
		var b: Vector2 = rows[row_index + 1]
		if (y >= a.y and y <= b.y) or (y <= a.y and y >= b.y):
			var span := b.y - a.y
			if absf(span) < 0.00001:
				return a.x
			return lerpf(a.x, b.x, (y - a.y) / span)
	if y > (rows[rows.size() - 1] as Vector2).y:
		return (rows[rows.size() - 1] as Vector2).x
	return (rows[0] as Vector2).x


static func _grid_mesh(
	rows: Array,
	radial_segments: int,
	shape_scale: Vector3,
	face_flatten: float
) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for row: Vector2 in rows:
		for column in range(radial_segments + 1):
			var phi := TAU * float(column) / float(radial_segments)
			var point := Vector3(
				maxf(row.x, 0.0004) * cos(phi) * shape_scale.x,
				row.y * shape_scale.y,
				maxf(row.x, 0.0004) * sin(phi) * shape_scale.z
			)
			if point.z < 0.0:
				point.z *= face_flatten
			vertices.append(point)
	for row_index in range(rows.size() - 1):
		var row_start := row_index * (radial_segments + 1)
		var next_start := row_start + radial_segments + 1
		for column in radial_segments:
			var a := row_start + column
			var b := a + 1
			var c := next_start + column
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	return _finalize(vertices, indices)


static func _curve_point(points: Array, t: float) -> Vector3:
	var count := points.size()
	if count == 1:
		return points[0]
	var scaled := t * float(count - 1)
	var segment := clampi(int(floor(scaled)), 0, count - 2)
	var local_t := scaled - float(segment)
	var p0: Vector3 = points[maxi(segment - 1, 0)]
	var p1: Vector3 = points[segment]
	var p2: Vector3 = points[segment + 1]
	var p3: Vector3 = points[mini(segment + 2, count - 1)]
	var t2 := local_t * local_t
	var t3 := t2 * local_t
	return 0.5 * (
		2.0 * p1
		+ (p2 - p0) * local_t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3
	)


static func _radius_lerp(radii: Array, t: float) -> float:
	var count := radii.size()
	if count == 1:
		return radii[0]
	var scaled := t * float(count - 1)
	var segment := clampi(int(floor(scaled)), 0, count - 2)
	return lerpf(
		float(radii[segment]), float(radii[segment + 1]), scaled - float(segment)
	)


static func _initial_normal(points: Array) -> Vector3:
	var tangent := (
		(points[points.size() - 1] as Vector3) - (points[0] as Vector3)
	).normalized()
	var helper := (
		Vector3.RIGHT if absf(tangent.dot(Vector3.UP)) > 0.9 else Vector3.UP
	)
	return helper.cross(tangent).normalized()


static func _finalize(
	vertices: PackedVector3Array,
	indices: PackedInt32Array
) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in vertices:
		tool.add_vertex(vertex)
	for index in indices:
		tool.add_index(index)
	tool.generate_normals()
	return tool.commit()
