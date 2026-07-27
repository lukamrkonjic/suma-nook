class_name WaterSurface
extends MeshInstance3D
## One contiguous water surface for a set of connected water cells.
## Vertices are authored in WORLD space (node stays at the origin), so wave
## phase, UVs, and normals are continuous across every tile — no seams, no
## per-tile banding. Rebuilt only when water topology changes, never per frame.

const SUBDIV := 14     # denser surface for the stronger three-frequency waves
## Water fills its slot exactly like land does: the skirt stops at the same
## -0.50 block bottom as terrain bodies. The old -0.56 overshoot hung a blue
## band below neighbouring land blocks, visible under the island edge.
const BLOCK_BOTTOM := -0.50
const SKIRT_INSET := 0.006   # avoids z-fighting where a land block shares the plane


func rebuild(
	cells: Array,
	cell_to_world: Callable,
	tile_size: float,
	level: float,
	water_material: Material
) -> void:
	rebuild_with_topology(
		cells,
		cells,
		cell_to_world,
		tile_size,
		level,
		water_material
	)


## Builds only `cells` while treating every entry in `topology_cells` as part
## of the same water region. A held tile uses this to suppress its shoreline
## foam and skirt along edges that will join existing water.
func rebuild_with_topology(
	cells: Array,
	topology_cells: Array,
	cell_to_world: Callable,
	tile_size: float,
	level: float,
	water_material: Material
) -> void:
	if cells.is_empty():
		mesh = null
		return
	if topology_cells.is_empty():
		topology_cells = cells
	var cell_set := {}
	for cell in topology_cells:
		cell_set[cell] = true
	# Shoreline segments: every cell edge whose neighbour is not water. Foam is
	# driven by the distance to these — a GEOMETRIC shoreline — never by a
	# screen-space depth difference, which would paint a white halo around any
	# object standing in front of or just under the surface.
	var shore: Array[PackedVector3Array] = []
	for cell in topology_cells:
		var origin: Vector3 = cell_to_world.call(cell)
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if cell_set.has(cell + dir):
				continue
			var out := Vector3(dir.x, 0, dir.y)
			var tangent := Vector3(-dir.y, 0, dir.x)
			var mid: Vector3 = origin + out * tile_size / 2.0
			shore.append(PackedVector3Array([
				mid - tangent * tile_size / 2.0, mid + tangent * tile_size / 2.0]))

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var step := tile_size / float(SUBDIV)
	for cell in cells:
		var origin: Vector3 = cell_to_world.call(cell)
		var base := verts.size()
		for iy in SUBDIV + 1:
			for ix in SUBDIV + 1:
				var p := Vector3(origin.x - tile_size / 2.0 + ix * step, level, origin.z - tile_size / 2.0 + iy * step)
				verts.append(p)
				normals.append(Vector3.UP)
				uvs.append(Vector2(p.x, p.z))
				# +1 sentinel: meshes without UV2 (GLB pond quads) read 0 and are
				# treated as "no shoreline data" rather than "at the shore".
				uv2s.append(Vector2(_shore_distance(p, shore) + 1.0, 0.0))
		for iy in SUBDIV:
			for ix in SUBDIV:
				var a := base + iy * (SUBDIV + 1) + ix
				var b := a + 1
				var c := a + SUBDIV + 1
				var d := c + 1
				indices.append_array([a, c, b, b, c, d])
		# Jello block sides: a translucent skirt wall on every edge that does
		# not continue into another water cell, from the surface to the block
		# bottom — the water reads as a solid glassy block, never a floating
		# sheet.
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if cell_set.has(cell + dir):
				continue
			var out := Vector3(dir.x, 0, dir.y)
			var tangent := Vector3(-dir.y, 0, dir.x)
			var edge_center: Vector3 = origin + out * (tile_size / 2.0 - SKIRT_INSET)
			var sbase := verts.size()
			for ix in SUBDIV + 1:
				var along := (ix / float(SUBDIV) - 0.5) * tile_size
				for iy in 2:
					var p := edge_center + tangent * along
					p.y = level if iy == 0 else BLOCK_BOTTOM
					verts.append(p)
					normals.append(out)
					uvs.append(Vector2(p.x + p.z, p.y))
					uv2s.append(Vector2(999.0, 0.0))
			for ix in SUBDIV:
				var a := sbase + ix * 2
				var b := a + 1
				var c := a + 2
				var d := a + 3
				indices.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = array_mesh
	material_override = water_material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Shortest distance from a surface point to the shoreline (region boundary).
func _shore_distance(p: Vector3, shore: Array[PackedVector3Array]) -> float:
	var best := 999.0
	for seg in shore:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var ab := b - a
		var len_sq := ab.length_squared()
		var t := 0.0 if len_sq < 1e-6 else clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best
