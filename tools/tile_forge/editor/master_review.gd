extends Node3D
## Acceptance-gate renderer for the three hand-authored master tiles.
##
## It exists to prove ONE architectural claim: a logical tile is not a visible
## block. A region is assembled as
##
##     SurfaceCap    one per cell, meeting edge to edge with zero gap and no
##                   perimeter treatment of any kind;
##     EdgeSkirt     ONLY where a cell has no compatible neighbour;
##     EdgeCorner    only at outside corners of the region;
##     Collision     one flat box per cell, invisible and independent.
##
## Internal side geometry is never built, so a 5x5 grass region has to read as
## one lawn rather than as 25 cubes — if it does not, the failure is in the art,
## not hidden by the renderer.
##
##   godot --path . tools/tile_forge/editor/master_review.tscn -- \
##       --shot-dir=<abs> [--clay]

const REPORT := "res://tools/tile_forge/masters/master_report.json"
const DAYLIGHT := "res://scenes/visual/SumaSoftDaylight.tscn"

const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8

var tile_size := 1.35
var _camera: Camera3D
var _output_dir := "user://tile_forge"
var _report: Dictionary = {}
var _paths: Dictionary = {}
var _region: Node3D
var _clay_material: StandardMaterial3D


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	_load_report()
	_environment()
	await get_tree().process_frame
	await _run()
	get_tree().quit()


func _load_report() -> void:
	var file := FileAccess.open(REPORT, FileAccess.READ)
	if file == null:
		push_error("no master report at %s" % REPORT)
		return
	_report = JSON.parse_string(file.get_as_text())
	tile_size = float(_report.get("tile_size", 1.35))
	for entry: Dictionary in _report.get("modules", []):
		_paths[String(entry["id"])] = String(entry["path"])


## The real Suma daylight rig, plus a broad environmental fill. The brief asks
## for a judgement under gameplay lighting, not under product-render lighting:
## no hard black plant shadows and no dramatic key.
func _environment() -> void:
	var scene: PackedScene = load(DAYLIGHT)
	if scene != null:
		add_child(scene.instantiate())
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.886, 0.867, 0.796)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.855, 0.83)
	environment.ambient_light_energy = 1.05
	environment.ssao_enabled = true
	environment.ssao_radius = 0.28
	environment.ssao_intensity = 0.9
	environment.ssao_power = 2.4
	environment.ssao_light_affect = 0.25
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 3.2
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.42
	fill.light_color = Color(0.86, 0.90, 0.97)
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-28.0, -52.0, 0.0)
	add_child(fill)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 15.0
	_camera.current = true
	add_child(_camera)

	_clay_material = StandardMaterial3D.new()
	_clay_material.albedo_color = Color(0.784, 0.761, 0.714)
	_clay_material.roughness = 1.0
	_clay_material.metallic_specular = 0.12


# --- region assembly ---------------------------------------------------------


func _cap_id(family: String, coord: Vector2i) -> String:
	match family:
		"grass":
			# Twelve authored layouts chosen by coordinate. Neighbours never
			# share one: the offsets are coprime with the layout count, so the
			# same arrangement cannot land next to itself in either axis.
			var count: int = int(_report.get("grass_layouts", 12))
			var index := posmod(coord.x * 5 + coord.y * 7, count)
			return "master_grass_lush_%02d" % index
		"paver":
			return "master_soft_pavers_%02d" % posmod(coord.x * 3 + coord.y, 4)
		_:
			# Wood run phase advances across the grain so board seams do not
			# line up cell to cell and the deck reads as continuous.
			return "master_wood_planks_%02d" % posmod(coord.y * 2 + coord.x, 4)


func _instance(id: String) -> Node3D:
	var path: String = _paths.get(id, "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	return scene.instantiate() as Node3D


## Builds an `size` x `size` region. `exposed` decides whether the perimeter
## gets skirts, which is how the interior-connected view is produced.
func _build_region(family: String, size: int, exposed := true) -> Node3D:
	if _region != null and is_instance_valid(_region):
		_region.free()
	_region = Node3D.new()
	_region.name = "Region"
	add_child(_region)

	var skirt_id := "master_%s_skirt" % family
	var corner_id := "master_%s_corner" % family
	var half := float(size - 1) * 0.5

	for row in size:
		for column in size:
			var coord := Vector2i(column, row)
			var origin := Vector3(
				(float(column) - half) * tile_size,
				0.0,
				(float(row) - half) * tile_size
			)
			var cap := _instance(_cap_id(family, coord))
			if cap != null:
				cap.position = origin
				_region.add_child(cap)

			if not exposed:
				continue
			# Exposed-edge mask: a skirt exists only where there is no
			# compatible neighbour. Internal edges get nothing at all.
			var mask := 0
			if row == 0:
				mask |= NORTH
			if row == size - 1:
				mask |= SOUTH
			if column == 0:
				mask |= WEST
			if column == size - 1:
				mask |= EAST
			_add_skirts(origin, mask, skirt_id, corner_id)
	return _region


## The skirt is authored along +Z. Each exposed side is the same mesh rotated
## into place, so one module covers all four edges.
func _add_skirts(origin: Vector3, mask: int, skirt_id: String, corner_id: String) -> void:
	var sides := {
		SOUTH: 0.0,
		WEST: PI * 0.5,
		NORTH: PI,
		EAST: PI * 1.5,
	}
	for bit: int in sides:
		if mask & bit == 0:
			continue
		var skirt := _instance(skirt_id)
		if skirt == null:
			continue
		skirt.position = origin
		skirt.rotation.y = sides[bit]
		_region.add_child(skirt)

	# Corners are authored at +X/+Z and rotated the same way.
	var corners := [
		[SOUTH | EAST, 0.0],
		[SOUTH | WEST, PI * 0.5],
		[NORTH | WEST, PI],
		[NORTH | EAST, PI * 1.5],
	]
	for entry in corners:
		var bits: int = entry[0]
		if mask & bits != bits:
			continue
		var corner := _instance(corner_id)
		if corner == null:
			continue
		corner.position = origin
		corner.rotation.y = entry[1]
		_region.add_child(corner)


func _apply_clay() -> void:
	for child in _region.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).material_override = _clay_material


# --- capture -----------------------------------------------------------------


func _frame(extent: float, centre := Vector3.ZERO) -> void:
	var distance := extent / (2.0 * tan(deg_to_rad(_camera.fov * 0.5)))
	var direction := Vector3(0.0, 0.0, 1.0) \
		.rotated(Vector3.RIGHT, deg_to_rad(-40.0)) \
		.rotated(Vector3.UP, deg_to_rad(45.0))
	_camera.position = centre + direction * distance
	_camera.look_at(centre, Vector3.UP)


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var absolute := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute)
	get_viewport().get_texture().get_image().save_png(absolute.path_join(filename))


func _set_wireframe(enabled: bool) -> void:
	RenderingServer.set_debug_generate_wireframes(enabled)
	get_viewport().debug_draw = (
		Viewport.DEBUG_DRAW_WIREFRAME if enabled else Viewport.DEBUG_DRAW_DISABLED
	)


func _run() -> void:
	for family in ["grass", "paver", "wood"]:
		# 1. single tile, close
		_build_region(family, 1)
		_frame(tile_size * 1.45)
		await _shoot("%s_1_single.png" % family)

		# 2. gameplay camera distance
		_build_region(family, 5)
		_frame(tile_size * 7.2)
		await _shoot("%s_2_gameplay.png" % family)

		# 3. 3x3
		_build_region(family, 3)
		_frame(tile_size * 4.1)
		await _shoot("%s_3_repeat3.png" % family)

		# 4. 5x5
		_build_region(family, 5)
		_frame(tile_size * 6.0)
		await _shoot("%s_4_repeat5.png" % family)

		# 5. clay — geometry judged with no colour to hide behind
		_build_region(family, 3)
		_apply_clay()
		_frame(tile_size * 4.1)
		await _shoot("%s_5_clay.png" % family)

		# 6. exposed island edge, seen low so the skirt is the subject
		_build_region(family, 3)
		_camera.fov = 22.0
		var distance := tile_size * 3.2 / (2.0 * tan(deg_to_rad(11.0)))
		var direction := Vector3(0.0, 0.0, 1.0) \
			.rotated(Vector3.RIGHT, deg_to_rad(-16.0)) \
			.rotated(Vector3.UP, deg_to_rad(35.0))
		_camera.position = direction * distance
		_camera.look_at(Vector3.ZERO, Vector3.UP)
		await _shoot("%s_6_island_edge.png" % family)
		_camera.fov = 15.0

		# 7. interior connected edges only — no skirts anywhere, which is what
		# every internal cell boundary actually looks like in a region.
		_build_region(family, 3, false)
		_frame(tile_size * 2.6)
		await _shoot("%s_7_interior_seam.png" % family)

		# 8. wireframe
		_build_region(family, 3)
		_set_wireframe(true)
		_frame(tile_size * 4.1)
		await _shoot("%s_8_wireframe.png" % family)
		_set_wireframe(false)

	print("MASTER REVIEW CAPTURED — %s" % _output_dir)
