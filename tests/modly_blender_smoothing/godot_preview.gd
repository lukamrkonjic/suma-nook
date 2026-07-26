extends Node3D
## Disposable in-game preview for the two Modly smoothing-test exports.
## Direct-loads experimental GLBs; never touches production registries.

const TREE_SPECS := [
	{
		"id": "tree1",
		"path": "res://tests/modly_blender_smoothing/exports/tree1_smooth_test.glb",
		"tile_position": Vector3(-1.15, 0.0, 0.0),
		"target_height": 2.0,
		"yaw_degrees": 18.0,
	},
	{
		"id": "tree2",
		"path": "res://tests/modly_blender_smoothing/exports/tree2_smooth_test.glb",
		"tile_position": Vector3(1.15, 0.0, 0.0),
		"target_height": 2.2,
		"yaw_degrees": -18.0,
	},
]

var _assets: AssetLibrary
var _lighting: LightingRig
var _camera: Camera3D
var _tree_nodes: Dictionary = {}
var _tile_nodes: Dictionary = {}
var _tree_heights: Dictionary = {}


func _ready() -> void:
	DisplayServer.window_set_title("Suma Nook — Modly Tree Preview (EXPERIMENT)")
	var palette: CozyPalette = load("res://assets/palettes/gg_material_palette.tres")
	var materials := MaterialLibrary.new(palette)
	_assets = AssetLibrary.new(materials)

	_lighting = (load("res://scenes/visual/GGDayLightingRig.tscn") as PackedScene).instantiate()
	_lighting.name = "PreviewLighting"
	add_child(_lighting)

	for spec: Dictionary in TREE_SPECS:
		_add_tree_preview(spec)

	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.1
	_camera.far = 80.0
	_camera.current = true
	add_child(_camera)
	_frame(Vector3(0.0, 0.9, 0.0), 4.4)
	_lighting.set_camera_shadow_distance(14.0)
	_handle_capture()


func _add_tree_preview(spec: Dictionary) -> void:
	var tile_position: Vector3 = spec["tile_position"]
	var tile := _assets.instantiate("tile_stone_mossy")
	tile.name = "%s_MossTile" % spec["id"]
	tile.position = tile_position
	add_child(tile)
	_tile_nodes[String(spec["id"])] = tile

	var packed := load(String(spec["path"])) as PackedScene
	if packed == null:
		push_error("Modly preview could not load " + String(spec["path"]))
		return
	var model := packed.instantiate() as Node3D
	model.name = "%s_SmoothedGLB" % spec["id"]
	add_child(model)

	var bounds := _combined_local_bounds(model)
	if bounds.size.y <= 0.0001:
		push_error("Modly preview found empty bounds for " + String(spec["id"]))
		return
	var target_height := float(spec["target_height"])
	var uniform_scale := target_height / bounds.size.y
	model.scale = Vector3.ONE * uniform_scale
	model.rotation.y = deg_to_rad(float(spec["yaw_degrees"]))
	# Both Modly exports have a centered origin. Raise the scaled lower bound
	# onto the quiet moss cap without altering the experimental GLB itself.
	model.position = tile_position + Vector3(0.0, -bounds.position.y * uniform_scale + 0.025, 0.0)
	model.set_meta("preview_target_height", target_height)
	model.set_meta("preview_uniform_scale", uniform_scale)
	_tree_nodes[String(spec["id"])] = model
	_tree_heights[String(spec["id"])] = target_height


func _combined_local_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var has_bounds := false
	var to_root := root.global_transform.affine_inverse()
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var transform_to_root := to_root * mesh_instance.global_transform
		var local_bounds: AABB = transform_to_root * mesh_instance.get_aabb()
		if not has_bounds:
			result = local_bounds
			has_bounds = true
		else:
			result = result.merge(local_bounds)
	return result


func _frame(pivot: Vector3, ortho_size: float) -> void:
	var basis := Basis.from_euler(
		Vector3(deg_to_rad(-31.0), deg_to_rad(42.0), 0.0)
	)
	_camera.transform = Transform3D(basis, pivot + basis.z * 12.0)
	_camera.size = ortho_size


func _handle_capture() -> void:
	var output_dir := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			output_dir = argument.trim_prefix("--shot-dir=")
	if output_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	_capture_all.call_deferred(output_dir)


func _capture_all(output_dir: String) -> void:
	await _settle(30)
	_save(output_dir.path_join("modly_trees_moss_tiles.png"))

	_set_preview_visible("tree2", false)
	_frame(Vector3(-1.15, 1.0, 0.0), 2.8)
	await _settle(12)
	_save(output_dir.path_join("tree1_moss_tile.png"))

	_set_preview_visible("tree1", false)
	_set_preview_visible("tree2", true)
	_frame(Vector3(1.15, 1.1, 0.0), 3.0)
	await _settle(12)
	_save(output_dir.path_join("tree2_moss_tile.png"))

	print(
		"MODLY GODOT PREVIEW COMPLETE — tree1 %.2fm, tree2 %.2fm"
		% [_tree_heights["tree1"], _tree_heights["tree2"]]
	)
	get_tree().quit()


func _set_preview_visible(tree_id: String, visible: bool) -> void:
	(_tree_nodes[tree_id] as Node3D).visible = visible
	(_tile_nodes[tree_id] as Node3D).visible = visible


func _settle(frame_count: int) -> void:
	for _frame_index in frame_count:
		await get_tree().process_frame


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save Modly preview: %s (%s)" % [path, error_string(error)])
	else:
		print("MODLY PREVIEW SHOT SAVED: " + path)
