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

	# At an L-shaped three-tile junction the open outer bevel must turn back up
	# to the fused endpoint. All three caps then meet at y=0 instead of exposing
	# the dark side wall as a V-shaped crevice.
	var dirt := load(
		"res://tools/tile_kit/library/recipes/tile_dirt.tres"
	) as TileKitPreset
	var dirt_generator := TileKitGenerator.new()
	dirt_generator.preset = dirt
	dirt_generator.neighbour_mask = 8
	get_root().add_child(dirt_generator)
	await process_frame
	var dirt_height: Callable = (
		dirt_generator.get("_context") as Dictionary
	)["cap_height"]
	_check(
		absf(float(dirt_height.call(Vector2(-0.85, 0.85)))) < 0.001,
		"connected dirt corner returns to the shared walk plane"
	)
	_check(
		float(dirt_height.call(Vector2(0.0, 0.85))) < -0.02,
		"open dirt edge keeps its bevel away from the junction"
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
				"res://tools/tile_kit/baked/tile_kit_grass_surface_n%02d.tscn"
				% mask
			),
			"surface variant %d is baked" % mask
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
	_check(
		String(factory.call(
			"_connected_layer_asset_id",
			"tile_kit_grass_surface",
			2
		)) == "tile_kit_grass_surface_n02",
		"runtime resolver selects the matching baked topology"
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
