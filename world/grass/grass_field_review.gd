extends Node3D
## Validation captures for the grass carpet, in the order the brief asks for
## them.
##
## Two of these views are the ones that actually decide whether the work passed.
## View 9 renders the surface unlit with a wireframe overlay: an internal cell or
## chunk boundary either exists as geometry there or it does not, which settles
## the seam question with evidence instead of argument. View 6 is the gameplay
## camera, because a field that only holds up in an orthographic studio shot has
## not been validated for the game it ships in.
##
##   godot --path . world/grass/grass_field_review.tscn -- --shot-dir=<abs path>

const REGION_TILES := 8
const CAMERA_PITCH := -40.0
const CAMERA_YAW := 45.0

var _output_dir := "user://grass_review"
var _manager: GrassFieldManager
var _profile: GrassFieldProfile
var _camera: Camera3D
var _environment: Environment
var _clearance_root: Node3D
var _report: Dictionary = {}


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	_build_rig()
	await get_tree().process_frame
	await _run()
	var absolute := ProjectSettings.globalize_path(_output_dir)
	var file := FileAccess.open(absolute.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_report, "  "))
	print("GRASS REVIEW CAPTURED — %s" % absolute)
	get_tree().quit()


func _build_rig() -> void:
	_profile = GrassFieldProfile.new()

	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0.855, 0.839, 0.796)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.82, 0.835, 0.83)
	_environment.ambient_light_energy = 0.62
	# Restrained: the brief explicitly rules out thousands of tiny noisy contact
	# shadows, and a strong SSAO radius on a carpet of micro-tufts produces
	# exactly that.
	_environment.ssao_enabled = true
	_environment.ssao_radius = 0.10
	_environment.ssao_intensity = 0.65
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.tonemap_white = 3.6
	var world := WorldEnvironment.new()
	world.environment = _environment
	add_child(world)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.98, 0.945)
	key.shadow_enabled = true
	key.shadow_blur = 1.6
	key.rotation_degrees = Vector3(-48.0, 128.0, 0.0)
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.26
	fill.light_color = Color(0.86, 0.90, 0.97)
	fill.rotation_degrees = Vector3(-24.0, -52.0, 0.0)
	add_child(fill)

	_clearance_root = Node3D.new()
	_clearance_root.name = "Props"
	add_child(_clearance_root)

	_manager = GrassFieldManager.new()
	_manager.name = "GrassFieldManager"
	_manager.profile = _profile
	# LOD off for validation: these renders exist to judge the full carpet, and a
	# distance band silently thinning it would make every frame a different test.
	_manager.lod_enabled = false
	add_child(_manager)
	_manager.clearance_root = _manager.get_path_to(_clearance_root)
	_manager.set_grass_cells(_square(REGION_TILES))


func _square(span: int) -> Array:
	var cells: Array = []
	for row in span:
		for column in span:
			cells.append(Vector2i(column - span / 2, row - span / 2))
	return cells


func _extent() -> float:
	return REGION_TILES * _profile.tile_size


func _frame_orthographic(extent: float, pitch := CAMERA_PITCH, yaw := CAMERA_YAW) -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = extent
	var direction := Vector3(0.0, 0.0, 1.0) \
		.rotated(Vector3.RIGHT, deg_to_rad(pitch)) \
		.rotated(Vector3.UP, deg_to_rad(yaw))
	_camera.position = direction * 18.0
	_camera.look_at(Vector3.ZERO, Vector3.UP if absf(pitch) < 89.0 else Vector3.FORWARD)


## The real Suma gameplay lens: 15 degrees at a 40 degree pitch. Long focal
## length flattens the field, which is exactly the condition under which a
## repeating pattern becomes obvious — so this is the honest test, not the
## flattering one.
func _frame_gameplay(span: float, target := Vector3.ZERO) -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 15.0
	var distance := span / (2.0 * tan(deg_to_rad(7.5)))
	var direction := Vector3(0.0, 0.0, 1.0) \
		.rotated(Vector3.RIGHT, deg_to_rad(CAMERA_PITCH)) \
		.rotated(Vector3.UP, deg_to_rad(CAMERA_YAW))
	_camera.position = target + direction * distance
	_camera.look_at(target, Vector3.UP)


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var absolute := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute)
	get_viewport().get_texture().get_image().save_png(absolute.path_join(file_name))


func _solo(surface: bool, dense: bool, flexible: bool) -> void:
	for chunk: GrassRenderChunk3D in _manager.chunks():
		chunk.show_surface_only = surface
		chunk.show_dense_carpet_only = dense
		chunk.show_flexible_tufts_only = flexible


func _run() -> void:
	var extent := _extent()

	# 1. Bare continuous surface — the broad sculpting with nothing on it.
	_solo(true, false, false)
	_frame_orthographic(extent)
	await _shoot("01_surface_bare.png")

	# 2. Same geometry, top-down, where periodic structure is most obvious.
	_frame_orthographic(extent * 0.95, -89.9, 0.0)
	await _shoot("02_surface_tone_top_down.png")

	# 3. Dense carpet only.
	_solo(false, true, false)
	_frame_orthographic(extent)
	await _shoot("03_dense_carpet_only.png")

	# 4. Dense carpet plus flexible tufts.
	_solo(false, false, false)
	_frame_orthographic(extent)
	await _shoot("04_all_layers.png")

	# 5. Close-up on the micro-tuft meshes themselves.
	_frame_orthographic(_profile.tile_size * 1.2, -22.0, 30.0)
	await _shoot("05_micro_tuft_closeup.png")

	# 6. Gameplay camera — the view that has to hold up.
	_frame_gameplay(extent * 0.85)
	await _shoot("06_gameplay_camera.png")

	# 7. Three props with soft clearances. The test is that the grass opens up
	# without a hard circular hole appearing anywhere.
	_add_props()
	_manager.rebuild()
	_frame_gameplay(extent * 0.85)
	await _shoot("07_props_with_clearance.png")
	_clear_props()
	_manager.rebuild()

	# 8. Low across the exposed rim.
	_frame_orthographic(extent * 0.6, -12.0, 32.0)
	await _shoot("08_island_edge.png")

	# 9. The decisive one: unlit wireframe across a chunk boundary.
	_frame_orthographic(extent * 0.5, -35.0, 20.0)
	RenderingServer.set_debug_generate_wireframes(true)
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	await _shoot("09_wireframe_chunk_boundary.png")
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
	RenderingServer.set_debug_generate_wireframes(false)

	# 10-12. The three detail states, framed identically so they can be flipped
	# between and compared directly.
	for entry: Array in [
		[GrassRenderChunk3D.DetailState.NEAR, "10_lod_near.png"],
		[GrassRenderChunk3D.DetailState.MID, "11_lod_mid.png"],
		[GrassRenderChunk3D.DetailState.FAR, "12_lod_far.png"],
	]:
		for chunk: GrassRenderChunk3D in _manager.chunks():
			chunk.set_detail_state(entry[0])
		_frame_gameplay(extent * 0.85)
		await _shoot(String(entry[1]))
	for chunk: GrassRenderChunk3D in _manager.chunks():
		chunk.set_detail_state(GrassRenderChunk3D.DetailState.NEAR)

	# 13. Triangle and instance counts.
	_report["statistics"] = _manager.statistics()
	_report["seam_probe"] = _seam_probe()


func _add_props() -> void:
	for offset: Vector2 in [Vector2(-2.4, -1.6), Vector2(1.9, 0.7), Vector2(0.2, 2.8)]:
		var marker := GrassClearance3D.new()
		marker.radius = 0.55
		marker.position = Vector3(offset.x, 0.0, offset.y)
		_clearance_root.add_child(marker)


func _clear_props() -> void:
	for child in _clearance_root.get_children():
		_clearance_root.remove_child(child)
		child.free()


## Numeric proof to sit alongside view 9. Samples the height, normal and colour
## functions on both sides of a chunk boundary at the exact shared coordinate;
## anything but an exact match means a seam exists whether or not a screenshot
## happens to catch it.
func _seam_probe() -> Dictionary:
	var chunk_a := _manager.chunk_at(Vector2i(0, 0))
	var chunk_b := _manager.chunk_at(Vector2i(-1, 0))
	if chunk_a == null or chunk_b == null:
		return {"tested": 0, "mismatches": -1}
	var boundary := -_profile.tile_size * 0.5
	var mismatches := 0
	var tested := 0
	for step in 64:
		var world := Vector2(boundary, -3.0 + 0.1 * step)
		tested += 1
		if not is_equal_approx(chunk_a.height_at(world), chunk_b.height_at(world)):
			mismatches += 1
		elif chunk_a.normal_at(world).distance_to(chunk_b.normal_at(world)) > 0.000001:
			mismatches += 1
		elif not chunk_a.colour_at(world).is_equal_approx(chunk_b.colour_at(world)):
			mismatches += 1
	return {"tested": tested, "mismatches": mismatches}
