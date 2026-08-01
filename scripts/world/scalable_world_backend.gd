extends RefCounted
## Chunked terrain backend used automatically by large worlds. It preserves
## the authored TileVisualFactory result, but flattens it once per visual state
## and renders repeated cells through MultiMesh. Structures remain behavioral
## scene objects; terrain rendering, terrain physics, water, and edge walls are
## bounded to an 8x8 chunk.

const CHUNK_SIZE := 8

var owner: WorldRenderer
var core: GameCore
var assets: AssetLibrary
var materials: MaterialLibrary
var tile_factory: TileVisualFactory
var structure_factory: StructureVisualFactory

var chunks: Dictionary = {}
var tile_holders: Dictionary = {}
var tile_instances: Dictionary = {}
var chunk_model_counts: Dictionary = {}


func setup(
	world_renderer: WorldRenderer,
	game_core: GameCore,
	asset_library: AssetLibrary,
	tile_visual_factory: TileVisualFactory,
	structure_visual_factory: StructureVisualFactory
) -> void:
	owner = world_renderer
	core = game_core
	assets = asset_library
	materials = asset_library.materials
	tile_factory = tile_visual_factory
	structure_factory = structure_visual_factory


func clear() -> void:
	for chunk_root: Node3D in chunks.values():
		if is_instance_valid(chunk_root):
			owner._unregister_holder_structures(chunk_root)
			chunk_root.queue_free()
	chunks.clear()
	tile_holders.clear()
	tile_instances.clear()
	chunk_model_counts.clear()


func rebuild_all() -> void:
	clear()
	var wanted := {}
	for coord: Vector2i in core.grid.cells:
		wanted[chunk_of(coord)] = true
	for key: Vector3i in core.grid.stacked_cells:
		wanted[chunk_of(Vector2i(key.x, key.z))] = true
	for chunk_coord: Vector2i in wanted:
		rebuild_chunk(chunk_coord)


func rebuild_around(coord: Vector2i) -> void:
	var dirty := {chunk_of(coord): true}
	for offset: Vector2i in WorldGrid.NEIGHBORS:
		dirty[chunk_of(coord + offset)] = true
	for chunk_coord: Vector2i in dirty:
		rebuild_chunk(chunk_coord)


func chunk_of(coord: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(coord.x) / CHUNK_SIZE),
		floori(float(coord.y) / CHUNK_SIZE)
	)


func tile_node(coord: Vector2i, elevation: int) -> Node3D:
	return tile_holders.get(core.grid.slot_key(coord, elevation))


func set_structure_burning(instance_id: int, _active: bool) -> void:
	var found := core.grid.find_structure(instance_id)
	if found.is_empty():
		return
	rebuild_chunk(chunk_of(found["coord"]))


func rebuild_chunk(chunk_coord: Vector2i) -> void:
	_erase_chunk_refs(chunk_coord)
	chunk_model_counts.erase(chunk_coord)
	if chunks.has(chunk_coord):
		var previous: Node3D = chunks[chunk_coord]
		owner._unregister_holder_structures(previous)
		previous.queue_free()
		chunks.erase(chunk_coord)

	var batches := {}
	var structure_surfaces := {}
	var ground_faces := PackedVector3Array()
	var edge_faces := PackedVector3Array()
	var pick_faces := PackedVector3Array()
	var water_cells: Array[Vector2i] = []
	var warm_lights: Array[Dictionary] = []
	var fire_effects: Array[Dictionary] = []
	var has_content := false
	var structure_count := 0
	var base_coord := chunk_coord * CHUNK_SIZE
	for local_y in CHUNK_SIZE:
		for local_x in CHUNK_SIZE:
			var coord := base_coord + Vector2i(local_x, local_y)
			var top := core.grid.top_elevation(coord)
			if top < 0:
				continue
			has_content = true
			for elevation in range(0, top + 1):
				var state := core.grid.cell_at(coord, elevation)
				var definition := core.grid.tile_def_at(coord, elevation)
				if state == null or definition == null:
					continue
				var world_position := core.grid.cell_to_world(coord, elevation)
				var covered := core.grid.has_cell_at(coord, elevation + 1)
				var neighbour_mask := tile_factory.connection_mask(
					definition,
					coord,
					elevation,
					state.rotation
				)
				var batch_key := "%s|%d|%d|%d" % [
					definition.id,
					int(covered),
					int(elevation > 0),
					neighbour_mask,
				]
				if not batches.has(batch_key):
					batches[batch_key] = {
						"kind": "tile",
						"definition": definition,
						"covered": covered,
						"stack_seam": elevation > 0,
						"neighbour_mask": neighbour_mask,
						"entries": [],
					}
				(batches[batch_key]["entries"] as Array).append({
					"key": core.grid.slot_key(coord, elevation),
					"transform": Transform3D(
						Basis(Vector3.UP, state.rotation * PI * 0.5),
						world_position
					),
				})

				_append_tile_collision(
					ground_faces,
					pick_faces,
					world_position,
					definition,
					state.rotation
				)
				if (
					elevation == 0
					and definition.render_profile == "continuous_water"
				):
					water_cells.append(coord)
				if not state.structures.is_empty():
					for structure: WorldGrid.StructureState in state.structures:
						if _append_structure(
							structure_surfaces,
							ground_faces,
							warm_lights,
							fire_effects,
							state,
							world_position,
							structure
						):
							structure_count += 1

			if _has_physical_walk_surface(coord):
				_append_edge_walls(edge_faces, coord)

	if not has_content:
		return
	var chunk_root := Node3D.new()
	chunk_root.name = "chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	owner.add_child(chunk_root)
	chunks[chunk_coord] = chunk_root

	for batch: Dictionary in batches.values():
		_build_batch(chunk_root, batch)
	_build_static_structure_geometry(chunk_root, structure_surfaces)
	for fire_entry: Dictionary in fire_effects:
		var fire := structure_factory.instantiate_fire_effect(
			fire_entry["definition"]
		)
		fire.name = "BurningEffect_%d" % int(fire_entry["instance_id"])
		fire.transform = fire_entry["transform"] * fire.transform
		fire.set_meta("instance_id", int(fire_entry["instance_id"]))
		if fire.has_method("set_burning"):
			fire.set_burning(bool(fire_entry["burning"]))
		chunk_root.add_child(fire)
	chunk_model_counts[chunk_coord] = structure_count
	_build_collision_body(
		chunk_root,
		ground_faces,
		WorldRenderer.BLOCKER_LAYER,
		"ChunkTerrain"
	)
	_build_collision_body(
		chunk_root,
		edge_faces,
		WorldRenderer.EDGE_WALL_LAYER,
		"ChunkEdges"
	)
	var pick_body := _build_collision_body(
		chunk_root,
		pick_faces,
		WorldRenderer.PLACEABLE_PICK_LAYER,
		"ChunkTilePick"
	)
	if pick_body != null:
		pick_body.set_meta("scalable_terrain", true)

	if not water_cells.is_empty():
		var water := WaterSurface.new()
		water.name = "ChunkWater"
		chunk_root.add_child(water)
		water.rebuild(
			water_cells,
			func(cell: Vector2i) -> Vector3:
				return core.grid.cell_to_world(cell),
			core.grid.tile_size,
			WorldRenderer.WATER_LEVEL,
			materials.material("water"),
			func(cell: Vector2i) -> bool:
				var definition := core.grid.tile_def(cell)
				return (
					definition != null
					and definition.render_profile == "continuous_water"
				)
		)
	warm_lights.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return bool(a.get("burning", true)) and not bool(
			b.get("burning", true)
		)
	)
	for index in mini(4, warm_lights.size()):
		_add_warm_light(chunk_root, warm_lights[index])


func _build_batch(chunk_root: Node3D, batch: Dictionary) -> void:
	var kind := String(batch["kind"])
	var definition: Resource = batch["definition"]
	var batch_mesh: ArrayMesh
	if kind == "tile":
		batch_mesh = tile_factory.batch_mesh(
			definition as Defs.TileDefinition,
			bool(batch["covered"]),
			bool(batch["stack_seam"]),
			int(batch["neighbour_mask"])
		)
	else:
		batch_mesh = structure_factory.batch_mesh(
			definition as Defs.StructureDefinition
		)
	if batch_mesh == null:
		push_warning(
			"ScalableWorldBackend: cannot batch %s '%s'" % [
				kind,
				definition.get("id"),
			]
		)
		return
	var entries: Array = batch["entries"]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = batch_mesh
	multimesh.instance_count = entries.size()
	for index in entries.size():
		var entry: Dictionary = entries[index]
		multimesh.set_instance_transform(index, entry["transform"])
		if kind == "tile":
			tile_instances[entry["key"]] = {
				"multimesh": multimesh,
				"index": index,
				"base": entry["transform"],
			}
	var instance := MultiMeshInstance3D.new()
	instance.name = "%ss_%s" % [kind, definition.get("id")]
	instance.multimesh = multimesh
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	chunk_root.add_child(instance)


func _append_structure(
	structure_surfaces: Dictionary,
	collision_faces: PackedVector3Array,
	warm_lights: Array[Dictionary],
	fire_effects: Array[Dictionary],
	state: WorldGrid.CellState,
	world_position: Vector3,
	structure: WorldGrid.StructureState
) -> bool:
	var definition := core.registries.structure(structure.structure_id)
	if definition == null:
		return false
	var local_transform := core.grid.structure_local_transform_in_cell(
		state,
		structure.instance_id
	)
	var world_transform := (
		Transform3D(Basis.IDENTITY, world_position) * local_transform
	)
	var source_mesh := structure_factory.batch_mesh(definition)
	var model_scale := assets.edits.model_scale_for(definition.asset_id)
	if source_mesh != null:
		for surface in source_mesh.get_surface_count():
			var active_material := source_mesh.surface_get_material(surface)
			var material_key := (
				"none"
				if active_material == null
				else str(active_material.get_instance_id())
			)
			if not structure_surfaces.has(material_key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tool.set_material(active_material)
				structure_surfaces[material_key] = tool
			(structure_surfaces[material_key] as SurfaceTool).append_from(
				source_mesh,
				surface,
				world_transform
			)
	match definition.collision_profile:
		"blocker":
			_append_box_faces(
				collision_faces,
				world_transform.origin + Vector3.UP * (0.5 * model_scale),
				Vector3(0.8, 1.0, 0.8) * model_scale
			)
		"walkable_surface":
			_append_box_faces(
				collision_faces,
				world_transform.origin
				+ Vector3(0.0, -0.08 * model_scale, 0.0),
				Vector3(
					core.grid.tile_size * 0.94,
					0.10,
					core.grid.tile_size * 0.94
				) * model_scale
			)
	if definition.has_capability("light"):
		var burning: bool = bool(
			core.fire.is_burning(structure.instance_id)
			if definition.has_capability("fire")
			else true
		)
		warm_lights.append({
			"position": (
				world_transform.origin
				+ Vector3.UP * definition.light_height * model_scale
			),
			"energy": (
				1.1
				if definition.has_capability("fire")
				else 0.6
			),
			"burning": burning,
			"instance_id": structure.instance_id,
		})
	if definition.has_capability("fire"):
		fire_effects.append({
			"definition": definition,
			"transform": world_transform,
			"instance_id": structure.instance_id,
			"burning": core.fire.is_burning(structure.instance_id),
		})
	return true


func _build_static_structure_geometry(
	chunk_root: Node3D,
	structure_surfaces: Dictionary
) -> void:
	if structure_surfaces.is_empty():
		return
	var combined := ArrayMesh.new()
	combined.resource_name = chunk_root.name + "_structures"
	for surface_tool: SurfaceTool in structure_surfaces.values():
		surface_tool.commit(combined)
	if combined.get_surface_count() == 0:
		return
	var instance := MeshInstance3D.new()
	instance.name = "ChunkStructures"
	instance.mesh = combined
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	chunk_root.add_child(instance)


func _add_warm_light(chunk_root: Node3D, data: Dictionary) -> void:
	var light := OmniLight3D.new()
	light.name = "BatchedWarmLight"
	light.position = data["position"]
	light.light_color = Color(1.0, 0.72, 0.4)
	light.omni_range = 4.5
	light.light_energy = float(data["energy"])
	light.set_meta("base_energy", float(data["energy"]))
	light.set_meta("instance_id", int(data.get("instance_id", 0)))
	light.visible = bool(data.get("burning", true))
	light.distance_fade_enabled = true
	light.distance_fade_begin = 12.0
	light.distance_fade_shadow = 10.0
	light.distance_fade_length = 3.0
	light.add_to_group("warm_lights")
	chunk_root.add_child(light)


func _append_tile_collision(
	ground_faces: PackedVector3Array,
	pick_faces: PackedVector3Array,
	world_position: Vector3,
	definition: Defs.TileDefinition,
	rotation_quarters: int
) -> void:
	var size := core.grid.tile_size
	_append_box_faces(
		pick_faces,
		world_position + Vector3(0.0, -0.01, 0.0),
		Vector3(size, 0.02, size)
	)
	match definition.collision_profile:
		"flat":
			if definition.walkable:
				_append_box_faces(
					ground_faces,
					world_position + Vector3(
						0.0,
						-core.grid.block_depth * 0.5,
						0.0
					),
					Vector3(size, core.grid.block_depth, size)
				)
		"pond_basin":
			if definition.walkable:
				_append_box_faces(
					ground_faces,
					world_position + Vector3(
						0.0,
						-core.grid.block_depth * 0.5,
						0.0
					),
					Vector3(size, core.grid.block_depth, size)
				)
			var authored_scale := size / TileVisualFactory.AUTHORED_TILE_SIZE
			var offset := Vector3(
				0.14 * authored_scale,
				0.4,
				0.14 * authored_scale
			).rotated(Vector3.UP, rotation_quarters * PI * 0.5)
			var basin_width := size * 0.68
			_append_box_faces(
				ground_faces,
				world_position + offset,
				Vector3(basin_width, 0.8, basin_width)
			)


func _has_physical_walk_surface(coord: Vector2i) -> bool:
	return (
		core.grid.has_walkable_top_surface(coord)
		or core.grid.has_walkable_structure_surface(coord)
	)


func _append_edge_walls(faces: PackedVector3Array, coord: Vector2i) -> void:
	var size := core.grid.tile_size
	for offset: Vector2i in WorldGrid.NEIGHBORS:
		if (
			core.grid.has_cell(coord + offset)
			and _has_physical_walk_surface(coord + offset)
		):
			continue
		var along_x := offset.y != 0
		var wall_size := (
			Vector3(size, 2.0, 0.12)
			if along_x
			else Vector3(0.12, 2.0, size)
		)
		var surface_elevation := maxi(0, core.grid.top_elevation(coord))
		var center := (
			core.grid.cell_to_world(coord, surface_elevation)
			+ Vector3(
				offset.x * size * 0.5,
				1.0,
				offset.y * size * 0.5
			)
		)
		_append_box_faces(faces, center, wall_size)


func _append_box_faces(
	faces: PackedVector3Array,
	center: Vector3,
	size: Vector3
) -> void:
	var half := size * 0.5
	var corners := [
		center + Vector3(-half.x, -half.y, -half.z),
		center + Vector3(half.x, -half.y, -half.z),
		center + Vector3(half.x, half.y, -half.z),
		center + Vector3(-half.x, half.y, -half.z),
		center + Vector3(-half.x, -half.y, half.z),
		center + Vector3(half.x, -half.y, half.z),
		center + Vector3(half.x, half.y, half.z),
		center + Vector3(-half.x, half.y, half.z),
	]
	for triangle in [
		[0, 2, 1], [0, 3, 2],
		[4, 5, 6], [4, 6, 7],
		[0, 1, 5], [0, 5, 4],
		[3, 7, 6], [3, 6, 2],
		[0, 4, 7], [0, 7, 3],
		[1, 2, 6], [1, 6, 5],
	]:
		faces.append(corners[triangle[0]])
		faces.append(corners[triangle[1]])
		faces.append(corners[triangle[2]])


func _build_collision_body(
	chunk_root: Node3D,
	faces: PackedVector3Array,
	layer: int,
	body_name: String
) -> StaticBody3D:
	if faces.is_empty():
		return null
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	shape_node.shape = shape
	body.add_child(shape_node)
	chunk_root.add_child(body)
	return body


func terrain_hit(point: Vector3) -> Dictionary:
	var coord := core.grid.world_to_cell(point)
	var elevation := core.grid.top_elevation(coord)
	if elevation < 0:
		return {}
	return {
		"kind": "tile",
		"coord": coord,
		"elevation": elevation,
		"point": point,
	}


func structure_hit(
	camera: Camera3D,
	screen_position: Vector2,
	radius_pixels := 58.0
) -> Dictionary:
	if camera == null:
		return {}
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001:
		return {}
	var distance_to_ground := -origin.y / direction.y
	if distance_to_ground < 0.0:
		return {}
	var ground_point := origin + direction * distance_to_ground
	var center_coord := core.grid.world_to_cell(ground_point)
	var best := {}
	var best_distance := radius_pixels
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var coord := center_coord + Vector2i(dx, dy)
			var top := core.grid.top_elevation(coord)
			for elevation in range(0, top + 1):
				var state := core.grid.cell_at(coord, elevation)
				if state == null:
					continue
				var cell_origin := core.grid.cell_to_world(coord, elevation)
				for structure: WorldGrid.StructureState in state.structures:
					var world_transform := (
						Transform3D(Basis.IDENTITY, cell_origin)
						* core.grid.structure_local_transform_in_cell(
							state,
							structure.instance_id
						)
					)
					var visual_point := (
						world_transform.origin + Vector3.UP * 0.55
					)
					if camera.is_position_behind(visual_point):
						continue
					var screen_distance := screen_position.distance_to(
						camera.unproject_position(visual_point)
					)
					if screen_distance >= best_distance:
						continue
					best_distance = screen_distance
					best = {
						"kind": "structure",
						"coord": coord,
						"elevation": elevation,
						"instance_id": structure.instance_id,
						"point": world_transform.origin,
					}
	return best


func animate_tile(coord: Vector2i, elevation: int = -1) -> void:
	var target_elevation := (
		core.grid.top_elevation(coord)
		if elevation < 0
		else elevation
	)
	var key := core.grid.slot_key(coord, target_elevation)
	if not tile_instances.has(key):
		return
	var data: Dictionary = tile_instances[key]
	var multimesh: MultiMesh = data["multimesh"]
	var index := int(data["index"])
	var target: Transform3D = data["base"]
	var start := target
	start.origin.y += 0.1
	start.basis = start.basis.scaled(Vector3.ONE * 0.96)
	multimesh.set_instance_transform(index, start)
	var tween := owner.create_tween()
	tween.tween_method(
		func(weight: float) -> void:
			if multimesh != null:
				multimesh.set_instance_transform(
					index,
					start.interpolate_with(target, weight)
				),
		0.0,
		1.0,
		0.18
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _erase_chunk_refs(chunk_coord: Vector2i) -> void:
	var base_coord := chunk_coord * CHUNK_SIZE
	for local_y in CHUNK_SIZE:
		for local_x in CHUNK_SIZE:
			var coord := base_coord + Vector2i(local_x, local_y)
			for elevation in range(0, core.grid.max_stack_elevation + 1):
				var key := core.grid.slot_key(coord, elevation)
				tile_holders.erase(key)
				tile_instances.erase(key)


func debug_stats() -> Dictionary:
	var batches := 0
	var models := 0
	var water_chunks := 0
	var collision_chunks := 0
	var warm_lights := 0
	for chunk_root: Node3D in chunks.values():
		for child: Node in chunk_root.get_children():
			if child is MultiMeshInstance3D:
				batches += 1
			elif child is WaterSurface:
				water_chunks += 1
			elif child is MeshInstance3D and child.name == "ChunkStructures":
				batches += 1
			elif child is StaticBody3D:
				collision_chunks += 1
		for light in chunk_root.find_children("*", "OmniLight3D", true, false):
			if light is OmniLight3D:
				warm_lights += 1
	for count: int in chunk_model_counts.values():
		models += count
	return {
		"chunks": chunks.size(),
		"batches": batches,
		"models": models,
		"instances": core.grid.total_tile_count() + models,
		"water_chunks": water_chunks,
		"collision_chunks": collision_chunks,
		"warm_lights": warm_lights,
	}
