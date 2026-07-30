class_name StructureVisualFactory
extends RefCounted
## Instantiates placeable visuals through their presentation contract.
##
## Most props retain authored dimensions. Grid-spanning structures such as the
## dock opt into a horizontal fit profile so a grid-size tuning change cannot
## leave their geometry overlapping neighbouring tile caps.

const GRID_FIT_MARGIN := 0.02
const AmbientMotionScript := preload("res://scripts/visuals/ambient_motion.gd")
const BurningEffectScript := preload("res://scripts/visuals/burning_effect_3d.gd")

var assets: AssetLibrary
var grid: WorldGrid
var _batch_mesh_cache: Dictionary = {}


func _init(asset_library: AssetLibrary, world_grid: WorldGrid) -> void:
	assets = asset_library
	grid = world_grid


func instantiate_visual(
	definition: Defs.StructureDefinition,
	include_effects := true
) -> Node3D:
	var visual := Node3D.new()
	if definition == null:
		push_warning("StructureVisualFactory received a missing structure definition.")
		return visual
	visual.name = definition.id
	var authored := assets.instantiate(definition.asset_id)
	authored.name = "AuthoredVisual"
	visual.add_child(authored)
	match definition.grid_fit_profile:
		"tile_span":
			_fit_authored_xz_to_tile(authored)
	if definition.has_capability("fire"):
		_hide_authored_fire(authored, definition.capability("fire"))
		if include_effects:
			visual.add_child(instantiate_fire_effect(definition, authored))
	if definition.has_capability("ambient_motion"):
		var motion := AmbientMotionScript.new()
		motion.name = "AmbientMotion"
		visual.add_child(motion)
		motion.configure(authored, definition.capability("ambient_motion"))
	return visual


func instantiate_fire_effect(
	definition: Defs.StructureDefinition,
	authored_visual: Node3D = null
) -> Node3D:
	if definition == null or not definition.has_capability("fire"):
		return Node3D.new()
	var profile := definition.capability("fire")
	var owns_authored := authored_visual == null
	if owns_authored:
		authored_visual = assets.instantiate(definition.asset_id)
		match definition.grid_fit_profile:
			"tile_span":
				_fit_authored_xz_to_tile(authored_visual)
	var effect := BurningEffectScript.new()
	effect.name = "BurningEffect"
	effect.configure(assets.materials, profile, authored_visual)
	if owns_authored:
		authored_visual.free()
	return effect


func _hide_authored_fire(authored: Node3D, profile: Dictionary) -> void:
	var hidden_nodes: Array = profile.get("hide_nodes", [])
	for node_name in hidden_nodes:
		var old_flame := authored.find_child(String(node_name), true, false)
		if old_flame is Node3D:
			(old_flame as Node3D).visible = false


func batch_mesh(definition: Defs.StructureDefinition) -> ArrayMesh:
	if definition == null:
		return null
	if _batch_mesh_cache.has(definition.id):
		return _batch_mesh_cache[definition.id]
	var visual := instantiate_visual(definition, false)
	var combined := assets.flatten_static_visual(visual, definition.id)
	visual.free()
	if combined != null:
		_batch_mesh_cache[definition.id] = combined
	return combined


func clear_asset_edit_cache() -> void:
	_batch_mesh_cache.clear()


func _fit_authored_xz_to_tile(authored: Node3D) -> void:
	var bounds_data := local_mesh_bounds(authored)
	if not bool(bounds_data.get("found", false)):
		return
	var bounds: AABB = bounds_data["bounds"]
	var authored_span := maxf(bounds.size.x, bounds.size.z)
	if authored_span <= 0.0001:
		return
	var target_span := maxf(0.18, grid.tile_size - GRID_FIT_MARGIN)
	var horizontal_scale := target_span / authored_span
	authored.scale = Vector3(
		authored.scale.x * horizontal_scale,
		authored.scale.y,
		authored.scale.z * horizontal_scale
	)


static func local_mesh_bounds(root: Node3D) -> Dictionary:
	var points: Array[Vector3] = []
	_collect_mesh_bounds(root, Transform3D.IDENTITY, points)
	if points.is_empty():
		return {
			"found": false,
			"bounds": AABB(),
		}
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return {
		"found": true,
		"bounds": AABB(minimum, maximum - minimum),
	}


static func _collect_mesh_bounds(
	parent: Node,
	parent_transform: Transform3D,
	points: Array[Vector3]
) -> void:
	if parent is MeshInstance3D:
		var parent_mesh := parent as MeshInstance3D
		if parent_mesh.mesh != null:
			var parent_bounds := parent_mesh.get_aabb()
			for corner_index in 8:
				points.append(
					parent_transform * parent_bounds.get_endpoint(corner_index)
				)
	for child in parent.get_children():
		var child_transform := parent_transform
		if child is Node3D:
			child_transform = parent_transform * (child as Node3D).transform
		_collect_mesh_bounds(child, child_transform, points)
