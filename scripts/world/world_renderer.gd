class_name WorldRenderer
extends Node3D
## Reconciles WorldGrid state into scene nodes: tile visuals + walk colliders,
## structures, edge blockers, anchor rest states, and landmark phases.
## State-diff driven (cell_changed / grid_changed) — never per-frame scans.

const BLOCKER_LAYER := 1
const REST_TWEEN_SECONDS := 0.5

var core: GameCore
var assets: AssetLibrary
var materials: MaterialLibrary

const WATER_LEVEL := -0.14

var _tile_nodes: Dictionary = {}        # Vector3i(x, elevation, grid_y) -> Node3D
var _landmark_nodes: Dictionary = {}    # landmark_id -> Node3D
var _edge_root: Node3D
var _silhouette_material: StandardMaterial3D
var _water_surface: WaterSurface
var _tile_visual_factory: TileVisualFactory


func setup(game_core: GameCore, asset_library: AssetLibrary) -> void:
	core = game_core
	assets = asset_library
	materials = asset_library.materials
	_tile_visual_factory = TileVisualFactory.new(assets, core.grid)
	_edge_root = Node3D.new()
	_edge_root.name = "EdgeBlockers"
	add_child(_edge_root)
	_silhouette_material = StandardMaterial3D.new()
	_silhouette_material.albedo_color = Color(0.16, 0.18, 0.15, 0.92)
	_silhouette_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_silhouette_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_water_surface = WaterSurface.new()
	_water_surface.name = "ContinuousWaterSurface"
	add_child(_water_surface)

	core.grid.slot_changed.connect(_on_slot_changed)
	core.grid.grid_changed.connect(_rebuild_edges)
	core.grid.grid_changed.connect(_rebuild_water_surface)
	core.landmarks.opportunity_appeared.connect(func(_s): _sync_landmarks())
	core.landmarks.landmark_revealed.connect(func(_s): _sync_landmarks())
	core.landmarks.landmark_reclaimed.connect(func(_s): _sync_landmarks())
	core.landmarks.landmark_resolved.connect(func(_s, _r): _sync_landmarks())
	rebuild_all()


func rebuild_all() -> void:
	for key in _tile_nodes.keys():
		_tile_nodes[key].queue_free()
	_tile_nodes.clear()
	for slot: Dictionary in core.grid.all_cell_slots():
		_build_cell(slot["coord"], int(slot["elevation"]), false)
	_rebuild_edges()
	_rebuild_water_surface()
	_sync_landmarks()


func _on_slot_changed(coord: Vector2i, elevation: int) -> void:
	var key := core.grid.slot_key(coord, elevation)
	if _tile_nodes.has(key):
		_tile_nodes[key].queue_free()
		_tile_nodes.erase(key)
	if core.grid.has_cell_at(coord, elevation):
		_build_cell(coord, elevation, true)
	if elevation > 0:
		_refresh_covered_surface(coord, elevation - 1)
	if elevation == 0:
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

	var visual := _tile_visual_factory.instantiate_visual(def)
	visual.rotation.y = state.rotation * PI * 0.5
	holder.add_child(visual)
	_apply_covered_surface(visual, coord, elevation, def)
	_attach_ambient_motion(visual, Vector2i(coord.x + elevation * 1009, coord.y))

	_tile_visual_factory.add_collision(holder, def, state.rotation)

	for s in state.structures:
		_build_structure(holder, s)

	_apply_anchor_visual(holder, state, def, false)
	if animate:
		_animate_placement_settle(holder)


func _apply_covered_surface(
	visual: Node3D,
	coord: Vector2i,
	elevation: int,
	def: Defs.TileDefinition
) -> void:
	if not def.supports_tiles:
		return
	var covered := core.grid.has_cell_at(coord, elevation + 1)
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var lower := mesh.name.to_lower()
		var is_block_shell := lower.ends_with("_body") or lower.ends_with("_cap")
		if not is_block_shell:
			mesh.visible = not covered


func _refresh_covered_surface(coord: Vector2i, elevation: int) -> void:
	var holder := tile_node(coord, elevation)
	var def := core.grid.tile_def_at(coord, elevation)
	if holder == null or def == null or holder.get_child_count() == 0:
		return
	var visual := holder.get_child(0) as Node3D
	if visual != null:
		_apply_covered_surface(visual, coord, elevation, def)


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
	var visual := assets.instantiate(def.asset_id)
	visual.name = "struct_%d" % s.instance_id
	visual.position = core.grid.socket_offset(s.socket_index)
	visual.rotation.y = s.rotation * PI * 0.5
	holder.add_child(visual)
	visual.set_meta("instance_id", s.instance_id)
	if def.blocks_movement:
		var body := StaticBody3D.new()
		body.collision_layer = BLOCKER_LAYER
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.9, 1.0, 0.5) if def.id.contains("fence") or def.id.contains("wall") else Vector3(0.8, 1.0, 0.8)
		shape.shape = box
		shape.position.y = 0.5
		body.add_child(shape)
		visual.add_child(body)
	if def.provides.has("light"):
		_add_warm_light(visual, 1.1 if def.id == "struct_campfire" else 0.6)
	if def.id == "struct_campfire":
		_animate_flame(visual)
	_attach_ambient_motion(visual, Vector2i(s.instance_id, s.rotation))


func _add_warm_light(parent: Node3D, energy: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.4)
	light.omni_range = 4.5
	light.position.y = 0.7
	light.light_energy = energy
	light.set_meta("base_energy", energy)
	light.add_to_group("warm_lights")
	parent.add_child(light)
	_animate_local_light(light)


func _animate_flame(campfire: Node3D) -> void:
	for flame_name in ["FlameOuter", "FlameCore"]:
		var flame := campfire.find_child(flame_name, true, false) as Node3D
		if flame == null:
			continue
		var tween := flame.create_tween().set_loops()
		var base := flame.scale
		tween.tween_property(flame, "scale", base * Vector3(0.88, 1.14, 0.88), 0.24).set_trans(Tween.TRANS_SINE)
		tween.tween_property(flame, "scale", base, 0.31).set_trans(Tween.TRANS_SINE)


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
			"position_offsets": [Vector3(0.05, 0.02, -0.03), Vector3(-0.04, -0.01, 0.04)],
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
	var base_position := light.position
	var tween := light.create_tween().set_loops()
	tween.tween_property(light, "position", base_position + Vector3(0.05, 0.02, -0.03), 0.33).set_trans(Tween.TRANS_SINE)
	tween.tween_property(light, "position", base_position + Vector3(-0.04, -0.01, 0.04), 0.33).set_trans(Tween.TRANS_SINE)


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
	var key := core.grid.slot_key(coord, 0)
	if not _tile_nodes.has(key):
		return
	var state := core.grid.cell(coord)
	var def := core.grid.tile_def(coord)
	if state != null and def != null:
		_apply_anchor_visual(_tile_nodes[key], state, def, true)


func tile_node(coord: Vector2i, elevation: int = -1) -> Node3D:
	var target_elevation := core.grid.top_elevation(coord) if elevation < 0 else elevation
	if target_elevation < 0:
		return null
	return _tile_nodes.get(core.grid.slot_key(coord, target_elevation))


# ------------------------------------------------------------------ edges

## Invisible walls at every open edge — continuous boundary, no fall into the
## void, no snap-back. Rebuilt only when the grid shape changes.
func _rebuild_edges() -> void:
	for child in _edge_root.get_children():
		child.queue_free()
	var size := core.grid.tile_size
	for coord: Vector2i in core.grid.cells:
		if not core.grid.is_walkable(coord):
			continue
		for offset: Vector2i in WorldGrid.NEIGHBORS:
			if core.grid.has_cell(coord + offset) and core.grid.is_walkable(coord + offset):
				continue
			var wall := StaticBody3D.new()
			wall.collision_layer = BLOCKER_LAYER
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			var along_x := offset.y != 0
			box.size = Vector3(size, 2.0, 0.12) if along_x else Vector3(0.12, 2.0, size)
			shape.shape = box
			wall.add_child(shape)
			wall.position = core.grid.cell_to_world(coord) + Vector3(offset.x * size * 0.5, 1.0, offset.y * size * 0.5)
			_edge_root.add_child(wall)


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
	mat.albedo_color = Color(0.85, 0.85, 0.78, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist.material_override = mat
	mist.position.y = 0.05
	node.add_child(mist)
	var tween := mist.create_tween().set_loops()
	tween.tween_property(mist, "scale", Vector3(1.06, 1.0, 1.06), 2.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(mist, "scale", Vector3.ONE, 2.2).set_trans(Tween.TRANS_SINE)
