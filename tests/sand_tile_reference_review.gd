extends Node
## Focused visual and structural review for the reference-matched sand top.
##
## The left 2x2 patch proves neighbour continuity. The right column proves
## that a covered lower sand tile loses its cap/heightfield and receives the
## ordinary body-coloured infill while the exposed upper tile keeps the dune.
##
## Run:
##   godot --path . tests/sand_tile_reference_review.tscn -- \
##     --shot-dir=<absolute folder>

const AUTHORED_HALF := 0.85
const VISUAL_HALF := 0.8704
const RELIEF_MIN := -0.055
const RELIEF_MAX := 0.170
const EPS := 0.0005

var _camera: Camera3D
var _output_dir := "user://sand_tile_reference_review"
var _failures := 0
var _review_tiles: Array[Node3D] = []


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")

	var palette: CozyPalette = load("res://assets/palettes/gg_material_palette.tres")
	var materials := MaterialLibrary.new(palette)
	var assets := AssetLibrary.new(materials)
	var core := GameCore.new()
	core.setup()
	var factory := TileVisualFactory.new(assets, core.grid)

	_add_review_lighting()
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_camera.size = 6.0
	add_child(_camera)

	var spacing := core.grid.tile_size
	for row in 2:
		for column in 2:
			var patch_tile := factory.instantiate_visual(
				core.registries.tile("tile_sand"),
				true
			)
			patch_tile.position = Vector3(
				-1.35 + (column - 0.5) * spacing,
				0.0,
				(row - 0.5) * spacing
			)
			add_child(patch_tile)
			_review_tiles.append(patch_tile)

	var lower := factory.instantiate_visual(core.registries.tile("tile_sand"), true)
	lower.position = Vector3(1.35, 0.0, 0.0)
	add_child(lower)
	_review_tiles.append(lower)
	factory.set_surface_covered(lower, true)

	var upper := factory.instantiate_visual(core.registries.tile("tile_sand"), true)
	upper.position = Vector3(1.35, core.grid.block_depth, 0.0)
	add_child(upper)
	_review_tiles.append(upper)

	_verify_exposed_tile(upper)
	_verify_covered_tile(lower)
	if _failures > 0:
		push_error("SAND TILE REVIEW FAILED (%d checks)" % _failures)
		get_tree().quit(1)
		return
	if DisplayServer.get_name() == "headless":
		print("SAND TILE STRUCTURAL REVIEW PASSED")
		get_tree().quit()
		return

	_camera.position = Vector3(5.7, 5.4, 6.5)
	_camera.look_at(Vector3(0.0, 0.05, 0.0), Vector3.UP)
	await _capture("sand_tile_reference_review.png")

	for tile in _review_tiles:
		tile.visible = false
	var reference_tile := factory.instantiate_visual(
		core.registries.tile("tile_sand"),
		true
	)
	reference_tile.position = Vector3.ZERO
	add_child(reference_tile)
	_camera.size = 2.75
	_camera.position = Vector3(2.65, 2.35, 2.65)
	_camera.look_at(Vector3(0.0, -0.12, 0.0), Vector3.UP)
	await _capture("sand_tile_reference_view.png")
	_camera.position = Vector3(-2.65, 2.35, 2.65)
	_camera.look_at(Vector3(0.0, -0.12, 0.0), Vector3.UP)
	await _capture("sand_tile_orbit_view.png")
	_camera.position = Vector3(0.0, 1.65, 3.1)
	_camera.look_at(Vector3(0.0, -0.12, 0.0), Vector3.UP)
	await _capture("sand_tile_side_view.png")
	_camera.position = Vector3(2.9, 0.82, 2.9)
	_camera.look_at(Vector3(0.0, -0.08, 0.0), Vector3.UP)
	await _capture("sand_tile_grazing_view.png")

	print("SAND TILE REVIEW PASSED — %s" % ProjectSettings.globalize_path(_output_dir))
	get_tree().quit()


func _capture(filename: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var absolute_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	get_viewport().get_texture().get_image().save_png(absolute_dir.path_join(filename))


func _add_review_lighting() -> void:
	# The current worktree's shared SumaSoftDaylight scene/profile is being
	# reworked and is temporarily absent. Keep this focused artifact deterministic
	# and close to the production warm day rig without mutating that unrelated work.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#D7D0BE")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#F1E5C8")
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.light_color = Color("#FFF0C8")
	key.light_energy = 1.18
	key.rotation_degrees = Vector3(-56.0, -38.0, 0.0)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 30.0
	add_child(key)


func _verify_exposed_tile(tile: Node3D) -> void:
	var surface := tile.find_child("sand_surface", true, false) as MeshInstance3D
	_check(surface != null, "exposed tile contains sand_surface")
	if surface == null:
		return
	var bounds := surface.get_aabb()
	_check(surface.visible, "exposed sand surface is visible")
	_check(
		absf(bounds.position.x + VISUAL_HALF) <= EPS
		and absf(bounds.end.x - VISUAL_HALF) <= EPS
		and absf(bounds.position.z + VISUAL_HALF) <= EPS
		and absf(bounds.end.z - VISUAL_HALF) <= EPS,
		"sand lip preserves the tile footprint with a 1.2% visual overhang"
	)
	_check(
		bounds.position.y >= RELIEF_MIN - EPS
		and bounds.end.y <= RELIEF_MAX + EPS,
		"sand surface stays inside the coverable relief budget"
	)
	var material := surface.get_active_material(0)
	_check(
		material != null
		and material.resource_name == "sand_top"
		and material is StandardMaterial3D,
		"sand surface rebinds to Suma's shared matte sand_top material"
	)
	var arrays := surface.mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var triangle_count := indices.size() / 3
	print("  INFO  imported sand triangle count = %d" % triangle_count)
	_check(
		triangle_count >= 800 and triangle_count <= 1500,
		"sand cap stays inside the requested 800..1500 triangle budget"
	)
	var minimum_up_normal := 1.0
	var maximum_top_normal_x := 0.0
	var maximum_top_normal_z := 0.0
	var has_side_normal := false
	for normal in normals:
		minimum_up_normal = minf(minimum_up_normal, normal.y)
		if normal.y > 0.35:
			maximum_top_normal_x = maxf(maximum_top_normal_x, absf(normal.x))
			maximum_top_normal_z = maxf(maximum_top_normal_z, absf(normal.z))
		if absf(normal.y) < 0.25:
			has_side_normal = true
	print("  INFO  imported sand normal.y minimum = %.6f" % minimum_up_normal)
	_check(minimum_up_normal < 0.999, "sand surface imports non-flat dune normals")
	_check(
		maximum_top_normal_x > 0.12 and maximum_top_normal_z > 0.12,
		"sand surface has strong slopes in both horizontal directions"
	)
	_check(has_side_normal, "sand surface includes a geometric perimeter skirt")

	var minimum_edge_height := RELIEF_MAX
	var maximum_edge_height := RELIEF_MIN
	var high_centroid := Vector2.ZERO
	var high_count := 0
	var occupied_high_quadrants := {}
	for vertex in vertices:
		var on_edge := (
			maxf(absf(vertex.x), absf(vertex.z)) >= AUTHORED_HALF * 0.92
		)
		if on_edge and vertex.y > 0.0:
			minimum_edge_height = minf(minimum_edge_height, vertex.y)
			maximum_edge_height = maxf(maximum_edge_height, vertex.y)
		if vertex.y > 0.10:
			high_centroid += Vector2(vertex.x, vertex.z)
			high_count += 1
			var quadrant := Vector2i(
				1 if vertex.x >= 0.0 else -1,
				1 if vertex.z >= 0.0 else -1
			)
			occupied_high_quadrants[quadrant] = true
	print("  INFO  sand edge-height range = %.6f .. %.6f" % [
		minimum_edge_height,
		maximum_edge_height,
	])
	_check(
		maximum_edge_height - minimum_edge_height > 0.020,
		"sand skin varies visibly in height along the block sides"
	)
	_check(high_count > 0, "sand surface contains a pronounced macro dune")
	_check(
		occupied_high_quadrants.size() >= 2,
		"broad dune mass spans multiple tile quadrants without uniform repetition"
	)
	if high_count > 0:
		high_centroid /= float(high_count)
		print("  INFO  high-dune centroid = %s" % high_centroid)
		_check(
			high_centroid.length() > 0.05,
			"highest sand mass is offset instead of centrally symmetric"
		)


func _verify_covered_tile(tile: Node3D) -> void:
	var surface := tile.find_child("sand_surface", true, false) as MeshInstance3D
	var cap := tile.find_child("sand_cap", true, false) as MeshInstance3D
	var infill := tile.find_child("CoveredSurfaceInfill", true, false) as MeshInstance3D
	_check(surface != null and not surface.visible, "covered tile hides sand relief")
	_check(cap != null and not cap.visible, "covered tile hides authored sand cap")
	_check(infill != null and infill.visible, "covered tile shows flush body-coloured infill")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS  %s" % message)
		return
	_failures += 1
	push_error("  FAIL  %s" % message)
