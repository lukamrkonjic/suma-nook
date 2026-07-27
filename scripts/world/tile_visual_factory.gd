class_name TileVisualFactory
extends RefCounted
## Converts data-defined tile behavior profiles into scene presentation.
## Renderers depend on profiles, never on particular content IDs.

const GROUND_LAYER := 1
const BLOCKER_LAYER := 1
const AUTHORED_TILE_SIZE := 1.7
const COVERED_INFILL_NAME := "CoveredSurfaceInfill"
const SURFACE_DETAIL_META := "tile_surface_detail"

var assets: AssetLibrary
var grid: WorldGrid


func _init(asset_library: AssetLibrary, world_grid: WorldGrid) -> void:
	assets = asset_library
	grid = world_grid


func instantiate_visual(def: Defs.TileDefinition) -> Node3D:
	# Production GLBs were authored to the former 1.70 m footprint. Keep their
	# vertical profile intact while normalizing only X/Z to the live grid size.
	# The wrapper lets generated surface detail remain in live-grid units.
	var visual := Node3D.new()
	visual.name = def.id
	var authored_visual: Node3D
	if def.render_profile == "continuous_water":
		authored_visual = assets.instantiate("tile_water_floor")
	else:
		authored_visual = assets.instantiate(def.asset_id)
	var horizontal_scale := grid.tile_size / AUTHORED_TILE_SIZE
	authored_visual.scale = Vector3(horizontal_scale, 1.0, horizontal_scale)
	visual.add_child(authored_visual)
	_add_surface_detail(visual, def.surface_detail_profile)
	return visual


## A covered tile keeps its structural body but loses its authored top cap and
## any raised surface dressing. A body-coloured infill closes the small bevel
## gap, so stacked columns read as solid blocks rather than layered sandwiches.
func set_surface_covered(visual: Node3D, covered: bool) -> void:
	var body_mesh: MeshInstance3D
	var infill := visual.find_child(COVERED_INFILL_NAME, true, false) as MeshInstance3D
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh == infill:
			continue
		var is_body := mesh.name.to_lower().ends_with("_body")
		if is_body:
			body_mesh = mesh
			mesh.visible = true
		else:
			# Caps, imported relief, and generated speckles all belong to the
			# removable top presentation layer.
			mesh.visible = not covered
	if covered and infill == null and body_mesh != null:
		infill = _covered_surface_infill(body_mesh)
		visual.add_child(infill)
	if infill != null:
		infill.visible = covered


func _add_surface_detail(root: Node3D, profile: String) -> void:
	match profile:
		"grass_speckles":
			var detail_root := Node3D.new()
			detail_root.name = "TileSurfaceDetails"
			detail_root.set_meta(SURFACE_DETAIL_META, true)
			root.add_child(detail_root)
			_add_speckle_layer(
				detail_root,
				"surface_detail_speckles_light",
				"grass_lush",
				0x51A7,
				13,
				0.012,
				0.030
			)
			_add_speckle_layer(
				detail_root,
				"surface_detail_speckles_dark",
				"grass_tuft",
				0xC029,
				9,
				0.010,
				0.024
			)


func _add_speckle_layer(
	root: Node3D,
	node_name: String,
	material_key: String,
	seed_value: int,
	count: int,
	min_height: float,
	max_height: float
) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.set_meta(SURFACE_DETAIL_META, true)
	mesh_instance.mesh = _speckle_mesh(seed_value, count, min_height, max_height)
	mesh_instance.material_override = assets.materials.material(material_key)
	root.add_child(mesh_instance)


func _speckle_mesh(
	seed_value: int,
	count: int,
	min_height: float,
	max_height: float
) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var safe_half_extent := grid.tile_size * 0.39
	for _index in count:
		var center := Vector3(
			rng.randf_range(-safe_half_extent, safe_half_extent),
			rng.randf_range(min_height, max_height),
			rng.randf_range(-safe_half_extent, safe_half_extent)
		)
		var radius_x := rng.randf_range(0.026, 0.065)
		var radius_z := rng.randf_range(0.012, 0.035)
		var yaw := rng.randf_range(0.0, TAU)
		var rim: Array[Vector3] = []
		for corner in 4:
			var angle := yaw + corner * TAU * 0.25
			rim.append(
				Vector3(
					center.x + cos(angle) * radius_x,
					0.0015,
					center.z + sin(angle) * radius_z
				)
			)
		for corner in 4:
			# Winding faces upward. Each low four-sided shard catches a little
			# directional light without reading as a separate placeable tuft.
			surface.add_vertex(center)
			surface.add_vertex(rim[(corner + 1) % 4])
			surface.add_vertex(rim[corner])
	surface.generate_normals()
	var result := surface.commit()
	result.resource_name = "tile_surface_speckles"
	return result


func _covered_surface_infill(body_mesh: MeshInstance3D) -> MeshInstance3D:
	var infill := MeshInstance3D.new()
	infill.name = COVERED_INFILL_NAME
	var box := BoxMesh.new()
	var height := minf(0.13, grid.block_depth * 0.3)
	box.size = Vector3(
		grid.tile_size - 0.004,
		height,
		grid.tile_size - 0.004
	)
	infill.mesh = box
	infill.position.y = -height * 0.5
	if body_mesh.mesh != null and body_mesh.mesh.get_surface_count() > 0:
		infill.material_override = body_mesh.get_active_material(0)
	return infill


func add_collision(
	holder: Node3D,
	def: Defs.TileDefinition,
	rotation_quarters: int
) -> void:
	match def.collision_profile:
		"flat":
			if def.walkable:
				_add_box(
					holder,
					Vector3(grid.tile_size, grid.block_depth, grid.tile_size),
					Vector3(0.0, -grid.block_depth * 0.5, 0.0),
					GROUND_LAYER
				)
		"pond_basin":
			if def.walkable:
				_add_box(
					holder,
					Vector3(grid.tile_size, grid.block_depth, grid.tile_size),
					Vector3(0.0, -grid.block_depth * 0.5, 0.0),
					GROUND_LAYER
				)
			var authored_scale := grid.tile_size / AUTHORED_TILE_SIZE
			var offset := Vector3(
				0.14 * authored_scale,
				0.4,
				0.14 * authored_scale
			).rotated(
				Vector3.UP,
				rotation_quarters * PI * 0.5
			)
			var basin_width := grid.tile_size * 0.68
			_add_box(holder, Vector3(basin_width, 0.8, basin_width), offset, BLOCKER_LAYER)
		"none":
			pass


func _add_box(
	holder: Node3D,
	size: Vector3,
	position: Vector3,
	layer: int
) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = position
	body.add_child(shape)
	holder.add_child(body)
