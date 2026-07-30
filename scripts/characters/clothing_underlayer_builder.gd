class_name ClothingUnderlayerBuilder
extends RefCounted
## Builds a small, skinned fabric shell for the body regions hidden by a
## garment. The shell prevents animation from revealing empty space beneath
## sleeves, collars, hems, and other moving openings.
##
## Geometry and skin weights come from the body, so deformation is as stable as
## the character itself. Visuals come from the garment's dominant surface. When
## that surface is textured, its UVs are transferred from the nearest fitted
## garment vertices instead of sampling the garment texture with unrelated body
## UVs.

const DEFAULT_INSET_METERS := 0.0015
const UV_GRID_DIVISIONS := 32.0
const UV_SEARCH_RADIUS := 2
const MIN_UV_CELL_METERS := 0.012
const MAX_UV_CELL_METERS := 0.05
const META_KEY := "generated_clothing_underlayer"


static func build(
	body_mesh: MeshInstance3D,
	target_skeleton: Skeleton3D,
	regions: PackedStringArray,
	garment_meshes: Array[MeshInstance3D],
	node_name: String,
	inset_meters := DEFAULT_INSET_METERS,
) -> MeshInstance3D:
	if (
		body_mesh == null
		or body_mesh.mesh == null
		or target_skeleton == null
		or regions.is_empty()
		or garment_meshes.is_empty()
	):
		return null
	var region_ids := _region_id_set(regions)
	if region_ids.is_empty():
		return null
	var garment_surface := _dominant_garment_surface(garment_meshes)
	if garment_surface.is_empty():
		return null
	var garment_material := garment_surface.get("material") as Material
	if garment_material == null:
		return null

	var uv_sampler := _build_garment_uv_sampler(
		body_mesh,
		garment_surface.get("mesh_instance") as MeshInstance3D,
		int(garment_surface.get("surface_index", -1)),
	)
	var underlayer_mesh := ArrayMesh.new()
	underlayer_mesh.resource_name = "%sMesh" % node_name
	var selected_triangle_count := 0
	for surface_index in body_mesh.mesh.get_surface_count():
		var source_arrays := body_mesh.mesh.surface_get_arrays(surface_index)
		var filtered := _filter_surface(
			source_arrays,
			region_ids,
			uv_sampler,
			maxf(inset_meters, 0.0),
		)
		var vertices: PackedVector3Array = filtered[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue
		var flags := _surface_flags(body_mesh.mesh, surface_index, source_arrays)
		underlayer_mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			filtered,
			[],
			{},
			flags,
		)
		var output_surface := underlayer_mesh.get_surface_count() - 1
		underlayer_mesh.surface_set_material(output_surface, garment_material)
		selected_triangle_count += vertices.size() / 3
	if underlayer_mesh.get_surface_count() == 0:
		return null

	var underlayer := MeshInstance3D.new()
	underlayer.name = node_name
	underlayer.mesh = underlayer_mesh
	underlayer.skin = body_mesh.skin
	underlayer.skeleton = NodePath("..")
	underlayer.transform = _transform_between(body_mesh, target_skeleton)
	# The outer garment already casts the visible shadow. A second almost
	# coincident shadow adds cost and can produce acne without improving depth.
	underlayer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	underlayer.set_meta(META_KEY, true)
	underlayer.set_meta("covered_regions", regions.duplicate())
	underlayer.set_meta("source_material", garment_material.resource_name)
	underlayer.set_meta("triangle_count", selected_triangle_count)
	return underlayer


static func is_generated_underlayer(node: Node) -> bool:
	return node != null and bool(node.get_meta(META_KEY, false))


static func _region_id_set(regions: PackedStringArray) -> Dictionary:
	var ids := {}
	for region in regions:
		if PlayerArmorRegions.REGION_IDS.has(region):
			ids[int(PlayerArmorRegions.REGION_IDS[region])] = true
	return ids


static func _dominant_garment_surface(
	garment_meshes: Array[MeshInstance3D],
) -> Dictionary:
	var result := {}
	var best_triangle_count := -1
	for mesh_instance in garment_meshes:
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface_index)
			if material == null:
				continue
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var triangle_count := (
				indices.size() / 3
				if not indices.is_empty()
				else vertices.size() / 3
			)
			if triangle_count <= best_triangle_count:
				continue
			best_triangle_count = triangle_count
			result = {
				"mesh_instance": mesh_instance,
				"surface_index": surface_index,
				"material": material,
				"triangle_count": triangle_count,
			}
	return result


static func _build_garment_uv_sampler(
	body_mesh: MeshInstance3D,
	garment_mesh: MeshInstance3D,
	surface_index: int,
) -> Dictionary:
	if (
		garment_mesh == null
		or garment_mesh.mesh == null
		or surface_index < 0
		or surface_index >= garment_mesh.mesh.get_surface_count()
	):
		return {}
	var arrays := garment_mesh.mesh.surface_get_arrays(surface_index)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if vertices.is_empty() or uvs.size() != vertices.size():
		return {}
	var garment_to_body := _transform_between(garment_mesh, body_mesh)
	var points := PackedVector3Array()
	points.resize(vertices.size())
	var bounds := AABB(garment_to_body * vertices[0], Vector3.ZERO)
	for index in vertices.size():
		var point := garment_to_body * vertices[index]
		points[index] = point
		bounds = bounds.expand(point)
	var cell_size := clampf(
		maxf(bounds.size.length(), MIN_UV_CELL_METERS) / UV_GRID_DIVISIONS,
		MIN_UV_CELL_METERS,
		MAX_UV_CELL_METERS,
	)
	var cells := {}
	for index in points.size():
		var key := _cell_for(points[index], cell_size)
		var bucket: Array = cells.get(key, [])
		bucket.append(index)
		cells[key] = bucket
	return {
		"points": points,
		"uvs": uvs,
		"cells": cells,
		"cell_size": cell_size,
	}


static func _filter_surface(
	source_arrays: Array,
	region_ids: Dictionary,
	uv_sampler: Dictionary,
	inset_meters: float,
) -> Array:
	var result: Array = []
	result.resize(Mesh.ARRAY_MAX)
	var vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = source_arrays[Mesh.ARRAY_TEX_UV2]
	if vertices.is_empty() or uv2.size() != vertices.size():
		return result
	var indices: PackedInt32Array = source_arrays[Mesh.ARRAY_INDEX]
	var source_order := PackedInt32Array()
	var element_count := indices.size() if not indices.is_empty() else vertices.size()
	for element in range(0, element_count - 2, 3):
		var a := indices[element] if not indices.is_empty() else element
		var b := indices[element + 1] if not indices.is_empty() else element + 1
		var c := indices[element + 2] if not indices.is_empty() else element + 2
		if a < 0 or b < 0 or c < 0:
			continue
		if a >= vertices.size() or b >= vertices.size() or c >= vertices.size():
			continue
		var region_id := int(round(uv2[a].x))
		if not region_ids.has(region_id):
			continue
		source_order.append(a)
		source_order.append(b)
		source_order.append(c)
	if source_order.is_empty():
		return result

	for array_type in Mesh.ARRAY_MAX:
		if array_type == Mesh.ARRAY_INDEX:
			continue
		var source_data: Variant = source_arrays[array_type]
		if source_data == null or source_data.size() == 0:
			continue
		if source_data.size() % vertices.size() != 0:
			continue
		var stride: int = source_data.size() / vertices.size()
		var target_data: Variant = source_data.duplicate()
		target_data.clear()
		for source_index in source_order:
			var offset := source_index * stride
			for component in stride:
				target_data.append(source_data[offset + component])
		result[array_type] = target_data

	var output_vertices: PackedVector3Array = result[Mesh.ARRAY_VERTEX]
	var output_normals: PackedVector3Array = result[Mesh.ARRAY_NORMAL]
	if output_normals.size() == output_vertices.size():
		for index in output_vertices.size():
			var normal := output_normals[index]
			if not normal.is_zero_approx():
				output_vertices[index] -= normal.normalized() * inset_meters
	else:
		for triangle in range(0, output_vertices.size() - 2, 3):
			var normal := (
				(output_vertices[triangle + 1] - output_vertices[triangle])
				.cross(output_vertices[triangle + 2] - output_vertices[triangle])
				.normalized()
			)
			for corner in 3:
				output_vertices[triangle + corner] -= normal * inset_meters
	result[Mesh.ARRAY_VERTEX] = output_vertices

	if not uv_sampler.is_empty():
		var output_uvs := PackedVector2Array()
		output_uvs.resize(source_order.size())
		var uv_cache := {}
		for output_index in source_order.size():
			var source_index := source_order[output_index]
			if not uv_cache.has(source_index):
				uv_cache[source_index] = _nearest_garment_uv(
					vertices[source_index], uv_sampler
				)
			output_uvs[output_index] = uv_cache[source_index]
		result[Mesh.ARRAY_TEX_UV] = output_uvs
	return result


static func _surface_flags(
	source_mesh: Mesh,
	surface_index: int,
	arrays: Array,
) -> int:
	var flags := 0
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if not vertices.is_empty() and weights.size() == vertices.size() * 8:
		flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var source_format: int = source_mesh.surface_get_format(surface_index)
	if source_format & Mesh.ARRAY_FLAG_USE_2D_VERTICES:
		flags |= Mesh.ARRAY_FLAG_USE_2D_VERTICES
	return flags


static func _nearest_garment_uv(
	point: Vector3,
	sampler: Dictionary,
) -> Vector2:
	var points: PackedVector3Array = sampler["points"]
	var uvs: PackedVector2Array = sampler["uvs"]
	var cells: Dictionary = sampler["cells"]
	var cell_size := float(sampler["cell_size"])
	var center := _cell_for(point, cell_size)
	var best_index := -1
	var best_distance_squared := INF
	for x in range(-UV_SEARCH_RADIUS, UV_SEARCH_RADIUS + 1):
		for y in range(-UV_SEARCH_RADIUS, UV_SEARCH_RADIUS + 1):
			for z in range(-UV_SEARCH_RADIUS, UV_SEARCH_RADIUS + 1):
				var key := center + Vector3i(x, y, z)
				for candidate in cells.get(key, []):
					var distance_squared := point.distance_squared_to(
						points[candidate]
					)
					if distance_squared < best_distance_squared:
						best_distance_squared = distance_squared
						best_index = candidate
	if best_index < 0:
		for candidate in points.size():
			var distance_squared := point.distance_squared_to(points[candidate])
			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best_index = candidate
	return uvs[best_index] if best_index >= 0 else Vector2.ZERO


static func _cell_for(point: Vector3, cell_size: float) -> Vector3i:
	return Vector3i(
		int(floor(point.x / cell_size)),
		int(floor(point.y / cell_size)),
		int(floor(point.z / cell_size)),
	)


## Node3D.global_transform reports an engine error for resource-only character
## assemblies that have not entered a SceneTree yet. Walking local parents gives
## the same relative transform and also keeps headless asset tests clean.
static func _transform_between(
	from_node: Node3D,
	to_node: Node3D,
) -> Transform3D:
	return (
		_local_to_hierarchy_root(to_node).affine_inverse()
		* _local_to_hierarchy_root(from_node)
	)


static func _local_to_hierarchy_root(node: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent is Node3D:
		result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result
