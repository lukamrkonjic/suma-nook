extends Node
## Production-path sand review: real Suma lighting, perspective camera rig,
## registries, asset/material libraries, tile scaling, and cover behavior.

var _output_dir := "user://sand_tile_gameplay_review"
var _camera_rig: CameraRig


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")

	var core := GameCore.new()
	core.setup()
	var palette: CozyPalette = load("res://assets/palettes/gg_material_palette.tres")
	var materials := MaterialLibrary.new(palette)
	var assets := AssetLibrary.new(materials)
	var factory := TileVisualFactory.new(assets, core.grid)

	add_child(
		(load("res://scenes/visual/SumaSoftDaylight.tscn") as PackedScene).instantiate()
	)

	var camera_target := Node3D.new()
	camera_target.position = Vector3(0.0, 0.03, 0.0)
	add_child(camera_target)
	_camera_rig = CameraRig.new()
	add_child(_camera_rig)
	_camera_rig.setup(core, camera_target)
	_camera_rig._size_target = 9.5
	_camera_rig.camera.position.z = _camera_rig._size_target

	var hero := factory.instantiate_visual(core.registries.tile("tile_sand"), true)
	hero.position = Vector3.ZERO
	add_child(hero)
	await _capture("sand_tile_gameplay_close.png")
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	await _capture("sand_tile_gameplay_wireframe.png")
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED

	var spacing := core.grid.tile_size
	hero.free()
	var patch_cells: Array[Vector2i] = [
		Vector2i.ZERO,
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, -1),
		Vector2i(0, 1),
		Vector2i(-1, -1),
		Vector2i(1, 1),
	]
	for offset: Vector2i in patch_cells:
		core.grid.place_tile(offset, "tile_sand")
	var sand_def := core.registries.tile("tile_sand")
	for offset: Vector2i in patch_cells:
		var neighbour_mask := factory.connection_mask(
			sand_def,
			offset,
			0,
			0
		)
		var neighbour := factory.instantiate_visual(
			sand_def,
			true,
			neighbour_mask,
			TileVisualFactory.detail_variant_for_coord(sand_def, offset)
		)
		neighbour.position = Vector3(offset.x * spacing, 0.0, offset.y * spacing)
		add_child(neighbour)
	_camera_rig._size_target = 16.0
	_camera_rig.camera.position.z = 16.0
	await _capture("sand_tile_gameplay_patch.png")

	var lower := factory.instantiate_visual(core.registries.tile("tile_sand"), true)
	lower.position = Vector3(2.0 * spacing, 0.0, 0.0)
	add_child(lower)
	factory.set_surface_covered(lower, true)
	var upper := factory.instantiate_visual(core.registries.tile("tile_sand"), true)
	upper.position = Vector3(2.0 * spacing, core.grid.block_depth, 0.0)
	add_child(upper)
	_camera_rig._pan_offset = Vector3(spacing, 0.0, 0.0)
	_camera_rig._size_target = 18.0
	_camera_rig.camera.position.z = 18.0
	await _capture("sand_tile_gameplay_stack.png")

	print(
		"SAND TILE GAMEPLAY REVIEW CAPTURED — %s"
		% ProjectSettings.globalize_path(_output_dir)
	)
	get_tree().quit()


func _capture(filename: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	get_viewport().get_texture().get_image().save_png(
		absolute_dir.path_join(filename)
	)
