extends Node
## Disposable visual-QA gallery for the original catalog expansion.
##
## It uses the production registries, material library, and visual factories,
## but never creates or edits a save. Run it with:
##   godot --path . tests/catalog_expansion_review.tscn
##         -- --shot-dir=<absolute output folder>

const TILE_IDS := [
	"tile_dirt",
	"tile_dirt_road",
	"tile_dirt_crossroad",
	"tile_mud",
	"tile_snowfield",
	"tile_snow_drift",
	"tile_snow_path",
	"tile_frosted_stone",
	"tile_cobblestone",
	"tile_flagstone",
	"tile_sand",
	"tile_clay",
	"tile_wooden_planks",
]
const STRUCTURE_IDS := [
	"struct_stone_wall_low",
	"struct_stone_wall_corner",
	"struct_stone_pillar",
	"struct_stone_well",
	"struct_stone_bench",
	"struct_birdbath",
	"struct_watering_can",
	"struct_barrel",
	"struct_crate",
	"struct_wheelbarrow",
	"struct_log_pile",
	"struct_wooden_arch",
	"struct_milk_churn",
	"struct_garden_trellis",
	"struct_snowman",
	"struct_water_wheel",
]

var _camera: Camera3D
var _title: Label
var _output_dir := "user://catalog_expansion_review"


func _ready() -> void:
	var pixel_level := 0
	var pixel_cel := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
		elif argument.begins_with("--pixel="):
			pixel_level = int(argument.trim_prefix("--pixel="))
		elif argument == "--cel":
			pixel_cel = true
	_build_gallery()
	if pixel_level > 0 or pixel_cel:
		var pixel := PixelLook.new()
		pixel.name = "PixelLook"
		add_child(pixel)
		pixel.apply(pixel_level, pixel_cel)
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture_tiles()
	await _capture_structures()
	print("CATALOG EXPANSION REVIEW CAPTURED — %s" % _output_dir)
	get_tree().quit()


func _build_gallery() -> void:
	var palette: CozyPalette = load("res://assets/palettes/gg_material_palette.tres")
	var materials := MaterialLibrary.new(palette)
	var assets := AssetLibrary.new(materials)
	var core := GameCore.new()
	core.setup()

	var lighting := (
		load("res://scenes/visual/SumaSoftDaylight.tscn") as PackedScene
	).instantiate()
	add_child(lighting)

	_camera = Camera3D.new()
	_camera.name = "ReviewCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	add_child(_camera)

	var tile_group := Node3D.new()
	tile_group.name = "ExpandedTiles"
	add_child(tile_group)
	var tile_factory := TileVisualFactory.new(assets, core.grid)
	for index in TILE_IDS.size():
		var definition := core.registries.tile(TILE_IDS[index])
		var visual := tile_factory.instantiate_visual(definition, true)
		visual.position = _grid_position(index, 4, 2.05, Vector3.ZERO)
		tile_group.add_child(visual)
		_add_name_label(tile_group, definition.display_name, visual.position)

	var structure_group := Node3D.new()
	structure_group.name = "ExpandedStructures"
	structure_group.position.x = 30.0
	add_child(structure_group)
	var structure_factory := StructureVisualFactory.new(assets, core.grid)
	for index in STRUCTURE_IDS.size():
		var definition := core.registries.structure(STRUCTURE_IDS[index])
		var pedestal_def := core.registries.tile(_pedestal_tile_for(definition.id))
		var pedestal := tile_factory.instantiate_visual(pedestal_def, true)
		pedestal.position = _grid_position(index, 4, 2.35, Vector3.ZERO)
		structure_group.add_child(pedestal)
		var visual := structure_factory.instantiate_visual(definition)
		visual.position = pedestal.position
		structure_group.add_child(visual)
		_add_name_label(structure_group, definition.display_name, visual.position)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	_title = Label.new()
	_title.position = Vector2(36, 28)
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color("#4b3b32"))
	canvas.add_child(_title)


func _grid_position(index: int, columns: int, spacing: float, offset: Vector3) -> Vector3:
	var row := index / columns
	var column := index % columns
	return offset + Vector3(
		(float(column) - (float(columns) - 1.0) * 0.5) * spacing,
		0.0,
		(float(row) - 1.0) * spacing
	)


func _pedestal_tile_for(structure_id: String) -> String:
	if structure_id == "struct_water_wheel":
		return "tile_open_water"
	if structure_id == "struct_snowman":
		return "tile_snowfield"
	if (
		structure_id.contains("stone")
		or structure_id == "struct_birdbath"
	):
		return "tile_flagstone"
	return "tile_grass"


func _add_name_label(parent: Node3D, text: String, position: Vector3) -> void:
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
	label.position = position + Vector3(0.0, -0.06, 0.82)
	parent.add_child(label)


func _capture_tiles() -> void:
	_title.text = "Suma Nook — new terrain collection"
	_frame(Vector3(0.0, 0.0, 1.0), 14.0)
	await _settle_and_capture("catalog_expansion_tiles.png")


func _capture_structures() -> void:
	_title.text = "Suma Nook — new garden & masonry collection"
	_frame(Vector3(30.0, 0.25, 1.15), 12.0)
	await _settle_and_capture("catalog_expansion_structures.png")


func _frame(center: Vector3, size: float) -> void:
	_camera.size = size
	_camera.position = center + Vector3(8.2, 8.0, 9.4)
	_camera.look_at(center, Vector3.UP)


func _settle_and_capture(filename: String) -> void:
	await get_tree().create_timer(0.8).timeout
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var image := get_viewport().get_texture().get_image()
	var result := image.save_png(absolute_dir.path_join(filename))
	if result != OK:
		push_error("Could not save catalog review image: %s" % filename)
