extends Node3D
## Validation renders for the continuous grass field.
##
## The question every view here answers is the same one: can you see the
## gameplay grid? The seam-debug pass is the important one — it renders the
## surface unlit with a wireframe overlay, so an internal seam shows up as
## geometry rather than being argued about from a shaded screenshot.
##
##   godot --path . tools/tile_forge/grass/field_review.tscn -- --shot-dir=<abs>

const CARPET_REPORT := "res://tools/tile_forge/modules/grass/carpet_report.json"
const REGION_CELLS := 5
const REGION_SEED := 771

var _output_dir := "user://tile_forge"
var _camera: Camera3D
var _stage: Node3D
var _environment: Environment
var _key: DirectionalLight3D
var _fill: DirectionalLight3D

var _region: GrassField.Region
var _modules: Dictionary = {}
var _surface_material: StandardMaterial3D
var _foliage_material: StandardMaterial3D
var _seam_material: StandardMaterial3D


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	_load_modules()
	_build_rig()
	var cells: Array = []
	for row in REGION_CELLS:
		for column in REGION_CELLS:
			cells.append(Vector2i(column - REGION_CELLS / 2, row - REGION_CELLS / 2))
	_region = GrassField.build_region(cells, REGION_SEED)
	await get_tree().process_frame
	await _run(cells)
	print("FIELD REVIEW CAPTURED — %s" % _output_dir)
	get_tree().quit()


func _load_modules() -> void:
	var file := FileAccess.open(CARPET_REPORT, FileAccess.READ)
	if file == null:
		push_error("no carpet report")
		return
	var report: Dictionary = JSON.parse_string(file.get_as_text())
	for entry: Dictionary in report.get("modules", []):
		_modules[String(entry["id"])] = String(entry["path"])


func _build_rig() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	add_child(_camera)

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	# Neutral warm beige, not the pale-yellow wash the earlier studio used —
	# that flattened every value relationship it was meant to reveal.
	_environment.background_color = Color(0.855, 0.839, 0.796)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.82, 0.835, 0.83)
	_environment.ambient_light_energy = 0.62
	_environment.ssao_enabled = true
	_environment.ssao_radius = 0.22
	_environment.ssao_intensity = 2.4
	_environment.ssao_power = 1.8
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.tonemap_white = 3.6
	var world := WorldEnvironment.new()
	world.environment = _environment
	add_child(world)

	_key = DirectionalLight3D.new()
	_key.light_energy = 1.25
	_key.light_color = Color(1.0, 0.98, 0.945)
	_key.shadow_enabled = true
	_key.shadow_blur = 1.6
	_key.rotation_degrees = Vector3(-48.0, 128.0, 0.0)
	add_child(_key)

	_fill = DirectionalLight3D.new()
	_fill.light_energy = 0.26
	_fill.light_color = Color(0.86, 0.90, 0.97)
	_fill.shadow_enabled = false
	_fill.rotation_degrees = Vector3(-24.0, -52.0, 0.0)
	add_child(_fill)

	# One shared terrain material that reads vertex colour. The broad tone lives
	# in the mesh, so there is no per-tile material and nothing to mismatch.
	_surface_material = StandardMaterial3D.new()
	_surface_material.vertex_color_use_as_albedo = true
	_surface_material.roughness = 0.97
	_surface_material.metallic_specular = 0.10

	# Foliage sits only a few percent off the ground it grows from.
	_foliage_material = StandardMaterial3D.new()
	_foliage_material.albedo_color = Color("#7FA34A")
	_foliage_material.roughness = 0.95
	_foliage_material.metallic_specular = 0.10

	_seam_material = StandardMaterial3D.new()
	_seam_material.albedo_color = Color(1.0, 0.0, 0.85)
	_seam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _clear() -> void:
	if _stage != null and is_instance_valid(_stage):
		_stage.free()
	_stage = Node3D.new()
	add_child(_stage)


func _add_surface(material: Material, cells: Array) -> void:
	# Chunked exactly as the runtime would be, so a chunk boundary is part of
	# what these renders test rather than something hidden by building one mesh.
	var chunks: Dictionary = {}
	for cell: Vector2i in cells:
		var key := Vector2i(
			floori(float(cell.x) / GrassField.CHUNK_CELLS),
			floori(float(cell.y) / GrassField.CHUNK_CELLS)
		)
		if not chunks.has(key):
			chunks[key] = []
		(chunks[key] as Array).append(cell)
	for key: Vector2i in chunks:
		var mesh := GrassField.build_surface(_region, chunks[key])
		if mesh == null:
			continue
		var node := MeshInstance3D.new()
		node.name = "SurfaceChunk_%d_%d" % [key.x, key.y]
		node.mesh = mesh
		node.material_override = material
		_stage.add_child(node)

	var skirt := GrassField.build_skirt(_region)
	if skirt != null:
		var node := MeshInstance3D.new()
		node.name = "ExposedEdgeSkirt"
		node.mesh = skirt
		node.material_override = material
		_stage.add_child(node)


## One MultiMesh per module per layer: the grouping the runtime will use, and
## the reason a dense field costs a handful of draw calls rather than hundreds.
func _add_foliage(layers: Array, material: Material) -> void:
	var by_module: Dictionary = {}
	var placements := GrassField.place_foliage(_region, REGION_SEED + 11)
	placements.append_array(GrassField.place_fringe(_region, REGION_SEED + 29))
	var pools := {
		GrassField.Layer.GROUND: ["ground_carpet_a", "ground_carpet_b", "ground_carpet_c"],
		GrassField.Layer.CARPET: ["medium_carpet_a", "medium_carpet_b", "medium_carpet_c"],
		# ~65% medium carpet, ~20% hero, ~15% small support.
		GrassField.Layer.MEDIUM: ["medium_carpet_a", "medium_carpet_b", "medium_carpet_c",
			"medium_carpet_a", "large_hero_carpet_a", "large_hero_carpet_b",
			"small_support_a", "small_support_b"],
		GrassField.Layer.ACCENT: ["large_hero_carpet_a", "large_hero_carpet_b"],
	}
	# Sink depth per layer, so nothing shows a flat base or a pad.
	var sink := {
		GrassField.Layer.GROUND: 0.40,
		GrassField.Layer.CARPET: 0.27,
		GrassField.Layer.MEDIUM: 0.20,
		GrassField.Layer.ACCENT: 0.15,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = REGION_SEED + 53

	for placement: Dictionary in placements:
		var layer: int = placement["layer"]
		if not layers.has(layer):
			continue
		var pool: Array = pools[layer]
		var id: String = pool[rng.randi() % pool.size()]
		if not by_module.has(id):
			by_module[id] = []
		(by_module[id] as Array).append({
			"transform": placement,
			"sink": sink[layer],
		})

	for id: String in by_module:
		var scene: PackedScene = load(_modules.get(id, ""))
		if scene == null:
			continue
		var probe := scene.instantiate()
		var source: Mesh = null
		for child in probe.find_children("*", "MeshInstance3D", true, false):
			source = (child as MeshInstance3D).mesh
			break
		probe.free()
		if source == null:
			continue
		var entries: Array = by_module[id]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = source
		multi.instance_count = entries.size()
		for index in entries.size():
			var entry: Dictionary = entries[index]
			var placement: Dictionary = entry["transform"]
			var scale_value: float = placement["scale"]
			var basis := Basis(Vector3.UP, placement["yaw"]).scaled(Vector3.ONE * scale_value)
			var origin: Vector3 = placement["position"]
			origin.y -= float(entry["sink"]) * source.get_aabb().size.y * scale_value
			multi.set_instance_transform(index, Transform3D(basis, origin))
		var node := MultiMeshInstance3D.new()
		node.name = "Foliage_%s" % id
		node.multimesh = multi
		node.material_override = material
		_stage.add_child(node)


func _frame(extent: float, pitch := -40.0, yaw := 45.0) -> void:
	_camera.size = extent
	var direction := Vector3(0.0, 0.0, 1.0) \
		.rotated(Vector3.RIGHT, deg_to_rad(pitch)) \
		.rotated(Vector3.UP, deg_to_rad(yaw))
	_camera.position = direction * 14.0
	_camera.look_at(Vector3.ZERO, Vector3.UP if absf(pitch) < 89.0 else Vector3.FORWARD)


func _shoot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var absolute := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute)
	get_viewport().get_texture().get_image().save_png(absolute.path_join(name))


func _run(cells: Array) -> void:
	var span := REGION_CELLS * GrassField.CELL * 1.30

	# 1. Bare connected surface — the broad sculpting with nothing on it.
	var plain := StandardMaterial3D.new()
	plain.albedo_color = Color("#6E8C40")
	plain.roughness = 0.97
	_clear(); _add_surface(plain, cells)
	_frame(span)
	await _shoot("1_surface_bare.png")

	# 2. The same surface with the broad world-space tone field.
	_clear(); _add_surface(_surface_material, cells)
	_frame(span)
	await _shoot("2_surface_toned.png")

	# 3. Seam debug: unlit magenta plus wireframe. If an internal cell boundary
	# exists as geometry, it is visible here and nowhere to hide.
	_clear(); _add_surface(_seam_material, cells)
	_frame(span * 0.55)
	RenderingServer.set_debug_generate_wireframes(true)
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	await _shoot("3_seam_debug.png")
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
	RenderingServer.set_debug_generate_wireframes(false)

	# 4. Ground-carpet layer only — the bridge between bare ground and tufts.
	_clear(); _add_surface(_surface_material, cells)
	_add_foliage([GrassField.Layer.GROUND], _foliage_material)
	_frame(span)
	await _shoot("4_ground_carpet_only.png")

	# 5. Every layer.
	_clear(); _add_surface(_surface_material, cells)
	_add_foliage([GrassField.Layer.GROUND, GrassField.Layer.CARPET,
		GrassField.Layer.MEDIUM, GrassField.Layer.ACCENT], _foliage_material)
	_frame(span)
	await _shoot("5_all_layers.png")

	# 6. Top-down, where a grid would be most obvious.
	_frame(span * 0.92, -89.9, 0.0)
	await _shoot("6_top_down.png")

	# 7. Gameplay camera.
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 15.0
	var distance := (span * 1.15) / (2.0 * tan(deg_to_rad(7.5)))
	var direction := Vector3(0.0, 0.0, 1.0) \
		.rotated(Vector3.RIGHT, deg_to_rad(-40.0)).rotated(Vector3.UP, deg_to_rad(45.0))
	_camera.position = direction * distance
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	await _shoot("7_gameplay.png")
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL

	# 8. Low angle across the exposed rim.
	_frame(span * 0.62, -13.0, 32.0)
	await _shoot("8_island_edge.png")
