extends Node
## Production-path visual QA for model seating and all four tile wall faces.
## Two opposing captures make a reversed cardinal wall impossible to hide.

var _output_dir := "user://tile_seating_review"
var _camera: Camera3D


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	_build_review()
	for _frame in 4:
		await get_tree().process_frame
	await _capture("tile_seating_southeast.png")
	_camera.position = Vector3(-5.8, 4.6, -6.4)
	_camera.look_at(Vector3(0.0, 0.15, 0.0), Vector3.UP)
	for _frame in 3:
		await get_tree().process_frame
	await _capture("tile_seating_northwest.png")
	print(
		"TILE SEATING REVIEW CAPTURED - %s"
		% ProjectSettings.globalize_path(_output_dir)
	)
	get_tree().quit(0)


func _build_review() -> void:
	var core := GameCore.new()
	core.setup("res://data", 73021)
	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))

	var entries := [
		{"coord": Vector2i(-1, 0), "tile": "tile_snowfield"},
		{"coord": Vector2i(1, 0), "tile": "tile_grass"},
		{"coord": Vector2i(0, -2), "tile": "tile_sand"},
	]
	for entry: Dictionary in entries:
		core.grid.place_tile(entry["coord"], entry["tile"])
		core.grid.add_structure(entry["coord"], "struct_lantern", 1)

	add_child(
		(load(
			"res://scenes/visual/SumaSoftDaylight.tscn"
		) as PackedScene).instantiate()
	)
	var renderer := WorldRenderer.new()
	renderer.name = "WorldRenderer"
	add_child(renderer)
	renderer.setup(core, assets)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 6.2
	_camera.position = Vector3(5.8, 4.6, 6.4)
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.15, 0.0), Vector3.UP)
	_camera.current = true


func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var error := get_viewport().get_texture().get_image().save_png(
		absolute_dir.path_join(filename)
	)
	if error != OK:
		push_error("Could not save tile seating review: %s" % error_string(error))
