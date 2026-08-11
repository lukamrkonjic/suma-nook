extends RefCounted

var _color_system := PaletteDefinition.shared()
## Chunked terrain backend used automatically by large worlds. It preserves
## the authored TileVisualFactory result, but flattens it once per visual state
## and renders repeated cells through MultiMesh. Structures remain behavioral
## scene objects; terrain rendering, terrain physics, water, and edge walls are
## bounded to an 8x8 chunk.

const CHUNK_SIZE := 8
const DEFAULT_REBUILD_BUDGET_USEC := 1000

var owner: WorldRenderer
var core: GameCore
var assets: AssetLibrary
var materials: MaterialLibrary
var tile_factory: TileVisualFactory
var structure_factory: StructureVisualFactory

var chunks: Dictionary = {}
var tile_holders: Dictionary = {}
var tile_instances: Dictionary = {}
var structure_instances: Dictionary = {}
var chunk_model_counts: Dictionary = {}
var reveal_tiles_in_flight: Dictionary = {}
var reveal_structures_in_flight: Dictionary = {}
var wish_tiles_in_flight: Dictionary = {}
var wish_structures_in_flight: Dictionary = {}
var structure_effect_tweens: Dictionary = {}
var hover_proxies: Array[Node3D] = []


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
	structure_instances.clear()
	chunk_model_counts.clear()
	reveal_tiles_in_flight.clear()
	reveal_structures_in_flight.clear()
	wish_tiles_in_flight.clear()
	wish_structures_in_flight.clear()
	structure_effect_tweens.clear()
	clear_hover_proxies()


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


## Batched entries do not have scene nodes of their own. These outline-only
## proxies mirror one exact MultiMesh entry into the dedicated outline camera;
## the gameplay camera never renders their visibility layer.
func hover_structure_node(instance_id: int) -> Node3D:
	if not structure_instances.has(instance_id):
		return null
	return _hover_proxy(structure_instances[instance_id], "HoverStructure_%d" % instance_id)


func hover_tile_node(coord: Vector2i, elevation: int) -> Node3D:
	var key := core.grid.slot_key(coord, elevation)
	if not tile_instances.has(key):
		return null
	return _hover_proxy(
		tile_instances[key],
		"HoverTile_%d_%d_%d" % [coord.x, coord.y, elevation]
	)


func _hover_proxy(data: Dictionary, proxy_name: String) -> Node3D:
	var multimesh := data.get("multimesh") as MultiMesh
	var index := int(data.get("index", -1))
	if multimesh == null or index < 0 or index >= multimesh.instance_count:
		return null
	var proxy := Node3D.new()
	proxy.name = proxy_name
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "OutlineMesh"
	mesh_instance.mesh = multimesh.mesh
	mesh_instance.layers = WorldRenderer.OUTLINE_VISIBILITY_LAYER
	proxy.add_child(mesh_instance)
	owner.add_child(proxy)
	proxy.transform = multimesh.get_instance_transform(index)
	hover_proxies.append(proxy)
	return proxy


func clear_hover_proxies() -> void:
	for proxy: Node3D in hover_proxies:
		if is_instance_valid(proxy):
			proxy.queue_free()
	hover_proxies.clear()


func set_structure_burning(instance_id: int, _active: bool) -> void:
	var found := core.grid.find_structure(instance_id)
	if found.is_empty():
		return
	rebuild_chunk(chunk_of(found["coord"]))


## Streams every cold PackedScene needed by an update before chunk composition.
## Node and mesh construction intentionally stays on the main thread: Godot's
## RenderingServer resources are not safe to mutate from a gameplay worker.
func prepare_update_async(dirty: Dictionary) -> void:
	var slots := _preparation_slots(dirty)
	var asset_ids := {}
	for entry: Dictionary in slots:
		var coord: Vector2i = entry["coord"]
		var elevation := int(entry["elevation"])
		var definition := core.grid.tile_def_at(coord, elevation)
		var state := core.grid.cell_at(coord, elevation)
		if definition == null or state == null:
			continue
		_collect_tile_asset_ids(
			definition,
			asset_ids,
			tile_factory.connection_mask(
				definition,
				coord,
				elevation,
				state.rotation
			)
		)
		for structure: WorldGrid.StructureState in state.structures:
			var structure_definition := core.registries.structure(
				structure.structure_id
			)
			if structure_definition == null:
				continue
			asset_ids[structure_definition.asset_id] = true
	await assets.prime_packed_scenes_async(asset_ids.keys())
	await assets.prime_presentations_async(asset_ids.keys())


func _preparation_slots(dirty: Dictionary) -> Array:
	var affected := dirty.duplicate(true)
	for entry: Dictionary in dirty.values():
		var coord: Vector2i = entry["coord"]
		var elevation := int(entry["elevation"])
		for offset: Vector2i in WorldGrid.NEIGHBORS:
			var neighbour := coord + offset
			affected[core.grid.slot_key(neighbour, elevation)] = {
				"coord": neighbour,
				"elevation": elevation,
			}
		if elevation > 0:
			affected[core.grid.slot_key(coord, elevation - 1)] = {
				"coord": coord,
				"elevation": elevation - 1,
			}
	return affected.values()


func _collect_tile_asset_ids(
	definition: Defs.TileDefinition,
	asset_ids: Dictionary,
	neighbour_mask: int
) -> void:
	if not definition.uses_layered_visual():
		asset_ids[definition.asset_id] = true
		return
	for layer: Defs.TileVisualLayerDefinition in definition.visual_layers:
		asset_ids[layer.asset_id] = true
		# Prime only the topology this cell will actually instantiate. Checking
		# every possible n/x scene for every cell created its own synchronous scan.
		var topology := neighbour_mask & 0x0F
		if topology == 0:
			continue
		var candidate := ""
		if (neighbour_mask & TileVisualFactory.MIXED_SURFACE_FLAG) != 0:
			candidate = "%s_x%02d" % [layer.asset_id, topology]
			if assets.exists(candidate):
				asset_ids[candidate] = true
				continue
		candidate = "%s_n%02d" % [layer.asset_id, topology]
		if assets.exists(candidate):
			asset_ids[candidate] = true


func rebuild_chunk(
	chunk_coord: Vector2i,
	cooperative := false,
	frame_budget_usec := DEFAULT_REBUILD_BUDGET_USEC
) -> void:
	# Live Nook expansion uses the cooperative path. Keep the currently visible
	# chunk intact while its replacement is prepared off-tree, then swap both in
	# one frame. Ordinary edits still use the synchronous path for immediacy.
	var tree := owner.get_tree() if cooperative else null
	var frame_started := Time.get_ticks_usec()
	var previous: Node3D = chunks.get(chunk_coord)

	var batches := {}
	var structure_batches := {}
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
				var covered := owner.is_tile_surface_covered_for_render(
					coord, elevation
				)
				var neighbour_mask := tile_factory.connection_mask(
					definition,
					coord,
					elevation,
					state.rotation
				)
				var detail_variant := TileVisualFactory.detail_variant_for_coord(
					definition, coord, elevation
				)
				var surface_masks: Array[PackedVector2Array] = (
					structure_factory.surface_masks_for_tile(
						state,
						state.rotation
					)
				)
				var batch_key := "%s|%d|%d|%d|%d|%s" % [
					definition.id,
					int(covered),
					int(elevation > 0),
					neighbour_mask,
					detail_variant,
					tile_factory.surface_mask_signature(surface_masks),
				]
				if not batches.has(batch_key):
					batches[batch_key] = {
						"kind": "tile",
						"definition": definition,
						"covered": covered,
						"stack_seam": elevation > 0,
						"neighbour_mask": neighbour_mask,
						"detail_variant": detail_variant,
						"surface_masks": surface_masks,
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
					and not owner.is_reveal_water(coord)
				):
					water_cells.append(coord)
				if not state.structures.is_empty():
					for structure: WorldGrid.StructureState in state.structures:
						if _append_structure(
							structure_batches,
							ground_faces,
							warm_lights,
							fire_effects,
							state,
							world_position,
							structure,
							chunk_coord
						):
							structure_count += 1

			if _has_physical_walk_surface(coord):
				_append_edge_walls(edge_faces, coord)
			if (
				cooperative
				and tree != null
				and Time.get_ticks_usec() - frame_started >= frame_budget_usec
			):
				await tree.process_frame
				frame_started = Time.get_ticks_usec()

	if not has_content:
		_erase_chunk_refs(chunk_coord)
		chunk_model_counts.erase(chunk_coord)
		if previous != null and is_instance_valid(previous):
			owner._unregister_holder_structures(previous)
			previous.queue_free()
		chunks.erase(chunk_coord)
		return
	var chunk_root := Node3D.new()
	chunk_root.name = "chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	_erase_chunk_refs(chunk_coord)
	chunk_model_counts.erase(chunk_coord)

	for batch: Dictionary in batches.values():
		_build_batch(chunk_root, batch)
		if (
			cooperative
			and tree != null
			and Time.get_ticks_usec() - frame_started >= frame_budget_usec
		):
			await tree.process_frame
			frame_started = Time.get_ticks_usec()
	for batch: Dictionary in structure_batches.values():
		_build_batch(chunk_root, batch)
		if (
			cooperative
			and tree != null
			and Time.get_ticks_usec() - frame_started >= frame_budget_usec
		):
			await tree.process_frame
			frame_started = Time.get_ticks_usec()
	if cooperative and tree != null:
		await tree.process_frame
		frame_started = Time.get_ticks_usec()
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
	if (
		cooperative
		and tree != null
		and Time.get_ticks_usec() - frame_started >= frame_budget_usec
	):
		await tree.process_frame
		frame_started = Time.get_ticks_usec()
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

	# The old chunk stayed rendered throughout preparation. Replace it only
	# after every mesh and collider is ready, avoiding a blank async frame.
	if previous != null and is_instance_valid(previous):
		owner._unregister_holder_structures(previous)
		previous.queue_free()
	owner.add_child(chunk_root)
	chunks[chunk_coord] = chunk_root


func _build_batch(chunk_root: Node3D, batch: Dictionary) -> void:
	var kind := String(batch["kind"])
	var definition: Resource = batch["definition"]
	var batch_mesh: ArrayMesh
	if kind == "tile":
		batch_mesh = tile_factory.batch_mesh(
			definition as Defs.TileDefinition,
			bool(batch["covered"]),
			bool(batch["stack_seam"]),
			int(batch["neighbour_mask"]),
			int(batch.get("detail_variant", 0)),
			batch.get("surface_masks", [])
		)
	else:
		batch_mesh = structure_factory.batch_mesh(
			definition as Defs.StructureDefinition,
			String(batch.get("harvest_state", "ready"))
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
	var batch_bounds := AABB()
	var has_batch_bounds := false
	var source_bounds := batch_mesh.get_aabb()
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var entry_transform: Transform3D = entry["transform"]
		var initial_transform := entry_transform
		var staged := false
		if kind == "tile":
			var tile_key: Vector3i = entry["key"]
			staged = owner.is_tile_key_staged_for_reveal(tile_key)
		else:
			staged = owner.is_structure_staged_for_reveal(int(entry["key"]))
		if staged:
			initial_transform.basis = initial_transform.basis.scaled(
				Vector3.ONE * 0.001
			)
		multimesh.set_instance_transform(index, initial_transform)
		if staged:
			owner.note_reveal_instance_built_hidden(
				absf(initial_transform.basis.determinant()) <= 0.01
			)
		var entry_bounds: AABB = entry_transform * source_bounds
		batch_bounds = (
			batch_bounds.merge(entry_bounds)
			if has_batch_bounds
			else entry_bounds
		)
		has_batch_bounds = true
		if kind == "tile":
			tile_instances[entry["key"]] = {
				"multimesh": multimesh,
				"index": index,
				"base": entry["transform"],
				"covered": bool(batch["covered"]),
			}
		else:
			structure_instances[int(entry["key"])] = {
				"multimesh": multimesh,
				"index": index,
				"base": entry["transform"],
				"chunk": entry["chunk"],
			}
	var instance := MultiMeshInstance3D.new()
	instance.name = "%ss_%s" % [kind, definition.get("id")]
	instance.multimesh = multimesh
	if has_batch_bounds:
		# MultiMesh culling normally derives a ground-level box. The reveal moves
		# instances six metres upward, so without explicit headroom the renderer
		# culls the sky portion and the intended falling wave appears to vanish.
		var reveal_headroom := maxf(
			5.2,
			float(core.registries.reveal_config.get(
				"tile_drop_height" if kind == "tile" else "model_drop_height",
				6.0 if kind == "tile" else 1.45
			))
				+ float(core.registries.reveal_config.get(
					"tile_overshoot" if kind == "tile" else "model_overshoot",
					0.08
				))
				+ 0.5
		)
		var reveal_footroom := (
			maxf(
				0.0,
				float(core.registries.reveal_config.get(
					"water_rise_depth", 1.35
				)) + 0.25
			)
			if kind == "tile"
			else 0.0
		)
		batch_bounds.position.y -= reveal_footroom
		batch_bounds.size.y += reveal_footroom
		batch_bounds.size.y += reveal_headroom
		multimesh.custom_aabb = batch_bounds
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	chunk_root.add_child(instance)


func _append_structure(
	structure_batches: Dictionary,
	collision_faces: PackedVector3Array,
	warm_lights: Array[Dictionary],
	fire_effects: Array[Dictionary],
	state: WorldGrid.CellState,
	world_position: Vector3,
	structure: WorldGrid.StructureState,
	chunk_coord: Vector2i
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
	var harvest_runtime: Dictionary = structure.runtime_state.get("harvest", {})
	var harvest_state := String(harvest_runtime.get("state", "ready"))
	var authored_model_scale: float = assets.edits.model_scale_for(
		definition.asset_id
	)
	var model_scale: float = structure_factory.effective_model_scale(definition)
	var batch_key := "%s|%s" % [definition.id, harvest_state]
	if not structure_batches.has(batch_key):
		structure_batches[batch_key] = {
			"kind": "structure",
			"definition": definition,
			"harvest_state": harvest_state,
			"entries": [],
		}
	(structure_batches[batch_key]["entries"] as Array).append({
		"key": structure.instance_id,
		"transform": world_transform,
		"chunk": chunk_coord,
	})
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
				+ Vector3(0.0, -0.08 * authored_model_scale, 0.0),
				Vector3(
					core.grid.tile_size * 0.94,
					0.10,
					core.grid.tile_size * 0.94
				) * authored_model_scale
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


func _add_warm_light(chunk_root: Node3D, data: Dictionary) -> void:
	var light := OmniLight3D.new()
	light.name = "BatchedWarmLight"
	light.position = data["position"]
	light.light_color = _color_system.color("vfx_local_light")
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
				var block_height := (
					core.grid.block_depth * definition.height_fraction
				)
				var collision_height := (
					block_height + definition.walk_surface_height
				)
				_append_box_faces(
					ground_faces,
					world_position + Vector3(
						0.0,
						(
							definition.walk_surface_height
							- block_height
						) * 0.5,
						0.0
					),
					Vector3(size, collision_height, size)
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
	# The grid commits reveal cells ahead of presentation. Treat them as void
	# for perimeter topology until their landing wave has completed, otherwise
	# the settled seam drops its blocker/edge one phase too early.
	if owner.is_coord_staged_for_reveal(coord):
		return false
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


## MultiMesh presentation equivalent of WorldRenderer's exact-node water hop.
## Only the committed destination instance moves; chunk topology and collision
## stay authoritative throughout the short flourish.
func animate_tile_water_skip(
	coord: Vector2i,
	elevation: int,
	impact_position: Vector3,
	relative_elevation: int
) -> Tween:
	var key := core.grid.slot_key(coord, elevation)
	if not tile_instances.has(key):
		return null
	var data: Dictionary = tile_instances[key]
	var multimesh: MultiMesh = data["multimesh"]
	var index := int(data["index"])
	var target: Transform3D = data["base"]
	var start := target
	start.origin = impact_position + Vector3.UP * (
		0.035 + relative_elevation * core.grid.block_depth
	)
	start.basis = start.basis.scaled(Vector3(1.12, 0.72, 1.12))
	var travel := target.origin - start.origin
	var horizontal_distance := Vector2(travel.x, travel.z).length()
	var arc_height := 0.46 + minf(0.5, horizontal_distance * 0.13)
	var control_a := start.origin + travel * 0.28 + Vector3.UP * arc_height
	var control_b := target.origin - travel * 0.18 + Vector3.UP * arc_height
	multimesh.set_instance_transform(index, start)
	var tween := owner.create_tween()
	tween.tween_method(
		func(weight: float) -> void:
			if multimesh == null:
				return
			var current := start.interpolate_with(target, weight)
			current.origin = start.origin.bezier_interpolate(
				control_a,
				control_b,
				target.origin,
				weight
			)
			multimesh.set_instance_transform(index, current),
		0.0,
		1.0,
		0.5
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var squash := target
	squash.basis = squash.basis.scaled(Vector3(1.07, 0.86, 1.07))
	tween.tween_method(
		func(weight: float) -> void:
			if multimesh != null:
				multimesh.set_instance_transform(
					index,
					target.interpolate_with(squash, weight)
				),
		0.0,
		1.0,
		0.055
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_method(
		func(weight: float) -> void:
			if multimesh != null:
				multimesh.set_instance_transform(
					index,
					squash.interpolate_with(target, weight)
				),
		0.0,
		1.0,
		0.12
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween


## Per-instance equivalent of the exact renderer's shooting-star fall. The
## authoritative object is already landed; only its MultiMesh transform takes
## the diagonal fall, squash, crooked rebound, and final settle.
func animate_tile_wish_landing(coord: Vector2i, elevation: int) -> Tween:
	var key := core.grid.slot_key(coord, elevation)
	if not tile_instances.has(key):
		return null
	wish_tiles_in_flight[key] = true
	return _animate_wish_instance(
		tile_instances[key],
		func() -> void: wish_tiles_in_flight.erase(key)
	)


func animate_structure_wish_landing(instance_id: int) -> Tween:
	if not structure_instances.has(instance_id):
		return null
	wish_structures_in_flight[instance_id] = true
	return _animate_wish_instance(
		structure_instances[instance_id],
		func() -> void: wish_structures_in_flight.erase(instance_id)
	)


func placeable_is_wish_falling(
	kind: String,
	coord: Vector2i,
	elevation: int,
	instance_id: int
) -> bool:
	return (
		wish_structures_in_flight.has(instance_id)
		if kind == "structure"
		else wish_tiles_in_flight.has(core.grid.slot_key(coord, elevation))
	)


func _animate_wish_instance(data: Dictionary, finished: Callable) -> Tween:
	var multimesh := data.get("multimesh") as MultiMesh
	var index := int(data.get("index", -1))
	if multimesh == null or index < 0 or index >= multimesh.instance_count:
		finished.call()
		return null
	var target: Transform3D = data["base"]
	var start := target
	start.origin += Vector3(-2.2, 4.4, -1.7)
	start.basis = Basis.from_euler(Vector3(0.48, -0.22, -0.72)) \
		* target.basis.scaled(Vector3.ONE * 0.72)
	var impact := target
	impact.basis = target.basis.scaled(Vector3(1.10, 0.79, 1.10))
	var rebound := target
	rebound.origin += Vector3(0.035, 0.24, -0.02)
	rebound.basis = Basis.from_euler(Vector3(0.025, -0.015, -0.055)) \
		* target.basis.scaled(Vector3(0.97, 1.07, 0.97))
	multimesh.set_instance_transform(index, start)
	var trail := owner._wish_shooting_star_trail(start.origin)
	var tween := owner.create_tween()
	tween.tween_method(
		_interpolate_reveal_transform.bind(multimesh, index, start, impact),
		0.0, 1.0, 0.72
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if trail != null:
		var trail_tween := trail.create_tween()
		trail_tween.tween_property(trail, "global_position", target.origin, 0.72) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_method(
		_interpolate_reveal_transform.bind(multimesh, index, impact, rebound),
		0.0, 1.0, 0.11
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(
		_interpolate_reveal_transform.bind(multimesh, index, rebound, target),
		0.0, 1.0, 0.18
	).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		_set_reveal_transform(multimesh, index, target)
		finished.call()
		if is_instance_valid(trail):
			trail.emitting = false
			owner.get_tree().create_timer(trail.lifetime).timeout.connect(func():
				if is_instance_valid(trail):
					trail.queue_free()
			)
	)
	return tween


## Tactile harvesting for MultiMesh structures. Ordinary hits squash and kick
## sideways; final tree hits topple, while rocks compress into their remnant.
func animate_structure_harvest_impact(
	instance_id: int,
	progress: float,
	final: bool,
	presentation: String,
	finished: Callable = Callable()
) -> bool:
	if not structure_instances.has(instance_id):
		if finished.is_valid():
			finished.call()
		return false
	var data: Dictionary = structure_instances[instance_id]
	var multimesh := data.get("multimesh") as MultiMesh
	var index := int(data.get("index", -1))
	if multimesh == null or index < 0 or index >= multimesh.instance_count:
		if finished.is_valid():
			finished.call()
		return false
	var previous := structure_effect_tweens.get(instance_id) as Tween
	if previous != null and previous.is_valid():
		previous.kill()
	var target: Transform3D = data["base"]
	multimesh.set_instance_transform(index, target)
	var amount := lerpf(0.045, 0.11, clampf(progress, 0.0, 1.0))
	var impact := target
	impact.basis = target.basis.rotated(Vector3.FORWARD, amount).scaled(
		Vector3(1.08, 0.9, 1.08)
	)
	var tween := owner.create_tween()
	structure_effect_tweens[instance_id] = tween
	tween.tween_method(
		_interpolate_reveal_transform.bind(multimesh, index, target, impact),
		0.0, 1.0, 0.055
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if final and presentation == "clay_tree":
		var felled := target
		felled.origin.y += 0.06
		felled.basis = target.basis.rotated(Vector3.RIGHT, 1.28)
		tween.tween_method(
			_interpolate_reveal_transform.bind(multimesh, index, impact, felled),
			0.0, 1.0, 0.34
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	elif final and presentation == "clay_rock":
		var crushed := target
		crushed.basis = target.basis.rotated(Vector3.UP, 0.16).scaled(
			Vector3(1.22, 0.12, 1.22)
		)
		crushed.origin.y -= 0.08
		tween.tween_method(
			_interpolate_reveal_transform.bind(multimesh, index, impact, crushed),
			0.0, 1.0, 0.19
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	else:
		tween.tween_method(
			_interpolate_reveal_transform.bind(multimesh, index, impact, target),
			0.0, 1.0, 0.14
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		structure_effect_tweens.erase(instance_id)
		if not final:
			_set_reveal_transform(multimesh, index, target)
		if finished.is_valid():
			finished.call()
	)
	return true


## Keeps one newly built MultiMesh entry out of sight until the Nook reveal
## owns it. Scaling only that instance preserves the already-visible terrain
## sharing the same batch and avoids a pre-animation pop.
func hide_tile_for_reveal(coord: Vector2i, elevation: int) -> bool:
	var key := core.grid.slot_key(coord, elevation)
	if not tile_instances.has(key):
		return false
	var data: Dictionary = tile_instances[key]
	var multimesh: MultiMesh = data["multimesh"]
	var index := int(data["index"])
	var hidden: Transform3D = data["base"]
	hidden.basis = hidden.basis.scaled(Vector3.ONE * 0.001)
	multimesh.set_instance_transform(index, hidden)
	return true


## MultiMesh equivalent of NookRevealPresenter._drop_tile(). The instance is
## hidden during its wave delay, then falls from the sky and lands on the
## immutable base transform stored by the chunk builder.
func animate_tile_reveal(
	coord: Vector2i,
	elevation: int,
	delay: float,
	drop_height: float,
	drop_seconds: float,
	overshoot: float
) -> bool:
	var key := core.grid.slot_key(coord, elevation)
	if not tile_instances.has(key):
		return false
	var data: Dictionary = tile_instances[key]
	var multimesh: MultiMesh = data["multimesh"]
	var index := int(data["index"])
	var target: Transform3D = data["base"]
	var start := target
	start.origin.y += drop_height
	var overshot := target
	overshot.origin.y -= overshoot
	var hidden := start
	hidden.basis = hidden.basis.scaled(Vector3.ONE * 0.001)
	multimesh.set_instance_transform(index, hidden)
	reveal_tiles_in_flight[key] = true
	var tween := owner.create_tween()
	tween.tween_interval(maxf(0.0, delay))
	tween.tween_callback(
		_set_reveal_transform.bind(multimesh, index, start)
	)
	tween.tween_method(
		_interpolate_reveal_transform.bind(
			multimesh,
			index,
			start,
			overshot
		),
		0.0,
		1.0,
		drop_seconds
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_method(
		_interpolate_reveal_transform.bind(
			multimesh,
			index,
			overshot,
			target
		),
		0.0,
		1.0,
		drop_seconds * 0.35
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(
		_finish_reveal_transform.bind(key, multimesh, index, target)
	)
	return true


## Water owns a second phase: its bed and joined surface wait below the world
## until every land block has seated, then rise together with a soft crest.
func animate_water_tile_reveal(
	coord: Vector2i,
	elevation: int,
	delay: float,
	rise_depth: float,
	rise_seconds: float,
	overshoot: float
) -> bool:
	var key := core.grid.slot_key(coord, elevation)
	if not tile_instances.has(key):
		return false
	var data: Dictionary = tile_instances[key]
	var multimesh: MultiMesh = data["multimesh"]
	var index := int(data["index"])
	var target: Transform3D = data["base"]
	var start := target
	start.origin.y -= maxf(0.0, rise_depth)
	var crest := target
	crest.origin.y += maxf(0.0, overshoot)
	var hidden := start
	hidden.basis = hidden.basis.scaled(Vector3.ONE * 0.001)
	multimesh.set_instance_transform(index, hidden)
	reveal_tiles_in_flight[key] = true
	var tween := owner.create_tween()
	tween.tween_interval(maxf(0.0, delay))
	tween.tween_callback(
		_set_reveal_transform.bind(multimesh, index, start)
	)
	tween.tween_method(
		_interpolate_reveal_transform.bind(
			multimesh,
			index,
			start,
			crest
		),
		0.0,
		1.0,
		rise_seconds
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(
		_interpolate_reveal_transform.bind(
			multimesh,
			index,
			crest,
			target
		),
		0.0,
		1.0,
		rise_seconds * 0.28
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(
		_finish_reveal_transform.bind(key, multimesh, index, target)
	)
	return true


## Models remain batched in large worlds, but every instance retains its own
## immutable transform. That makes a true per-object drop possible without
## restoring one scene tree per rock, wall, or tree.
func animate_structure_reveal(
	instance_id: int,
	delay: float,
	drop_height: float,
	drop_seconds: float,
	overshoot: float
) -> bool:
	if not structure_instances.has(instance_id):
		return false
	var data: Dictionary = structure_instances[instance_id]
	var multimesh: MultiMesh = data["multimesh"]
	var index := int(data["index"])
	var target: Transform3D = data["base"]
	var start := target
	start.origin.y += maxf(0.0, drop_height)
	start.basis = start.basis.scaled(Vector3.ONE * 0.88)
	var landed := target
	landed.origin.y -= maxf(0.0, overshoot)
	landed.basis = landed.basis.scaled(Vector3.ONE * 1.035)
	var hidden := start
	hidden.basis = hidden.basis.scaled(Vector3.ONE * 0.001)
	multimesh.set_instance_transform(index, hidden)
	reveal_structures_in_flight[instance_id] = true
	var tween := owner.create_tween()
	tween.tween_interval(maxf(0.0, delay))
	tween.tween_callback(
		_set_reveal_transform.bind(multimesh, index, start)
	)
	tween.tween_method(
		_interpolate_reveal_transform.bind(
			multimesh,
			index,
			start,
			landed
		),
		0.0,
		1.0,
		drop_seconds
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_method(
		_interpolate_reveal_transform.bind(
			multimesh,
			index,
			landed,
			target
		),
		0.0,
		1.0,
		drop_seconds * 0.34
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(
		_finish_structure_reveal.bind(
			instance_id,
			multimesh,
			index,
			target
		)
	)
	return true


func _set_reveal_transform(
	multimesh: MultiMesh,
	index: int,
	transform: Transform3D
) -> void:
	if multimesh != null and index >= 0 and index < multimesh.instance_count:
		multimesh.set_instance_transform(index, transform)


func _interpolate_reveal_transform(
	weight: float,
	multimesh: MultiMesh,
	index: int,
	from: Transform3D,
	to: Transform3D
) -> void:
	_set_reveal_transform(
		multimesh,
		index,
		from.interpolate_with(to, weight)
	)


func _finish_reveal_transform(
	key: Vector3i,
	multimesh: MultiMesh,
	index: int,
	transform: Transform3D
) -> void:
	_set_reveal_transform(multimesh, index, transform)
	reveal_tiles_in_flight.erase(key)


func _finish_structure_reveal(
	instance_id: int,
	multimesh: MultiMesh,
	index: int,
	transform: Transform3D
) -> void:
	_set_reveal_transform(multimesh, index, transform)
	reveal_structures_in_flight.erase(instance_id)


func _erase_chunk_refs(chunk_coord: Vector2i) -> void:
	var base_coord := chunk_coord * CHUNK_SIZE
	for local_y in CHUNK_SIZE:
		for local_x in CHUNK_SIZE:
			var coord := base_coord + Vector2i(local_x, local_y)
			for elevation in range(0, core.grid.max_stack_elevation + 1):
				var key := core.grid.slot_key(coord, elevation)
				tile_holders.erase(key)
				tile_instances.erase(key)
				reveal_tiles_in_flight.erase(key)
	for instance_id: int in structure_instances.keys():
		var data: Dictionary = structure_instances[instance_id]
		if data.get("chunk", Vector2i.ZERO) != chunk_coord:
			continue
		structure_instances.erase(instance_id)
		reveal_structures_in_flight.erase(instance_id)


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
