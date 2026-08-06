extends Node
## Production-path visual review for modular stone-wall proportions.

var _output_dir := "user://stone_wall_module_review"
var _camera: Camera3D
var _layout := "comparison"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
		elif argument.begins_with("--layout="):
			_layout = argument.trim_prefix("--layout=")
	_build_review()
	for _frame in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var result := get_viewport().get_texture().get_image().save_png(
		absolute_dir.path_join("stone_wall_%s.png" % _layout)
	)
	if result != OK:
		push_error("Could not save wall review: %s" % error_string(result))
	else:
		print("STONE WALL MODULE REVIEW CAPTURED - %s" % absolute_dir)
	get_tree().quit(0)


func _build_review() -> void:
	var core := GameCore.new()
	core.setup("res://data", 73021)
	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	var entries := _entries_for_layout()
	var placed_by_coord: Dictionary = {}
	for entry: Dictionary in entries:
		core.grid.place_tile(entry["coord"], "tile_grass")
		var placed = core.grid.add_structure(
			entry["coord"],
			entry["structure"],
			1,
			int(entry.get("rotation", 0))
		)
		placed_by_coord[entry["coord"]] = placed
	if _layout == "stack":
		var root = placed_by_coord.get(Vector2i.ZERO)
		var middle = core.grid.add_structure_on(
			root.instance_id,
			"struct_stone_wall_polished",
			"wall_top"
		)
		var upper = core.grid.add_structure_on(
			middle.instance_id,
			"struct_stone_wall_polished",
			"wall_top"
		)
		core.grid.add_structure_on(
			upper.instance_id,
			"struct_stone_wall_polished",
			"wall_top"
		)
	elif _layout == "pair":
		var root = placed_by_coord.get(Vector2i.ZERO)
		core.grid.add_structure_on(
			root.instance_id,
			"struct_stone_wall_polished",
			"wall_top"
		)

	add_child(
		(load(
			"res://scenes/visual/SumaSoftDaylight.tscn"
		) as PackedScene).instantiate()
	)
	var renderer := WorldRenderer.new()
	renderer.name = "WorldRenderer"
	add_child(renderer)
	renderer.setup(core, assets)
	if _layout in ["fire", "back_fire"]:
		var warm_light := OmniLight3D.new()
		warm_light.name = "ProductionWarmLightProbe"
		warm_light.light_color = PaletteDefinition.shared().color("vfx_local_light")
		warm_light.light_energy = 1.1
		warm_light.omni_range = 4.5
		warm_light.position = Vector3(
			0.42,
			0.38,
			-0.86 if _layout == "back_fire" else 0.86
		)
		warm_light.add_to_group("warm_lights")
		add_child(warm_light)
	var probe_factory := StructureVisualFactory.new(assets, core.grid)
	var probe_definition := core.registries.structure("struct_stone_wall_polished")
	var probe := probe_factory.instantiate_visual(probe_definition)
	var probe_bounds := StructureVisualFactory.local_mesh_bounds(probe)
	print("POLISHED WALL LIVE BOUNDS - %s" % [probe_bounds.get("bounds", AABB())])
	probe.free()
	for entry: Dictionary in entries:
		if String(entry.get("label", "")).is_empty():
			continue
		var label := Label3D.new()
		label.text = String(entry["label"])
		label.font_size = 42
		label.outline_size = 10
		label.position = core.grid.cell_to_world(entry["coord"])
		label.position.y = 1.28
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = (
		2.7 if _layout == "straight"
		else 1.45 if _layout in ["single", "side", "fire", "back_fire"]
		else 1.85 if _layout == "pair"
		else 4.6 if _layout == "assembly"
		else 3.8 if _layout == "stack"
		else 3.8
	)
	_camera.position = (
		Vector3(0.0, 1.15, 5.8)
		if _layout == "straight"
		else Vector3(2.35, 1.05, 3.25) if _layout in ["single", "fire"]
		else Vector3(2.6, 1.65, 3.6) if _layout == "pair"
		else Vector3(2.35, 1.05, -3.25) if _layout in ["side", "back_fire"]
		else Vector3(4.8, 2.8, 5.8) if _layout == "stack"
		else Vector3(4.8, 3.4, 5.6)
	)
	add_child(_camera)
	_camera.look_at(
		Vector3(0.0, 0.25, 0.0) if _layout == "straight"
		else Vector3(0.0, 0.25, 0.0) if _layout in ["single", "side", "fire", "back_fire"]
		else Vector3(0.0, 0.5, 0.0) if _layout == "pair"
		else Vector3(0.0, 0.95, 0.0) if _layout == "stack"
		else Vector3(0.25, 0.48, 0.25) if _layout == "assembly"
		else Vector3(0.0, 0.35, 0.0),
		Vector3.UP
	)
	_camera.current = true


func _entries_for_layout() -> Array[Dictionary]:
	if _layout in ["single", "side", "fire", "back_fire", "pair"]:
		return [
			{"coord": Vector2i.ZERO, "structure": "struct_stone_wall_polished", "rotation": 0},
		]
	if _layout == "straight":
		return [
			{"coord": Vector2i(-1, 0), "structure": "struct_stone_wall_polished", "rotation": 0},
			{"coord": Vector2i(0, 0), "structure": "struct_stone_wall_polished", "rotation": 0},
			{"coord": Vector2i(1, 0), "structure": "struct_stone_wall_polished", "rotation": 0},
		]
	if _layout == "assembly":
		return [
			{"coord": Vector2i(0, -1), "structure": "struct_stone_wall_polished", "rotation": 1},
			{"coord": Vector2i(0, 0), "structure": "struct_stone_wall_polished", "rotation": 1},
			{"coord": Vector2i(0, 1), "structure": "struct_stone_wall_polished", "rotation": 1},
			{"coord": Vector2i(1, 1), "structure": "struct_stone_wall_polished", "rotation": 0},
			{"coord": Vector2i(1, 0), "structure": "struct_stone_wall_polished", "rotation": 0},
		]
	if _layout == "stack":
		return [
			{"coord": Vector2i(-1, 0), "structure": "struct_stone_wall_polished", "rotation": 0},
			{"coord": Vector2i(0, 0), "structure": "struct_stone_wall_polished", "rotation": 0},
			{"coord": Vector2i(1, 0), "structure": "struct_stone_wall_polished", "rotation": 0},
		]
	return [
		{
			"coord": Vector2i(-1, 0),
			"structure": "struct_stone_wall",
			"rotation": 1,
			"label": "Old Stone Wall",
		},
		{
			"coord": Vector2i(1, 0),
			"structure": "struct_stone_wall_polished",
			"rotation": 1,
			"label": "Polished Stone Wall",
		},
	]
