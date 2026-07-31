class_name AssetEditLibrary
extends RefCounted
## Persistent, game-runtime presentation edits for production GLB assets.
##
## Profiles never replace source assets. They are applied after
## MaterialLibrary semantic rebinding, so the same asset id looks identical in
## Asset Studio, newly placed objects, rebuilt tile chunks, and the next game
## launch. Models can blend all authored corner normals toward position-welded
## smooth normals without changing their geometry, and can apply a persistent
## uniform size multiplier at their semantic asset root. Tile smoothing splits
## by what a mesh is: the structural exposed surface — one connected shell
## spanning the tile — additionally relaxes and compresses its height relief,
## while sculpted detail forms (grass tufts, billows, stones, and other
## separate shells) keep their silhouette and only round their shading. Tile
## size, perimeters, structural bases, borders, X/Z positions, UVs, topology,
## and collision remain authored.

const DATA_PATH := "res://data/asset_edits.json"
const SOURCE_ASSET_META := "suma_source_asset_id"
const SOURCE_MESH_META := "suma_asset_edit_source_mesh"
const BASE_MATERIALS_META := "suma_asset_edit_base_materials"
const BASE_MATERIAL_OVERRIDE_META := "suma_asset_edit_base_material_override"
const APPLIED_SCALE_META := "suma_asset_edit_applied_scale"
const PROFILE_VERSION := 2
const MODEL_SCALE_MIN := 0.25
const MODEL_SCALE_MAX := 3.0
const SMOOTH_ALL := &"all"
const SMOOTH_TILE_TOP := &"tile_top"
const SMOOTH_TILE_DETAIL := &"tile_detail"
const SMOOTH_NONE := &"none"
const TILE_TOP_NORMAL_MIN := 0.8
const TILE_STRUCTURAL_SPAN_MIN := 1.2
const TILE_SURFACE_COVERAGE_MIN := 0.6
const TILE_RELAX_PASSES := 18
const TILE_RELAX_WEIGHT := 0.62
const TILE_FULL_RELIEF_SCALE := 0.08
const TILE_DEFORM_POWER := 1.65
const TILE_PERIMETER_EPSILON := 0.002

var _profiles: Dictionary = {}
var _smooth_mesh_cache: Dictionary = {}
var _shell_field_cache: Dictionary = {}
var _data_path := DATA_PATH


func _init(profile_path: String = DATA_PATH) -> void:
	_data_path = profile_path
	reload()


func reload() -> void:
	_profiles.clear()
	_smooth_mesh_cache.clear()
	_shell_field_cache.clear()
	if not FileAccess.file_exists(_data_path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_data_path))
	if parsed is Dictionary:
		var raw_profiles: Variant = parsed.get("profiles", {})
		if not raw_profiles is Dictionary:
			return
		var loaded: Dictionary = raw_profiles
		for asset_id: String in loaded:
			if loaded[asset_id] is Dictionary:
				var clean := _sanitize_profile(loaded[asset_id])
				if asset_id.begins_with("tile_"):
					clean["scale"] = 1.0
				_profiles[asset_id] = clean


func profile(asset_id: String) -> Dictionary:
	if not _profiles.has(asset_id):
		return {}
	return (_profiles[asset_id] as Dictionary).duplicate(true)


func has_profile(asset_id: String) -> bool:
	return _profiles.has(asset_id)


func model_scale_for(asset_id: String) -> float:
	if asset_id.is_empty() or asset_id.begins_with("tile_"):
		return 1.0
	return float(profile(asset_id).get("scale", 1.0))


func save_profile(asset_id: String, supplied: Dictionary) -> Error:
	if asset_id.is_empty():
		return ERR_INVALID_PARAMETER
	var clean := _sanitize_profile(supplied)
	if asset_id.begins_with("tile_"):
		clean["scale"] = 1.0
	if _profile_is_authored_default(clean):
		_profiles.erase(asset_id)
	else:
		_profiles[asset_id] = clean
	_smooth_mesh_cache.clear()
	var payload := {
		"version": PROFILE_VERSION,
		"profiles": _profiles,
	}
	var absolute_path := ProjectSettings.globalize_path(_data_path)
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t", false) + "\n")
	file.close()
	return OK


func apply_to_instance(root: Node3D, asset_id: String) -> void:
	apply_to_tree(root, asset_id, profile(asset_id))


func apply_to_tree(
	root: Node,
	asset_id: String,
	supplied_profile: Dictionary
) -> void:
	var clean := _sanitize_profile(supplied_profile)
	_apply_model_scale(
		root,
		asset_id,
		float(clean.get("scale", 1.0))
	)
	var smoothing := float(clean.get("smoothing", 0.0))
	var material_edits: Dictionary = clean.get("materials", {})
	for mesh_instance: MeshInstance3D in _mesh_instances(root):
		if not _belongs_to_asset(mesh_instance, asset_id):
			continue
		_restore_authored_state(mesh_instance)
		if mesh_instance.mesh == null:
			continue
		var smoothing_mode := _smoothing_mode(asset_id, mesh_instance)
		if smoothing > 0.0001 and smoothing_mode != SMOOTH_NONE:
			mesh_instance.mesh = _smoothed_mesh(
				mesh_instance.mesh,
				smoothing,
				smoothing_mode
			)
		if mesh_instance.material_override != null:
			var base_override := mesh_instance.material_override
			var override_key := material_key(base_override, 0)
			if material_edits.has(override_key):
				var edited_override := base_override.duplicate(true) as Material
				_apply_material_values(
					edited_override,
					material_edits[override_key]
				)
				edited_override.resource_name = base_override.resource_name
				mesh_instance.material_override = edited_override
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var base_material := mesh_instance.get_active_material(surface)
			if base_material == null:
				continue
			var key := material_key(base_material, surface)
			if not material_edits.has(key):
				continue
			var edited := base_material.duplicate(true) as Material
			_apply_material_values(edited, material_edits[key])
			edited.resource_name = base_material.resource_name
			mesh_instance.set_surface_override_material(surface, edited)


func _apply_model_scale(
	root: Node,
	asset_id: String,
	uniform_scale: float
) -> void:
	var applied_scale := (
		1.0 if asset_id.begins_with("tile_") else uniform_scale
	)
	for asset_root: Node3D in _asset_roots(root, asset_id):
		var previous_scale := float(
			asset_root.get_meta(APPLIED_SCALE_META, 1.0)
		)
		var ratio := applied_scale / maxf(previous_scale, 0.0001)
		asset_root.scale *= ratio
		asset_root.set_meta(APPLIED_SCALE_META, applied_scale)


func _asset_roots(root: Node, asset_id: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if (
		root is Node3D
		and root.has_meta(SOURCE_ASSET_META)
		and String(root.get_meta(SOURCE_ASSET_META)) == asset_id
	):
		result.append(root as Node3D)
	for descendant in root.find_children("*", "Node3D", true, false):
		var candidate := descendant as Node3D
		if (
			candidate.has_meta(SOURCE_ASSET_META)
			and String(candidate.get_meta(SOURCE_ASSET_META)) == asset_id
		):
			result.append(candidate)
	return result


func collect_material_defaults(root: Node, asset_id: String) -> Dictionary:
	var result := {}
	for mesh_instance: MeshInstance3D in _mesh_instances(root):
		if not _belongs_to_asset(mesh_instance, asset_id) or mesh_instance.mesh == null:
			continue
		var base_materials: Array = []
		if mesh_instance.has_meta(BASE_MATERIALS_META):
			base_materials = mesh_instance.get_meta(BASE_MATERIALS_META)
		for surface in mesh_instance.mesh.get_surface_count():
			var active: Material = (
				base_materials[surface]
				if surface < base_materials.size()
				else mesh_instance.get_active_material(surface)
			)
			if active == null:
				continue
			var key := material_key(active, surface)
			if not result.has(key):
				result[key] = material_values(active)
	return result


func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		result.append(root as MeshInstance3D)
	for descendant in root.find_children("*", "MeshInstance3D", true, false):
		result.append(descendant as MeshInstance3D)
	return result


func material_key(material: Material, surface: int) -> String:
	var key := material.resource_name.get_slice("|", 0).get_slice(".", 0)
	return key if not key.is_empty() else "surface_%02d" % surface


func material_values(material: Material) -> Dictionary:
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		return {
			"color": standard.albedo_color.to_html(false),
			"roughness": standard.roughness,
			"metallic": standard.metallic,
		}
	if material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		return {
			"color": _shader_color(shader_material).to_html(false),
			"roughness": _shader_float(
				shader_material,
				["roughness_val", "water_roughness"],
				0.72
			),
			"metallic": _shader_float(
				shader_material,
				["metallic_val"],
				0.0
			),
		}
	return {
		"color": Color.WHITE.to_html(false),
		"roughness": 0.72,
		"metallic": 0.0,
	}


func _restore_authored_state(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.has_meta(SOURCE_MESH_META):
		mesh_instance.mesh = mesh_instance.get_meta(SOURCE_MESH_META) as Mesh
	elif mesh_instance.mesh != null:
		mesh_instance.set_meta(SOURCE_MESH_META, mesh_instance.mesh)
	if mesh_instance.has_meta(BASE_MATERIAL_OVERRIDE_META):
		var stored_override: Array = mesh_instance.get_meta(
			BASE_MATERIAL_OVERRIDE_META
		)
		mesh_instance.material_override = (
			stored_override[0] as Material
			if not stored_override.is_empty()
			else null
		)
	elif mesh_instance.material_override != null:
		## Layered tile composition assigns its semantic material after the GLB
		## is instantiated. Capture that late-bound global override the first
		## time AssetEditLibrary sees it, then always restore from this baseline
		## before applying a live or saved color edit.
		mesh_instance.set_meta(
			BASE_MATERIAL_OVERRIDE_META,
			[mesh_instance.material_override]
		)
	if mesh_instance.mesh == null:
		return
	var base_materials: Array = []
	if mesh_instance.has_meta(BASE_MATERIALS_META):
		base_materials = mesh_instance.get_meta(BASE_MATERIALS_META)
	else:
		for surface in mesh_instance.mesh.get_surface_count():
			base_materials.append(mesh_instance.get_active_material(surface))
		mesh_instance.set_meta(BASE_MATERIALS_META, base_materials)
	for surface in mini(base_materials.size(), mesh_instance.mesh.get_surface_count()):
		mesh_instance.set_surface_override_material(surface, base_materials[surface])


func _belongs_to_asset(node: Node, asset_id: String) -> bool:
	var current: Node = node
	while current != null:
		if current.has_meta(SOURCE_ASSET_META):
			return String(current.get_meta(SOURCE_ASSET_META)) == asset_id
		current = current.get_parent()
	return false


func _smoothing_mode(
	asset_id: String,
	mesh_instance: MeshInstance3D
) -> StringName:
	if not asset_id.begins_with("tile_"):
		return SMOOTH_ALL
	if asset_id.begins_with("tile_layer_base_"):
		return SMOOTH_NONE
	var lower_name := mesh_instance.name.to_lower()
	for rigid_token in [
		"border", "edge", "skirt", "side", "wall", "body", "base",
		"underside", "seam", "frame",
	]:
		if lower_name.contains(rigid_token):
			return SMOOTH_NONE
	var bounds := mesh_instance.get_aabb()
	if (
		bounds.size.x >= TILE_STRUCTURAL_SPAN_MIN
		and bounds.size.z >= TILE_STRUCTURAL_SPAN_MIN
		and not _is_detail_shell_field(mesh_instance.mesh)
	):
		## A tile-spanning single connected shell is the sculpted exposed
		## surface, possibly fused with its structural skirt. Only upward
		## normals participate, so the perimeter split stays perfectly hard.
		return SMOOTH_TILE_TOP
	## Small meshes fused onto a tile and footprint-wide fields of separate
	## sculpted shells (grass tufts, stones, snow billows, moss, flowers)
	## are complete forms, never the ground plane.
	return SMOOTH_TILE_DETAIL


func _is_detail_shell_field(mesh: Mesh) -> bool:
	## The structural exposed surface either is one connected shell (possibly
	## fused with its skirt) or, when authored as separate slabs, still
	## blankets its footprint with upward-facing area. A mesh of several
	## disconnected shells whose tops cover only a fraction of the footprint
	## is a field of sculpted forms (grass tufts and similar), never the
	## ground plane.
	var cache_key := mesh.get_instance_id()
	if _shell_field_cache.has(cache_key):
		return _shell_field_cache[cache_key]
	var parents := {}
	var upward_area := 0.0
	var bounds_min := Vector3(INF, INF, INF)
	var bounds_max := Vector3(-INF, -INF, -INF)
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var corner_count := (
			indices.size() if not indices.is_empty() else vertices.size()
		)
		if corner_count % 3 != 0:
			continue
		for corner in range(0, corner_count, 3):
			var corner_indices := PackedInt32Array()
			var keys: Array[String] = []
			for offset in 3:
				var index := (
					indices[corner + offset]
					if not indices.is_empty()
					else corner + offset
				)
				corner_indices.append(index)
				keys.append(_position_key(vertices[index]))
				bounds_min = bounds_min.min(vertices[index])
				bounds_max = bounds_max.max(vertices[index])
			for key in keys:
				if not parents.has(key):
					parents[key] = key
			_union_shell_keys(parents, keys[0], keys[1])
			_union_shell_keys(parents, keys[1], keys[2])
			if normals.size() == vertices.size() and not normals.is_empty():
				var authored_up := (
					normals[corner_indices[0]].y
					+ normals[corner_indices[1]].y
					+ normals[corner_indices[2]].y
				)
				if authored_up > 0.0:
					var area_vector := (
						vertices[corner_indices[1]]
						- vertices[corner_indices[0]]
					).cross(
						vertices[corner_indices[2]]
						- vertices[corner_indices[0]]
					)
					upward_area += absf(area_vector.y) * 0.5
	var shells := 0
	for raw_key: Variant in parents:
		var key := String(raw_key)
		if String(parents[key]) == key:
			shells += 1
			if shells > 1:
				break
	var footprint := (
		(bounds_max.x - bounds_min.x) * (bounds_max.z - bounds_min.z)
	)
	var coverage := (
		upward_area / footprint if footprint > 0.0001 else INF
	)
	var is_field := shells > 1 and coverage < TILE_SURFACE_COVERAGE_MIN
	_shell_field_cache[cache_key] = is_field
	return is_field


func _union_shell_keys(parents: Dictionary, a: String, b: String) -> void:
	var root_a := _find_shell_root(parents, a)
	var root_b := _find_shell_root(parents, b)
	if root_a != root_b:
		parents[root_a] = root_b


func _find_shell_root(parents: Dictionary, key: String) -> String:
	var root := key
	while String(parents[root]) != root:
		root = String(parents[root])
	var cursor := key
	while String(parents[cursor]) != root:
		var next := String(parents[cursor])
		parents[cursor] = root
		cursor = next
	return root


func _smoothed_mesh(
	source: Mesh,
	amount: float,
	smoothing_mode: StringName
) -> ArrayMesh:
	var quantized := clampf(snappedf(amount, 0.01), 0.0, 1.0)
	var cache_key := "%d|%.2f|%s" % [
		source.get_instance_id(),
		quantized,
		smoothing_mode,
	]
	if _smooth_mesh_cache.has(cache_key):
		return _smooth_mesh_cache[cache_key]
	var result := ArrayMesh.new()
	result.resource_name = "%s_smooth_%d" % [
		source.resource_name,
		roundi(quantized * 100.0),
	]
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		if vertices.size() == normals.size() and not normals.is_empty():
			var top_only := smoothing_mode == SMOOTH_TILE_TOP
			if top_only:
				## Only the structural exposed surface flattens toward its
				## perimeter baseline. Detail forms keep their height so tufts
				## and billows become smooth blobs instead of crushed discs.
				vertices = _relax_tile_vertices(
					vertices,
					normals,
					indices,
					quantized
				)
				arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = _blend_normals(
				vertices,
				normals,
				indices,
				quantized,
				top_only
			)
		result.add_surface_from_arrays(
			source.surface_get_primitive_type(surface),
			arrays
		)
		result.surface_set_material(
			result.get_surface_count() - 1,
			source.surface_get_material(surface)
		)
	_smooth_mesh_cache[cache_key] = result
	return result


func _blend_normals(
	vertices: PackedVector3Array,
	authored: PackedVector3Array,
	indices: PackedInt32Array,
	amount: float,
	top_only: bool
) -> PackedVector3Array:
	var sums := {}
	var corner_count := (
		indices.size() if not indices.is_empty() else vertices.size()
	)
	if corner_count % 3 == 0:
		for corner in range(0, corner_count, 3):
			var a := indices[corner] if not indices.is_empty() else corner
			var b := (
				indices[corner + 1]
				if not indices.is_empty()
				else corner + 1
			)
			var c := (
				indices[corner + 2]
				if not indices.is_empty()
				else corner + 2
			)
			var face_normal := (
				vertices[b] - vertices[a]
			).cross(vertices[c] - vertices[a])
			if face_normal.length_squared() <= 0.0000001:
				continue
			var authored_direction := authored[a] + authored[b] + authored[c]
			if face_normal.dot(authored_direction) < 0.0:
				face_normal = -face_normal
			for index in [a, b, c]:
				if top_only and authored[index].y < TILE_TOP_NORMAL_MIN:
					continue
				var key := _position_key(vertices[index])
				sums[key] = sums.get(key, Vector3.ZERO) + face_normal
	if sums.is_empty():
		for index in vertices.size():
			if top_only and authored[index].y < TILE_TOP_NORMAL_MIN:
				continue
			var key := _position_key(vertices[index])
			sums[key] = sums.get(key, Vector3.ZERO) + authored[index]
	var blended := PackedVector3Array()
	blended.resize(authored.size())
	for index in authored.size():
		if top_only and authored[index].y < TILE_TOP_NORMAL_MIN:
			blended[index] = authored[index]
			continue
		var key := _position_key(vertices[index])
		if not sums.has(key):
			blended[index] = authored[index]
			continue
		var summed: Vector3 = sums[key]
		var target := summed.normalized()
		var source_normal := authored[index].normalized()
		blended[index] = source_normal.lerp(target, amount).normalized()
	return blended


func _relax_tile_vertices(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	amount: float
) -> PackedVector3Array:
	var groups := {}
	var positions := {}
	var eligible := {}
	var rigid := {}
	for index in vertices.size():
		var key := _position_key(vertices[index])
		if not groups.has(key):
			groups[key] = []
			positions[key] = vertices[index]
		var group: Array = groups[key]
		group.append(index)
		groups[key] = group
		if normals[index].y >= TILE_TOP_NORMAL_MIN:
			eligible[key] = true
		else:
			rigid[key] = true
	if eligible.is_empty():
		return vertices

	var bounds_min := Vector3(INF, INF, INF)
	var bounds_max := Vector3(-INF, -INF, -INF)
	for raw_key: Variant in eligible:
		var key := String(raw_key)
		var position: Vector3 = positions[key]
		bounds_min = bounds_min.min(position)
		bounds_max = bounds_max.max(position)
	var span := bounds_max - bounds_min
	var edge_epsilon := maxf(
		TILE_PERIMETER_EPSILON,
		maxf(span.x, span.z) * TILE_PERIMETER_EPSILON
	)
	var movable := {}
	var plateau_sum := 0.0
	for raw_key: Variant in eligible:
		var key := String(raw_key)
		var position: Vector3 = positions[key]
		var locked := (
			rigid.has(key)
			or absf(position.x - bounds_min.x) <= edge_epsilon
			or absf(position.x - bounds_max.x) <= edge_epsilon
			or absf(position.z - bounds_min.z) <= edge_epsilon
			or absf(position.z - bounds_max.z) <= edge_epsilon
		)
		if not locked:
			movable[key] = true
			plateau_sum += position.y
	if movable.is_empty():
		return vertices
	## Relief compresses toward the authored interior mean, never the perimeter
	## anchors: a fully smoothed top keeps the tile's standardized walk-surface
	## height instead of sagging to rim level and reading recessed against its
	## neighbours. The locked perimeter alone keeps seams authored-tight.
	var baseline := plateau_sum / float(movable.size())

	var adjacency := {}
	for raw_key: Variant in eligible:
		adjacency[String(raw_key)] = {}
	var corner_count := (
		indices.size() if not indices.is_empty() else vertices.size()
	)
	if corner_count % 3 != 0:
		return vertices
	for corner in range(0, corner_count, 3):
		var triangle := [
			indices[corner] if not indices.is_empty() else corner,
			(
				indices[corner + 1]
				if not indices.is_empty()
				else corner + 1
			),
			(
				indices[corner + 2]
				if not indices.is_empty()
				else corner + 2
			),
		]
		for edge in 3:
			var a := _position_key(vertices[triangle[edge]])
			var b := _position_key(vertices[triangle[(edge + 1) % 3]])
			if a == b or not eligible.has(a) or not eligible.has(b):
				continue
			var a_neighbors: Dictionary = adjacency[a]
			var b_neighbors: Dictionary = adjacency[b]
			a_neighbors[b] = true
			b_neighbors[a] = true
			adjacency[a] = a_neighbors
			adjacency[b] = b_neighbors

	var heights := {}
	for raw_key: Variant in eligible:
		var key := String(raw_key)
		heights[key] = (positions[key] as Vector3).y
	for _pass in TILE_RELAX_PASSES:
		var next_heights := heights.duplicate()
		for raw_key: Variant in movable:
			var key := String(raw_key)
			var neighbors: Dictionary = adjacency.get(key, {})
			if neighbors.is_empty():
				continue
			var neighbor_sum := 0.0
			var neighbor_count := 0
			for raw_neighbor: Variant in neighbors:
				var neighbor := String(raw_neighbor)
				neighbor_sum += float(heights[neighbor])
				neighbor_count += 1
			if neighbor_count > 0:
				next_heights[key] = lerpf(
					float(heights[key]),
					neighbor_sum / float(neighbor_count),
					TILE_RELAX_WEIGHT
				)
		heights = next_heights

	var deformation := pow(amount, TILE_DEFORM_POWER)
	var result := vertices.duplicate()
	for raw_key: Variant in movable:
		var key := String(raw_key)
		var relaxed_height := baseline + (
			float(heights[key]) - baseline
		) * TILE_FULL_RELIEF_SCALE
		for raw_index: Variant in groups[key]:
			var index := int(raw_index)
			var edited := vertices[index]
			edited.y = lerpf(edited.y, relaxed_height, deformation)
			result[index] = edited
	return result


func _position_key(position: Vector3) -> String:
	return "%d:%d:%d" % [
		roundi(position.x * 100000.0),
		roundi(position.y * 100000.0),
		roundi(position.z * 100000.0),
	]


func _apply_material_values(material: Material, raw_values: Variant) -> void:
	if not raw_values is Dictionary:
		return
	var values := raw_values as Dictionary
	var color := Color.from_string(
		String(values.get("color", "ffffff")),
		Color.WHITE
	)
	var roughness := clampf(float(values.get("roughness", 0.72)), 0.0, 1.0)
	var metallic := clampf(float(values.get("metallic", 0.0)), 0.0, 1.0)
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		color.a = standard.albedo_color.a
		standard.albedo_color = color
		standard.roughness = roughness
		standard.metallic = metallic
		if standard.emission_enabled:
			standard.emission = color
	elif material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		_set_first_shader_parameter(
			shader_material,
			["albedo", "shallow_color", "mid_color"],
			color
		)
		_set_first_shader_parameter(
			shader_material,
			["roughness_val", "water_roughness"],
			roughness
		)
		_set_first_shader_parameter(
			shader_material,
			["metallic_val"],
			metallic
		)


func _shader_color(material: ShaderMaterial) -> Color:
	for name in ["albedo", "shallow_color", "mid_color"]:
		if _shader_has_parameter(material, name):
			var value = material.get_shader_parameter(name)
			if value is Color:
				return value
	return Color.WHITE


func _shader_float(
	material: ShaderMaterial,
	names: Array[String],
	fallback: float
) -> float:
	for name: String in names:
		if _shader_has_parameter(material, name):
			return float(material.get_shader_parameter(name))
	return fallback


func _set_first_shader_parameter(
	material: ShaderMaterial,
	names: Array[String],
	value: Variant
) -> void:
	for name: String in names:
		if _shader_has_parameter(material, name):
			material.set_shader_parameter(name, value)
			return


func _shader_has_parameter(material: ShaderMaterial, parameter_name: String) -> bool:
	if material.shader == null:
		return false
	for uniform: Variant in material.shader.get_shader_uniform_list():
		var raw: Dictionary = uniform
		if String(raw.get("name", "")) == parameter_name:
			return true
	return false


func _sanitize_profile(raw: Dictionary) -> Dictionary:
	var materials := {}
	var raw_materials: Variant = raw.get("materials", {})
	var supplied_materials: Dictionary = (
		raw_materials if raw_materials is Dictionary else {}
	)
	for key: String in supplied_materials:
		if not supplied_materials[key] is Dictionary:
			continue
		var values: Dictionary = supplied_materials[key]
		materials[key] = {
			"color": Color.from_string(
				String(values.get("color", "ffffff")),
				Color.WHITE
			).to_html(false),
			"roughness": clampf(
				float(values.get("roughness", 0.72)),
				0.0,
				1.0
			),
			"metallic": clampf(
				float(values.get("metallic", 0.0)),
				0.0,
				1.0
			),
		}
	return {
		"scale": clampf(
			float(raw.get("scale", 1.0)),
			MODEL_SCALE_MIN,
			MODEL_SCALE_MAX
		),
		"smoothing": clampf(float(raw.get("smoothing", 0.0)), 0.0, 1.0),
		"materials": materials,
	}


func _profile_is_authored_default(clean: Dictionary) -> bool:
	var materials: Dictionary = clean.get("materials", {})
	return (
		is_equal_approx(float(clean.get("scale", 1.0)), 1.0)
		and float(clean.get("smoothing", 0.0)) <= 0.0001
		and materials.is_empty()
	)
