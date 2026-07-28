extends Node3D
## Textured two-angle Godot QA for the geometry-preserving wooden-planks pass.

const MODEL_PATH := "res://Workflows/wooden-planks-normals-only.glb"
const PREVIEW_SCALE := 2.15

var _camera: Camera3D
var _output_dir := "user://wooden_planks_normals_review"


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	_build_review()
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture(
		"wooden_planks_normals_front.png",
		Vector3(3.4, 2.75, 3.65),
		Vector3(0.0, 0.26, 0.0)
	)
	await _capture(
		"wooden_planks_normals_opposite.png",
		Vector3(-3.55, 2.55, -3.35),
		Vector3(0.0, 0.24, 0.0)
	)
	print("WOODEN PLANKS NORMALS REVIEW CAPTURED — %s" % _output_dir)
	get_tree().quit()


func _build_review() -> void:
	var lighting := (
		load("res://scenes/visual/SumaSoftDaylight.tscn") as PackedScene
	).instantiate()
	add_child(lighting)

	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("Could not load wooden-planks review model: %s" % MODEL_PATH)
		get_tree().quit(1)
		return
	var model := packed.instantiate() as Node3D
	model.name = "WoodenPlanksNormalsOnly"
	model.scale = Vector3.ONE * PREVIEW_SCALE
	model.rotation.y = deg_to_rad(8.0)
	add_child(model)

	_camera = Camera3D.new()
	_camera.name = "ReviewCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 3.35
	_camera.current = true
	add_child(_camera)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	var title := Label.new()
	title.position = Vector2(34, 24)
	title.text = "Wooden Planks — normals-only polish"
	title.add_theme_font_override(
		"font",
		load("res://assets/fonts/Fredoka-SemiBold.ttf")
	)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#4b3b32"))
	canvas.add_child(title)

	var subtitle := Label.new()
	subtitle.position = Vector2(36, 62)
	subtitle.text = "Original texture • unchanged dimensions • 60° smooth-by-angle"
	subtitle.add_theme_font_override(
		"font",
		load("res://assets/fonts/Fredoka-Medium.ttf")
	)
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color("#735c4d"))
	canvas.add_child(subtitle)


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
		push_error("Could not save wooden-planks review image: %s" % filename)
