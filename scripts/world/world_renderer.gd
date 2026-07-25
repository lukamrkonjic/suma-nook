class_name WorldRenderer
extends Node3D
## Reconciles WorldGrid state into scene nodes: tile visuals + walk colliders,
## structures, edge blockers, anchor rest states, and landmark phases.
## State-diff driven (cell_changed / grid_changed) — never per-frame scans.

const GROUND_LAYER := 1
const BLOCKER_LAYER := 1
const REST_TWEEN_SECONDS := 0.5

var core: GameCore
var assets: AssetLibrary
var materials: MaterialLibrary

var _tile_nodes: Dictionary = {}        # Vector2i -> Node3D
var _landmark_nodes: Dictionary = {}    # landmark_id -> Node3D
var _edge_root: Node3D
var _silhouette_material: StandardMaterial3D


func setup(game_core: GameCore, asset_library: AssetLibrary) -> void:
	core = game_core
	assets = asset_library
	materials = asset_library.materials
	_edge_root = Node3D.new()
	_edge_root.name = "EdgeBlockers"
	add_child(_edge_root)
	_silhouette_material = StandardMaterial3D.new()
	_silhouette_material.albedo_color = Color(0.16, 0.18, 0.15, 0.92)
	_silhouette_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_silhouette_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	core.grid.cell_changed.connect(_on_cell_changed)
	core.grid.grid_changed.connect(_rebuild_edges)
	core.landmarks.opportunity_appeared.connect(func(_s): _sync_landmarks())
	core.landmarks.landmark_revealed.connect(func(_s): _sync_landmarks())
	core.landmarks.landmark_reclaimed.connect(func(_s): _sync_landmarks())
	core.landmarks.landmark_resolved.connect(func(_s, _r): _sync_landmarks())
	rebuild_all()


func rebuild_all() -> void:
	for coord: Vector2i in _tile_nodes.keys():
		_tile_nodes[coord].queue_free()
	_tile_nodes.clear()
	for coord: Vector2i in core.grid.cells:
		_build_cell(coord)
	_rebuild_edges()
	_sync_landmarks()


func _on_cell_changed(coord: Vector2i) -> void:
	if _tile_nodes.has(coord):
		_tile_nodes[coord].queue_free()
		_tile_nodes.erase(coord)
	if core.grid.has_cell(coord):
		_build_cell(coord)


func _build_cell(coord: Vector2i) -> void:
	var state := core.grid.cell(coord)
	var def := core.grid.tile_def(coord)
	if def == null:
		return
	var holder := Node3D.new()
	holder.name = "cell_%d_%d" % [coord.x, coord.y]
	holder.position = core.grid.cell_to_world(coord)
	add_child(holder)
	_tile_nodes[coord] = holder

	var visual := _make_open_water_tile() if def.id == "tile_open_water" else assets.instantiate(def.asset_id)
	visual.rotation.y = state.rotation * PI * 0.5
	holder.add_child(visual)

	# Ground collider: one box whose top is exactly y=0 — identical heights on
	# every tile means zero collision seams between connected tiles.
	if def.walkable:
		var body := StaticBody3D.new()
		body.collision_layer = GROUND_LAYER
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(core.grid.tile_size, 0.9, core.grid.tile_size)
		shape.shape = box
		shape.position.y = -0.45
		body.add_child(shape)
		holder.add_child(body)

	# Pond tiles: low blocker over the water basin so the player wades the
	# shore but not the deep middle. Matches the basin authored in the GLB.
	if def.water_cells.has("pond"):
		var water_block := StaticBody3D.new()
		water_block.collision_layer = BLOCKER_LAYER
		var ws := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = Vector3(1.35, 0.8, 1.35)
		ws.shape = wb
		ws.position = Vector3(0.14, 0.4, 0.14).rotated(Vector3.UP, state.rotation * PI * 0.5)
		water_block.add_child(ws)
		holder.add_child(water_block)

	for s in state.structures:
		_build_structure(holder, s)

	_apply_anchor_visual(holder, state, def, false)


func _make_open_water_tile() -> Node3D:
	var root := Node3D.new()
	root.name = "tile_open_water"
	var bed := MeshInstance3D.new()
	var bed_mesh := BoxMesh.new()
	bed_mesh.size = Vector3(core.grid.tile_size, 0.82, core.grid.tile_size)
	bed.mesh = bed_mesh
	bed.position.y = -0.49
	bed.material_override = materials.material("dark_soil")
	root.add_child(bed)
	var surface := MeshInstance3D.new()
	surface.name = "ContinuousWater"
	var water_mesh := BoxMesh.new()
	water_mesh.size = Vector3(core.grid.tile_size + 0.012, 0.14, core.grid.tile_size + 0.012)
	surface.mesh = water_mesh
	surface.position.y = -0.08
	surface.material_override = materials.material("water")
	root.add_child(surface)
	return root


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


func _add_warm_light(parent: Node3D, energy: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.4)
	light.omni_range = 4.5
	light.position.y = 0.7
	light.light_energy = energy
	light.set_meta("base_energy", energy)
	light.add_to_group("warm_lights")
	parent.add_child(light)


func _animate_flame(campfire: Node3D) -> void:
	for flame_name in ["FlameOuter", "FlameCore"]:
		var flame := campfire.find_child(flame_name, true, false) as Node3D
		if flame == null:
			continue
		var tween := flame.create_tween().set_loops()
		var base := flame.scale
		tween.tween_property(flame, "scale", base * Vector3(0.88, 1.14, 0.88), 0.24).set_trans(Tween.TRANS_SINE)
		tween.tween_property(flame, "scale", base, 0.31).set_trans(Tween.TRANS_SINE)


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
	if not _tile_nodes.has(coord):
		return
	var state := core.grid.cell(coord)
	var def := core.grid.tile_def(coord)
	if state != null and def != null:
		_apply_anchor_visual(_tile_nodes[coord], state, def, true)


func tile_node(coord: Vector2i) -> Node3D:
	return _tile_nodes.get(coord)


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
