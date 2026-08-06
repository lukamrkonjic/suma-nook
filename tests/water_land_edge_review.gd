extends Node
## Production-path shoreline review: continuous water beside ordinary land.

var _output_dir := "user://water_land_edge_review"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")

	var core := GameCore.new()
	core.setup("res://data", 73021)
	for z in range(-1, 2):
		for x in range(-2, 0):
			core.grid.place_tile(Vector2i(x, z), "tile_open_water")
		for x in range(0, 2):
			core.grid.place_tile(Vector2i(x, z), "tile_grass")

	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	add_child(
		(load(
			"res://scenes/visual/SumaSoftDaylight.tscn"
		) as PackedScene).instantiate()
	)
	var renderer := WorldRenderer.new()
	renderer.name = "WorldRenderer"
	add_child(renderer)
	renderer.setup(core, assets)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.25
	camera.position = Vector3(-4.4, 2.25, 4.5)
	add_child(camera)
	camera.look_at(Vector3(-0.5, -0.08, 0.0), Vector3.UP)
	camera.current = true

	for _frame in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var result := get_viewport().get_texture().get_image().save_png(
		absolute_dir.path_join("water_land_edge.png")
	)
	if result != OK:
		push_error("Could not save shoreline review: %s" % error_string(result))
	else:
		print("WATER LAND EDGE REVIEW CAPTURED - %s" % absolute_dir)
	get_tree().quit(0)
