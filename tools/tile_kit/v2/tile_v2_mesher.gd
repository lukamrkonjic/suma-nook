class_name TileV2Mesher
extends RefCounted
## Bakes a TileV2Field + body profile into coherent vertex-coloured meshes.
##
## Construction: one displaced grid IS the top surface (no flat cap, no
## relief blanket), its boundary ring welds vertex-for-vertex to a side
## skirt whose profile is recipe data (wall, lip, overhang, substrate
## reveal), and the body below the −0.18 stacking seam bakes separately as
## the persistent base. Colour lives per vertex — the field's paint
## compositor decides, boundaries interpolate smoothly, and the whole tile
## draws as ONE surface with the shared clay material.
##
## Winding follows the repo's verified clockwise-front-face conventions:
## up-facing grids emit [a, b, c, a, c, d]; outward ring strips emit
## lower → lower_next → upper_next (see TileKitMeshUtils).

const TILE := 1.70
const HALF := TILE / 2.0
const BODY_BOTTOM := -0.50
const SEAM := -0.18


## One accumulating vertex-coloured mesh.
class Batch:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func add_triangle(a: Vector3, b: Vector3, c: Vector3,
			na: Vector3, nb: Vector3, nc: Vector3,
			ca: Color, cb: Color, cc: Color) -> void:
		var offset := vertices.size()
		vertices.append(a)
		vertices.append(b)
		vertices.append(c)
		normals.append(na)
		normals.append(nb)
		normals.append(nc)
		colors.append(ca)
		colors.append(cb)
		colors.append(cc)
		indices.append(offset)
		indices.append(offset + 1)
		indices.append(offset + 2)

	func add_patch(patch_vertices: PackedVector3Array,
			patch_normals: PackedVector3Array, patch_colors: PackedColorArray,
			patch_indices: PackedInt32Array) -> void:
		var offset := vertices.size()
		vertices.append_array(patch_vertices)
		normals.append_array(patch_normals)
		colors.append_array(patch_colors)
		for index in patch_indices:
			indices.append(index + offset)

	func commit(material: Material) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if vertices.is_empty():
			return mesh
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		return mesh

	func triangle_count() -> int:
		return indices.size() / 3


## Result carrier for one build.
class Result:
	var surface_batch := Batch.new()
	var base_batch := Batch.new()
	var boundary_points := PackedVector2Array()
	var boundary_heights := PackedFloat32Array()
	var boundary_outwards := PackedVector2Array()
	var boundary_carries := PackedFloat32Array()
	var max_height := 0.0
	var min_height := 0.0


## body spec keys:
##   chamfer: float                     bottom chamfer size
##   lower_key / side_key: String       below-seam colours
##   upper_rings: Array[Dictionary]     bottom-up skirt rings seam→rim, each
##       {t: 0..1 fraction of rim height, out: outward offset, out_carry:
##        extra outward where edge-carry lobes cross, key: band colour,
##        key_carry: optional colour blended in by local carry weight}
##   The rim ring (t = 1, out = 0) is implicit and welds to the top grid.
static func build(field: TileV2Field, body: Dictionary, resolution: int) -> Result:
	var result := Result.new()
	_build_top(field, resolution, result)
	_build_skirt(field, body, result)
	_build_base(field, body, result)
	return result


static func color_of(key: String) -> Color:
	return TileV2Palette.color(key)


# --- top surface -------------------------------------------------------------


static func _build_top(field: TileV2Field, resolution: int,
		result: Result) -> void:
	var cells := maxi(resolution, 24)
	var stride := cells + 1
	var step := TILE / float(cells)
	var positions := PackedVector3Array()
	positions.resize(stride * stride)
	var vertex_colors := PackedColorArray()
	vertex_colors.resize(stride * stride)

	for row in stride:
		for column in stride:
			var raw := Vector2(-HALF + column * step, -HALF + row * step)
			var p := field.clip_to_plan(raw)
			field.sample_into(p.x, p.y)
			var h := field.out_height
			positions[row * stride + column] = Vector3(p.x, h, p.y)
			vertex_colors[row * stride + column] = field.out_color
			result.max_height = maxf(result.max_height, h)
			result.min_height = minf(result.min_height, h)

	# Smooth normals from grid neighbours — one field sample per vertex total.
	var normals := PackedVector3Array()
	normals.resize(stride * stride)
	for row in stride:
		for column in stride:
			var left := positions[row * stride + maxi(column - 1, 0)]
			var right := positions[row * stride + mini(column + 1, cells)]
			var back := positions[maxi(row - 1, 0) * stride + column]
			var front := positions[mini(row + 1, cells) * stride + column]
			var dx := right - left
			var dz := front - back
			var normal := dz.cross(dx)
			if normal.length_squared() < 0.0000001 or normal.y <= 0.0:
				normal = Vector3.UP
			normals[row * stride + column] = normal.normalized()

	for row in cells:
		for column in cells:
			var a := row * stride + column
			var b := row * stride + column + 1
			var c := (row + 1) * stride + column + 1
			var d := (row + 1) * stride + column
			_emit_top_triangle(result.surface_batch, positions, normals,
				vertex_colors, a, b, c)
			_emit_top_triangle(result.surface_batch, positions, normals,
				vertex_colors, a, c, d)

	# Boundary ring (counter-clockwise, matching rounded_rect_outline's
	# direction): row 0 → +x, column N → +z, row N → −x, column 0 → −z.
	var ring_indices := PackedInt32Array()
	for column in stride:
		ring_indices.append(column)
	for row in range(1, stride):
		ring_indices.append(row * stride + cells)
	for column in range(cells - 1, -1, -1):
		ring_indices.append(cells * stride + column)
	for row in range(cells - 1, 0, -1):
		ring_indices.append(row * stride)
	# Weld near-duplicate boundary verts (grid corners clip several verts
	# onto almost the same outline point): duplicates make degenerate skirt
	# quads and streaked corner normals.
	var previous := Vector3(INF, INF, INF)
	for ring_index in ring_indices:
		var position := positions[ring_index]
		if position.distance_squared_to(previous) < 0.000004:
			continue
		previous = position
		var p2 := Vector2(position.x, position.z)
		result.boundary_points.append(p2)
		result.boundary_heights.append(position.y)
		result.boundary_outwards.append(_outward_at(p2, field.corner_radius))
		result.boundary_carries.append(field.carry_at(p2))
	# The walk closes on itself; drop the tail if it welds onto the head.
	if result.boundary_points.size() > 2:
		var head := Vector3(result.boundary_points[0].x,
			result.boundary_heights[0], result.boundary_points[0].y)
		var tail_index := result.boundary_points.size() - 1
		var tail := Vector3(result.boundary_points[tail_index].x,
			result.boundary_heights[tail_index],
			result.boundary_points[tail_index].y)
		if head.distance_squared_to(tail) < 0.000004:
			result.boundary_points.remove_at(tail_index)
			result.boundary_heights.remove_at(tail_index)
			result.boundary_outwards.remove_at(tail_index)
			result.boundary_carries.remove_at(tail_index)


static func _emit_top_triangle(batch: Batch, positions: PackedVector3Array,
		normals: PackedVector3Array, vertex_colors: PackedColorArray,
		a: int, b: int, c: int) -> void:
	var pa := positions[a]
	var pb := positions[b]
	var pc := positions[c]
	# Clipped corner verts collapse onto the outline; skip the degenerates.
	if pa.distance_squared_to(pb) < 0.00000004 \
			or pb.distance_squared_to(pc) < 0.00000004 \
			or pc.distance_squared_to(pa) < 0.00000004:
		return
	batch.add_triangle(pa, pb, pc, normals[a], normals[b], normals[c],
		vertex_colors[a], vertex_colors[b], vertex_colors[c])


## Outward direction of the rounded-rect plan at a boundary point: axis
## normals on the straight edges, radial in the corner arcs.
static func _outward_at(p: Vector2, corner: float) -> Vector2:
	var inner := HALF - corner
	var q := Vector2(absf(p.x) - inner, absf(p.y) - inner)
	if q.x > 0.0 and q.y > 0.0:
		var radial := q.normalized()
		return Vector2(radial.x * signf(p.x), radial.y * signf(p.y))
	if absf(p.x) > absf(p.y):
		return Vector2(signf(p.x), 0.0)
	return Vector2(0.0, signf(p.y))


# --- skirt (seam → rim) ------------------------------------------------------


static func _build_skirt(field: TileV2Field, body: Dictionary,
		result: Result) -> void:
	var count := result.boundary_points.size()
	if count < 3:
		return
	var side_color := color_of(String(body.get("side_key", "rock_side")))
	var upper_rings: Array = body.get("upper_rings", [])
	# Ring stack bottom-up: seam ring, authored rings, implicit rim ring.
	var specs: Array = [{"t": 0.0, "out": 0.0, "out_carry": 0.0,
		"color": side_color}]
	for ring: Dictionary in upper_rings:
		var spec := {
			"t": ring.get("t", 0.5),
			"out": ring.get("out", 0.0),
			"out_carry": ring.get("out_carry", 0.0),
			"color": color_of(String(ring.get("key", "rock_side"))),
		}
		if ring.has("key_carry"):
			spec["color_carry"] = color_of(String(ring["key_carry"]))
		specs.append(spec)
	specs.append({"t": 1.0, "out": 0.0, "out_carry": 0.0,
		"color": specs.back()["color"],
		"color_carry": specs.back().get("color_carry")})

	# Positions ring-major, bottom-up; colours per vertex (carry can tint a
	# ring exactly where a carried lobe rolls over the rim).
	var ring_count := specs.size()
	var ring_positions := PackedVector3Array()
	ring_positions.resize(ring_count * count)
	var ring_colors := PackedColorArray()
	ring_colors.resize(ring_count * count)
	for ring in ring_count:
		var spec: Dictionary = specs[ring]
		var t: float = spec["t"]
		var out: float = spec["out"]
		var out_carry: float = spec["out_carry"]
		var base_color: Color = spec["color"]
		var carry_color: Variant = spec.get("color_carry")
		for index in count:
			var p := result.boundary_points[index]
			var rim_y := result.boundary_heights[index]
			var carry := result.boundary_carries[index]
			var y := SEAM + t * (rim_y - SEAM)
			var reach := out + out_carry * carry
			var outward := result.boundary_outwards[index]
			if ring == ring_count - 1:
				# The rim ring welds exactly onto the top grid boundary.
				ring_positions[ring * count + index] = Vector3(p.x, rim_y, p.y)
			else:
				ring_positions[ring * count + index] = Vector3(
					p.x + outward.x * reach, y, p.y + outward.y * reach)
			var color := base_color
			if carry_color is Color:
				color = base_color.lerp(carry_color,
					smoothstep(0.15, 0.75, carry))
			ring_colors[ring * count + index] = color

	_emit_ring_stack(result.surface_batch, ring_positions, ring_colors,
		result.boundary_outwards, ring_count, count)


## Emits a ring stack as one smooth strip: numeric per-vertex normals,
## per-vertex colours, ring 0 = LOWEST (winding contract of the repo).
static func _emit_ring_stack(batch: Batch, ring_positions: PackedVector3Array,
		ring_colors: PackedColorArray, outwards: PackedVector2Array,
		ring_count: int, count: int) -> void:
	var ring_normals := PackedVector3Array()
	ring_normals.resize(ring_count * count)
	for ring in ring_count:
		var below := maxi(ring - 1, 0)
		var above := mini(ring + 1, ring_count - 1)
		for index in count:
			var vertical := ring_positions[above * count + index] \
				- ring_positions[below * count + index]
			var around := ring_positions[ring * count + (index + 1) % count] \
				- ring_positions[ring * count + (index + count - 1) % count]
			var normal := vertical.cross(around)
			if normal.length_squared() < 0.0000000001:
				var outward := outwards[index]
				normal = Vector3(outward.x, 0.0, outward.y)
			ring_normals[ring * count + index] = normal.normalized()
	var indices := PackedInt32Array()
	for ring in ring_count - 1:
		var a0 := ring * count
		var b0 := (ring + 1) * count
		for index in count:
			var next := (index + 1) % count
			indices.append_array([
				a0 + index, a0 + next, b0 + next,
				a0 + index, b0 + next, b0 + index,
			])
	batch.add_patch(ring_positions, ring_normals, ring_colors, indices)


# --- structural base (BODY_BOTTOM → seam) ------------------------------------


static func _build_base(field: TileV2Field, body: Dictionary,
		result: Result) -> void:
	var count := result.boundary_points.size()
	if count < 3:
		return
	var chamfer: float = body.get("chamfer", 0.016)
	var lower_color := color_of(String(body.get("lower_key", "rock_deep")))
	var side_color := color_of(String(body.get("side_key", "rock_side")))
	var side_split := lerpf(BODY_BOTTOM, SEAM, 0.42)
	var rings: Array = [
		[BODY_BOTTOM, chamfer, lower_color],
		[BODY_BOTTOM + chamfer, 0.0, lower_color],
		[side_split, 0.0, side_color],
		[SEAM, 0.0, side_color],
	]
	var ring_count := rings.size()
	var ring_positions := PackedVector3Array()
	ring_positions.resize(ring_count * count)
	var ring_colors := PackedColorArray()
	ring_colors.resize(ring_count * count)
	for ring in ring_count:
		var spec: Array = rings[ring]
		var y: float = spec[0]
		var inset: float = spec[1]
		for index in count:
			var p := result.boundary_points[index]
			var outward := result.boundary_outwards[index]
			ring_positions[ring * count + index] = Vector3(
				p.x - outward.x * inset, y, p.y - outward.y * inset)
			ring_colors[ring * count + index] = spec[2]
	_emit_ring_stack(result.base_batch, ring_positions, ring_colors,
		result.boundary_outwards, ring_count, count)

	# Bottom cap (down-facing, at the chamfer inset) and a flush seam lid
	# (up-facing) so the body stays watertight when a covering tile hides
	# the surface mesh.
	_add_cap(result.base_batch, lower_color, result, chamfer, BODY_BOTTOM, false)
	_add_cap(result.base_batch, side_color, result, 0.0, SEAM, true)


static func _add_cap(batch: Batch, color: Color, result: Result,
		inset: float, y: float, facing_up: bool) -> void:
	var count := result.boundary_points.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var normal := Vector3.UP if facing_up else Vector3.DOWN
	vertices.append(Vector3(0.0, y, 0.0))
	normals.append(normal)
	colors.append(color)
	for index in count:
		var p := result.boundary_points[index]
		var outward := result.boundary_outwards[index]
		vertices.append(Vector3(p.x - outward.x * inset, y, p.y - outward.y * inset))
		normals.append(normal)
		colors.append(color)
	for index in count:
		var next := (index + 1) % count
		if facing_up:
			indices.append_array([0, 1 + index, 1 + next])
		else:
			indices.append_array([0, 1 + next, 1 + index])
	batch.add_patch(vertices, normals, colors, indices)
