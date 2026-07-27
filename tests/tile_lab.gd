extends Node
## Tile geometry laboratory — the visual QA scene for the
## TileGeometryProfile system (art_source/blender/tile_profiles.py).
##
## Lays out every profile family under the production lighting rig and the
## game's orthographic camera angle: hard cubes, micro-bevel terrain, a
## connected grass patch, soft recessed snow, rounded-corner slabs, a stepped
## plinth, the constructed plank platform, organic overlays on a crisp base,
## a merged 3x3 water pool, a mixed checkerboard, stacked blocks, and a
## four-tile junction close-up. Run:
##   godot --path . tests/tile_lab.tscn -- --shot-dir=<absolute folder>

var _spacing := 1.70   # replaced by grid.tile_size in _build

var _camera: Camera3D
var _output_dir := "user://tile_lab"
var _pixel_level := 0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
		elif argument.begins_with("--pixel="):
			_pixel_level = int(argument.trim_prefix("--pixel="))
	_build()
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture("tile_lab_overview.png", _cell(0.0, 1.6), 16.0)
	await _capture("tile_lab_junction.png", _cell(3.5, 5.0), 3.2)
	await _capture("tile_lab_water.png", _cell(4.0, 1.5), 7.0)
	print("TILE LAB CAPTURED — %s" % _output_dir)
	get_tree().quit()


func _cell(cx: float, cz: float) -> Vector3:
	return Vector3(cx * _spacing, 0.0, cz * _spacing)


func _build() -> void:
	var palette: CozyPalette = load("res://assets/palettes/gg_material_palette.tres")
	var materials := MaterialLibrary.new(palette)
	var assets := AssetLibrary.new(materials)
	var core := GameCore.new()
	core.setup()
	var tile_factory := TileVisualFactory.new(assets, core.grid)
	_spacing = core.grid.tile_size

	add_child((load("res://scenes/visual/SumaSoftDaylight.tscn") as PackedScene).instantiate())
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	add_child(_camera)
	if _pixel_level > 0:
		var pixel := PixelLook.new()
		add_child(pixel)
		pixel.apply(_pixel_level, false)

	# 1. HARD_SQUARE 3x3 (Foundation Stone).
	_grid(tile_factory, core, "tile_stone_ruin", Vector2i(3, 3), _cell(-6.0, -2.0), "HARD_SQUARE")
	# 2. MICRO_BEVEL_SQUARE 3x3 (stone path).
	_grid(tile_factory, core, "tile_path", Vector2i(3, 3), _cell(-2.0, -2.0), "MICRO_BEVEL")
	# 3. Connected grass patch, full-flush 3x3.
	_grid(tile_factory, core, "tile_grass", Vector2i(3, 3), _cell(2.0, -2.0), "GRASS PATCH")
	# 4. SOFT_RECESSED_TOP x4 (snow).
	_grid(tile_factory, core, "tile_snowfield", Vector2i(2, 2), _cell(5.5, -2.0), "SOFT RECESS")
	# 5. ROUNDED_CORNER_SLAB x4 (clay).
	_grid(tile_factory, core, "tile_clay", Vector2i(2, 2), _cell(-6.0, 1.5), "CORNER SLAB")
	# 6. Stepped stone platform (courtyard plinth).
	_grid(tile_factory, core, "tile_courtyard", Vector2i(2, 1), _cell(-3.5, 1.5), "PLINTH")
	# 7. Constructed plank platform.
	_grid(tile_factory, core, "tile_wooden_planks", Vector2i(2, 1), _cell(-1.0, 1.5), "PLANKS")
	# 8. Crisp base + organic overlays (mud with puddles).
	_grid(tile_factory, core, "tile_mud", Vector2i(2, 1), _cell(1.5, 1.5), "OVERLAYS")
	# 9. 3x3 merged water pool over the water floor tiles.
	_water_pool(tile_factory, core, materials, _cell(4.0, 1.5))
	# 10. Mixed checkerboard of profiles meeting.
	var mix := ["tile_grass", "tile_path", "tile_dirt", "tile_snowfield"]
	for row in 4:
		for col in 4:
			_tile(tile_factory, core, mix[(row * 4 + col + row) % mix.size()],
				_cell(-6.5 + col, 4.0 + row))
	# 11. Stacked blocks — lower levels rendered in their COVERED form (the
	# exposed top layer swaps for the flush infill lid, as in the real game).
	for level in 3:
		var stacked := _tile(tile_factory, core, "tile_grass" if level == 2 else "tile_stone_ruin",
			_cell(0.5, 4.5) + Vector3(0, level * 0.5, 0))
		tile_factory.set_surface_covered(stacked, level < 2)
	var lower := _tile(tile_factory, core, "tile_grass", _cell(1.5, 4.5))
	tile_factory.set_surface_covered(lower, true)
	_tile(tile_factory, core, "tile_grass", _cell(1.5, 4.5) + Vector3(0, 0.5, 0))
	# 12. Four-tile junction at gameplay zoom (captured separately).
	_grid(tile_factory, core, "tile_grass", Vector2i(2, 2), _cell(3.5, 5.0), "")


func _grid(factory: TileVisualFactory, core: GameCore, tile_id: String, cells: Vector2i, origin: Vector3, _label: String) -> void:
	for row in cells.y:
		for col in cells.x:
			_tile(factory, core, tile_id, origin + Vector3(
				(col - (cells.x - 1) * 0.5) * _spacing, 0.0,
				(row - (cells.y - 1) * 0.5) * _spacing))


func _tile(factory: TileVisualFactory, core: GameCore, tile_id: String, at: Vector3) -> Node3D:
	var visual := factory.instantiate_visual(core.registries.tile(tile_id), true)
	visual.position = at
	add_child(visual)
	return visual


func _water_pool(factory: TileVisualFactory, core: GameCore, materials: MaterialLibrary, origin: Vector3) -> void:
	var cells: Array = []
	for row in 3:
		for col in 3:
			cells.append(Vector2i(col, row))
			# preview=false: the merged WaterSurface below is the ONLY water —
			# preview mode would add a per-tile quad on every cell on top of it.
			var floor_visual := factory.instantiate_visual(
				core.registries.tile("tile_open_water"), false)
			floor_visual.position = origin + Vector3(
				(col - 1.0) * _spacing, 0.0, (row - 1.0) * _spacing)
			add_child(floor_visual)
	var surface := WaterSurface.new()
	surface.name = "LabWaterSurface"
	add_child(surface)
	var closure_origin := origin
	surface.rebuild(
		cells,
		func(c: Vector2i) -> Vector3:
			return closure_origin + Vector3((c.x - 1.0) * _spacing, 0.0, (c.y - 1.0) * _spacing),
		_spacing,
		-0.14,
		materials.material("water")
	)


func _capture(filename: String, center: Vector3, size: float) -> void:
	_camera.size = size
	_camera.position = center + Vector3(8.2, 8.0, 9.4)
	_camera.look_at(center, Vector3.UP)
	await get_tree().create_timer(0.6).timeout
	# Capture only after the renderer has drawn a frame with the camera state
	# set above — saving straight off the timer raced the draw queue and could
	# store a frame from the previous framing.
	await RenderingServer.frame_post_draw
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	get_viewport().get_texture().get_image().save_png(absolute_dir.path_join(filename))
