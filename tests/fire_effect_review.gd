extends Node
## Focused production-path review for every structure using the fire capability.
##
## Run with:
##   godot --path . tests/fire_effect_review.tscn
##         -- --shot-dir=<absolute output folder>

const ITEMS := [
	{
		"id": "struct_campfire",
		"position": Vector3(-1.15, 0.0, 0.0),
		"rotation": -0.16,
	},
	{
		"id": "struct_firepit_polished",
		"position": Vector3(1.15, 0.0, 0.0),
		"rotation": 0.18,
	},
]

var _camera: Camera3D
var _output_dir := "user://fire_effect_review"


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	_build_review()
	await get_tree().create_timer(0.9).timeout
	_camera.position = Vector3(4.8, 4.2, 6.0)
	_camera.look_at(Vector3(0.0, 0.24, 0.0), Vector3.UP)
	await get_tree().process_frame
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var result := get_viewport().get_texture().get_image().save_png(
		absolute_dir.path_join("fire_effects.png")
	)
	if result != OK:
		push_error("Could not save fire-effect review image.")
	print("FIRE EFFECT REVIEW CAPTURED — %s" % absolute_dir)
	get_tree().quit(result)


func _build_review() -> void:
	var palette: CozyPalette = load(
		"res://assets/palettes/gg_material_palette.tres"
	)
	var materials := MaterialLibrary.new(palette)
	var assets := AssetLibrary.new(materials)
	var core := GameCore.new()
	if not core.setup():
		push_error("Could not load production content for fire-effect review.")
		get_tree().quit(1)
		return
	add_child(
		(load(
			"res://scenes/visual/SumaSoftDaylight.tscn"
		) as PackedScene).instantiate()
	)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 4.2
	_camera.current = true
	add_child(_camera)

	var tile_factory := TileVisualFactory.new(assets, core.grid)
	var structure_factory := StructureVisualFactory.new(assets, core.grid)
	var grass := core.registries.tile("tile_grass")
	for item: Dictionary in ITEMS:
		var position: Vector3 = item["position"]
		var tile := tile_factory.instantiate_visual(grass, true)
		tile.position = position
		add_child(tile)
		var definition := core.registries.structure(item["id"])
		var visual := structure_factory.instantiate_visual(definition)
		visual.position = position
		visual.rotation.y = float(item["rotation"])
		add_child(visual)
