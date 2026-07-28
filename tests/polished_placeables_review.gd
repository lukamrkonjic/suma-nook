extends Node
## Focused production-path visual review for the imported polished placeables.
##
## The scene uses the real content registry, AssetLibrary, tile/structure
## factories, embedded GLB materials, and Suma daylight. It does not touch a
## save. Run with:
##   godot --path . tests/polished_placeables_review.tscn
##         -- --shot-dir=<absolute output folder>

const ITEMS := [
	{
		"id": "struct_stone_wall_polished",
		"tile": "tile_flagstone",
		"position": Vector3(-1.25, 0.0, 0.0),
		"rotation": -0.18,
	},
	{
		"id": "struct_firepit_polished",
		"tile": "tile_grass",
		"position": Vector3(1.25, 0.0, 0.0),
		"rotation": 0.20,
	},
]

var _camera: Camera3D
var _title: Label
var _output_dir := "user://polished_placeables_review"


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	_build_review()
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture(
		"polished_placeables_front.png",
		Vector3(5.4, 4.4, 6.2),
		Vector3(0.0, 0.35, 0.0)
	)
	await _capture(
		"polished_placeables_opposite.png",
		Vector3(-5.2, 3.8, -5.8),
		Vector3(0.0, 0.32, 0.0)
	)
	print("POLISHED PLACEABLES REVIEW CAPTURED — %s" % _output_dir)
	get_tree().quit()


func _build_review() -> void:
	var palette: CozyPalette = load("res://assets/palettes/gg_material_palette.tres")
	var materials := MaterialLibrary.new(palette)
	var assets := AssetLibrary.new(materials)
	var core := GameCore.new()
	if not core.setup():
		push_error("Could not load production content for polished-placeables review")
		get_tree().quit(1)
		return

	var environment := (
		load("res://scenes/visual/SumaSoftDaylight.tscn") as PackedScene
	).instantiate()
	add_child(environment)

	_camera = Camera3D.new()
	_camera.name = "ReviewCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 5.0
	_camera.current = true
	add_child(_camera)

	var tile_factory := TileVisualFactory.new(assets, core.grid)
	var structure_factory := StructureVisualFactory.new(assets, core.grid)
	for item: Dictionary in ITEMS:
		var position: Vector3 = item["position"]
		var tile_definition := core.registries.tile(item["tile"])
		var tile := tile_factory.instantiate_visual(tile_definition, true)
		tile.position = position
		add_child(tile)

		var definition := core.registries.structure(item["id"])
		var visual := structure_factory.instantiate_visual(definition)
		visual.position = position
		visual.rotation.y = item["rotation"]
		add_child(visual)
		_add_label(definition.display_name, visual)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	_title = Label.new()
	_title.position = Vector2(34, 24)
	_title.text = "New placeables — production Godot import"
	_title.add_theme_font_override(
		"font",
		load("res://assets/fonts/Fredoka-SemiBold.ttf")
	)
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color("#4b3b32"))
	canvas.add_child(_title)

	var subtitle := Label.new()
	subtitle.position = Vector2(36, 62)
	subtitle.text = "Polished Stone Wall  •  Polished Firepit"
	subtitle.add_theme_font_override(
		"font",
		load("res://assets/fonts/Fredoka-Medium.ttf")
	)
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color("#735c4d"))
	canvas.add_child(subtitle)


func _add_label(text: String, visual: Node3D) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = load("res://assets/fonts/Fredoka-SemiBold.ttf")
	label.font_size = 30
	label.pixel_size = 0.006
	label.modulate = Color("#4b3b32")
	label.outline_modulate = Color("#fff9e9")
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	var bounds_data := StructureVisualFactory.local_mesh_bounds(visual)
	var label_height := 0.8
	if bool(bounds_data.get("found", false)):
		var bounds: AABB = bounds_data["bounds"]
		label_height = bounds.position.y + bounds.size.y + 0.16
	label.position = visual.position + Vector3(0.0, label_height, 0.0)
	add_child(label)


func _capture(filename: String, camera_position: Vector3, target: Vector3) -> void:
	_camera.position = camera_position
	_camera.look_at(target, Vector3.UP)
	await get_tree().create_timer(0.65).timeout
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var result := get_viewport().get_texture().get_image().save_png(
		absolute_dir.path_join(filename)
	)
	if result != OK:
		push_error("Could not save polished-placeables review image: %s" % filename)
