class_name WorldRenderer
extends Node3D

var _color_system := PaletteDefinition.shared()
## Reconciles WorldGrid state into scene nodes: tile visuals + walk colliders,
## structures, edge blockers, anchor rest states, and landmark phases.
## State-diff driven (cell_changed / grid_changed) — never per-frame scans.

const BLOCKER_LAYER := 1
## Perimeter walls live on their own layer: the player collides with it only
## while grounded, so walking off the island is blocked but a deliberate jump
## sails over the lip (and the water rescue brings them home).
const EDGE_WALL_LAYER := 1 << 3
const PLACEABLE_PICK_LAYER := 1 << 7
const OUTLINE_VISIBILITY_LAYER := 1 << 19
const REST_TWEEN_SECONDS := 0.5
const StructureVisualFactoryScript := preload(
	"res://scripts/world/structure_visual_factory.gd"
)
const FoliageWindScript := preload("res://scripts/visuals/foliage_wind.gd")
const ScalableWorldBackendScript := preload(
	"res://scripts/world/scalable_world_backend.gd"
)
const SCALABLE_WORLD_THRESHOLD := 512

var core: GameCore
var assets: AssetLibrary
var materials: MaterialLibrary

const WATER_LEVEL := -0.14

var _tile_nodes: Dictionary = {}        # Vector3i(x, elevation, grid_y) -> Node3D
var _structure_nodes: Dictionary = {}   # stable structure instance id -> visual
var _landmark_nodes: Dictionary = {}    # landmark_id -> Node3D
var _edge_root: Node3D
var _silhouette_material: StandardMaterial3D
var _water_surface: WaterSurface
var _tile_visual_factory: TileVisualFactory
var _structure_visual_factory: RefCounted
var _outlined_meshes: Array[MeshInstance3D] = []
var _hovered_structure_id := -1
var _hover_signature := ""
var _outline_viewport: SubViewport
var _outline_camera: Camera3D
var _outline_overlay: TextureRect
var _outline_source_camera: Camera3D
var _scalable_backend
var _scalable_mode := false


func setup(game_core: GameCore, asset_library: AssetLibrary) -> void:
	core = game_core
	assets = asset_library
	materials = asset_library.materials
	_tile_visual_factory = TileVisualFactory.new(assets, core.grid)
	_structure_visual_factory = StructureVisualFactoryScript.new(assets, core.grid)
	_scalable_backend = ScalableWorldBackendScript.new()
	_scalable_backend.setup(
		self,
		core,
		assets,
		_tile_visual_factory,
		_structure_visual_factory
	)
	_edge_root = Node3D.new()
	_edge_root.name = "EdgeBlockers"
	add_child(_edge_root)
	_silhouette_material = StandardMaterial3D.new()
	_silhouette_material.albedo_color = _color_system.color("vfx_silhouette")
	_silhouette_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_silhouette_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_setup_screen_space_outline()

	_water_surface = WaterSurface.new()
	_water_surface.name = "ContinuousWaterSurface"
	add_child(_water_surface)

	core.grid.slot_changed.connect(_on_slot_changed)
	core.grid.grid_changed.connect(_on_grid_changed)
	core.landmarks.opportunity_appeared.connect(func(_s): _sync_landmarks())
	core.landmarks.landmark_revealed.connect(func(_s): _sync_landmarks())
	core.landmarks.landmark_reclaimed.connect(func(_s): _sync_landmarks())
	core.landmarks.landmark_resolved.connect(func(_s, _r): _sync_landmarks())
	rebuild_all()


func _process(_delta: float) -> void:
	if (
		_hover_signature == ""
		or _outline_source_camera == null
		or not is_instance_valid(_outline_source_camera)
	):
		return
	_sync_outline_camera()


func _sync_outline_camera() -> void:
	_outline_camera.global_transform = _outline_source_camera.global_transform
	_outline_camera.projection = _outline_source_camera.projection
	_outline_camera.fov = _outline_source_camera.fov
	_outline_camera.size = _outline_source_camera.size
	_outline_camera.near = _outline_source_camera.near
	_outline_camera.far = _outline_source_camera.far
	_outline_camera.keep_aspect = _outline_source_camera.keep_aspect
	_outline_camera.frustum_offset = _outline_source_camera.frustum_offset
	_outline_camera.h_offset = _outline_source_camera.h_offset
	_outline_camera.v_offset = _outline_source_camera.v_offset


func rebuild_all() -> void:
	clear_structure_hover()
	var wants_scalable := (
		core.grid.total_tile_count() >= SCALABLE_WORLD_THRESHOLD
	)
	if wants_scalable:
		for key in _tile_nodes.keys():
			_tile_nodes[key].queue_free()
		_tile_nodes.clear()
		_structure_nodes.clear()
		for child in _edge_root.get_children():
			child.queue_free()
		_water_surface.visible = false
		_water_surface.mesh = null
		_scalable_mode = true
		_scalable_backend.rebuild_all()
		_sync_landmarks()
		return
	if _scalable_mode:
		_scalable_backend.clear()
		_scalable_mode = false
	_water_surface.visible = true
	for key in _tile_nodes.keys():
		_tile_nodes[key].queue_free()
	_tile_nodes.clear()
	_structure_nodes.clear()
	for slot: Dictionary in core.grid.all_cell_slots():
		_build_cell(slot["coord"], int(slot["elevation"]), false)
	_rebuild_edges()
	_rebuild_water_surface()
	_sync_landmarks()


func refresh_asset_edits() -> void:
	## Asset Studio edits must invalidate the composed tile/structure meshes as
	## well as direct AssetLibrary batches. Rebuilding here makes Save visible
	## in the already-running world, including scalable MultiMesh chunks.
	assets.clear_edit_caches()
	_tile_visual_factory.clear_asset_edit_cache()
	_structure_visual_factory.clear_asset_edit_cache()
	rebuild_all()


func _on_slot_changed(coord: Vector2i, elevation: int) -> void:
	var wants_scalable := (
		core.grid.total_tile_count() >= SCALABLE_WORLD_THRESHOLD
	)
	if wants_scalable != _scalable_mode:
		rebuild_all()
		return
	if _scalable_mode:
		_scalable_backend.rebuild_around(coord)
		if core.grid.has_cell_at(coord, elevation):
			_scalable_backend.animate_tile(coord, elevation)
		return
	_remove_cell_node(coord, elevation)
	if core.grid.has_cell_at(coord, elevation):
		_build_cell(coord, elevation, true)
	_refresh_connection_neighbours(coord, elevation)
	if elevation > 0:
		_refresh_covered_surface(coord, elevation - 1, true)
	# Any changed elevation can turn a void edge into a jumpable raised
	# neighbour (or vice versa), so physical perimeter walls follow columns,
	# not only their elevation-zero roots.
	_rebuild_edges()
	if elevation == 0:
		# A moved dock can add or remove a traversable surface on water, so the
		# perimeter opening must follow authoritative structure state.
		_rebuild_water_surface()


func _on_grid_changed() -> void:
	if _scalable_mode:
		return
	_rebuild_edges()
	_rebuild_water_surface()


func _build_cell(coord: Vector2i, elevation: int, animate := false) -> void:
	var state := core.grid.cell_at(coord, elevation)
	var def := core.grid.tile_def_at(coord, elevation)
	if def == null:
		return
	var holder := Node3D.new()
	holder.name = "cell_%d_%d_e%d" % [coord.x, coord.y, elevation]
	holder.position = core.grid.cell_to_world(coord, elevation)
	holder.set_meta("grid_coord", coord)
	holder.set_meta("elevation", elevation)
	add_child(holder)
	_tile_nodes[core.grid.slot_key(coord, elevation)] = holder

	var neighbour_mask := _tile_visual_factory.connection_mask(
		def,
		coord,
		elevation,
		state.rotation
	)
	var visual := _tile_visual_factory.instantiate_visual(
		def,
		false,
		neighbour_mask,
		TileVisualFactory.detail_variant_for_coord(def, coord, elevation)
	)
	visual.rotation.y = state.rotation * PI * 0.5
	holder.add_child(visual)
	_tile_visual_factory.set_stack_seam_visible(visual, elevation > 0)
	_apply_covered_surface(visual, coord, elevation, def)

	_tile_visual_factory.add_collision(holder, def, state.rotation)
	_add_tile_pick_target(holder, visual, coord, elevation)

	for s in state.structures:
		_build_structure(holder, s)

	_apply_anchor_visual(holder, state, def, false)
	if animate:
		_animate_placement_settle(holder)


func _remove_cell_node(coord: Vector2i, elevation: int) -> void:
	var key := core.grid.slot_key(coord, elevation)
	if not _tile_nodes.has(key):
		return
	var previous: Node3D = _tile_nodes[key]
	_unregister_holder_structures(previous)
	# Detach immediately so a topology replacement can keep the stable holder
	# name during the same signal turn; destruction itself stays deferred.
	remove_child(previous)
	previous.queue_free()
	_tile_nodes.erase(key)


func _refresh_connection_neighbours(coord: Vector2i, elevation: int) -> void:
	for offset: Vector2i in WorldGrid.NEIGHBORS:
		var neighbour_coord := coord + offset
		if not core.grid.has_cell_at(neighbour_coord, elevation):
			continue
		_remove_cell_node(neighbour_coord, elevation)
		_build_cell(neighbour_coord, elevation, false)


func _apply_covered_surface(
	visual: Node3D,
	coord: Vector2i,
	elevation: int,
	def: Defs.TileDefinition,
	animate := false
) -> void:
	if not def.supports_tiles:
		return
	var covered := core.grid.has_cell_at(coord, elevation + 1)
	_tile_visual_factory.set_surface_covered(visual, covered, animate)


func _refresh_covered_surface(
	coord: Vector2i,
	elevation: int,
	animate := false
) -> void:
	var holder := tile_node(coord, elevation)
	var def := core.grid.tile_def_at(coord, elevation)
	if holder == null or def == null or holder.get_child_count() == 0:
		return
	var visual := holder.get_child(0) as Node3D
	if visual != null:
		_apply_covered_surface(visual, coord, elevation, def, animate)


## Deterministic per-cell underwater dressing: 2-4 clusters weighted toward
## shorelines (eelgrass, broadleaf, rocks; reeds/lilies only near land).
func _dress_underwater(root: Node3D, coord: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(coord) + 7331
	var shore_dirs: Array[Vector2i] = []
	for offset: Vector2i in WorldGrid.NEIGHBORS:
		var neighbor := coord + offset
		if core.grid.has_cell(neighbor) and core.grid.tile_def(neighbor) != null \
				and core.grid.tile_def(neighbor).render_profile != "continuous_water":
			shore_dirs.append(offset)
	var placed := 0
	var budget := 2 + (rng.randi() % 2) + (1 if shore_dirs.size() > 0 else 0)
	for dir in shore_dirs:
		if placed >= budget:
			break
		var inset := 0.62
		var pos := Vector3(dir.x * inset, WATER_LEVEL - 0.26, dir.y * inset)
		pos += Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var pool := ["prop_uw_eelgrass_a", "prop_uw_eelgrass_b", "prop_uw_eelgrass_c",
				"prop_uw_reeds_a", "prop_uw_reeds_b", "prop_uw_broadleaf_a"]
		_place_uw(root, pool[rng.randi() % pool.size()], pos, rng)
		placed += 1
	if placed < budget and rng.randf() < 0.85:
		var pool := ["prop_uw_rocks_a", "prop_uw_rocks_b", "prop_uw_rocks_c",
				"prop_uw_broadleaf_b", "prop_uw_eelgrass_b"]
		_place_uw(root, pool[rng.randi() % pool.size()],
				Vector3(rng.randf_range(-0.5, 0.5), WATER_LEVEL - 0.27, rng.randf_range(-0.5, 0.5)), rng)
		placed += 1
	if shore_dirs.size() > 0 and rng.randf() < 0.3:
		_place_uw(root, "prop_lily_a" if rng.randf() < 0.6 else "prop_lily_b",
				Vector3(shore_dirs[0].x * 0.45 + rng.randf_range(-0.2, 0.2), WATER_LEVEL + 0.005,
						shore_dirs[0].y * 0.45 + rng.randf_range(-0.2, 0.2)), rng)


func _place_uw(root: Node3D, asset_id: String, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var node := assets.instantiate(asset_id)
	node.position = pos
	node.rotation.y = rng.randf_range(0.0, TAU)
	root.add_child(node)
	var base_y := node.position.y
	var tween := node.create_tween().set_loops()
	var duration := rng.randf_range(1.6, 2.5)
	tween.tween_property(node, "position:y", base_y + rng.randf_range(0.018, 0.04), duration).set_trans(Tween.TRANS_SINE)
	tween.tween_property(node, "position:y", base_y, duration).set_trans(Tween.TRANS_SINE)


func _rebuild_water_surface() -> void:
	var cells: Array = []
	for coord: Vector2i in core.grid.cells:
		var def := core.grid.tile_def(coord)
		if def != null and def.render_profile == "continuous_water":
			cells.append(coord)
	_water_surface.rebuild(cells, func(c: Vector2i) -> Vector3: return core.grid.cell_to_world(c),
			core.grid.tile_size, WATER_LEVEL, materials.material("water"))


func _build_structure(holder: Node3D, s: WorldGrid.StructureState) -> void:
	var def := core.registries.structure(s.structure_id)
	if def == null:
		return
	var harvest_runtime: Dictionary = s.runtime_state.get("harvest", {})
	var visual: Node3D = _structure_visual_factory.instantiate_visual(
		def,
		true,
		int(harvest_runtime.get("visual_seed", s.instance_id))
	)
	visual.name = "struct_%d" % s.instance_id
	# All visuals stay siblings under the tile holder so selecting a jar does
	# not outline its stool (or vice versa). The persistent support graph is
	# resolved into a composed transform instead of a scene-tree hierarchy.
	visual.transform = core.grid.structure_local_transform(s.instance_id)
	holder.add_child(visual)
	visual.set_meta("instance_id", s.instance_id)
	_structure_nodes[s.instance_id] = visual
	if def.has_capability("harvest_source"):
		_structure_visual_factory.sync_harvest_visual(
			visual,
			def,
			String(harvest_runtime.get("state", "maturing")),
			false
		)
		visual.scale = Vector3.ONE * _harvest_visual_scale(s)
	elif def.anchor_id != "" and s.anchor_resting:
		visual.scale = Vector3.ONE * core.registries.tunef(
			"grove_rest_visual_scale", 0.82
		)
	if def.collision_profile == "walkable_surface":
		_align_walkable_surface(visual)
	_add_placeable_pick_target(
		visual,
		s.instance_id,
		holder.get_meta("grid_coord"),
		int(holder.get_meta("elevation"))
	)
	match def.collision_profile:
		"blocker":
			_add_structure_blocker(visual)
		"walkable_surface":
			_add_walkable_structure_surface(visual)
	var is_firepit := def.has_capability("fire")
	if def.has_capability("light"):
		var model_scale: float = (
			_structure_visual_factory.effective_model_scale(def)
		)
		_add_warm_light(
			visual,
			1.1 if is_firepit else 0.6,
			def.light_height * model_scale,
			def.light_flicker
		)
	if is_firepit:
		_apply_burning_state(
			visual,
			core.fire.is_burning(s.instance_id)
		)
	if "tree" in def.placement_tags:
		_attach_tree_wind(visual, s.instance_id)
	else:
		_attach_ambient_motion(visual, Vector2i(s.instance_id, s.rotation))


func _attach_tree_wind(root: Node3D, seed_value: int) -> void:
	var controller := FoliageWindScript.new()
	root.add_child(controller)
	controller.setup(root, seed_value)


func _add_structure_blocker(visual: Node3D) -> void:
	var bounds_data := _visual_local_bounds(visual)
	if not bool(bounds_data.get("found", false)):
		return
	var bounds: AABB = bounds_data["bounds"]
	var body := StaticBody3D.new()
	body.name = "PlaceableMovementBlocker"
	body.collision_layer = BLOCKER_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var raw_size := bounds.size
	box.size = Vector3(
		maxf(0.18, raw_size.x * 0.78),
		maxf(0.15, raw_size.y * 0.92),
		maxf(0.18, raw_size.z * 0.78)
	)
	shape.shape = box
	shape.position = bounds.position + bounds.size * 0.5
	body.add_child(shape)
	visual.add_child(body)


## Deck assets may contain legs or piles below their walking plane. Align the
## highest authored surface with the supporting tile's y=0 plane, then give it
## a thin floor collider rather than turning the complete bounds into a wall.
func _align_walkable_surface(visual: Node3D) -> void:
	var bounds_data := _visual_local_bounds(visual)
	if not bool(bounds_data.get("found", false)):
		return
	var bounds: AABB = bounds_data["bounds"]
	visual.position.y -= bounds.end.y
	visual.set_meta("walkable_surface_local_y", bounds.end.y)


func _add_walkable_structure_surface(visual: Node3D) -> void:
	var bounds_data := _visual_local_bounds(visual)
	if not bool(bounds_data.get("found", false)):
		return
	var bounds: AABB = bounds_data["bounds"]
	var surface_y := float(
		visual.get_meta("walkable_surface_local_y", bounds.end.y)
	)
	var body := StaticBody3D.new()
	body.name = "WalkableStructureSurface"
	body.collision_layer = BLOCKER_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var thickness := 0.10
	# A tiny physical inset keeps CharacterBody3D's safety margin from catching
	# the deck's vertical edge where it meets an ordinary tile. The authored
	# planks remain visually flush at y=0.
	var seam_inset := 0.03
	box.size = Vector3(
		maxf(0.18, bounds.size.x * 0.96),
		thickness,
		maxf(0.18, bounds.size.z * 0.96)
	)
	shape.shape = box
	shape.position = Vector3(
		bounds.get_center().x,
		surface_y - seam_inset - thickness * 0.5,
		bounds.get_center().z
	)
	body.add_child(shape)
	visual.add_child(body)


func _visual_local_bounds(visual: Node3D) -> Dictionary:
	var found := false
	var minimum := Vector3.ZERO
	var maximum := Vector3.ZERO
	var visual_inverse := visual.global_transform.affine_inverse()
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local_transform := visual_inverse * mesh_instance.global_transform
		var mesh_bounds := mesh_instance.get_aabb()
		for corner_index in 8:
			var point := local_transform * mesh_bounds.get_endpoint(corner_index)
			if not found:
				minimum = point
				maximum = point
				found = true
			else:
				minimum = minimum.min(point)
				maximum = maximum.max(point)
	return {
		"found": found,
		"bounds": AABB(minimum, maximum - minimum),
	}


func _add_warm_light(
	parent: Node3D,
	energy: float,
	height: float,
	flicker: bool
) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = _color_system.color("vfx_local_light")
	light.omni_range = 4.5
	light.position.y = height
	light.light_energy = energy
	light.set_meta("base_energy", energy)
	light.add_to_group("warm_lights")
	parent.add_child(light)
	if flicker:
		_animate_local_light(light)
	return light


func _apply_burning_state(visual: Node3D, active: bool) -> void:
	var effect := visual.find_child("BurningEffect", true, false)
	if effect != null and effect.has_method("set_burning"):
		effect.set_burning(active)
	for child in visual.find_children("*", "OmniLight3D", true, false):
		(child as OmniLight3D).visible = active


func set_structure_burning(instance_id: int, active: bool) -> void:
	if _scalable_mode:
		_scalable_backend.set_structure_burning(instance_id, active)
		return
	var visual := structure_node(instance_id)
	if visual != null:
		_apply_burning_state(visual, active)


func structure_fire_world_position(instance_id: int) -> Vector3:
	var found := core.grid.find_structure(instance_id)
	if found.is_empty():
		return Vector3.ZERO
	var structure: WorldGrid.StructureState = found["structure"]
	var definition := core.registries.structure(structure.structure_id)
	var offset := Vector3.ZERO
	if definition != null and definition.has_capability("fire"):
		var offset_data: Array = (
			definition.capability("fire").get("offset", [])
		)
		if offset_data.size() >= 3:
			offset = Vector3(
				float(offset_data[0]),
				float(offset_data[1]),
				float(offset_data[2])
			)
	var world_transform := (
		Transform3D(
			Basis.IDENTITY,
			core.grid.cell_to_world(
				found["coord"],
				int(found["elevation"])
			)
		)
		* core.grid.structure_local_transform(instance_id)
	)
	return world_transform * offset


## State has already committed before this presentation starts. The measured
## placement language is a 2.5° two-beat wobble with 0.02 s beats; a short
## 0.12 s settle keeps that readable at ordinary frame rates.
func _animate_placement_settle(holder: Node3D) -> void:
	var target_position := holder.position
	holder.position.y += 0.1
	holder.scale = Vector3.ONE * 0.96
	holder.rotation_degrees.z = 2.5
	var tween := holder.create_tween()
	tween.set_parallel(true)
	tween.tween_property(holder, "position", target_position, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(holder, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_property(holder, "rotation_degrees:z", -2.5, 0.02)
	tween.tween_property(holder, "rotation_degrees:z", 1.25, 0.02)
	tween.tween_property(holder, "rotation_degrees:z", 0.0, 0.08).set_trans(Tween.TRANS_SINE)


## The first island is not an ordinary build placement: its 3×3 land square,
## water ring, and tree rise through the empty sky beneath the waiting keeper.
func animate_arrival_island() -> void:
	for slot: Dictionary in core.grid.all_cell_slots():
		if int(slot["elevation"]) != 0:
			continue
		var coord: Vector2i = slot["coord"]
		var holder := tile_node(coord, 0)
		if holder == null:
			continue
		var target_position := core.grid.cell_to_world(coord, 0)
		var delay := float(maxi(absi(coord.x), absi(coord.y))) * 0.035
		holder.position = target_position + Vector3.DOWN * 1.55
		holder.scale = Vector3.ONE * 0.68
		holder.rotation_degrees.z = float(coord.x) * 1.2
		var tween := holder.create_tween()
		if delay > 0.0:
			tween.tween_interval(delay)
		tween.set_parallel(true)
		tween.tween_property(holder, "position", target_position, 0.56) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(holder, "scale", Vector3.ONE, 0.48) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(holder, "rotation_degrees:z", 0.0, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func animation_manifest() -> Dictionary:
	return {
		"tile_placement": {
			"duration": 0.24,
			"events": [{"name": "settled", "time": 0.24}],
			"tracks": {
				"position.y": [
					{"time": 0.0, "offset": 0.1},
					{"time": 0.12, "offset": 0.0, "curve": "quad_out"},
				],
				"scale": [
					{"time": 0.0, "value": 0.96},
					{"time": 0.12, "value": 1.0, "curve": "back_out"},
				],
				"rotation.z_degrees": [
					{"time": 0.0, "value": 2.5},
					{"time": 0.14, "value": -2.5, "curve": "linear"},
					{"time": 0.16, "value": 1.25, "curve": "linear"},
					{"time": 0.24, "value": 0.0, "curve": "sine_in_out"},
				],
			},
		},
		"foliage_ambient": {
			"looping": true,
			"duration_range_per_half_cycle": [1.35, 2.4],
			"rotation_amplitude_degrees": [0.8, 2.2],
			"curve": "sine_in_out",
			"deterministic_per_instance": true,
		},
		"underwater_bob": {
			"looping": true,
			"duration_range_per_half_cycle": [1.6, 2.5],
			"height_range": [0.018, 0.04],
			"curve": "sine_in_out",
			"deterministic_per_cell": true,
		},
		"warm_light_flicker": {
			"looping": true,
			"half_cycle": 0.33,
			"energy_multiplier_range": [0.92, 1.05],
			"curve": "sine_in_out",
		},
	}


func _attach_ambient_motion(root: Node3D, seed_key: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key) + 1919
	for child in root.find_children("*", "Node3D", true, false):
		var node := child as Node3D
		if node == null or node.has_meta("ambient_motion"):
			continue
		var lower := node.name.to_lower()
		if not (
			lower.contains("leaf")
			or lower.contains("tier")
			or lower.contains("grass")
			or lower.contains("flower")
			or lower.contains("reed")
			or lower.contains("tuft")
		):
			continue
		node.set_meta("ambient_motion", true)
		var base_z := node.rotation.z
		var amplitude := deg_to_rad(rng.randf_range(0.6, 1.8))
		var duration := rng.randf_range(1.5, 2.8)
		var tween := node.create_tween().set_loops()
		tween.tween_interval(rng.randf_range(0.0, 0.8))
		tween.tween_property(node, "rotation:z", base_z + amplitude, duration).set_trans(Tween.TRANS_SINE)
		tween.tween_property(node, "rotation:z", base_z - amplitude, duration * 1.07).set_trans(Tween.TRANS_SINE)


func _animate_local_light(light: OmniLight3D) -> void:
	var base_energy := float(light.get_meta("base_energy", light.light_energy))
	var tween := light.create_tween().set_loops()
	tween.tween_method(
		func(multiplier: float):
			light.light_energy = (
				base_energy
				* float(light.get_meta("time_energy_scale", 1.0))
				* multiplier
			),
		1.0,
		1.05,
		0.33
	).set_trans(Tween.TRANS_SINE)
	tween.tween_method(
		func(multiplier: float):
			light.light_energy = (
				base_energy
				* float(light.get_meta("time_energy_scale", 1.0))
				* multiplier
			),
		1.05,
		0.92,
		0.33
	).set_trans(Tween.TRANS_SINE)


## Grove rest: vegetation gently shrinks and desaturates while regrowing —
## still attractive, clearly resting, never a dirt patch.
func _apply_anchor_visual(holder: Node3D, state: WorldGrid.CellState, def: Defs.TileDefinition, animate: bool) -> void:
	if def.anchor_id == "" or def.water_cells.has("pond"):
		return
	var target_scale: float = core.registries.tunef("grove_rest_visual_scale", 0.82) if state.anchor_resting else 1.0
	for child in holder.get_child(0).get_children():
		var node := child as Node3D
		if node == null:
			continue
		var lower := node.name.to_lower()
		if lower.contains("trunk") or lower.contains("tier") or lower.contains("leaf"):
			if animate:
				var tween := node.create_tween()
				tween.tween_property(node, "scale", Vector3.ONE * target_scale, REST_TWEEN_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			else:
				node.scale = Vector3.ONE * target_scale


func refresh_anchor(coord: Vector2i) -> void:
	if _scalable_mode:
		_scalable_backend.rebuild_around(coord)
		return
	var key := core.grid.slot_key(coord, 0)
	if not _tile_nodes.has(key):
		return
	var state := core.grid.cell(coord)
	var def := core.grid.tile_def(coord)
	if state != null and def != null:
		_apply_anchor_visual(_tile_nodes[key], state, def, true)


func refresh_structure_anchor(instance_id: int, animate := true) -> void:
	var found := core.grid.find_structure(instance_id)
	if _scalable_mode:
		if not found.is_empty():
			_scalable_backend.rebuild_around(found["coord"])
		return
	var visual := structure_node(instance_id)
	if found.is_empty() or visual == null:
		return
	var structure: WorldGrid.StructureState = found["structure"]
	var target_scale := (
		Vector3.ONE * core.registries.tunef("grove_rest_visual_scale", 0.82)
		if structure.anchor_resting
		else Vector3.ONE
	)
	if not animate:
		visual.scale = target_scale
		return
	var tween := visual.create_tween()
	tween.tween_property(visual, "scale", target_scale, REST_TWEEN_SECONDS).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)


func refresh_structure_harvest(instance_id: int, animate := true) -> void:
	var found := core.grid.find_structure(instance_id)
	var visual := structure_node(instance_id)
	if found.is_empty() or visual == null:
		return
	var structure: WorldGrid.StructureState = found["structure"]
	var definition := core.registries.structure(structure.structure_id)
	var runtime: Dictionary = structure.runtime_state.get("harvest", {})
	_structure_visual_factory.sync_harvest_visual(
		visual,
		definition,
		String(runtime.get("state", "maturing")),
		animate
	)
	var target := Vector3.ONE * _harvest_visual_scale(structure)
	if not animate:
		visual.scale = target
		return
	var tween := visual.create_tween()
	tween.tween_property(visual, "scale", target, 0.46).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)


func _harvest_visual_scale(structure: WorldGrid.StructureState) -> float:
	var runtime: Dictionary = structure.runtime_state.get("harvest", {})
	var profile: Defs.HarvestProfileDefinition = (
		core.harvesting.profile_for_structure(structure)
	)
	if profile != null and profile.presentation_profile == "berry_cluster":
		# Fruit changes state; the replaceable host model remains fully grown.
		return 1.0
	match String(runtime.get("state", "maturing")):
		"ready": return 1.0
		"regrowing": return 0.28
		_: return 0.72


func tile_node(coord: Vector2i, elevation: int = -1) -> Node3D:
	var target_elevation := core.grid.top_elevation(coord) if elevation < 0 else elevation
	if target_elevation < 0:
		return null
	if _scalable_mode:
		return _scalable_backend.tile_node(coord, target_elevation)
	return _tile_nodes.get(core.grid.slot_key(coord, target_elevation))


# ------------------------------------------------------------------ placeable picking / hover

func _setup_screen_space_outline() -> void:
	_outline_viewport = SubViewport.new()
	_outline_viewport.name = "PlaceableOutlineViewport"
	_outline_viewport.transparent_bg = true
	_outline_viewport.world_3d = get_world_3d()
	_outline_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_outline_viewport.handle_input_locally = false
	add_child(_outline_viewport)

	_outline_camera = Camera3D.new()
	_outline_camera.name = "PlaceableOutlineCamera"
	_outline_camera.cull_mask = OUTLINE_VISIBILITY_LAYER
	_outline_camera.current = true
	_outline_viewport.add_child(_outline_camera)

	var canvas := CanvasLayer.new()
	canvas.name = "PlaceableOutlineCanvas"
	canvas.layer = 5
	add_child(canvas)
	_outline_overlay = TextureRect.new()
	_outline_overlay.name = "PlaceableOutlineOverlay"
	_outline_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_outline_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_outline_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline_overlay.texture = _outline_viewport.get_texture()
	_outline_overlay.visible = false
	canvas.add_child(_outline_overlay)

	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;

uniform vec4 outline_color : source_color = vec4(1.0, 0.99, 0.96, 1.0);
uniform float outline_width_pixels = 2.25;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * outline_width_pixels;
	float center = texture(TEXTURE, UV).a;
	float around = 0.0;
	around = max(around, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	around = max(around, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	around = max(around, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	around = max(around, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
	around = max(around, texture(TEXTURE, UV + px).a);
	around = max(around, texture(TEXTURE, UV - px).a);
	around = max(around, texture(TEXTURE, UV + vec2(px.x, -px.y)).a);
	around = max(around, texture(TEXTURE, UV + vec2(-px.x, px.y)).a);
	float outline = smoothstep(0.08, 0.65, around) * (1.0 - smoothstep(0.02, 0.35, center));
	COLOR = vec4(outline_color.rgb, outline_color.a * outline);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	_outline_overlay.material = material
	_resize_outline_viewport()
	get_viewport().size_changed.connect(_resize_outline_viewport)


func _resize_outline_viewport() -> void:
	if _outline_viewport == null:
		return
	var size := Vector2i(get_viewport().get_visible_rect().size)
	_outline_viewport.size = Vector2i(maxi(1, size.x), maxi(1, size.y))
	_outline_overlay.position = Vector2.ZERO
	_outline_overlay.size = Vector2(_outline_viewport.size)


func _add_placeable_pick_target(
	visual: Node3D,
	instance_id: int,
	coord: Vector2i,
	elevation: int
) -> void:
	var body := StaticBody3D.new()
	body.name = "PlaceablePickTarget"
	body.collision_layer = PLACEABLE_PICK_LAYER
	body.collision_mask = 0
	body.set_meta("placeable_kind", "structure")
	body.set_meta("structure_instance_id", instance_id)
	body.set_meta("grid_coord", coord)
	body.set_meta("elevation", elevation)
	visual.add_child(body)

	var visual_inverse := visual.global_transform.affine_inverse()
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var trimesh := mesh_instance.mesh.create_trimesh_shape()
		if trimesh == null:
			continue
		var shape := CollisionShape3D.new()
		shape.shape = trimesh
		shape.transform = visual_inverse * mesh_instance.global_transform
		body.add_child(shape)

	if body.get_child_count() == 0:
		var fallback := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.75, 1.0, 0.75)
		fallback.shape = box
		fallback.position.y = 0.5
		body.add_child(fallback)


func _add_tile_pick_target(
	holder: Node3D,
	visual: Node3D,
	coord: Vector2i,
	elevation: int
) -> void:
	var body := StaticBody3D.new()
	body.name = "TilePickTarget"
	body.collision_layer = PLACEABLE_PICK_LAYER
	body.collision_mask = 0
	body.set_meta("placeable_kind", "tile")
	body.set_meta("grid_coord", coord)
	body.set_meta("elevation", elevation)
	holder.add_child(body)
	var holder_inverse := holder.global_transform.affine_inverse()
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var trimesh := mesh_instance.mesh.create_trimesh_shape()
		if trimesh == null:
			continue
		var shape := CollisionShape3D.new()
		shape.shape = trimesh
		shape.transform = holder_inverse * mesh_instance.global_transform
		body.add_child(shape)
	if body.get_child_count() == 0:
		var fallback := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(
			core.grid.tile_size * 0.96,
			core.grid.block_depth,
			core.grid.tile_size * 0.96
		)
		fallback.shape = box
		fallback.position.y = -core.grid.block_depth * 0.5
		body.add_child(fallback)


func pick_placeable_at_screen(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	if camera == null or not is_inside_tree():
		return {}
	_outline_source_camera = camera
	if _scalable_mode:
		var structure_hit: Dictionary = _scalable_backend.structure_hit(
			camera,
			screen_position
		)
		if not structure_hit.is_empty():
			return structure_hit
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * 1000.0,
		PLACEABLE_PICK_LAYER
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider := hit.get("collider") as CollisionObject3D
	if collider == null:
		return {}
	if _scalable_mode and collider.has_meta("scalable_terrain"):
		return _scalable_backend.terrain_hit(
			hit.get("position", Vector3.ZERO)
		)
	if not collider.has_meta("placeable_kind"):
		return {}
	var result := {
		"kind": String(collider.get_meta("placeable_kind")),
		"coord": collider.get_meta("grid_coord"),
		"elevation": int(collider.get_meta("elevation")),
		"point": hit.get("position", Vector3.ZERO),
	}
	if result["kind"] == "structure":
		result["instance_id"] = int(collider.get_meta("structure_instance_id"))
	return result


func pick_structure_at_screen(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	var result := pick_placeable_at_screen(camera, screen_position)
	return result if result.get("kind", "") == "structure" else {}


func set_hovered_structure(instance_id: int, include_descendants := true) -> void:
	var signature := "structure:%d:%s" % [instance_id, str(include_descendants)]
	if _hover_signature == signature:
		return
	var nodes: Array[Node3D] = []
	var structures := (
		core.grid.structure_subtree(instance_id)
		if include_descendants
		else []
	)
	if not include_descendants:
		var found := core.grid.find_structure(instance_id)
		if not found.is_empty():
			structures = [found["structure"]]
	for structure: WorldGrid.StructureState in structures:
		var visual := structure_node(structure.instance_id)
		if visual != null:
			nodes.append(visual)
	_set_hover_nodes(nodes, signature, instance_id)


func set_hovered_tile(
	coord: Vector2i,
	elevation: int,
	include_above := true
) -> void:
	var signature := "tile:%d:%d:%d:%s" % [
		coord.x,
		coord.y,
		elevation,
		str(include_above),
	]
	if _hover_signature == signature:
		return
	var nodes: Array[Node3D] = []
	var top := core.grid.top_elevation(coord) if include_above else elevation
	for layer in range(elevation, top + 1):
		var holder := tile_node(coord, layer)
		if holder != null:
			nodes.append(holder)
	_set_hover_nodes(nodes, signature, -1)


func _set_hover_nodes(
	nodes: Array[Node3D],
	signature: String,
	structure_instance_id: int
) -> void:
	clear_structure_hover()
	if nodes.is_empty():
		return
	if _outline_source_camera == null or not is_instance_valid(_outline_source_camera):
		_outline_source_camera = get_viewport().get_camera_3d()
	if _outline_source_camera == null:
		return
	_sync_outline_camera()
	_hovered_structure_id = structure_instance_id
	_hover_signature = signature
	var seen := {}
	for node: Node3D in nodes:
		for child in node.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := child as MeshInstance3D
			if seen.has(mesh_instance.get_instance_id()):
				continue
			seen[mesh_instance.get_instance_id()] = true
			mesh_instance.set_meta("_outline_previous_layers", mesh_instance.layers)
			mesh_instance.layers |= OUTLINE_VISIBILITY_LAYER
			_outlined_meshes.append(mesh_instance)
	_outline_overlay.visible = true
	_outline_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func clear_structure_hover() -> void:
	for mesh_instance: MeshInstance3D in _outlined_meshes:
		if is_instance_valid(mesh_instance):
			mesh_instance.layers = int(
				mesh_instance.get_meta("_outline_previous_layers", mesh_instance.layers & ~OUTLINE_VISIBILITY_LAYER)
			)
			mesh_instance.remove_meta("_outline_previous_layers")
	_outlined_meshes.clear()
	if _outline_overlay != null:
		_outline_overlay.visible = false
	if _outline_viewport != null:
		_outline_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_hovered_structure_id = -1
	_hover_signature = ""


func hovered_structure_id() -> int:
	return _hovered_structure_id


func structure_node(instance_id: int) -> Node3D:
	var visual := _structure_nodes.get(instance_id) as Node3D
	if visual == null or not is_instance_valid(visual):
		_structure_nodes.erase(instance_id)
		return null
	return visual


func debug_stats() -> Dictionary:
	if _scalable_mode and _scalable_backend != null:
		var stats: Dictionary = _scalable_backend.debug_stats()
		stats["mode"] = "chunked"
		return stats
	var models := _structure_nodes.size()
	return {
		"mode": "exact",
		"chunks": 1 if models > 0 else 0,
		"batches": 0,
		"models": models,
		"instances": _tile_nodes.size() + models,
		"water_chunks": (
			1
			if _water_surface != null and _water_surface.mesh != null
			else 0
		),
		"collision_chunks": _tile_nodes.size(),
		"warm_lights": get_tree().get_nodes_in_group("warm_lights").size(),
	}


func support_slot_world_transform(parent_instance_id: int, slot_id: String) -> Transform3D:
	var found := core.grid.find_structure(parent_instance_id)
	if found.is_empty():
		return Transform3D.IDENTITY
	if _scalable_mode:
		return (
			Transform3D(
				Basis.IDENTITY,
				core.grid.cell_to_world(
					found["coord"],
					int(found["elevation"])
				)
			)
			* core.grid.support_slot_local_transform(
				parent_instance_id,
				slot_id
			)
		)
	var holder := tile_node(found["coord"], int(found["elevation"]))
	if holder == null:
		return Transform3D.IDENTITY
	return holder.global_transform * core.grid.support_slot_local_transform(
		parent_instance_id,
		slot_id
	)


func structure_preview_position(instance_id: int) -> Vector3:
	if _scalable_mode:
		var found := core.grid.find_structure(instance_id)
		if found.is_empty():
			return Vector3.ZERO
		return (
			core.grid.cell_to_world(
				found["coord"],
				int(found["elevation"])
			)
			+ core.grid.structure_local_transform(instance_id).origin
			+ Vector3.UP * 0.75
		)
	var visual := structure_node(instance_id)
	if visual == null:
		return Vector3.ZERO
	var bounds_found := false
	var highest := visual.global_position.y
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		var local_aabb := mesh.get_aabb()
		for corner_index in 8:
			var corner := mesh.global_transform * local_aabb.get_endpoint(corner_index)
			highest = maxf(highest, corner.y)
			bounds_found = true
	return Vector3(
		visual.global_position.x,
		highest if bounds_found else visual.global_position.y + 0.5,
		visual.global_position.z
	)


func animate_structure_settle(instance_id: int) -> void:
	if _scalable_mode:
		return
	var visual := structure_node(instance_id)
	if visual == null:
		return
	var target := visual.position
	visual.position.y += 0.12
	visual.scale = Vector3.ONE * 0.94
	var tween := visual.create_tween().set_parallel(true)
	tween.tween_property(visual, "position", target, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _unregister_holder_structures(holder: Node3D) -> void:
	var holder_was_outlined := false
	for outlined: MeshInstance3D in _outlined_meshes:
		if is_instance_valid(outlined) and holder.is_ancestor_of(outlined):
			holder_was_outlined = true
			break
	if holder_was_outlined:
		clear_structure_hover()
	for child in holder.find_children("*", "Node3D", true, false):
		var node := child as Node3D
		if not node.has_meta("instance_id"):
			continue
		var instance_id := int(node.get_meta("instance_id"))
		_structure_nodes.erase(instance_id)


# ------------------------------------------------------------------ edges

## Invisible walls at every open edge — continuous boundary, no fall into the
## void, no snap-back. Rebuilt only when the grid shape changes.
func _rebuild_edges() -> void:
	for child in _edge_root.get_children():
		child.queue_free()
	var size := core.grid.tile_size
	for coord: Vector2i in core.grid.cells:
		if not _has_physical_walk_surface(coord):
			continue
		for offset: Vector2i in WorldGrid.NEIGHBORS:
			if (
				core.grid.has_cell(coord + offset)
				and _has_physical_walk_surface(coord + offset)
			):
				continue
			var wall := StaticBody3D.new()
			wall.collision_layer = EDGE_WALL_LAYER
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			var along_x := offset.y != 0
			box.size = Vector3(size, 2.0, 0.12) if along_x else Vector3(0.12, 2.0, size)
			shape.shape = box
			wall.add_child(shape)
			var surface_elevation := maxi(0, core.grid.top_elevation(coord))
			wall.position = (
				core.grid.cell_to_world(coord, surface_elevation)
				+ Vector3(offset.x * size * 0.5, 1.0, offset.y * size * 0.5)
			)
			_edge_root.add_child(wall)


func _has_physical_walk_surface(coord: Vector2i) -> bool:
	return (
		core.grid.has_walkable_top_surface(coord)
		or core.grid.has_walkable_structure_surface(coord)
	)


# ------------------------------------------------------------------ landmarks

func _sync_landmarks() -> void:
	if not core.registries.feature("hostile_landmarks_enabled", false):
		for node in _landmark_nodes.values():
			node.queue_free()
		_landmark_nodes.clear()
		return
	var seen := {}
	for state in core.landmarks.active:
		seen[state.landmark_id] = true
		var def := core.registries.landmark(state.landmark_id)
		var node: Node3D = _landmark_nodes.get(state.landmark_id)
		var wanted_phase := state.phase
		if node != null and node.get_meta("phase", "") == wanted_phase:
			continue
		if node != null:
			node.queue_free()
		node = Node3D.new()
		node.name = "landmark_" + state.landmark_id
		node.set_meta("phase", wanted_phase)
		# Center of the footprint.
		var center := Vector3.ZERO
		for cell in core.landmarks.footprint_cells(state):
			center += core.grid.cell_to_world(cell)
		center /= maxf(1.0, def.footprint.size())
		node.position = center
		add_child(node)
		_landmark_nodes[state.landmark_id] = node

		var visual := assets.instantiate(def.asset_id)
		visual.position = Vector3.ZERO
		node.add_child(visual)
		if wanted_phase == LandmarkManager.PHASE_SILHOUETTE:
			_apply_silhouette(visual)
			_add_mist(node)
		elif wanted_phase == LandmarkManager.PHASE_RECLAIMED and def.reclaimed_dressing_asset != "":
			var dressing := assets.instantiate(def.reclaimed_dressing_asset)
			node.add_child(dressing)
	for landmark_id: String in _landmark_nodes.keys():
		if not seen.has(landmark_id):
			_landmark_nodes[landmark_id].queue_free()
			_landmark_nodes.erase(landmark_id)


func _apply_silhouette(visual: Node3D) -> void:
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, _silhouette_material)


func _add_mist(node: Node3D) -> void:
	var mist := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 3.6
	disc.bottom_radius = 3.6
	disc.height = 0.08
	mist.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color_system.color("vfx_mist_disc")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist.material_override = mat
	mist.position.y = 0.05
	node.add_child(mist)
	var tween := mist.create_tween().set_loops()
	tween.tween_property(mist, "scale", Vector3(1.06, 1.0, 1.06), 2.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(mist, "scale", Vector3.ONE, 2.2).set_trans(Tween.TRANS_SINE)
