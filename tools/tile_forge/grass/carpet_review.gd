extends Node3D
## Validation renders for the carpet-tuft grass rebuild.
##
## Carpet tufts fail in ways a shaded hero shot hides. A lobe cluster can read as
## a soft mass in clay and still be a spiky botanical star in outline, and twelve
## tufts can each look fine alone while leaving bald gaps once they are scattered.
## So shape is judged flat and black before it is judged lit, and the patch is
## captured twice from one arrangement: clay for feel, black top-down for whether
## the carpet actually closes.
##
##   godot --path . tools/tile_forge/grass/carpet_review.tscn -- --shot-dir=<abs>
##
## Outputs per module: sil_top_<id>, sil_iso_<id>, clay_<id>, thumb_<id>.
## Outputs per set:    carpet_12_clay, carpet_12_sil (carpet kinds only).

const REPORT := "res://tools/tile_forge/modules/grass/carpet_report.json"

## Silhouettes go through a square SubViewport, never the 16:9 window: the
## analyzer turns pixel counts into footprint area, so a stretched axis is a
## silently wrong measurement rather than an obviously wrong picture.
const FRAME_SIZE := 1024
const THUMB_SIZE := 128

## Fraction of the square frame the measured outline should occupy. Framing is
## exact (see _aim), so these are real margins, not guesses — clay keeps more
## room than the silhouettes because the key light throws a shadow that would
## otherwise crop.
const SIL_FILL := 0.80
const CLAY_FILL := 0.74
const GROUP_CLAY_FILL := 0.82

const GAMEPLAY_PITCH := -40.0
const GAMEPLAY_YAW := 45.0

## Square metre patch, overridable with --patch=<metres>. Density is the whole
## question the group shots exist to answer, so it is a knob rather than a
## constant somebody has to edit the script to move.
const DEFAULT_PATCH_SIZE := 1.0
const PATCH_COLUMNS := 4
const PATCH_ROWS := 3
const PATCH_COUNT := PATCH_COLUMNS * PATCH_ROWS
## Fixed so a re-run is diffable against the previous run rather than merely
## similar to it.
const PATCH_SEED := 20260801
const PATCH_JITTER := 0.30
const SCALE_MIN := 0.88
const SCALE_MAX := 1.12

const PLATE_COLOUR := Color(0.80, 0.78, 0.73)
const STUDIO_BACKGROUND := Color(0.886, 0.867, 0.796)

var _output_dir := "user://tile_forge"
var _patch_size := DEFAULT_PATCH_SIZE
var _modules: Array = []
var _paths: Dictionary = {}
var _saved := 0

var _clay_material: StandardMaterial3D
var _flat_material: StandardMaterial3D

var _flat_view: SubViewport
var _flat_camera: Camera3D
var _flat_stage: Node3D

var _clay_view: SubViewport
var _clay_camera: Camera3D
var _clay_stage: Node3D
var _plate: MeshInstance3D

var _thumb_view: SubViewport
var _thumb_camera: Camera3D


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
		elif argument.begins_with("--patch="):
			_patch_size = maxf(argument.trim_prefix("--patch=").to_float(), 0.05)
	if not _load_report():
		print("CARPET REVIEW FAILED — no manifest at %s" % REPORT)
		get_tree().quit(1)
		return

	_build_materials()
	_build_flat_rig()
	_build_shaded_rig()
	# Warm-up. The freshly built render targets and their scenarios do not settle
	# on the first frame, and without this the very first capture of the run came
	# back pure white while every later one was correct.
	for _index in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var rendered := 0
	# Warm-up pass. The first module through a freshly created SubViewport was
	# captured before its camera transform had reached the render server, so it
	# came out small and off-centre. Running it once and discarding the result
	# costs a few frames and removes the whole class of first-frame artefacts.
	if not _modules.is_empty():
		await _module_passes(_modules[0])

	for entry: Dictionary in _modules:
		if await _module_passes(entry):
			rendered += 1
	await _group_passes()

	print(
		"CARPET REVIEW CAPTURED — %d/%d modules, %d images -> %s"
		% [rendered, _modules.size(), _saved, ProjectSettings.globalize_path(_output_dir)]
	)
	get_tree().quit()


func _load_report() -> bool:
	var file := FileAccess.open(REPORT, FileAccess.READ)
	if file == null:
		push_error("no carpet report at %s" % REPORT)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("carpet report is not a JSON object")
		return false
	var listed: Variant = (parsed as Dictionary).get("modules", [])
	if typeof(listed) != TYPE_ARRAY:
		push_error("carpet report has no modules array")
		return false
	_modules = listed as Array
	for entry: Dictionary in _modules:
		_paths[String(entry.get("id", ""))] = String(entry.get("path", ""))
	return not _modules.is_empty()


# ---------------------------------------------------------------- rig assembly

func _build_materials() -> void:
	_clay_material = StandardMaterial3D.new()
	_clay_material.albedo_color = Color(0.784, 0.761, 0.714)
	_clay_material.roughness = 0.95
	_clay_material.metallic_specular = 0.14

	# Unshaded pure black with culling off: the silhouette must be one solid
	# region even where a lobe's back faces the camera, otherwise the analyzer
	# reads an interior hole as a gap in the tuft.
	_flat_material = StandardMaterial3D.new()
	_flat_material.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	_flat_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flat_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flat_material.disable_ambient_light = true
	_flat_material.disable_receive_shadows = true


## Measurement rig: white void, no lights, no post, no antialiasing. Anything
## that softens or tints an edge here becomes measurement error downstream.
func _build_flat_rig() -> void:
	_flat_view = SubViewport.new()
	_flat_view.name = "FlatView"
	_flat_view.size = Vector2i(FRAME_SIZE, FRAME_SIZE)
	_flat_view.transparent_bg = false
	_flat_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_flat_view.msaa_3d = Viewport.MSAA_DISABLED
	_flat_view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_flat_view.use_taa = false
	_flat_view.use_debanding = false
	_flat_view.positional_shadow_atlas_size = 0
	add_child(_flat_view)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(1.0, 1.0, 1.0)
	environment.background_energy_multiplier = 1.0
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	# Linear tonemapping only: filmic would pull the white plate off 255 and the
	# analyzer thresholds on pure white.
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 1.0
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.sdfgi_enabled = false
	environment.glow_enabled = false
	environment.fog_enabled = false
	environment.adjustment_enabled = false

	var world := World3D.new()
	world.environment = environment
	_flat_view.world_3d = world

	_flat_camera = _make_camera()
	_flat_view.add_child(_flat_camera)

	_flat_stage = Node3D.new()
	_flat_stage.name = "FlatStage"
	_flat_view.add_child(_flat_stage)


## Clay rig. The thumbnail viewport shares this World3D so the 128px frame is a
## genuine 128px render of the same stage, not a downscale of the big one.
func _build_shaded_rig() -> void:
	_clay_view = SubViewport.new()
	_clay_view.name = "ClayView"
	_clay_view.size = Vector2i(FRAME_SIZE, FRAME_SIZE)
	_clay_view.transparent_bg = false
	_clay_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_clay_view.msaa_3d = Viewport.MSAA_4X
	add_child(_clay_view)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = STUDIO_BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.855, 0.84)
	environment.ambient_light_energy = 0.9
	environment.ssao_enabled = true
	environment.ssao_radius = 0.16
	environment.ssao_intensity = 1.15
	environment.ssao_power = 2.2
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 3.0

	var world := World3D.new()
	world.environment = environment
	_clay_view.world_3d = world

	_clay_camera = _make_camera()
	_clay_view.add_child(_clay_camera)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.05
	key.light_color = Color(1.0, 0.975, 0.93)
	key.shadow_enabled = true
	key.shadow_blur = 2.2
	key.rotation_degrees = Vector3(-46.0, 132.0, 0.0)
	_clay_view.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.40
	fill.light_color = Color(0.87, 0.91, 0.98)
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-22.0, -48.0, 0.0)
	_clay_view.add_child(fill)

	_plate = MeshInstance3D.new()
	_plate.name = "Plate"
	_plate.mesh = BoxMesh.new()
	var plate_material := StandardMaterial3D.new()
	plate_material.albedo_color = PLATE_COLOUR
	plate_material.roughness = 1.0
	_plate.material_override = plate_material
	_clay_view.add_child(_plate)

	# Kept out of the stage so bounds measurement never sees the plate.
	_clay_stage = Node3D.new()
	_clay_stage.name = "ClayStage"
	_clay_view.add_child(_clay_stage)

	_thumb_view = SubViewport.new()
	_thumb_view.name = "ThumbView"
	_thumb_view.size = Vector2i(THUMB_SIZE, THUMB_SIZE)
	_thumb_view.transparent_bg = false
	_thumb_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_thumb_view.msaa_3d = Viewport.MSAA_4X
	_thumb_view.world_3d = world
	add_child(_thumb_view)

	_thumb_camera = _make_camera()
	_thumb_view.add_child(_thumb_camera)


func _make_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.current = true
	return camera


func _set_plate(size: float) -> void:
	var mesh := _plate.mesh as BoxMesh
	mesh.size = Vector3(size, 0.04, size)
	# Top face flush with y = 0, which is where the modules make ground contact.
	_plate.position.y = -0.02


# ------------------------------------------------------------- stage handling

func _clear(stage: Node3D) -> void:
	for child in stage.get_children():
		stage.remove_child(child)
		child.queue_free()


func _spawn(id: String, stage: Node3D, material: Material) -> Node3D:
	var path := String(_paths.get(id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("carpet module %s missing at %s" % [id, path])
		return null
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		push_warning("carpet module %s did not load as a scene" % id)
		return null
	var node := scene.instantiate() as Node3D
	if node == null:
		return null
	for child in node.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).material_override = material
	stage.add_child(node)
	return node


## Vertices, not AABBs. Merging per-mesh AABBs re-axis-aligns each rotated lobe
## and inflates the union by a different amount per module, which silently
## shrank every silhouette away from the 80% the analyzer expects. A few hundred
## transformed points per tuft costs nothing and is exact from any angle.
func _points(root: Node3D) -> PackedVector3Array:
	var to_local := root.global_transform.affine_inverse()
	var cloud := PackedVector3Array()
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var transform := to_local * mesh_instance.global_transform
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			if arrays.is_empty():
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				cloud.append(transform * vertex)
	return cloud


func _bounds_of(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var bounds := AABB(points[0], Vector3.ZERO)
	for index in range(1, points.size()):
		bounds = bounds.expand(points[index])
	return bounds


func _corners_of(bounds: AABB) -> PackedVector3Array:
	var corners := PackedVector3Array()
	for index in 8:
		corners.append(bounds.get_endpoint(index))
	return corners


## Orthographic framing from the point cloud projected onto the view plane, so
## every pass fits the real outline without hand-tuned per-angle padding.
func _aim(
	camera: Camera3D, points: PackedVector3Array, pitch: float, yaw: float, fill: float
) -> void:
	var basis := Basis.from_euler(
		Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0), EULER_ORDER_YXZ
	)
	camera.near = 0.01
	if points.is_empty():
		camera.size = 1.0
		camera.far = 100.0
		camera.transform = Transform3D(basis, basis.z * 10.0)
		return

	var right := basis.x
	var up := basis.y
	var back := basis.z
	var min_right := INF
	var max_right := -INF
	var min_up := INF
	var max_up := -INF
	var max_back := -INF
	for point in points:
		min_right = minf(min_right, point.dot(right))
		max_right = maxf(max_right, point.dot(right))
		min_up = minf(min_up, point.dot(up))
		max_up = maxf(max_up, point.dot(up))
		max_back = maxf(max_back, point.dot(back))

	var span := maxf(max_right - min_right, max_up - min_up)
	camera.size = maxf(span / clampf(fill, 0.05, 1.0), 0.001)
	# The basis is orthonormal, so a world point rebuilds from its projections.
	var focus := right * ((min_right + max_right) * 0.5) + up * ((min_up + max_up) * 0.5)
	var distance := max_back + camera.size * 2.0 + 1.0
	camera.far = distance * 3.0 + 10.0
	camera.transform = Transform3D(basis, focus + back * distance)


func _capture(view: SubViewport, filename: String) -> void:
	# A timer alone races the draw queue; frame_post_draw is the only point at
	# which the render target is guaranteed to hold the frame we just set up.
	# Twice, because the first one can still belong to a frame whose commands
	# were built before this pass's camera move reached the rendering server.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(directory)
	var image := view.get_texture().get_image()
	if image == null:
		push_error("no image for %s" % filename)
		return
	if image.save_png(directory.path_join(filename)) != OK:
		push_error("could not write %s" % filename)
		return
	_saved += 1


# -------------------------------------------------------------- module passes

func _module_passes(entry: Dictionary) -> bool:
	var id := String(entry.get("id", ""))
	if id.is_empty():
		return false

	_clear(_flat_stage)
	var flat := _spawn(id, _flat_stage, _flat_material)
	if flat == null:
		return false
	await get_tree().process_frame
	var points := _points(flat)

	_plate.visible = false
	_aim(_flat_camera, points, -90.0, 0.0, SIL_FILL)
	await _capture(_flat_view, "sil_top_%s.png" % id)
	_aim(_flat_camera, points, GAMEPLAY_PITCH, GAMEPLAY_YAW, SIL_FILL)
	await _capture(_flat_view, "sil_iso_%s.png" % id)
	_clear(_flat_stage)

	_clear(_clay_stage)
	if _spawn(id, _clay_stage, _clay_material) == null:
		return false
	var bounds := _bounds_of(points)
	var reach := maxf(maxf(bounds.size.x, bounds.size.z), 0.05)
	_plate.visible = true
	_set_plate(reach * 8.0)
	# Thumb shares this stage and world, so it gets the identical framing.
	_aim(_clay_camera, points, GAMEPLAY_PITCH, GAMEPLAY_YAW, CLAY_FILL)
	_aim(_thumb_camera, points, GAMEPLAY_PITCH, GAMEPLAY_YAW, CLAY_FILL)
	await _capture(_clay_view, "clay_%s.png" % id)
	await _capture(_thumb_view, "thumb_%s.png" % id)
	_clear(_clay_stage)
	return true


# --------------------------------------------------------------- group passes

func _carpet_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for entry: Dictionary in _modules:
		if String(entry.get("kind", "")) == "carpet":
			result.append(String(entry.get("id", "")))
	return result


## Deterministic bag: every module gets used before any repeats, and the shuffle
## runs off our own RandomNumberGenerator because Array.shuffle() draws from the
## global generator and would drift between runs.
func _deal(ids: PackedStringArray, count: int, rng: RandomNumberGenerator) -> PackedStringArray:
	var bag := PackedStringArray()
	while bag.size() < count:
		for id in ids:
			bag.append(id)
			if bag.size() == count:
				break
	for index in range(bag.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held := bag[index]
		bag[index] = bag[swap]
		bag[swap] = held
	return bag


## Jittered lattice rather than free scatter: pure random placement clusters and
## leaves holes at only twelve samples, and a clean grid is instantly readable as
## a grid. Half-cell jitter keeps the coverage even while breaking the rows.
func _placements() -> Array:
	var ids := _carpet_ids()
	if ids.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = PATCH_SEED
	var bag := _deal(ids, PATCH_COUNT, rng)
	var cell_x := _patch_size / float(PATCH_COLUMNS)
	var cell_z := _patch_size / float(PATCH_ROWS)
	var result: Array = []
	var index := 0
	for row in PATCH_ROWS:
		for column in PATCH_COLUMNS:
			var base_x := (float(column) + 0.5) * cell_x - _patch_size * 0.5
			var base_z := (float(row) + 0.5) * cell_z - _patch_size * 0.5
			result.append({
				"id": bag[index],
				"position": Vector3(
					base_x + rng.randf_range(-PATCH_JITTER, PATCH_JITTER) * cell_x,
					0.0,
					base_z + rng.randf_range(-PATCH_JITTER, PATCH_JITTER) * cell_z
				),
				"yaw": rng.randf_range(0.0, 360.0),
				"scale": rng.randf_range(SCALE_MIN, SCALE_MAX),
			})
			index += 1
	return result


func _populate(stage: Node3D, material: Material, placements: Array) -> void:
	for placement: Dictionary in placements:
		var tuft := _spawn(String(placement["id"]), stage, material)
		if tuft == null:
			continue
		tuft.position = placement["position"]
		tuft.rotation_degrees = Vector3(0.0, float(placement["yaw"]), 0.0)
		tuft.scale = Vector3.ONE * float(placement["scale"])


func _group_passes() -> void:
	var placements := _placements()
	if placements.is_empty():
		push_warning("no carpet-kind modules to scatter")
		return

	_clear(_clay_stage)
	_populate(_clay_stage, _clay_material, placements)
	await get_tree().process_frame
	var points := _points(_clay_stage)
	_plate.visible = true
	_set_plate(_patch_size * 6.0)
	_aim(_clay_camera, points, GAMEPLAY_PITCH, GAMEPLAY_YAW, GROUP_CLAY_FILL)
	await _capture(_clay_view, "carpet_12_clay.png")
	_clear(_clay_stage)

	_clear(_flat_stage)
	_populate(_flat_stage, _flat_material, placements)
	await get_tree().process_frame
	_plate.visible = false
	# Framed on the nominal patch, not on the scattered outline: a fixed square
	# at 80% fill pins the metres-per-pixel scale, so the analyzer can measure
	# closure inside the patch and still read overhang as overhang.
	var patch := AABB(
		Vector3(-_patch_size * 0.5, 0.0, -_patch_size * 0.5),
		Vector3(_patch_size, 0.01, _patch_size)
	)
	_aim(_flat_camera, _corners_of(patch), -90.0, 0.0, SIL_FILL)
	await _capture(_flat_view, "carpet_12_sil.png")
	_clear(_flat_stage)
