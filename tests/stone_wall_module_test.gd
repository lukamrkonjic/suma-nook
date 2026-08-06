extends Node
## Regression guard for the polished stone wall's half-tile module contract.

const TOLERANCE := 0.001
const EXPECTED_FACE_WIDTH := 1.059259
const EXPECTED_JUNCTION_SPAN := 1.592593
const EXPECTED_MODULE_HEIGHT := 0.5


func _ready() -> void:
	var core := GameCore.new()
	core.setup("res://data", 73021)
	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	var factory := StructureVisualFactory.new(assets, core.grid)
	var definition := core.registries.structure("struct_stone_wall_polished")
	var visual := factory.instantiate_visual(definition)
	var result := StructureVisualFactory.local_mesh_bounds(visual)
	if not bool(result.get("found", false)):
		push_error("Polished stone wall has no runtime mesh bounds")
		get_tree().quit(1)
		return
	var bounds: AABB = result["bounds"]
	var failures: Array[String] = []
	if absf(bounds.size.x - EXPECTED_FACE_WIDTH) > TOLERANCE:
		failures.append(
			"ordinary face width %.6f != seam-safe width %.6f"
			% [bounds.size.x, EXPECTED_FACE_WIDTH]
		)
	if bounds.position.y > TOLERANCE or bounds.end.y < EXPECTED_MODULE_HEIGHT - TOLERANCE:
		failures.append("wall does not cover the complete half-tile support interval: %s" % bounds)
	if bounds.position.y < -0.06 or bounds.end.y > EXPECTED_MODULE_HEIGHT + 0.06:
		failures.append("stack-seam overlap exceeds the 6 cm live visual allowance: %s" % bounds)
	if absf(bounds.position.x + EXPECTED_FACE_WIDTH * 0.5) > TOLERANCE:
		failures.append("wall is not centered on the tile X axis")
	if bounds.size.z >= core.grid.tile_size * 0.6:
		failures.append("wall depth %.6f is too bulky for house construction" % bounds.size.z)
	var authored := visual.get_node_or_null("AuthoredVisual") as Node3D
	var support := visual.find_child("WallTopSupport", true, false) as Marker3D
	var masonry := visual.find_child("RoundedMasonryCourses", true, false) as MeshInstance3D
	var gap_core := visual.find_child("GapProofCore", true, false) as MeshInstance3D
	if authored == null or support == null:
		failures.append("procedural wall is missing its stable top support marker")
	elif absf((authored.transform * support.position).y
			- EXPECTED_MODULE_HEIGHT) > TOLERANCE:
		failures.append("top support marker is not exactly half a live tile high")
	if masonry == null:
		failures.append("procedural wall is missing its primary masonry courses")
	else:
		var masonry_bounds := masonry.mesh.get_aabb()
		var live_face_width := masonry_bounds.size.x * authored.scale.x
		if absf(live_face_width - EXPECTED_FACE_WIDTH) > TOLERANCE:
			failures.append(
				"primary masonry width %.6f != straight-seam width %.6f"
				% [live_face_width, EXPECTED_FACE_WIDTH]
			)
		var live_depth := masonry_bounds.size.y * authored.scale.z
		var required_half_span := core.grid.tile_size - live_depth * 0.5
		var procedural := authored
		var live_junction_span := (
			float(procedural.get_meta("authored_junction_span", 0.0))
			* authored.scale.x
			if procedural != null else 0.0
		)
		if live_junction_span * 0.5 < required_half_span - TOLERANCE:
			failures.append(
				"junction span stops before a perpendicular neighbour's face"
			)
		var has_back_normals := false
		for surface_index in masonry.mesh.get_surface_count():
			var arrays := masonry.mesh.surface_get_arrays(surface_index)
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for normal: Vector3 in normals:
				if normal.y < -0.999:
					has_back_normals = true
					break
			var material := masonry.mesh.surface_get_material(surface_index)
			if material is StandardMaterial3D:
				var stone := material as StandardMaterial3D
				if absf(stone.roughness - 0.72) > TOLERANCE:
					failures.append("wall stone roughness is not warm-light safe")
				if absf(stone.metallic_specular - 0.14) > TOLERANCE:
					failures.append("wall stone specular response is not authored")
		if not has_back_normals:
			failures.append("rounded wall slabs are missing their closed rear caps")
		if gap_core == null:
			failures.append("procedural wall is missing its recessed cavity core")
		elif gap_core.mesh.get_aabb().size.x >= masonry_bounds.size.x - 0.05:
			failures.append("cavity core ends remain coplanar with outer stones")
	visual.free()

	var coord := Vector2i(3, 4)
	core.grid.place_tile(coord, "tile_grass")
	var first := core.grid.add_structure(coord, definition.id, 1)
	var second := (
		core.grid.add_structure_on(first.instance_id, definition.id, "wall_top")
		if first != null else null
	)
	var third := (
		core.grid.add_structure_on(second.instance_id, definition.id, "wall_top")
		if second != null else null
	)
	if first == null or second == null or third == null:
		failures.append("polished walls cannot form a three-module vertical stack")
	else:
		var first_origin := core.grid.structure_local_transform(first.instance_id).origin
		var second_origin := core.grid.structure_local_transform(second.instance_id).origin
		var third_origin := core.grid.structure_local_transform(third.instance_id).origin
		if not first_origin.is_equal_approx(Vector3.ZERO):
			failures.append("root wall does not remain on its tile origin")
		if absf(second_origin.y - EXPECTED_MODULE_HEIGHT) > TOLERANCE:
			failures.append("second wall is not exactly half a tile above the first")
		if absf(third_origin.y - core.grid.tile_size) > TOLERANCE:
			failures.append("two stacked wall intervals do not equal one tile")

	var junction_core := GameCore.new()
	junction_core.setup("res://data", 73021)
	junction_core.grid.place_tile(Vector2i.ZERO, "tile_grass")
	junction_core.grid.place_tile(Vector2i.RIGHT, "tile_grass")
	var long_wall := junction_core.grid.add_structure(
		Vector2i.ZERO, definition.id, 1, 1
	)
	var joining_wall := junction_core.grid.add_structure(
		Vector2i.RIGHT, definition.id, 1, 0
	)
	var renderer := WorldRenderer.new()
	add_child(renderer)
	renderer.setup(junction_core, assets)
	var joining_visual := renderer.structure_node(joining_wall.instance_id)
	var left_junction := joining_visual.find_child(
		"JunctionLeft", true, false
	) as Node3D
	var right_junction := joining_visual.find_child(
		"JunctionRight", true, false
	) as Node3D
	if left_junction == null or not left_junction.visible:
		failures.append("perpendicular left neighbour does not reveal its junction arm")
	if right_junction == null or right_junction.visible:
		failures.append("open wall end reveals an unnecessary junction arm")
	if renderer.structure_node(long_wall.instance_id) == null:
		failures.append("junction review lost the receiving wall visual")
	renderer.queue_free()
	if not failures.is_empty():
		for failure: String in failures:
			push_error(failure)
		get_tree().quit(1)
		return
	print("STONE WALL MODULE TEST PASSED - %s" % bounds)
	get_tree().quit(0)
