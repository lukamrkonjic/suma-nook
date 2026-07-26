extends Node3D
## Garden Galaxy Match Lab — the visual acceptance test for the whole pipeline.
## One of each core surface/prop under the shared lighting rig, captured from a
## fixed camera into a SubViewport at an exact native resolution, with a JSON
## manifest of screen-space sample points for tools/compare_reference_render.py.
##
## Headless-ish capture (opens a window briefly, saves, quits):
##   /Applications/Godot.app/Contents/MacOS/Godot --path . scenes/debug/GardenGalaxyMatchLab.tscn \
##       -- --shot=docs/visual_match/captures/day --profile=day
##
## Writes <base>.png (scene), <base>_post.png (scene + 1-tile shadow test post),
## and <base>.json (manifest). Profiles: day | mist | rain.

const TILE := 2.0
const CAPTURE_SIZE := Vector2i(1920, 1080)
const CAMERA_ORTHO_SIZE := 10.55
const CAMERA_YAW := 45.0
const CAMERA_PITCH := -34.0
const PIVOT := Vector3(4.0, 0.0, 2.0)
const POST_BASE := Vector3(2.0, 0.0, 4.0)

const TILES := [
	["tile_grass", Vector2(0, 0)],
	["tile_grass_flower", Vector2(2, 0)],
	["tile_path", Vector2(4, 0)],
	["tile_grass", Vector2(6, 0)],
	["tile_grass", Vector2(0, 2)],
	["tile_grass", Vector2(2, 2)],
	["tile_path", Vector2(4, 2)],
	["tile_grass_pond_edge", Vector2(6, 2)],
	["tile_grass", Vector2(0, 4)],
	["tile_grass", Vector2(2, 4)],
	["tile_stone_clearing", Vector2(4, 4)],
	["tile_grass", Vector2(6, 4)],
]

const PROPS := [
	["prop_pine_a", Vector3(-0.45, 0, -0.45), 0.0],
	["prop_campfire", Vector3(6, 0, 0), 0.0],
	["prop_bush_a", Vector3(0, 0, 2), 0.0],
	["prop_pot", Vector3(5.55, 0, 3.5), 0.0],
	["prop_bench", Vector3(4, 0, 2.25), 180.0],
	["prop_lantern", Vector3(4.75, 0, 0.7), 0.0],
	["prop_cardboard_box", Vector3(3.55, 0, 0.3), 0.6],
	["prop_flowers_pink", Vector3(6.6, 0, 4.4), 0.0],
	["calib_sphere", Vector3(-0.35, 0, 4.35), 0.0],
	["calib_cube", Vector3(0.55, 0, 4.55), 0.4],
	["character_proxy", Vector3(2.75, 0.02, 2.75), -135.0],
]

## World-space points whose rendered screen color the compare script samples.
const MARKERS := {
	"grass_lit": Vector3(2.7, 0.035, 3.3),
	"grass_lit_b": Vector3(6.6, 0.035, 4.7),
	"stone_lit": Vector3(3.45, 0.075, 1.35),
	"stone_clearing": Vector3(3.6, 0.035, 4.6),
	"soil_side": Vector3(0.4, -0.35, 5.02),
	"wood": Vector3(4.15, 0.335, 2.3),
	"water": Vector3(6.1, -0.19, 2.1),
	"water_open": Vector3(8.2, -0.075, 2.2),
	"pine": Vector3(-0.2, 1.05, -0.2),
	"bush": Vector3(0.28, 0.42, 2.28),
	"terracotta": Vector3(5.68, 0.17, 3.66),
	"charcoal": Vector3(4.86, 1.18, 0.81),
	"cardboard": Vector3(3.84, 0.22, 0.32),
	"calib_sphere_top": Vector3(-0.35, 0.83, 4.36),
	"calib_cube_top": Vector3(0.55, 0.705, 4.55),
	"contact_shadow": Vector3(5.58, 0.035, 3.74),
	"contact_center": Vector3(5.55, 0.02, 3.5),
}

var _materials: MaterialLibrary
var _assets: AssetLibrary
var _lighting: LightingRig
var _viewport: SubViewport
var _camera: Camera3D
var _post: MeshInstance3D


func _ready() -> void:
	var palette: CozyPalette = load("res://assets/palettes/gg_material_palette.tres")
	_materials = MaterialLibrary.new(palette)
	_assets = AssetLibrary.new(_materials)

	_lighting = (load("res://scenes/visual/GGDayLightingRig.tscn") as PackedScene).instantiate()
	add_child(_lighting)

	for entry in TILES:
		var node := _assets.instantiate(entry[0])
		node.position = Vector3(entry[1].x, 0, entry[1].y)
		add_child(node)
	add_child(_open_water_tile(Vector3(8, 0, 2)))

	for entry in PROPS:
		var node := _assets.instantiate(entry[0])
		node.position = entry[1]
		node.rotation_degrees.y = entry[2]
		add_child(node)

	_post = _build_test_post()
	_post.visible = false
	add_child(_post)

	_viewport = SubViewport.new()
	_viewport.size = CAPTURE_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.use_debanding = true
	add_child(_viewport)
	var cam_basis := Basis.from_euler(Vector3(deg_to_rad(CAMERA_PITCH), deg_to_rad(CAMERA_YAW), 0.0))
	var cam_transform := Transform3D(cam_basis, PIVOT + cam_basis.z * 40.0)

	# The directional shadow fit follows the ROOT viewport's current camera —
	# without one it collapses around the world origin and most casters drop
	# out of the map. Keep a twin camera in the root viewport purely to drive
	# the shadow fit; the SubViewport camera renders the actual capture.
	# Tight near/far is load-bearing too: a 0.05..4000 range dilutes the
	# shadow map until shadows disappear.
	var fit_camera := Camera3D.new()
	fit_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	fit_camera.size = CAMERA_ORTHO_SIZE
	fit_camera.near = 25.0
	fit_camera.far = 58.0
	fit_camera.transform = cam_transform
	add_child(fit_camera)
	fit_camera.current = true

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_ORTHO_SIZE
	_camera.near = 25.0
	_camera.far = 58.0
	_camera.transform = cam_transform
	_viewport.add_child(_camera)
	_camera.current = true

	var profile_name := "day"
	var shot_base := ""
	var probe := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_base = arg.trim_prefix("--shot=")
		elif arg.begins_with("--profile="):
			profile_name = arg.trim_prefix("--profile=")
		elif arg == "--probe":
			probe = true

	var profile := _profile_for(profile_name)
	_lighting.apply_profile(profile)
	if profile.background_gradient and not probe:
		_add_gradient_backdrop(profile)

	if probe:
		# Transfer-curve probe: unshaded swatches through the full 3D tonemap
		# chain, plus a loud env background to reveal whether BG_CANVAS shows.
		var env := (_lighting.get_node("Atmosphere") as WorldEnvironment).environment
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(1.0, 0.0, 1.0)
		_spawn_probe_swatches()

	if shot_base != "":
		if probe:
			_capture_probe(shot_base)
		else:
			_capture(shot_base, profile_name)


const PROBE_COLORS_VALIDATION := [
	Color(0.9137, 0.8863, 0.8118),  # day cream target
	Color(0.7059, 0.7765, 0.7725),  # mist top
	Color(0.7333, 0.8157, 0.7922),  # mist bottom
	Color(0.8, 0.7569, 0.1412),     # grass target family
	Color(0.7922, 0.4392, 0.1765),  # terracotta
	Color(0.4902, 0.5725, 0.5216),  # water
	Color(0.5882, 0.3569, 0.0863),  # soil
]

var _probe_entries := []  # [value_or_color, world_pos]


func _spawn_probe_swatches() -> void:
	var cam_basis := Basis.from_euler(Vector3(deg_to_rad(CAMERA_PITCH), deg_to_rad(CAMERA_YAW), 0.0))
	# Swatch wall on the camera axis, in front of the diorama and safely
	# inside the tight near/far range (near is 25 — 20 m would be clipped).
	var origin := PIVOT + cam_basis.z * 8.0
	var count := 0
	for i in 33:
		var v := i / 32.0
		_probe_entries.append([Color(v, v, v), count])
		count += 1
	for c in PROBE_COLORS_VALIDATION:
		_probe_entries.append([c, count])
		count += 1
	for entry in _probe_entries:
		var idx: int = entry[1]
		var col := idx % 8
		var row := idx / 8
		var local := cam_basis.x * ((col - 3.5) * 1.0) + cam_basis.y * ((2.0 - row) * 1.0)
		var quad := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.86, 0.86, 0.02)
		quad.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = entry[0]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		quad.material_override = mat
		quad.basis = cam_basis
		quad.position = origin + local
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(quad)
		entry.append(quad.position)


func _capture_probe(base_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_path).get_base_dir())
	await _settle(20)
	_save_view(base_path + "_probe.png")
	var swatches := []
	for entry in _probe_entries:
		var color: Color = entry[0]
		var px := _camera.unproject_position(entry[2])
		swatches.append({"input": [color.r, color.g, color.b], "px": [px.x, px.y]})
	var file := FileAccess.open(base_path + "_probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"swatches": swatches}, "  "))
	file.close()
	print("PROBE SAVED: " + base_path)
	get_tree().quit()


func _profile_for(name: String) -> VisualStyleProfile:
	match name:
		"mist":
			return load("res://assets/visual_profiles/garden_galaxy_mist.tres")
		"rain":
			return load("res://assets/visual_profiles/garden_rain.tres")
		"a":
			return load("res://assets/visual_profiles/garden_galaxy_candidate_a.tres")
		"c":
			return load("res://assets/visual_profiles/garden_galaxy_candidate_c.tres")
		_:
			return load("res://assets/visual_profiles/gg_day_profile.tres")


## The rig's gradient backdrop lives in the window viewport; the capture
## SubViewport needs its own copy for BG_CANVAS to show anything.
func _add_gradient_backdrop(profile: VisualStyleProfile) -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	_viewport.add_child(layer)
	var rect := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/materials/mist_background.gdshader")
	mat.set_shader_parameter("top_color", profile.gradient_top)
	mat.set_shader_parameter("mid_color", profile.gradient_mid)
	mat.set_shader_parameter("bottom_color", profile.gradient_bottom)
	mat.set_shader_parameter("stars_amount", 1.0 if profile.stars_enabled else 0.0)
	rect.material = mat
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)


func _open_water_tile(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "open_water"
	root.position = pos
	var bed := MeshInstance3D.new()
	var bed_mesh := BoxMesh.new()
	bed_mesh.size = Vector3(TILE, 0.54, TILE)
	bed.mesh = bed_mesh
	bed.position.y = -0.35
	bed.material_override = _materials.material("water_deep")
	root.add_child(bed)
	var surface := MeshInstance3D.new()
	var water_mesh := BoxMesh.new()
	water_mesh.size = Vector3(TILE + 0.012, 0.12, TILE + 0.012)
	surface.mesh = water_mesh
	surface.position.y = -0.14
	surface.material_override = _materials.material("water")
	root.add_child(surface)
	return root


## Upright post exactly one tile tall, unshaded magenta so the compare script
## can mask its silhouette and isolate the cast shadow it adds.
func _build_test_post() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.22, TILE, 0.22)
	mesh_instance.mesh = mesh
	mesh_instance.position = POST_BASE + Vector3(0, TILE / 2.0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.0, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mesh_instance


func _capture(base_path: String, profile_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_path).get_base_dir())
	await _settle(30)
	_save_view(base_path + ".png")
	_write_manifest(base_path + ".json", profile_name)
	_post.visible = true
	await _settle(8)
	_save_view(base_path + "_post.png")
	print("CAPTURE COMPLETE: " + base_path)
	get_tree().quit()


func _settle(frames: int) -> void:
	for i in frames:
		await RenderingServer.frame_post_draw


func _save_view(path: String) -> void:
	var image := _viewport.get_texture().get_image()
	image.save_png(path)
	print("SHOT SAVED: " + path)


func _write_manifest(path: String, profile_name: String) -> void:
	var markers := {}
	for marker_name: String in MARKERS:
		var px := _camera.unproject_position(MARKERS[marker_name])
		markers[marker_name] = [px.x, px.y]

	# Screen px per world meter, measured along the camera's ground-plane right.
	var right := Vector3(cos(deg_to_rad(CAMERA_YAW)), 0, -sin(deg_to_rad(CAMERA_YAW)))
	var origin_px := _camera.unproject_position(PIVOT)
	var meter_px := _camera.unproject_position(PIVOT + right).distance_to(origin_px)

	# Expected screen-space shadow direction from the sun's horizontal travel.
	var sun := _lighting.get_node("Sun") as DirectionalLight3D
	var light_dir := -sun.global_transform.basis.z
	var horizontal := Vector3(light_dir.x, 0, light_dir.z).normalized()
	var base_px := _camera.unproject_position(POST_BASE)
	var tip_px := _camera.unproject_position(POST_BASE + horizontal)
	var shadow_dir := (tip_px - base_px).normalized()

	var corners := []
	for x in [-1.0, 9.0]:
		for z in [-1.0, 5.0]:
			for y in [-0.62, 0.0]:
				var c := _camera.unproject_position(Vector3(x, y, z))
				corners.append([c.x, c.y])

	var manifest := {
		"size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"profile": profile_name,
		"camera": {"ortho_size": CAMERA_ORTHO_SIZE, "yaw": CAMERA_YAW, "pitch": CAMERA_PITCH},
		"px_per_meter": meter_px,
		"tile_px": meter_px * TILE,
		"markers": markers,
		"post": {
			"base_world": [POST_BASE.x, POST_BASE.y, POST_BASE.z],
			"base_px": [base_px.x, base_px.y],
			"top_px": [_camera.unproject_position(POST_BASE + Vector3(0, TILE, 0)).x, _camera.unproject_position(POST_BASE + Vector3(0, TILE, 0)).y],
			"expected_shadow_dir": [shadow_dir.x, shadow_dir.y],
			"height_m": TILE,
		},
		"sun": {"pitch": sun.rotation_degrees.x, "yaw": sun.rotation_degrees.y},
		"world_corners": corners,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  "))
	file.close()
	print("MANIFEST SAVED: " + path)
