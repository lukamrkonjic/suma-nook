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
	registries.tuning = {"tile_size": 1.35, "block_depth": 0.5}
	var definition := Defs.TileDefinition.new()
	definition.id = "tile_kit_grass"
	definition.family = "tile_kit"
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
		"runtime topology sees the east same-family neighbour (got %d)" % runtime_mask
	)
	_check(
		String(factory.call(
			"_connected_layer_asset_id",
			"tile_kit_grass_surface",
			2
		)) == "tile_kit_grass_surface_n02",
		"runtime resolver selects the matching baked topology"
	)

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
