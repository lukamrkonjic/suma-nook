extends Node3D
## Acceptance-gate captures for Tile Art V2 — premium correction pass.
##
## Root-viewport rendering, ortho diorama camera (yaw 45°, pitch −35.264°),
## measured width calibration, hdr_2d-safe capture. Lighting is deliberately
## calmer than the game's golden-hour grade: one broad soft warm key,
## restrained ambient, no bloom, warm mid background that never bleeds into
## the models.
##
##   01  contact sheet          02  128 px thumbnails (+ strip)
##   03  grey silhouettes       04  grayscale value study
##   05  per-tile hero isos     06  mixed 3×3 adjacency
##   07  three variants each    08  before/after vs the V1 equivalents
##   09  top-surface close-ups  10  four-corner close-ups (rotated row)
##   11  side-wall study        12  wireframe close-ups
##   13  normal visualisation
##
##   godot --path . tools/tile_kit/v2/review/tile_v2_review.tscn -- --shot-dir=<abs>

const TILE := 1.70
const Validate := preload("res://tools/tile_kit/v2/tile_v2_validate.gd")

var _output_dir := "user://tile_v2_review"
var _camera: Camera3D
var _stage: Node3D
var _key_light: DirectionalLight3D
var _environment: Environment
var _render_viewport: Viewport

const OLD_EQUIVALENTS := {
	"tile_v2_forest_floor": "tile_proc_mulch_dirt_floor",
	"tile_v2_sculpted_sand": "tile_proc_sandy_ground",
	"tile_v2_pillowy_snow": "tile_proc_snow_field",
	"tile_v2_rock_ground": "tile_proc_cobblestone_paving",
	"tile_v2_moss_cushion": "tile_proc_mossy_forest_floor",
}

const NORMAL_DEBUG_SHADER := "
shader_type spatial;
render_mode unshaded, cull_back;
void fragment() {
	vec3 world_normal = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
	ALBEDO = world_normal * 0.5 + 0.5;
}
"


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	_render_viewport = get_viewport()
	_build_rig()
	await get_tree().process_frame
	await _run()
	print("TILE V2 REVIEW CAPTURED — %s" % ProjectSettings.globalize_path(_output_dir))
	get_tree().quit()


func _build_rig() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	add_child(_camera)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	# Warm off-white presentation ground, per the acceptance framing.
	environment.background_color = TileV2Palette.DESIGN_SYSTEM.render_target(
		"plain_ground_gg")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.86, 0.88, 0.90)
	environment.ambient_light_energy = 0.55
	environment.ambient_light_sky_contribution = 0.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.10
	environment.glow_enabled = false
	environment.ssao_enabled = true
	environment.ssao_intensity = 1.15
	environment.ssao_radius = 0.26
	environment.ssao_power = 1.3
	var world := WorldEnvironment.new()
	world.environment = environment
	_environment = environment
	add_child(world)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.15
	key.light_color = Color(1.0, 0.945, 0.85)
	key.shadow_enabled = true
	key.shadow_blur = 1.8
	key.directional_shadow_max_distance = 24.0
	key.rotation_degrees = Vector3(-42.0, -34.0, 0.0)
	_key_light = key
	add_child(key)

	_stage = Node3D.new()
	add_child(_stage)


func _clear() -> void:
	for child in _stage.get_children():
		child.free()


func _add_ground(y := -0.50) -> void:
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(80.0, 80.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = TileV2Palette.DESIGN_SYSTEM.render_target(
		"plain_ground_gg")
	material.roughness = 1.0
	mesh.material = material
	plane.mesh = mesh
	plane.position = Vector3(0.0, y, 0.0)
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(plane)


func _frame(extent: float, target := Vector3.ZERO, pitch := -35.264) -> void:
	_camera.size = extent
	var direction := Vector3(0.0, 0.0, 1.0) \
		.rotated(Vector3.RIGHT, deg_to_rad(pitch)) \
		.rotated(Vector3.UP, deg_to_rad(45.0))
	_camera.position = target + direction * 14.0
	_camera.look_at(target, Vector3.UP)


func _calibrate_width(extent: float) -> void:
	await get_tree().create_timer(0.35).timeout
	for round in 3:
		await get_tree().process_frame
		var origin := _camera.unproject_position(Vector3.ZERO)
		var step := _camera.unproject_position(Vector3(1.0, 0.0, -1.0).normalized())
		var pixels_per_unit := (step - origin).length()
		if pixels_per_unit <= 0.001:
			return
		var width := _render_viewport.get_visible_rect().size.x
		var correction := (pixels_per_unit * extent) / width
		_camera.size *= correction
		if absf(correction - 1.0) < 0.005:
			break


func _capture() -> Image:
	await get_tree().process_frame
	await get_tree().create_timer(0.12).timeout
	await RenderingServer.frame_post_draw
	var image := _render_viewport.get_texture().get_image()
	if _render_viewport.use_hdr_2d:
		image.convert(Image.FORMAT_RGBA8)
		image.linear_to_srgb()
	return image


func _shoot(file_name: String) -> void:
	var image: Image = await _capture()
	var absolute := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(absolute)
	image.save_png(absolute.path_join(file_name))
	print("shot %s" % file_name)


func _spawn(tile_id: String, at: Vector3, seed_value := 0, layout := 0,
		yaw := 0.0) -> TileV2Generator:
	var generator := TileV2Generator.new()
	var recipe := TileV2Library.recipe(tile_id)
	if seed_value != 0:
		recipe.seed = seed_value
	recipe.layout = layout
	generator.recipe = recipe
	generator.position = at
	generator.rotation.y = yaw
	_stage.add_child(generator)
	return generator


func _set_override(mode: String) -> void:
	match mode:
		"silhouette":
			var grey := StandardMaterial3D.new()
			grey.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			grey.albedo_color = Color(0.30, 0.29, 0.28)
			TileV2Palette.set_override_material(grey)
		"value":
			var white := StandardMaterial3D.new()
			white.albedo_color = Color(0.85, 0.85, 0.85)
			white.roughness = 1.0
			white.metallic_specular = 0.1
			TileV2Palette.set_override_material(white)
		"normals":
			var shader := Shader.new()
			shader.code = NORMAL_DEBUG_SHADER
			var debug := ShaderMaterial.new()
			debug.shader = shader
			TileV2Palette.set_override_material(debug)
		_:
			TileV2Palette.set_override_material(null)
	TileV2Generator.clear_cache()


## Adds unshaded dark line overlays for every surface of a generator's
## meshes — a wireframe that works identically in any build.
func _add_wireframe(generator: TileV2Generator) -> void:
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color(0.13, 0.11, 0.10)
	for child in generator.get_children():
		if child is not MeshInstance3D:
			continue
		var source: ArrayMesh = (child as MeshInstance3D).mesh
		if source == null:
			continue
		var lines := ArrayMesh.new()
		for surface in source.get_surface_count():
			var arrays := source.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var seen: Dictionary = {}
			var line_vertices := PackedVector3Array()
			for triangle in indices.size() / 3:
				for edge in 3:
					var a := indices[triangle * 3 + edge]
					var b := indices[triangle * 3 + (edge + 1) % 3]
					var key := "%d:%d" % [mini(a, b), maxi(a, b)]
					if seen.has(key):
						continue
					seen[key] = true
					line_vertices.append(vertices[a])
					line_vertices.append(vertices[b])
			var line_arrays := []
			line_arrays.resize(Mesh.ARRAY_MAX)
			line_arrays[Mesh.ARRAY_VERTEX] = line_vertices
			var index := lines.get_surface_count()
			lines.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)
			lines.surface_set_material(index, line_material)
		var overlay := MeshInstance3D.new()
		overlay.mesh = lines
		overlay.position = Vector3(0.0, 0.0006, 0.0)
		child.add_child(overlay)


func _run() -> void:
	var ids := TileV2Library.prototype_ids()

	# 01 — contact sheet.
	_clear()
	_add_ground()
	for index in ids.size():
		_spawn(ids[index], Vector3(
			(index % 3) * 2.35 - 2.35, 0.0, (index / 3) * 2.5 - 1.2))
	_frame(8.6, Vector3(0.0, -0.25, 0.0))
	await _calibrate_width(8.6)
	await _shoot("01_contact_sheet.png")

	# Stats + validation for the report.
	for tile_id in ids:
		_clear()
		var generator := _spawn(tile_id, Vector3.ZERO)
		await get_tree().process_frame
		print("stats %s: %s" % [tile_id, JSON.stringify(generator.statistics())])
		var built := TileV2Generator.build_meshes(TileV2Library.recipe(tile_id))
		var issues: PackedStringArray = Validate.validate(
			built["surface"], tile_id + ":surface")
		issues.append_array(Validate.validate(built["base"], tile_id + ":base"))
		if issues.is_empty():
			print("validate %s: clean" % tile_id)
		else:
			for issue in issues:
				print("validate ISSUE %s" % issue)

	# 02 — inventory thumbnails at 128 px.
	var thumbs: Array[Image] = []
	for tile_id in ids:
		_clear()
		_add_ground()
		_spawn(tile_id, Vector3.ZERO)
		_frame(2.6, Vector3(0.0, -0.18, 0.0))
		await _calibrate_width(2.7)
		var image: Image = await _capture()
		var size := image.get_size()
		var side := mini(size.x, size.y)
		var square := image.get_region(Rect2i(
			(size.x - side) / 2, (size.y - side) / 2, side, side))
		square.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		thumbs.append(square)
		var absolute := ProjectSettings.globalize_path(_output_dir)
		DirAccess.make_dir_recursive_absolute(absolute)
		square.save_png(absolute.path_join("02_thumb_%s.png" % tile_id))
	var strip := Image.create(5 * 136 + 8, 144, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.97, 0.95, 0.91))
	for index in thumbs.size():
		strip.blit_rect(thumbs[index], Rect2i(0, 0, 128, 128),
			Vector2i(8 + index * 136, 8))
	strip.save_png(ProjectSettings.globalize_path(_output_dir)
		.path_join("02_thumbnail_strip.png"))
	print("shot 02_thumbnail_strip.png")

	# 03 — grey silhouettes (unshaded).
	_set_override("silhouette")
	_clear()
	for index in ids.size():
		_spawn(ids[index], Vector3(
			(index % 3) * 2.35 - 2.35, 0.0, (index / 3) * 2.5 - 1.2))
	_frame(8.6, Vector3(0.0, -0.25, 0.0))
	await _shoot("03_silhouettes.png")

	# 04 — grayscale value study.
	_set_override("value")
	_clear()
	_add_ground()
	for index in ids.size():
		_spawn(ids[index], Vector3(
			(index % 3) * 2.35 - 2.35, 0.0, (index / 3) * 2.5 - 1.2))
	_frame(8.6, Vector3(0.0, -0.25, 0.0))
	await _shoot("04_value_study.png")
	_set_override("")

	# 05 — per-tile hero iso shots.
	for tile_id in ids:
		_clear()
		_add_ground()
		_spawn(tile_id, Vector3.ZERO)
		_frame(2.9, Vector3(0.0, -0.2, 0.0))
		await _calibrate_width(3.0)
		await _shoot("05_iso_%s.png" % tile_id)

	# 06 — mixed 3×3 adjacency.
	_clear()
	_add_ground()
	var grid_ids := [
		ids[0], ids[1], ids[2],
		ids[3], ids[4], ids[0],
		ids[1], ids[2], ids[3],
	]
	for z in 3:
		for x in 3:
			_spawn(grid_ids[z * 3 + x],
				Vector3((x - 1) * TILE, 0.0, (z - 1) * TILE),
				20260803 + (z * 3 + x) * 977, (z * 3 + x) % 2)
	_frame(6.4, Vector3(0.0, -0.25, 0.0))
	await _calibrate_width(6.6)
	await _shoot("06_adjacency_3x3.png")

	# 07 — three deterministic variants per prototype.
	for tile_id in ids:
		_clear()
		_add_ground()
		var variants := [[20260803, 0], [20267741, 1], [20271303, 0]]
		for index in variants.size():
			_spawn(tile_id, Vector3((index - 1) * 2.3, 0.0, 0.0),
				variants[index][0], variants[index][1])
		_frame(7.4, Vector3(0.0, -0.2, 0.0))
		await _calibrate_width(7.5)
		await _shoot("07_variants_%s.png" % tile_id)

	# 08 — before/after: V1 equivalent (left) vs V2 (right).
	for tile_id in ids:
		_clear()
		_add_ground()
		var old_preset := TileKitPreset.official_recipe(
			String(OLD_EQUIVALENTS.get(tile_id, "")))
		if old_preset != null:
			var old := TileKitGenerator.new()
			old.preset = old_preset
			old.position = Vector3(-1.4, 0.0, 0.0)
			_stage.add_child(old)
		_spawn(tile_id, Vector3(1.4, 0.0, 0.0))
		_frame(4.9, Vector3(0.0, -0.2, 0.0))
		await _calibrate_width(5.0)
		await _shoot("08_before_after_%s.png" % tile_id)

	# 09 — top-surface close-ups.
	for tile_id in ids:
		_clear()
		_add_ground()
		_spawn(tile_id, Vector3.ZERO)
		_frame(1.7, Vector3(0.0, 0.02, 0.0), -48.0)
		await _shoot("09_top_%s.png" % tile_id)

	# 10 — all four corners: the same tile rotated 0/90/180/270 in a row,
	# each instance presenting a different corner to the camera.
	for tile_id in ids:
		_clear()
		_add_ground()
		for quarter in 4:
			_spawn(tile_id, Vector3((quarter - 1.5) * 2.05, 0.0, 0.0), 0, 0,
				quarter * PI * 0.5)
		_frame(8.6, Vector3(0.0, -0.15, 0.0))
		await _calibrate_width(8.7)
		await _shoot("10_corners_%s.png" % tile_id)

	# 11 — side-wall study: low grazing orbit across all five bodies.
	_clear()
	_add_ground()
	for index in ids.size():
		_spawn(ids[index], Vector3((index - 2.0) * 2.05, 0.0, 0.0))
	_frame(10.6, Vector3(0.0, -0.05, 0.0), -12.0)
	await _shoot("11_sidewalls.png")

	# 12 — wireframe close-ups over white clay.
	_set_override("value")
	for tile_id in ids:
		_clear()
		var generator := _spawn(tile_id, Vector3.ZERO)
		await get_tree().process_frame
		_add_wireframe(generator)
		_frame(2.4, Vector3(0.0, -0.1, 0.0))
		await _shoot("12_wireframe_%s.png" % tile_id)
	_set_override("")

	# 13 — normal visualisation.
	_set_override("normals")
	_clear()
	for index in ids.size():
		_spawn(ids[index], Vector3(
			(index % 3) * 2.35 - 2.35, 0.0, (index / 3) * 2.5 - 1.2))
	_frame(8.6, Vector3(0.0, -0.25, 0.0))
	await _shoot("13_normals.png")
	_set_override("")
