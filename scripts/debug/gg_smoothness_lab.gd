extends Node3D
## GG Smoothness Lab — validates silhouette quality, normals, anti-aliasing and
## shadow softness at the REAL gameplay camera distance (never close-up only).
##
##   godot --path . scenes/debug/GGSmoothnessLab.tscn -- --shot=docs/... [options]
##
## Options:
##   --aa=a|b        A: 8x MSAA, no TAA (default).  B: 4x MSAA + TAA.
##   --aa=c          8x MSAA + FXAA: validates post-composited water edges.
##   --wireframe     draw wireframe overlay
##   --normals       visualise shading normals as color
##   --flat          force flat shading (shows what the meshes would look like
##                   without authored smooth normals)
##   --no-shadows    disable the sun's shadows
##   --no-ao         disable SSAO
##   --zooms         also capture zoomed silhouette crops (tree/character/
##                   terrain edge/shadow edge)

const CAPTURE_SIZE := Vector2i(1920, 1080)
const CAMERA_YAW := 45.0
const CAMERA_PITCH := -34.0
const PIVOT := Vector3(3.6, 0, 2.2)
const ORTHO := 11.0

const ROSTER := [
	["tile_grass", Vector3(0, 0, 0), 0.0], ["tile_grass_flower", Vector3(2, 0, 0), 0.0],
	["tile_path", Vector3(4, 0, 0), 0.0], ["tile_grass", Vector3(0, 0, 2), 0.0],
	["tile_grass", Vector3(2, 0, 2), 0.0], ["tile_stone_clearing", Vector3(4, 0, 2), 0.0],
	["tile_grass", Vector3(0, 0, 4), 0.0], ["tile_grass", Vector3(2, 0, 4), 0.0],
	["tile_grass", Vector3(4, 0, 4), 0.0],
	["prop_pine_b", Vector3(0.1, 0, 0.1), 0.0],
	["prop_pine_a", Vector3(-0.55, 0, 1.5), 0.0],
	["prop_pine_young", Vector3(0.6, 0, 2.6), 0.0],
	["prop_bush_a", Vector3(2.1, 0, 1.4), 0.0],
	["prop_bush_b", Vector3(2.8, 0, 2.0), 0.0],
	["prop_flowers_pink", Vector3(1.3, 0, 3.3), 0.0],
	["prop_grass_tuft", Vector3(2.4, 0, 3.6), 0.0],
	["prop_rock_cluster", Vector3(4.3, 0, 3.4), 0.0],
	["prop_bench", Vector3(2.2, 0, 4.4), 20.0],
	["prop_chest", Vector3(3.5, 0, 4.5), -15.0],
	["prop_lantern", Vector3(4.5, 0, 0.6), 0.0],
	["prop_dock", Vector3(5.4, 0, 2.0), 90.0],
	["character_proxy", Vector3(1.15, 0.02, 1.1), -135.0],
	["calib_sphere", Vector3(-0.6, 0, 3.6), 0.0],
	["calib_cube", Vector3(-0.5, 0, 4.6), 0.0],
]
const WATER_CELLS := [Vector2i(6, 0), Vector2i(6, 2), Vector2i(6, 4), Vector2i(8, 2)]

## Zoomed silhouette crops: name -> [world focus, ortho size]
const ZOOMS := {
	"tree": [Vector3(0.1, 1.4, 0.1), 3.0],
	"character": [Vector3(1.15, 0.7, 1.1), 1.6],
	"terrain_edge": [Vector3(0.0, 0.0, 4.9), 2.2],
	"shadow_edge": [Vector3(3.0, 0.0, 1.4), 2.6],
	"water": [Vector3(6.6, -0.1, 2.2), 3.4],
}

var _materials: MaterialLibrary
var _assets: AssetLibrary
var _lighting: LightingRig
var _viewport: SubViewport
var _camera: Camera3D
var _fit_camera: Camera3D
var _post: MeshInstance3D
var _water_surface: WaterSurface
var _motion := false


func _ready() -> void:
	var palette: CozyPalette = load("res://assets/palettes/gg_material_palette.tres")
	_materials = MaterialLibrary.new(palette)
	_assets = AssetLibrary.new(_materials)
	_lighting = (load("res://scenes/visual/GGDayLightingRig.tscn") as PackedScene).instantiate()
	add_child(_lighting)

	for entry in ROSTER:
		var node := _assets.instantiate(entry[0])
		node.position = entry[1]
		node.rotation_degrees.y = entry[2]
		add_child(node)
	for cell in WATER_CELLS:
		var floor_node := _assets.instantiate("tile_water_floor")
		floor_node.position = Vector3(cell.x, 0, cell.y)
		add_child(floor_node)
	for entry in [["prop_uw_eelgrass_a", Vector3(5.5, -0.4, 0.5)],
			["prop_uw_rocks_b", Vector3(6.4, -0.42, 2.7)],
			["prop_lily_a", Vector3(5.8, -0.135, 3.6)]]:
		var node := _assets.instantiate(entry[0])
		node.position = entry[1]
		add_child(node)
	_water_surface = WaterSurface.new()
	add_child(_water_surface)
	_water_surface.rebuild(WATER_CELLS, func(c: Vector2i) -> Vector3: return Vector3(c.x, 0, c.y),
			2.0, -0.14, _materials.material("water"))

	# One-tile-tall shadow test post.
	_post = MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.2, 2.0, 0.2)
	_post.mesh = post_mesh
	_post.position = Vector3(3.0, 1.0, 1.4)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = _materials.palette.color("stone_light")
	_post.material_override = post_mat
	add_child(_post)

	var args := OS.get_cmdline_user_args()
	var shot_base := ""
	var aa := "a"
	var zooms := false
	for arg in args:
		if arg.begins_with("--shot="):
			shot_base = arg.trim_prefix("--shot=")
		elif arg.begins_with("--aa="):
			aa = arg.trim_prefix("--aa=")
		elif arg == "--zooms":
			zooms = true
		elif arg == "--motion":
			_motion = true

	_viewport = SubViewport.new()
	_viewport.size = CAPTURE_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.use_debanding = true
	if aa == "b":
		_viewport.msaa_3d = Viewport.MSAA_4X
		_viewport.use_taa = true
		_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	elif aa == "c":
		_viewport.msaa_3d = Viewport.MSAA_8X
		_viewport.use_taa = false
		_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	else:
		_viewport.msaa_3d = Viewport.MSAA_8X
		_viewport.use_taa = false
		_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.mesh_lod_threshold = 0.0
	add_child(_viewport)

	_fit_camera = _make_camera()
	add_child(_fit_camera)
	_fit_camera.current = true
	_camera = _make_camera()
	_viewport.add_child(_camera)
	_camera.current = true
	_frame(PIVOT, ORTHO)

	_apply_debug_toggles(args)
	if args.has("--no-water"):
		_water_surface.visible = false
	if shot_base != "":
		if _motion:
			_capture_motion(shot_base)
		else:
			_capture(shot_base, zooms)


## Movement + camera-rotation test. Slides the test post like a walking player
## and rotates the camera, saving a burst of frames. Ghosting/shimmer is then
## measured from the burst by tools/analyze_motion_burst.py.
func _capture_motion(base: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base).get_base_dir())
	await _settle(30)
	var yaw := CAMERA_YAW
	for i in 12:
		yaw += 3.0
		_post.position.x = 3.0 + i * 0.12
		var basis := Basis.from_euler(Vector3(deg_to_rad(CAMERA_PITCH), deg_to_rad(yaw), 0.0))
		var t := Transform3D(basis, PIVOT + basis.z * 40.0)
		for cam in [_camera, _fit_camera]:
			cam.transform = t
		await _settle(2)
		_save("%s_motion_%02d.png" % [base, i])
	print("SMOOTHNESS LAB COMPLETE")
	get_tree().quit()


func _apply_debug_toggles(args: PackedStringArray) -> void:
	if args.has("--wireframe"):
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
		_viewport.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
		RenderingServer.set_debug_generate_wireframes(true)
	if args.has("--normals"):
		_viewport.debug_draw = Viewport.DEBUG_DRAW_NORMAL_BUFFER
	if args.has("--no-shadows"):
		(_lighting.get_node("Sun") as DirectionalLight3D).shadow_enabled = false
	if args.has("--no-ao"):
		var env := (_lighting.get_node("Atmosphere") as WorldEnvironment).environment
		env.ssao_enabled = false
	if args.has("--flat"):
		# Shows what these meshes would look like WITHOUT authored smooth
		# normals — the comparison that proves the normals are doing work.
		for child in find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				continue
			var flat := StandardMaterial3D.new()
			flat.albedo_color = Color(0.72, 0.7, 0.66)
			mi.material_override = flat
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				arr[Mesh.ARRAY_NORMAL] = null
				arr[Mesh.ARRAY_TANGENT] = null


func _make_camera() -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 18.0
	cam.far = 62.0
	return cam


func _frame(pivot: Vector3, ortho_size: float) -> void:
	var basis := Basis.from_euler(Vector3(deg_to_rad(CAMERA_PITCH), deg_to_rad(CAMERA_YAW), 0.0))
	var t := Transform3D(basis, pivot + basis.z * 40.0)
	for cam in [_camera, _fit_camera]:
		cam.transform = t
		cam.size = ortho_size


func _capture(base: String, zooms: bool) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base).get_base_dir())
	await _settle(30)
	_save(base + ".png")
	if zooms:
		for zoom_name: String in ZOOMS:
			var entry: Array = ZOOMS[zoom_name]
			_frame(entry[0], entry[1])
			await _settle(10)
			_save("%s_zoom_%s.png" % [base, zoom_name])
	print("SMOOTHNESS LAB COMPLETE")
	get_tree().quit()


func _settle(frames: int) -> void:
	for i in frames:
		await RenderingServer.frame_post_draw


func _save(path: String) -> void:
	_viewport.get_texture().get_image().save_png(path)
	print("SHOT SAVED: " + path)
