@tool
class_name TileLayerGenerator
extends RefCounted
## Base class every geometry family implements.
##
## The contract is deliberately narrow. A generator answers what it CONTRIBUTES
## — height, meshes, instances, collision — and never decides how the result is
## materialised, named, merged, or saved. That is why adding a new family is a
## one-file change: register an id, implement the hooks you need, and every
## recipe, the baker, the validator, and the lab pick it up unchanged.
##
## Implement `kinds()` honestly. The pipeline uses it to decide which passes to
## run, and the validator uses it to catch a recipe that asks a mesh generator
## for a height contribution.

## Registry id. Must be unique and stable; recipes store this string.
func generator_id() -> String:
	return "abstract"


## Which passes this generator participates in.
func kinds() -> Array:
	return [TileForgeConstants.Kind.HEIGHTFIELD]


func handles_kind(kind: int) -> bool:
	return kinds().has(kind)


## Human-readable one-liner shown in the lab and in the registry report.
func description() -> String:
	return ""


## Return an array of problem strings. Empty means the layer is usable.
## Validation runs BEFORE any geometry is built, so a bad recipe fails fast
## with a message naming the layer rather than crashing mid-bake.
func validate(_layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> PackedStringArray:
	return PackedStringArray()


## HEIGHTFIELD pass. Write into `ctx.field`. The pipeline has already sized the
## field and will re-lock the boundary afterwards, so a generator should apply
## its own shape and let the shared code own the seam.
func generate_height(_layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> void:
	pass


## MESH pass. Return geometry in LIVE space relative to the tile centre.
func generate_mesh(_layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> Array[TileMeshPart]:
	return []


## INSTANCE pass. Return placed modules; the baker turns them into merged
## meshes, MultiMeshes, or debug nodes according to the rule's output mode.
func generate_instances(
	_layer: TileSurfaceLayer,
	_rule: TileDetailRule,
	_ctx: TileGenerationContext
) -> Array[TileModuleInstance]:
	return []


## Extra collision beyond the recipe's collision_mode. Each entry is
## {"shape": Shape3D, "transform": Transform3D, "layer": int}.
func generate_collision(_layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> Array:
	return []


## Local-space bounds this layer expects to occupy. Used by the validator to
## catch geometry that will cross the tile boundary before it is built.
func get_bounds(_layer: TileSurfaceLayer, ctx: TileGenerationContext) -> AABB:
	var extent := ctx.half_extent
	return AABB(
		Vector3(-extent, -0.2, -extent),
		Vector3(extent * 2.0, 0.4, extent * 2.0)
	)


func get_debug_info(_layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> Dictionary:
	return {"generator": generator_id()}


# --- Shared helpers available to every generator ------------------------------

## Builds a triangulated mesh from the shared heightfield, grouped into one
## surface per material slot. Diagonal choice per quad minimises the height
## difference across the split, which keeps a ridge reading as a ridge instead
## of picking up a herringbone from a fixed triangulation.
static func build_field_mesh(
	field: TileHeightField,
	smooth: bool,
	y_offset := 0.0
) -> TileMeshPart:
	var tools: Dictionary = {}
	var slot_order := PackedStringArray()
	var resolution := field.resolution

	for j in resolution - 1:
		for i in resolution - 1:
			if (
				field.is_hole(i, j)
				or field.is_hole(i + 1, j)
				or field.is_hole(i, j + 1)
				or field.is_hole(i + 1, j + 1)
			):
				continue
			var slot := _dominant_slot(field, i, j)
			if not tools.has(slot):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[slot] = tool
				slot_order.append(slot)
			var surface: SurfaceTool = tools[slot]
			var p00 := _vertex(field, i, j, y_offset)
			var p10 := _vertex(field, i + 1, j, y_offset)
			var p01 := _vertex(field, i, j + 1, y_offset)
			var p11 := _vertex(field, i + 1, j + 1, y_offset)
			# Split along the shorter height diagonal. Vertex order matches the
			# engine's front-face winding — the same order the side wall and the
			# chamfer use — so an upward-facing top is not silently culled.
			if absf(p00.y - p11.y) <= absf(p10.y - p01.y):
				_triangle(surface, field, p00, p10, p11, smooth)
				_triangle(surface, field, p00, p11, p01, smooth)
			else:
				_triangle(surface, field, p00, p10, p01, smooth)
				_triangle(surface, field, p10, p11, p01, smooth)

	if slot_order.is_empty():
		return null
	var mesh := ArrayMesh.new()
	for slot in slot_order:
		var tool: SurfaceTool = tools[slot]
		if smooth:
			tool.index()
		# Normals are written per vertex above — analytically from the field for
		# a smooth top, per face for a flat one. Regenerating them here would
		# discard the analytic normals that make a broad mound shade smoothly.
		# No tangents either: this geometry carries no normal map and no UVs.
		tool.commit(mesh)
		mesh.surface_set_name(mesh.get_surface_count() - 1, slot)
	return TileMeshPart.make(mesh, slot_order, "surface")


## The chamfered rim that turns a flat top into a miniature.
##
## The field covers only the INNER area; this ring carries it out to the true
## boundary while dropping by `bevel`, so the widest point of the tile is still
## exactly ±half_extent and the square footprint is untouched. What changes is
## that the top perimeter now has a facet angled towards the key light, which is
## the single difference between a collectible object and an untreated cube.
##
## The ring is emitted as its own material slot so the rim can take a slightly
## lighter value than the top — a real highlight rather than a painted one.
static func build_top_chamfer(
	field: TileHeightField,
	full_extent: float,
	bevel: float,
	segments: int,
	slot: String
) -> TileMeshPart:
	if bevel <= 0.0005 or full_extent <= field.half_extent + 0.0001:
		return null
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := field.half_extent
	var steps: int = maxi(1, segments)
	var resolution := field.resolution

	# Walk the four edges of the field's outer ring. Each edge segment becomes a
	# short chamfer strip subdivided `segments` times, so the rim catches a
	# graded highlight instead of one hard facet.
	for side in 4:
		for index in resolution - 1:
			var a := _ring_point(field, side, index)
			var b := _ring_point(field, side, index + 1)
			for step in steps:
				var t0 := float(step) / float(steps)
				var t1 := float(step + 1) / float(steps)
				var a0 := _chamfer_point(a, inner, full_extent, bevel, t0)
				var a1 := _chamfer_point(a, inner, full_extent, bevel, t1)
				var b0 := _chamfer_point(b, inner, full_extent, bevel, t0)
				var b1 := _chamfer_point(b, inner, full_extent, bevel, t1)
				_quad(tool, a0, b0, b1, a1)
	tool.generate_normals()
	var mesh := ArrayMesh.new()
	tool.commit(mesh)
	if mesh.get_surface_count() == 0:
		return null
	mesh.surface_set_name(0, slot)
	var part := TileMeshPart.make(mesh, PackedStringArray([slot]), "surface")
	part.smooth_shading = false
	return part


## One point on the field's outer ring, with its height, walking side by side.
static func _ring_point(field: TileHeightField, side: int, index: int) -> Vector3:
	var last := field.resolution - 1
	match side:
		0:  # south, running +X
			return Vector3(field.world_axis(index), field.heights[field.index_of(index, 0)], -field.half_extent)
		1:  # east, running +Z
			return Vector3(field.half_extent, field.heights[field.index_of(last, index)], field.world_axis(index))
		2:  # north, running -X
			var flipped := last - index
			return Vector3(field.world_axis(flipped), field.heights[field.index_of(flipped, last)], field.half_extent)
		_:  # west, running -Z
			var back := last - index
			return Vector3(-field.half_extent, field.heights[field.index_of(0, back)], field.world_axis(back))


## Interpolates a rim point from the field boundary out to the true tile
## boundary. The outward direction is the axis the point is already extreme on,
## so corners move diagonally and stay exact.
static func _chamfer_point(
	point: Vector3,
	inner: float,
	full: float,
	bevel: float,
	t: float
) -> Vector3:
	var outward := Vector3.ZERO
	if absf(absf(point.x) - inner) < 0.0001:
		outward.x = signf(point.x)
	if absf(absf(point.z) - inner) < 0.0001:
		outward.z = signf(point.z)
	var reach := full - inner
	# A quarter-circle rather than a straight chamfer: the highlight rolls off
	# instead of terminating, which is what makes the edge read as soft without
	# rounding the silhouette away.
	var curve := sin(t * PI * 0.5)
	var drop := 1.0 - cos(t * PI * 0.5)
	return Vector3(
		point.x + outward.x * reach * curve,
		point.y - bevel * drop,
		point.z + outward.z * reach * curve
	)


## The structural body below the seam: a straight wall and a chamfer at the
## bottom so a tile lifts off its neighbour instead of welding to it.
static func build_block_body(
	full_extent: float,
	top_y: float,
	bottom_y: float,
	bevel: float,
	segments: int,
	side_slot: String,
	underside_slot: String,
	generate_underside: bool
) -> Array[TileMeshPart]:
	var parts: Array[TileMeshPart] = []
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var chamfer: float = clampf(bevel, 0.0, (top_y - bottom_y) * 0.4)
	var wall_bottom := bottom_y + chamfer
	var corners := [
		Vector2(-full_extent, -full_extent),
		Vector2(full_extent, -full_extent),
		Vector2(full_extent, full_extent),
		Vector2(-full_extent, full_extent),
	]
	for index in 4:
		var a: Vector2 = corners[index]
		var b: Vector2 = corners[(index + 1) % 4]
		_quad(
			tool,
			Vector3(a.x, top_y, a.y),
			Vector3(a.x, wall_bottom, a.y),
			Vector3(b.x, wall_bottom, b.y),
			Vector3(b.x, top_y, b.y)
		)
	if chamfer > 0.0005:
		var steps: int = maxi(1, segments)
		var inner := full_extent - chamfer
		for index in 4:
			var a: Vector2 = corners[index]
			var b: Vector2 = corners[(index + 1) % 4]
			for step in steps:
				var t0 := float(step) / float(steps)
				var t1 := float(step + 1) / float(steps)
				_quad(
					tool,
					_block_chamfer_point(a, full_extent, inner, wall_bottom, bottom_y, t0),
					_block_chamfer_point(a, full_extent, inner, wall_bottom, bottom_y, t1),
					_block_chamfer_point(b, full_extent, inner, wall_bottom, bottom_y, t1),
					_block_chamfer_point(b, full_extent, inner, wall_bottom, bottom_y, t0)
				)
	tool.generate_normals()
	var mesh := ArrayMesh.new()
	tool.commit(mesh)
	if mesh.get_surface_count() > 0:
		mesh.surface_set_name(0, side_slot)
		var wall := TileMeshPart.make(mesh, PackedStringArray([side_slot]), "base")
		wall.smooth_shading = false
		parts.append(wall)

	if generate_underside:
		var floor_tool := SurfaceTool.new()
		floor_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var inner_extent: float = full_extent - clampf(bevel, 0.0, full_extent * 0.4)
		_quad(
			floor_tool,
			Vector3(-inner_extent, bottom_y, -inner_extent),
			Vector3(-inner_extent, bottom_y, inner_extent),
			Vector3(inner_extent, bottom_y, inner_extent),
			Vector3(inner_extent, bottom_y, -inner_extent)
		)
		floor_tool.generate_normals()
		var floor_mesh := ArrayMesh.new()
		floor_tool.commit(floor_mesh)
		if floor_mesh.get_surface_count() > 0:
			floor_mesh.surface_set_name(0, underside_slot)
			var floor_part := TileMeshPart.make(
				floor_mesh, PackedStringArray([underside_slot]), "base"
			)
			floor_part.smooth_shading = false
			parts.append(floor_part)
	return parts


static func _block_chamfer_point(
	corner: Vector2,
	full: float,
	inner: float,
	wall_bottom: float,
	bottom: float,
	t: float
) -> Vector3:
	var direction := Vector2(signf(corner.x), signf(corner.y))
	var curve := sin(t * PI * 0.5)
	var drop := 1.0 - cos(t * PI * 0.5)
	var radius := full - inner
	return Vector3(
		direction.x * (full - radius * drop),
		wall_bottom - (wall_bottom - bottom) * curve,
		direction.y * (full - radius * drop)
	)


## Vertical skirt from the surface boundary down to the structural seam. Without
## it a raised top shows daylight between itself and the shared base.
## `full_extent` and `bevel` describe where the chamfer ring left off: the wall
## starts at the true boundary, one bevel below the field's own boundary height,
## and drops to the structural seam.
static func build_side_wall(
	field: TileHeightField,
	seam_y: float,
	slot: String,
	full_extent := -1.0,
	bevel := 0.0
) -> TileMeshPart:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var resolution := field.resolution
	var extent: float = field.half_extent if full_extent < 0.0 else full_extent
	var last := resolution - 1
	var emitted := false

	# Walk the four boundary runs with a consistent outward winding. Each run
	# maps a field-ring vertex onto the true boundary so the wall lines up with
	# the chamfer above it exactly.
	for i in resolution - 1:
		var x0 := _project(field.world_axis(i), field.half_extent, extent)
		var x1 := _project(field.world_axis(i + 1), field.half_extent, extent)
		emitted = _wall_quad(
			tool,
			Vector3(x1, field.heights[field.index_of(i + 1, 0)] - bevel, -extent),
			Vector3(x0, field.heights[field.index_of(i, 0)] - bevel, -extent),
			seam_y
		) or emitted
		emitted = _wall_quad(
			tool,
			Vector3(x0, field.heights[field.index_of(i, last)] - bevel, extent),
			Vector3(x1, field.heights[field.index_of(i + 1, last)] - bevel, extent),
			seam_y
		) or emitted
	for j in resolution - 1:
		var z0 := _project(field.world_axis(j), field.half_extent, extent)
		var z1 := _project(field.world_axis(j + 1), field.half_extent, extent)
		emitted = _wall_quad(
			tool,
			Vector3(-extent, field.heights[field.index_of(0, j)] - bevel, z0),
			Vector3(-extent, field.heights[field.index_of(0, j + 1)] - bevel, z1),
			seam_y
		) or emitted
		emitted = _wall_quad(
			tool,
			Vector3(extent, field.heights[field.index_of(last, j + 1)] - bevel, z1),
			Vector3(extent, field.heights[field.index_of(last, j)] - bevel, z0),
			seam_y
		) or emitted

	if not emitted:
		return null
	tool.generate_normals()
	var mesh := ArrayMesh.new()
	tool.commit(mesh)
	mesh.surface_set_name(0, slot)
	return TileMeshPart.make(mesh, PackedStringArray([slot]), "side")


static func _project(value: float, from_extent: float, to_extent: float) -> float:
	if from_extent <= 0.0001:
		return value
	return value / from_extent * to_extent


static func _wall_quad(
	tool: SurfaceTool,
	top_a: Vector3,
	top_b: Vector3,
	bottom_y: float
) -> bool:
	if top_a.y <= bottom_y + 0.0002 and top_b.y <= bottom_y + 0.0002:
		return false
	var bottom_a := Vector3(top_a.x, bottom_y, top_a.z)
	var bottom_b := Vector3(top_b.x, bottom_y, top_b.z)
	tool.add_vertex(top_a)
	tool.add_vertex(bottom_a)
	tool.add_vertex(bottom_b)
	tool.add_vertex(top_a)
	tool.add_vertex(bottom_b)
	tool.add_vertex(top_b)
	return true


static func _vertex(field: TileHeightField, i: int, j: int, y_offset: float) -> Vector3:
	return Vector3(
		field.world_axis(i),
		field.heights[field.index_of(i, j)] + y_offset,
		field.world_axis(j)
	)


## Slot of a quad, taken from its lower-left corner. Using one corner rather
## than a vote keeps colour regions contiguous instead of speckled along a
## region boundary.
static func _dominant_slot(field: TileHeightField, i: int, j: int) -> String:
	return field.slot_at(i, j)


static func _triangle(
	tool: SurfaceTool,
	field: TileHeightField,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	smooth: bool
) -> void:
	if smooth:
		tool.set_smooth_group(0)
		tool.set_normal(field.normal_at(a.x / field.half_extent, a.z / field.half_extent))
		tool.add_vertex(a)
		tool.set_normal(field.normal_at(b.x / field.half_extent, b.z / field.half_extent))
		tool.add_vertex(b)
		tool.set_normal(field.normal_at(c.x / field.half_extent, c.z / field.half_extent))
		tool.add_vertex(c)
	else:
		tool.set_smooth_group(-1)
		# A top always faces up. Deriving the sign from the cross product alone
		# would flip a facet whenever the chosen diagonal reverses.
		var normal := (b - a).cross(c - a).normalized()
		if normal.y < 0.0:
			normal = -normal
		tool.set_normal(normal)
		tool.add_vertex(a)
		tool.set_normal(normal)
		tool.add_vertex(b)
		tool.set_normal(normal)
		tool.add_vertex(c)


## Extrudes a closed CCW outline between two heights, capping the top. Shared
## by the board, paver, and basin-rim generators so every constructed piece
## gets identical shading and identical bevel treatment.
static func extrude_prism(
	tool: SurfaceTool,
	outline: PackedVector2Array,
	bottom_y: float,
	top_y: float,
	bevel: float,
	transform_2d := Transform2D.IDENTITY
) -> void:
	if outline.size() < 3:
		return
	var points := PackedVector2Array()
	for point in outline:
		points.append(transform_2d * point)

	var top_points := points
	if bevel > 0.0001:
		top_points = _inset_outline(points, bevel)
		# Chamfer ring between the wall top and the inset cap.
		var shoulder_y := top_y - bevel
		for index in points.size():
			var next := (index + 1) % points.size()
			_quad(
				tool,
				Vector3(points[index].x, shoulder_y, points[index].y),
				Vector3(points[next].x, shoulder_y, points[next].y),
				Vector3(top_points[next].x, top_y, top_points[next].y),
				Vector3(top_points[index].x, top_y, top_points[index].y)
			)
		# Walls stop at the shoulder.
		for index in points.size():
			var next := (index + 1) % points.size()
			_quad(
				tool,
				Vector3(points[index].x, bottom_y, points[index].y),
				Vector3(points[next].x, bottom_y, points[next].y),
				Vector3(points[next].x, shoulder_y, points[next].y),
				Vector3(points[index].x, shoulder_y, points[index].y)
			)
	else:
		for index in points.size():
			var next := (index + 1) % points.size()
			_quad(
				tool,
				Vector3(points[index].x, bottom_y, points[index].y),
				Vector3(points[next].x, bottom_y, points[next].y),
				Vector3(points[next].x, top_y, points[next].y),
				Vector3(points[index].x, top_y, points[index].y)
			)

	# Top cap as a fan from the centroid — outlines here are always convex.
	var centroid := Vector2.ZERO
	for point in top_points:
		centroid += point
	centroid /= float(top_points.size())
	for index in top_points.size():
		var next := (index + 1) % top_points.size()
		tool.add_vertex(Vector3(centroid.x, top_y, centroid.y))
		tool.add_vertex(Vector3(top_points[index].x, top_y, top_points[index].y))
		tool.add_vertex(Vector3(top_points[next].x, top_y, top_points[next].y))


static func _inset_outline(points: PackedVector2Array, amount: float) -> PackedVector2Array:
	var centroid := Vector2.ZERO
	for point in points:
		centroid += point
	centroid /= float(points.size())
	var result := PackedVector2Array()
	for point in points:
		var direction := point - centroid
		var length := direction.length()
		if length <= amount * 1.2:
			result.append(centroid)
		else:
			result.append(centroid + direction * ((length - amount) / length))
	return result


static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)
	tool.add_vertex(a)
	tool.add_vertex(c)
	tool.add_vertex(d)


## Rounded-rectangle outline in CCW order. `corner_segments` of 0 gives a plain
## rectangle; 2 is the restrained rounding constructed pieces use.
static func rounded_rect(
	size: Vector2,
	corner_radius: float,
	corner_segments: int
) -> PackedVector2Array:
	var half := size * 0.5
	var radius: float = clampf(corner_radius, 0.0, minf(half.x, half.y) * 0.9)
	if radius <= 0.0001 or corner_segments <= 0:
		return PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y),
		])
	var result := PackedVector2Array()
	var centres := [
		Vector2(half.x - radius, -(half.y - radius)),
		Vector2(half.x - radius, half.y - radius),
		Vector2(-(half.x - radius), half.y - radius),
		Vector2(-(half.x - radius), -(half.y - radius)),
	]
	var start_angles := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for corner in 4:
		var centre: Vector2 = centres[corner]
		var start: float = start_angles[corner]
		for step in corner_segments + 1:
			var angle: float = start + (PI * 0.5) * float(step) / float(corner_segments)
			result.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return result
