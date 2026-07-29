class_name WaterSurface
extends MeshInstance3D
## Joined water mesh for either a complete small world or one spatial chunk.
## Vertices remain in world space so wave phase, UVs, and normals cross tile
## and chunk boundaries without seams.

const SUBDIV := 8
const BLOCK_BOTTOM := -0.50
const SKIRT_INSET := 0.006
const DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.LEFT,
	Vector2i(0, 1),
	Vector2i(0, -1),
]


func rebuild(
	cells: Array,
	cell_to_world: Callable,
	tile_size: float,
	level: float,
	water_material: Material,
	global_water_lookup := Callable()
) -> void:
	rebuild_with_topology(
		cells,
		cells,
		cell_to_world,
		tile_size,
		level,
		water_material,
		global_water_lookup
	)


## Builds only `cells` while treating `topology_cells` (or the optional global
## lookup) as the full connected region. Placement previews use the topology
## array; the scalable renderer uses the lookup across chunk boundaries.
func rebuild_with_topology(
	cells: Array,
	topology_cells: Array,
	cell_to_world: Callable,
	tile_size: float,
	level: float,
	water_material: Material,
	global_water_lookup := Callable()
) -> void:
	if cells.is_empty():
		mesh = null
		return
	if topology_cells.is_empty():
		topology_cells = cells
	var cell_set := {}
	for cell in topology_cells:
		cell_set[cell] = true
	var is_water := func(coord: Vector2i) -> bool:
		if global_water_lookup.is_valid():
			return bool(global_water_lookup.call(coord))
		return cell_set.has(coord)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var step := tile_size / float(SUBDIV)
	for cell in cells:
		var origin: Vector3 = cell_to_world.call(cell)
		var base := vertices.size()
		var exposed := {
			Vector2i.RIGHT: not is_water.call(cell + Vector2i.RIGHT),
			Vector2i.LEFT: not is_water.call(cell + Vector2i.LEFT),
			Vector2i(0, 1): not is_water.call(cell + Vector2i(0, 1)),
			Vector2i(0, -1): not is_water.call(cell + Vector2i(0, -1)),
		}
		for iy in SUBDIV + 1:
			for ix in SUBDIV + 1:
				var local_x := -tile_size / 2.0 + ix * step
				var local_z := -tile_size / 2.0 + iy * step
				var point := Vector3(
					origin.x + local_x,
					level,
					origin.z + local_z
				)
				vertices.append(point)
				normals.append(Vector3.UP)
				uvs.append(Vector2(point.x, point.z))
				# +1 is the shader's "shore data exists" sentinel.
				uv2s.append(Vector2(
					_local_shore_distance(
						local_x,
						local_z,
						tile_size,
						exposed
					) + 1.0,
					0.0
				))
		for iy in SUBDIV:
			for ix in SUBDIV:
				var a := base + iy * (SUBDIV + 1) + ix
				var b := a + 1
				var c := a + SUBDIV + 1
				var d := c + 1
				indices.append_array([a, c, b, b, c, d])

		# Translucent block walls only at the actual region boundary. The
		# global lookup suppresses false skirts where another chunk continues.
		for direction: Vector2i in DIRECTIONS:
			if is_water.call(cell + direction):
				continue
			var out := Vector3(direction.x, 0, direction.y)
			var tangent := Vector3(-direction.y, 0, direction.x)
			var edge_center: Vector3 = (
				origin + out * (tile_size * 0.5 - SKIRT_INSET)
			)
			var side_base := vertices.size()
			for ix in SUBDIV + 1:
				var along := (ix / float(SUBDIV) - 0.5) * tile_size
				for iy in 2:
					var point := edge_center + tangent * along
					point.y = level if iy == 0 else BLOCK_BOTTOM
					vertices.append(point)
					normals.append(out)
					uvs.append(Vector2(point.x + point.z, point.y))
					uv2s.append(Vector2(999.0, 0.0))
			for ix in SUBDIV:
				var a := side_base + ix * 2
				var b := a + 1
				var c := a + 2
				var d := a + 3
				indices.append_array([a, c, b, b, c, d])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = array_mesh
	material_override = water_material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Foam is only 0.13 m wide, so only an exposed edge of this cell can affect
## one of its vertices. This is constant work per vertex instead of comparing
## every vertex against every shoreline segment in the entire world.
func _local_shore_distance(
	local_x: float,
	local_z: float,
	tile_size: float,
	exposed: Dictionary
) -> float:
	var best := 999.0
	var half := tile_size * 0.5
	if exposed[Vector2i.RIGHT]:
		best = minf(best, half - local_x)
	if exposed[Vector2i.LEFT]:
		best = minf(best, local_x + half)
	if exposed[Vector2i(0, 1)]:
		best = minf(best, half - local_z)
	if exposed[Vector2i(0, -1)]:
		best = minf(best, local_z + half)
	return best
