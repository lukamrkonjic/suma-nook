extends Node3D
## Textured two-angle Godot QA for the geometry-preserving stone-pine pass.

const MODEL_PATH := "res://Workflows/stone-pine-normals-only.glb"
const TARGET_HEIGHT := 2.65

var _camera: Camera3D
var _output_dir := "user://stone_pine_normals_review"


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	_build_review()
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture(
		"stone_pine_normals_front.png",
		Vector3(4.7, 3.25, 6.0),
		Vector3(0.0, 1.22, 0.0)
	)
	await _capture(
		"stone_pine_normals_opposite.png",
		Vector3(-4.9, 3.05, -5.7),
		Vector3(0.0, 1.18, 0.0)
	)
	print("STONE PINE NORMALS REVIEW CAPTURED — %s" % _output_dir)
	get_tree().quit()


func _build_review() -> void:
	var lighting := (
		load("res://scenes/visual/SumaSoftDaylight.tscn") as PackedScene
	).instantiate()
	add_child(lighting)

	var palette: CozyPalette = load("res://assets/palettes/gg_material_palette.tres")
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	var tile := assets.instantiate("tile_stone_mossy")
	tile.name = "MossTile"
	add_child(tile)

	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("Could not load stone-pine review model: %s" % MODEL_PATH)
		get_tree().quit(1)
		return
	var model := packed.instantiate() as Node3D
	model.name = "StonePineNormalsOnly"
	add_child(model)
	var bounds := _combined_local_bounds(model)
	if bounds.size.y <= 0.0001:
		push_error("Stone-pine review model has empty bounds")
		get_tree().quit(1)
		return
	var scale_factor := TARGET_HEIGHT / bounds.size.y
	model.scale = Vector3.ONE * scale_factor
	model.position.y = -bounds.position.y * scale_factor + 0.025
	model.rotation.y = deg_to_rad(14.0)

	_camera = Camera3D.new()
	_camera.name = "ReviewCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 3.55
	_camera.current = true
	add_child(_camera)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	var title := Label.new()
	title.position = Vector2(34, 24)
	title.text = "Stone Pine — normals-only polish"
	title.add_theme_font_override(
		"font",
		load("res://assets/fonts/Fredoka-SemiBold.ttf")
	)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#4b3b32"))
	canvas.add_child(title)

	var subtitle := Label.new()
	subtitle.position = Vector2(36, 62)
	subtitle.text = "Original texture • unchanged silhouette • 60° smooth-by-angle"
	subtitle.add_theme_font_override(
		"font",
		load("res://assets/fonts/Fredoka-Medium.ttf")
	)
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color("#735c4d"))
	canvas.add_child(subtitle)


func _combined_local_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	var to_root := root.global_transform.affine_inverse()
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local_bounds := to_root * mesh_instance.global_transform * mesh_instance.get_aabb()
		result = result.merge(local_bounds) if found else local_bounds
		found = true
	return result


func _capture(filename: String, position: Vector3, target: Vector3) -> void:
	_camera.position = position
	_camera.look_at(target, Vector3.UP)
	await get_tree().create_timer(0.75).timeout
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var result := get_viewport().get_texture().get_image().save_png(
		absolute_dir.path_join(filename)
	)
	if result != OK:
		push_error("Could not save stone-pine review image: %s" % filename)
