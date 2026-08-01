@tool
extends Node3D
## Tile Forge laboratory — the visual QA surface for every generated tile.
##
## It builds recipes through the SAME TileForgeBuilder + TileBaker path that
## ships assets, so what is reviewed here is what gets baked. Nothing is
## generated per frame: rebuilds happen on an explicit action or on a debounced
## property change.
##
## In the editor: open this scene, pick a recipe, tick Rebuild.
## Headless / from the command line:
##
##   godot --path . tools/tile_forge/editor/tile_lab.tscn -- \
##       --shot-dir=<abs> --recipes=all --modes=single,seam3,repeat5,gameplay
##
## Preview modes are the review checklist made runnable: single tile, 3x3 seam,
## 5x5 repetition, mixed neighbours, four rotations, wireframe, normals,
## collision, layer isolation, and the real gameplay camera distance.

enum PreviewMode {
	SINGLE_TILE,
	SEAM_3X3,
	REPEAT_5X5,
	MIXED_NEIGHBOURS,
	ROTATION_TEST,
	WIREFRAME,
	NORMALS,
	COLLISION,
	LAYER_ISOLATION,
	GAMEPLAY_DISTANCE,
}

enum LayerFilter { ALL, BASE_ONLY, SURFACE_ONLY, DETAILS_ONLY, WATER_ONLY }

const RECIPE_DIR := "res://tools/tile_forge/recipes/golden"
const PALETTE_PATH := "res://assets/palettes/gg_material_palette.tres"
const DAYLIGHT_SCENE := "res://scenes/visual/SumaSoftDaylight.tscn"

@export_group("Recipe")
@export var recipe: TileRecipe:
	set(value):
		recipe = value
		_request_rebuild()
## Ticking this rebuilds now. It resets itself, so it reads as a button.
@export var rebuild := false:
	set(value):
		if value:
			_rebuild()
		rebuild = false
@export var randomize_seed := false:
	set(value):
		if value and recipe != null:
			recipe.seed_value = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
			_rebuild()
		randomize_seed = false
@export var next_seed := false:
	set(value):
		if value and recipe != null:
			recipe.variant += 1
			_rebuild()
		next_seed = false
@export var previous_seed := false:
	set(value):
		if value and recipe != null:
			recipe.variant = maxi(0, recipe.variant - 1)
			_rebuild()
		previous_seed = false
@export_range(1, 32, 1) var variant_set_size := 8
@export var generate_variant_set := false:
	set(value):
		if value:
			_generate_variant_set()
		generate_variant_set = false

@export_group("Preview")
@export var mode: PreviewMode = PreviewMode.SINGLE_TILE:
	set(value):
		mode = value
		_request_rebuild()
@export var layer_filter: LayerFilter = LayerFilter.ALL:
	set(value):
		layer_filter = value
		_apply_layer_filter()
@export var show_tile_bounds := false:
	set(value):
		show_tile_bounds = value
		_request_rebuild()
@export var show_edge_lock_region := false:
	set(value):
		show_edge_lock_region = value
		_request_rebuild()
@export var show_collision := false:
	set(value):
		show_collision = value
		_request_rebuild()
## Warm studio plate behind the tile. Off uses the game's own background.
@export var studio_backdrop := true:
	set(value):
		studio_backdrop = value
		_request_rebuild()

@export_group("Actions")
@export var validate_now := false:
	set(value):
		if value:
			_print_validation()
		validate_now = false
@export var bake_now := false:
	set(value):
		if value:
			_bake()
		bake_now = false
@export var bake_all_proof_recipes := false:
	set(value):
		if value:
			_bake_all()
		bake_all_proof_recipes = false

var _materials: MaterialLibrary
var _cozy: CozyPalette
var _content: Node3D
var _camera: Camera3D
var _debounce: SceneTreeTimer
var _shared_modules: Dictionary = {}
var _last_report: TileValidator.Report

var _output_dir := "user://tile_forge"
var _headless_recipes: PackedStringArray = []
var _headless_modes: PackedStringArray = []


func _ready() -> void:
	_cozy = load(PALETTE_PATH)
	_materials = MaterialLibrary.new(_cozy)
	if Engine.is_editor_hint():
		_rebuild()
		return
	_parse_arguments()
	await _run_headless()


func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
		elif argument.begins_with("--recipes="):
			_headless_recipes = argument.trim_prefix("--recipes=").split(",", false)
		elif argument.begins_with("--modes="):
			_headless_modes = argument.trim_prefix("--modes=").split(",", false)


# --- build -------------------------------------------------------------------


## Debounced so dragging a slider in the inspector cannot start a rebuild storm.
func _request_rebuild() -> void:
	if not is_inside_tree():
		return
	if _debounce != null and _debounce.time_left > 0.0:
		return
	_debounce = get_tree().create_timer(0.15)
	_debounce.timeout.connect(_rebuild, CONNECT_ONE_SHOT)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _materials == null:
		_cozy = load(PALETTE_PATH)
		_materials = MaterialLibrary.new(_cozy)
	_clear_content()
	_ensure_environment()
	if recipe == null:
		return
	match mode:
		PreviewMode.SINGLE_TILE, PreviewMode.WIREFRAME, PreviewMode.NORMALS, \
		PreviewMode.COLLISION, PreviewMode.LAYER_ISOLATION:
			_place(recipe, Vector3.ZERO, 0)
		PreviewMode.SEAM_3X3:
			_grid(recipe, 3)
		PreviewMode.REPEAT_5X5:
			_grid(recipe, 5)
		PreviewMode.GAMEPLAY_DISTANCE:
			_grid(recipe, 5)
		PreviewMode.MIXED_NEIGHBOURS:
			_mixed()
		PreviewMode.ROTATION_TEST:
			_rotations()
	_apply_debug_overlays()
	_apply_layer_filter()
	_frame_camera()


func _clear_content() -> void:
	if _content != null and is_instance_valid(_content):
		_content.free()
	_content = Node3D.new()
	_content.name = "Preview"
	add_child(_content)


func _ensure_environment() -> void:
	if get_node_or_null("Daylight") == null:
		var scene: PackedScene = load(DAYLIGHT_SCENE)
		if scene != null:
			var rig := scene.instantiate()
			rig.name = "Daylight"
			add_child(rig)
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_node_or_null("LabCamera") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "LabCamera"
		# The real gameplay lens, not a convenient one: a long 15-degree FOV is
		# what gives Suma its miniature read, and a tile judged through a wider
		# lens is judged wrong.
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = TileForgeConstants.CAMERA_FOV_DEG
		_camera.current = true
		add_child(_camera)
	if studio_backdrop:
		_add_backdrop()


## A warm plate under the tile. Judging a pale snow tile against a pale sky
## hides exactly the silhouette problems the lab exists to catch.
func _add_backdrop() -> void:
	var plate := MeshInstance3D.new()
	plate.name = "StudioPlate"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(30.0, 0.1, 30.0)
	plate.mesh = mesh
	plate.position.y = -TileForgeConstants.BLOCK_DEPTH - 0.05
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.86, 0.83, 0.72)
	material.roughness = 1.0
	plate.material_override = material
	_content.add_child(plate)


func _build(source: TileRecipe) -> TileBuildResult:
	return TileForgeBuilder.build(source, {}, true, _shared_modules)


func _place(source: TileRecipe, position: Vector3, rotation_quarters: int) -> Node3D:
	var result := _build(source)
	_last_report = TileValidator.validate(result)
	var node := TileBaker.assemble(result, _materials, _cozy)
	node.position = position
	node.rotation.y = float(rotation_quarters) * PI * 0.5
	_add_shared_base(node)
	_content.add_child(node)
	if show_collision or mode == PreviewMode.COLLISION:
		_add_collision_debug(node, result)
	return node


## The shared structural block, so the lab shows the complete tile the player
## sees rather than a floating top skin.
func _add_shared_base(node: Node3D) -> void:
	if recipe == null or recipe.base_profile == null:
		return
	var asset := recipe.base_profile.shared_base_asset()
	if asset == "":
		return
	var path := AssetLibrary.resolve_path(asset)
	if path == "":
		return
	var scene: PackedScene = load(path)
	if scene == null:
		return
	var base := scene.instantiate() as Node3D
	base.name = "StructuralBase"
	_materials.rebind_materials(base)
	for mesh_child in base.find_children("*", "MeshInstance3D", true, false):
		(mesh_child as MeshInstance3D).material_override = _materials.material(
			recipe.palette.key_for_slot(TileForgeConstants.SLOT_SIDE)
		)
	# The catalog base is authored at 1.70 m; the runtime scales only X/Z.
	var factor := recipe.tile_size / TileForgeConstants.AUTHORED_TILE_SIZE
	base.scale = Vector3(factor, 1.0, factor)
	node.add_child(base)
	node.move_child(base, 0)


func _grid(source: TileRecipe, size: int) -> void:
	var spacing := source.tile_size
	for row in size:
		for column in size:
			# Every copy is the SAME baked variant: a seam test must prove that
			# one asset repeats cleanly, not that eight different ones hide it.
			_place(
				source,
				Vector3(
					(float(column) - float(size - 1) * 0.5) * spacing,
					0.0,
					(float(row) - float(size - 1) * 0.5) * spacing
				),
				0
			)


func _rotations() -> void:
	var spacing := recipe.tile_size * 1.35
	for quarter in 4:
		_place(
			recipe,
			Vector3((float(quarter) - 1.5) * spacing, 0.0, 0.0),
			quarter
		)


## Every proof recipe placed next to its neighbours. Different surfaces meeting
## is the case that exposes an accidental colour seam or a height mismatch.
func _mixed() -> void:
	var recipes := _load_all_recipes()
	if recipes.is_empty():
		return
	var spacing := recipe.tile_size
	var columns := int(ceil(sqrt(float(recipes.size()))))
	for index in recipes.size():
		var column := index % columns
		var row := index / columns
		_place(
			recipes[index],
			Vector3(
				(float(column) - float(columns - 1) * 0.5) * spacing,
				0.0,
				(float(row) - float(columns - 1) * 0.5) * spacing
			),
			0
		)


func _load_all_recipes() -> Array[TileRecipe]:
	var result: Array[TileRecipe] = []
	var dir := DirAccess.open(RECIPE_DIR)
	if dir == null:
		return result
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var loaded: Variant = load(RECIPE_DIR.path_join(clean))
		if loaded is TileRecipe:
			result.append(loaded)
	return result


# --- overlays ----------------------------------------------------------------


func _apply_debug_overlays() -> void:
	if mode == PreviewMode.WIREFRAME:
		_set_wireframe(true)
	if mode == PreviewMode.NORMALS:
		_set_normal_debug()
	if show_tile_bounds:
		_add_bounds_frame(recipe.half_extent(), Color(1.0, 0.35, 0.2), 0.002)
	if show_edge_lock_region:
		var width := 0.24
		for layer in recipe.enabled_surface_layers():
			width = minf(width, layer.edge_lock_width)
		_add_bounds_frame(
			recipe.half_extent() * (1.0 - width),
			Color(0.2, 0.6, 1.0),
			0.0025
		)


func _set_wireframe(enabled: bool) -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.debug_draw = (
			Viewport.DEBUG_DRAW_WIREFRAME if enabled else Viewport.DEBUG_DRAW_DISABLED
		)
	RenderingServer.set_debug_generate_wireframes(enabled)


func _set_normal_debug() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = false
	# Normals as colour: the fastest way to see a flipped face or a smoothing
	# group that crosses an edge which should have stayed hard.
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	ALBEDO = normalize(NORMAL) * 0.5 + 0.5;
}
"""
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	for child in _content.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).material_override = shader_material


func _add_bounds_frame(extent: float, colour: Color, thickness: float) -> void:
	var frame := MeshInstance3D.new()
	frame.name = "BoundsFrame"
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [
		Vector3(-extent, 0.0, -extent), Vector3(extent, 0.0, -extent),
		Vector3(extent, 0.0, extent), Vector3(-extent, 0.0, extent),
	]
	for index in 4:
		var a: Vector3 = corners[index]
		var b: Vector3 = corners[(index + 1) % 4]
		var side := (b - a).normalized().cross(Vector3.UP) * thickness
		tool.add_vertex(a + side)
		tool.add_vertex(b + side)
		tool.add_vertex(b - side)
		tool.add_vertex(a + side)
		tool.add_vertex(b - side)
		tool.add_vertex(a - side)
	tool.generate_normals()
	frame.mesh = tool.commit()
	frame.position.y = 0.09
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frame.material_override = material
	_content.add_child(frame)


func _add_collision_debug(node: Node3D, result: TileBuildResult) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.9, 0.5, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for entry: Dictionary in result.collision:
		var shape: Variant = entry.get("shape")
		if not (shape is BoxShape3D):
			continue
		var display := MeshInstance3D.new()
		display.name = "CollisionDebug"
		var box := BoxMesh.new()
		box.size = (shape as BoxShape3D).size
		display.mesh = box
		display.transform = entry.get("transform", Transform3D.IDENTITY)
		display.material_override = material
		node.add_child(display)


func _apply_layer_filter() -> void:
	if _content == null or not is_instance_valid(_content):
		return
	for child in _content.find_children("*", "Node3D", true, false):
		var node := child as Node3D
		var name_lower := node.name.to_lower()
		var visible_now := true
		match layer_filter:
			LayerFilter.BASE_ONLY:
				visible_now = name_lower.begins_with("structuralbase")
			LayerFilter.SURFACE_ONLY:
				visible_now = not (
					name_lower.begins_with("detail")
					or name_lower.begins_with("water")
					or name_lower.begins_with("structuralbase")
				)
			LayerFilter.DETAILS_ONLY:
				visible_now = name_lower.begins_with("detail")
			LayerFilter.WATER_ONLY:
				visible_now = name_lower.begins_with("water")
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			node.visible = visible_now


# --- framing -----------------------------------------------------------------


func _frame_camera() -> void:
	if _camera == null:
		return
	var span := recipe.tile_size if recipe != null else TileForgeConstants.LIVE_TILE_SIZE
	match mode:
		PreviewMode.SINGLE_TILE, PreviewMode.WIREFRAME, PreviewMode.NORMALS, \
		PreviewMode.COLLISION, PreviewMode.LAYER_ISOLATION:
			_look_at_extent(span * 1.6)
		PreviewMode.SEAM_3X3:
			_look_at_extent(span * 4.0)
		PreviewMode.REPEAT_5X5:
			_look_at_extent(span * 6.4)
		PreviewMode.ROTATION_TEST:
			_look_at_extent(span * 6.6)
		PreviewMode.MIXED_NEIGHBOURS:
			_look_at_extent(span * 5.4)
		PreviewMode.GAMEPLAY_DISTANCE:
			# The real zoom the player uses, derived exactly as CameraRig does.
			_look_at_extent(TileForgeConstants.CAMERA_DEFAULT_SIZE * 0.28)


## Converts a desired visible extent into a camera distance for the game's
## narrow lens, then places the camera on the gameplay pitch and yaw.
func _look_at_extent(extent: float) -> void:
	var distance := extent / (2.0 * tan(deg_to_rad(TileForgeConstants.CAMERA_FOV_DEG * 0.5)))
	var pitch := deg_to_rad(TileForgeConstants.CAMERA_PITCH_DEG)
	var yaw := deg_to_rad(TileForgeConstants.CAMERA_YAW_DEG)
	var direction := Vector3(0.0, 0.0, 1.0).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
	_camera.position = direction * distance
	_camera.look_at(Vector3.ZERO, Vector3.UP)


# --- actions -----------------------------------------------------------------


func _print_validation() -> void:
	if recipe == null:
		return
	var result := _build(recipe)
	var report := TileValidator.validate(result)
	print("=== %s ===" % recipe.tile_id)
	print(report.text())
	print("triangles: %d  instances: %d  build: %d ms" % [
		result.triangle_count(), result.instances.size(), result.build_msec
	])


func _bake() -> void:
	if recipe == null:
		return
	var manifest := TileBaker.bake(
		recipe, TileForgeConstants.BAKED_DIR, _materials, _cozy, _shared_modules
	)
	print(manifest.summary_line())
	for error in manifest.errors:
		print("  ERROR %s" % error)


func _bake_all() -> void:
	for source in _load_all_recipes():
		var manifest := TileBaker.bake(
			source, TileForgeConstants.BAKED_DIR, _materials, _cozy, _shared_modules
		)
		print(manifest.summary_line())


func _generate_variant_set() -> void:
	if recipe == null:
		return
	var manifests := TileBaker.bake_variant_set(
		recipe, variant_set_size, TileForgeConstants.BAKED_DIR, _materials, _cozy
	)
	var passed := 0
	for manifest in manifests:
		if manifest.passed:
			passed += 1
		else:
			print("rejected variant %d: %s" % [manifest.variant, ", ".join(manifest.errors)])
	print("variant set: %d/%d accepted" % [passed, manifests.size()])


# --- headless capture --------------------------------------------------------


func _run_headless() -> void:
	var recipes := _load_all_recipes()
	if _headless_recipes.size() > 0 and _headless_recipes[0] != "all":
		var filtered: Array[TileRecipe] = []
		for candidate in recipes:
			if _headless_recipes.has(candidate.tile_id):
				filtered.append(candidate)
		recipes = filtered
	var modes := _headless_modes
	if modes.is_empty():
		modes = PackedStringArray(["single", "seam3", "repeat5", "gameplay"])

	var absolute := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute)

	for source in recipes:
		recipe = source
		for mode_name in modes:
			mode = _mode_from_name(mode_name)
			_rebuild()
			await get_tree().process_frame
			await get_tree().create_timer(0.25).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				absolute.path_join("%s_%s.png" % [source.tile_id, mode_name])
			)
		if _last_report != null:
			print("%s: %s" % [source.tile_id, _last_report.text().split("\n")[0]])
	print("TILE LAB CAPTURED — %s" % _output_dir)
	get_tree().quit()


func _mode_from_name(name: String) -> PreviewMode:
	match name:
		"single": return PreviewMode.SINGLE_TILE
		"seam3": return PreviewMode.SEAM_3X3
		"repeat5": return PreviewMode.REPEAT_5X5
		"mixed": return PreviewMode.MIXED_NEIGHBOURS
		"rotation": return PreviewMode.ROTATION_TEST
		"wireframe": return PreviewMode.WIREFRAME
		"normals": return PreviewMode.NORMALS
		"collision": return PreviewMode.COLLISION
		"isolation": return PreviewMode.LAYER_ISOLATION
		"gameplay": return PreviewMode.GAMEPLAY_DISTANCE
	return PreviewMode.SINGLE_TILE
