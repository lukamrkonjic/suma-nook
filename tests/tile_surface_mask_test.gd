extends SceneTree
## Verifies that placed-model contact footprints remove procedural tile detail
## geometry without hiding the untouched remainder of the tile.

var failures: Array[String] = []
var checks := 0


func _init() -> void:
	_run()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _run() -> void:
	var core := GameCore.new()
	core.setup("res://data", 73021)
	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	var tile_factory := TileVisualFactory.new(assets, core.grid)
	var structure_factory := StructureVisualFactory.new(assets, core.grid)
	var campfire := core.registries.structure("struct_campfire")
	var mask := structure_factory.surface_contact_mask(campfire)
	check(mask.size() >= 3, "campfire produces a contact footprint")
	check(
		Geometry2D.is_point_in_polygon(Vector2.ZERO, mask),
		"campfire contact footprint covers its center"
	)

	var state := WorldGrid.CellState.new()
	state.tile_id = "tile_grass"
	var root_structure := WorldGrid.StructureState.new()
	root_structure.instance_id = 1
	root_structure.structure_id = "struct_campfire"
	root_structure.rotation = 1
	state.structures.append(root_structure)
	var supported_child := WorldGrid.StructureState.new()
	supported_child.instance_id = 2
	supported_child.structure_id = "struct_pot"
	supported_child.parent_instance_id = 1
	supported_child.support_slot_id = "missing_test_slot"
	state.structures.append(supported_child)
	var tile_masks := structure_factory.surface_masks_for_tile(state, 0)
	check(tile_masks.size() == 1, "only the tile-root object contributes a mask")

	var grass := core.registries.tile("tile_grass")
	var visual := tile_factory.instantiate_visual(grass)
	var before := _detail_triangle_count(visual)
	tile_factory.apply_surface_exclusion_masks(
		visual, tile_masks, grass.walk_surface_height
	)
	var after := _detail_triangle_count(visual)
	check(before > 0, "grass begins with procedural detail geometry")
	check(after > 0, "mask preserves grass outside the model footprint")
	check(after < before, "mask removes grass beneath the campfire")
	check(
		not _detail_intersects_masks(visual, tile_masks),
		"no surviving detail triangle intersects the model footprint"
	)
	visual.free()
	var unmasked_batch := tile_factory.batch_mesh(grass, false, false)
	var masked_batch := tile_factory.batch_mesh(
		grass, false, false, 0, 0, tile_masks
	)
	check(
		masked_batch != unmasked_batch,
		"batched renderer caches masked and unmasked tiles separately"
	)
	check(
		_mesh_triangle_count(masked_batch) < _mesh_triangle_count(unmasked_batch),
		"batched renderer removes the same covered detail geometry"
	)

	var snow := core.registries.tile("tile_snowfield")
	var lantern_definition := core.registries.structure("struct_lantern")
	var lantern_mask := structure_factory.surface_contact_mask(lantern_definition)
	var snow_visual := tile_factory.instantiate_visual(snow)
	tile_factory.apply_surface_exclusion_masks(
		snow_visual, [lantern_mask], snow.walk_surface_height
	)
	check(
		not _surface_exceeds_height_in_masks(
			snow_visual, [lantern_mask], snow.walk_surface_height
		),
		"snow relief stays below a lantern throughout its contact footprint"
	)
	snow_visual.free()
	var snow_coord := Vector2i(41, 37)
	var snow_state := core.grid.place_tile(snow_coord, snow.id)
	var lantern := core.grid.add_structure(snow_coord, "struct_lantern", 1)
	check(snow_state != null, "raised snow tile can be placed for seating test")
	check(lantern != null, "lantern can be placed on raised snow")
	if lantern != null:
		var expected_height := maxf(0.0, snow.walk_surface_height)
		check(
			is_equal_approx(
				core.grid.structure_local_transform(lantern.instance_id).origin.y,
				expected_height
			),
			"placed object is seated on the snow walk surface"
		)
		check(
			is_equal_approx(
				core.grid.structure_local_transform_in_cell(
					snow_state, lantern.instance_id
				).origin.y,
				expected_height
			),
			"detached previews use the same raised seating plane"
		)

	if failures.is_empty():
		print("TILE SURFACE MASK TEST PASSED — %d checks" % checks)
		quit(0)
	else:
		for failure: String in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _detail_triangle_count(root: Node3D) -> int:
	var count := 0
	for child: Node in root.find_children("*", "MeshInstance3D", true, false):
		var detail := child as MeshInstance3D
		if not bool(detail.get_meta(TileVisualFactory.SURFACE_DETAIL_META, false)):
			continue
		for surface_index in detail.mesh.get_surface_count():
			var arrays := detail.mesh.surface_get_arrays(surface_index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			count += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	return count


func _mesh_triangle_count(mesh: Mesh) -> int:
	var count := 0
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		count += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	return count


func _detail_intersects_masks(root: Node3D, masks: Array) -> bool:
	for child: Node in root.find_children("*", "MeshInstance3D", true, false):
		var detail := child as MeshInstance3D
		if (
			detail.mesh == null
			or not detail.visible
			or not bool(detail.get_meta(TileVisualFactory.SURFACE_DETAIL_META, false))
		):
			continue
		var mesh_to_root := _transform_from_ancestor(root, detail)
		for surface_index in detail.mesh.get_surface_count():
			var arrays := detail.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices.resize(vertices.size())
				for index in vertices.size():
					indices[index] = index
			for start in range(0, indices.size() - 2, 3):
				var triangle := PackedVector2Array()
				for offset in 3:
					var point := mesh_to_root * vertices[indices[start + offset]]
					triangle.append(Vector2(point.x, point.z))
				for raw_mask: Variant in masks:
					if _polygons_intersect(triangle, raw_mask):
						return true
	return false


func _surface_exceeds_height_in_masks(
	root: Node3D,
	masks: Array,
	maximum_height: float
) -> bool:
	for child: Node in root.find_children("*", "MeshInstance3D", true, false):
		var surface := child as MeshInstance3D
		if (
			surface.mesh == null
			or String(surface.get_meta(TileVisualFactory.LAYER_ROLE_META, ""))
				!= "surface"
		):
			continue
		var mesh_to_root := _transform_from_ancestor(root, surface)
		for surface_index in surface.mesh.get_surface_count():
			var arrays := surface.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices.resize(vertices.size())
				for index in vertices.size():
					indices[index] = index
			for start in range(0, indices.size() - 2, 3):
				var triangle := PackedVector2Array()
				var highest := -INF
				for offset in 3:
					var point := mesh_to_root * vertices[indices[start + offset]]
					triangle.append(Vector2(point.x, point.z))
					highest = maxf(highest, point.y)
				for raw_mask: Variant in masks:
					if (
						_polygons_intersect(triangle, raw_mask)
						and highest > maximum_height + 0.00001
					):
						return true
	return false


func _polygons_intersect(
	first: PackedVector2Array,
	second: PackedVector2Array
) -> bool:
	for point: Vector2 in first:
		if Geometry2D.is_point_in_polygon(point, second):
			return true
	for point: Vector2 in second:
		if Geometry2D.is_point_in_polygon(point, first):
			return true
	for first_index in first.size():
		for second_index in second.size():
			if Geometry2D.segment_intersects_segment(
				first[first_index],
				first[(first_index + 1) % first.size()],
				second[second_index],
				second[(second_index + 1) % second.size()]
			) != null:
				return true
	return false


func _transform_from_ancestor(
	ancestor: Node3D,
	descendant: Node3D
) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = descendant
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result
