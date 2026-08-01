extends Node3D
## Validation renders for the lush-grass rebuild.
##
## Shape is judged before colour. The clay and silhouette passes exist so a weak
## leaf or a columnar clump cannot be hidden behind a nice palette — which is
## exactly how the previous three attempts got as far as a screenshot review.
##
##   godot --path . tools/tile_forge/grass/grass_review.tscn -- \
##       --shot-dir=<abs> --pass=shapes|field
##
## Passes:
##   shapes  leaf close-up in clay, the six clump silhouettes, clay clump sheet
##   field   single tile, region, trees, gameplay camera (added once the runtime
##           field builder exists)

const REPORT := "res://tools/tile_forge/modules/grass/grass_report.json"

var _camera: Camera3D
var _stage: Node3D
var _output_dir := "user://tile_forge"
var _pass := "shapes"
var _report: Dictionary = {}

var _clay: StandardMaterial3D
var _silhouette: StandardMaterial3D


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
		elif argument.begins_with("--pass="):
			_pass = argument.trim_prefix("--pass=")
	_load_report()
	_materials()
	await get_tree().process_frame
	if _pass == "shapes":
		await _shape_passes()
	print("GRASS REVIEW CAPTURED — %s" % _output_dir)
	get_tree().quit()


func _load_report() -> void:
	var file := FileAccess.open(REPORT, FileAccess.READ)
	if file == null:
		push_error("no grass report at %s" % REPORT)
		return
	_report = JSON.parse_string(file.get_as_text())


func _materials() -> void:
	_clay = StandardMaterial3D.new()
	_clay.albedo_color = Color(0.784, 0.761, 0.714)
	_clay.roughness = 0.95
	_clay.metallic_specular = 0.14

	# Pure black against a bright plate: a silhouette test only answers whether
	# the outline alone is recognisable.
	_silhouette = StandardMaterial3D.new()
	_silhouette.albedo_color = Color(0.05, 0.05, 0.06)
	_silhouette.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	add_child(_camera)


## One large soft key, a moderate neutral fill, compact contact shadows, warm
## neutral background. No fog, no bloom, no outline.
func _studio(background: Color) -> void:
	var existing := get_node_or_null("Studio")
	if existing != null:
		existing.free()
	var holder := Node3D.new()
	holder.name = "Studio"
	add_child(holder)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = background
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.855, 0.84)
	environment.ambient_light_energy = 0.9
	environment.ssao_enabled = true
	environment.ssao_radius = 0.16
	environment.ssao_intensity = 1.15
	environment.ssao_power = 2.2
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 3.0
	var world := WorldEnvironment.new()
	world.environment = environment
	holder.add_child(world)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.05
	key.light_color = Color(1.0, 0.975, 0.93)
	key.shadow_enabled = true
	key.shadow_blur = 2.2
	key.rotation_degrees = Vector3(-46.0, 132.0, 0.0)
	holder.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.40
	fill.light_color = Color(0.87, 0.91, 0.98)
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-22.0, -48.0, 0.0)
	holder.add_child(fill)


func _clear_stage() -> void:
	if _stage != null and is_instance_valid(_stage):
		_stage.free()
	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)


func _module(id: String) -> Node3D:
	for entry: Dictionary in _report.get("modules", []):
		if String(entry.get("id", "")) != id:
			continue
		var scene: PackedScene = load(String(entry["path"]))
		if scene != null:
			return scene.instantiate() as Node3D
	return null


func _paint(root: Node3D, material: Material) -> void:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).material_override = material


func _plate(colour: Color, size := 4.0) -> void:
	var plate := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size, 0.04, size)
	plate.mesh = mesh
	plate.position.y = -0.02
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	plate.material_override = material
	_stage.add_child(plate)


func _frame(centre: Vector3, extent: float, pitch := -32.0, yaw := 42.0) -> void:
	_camera.size = extent
	var direction := Vector3(0.0, 0.0, 1.0) \
		.rotated(Vector3.RIGHT, deg_to_rad(pitch)) \
		.rotated(Vector3.UP, deg_to_rad(yaw))
	_camera.position = centre + direction * 6.0
	_camera.look_at(centre, Vector3.UP)


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var absolute := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute)
	get_viewport().get_texture().get_image().save_png(absolute.path_join(filename))


func _clump_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for entry: Dictionary in _report.get("modules", []):
		if String(entry.get("kind", "")) == "clump":
			result.append(String(entry["id"]))
	return result


func _shape_passes() -> void:
	# 1. One broad leaf close-up in clay. The question this answers: does the
	# leaf widen, arc, and taper — or is it still a tube with a flat top?
	_studio(Color(0.886, 0.867, 0.796))
	_clear_stage()
	_plate(Color(0.80, 0.78, 0.73), 0.60)
	var leaf := _module("grass_leaf_reference")
	if leaf != null:
		_paint(leaf, _clay)
		_stage.add_child(leaf)
	_frame(Vector3(0.0, 0.025, -0.085), 0.26, -26.0, 38.0)
	await _shoot("1_leaf_clay.png")

	# Same leaf from directly along its length, where a flat top would be
	# unmissable.
	_frame(Vector3(0.0, 0.028, -0.085), 0.22, -5.0, 90.0)
	await _shoot("1b_leaf_profile.png")

	var ids := _clump_ids()

	# 2. The six clump silhouettes in black. A clump that is not recognisable
	# here is not a clump, whatever it looks like shaded.
	_studio(Color(0.96, 0.95, 0.92))
	_clear_stage()
	for index in ids.size():
		var clump := _module(ids[index])
		if clump == null:
			continue
		_paint(clump, _silhouette)
		clump.position = Vector3((float(index) - 2.5) * 0.55, 0.0, 0.0)
		_stage.add_child(clump)
	_frame(Vector3(0.0, 0.055, 0.0), 2.6, -3.0, 0.0)
	await _shoot("2_clump_silhouettes.png")

	# 3. The same six in clay at the studio angle, so proportion and leaf
	# overlap can be read as a set.
	_studio(Color(0.886, 0.867, 0.796))
	_clear_stage()
	_plate(Color(0.80, 0.78, 0.73), 2.6)
	for index in ids.size():
		var clump := _module(ids[index])
		if clump == null:
			continue
		_paint(clump, _clay)
		var column := index % 3
		var row := index / 3
		clump.position = Vector3(
			(float(column) - 1.0) * 0.62, 0.0, (float(row) - 0.5) * 0.62
		)
		_stage.add_child(clump)
	_frame(Vector3(0.0, 0.04, 0.0), 1.55, -32.0, 40.0)
	await _shoot("3_clumps_clay.png")
