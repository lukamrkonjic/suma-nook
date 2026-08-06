class_name StructureVisualFactory
extends RefCounted
## Instantiates placeable visuals through their presentation contract.
##
## Every catalog model receives the shared world-model calibration. Grid-
## spanning structures such as the dock already derive their X/Z footprint
## from the live tile and therefore receive the shared scale vertically only.

const GRID_FIT_MARGIN := 0.02
const SURFACE_MASK_MIN_CONTACT_BAND := 0.06
const SURFACE_MASK_MAX_CONTACT_BAND := 0.18
const SURFACE_MASK_CONTACT_BAND_RATIO := 0.12
const AmbientMotionScript := preload("res://scripts/visuals/ambient_motion.gd")
const BurningEffectScript := preload("res://scripts/visuals/burning_effect_3d.gd")
const BerryGrowthVisualScript := preload(
	"res://scripts/features/harvesting/presentation/berry_growth_visual.gd"
)

var assets: AssetLibrary
var grid: WorldGrid
var _batch_mesh_cache: Dictionary = {}
var _surface_contact_mask_cache: Dictionary = {}


func _init(asset_library: AssetLibrary, world_grid: WorldGrid) -> void:
	assets = asset_library
	grid = world_grid


func instantiate_visual(
	definition: Defs.StructureDefinition,
	include_effects := true,
	visual_seed := 0
) -> Node3D:
	var visual := Node3D.new()
	if definition == null:
		push_warning("StructureVisualFactory received a missing structure definition.")
		return visual
	visual.name = definition.id
	var authored := assets.instantiate(definition.asset_id)
	authored.name = "AuthoredVisual"
	visual.add_child(authored)
	_prepare_authored_visual(authored, definition)
	_attach_harvest_presentation(visual, definition, visual_seed)
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


func _attach_harvest_presentation(
	visual: Node3D,
	definition: Defs.StructureDefinition,
	visual_seed: int
) -> void:
	if not definition.has_capability("harvest_source"):
		return
	var profile_id := String(
		definition.capability("harvest_source").get("profile_id", "")
	)
	var profile := grid.registries.harvest_profile(profile_id)
	if profile == null or profile.presentation_profile != "berry_cluster":
		return
	var bounds_data := local_mesh_bounds(visual)
	if not bool(bounds_data.get("found", false)):
		return
	var growth := BerryGrowthVisualScript.new()
	growth.name = "HarvestYieldVisual"
	visual.add_child(growth)
	growth.configure(
		assets.materials,
		profile.presentation_settings,
		visual_seed if visual_seed != 0 else hash(definition.id),
		bounds_data["bounds"]
	)


func sync_harvest_visual(
	visual: Node3D,
	definition: Defs.StructureDefinition,
	state: String,
	animate := true
) -> void:
	if visual == null or definition == null:
		return
	var yield_visual := visual.find_child("HarvestYieldVisual", true, false)
	if yield_visual != null and yield_visual.has_method("set_harvest_state"):
		yield_visual.call("set_harvest_state", state, animate)


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
		_prepare_authored_visual(authored_visual, definition)
	var effect := BurningEffectScript.new()
	effect.name = "BurningEffect"
	effect.configure(assets.materials, profile, authored_visual)
	# Fire geometry is a sibling of the authored model. Scale it explicitly so
	# flame dimensions, offsets, and duplicated fuel overlays stay registered.
	effect.scale = Vector3.ONE * effective_model_scale(definition)
	if owns_authored:
		authored_visual.free()
	return effect


func _hide_authored_fire(authored: Node3D, profile: Dictionary) -> void:
	var hidden_nodes: Array = profile.get("hide_nodes", [])
	for node_name in hidden_nodes:
		var old_flame := authored.find_child(String(node_name), true, false)
		if old_flame is Node3D:
			(old_flame as Node3D).visible = false


func batch_mesh(
	definition: Defs.StructureDefinition,
	harvest_state := "ready"
) -> ArrayMesh:
	if definition == null:
		return null
	var cache_key := "%s|%s" % [definition.id, harvest_state]
	if _batch_mesh_cache.has(cache_key):
		return _batch_mesh_cache[cache_key]
	var visual := instantiate_visual(definition, false)
	sync_harvest_visual(visual, definition, harvest_state, false)
	var combined := assets.flatten_static_visual(visual, definition.id)
	visual.free()
	if combined != null:
		_batch_mesh_cache[cache_key] = combined
	return combined


func clear_asset_edit_cache() -> void:
	_batch_mesh_cache.clear()
	_surface_contact_mask_cache.clear()


## Returns model contact footprints in tile-visual local space. Only objects
## directly supported by the tile participate; children sitting on benches,
## tables, or other support slots must not clear the terrain beneath them.
func surface_masks_for_tile(
	state: WorldGrid.CellState,
	tile_rotation_quarters: int
) -> Array[PackedVector2Array]:
	var masks: Array[PackedVector2Array] = []
	if state == null or state.structures.is_empty():
		return masks
	var tile_transform := Transform3D(
		Basis(Vector3.UP, tile_rotation_quarters * PI * 0.5),
		Vector3.ZERO
	)
	var tile_inverse := tile_transform.affine_inverse()
	for structure: WorldGrid.StructureState in state.structures:
		if structure.parent_instance_id != 0:
			continue
		var definition := grid.registries.structure(structure.structure_id)
		var model_mask := surface_contact_mask(definition)
		if model_mask.size() < 3:
			continue
		var relative_transform := (
			tile_inverse
			* grid.structure_local_transform_in_cell(state, structure.instance_id)
		)
		var tile_mask := PackedVector2Array()
		for point: Vector2 in model_mask:
			var transformed := relative_transform * Vector3(point.x, 0.0, point.y)
			tile_mask.append(Vector2(transformed.x, transformed.z))
		masks.append(tile_mask)
	return masks


## The exclusion shape follows the authored model's actual near-ground
## geometry instead of its complete AABB. A tree therefore clears around its
## trunk rather than its canopy, while a firepit follows the stone ring and a
## bench spans its feet. The result is cached per edited model definition.
func surface_contact_mask(
	definition: Defs.StructureDefinition
) -> PackedVector2Array:
	if definition == null:
		return PackedVector2Array()
	var cache_key := definition.id
	if _surface_contact_mask_cache.has(cache_key):
		return _surface_contact_mask_cache[cache_key]
	var visual := instantiate_visual(definition, false)
	var mask := surface_contact_mask_from_visual(visual)
	visual.free()
	_surface_contact_mask_cache[cache_key] = mask
	return mask


static func surface_contact_mask_from_visual(
	visual: Node3D
) -> PackedVector2Array:
	if visual == null:
		return PackedVector2Array()
	var authored := visual.get_node_or_null("AuthoredVisual") as Node3D
	if authored == null:
		return PackedVector2Array()
	var vertices: Array[Vector3] = []
	_collect_mesh_vertices(authored, authored.transform, vertices)
	if vertices.size() < 3:
		return PackedVector2Array()
	var minimum_y := vertices[0].y
	var maximum_y := vertices[0].y
	for vertex: Vector3 in vertices:
		minimum_y = minf(minimum_y, vertex.y)
		maximum_y = maxf(maximum_y, vertex.y)
	var contact_band := clampf(
		(maximum_y - minimum_y) * SURFACE_MASK_CONTACT_BAND_RATIO,
		SURFACE_MASK_MIN_CONTACT_BAND,
		SURFACE_MASK_MAX_CONTACT_BAND
	)
	var contact_points := PackedVector2Array()
	for vertex: Vector3 in vertices:
		if vertex.y <= minimum_y + contact_band:
			contact_points.append(Vector2(vertex.x, vertex.z))
	if contact_points.size() < 3:
		for vertex: Vector3 in vertices:
			contact_points.append(Vector2(vertex.x, vertex.z))
	return Geometry2D.convex_hull(contact_points)


static func _collect_mesh_vertices(
	node: Node,
	local_transform: Transform3D,
	vertices: Array[Vector3]
) -> void:
	if (
		node.has_meta("exclude_from_structural_bounds")
		and bool(node.get_meta("exclude_from_structural_bounds"))
	):
		return
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
				var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for position: Vector3 in positions:
					vertices.append(local_transform * position)
	for child: Node in node.get_children():
		var child_transform := local_transform
		if child is Node3D:
			child_transform = local_transform * (child as Node3D).transform
		_collect_mesh_vertices(child, child_transform, vertices)


func effective_model_scale(definition: Defs.StructureDefinition) -> float:
	if definition == null:
		return grid.world_model_scale
	return (
		grid.world_model_scale
		* assets.edits.model_scale_for(definition.asset_id)
	)


func _prepare_authored_visual(
	authored: Node3D,
	definition: Defs.StructureDefinition
) -> void:
	if definition.grid_fit_profile == "tile_span":
		# Tile-span models were already reduced horizontally when tile_size moved
		# from 1.35 m to 1.00 m. Preserve that exact live fit and scale only the
		# remaining authored (vertical) dimension here.
		_fit_authored_xz_to_tile(authored)
		authored.scale.y *= grid.world_model_scale
		return
	authored.scale *= grid.world_model_scale


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
	if (
		parent.has_meta("exclude_from_structural_bounds")
		and bool(parent.get_meta("exclude_from_structural_bounds"))
	):
		return
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
