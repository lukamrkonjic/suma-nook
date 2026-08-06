extends SceneTree
## Focused contract test for connection-aware Tile Kit presets and baking.

var _failures: Array[String] = []
var _checks := 0


func _init() -> void:
	_run()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _run() -> void:
	var grass := TileKitPreset.reference_clean_grass()
	var path := TileKitPreset.cobblestone_paving()
	_check(not grass.separate_tiles, "grass fuses by default")
	_check(path.separate_tiles, "constructed paving keeps individual seams")
	_check(
		path.duplicate_preset().separate_tiles,
		"preset duplication persists the separation choice"
	)
	await _test_programmatic_tile_structure()
	var grass_generator := TileKitGenerator.new()
	grass_generator.preset = grass
	grass_generator.neighbour_mask = 2
	get_root().add_child(grass_generator)
	await process_frame
	_check(
		int((grass_generator.get("_context") as Dictionary)["neighbour_mask"]) == 2,
		"fused presets consume supplied neighbour topology"
	)
	grass_generator.free()

	# Neighbour topology may affect vertical relief, but the cap footprint is
	# always the exact square slot. The old open-edge bevel created the visible
	# V-shaped bite at L junctions.
	var dirt := load(
		"res://tools/tile_kit/library/recipes/tile_dirt.tres"
	) as TileKitPreset
	for mask in [0, 8, 10, 15]:
		var dirt_generator := TileKitGenerator.new()
		dirt_generator.preset = dirt
		dirt_generator.neighbour_mask = mask
		get_root().add_child(dirt_generator)
		await process_frame
		var dirt_surface := _generated_role_mesh(dirt_generator, "surface")
		_check(
			dirt_surface != null
				and _mesh_stays_inside_square_slot(dirt_surface)
				and _has_square_footprint_corners(dirt_surface),
			"dirt mask %02d keeps the full square cap footprint" % mask
		)
		dirt_generator.free()

	var moss_material := TileKitPalette.material("moss_plush_base")
	_check(
		moss_material is StandardMaterial3D,
		"moss ground uses a static matte material without animated rim flashes"
	)
	if moss_material is StandardMaterial3D:
		_check(
			(moss_material as StandardMaterial3D).albedo_color.get_luminance() > 0.35,
			"moss ground stays in a readable mid-value range"
		)
	var forest_floor := TileKitPalette.material("forest_floor_top")
	_check(
		forest_floor is StandardMaterial3D
			and (forest_floor as StandardMaterial3D).albedo_color.get_luminance() > 0.35
			and (forest_floor as StandardMaterial3D).metallic_specular <= 0.051,
		"mature grove floor uses the readable moss range"
	)
	var forest_foliage := TileKitPalette.material("forest_rooted_gradient")
	_check(
		forest_foliage is StandardMaterial3D,
		"mature grove foliage is static and cannot shimmer under camera movement"
	)
	if forest_foliage is StandardMaterial3D:
		_check(
			is_zero_approx(
				(forest_foliage as StandardMaterial3D).metallic_specular
			),
			"mature grove foliage cannot produce moving specular flashes"
		)

	var path_generator := TileKitGenerator.new()
	path_generator.preset = path
	path_generator.neighbour_mask = 2
	get_root().add_child(path_generator)
	await process_frame
	_check(
		int((path_generator.get("_context") as Dictionary)["neighbour_mask"]) == 0,
		"separated presets retain the standalone rim"
	)
	path_generator.free()

	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var panel := TileKitPanel.new()
	panel.setup(UiKit.new(palette))
	get_root().add_child(panel)
	var checkbox := panel.find_child(
		"TileKitSeparateTiles",
		true,
		false
	) as CheckBox
	_check(checkbox != null, "tile editor exposes the separation checkbox")
	if checkbox != null:
		checkbox.button_pressed = true
		_check(panel.preset.separate_tiles, "checkbox updates the working preset")
	panel.free()

	for mask in range(1, 16):
		_check(
			ResourceLoader.exists(
				"res://tools/tile_kit/baked/tile_kit_grass_edge_n%02d.tscn"
				% mask
			),
			"lightweight edge variant %d is baked" % mask
		)
		_check(
			not ResourceLoader.exists(
				"res://tools/tile_kit/baked/tile_kit_grass_surface_n%02d.tscn"
				% mask
			),
			"heavy flat surface variant %d is deduplicated" % mask
		)
	var registries := Registries.new()
	registries.tuning = {"tile_size": 1.0, "block_depth": 0.5}
	var definition := Defs.TileDefinition.new()
	definition.id = "tile_kit_grass"
	definition.family = "tile_kit"
	definition.connection_group = "tile_kit_grass"
	definition.connection_mode = "full_flush"
	registries.tiles[definition.id] = definition
	var grid := WorldGrid.new(registries)
	grid.place_tile(Vector2i.ZERO, "tile_kit_grass")
	grid.place_tile(Vector2i.RIGHT, "tile_kit_grass")
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	var factory := TileVisualFactory.new(assets, grid)
	var runtime_mask := factory.connection_mask(definition, Vector2i.ZERO, 0, 0)
	_check(
		runtime_mask == 2,
		"runtime topology sees the east same-connection neighbour (got %d)" % runtime_mask
	)
	var other_definition := Defs.TileDefinition.new()
	other_definition.id = "tile_proc_flower_meadow"
	other_definition.family = "tile_kit"
	other_definition.connection_group = "tile_proc_flower_meadow"
	registries.tiles[other_definition.id] = other_definition
	var mixed_grid := WorldGrid.new(registries)
	mixed_grid.place_tile(Vector2i.ZERO, definition.id)
	mixed_grid.place_tile(Vector2i.RIGHT, other_definition.id)
	var mixed_factory := TileVisualFactory.new(assets, mixed_grid)
	var mixed_mask := mixed_factory.connection_mask(
		definition, Vector2i.ZERO, 0, 0)
	_check(
		mixed_mask == (2 | TileVisualFactory.MIXED_SURFACE_FLAG),
		"unlike full-flush terrain removes its shared rim with transition topology"
	)
	var modular_definition := Defs.TileDefinition.new()
	modular_definition.id = "tile_wooden_planks"
	modular_definition.family = "home_meadow"
	modular_definition.connection_group = "home_meadow"
	modular_definition.connection_mode = "tiny_individual_seam"
	registries.tiles[modular_definition.id] = modular_definition
	var modular_grid := WorldGrid.new(registries)
	modular_grid.place_tile(Vector2i.ZERO, definition.id)
	modular_grid.place_tile(Vector2i.RIGHT, modular_definition.id)
	var modular_factory := TileVisualFactory.new(assets, modular_grid)
	_check(
		modular_factory.connection_mask(definition, Vector2i.ZERO, 0, 0) == 0,
		"deliberately modular planks preserve the shared bevel seam"
	)
	var water_definition := Defs.TileDefinition.new()
	water_definition.id = "tile_open_water"
	water_definition.family = "waterside"
	water_definition.connection_group = "waterside"
	water_definition.connection_mode = "full_flush"
	water_definition.render_profile = "continuous_water"
	registries.tiles[water_definition.id] = water_definition
	var shoreline_grid := WorldGrid.new(registries)
	shoreline_grid.place_tile(Vector2i.ZERO, definition.id)
	shoreline_grid.place_tile(Vector2i.RIGHT, water_definition.id)
	var shoreline_factory := TileVisualFactory.new(assets, shoreline_grid)
	_check(
		shoreline_factory.connection_mask(
			definition, Vector2i.ZERO, 0, 0
		) == 0,
		"open water cannot consume a land tile's structural cap wall"
	)
	_check(
		String(factory.call(
			"_connected_layer_asset_id",
			"tile_kit_grass_surface",
			2
		)) == "tile_kit_grass_surface",
		"runtime resolver reuses the canonical heavy surface"
	)
	_check(
		String(factory.call(
			"_connected_layer_asset_id",
			"tile_kit_grass_edge",
			2
		)) == "tile_kit_grass_edge_n02",
		"runtime resolver selects the lightweight matching edge topology"
	)
	_check(
		String(factory.call(
			"_connected_layer_asset_id",
			"tile_kit_grass_surface",
			2 | TileVisualFactory.MIXED_SURFACE_FLAG
		)) == "tile_kit_grass_surface_x02",
		"mixed terrain selects the relief-safe transition topology"
	)
	definition.detail_rotation_variants = 4
	var detail_variants := {}
	var first_row: Array[int] = []
	var second_row: Array[int] = []
	for y in 5:
		for x in 5:
			var detail_variant := TileVisualFactory.detail_variant_for_coord(
				definition, Vector2i(x, y)
			)
			detail_variants[detail_variant] = true
			if y == 0:
				first_row.append(detail_variant)
			elif y == 1:
				second_row.append(detail_variant)
	_check(
		detail_variants.size() == 4,
		"spatial detail variation exercises every authored quarter turn"
	)
	_check(
		first_row != second_row,
		"spatial detail variation does not repeat identical grid rows"
	)
	_check(
		TileVisualFactory.detail_variant_for_coord(
			definition, Vector2i(3, -7), 2
		) == TileVisualFactory.detail_variant_for_coord(
			definition, Vector2i(3, -7), 2
		),
		"spatial detail variation is deterministic for a saved cell"
	)

	# Rotation is the only allowed runtime spatial variation. Translating an
	# authored detail layer can push otherwise-contained foliage beyond the cap
	# and make it appear to float beside the block.
	definition.render_profile = "layered"
	var detail_layer := Defs.TileVisualLayerDefinition.new()
	detail_layer.role = "detail"
	detail_layer.asset_id = "tile_grass_detail"
	detail_layer.offset = Vector3(0.0, 0.017, 0.0)
	definition.visual_layers.append(detail_layer)
	for detail_variant in 4:
		var visual := factory.instantiate_visual(
			definition, false, 0, detail_variant)
		var runtime_detail: Node3D = null
		for candidate: Node in visual.find_children("*", "Node3D", true, false):
			if String(candidate.get_meta(
				TileVisualFactory.LAYER_ROLE_META, "")) == "detail":
				runtime_detail = candidate as Node3D
				break
		_check(runtime_detail != null,
			"runtime variant %d instantiates its detail layer" % detail_variant)
		if runtime_detail != null:
			_check(runtime_detail.position.is_equal_approx(detail_layer.offset),
				"runtime variant %d rotates without translating contained detail"
				% detail_variant)
		visual.free()

	# These are the clutter-bearing redesigned tiles. Their complete authored
	# detail footprint must remain inside the 1.70 m cap before any rotation.
	for detail_asset_id in [
		"tile_grass_detail",
		"tile_dirt_detail",
		"tile_grove_mossy_detail",
		"tile_grove_mature_detail",
	]:
		var detail_path := AssetLibrary.resolve_path(detail_asset_id)
		var packed := load(detail_path) as PackedScene
		var detail_root := packed.instantiate() as Node3D
		var bounds := _visual_bounds(detail_root)
		var inside_cap := (
			bounds.position.x >= -0.8501
			and bounds.position.z >= -0.8501
			and bounds.end.x <= 0.8501
			and bounds.end.z <= 0.8501
		)
		_check(inside_cap,
			"%s detail stays inside the authored cap (bounds %s)"
			% [detail_asset_id, bounds])
		detail_root.free()

	if _failures.is_empty():
		print("TILE KIT CONNECTION TEST PASSED — %d checks" % _checks)
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: %s" % failure)
	printerr("TILE KIT CONNECTION TEST FAILED — %d/%d" % [
		_failures.size(),
		_checks,
	])
	quit(1)


func _test_programmatic_tile_structure() -> void:
	await _test_all_active_structural_bases()
	await _test_constructed_surface_contract()
	var recipe_paths := {
		"grass": "res://tools/tile_kit/library/recipes/tile_grass.tres",
		"sand": "res://tools/tile_kit/library/recipes/tile_sand.tres",
	}

	var grass_preset := load(String(recipe_paths["grass"])) as TileKitPreset
	var grass_base := grass_preset.layer_of_kind("base")
	_check(
		String(grass_base.value("surface_profile", "")) == "uniform_square",
		"default grass explicitly uses the uniform square upper form"
	)
	for mask in [0, 1, 3, 5, 10, 15]:
		var generator := TileKitGenerator.new()
		generator.preset = grass_preset
		generator.neighbour_mask = mask
		get_root().add_child(generator)
		await process_frame
		var cap_height: Callable = (
			generator.get("_context") as Dictionary
		)["cap_height"]
		for sample in [
			Vector2.ZERO,
			Vector2(KitBaseBuilder.HALF, 0.0),
			Vector2(-KitBaseBuilder.HALF, KitBaseBuilder.HALF),
			Vector2(KitBaseBuilder.HALF, -KitBaseBuilder.HALF),
		]:
			_check(
				is_zero_approx(float(cap_height.call(sample))),
				"grass mask %02d stays flat at %s" % [mask, sample]
			)
		var surface := _generated_role_mesh(generator, "surface")
		_check(surface != null and _has_square_top_corners(surface),
			"grass mask %02d reaches every exact top corner" % mask)
		generator.free()

	var sand_preset := load(String(recipe_paths["sand"])) as TileKitPreset
	var sand_base := sand_preset.layer_of_kind("base")
	_check(
		String(sand_base.value("surface_profile", "")) == "detailed_square",
		"sand explicitly uses relief over a square upper perimeter"
	)
	for mask in [0, 1, 3, 5, 10, 15]:
		var generator := TileKitGenerator.new()
		generator.preset = sand_preset
		generator.neighbour_mask = mask
		get_root().add_child(generator)
		await process_frame
		var surface := _generated_role_mesh(generator, "surface")
		_check(
			surface != null
				and _mesh_stays_inside_square_slot(surface)
				and _has_square_footprint_corners(surface),
			"sand mask %02d keeps an exact square upper perimeter" % mask
		)
		var cap_height: Callable = (
			generator.get("_context") as Dictionary
		)["cap_height"]
		var edge_samples := [
			[1, Vector2(0.0, -KitBaseBuilder.HALF)],
			[2, Vector2(KitBaseBuilder.HALF, 0.0)],
			[4, Vector2(0.0, KitBaseBuilder.HALF)],
			[8, Vector2(-KitBaseBuilder.HALF, 0.0)],
		]
		for edge: Array in edge_samples:
			_check(
				float(cap_height.call(edge[1])) >= -0.0001,
				"sand mask %02d keeps relief on square edge %d"
				% [mask, int(edge[0])]
			)
		generator.free()


func _test_all_active_structural_bases() -> void:
	var tuning := JSON.parse_string(
		FileAccess.get_file_as_string("res://data/tuning.json")
	) as Dictionary
	_check(not tuning.is_empty(), "active tile tuning loads")
	var runtime_catalog := JSON.parse_string(
		FileAccess.get_file_as_string("res://data/tiles.json")
	) as Dictionary
	var runtime_by_id: Dictionary = {}
	for entry: Dictionary in runtime_catalog.get("tiles", []):
		runtime_by_id[String(entry.get("id", ""))] = entry
	var library := TileLibraryService.new()
	library.reload()
	for tile_value: Variant in tuning.get("active_tile_ids", []):
		var tile_id := String(tile_value)
		var manifest := library.official_manifest(tile_id)
		_check(manifest != null, "%s has an official procedural manifest" % tile_id)
		if manifest == null:
			continue
		if manifest.baked_roles.has("edge"):
			var runtime_entry: Dictionary = runtime_by_id.get(tile_id, {})
			var exposes_edge := false
			for runtime_layer: Dictionary in runtime_entry.get("layers", []):
				if String(runtime_layer.get("role", "")) == "edge":
					exposes_edge = true
					break
			_check(
				exposes_edge,
				"%s runtime definition includes its baked edge closure" % tile_id
			)
		var preset := ResourceLoader.load(
			manifest.recipe_path, "", ResourceLoader.CACHE_MODE_IGNORE
		) as TileKitPreset
		_check(preset != null, "%s procedural recipe loads" % tile_id)
		if preset == null:
			continue
		var signatures: Array[String] = []
		var cap_footprints: Array[String] = []
		var base_layer := preset.layer_of_kind("base")
		var ordinary_cap := (
			float(base_layer.value("basin_depth", 0.0)) <= 0.0
			and not bool(base_layer.value("turf_cap", false))
		)
		# Separate constructed cells deliberately retain their authored rim on
		# every side. Structural edge culling applies only to fused terrain;
		# paver/plank seams are validated by the constructed-surface contract.
		var fused_structural_edges := ordinary_cap and not preset.separate_tiles
		for mask in [0, 1, 3, 8, 15]:
			var generator := TileKitGenerator.new()
			generator.preset = preset
			generator.neighbour_mask = mask
			get_root().add_child(generator)
			await process_frame
			var body := _generated_role_mesh(generator, "base")
			_check(
				body != null and _is_exact_square_base(body),
				"%s mask %02d base is an exact slot-sized square prism"
				% [tile_id, mask]
			)
			if body != null:
				_check(
					body.get_surface_count() == 1,
					"%s mask %02d structural shell uses one material"
					% [tile_id, mask]
				)
				signatures.append(_mesh_vertex_signature(body))
			if ordinary_cap:
				var cap := _generated_role_mesh(generator, "surface")
				var edge_mesh := _generated_role_mesh(generator, "edge")
				_check(
					cap != null
						and _mesh_stays_inside_square_slot(cap)
						and _has_square_footprint_corners(cap),
					"%s mask %02d cap fills the exact square slot"
					% [tile_id, mask]
				)
				if cap != null:
					cap_footprints.append(_mesh_horizontal_signature(cap))
				if fused_structural_edges:
					for edge_bit in [1, 2, 4, 8]:
						_check(
							_edge_mesh_has_wall(edge_mesh, edge_bit)
								== ((mask & edge_bit) == 0),
							"%s mask %02d renders edge %d only when exposed"
							% [tile_id, mask, edge_bit]
						)
			generator.free()
		_check(signatures.size() == 5 and signatures.all(
			func(signature: String) -> bool: return signature == signatures[0]
		), "%s base geometry is invariant across neighbour topology" % tile_id)
		if ordinary_cap:
			_check(cap_footprints.size() == 5 and cap_footprints.all(
				func(signature: String) -> bool:
					return signature == cap_footprints[0]
			), "%s cap footprint is invariant across neighbour topology" % tile_id)


func _test_constructed_surface_contract() -> void:
	var brick := load(
		"res://tools/tile_kit/library/recipes/tile_proc_brick_court.tres"
	) as TileKitPreset
	var generator := TileKitGenerator.new()
	generator.preset = brick
	get_root().add_child(generator)
	await process_frame
	var context := generator.get("_context") as Dictionary
	var recess := float(context.get("surface_recess", 0.0))
	_check(
		bool(context.get("integrated_constructed_surface", false)),
		"full-course pavers use an integrated replacement cap"
	)
	_check(
		recess >= 0.004 and recess <= 0.018,
		"constructed grout recess stays shallow (got %.4f)" % recess
	)
	var cap_height: Callable = context["cap_height"]
	_check(
		is_equal_approx(float(cap_height.call(Vector2.ZERO)), -recess),
		"constructed carrier is recessed below the walk plane"
	)
	var pavers := _generated_kind_mesh(generator, "pavers")
	_check(pavers != null, "constructed surface generates embedded pavers")
	if pavers != null:
		var bounds := pavers.get_aabb()
		_check(
			bounds.position.y >= -0.0181 and bounds.end.y <= 0.0041,
			"embedded pavers finish at the walk plane (bounds %s)" % bounds
		)
		_check(
			bounds.position.x <= -KitBaseBuilder.HALF + 0.02
				and bounds.position.z <= -KitBaseBuilder.HALF + 0.02
				and bounds.end.x >= KitBaseBuilder.HALF - 0.02
				and bounds.end.z >= KitBaseBuilder.HALF - 0.02,
			"constructed courses reach the tile boundary (bounds %s)" % bounds
		)
	generator.free()


func _generated_role_mesh(generator: TileKitGenerator, role: String) -> ArrayMesh:
	var results := generator.get("_layer_results") as Dictionary
	for entries: Array in results.values():
		for entry: Dictionary in entries:
			if String(entry.get("role", "")) == role:
				return entry.get("mesh") as ArrayMesh
	return null


func _generated_kind_mesh(generator: TileKitGenerator, kind: String) -> ArrayMesh:
	var results := generator.get("_layer_results") as Dictionary
	for entry: Dictionary in results.get(kind, []):
		return entry.get("mesh") as ArrayMesh
	return null


func _is_exact_square_base(mesh: ArrayMesh) -> bool:
	var bounds := mesh.get_aabb()
	if not bounds.position.is_equal_approx(Vector3(
		-KitBaseBuilder.HALF,
		KitBaseBuilder.BODY_BOTTOM,
		-KitBaseBuilder.HALF
	)):
		return false
	if not bounds.end.is_equal_approx(Vector3(
		KitBaseBuilder.HALF,
		KitBaseBuilder.SEAM,
		KitBaseBuilder.HALF
	)):
		return false
	return _has_corner_at_height(mesh, KitBaseBuilder.BODY_BOTTOM) \
		and _has_corner_at_height(mesh, KitBaseBuilder.SEAM)


func _has_square_top_corners(mesh: ArrayMesh) -> bool:
	return _has_corner_at_height(mesh, 0.0)


func _has_square_footprint_corners(mesh: ArrayMesh) -> bool:
	var corners := {
		Vector2(-KitBaseBuilder.HALF, -KitBaseBuilder.HALF): false,
		Vector2(-KitBaseBuilder.HALF, KitBaseBuilder.HALF): false,
		Vector2(KitBaseBuilder.HALF, -KitBaseBuilder.HALF): false,
		Vector2(KitBaseBuilder.HALF, KitBaseBuilder.HALF): false,
	}
	for surface in mesh.get_surface_count():
		var vertices: PackedVector3Array = (
			mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		)
		for vertex in vertices:
			var key := Vector2(vertex.x, vertex.z)
			if corners.has(key):
				corners[key] = true
	return corners.values().all(func(found: bool) -> bool: return found)


func _mesh_stays_inside_square_slot(mesh: ArrayMesh) -> bool:
	var bounds := mesh.get_aabb()
	return (
		is_equal_approx(bounds.position.x, -KitBaseBuilder.HALF)
		and is_equal_approx(bounds.position.z, -KitBaseBuilder.HALF)
		and is_equal_approx(bounds.end.x, KitBaseBuilder.HALF)
		and is_equal_approx(bounds.end.z, KitBaseBuilder.HALF)
	)


func _edge_mesh_has_wall(mesh: ArrayMesh, edge_bit: int) -> bool:
	if mesh == null:
		return false
	var outward: Vector3 = {
		1: Vector3(0.0, 0.0, -1.0),
		2: Vector3(1.0, 0.0, 0.0),
		4: Vector3(0.0, 0.0, 1.0),
		8: Vector3(-1.0, 0.0, 0.0),
	}.get(edge_bit, Vector3.ZERO)
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(vertices.size())
			for index in vertices.size():
				indices[index] = index
		for start in range(0, indices.size() - 2, 3):
			var first := vertices[indices[start]]
			var second := vertices[indices[start + 1]]
			var third := vertices[indices[start + 2]]
			var winding_normal := (second - first).cross(third - first)
			if (
				winding_normal.length_squared() > 0.0000001
				# Godot considers clockwise triangles front-facing, so the
				# conventional cross product points opposite the visible face.
				and winding_normal.normalized().dot(outward) < -0.99
			):
				return true
	return false


func _has_corner_at_height(mesh: ArrayMesh, height: float) -> bool:
	var corners := {
		Vector2(-KitBaseBuilder.HALF, -KitBaseBuilder.HALF): false,
		Vector2(-KitBaseBuilder.HALF, KitBaseBuilder.HALF): false,
		Vector2(KitBaseBuilder.HALF, -KitBaseBuilder.HALF): false,
		Vector2(KitBaseBuilder.HALF, KitBaseBuilder.HALF): false,
	}
	for surface in mesh.get_surface_count():
		var vertices: PackedVector3Array = (
			mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		)
		for vertex in vertices:
			if not is_equal_approx(vertex.y, height):
				continue
			var key := Vector2(vertex.x, vertex.z)
			if corners.has(key):
				corners[key] = true
	return corners.values().all(func(found: bool) -> bool: return found)


func _mesh_vertex_signature(mesh: ArrayMesh) -> String:
	var signature := ""
	for surface in mesh.get_surface_count():
		var vertices: PackedVector3Array = (
			mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		)
		for vertex in vertices:
			signature += "%.5f,%.5f,%.5f;" % [vertex.x, vertex.y, vertex.z]
	return signature


func _mesh_horizontal_signature(mesh: ArrayMesh) -> String:
	var signature := ""
	for surface in mesh.get_surface_count():
		var vertices: PackedVector3Array = (
			mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		)
		for vertex in vertices:
			signature += "%.5f,%.5f;" % [vertex.x, vertex.z]
	return signature


func _visual_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var has_bounds := false
	for child: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var relative := Transform3D.IDENTITY
		var current: Node = mesh_instance
		while current != null and current != root:
			if current is Node3D:
				relative = (current as Node3D).transform * relative
			current = current.get_parent()
		var mesh_bounds := relative * mesh_instance.get_aabb()
		if not has_bounds:
			result = mesh_bounds
			has_bounds = true
		else:
			result = result.merge(mesh_bounds)
	return result
