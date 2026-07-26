extends Node3D
## GG Asset Quality Lab — rebuilt assets on neutral tiles under the final day
## rig. No asset ships to the main scene before it reads correctly here at
## gameplay distance, close up, and in silhouette.
##
##   godot --path . scenes/debug/GGAssetQualityLab.tscn -- --shot=docs/visual_rework/comparisons/lab
##       [--closeups] [--silhouette]
##
## --shot alone: full-lab capture. --closeups: adds per-asset medium close-ups
## for the FEATURED list. --silhouette: adds a flat-shaded silhouette capture.

const CAPTURE_SIZE := Vector2i(1920, 1080)
const CAMERA_YAW := 45.0
const CAMERA_PITCH := -34.0

## [asset_id, world_pos, yaw_deg]
const ROSTER := [
	["tile_grass", Vector3(0, 0, 0), 0.0],
	["tile_grass_flower", Vector3(2, 0, 0), 0.0],
	["tile_path", Vector3(4, 0, 0), 0.0],
	["tile_garden", Vector3(6, 0, 0), 0.0],
	["tile_grass", Vector3(0, 0, 2), 0.0],
	["tile_grass", Vector3(2, 0, 2), 0.0],
	["tile_stone_clearing", Vector3(4, 0, 2), 0.0],
	["tile_grass", Vector3(6, 0, 2), 0.0],
	["tile_grass", Vector3(0, 0, 4), 0.0],
	["tile_grass", Vector3(2, 0, 4), 0.0],
	["tile_grass", Vector3(4, 0, 4), 0.0],
	["tile_grass_pond_edge", Vector3(6, 0, 4), 0.0],
	["prop_pine_a", Vector3(0, 0, 2), 0.0],
	["prop_pine_young", Vector3(-0.8, 0, 2.7), 0.0],
	["prop_pine_b", Vector3(6.2, 0, 2.2), 0.0],
	["prop_bush_a", Vector3(2, 0, 2.1), 0.0],
	["prop_bush_b", Vector3(2.8, 0, 2.6), 0.0],
	["prop_bench", Vector3(4, 0, 4.15), 25.0],
	["prop_chest", Vector3(2.5, 0, 4.4), -15.0],
	["prop_lantern", Vector3(4.6, 0, 0.55), 0.0],
	["prop_present", Vector3(5.4, 0, 2.6), 12.0],
	["prop_dock", Vector3(0.4, 0, 4.6), 0.0],
	["prop_pot", Vector3(6.5, 0, 0.4), 0.0],
	["prop_cardboard_box", Vector3(3.4, 0, 0.4), 30.0],
	["character_proxy", Vector3(1.2, 0.02, 3.2), -135.0],
	["calib_sphere", Vector3(-0.6, 0, 0.2), 0.0],
	["calib_cube", Vector3(-0.55, 0, 1.2), 0.0],
]

## Assets that get dedicated close-up captures with --closeups.
const FEATURED := {
	"tile_grass": Vector3(0, 0.1, 0),
	"prop_pine_a": Vector3(0, 0.9, 2),
	"prop_bush_a": Vector3(2, 0.3, 2.1),
	"prop_bench": Vector3(4, 0.3, 4.15),
	"prop_chest": Vector3(2.5, 0.25, 4.4),
	"prop_lantern": Vector3(4.6, 0.7, 0.55),
	"prop_dock": Vector3(0.4, 0.1, 4.6),
	"prop_present": Vector3(5.4, 0.2, 2.6),
	"water": Vector3(8.4, -0.14, 2.4),
}

var _materials: MaterialLibrary
var _assets: AssetLibrary
var _lighting: LightingRig
var _viewport: SubViewport
var _camera: Camera3D
var _fit_camera: Camera3D


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

	_build_water_region()

	_viewport = SubViewport.new()
	_viewport.size = CAPTURE_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.use_debanding = true
	add_child(_viewport)

	# Root-viewport twin camera drives the directional shadow fit (see
	# docs/visual_match/README.md — hard-won Godot facts).
	_fit_camera = _make_camera()
	add_child(_fit_camera)
	_fit_camera.current = true
	_camera = _make_camera()
	_viewport.add_child(_camera)
	_camera.current = true
	_frame(Vector3(4.4, 0, 2.2), 11.5)

	var shot_base := ""
	var closeups := false
	var silhouette := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot_base = arg.trim_prefix("--shot=")
		elif arg == "--closeups":
			closeups = true
		elif arg == "--silhouette":
			silhouette = true
	if shot_base != "":
		_capture_all(shot_base, closeups, silhouette)


## Demo water region east of the land: modeled sand floor, contiguous wavy
## surface, shoreline-weighted flora, dock reaching over the shallows.
const WATER_CELLS := [Vector2i(8, 0), Vector2i(8, 2), Vector2i(8, 4), Vector2i(10, 2)]


func _build_water_region() -> void:
	var flora := [
		["prop_uw_eelgrass_a", Vector3(7.4, -0.4, 0.4), 0.4],
		["prop_uw_eelgrass_c", Vector3(7.5, -0.4, 4.3), 2.1],
		["prop_uw_broadleaf_a", Vector3(7.6, -0.41, 2.6), 1.0],
		["prop_uw_rocks_b", Vector3(8.4, -0.42, 0.9), 0.0],
		["prop_uw_rocks_a", Vector3(8.6, -0.42, 3.6), 2.4],
		["prop_uw_reeds_a", Vector3(7.25, -0.38, 1.4), 0.9],
		["prop_lily_a", Vector3(7.75, -0.135, 3.4), 0.0],
		["prop_uw_eelgrass_b", Vector3(9.6, -0.4, 2.2), 3.4],
	]
	for cell in WATER_CELLS:
		var floor_node := _assets.instantiate("tile_water_floor")
		floor_node.position = Vector3(cell.x, 0, cell.y)
		add_child(floor_node)
	for entry in flora:
		var node := _assets.instantiate(entry[0])
		node.position = entry[1]
		node.rotation.y = entry[2]
		add_child(node)
	var dock := _assets.instantiate("prop_dock")
	dock.position = Vector3(6.7, 0, 2.0)
	dock.rotation_degrees.y = 90.0
	add_child(dock)
	var surface := WaterSurface.new()
	add_child(surface)
	surface.rebuild(WATER_CELLS, func(c: Vector2i) -> Vector3: return Vector3(c.x, 0, c.y),
			2.0, -0.14, _materials.material("water"))


func _make_camera() -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 20.0
	cam.far = 60.0
	return cam


func _frame(pivot: Vector3, ortho_size: float) -> void:
	var cam_basis := Basis.from_euler(Vector3(deg_to_rad(CAMERA_PITCH), deg_to_rad(CAMERA_YAW), 0.0))
	var t := Transform3D(cam_basis, pivot + cam_basis.z * 40.0)
	for cam in [_camera, _fit_camera]:
		cam.transform = t
		cam.size = ortho_size


func _capture_all(base: String, closeups: bool, silhouette: bool) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base).get_base_dir())
	await _settle(28)
	_save(base + "_full.png")
	if closeups:
		for asset_id: String in FEATURED:
			_frame(FEATURED[asset_id], 2.6)
			await _settle(8)
			_save("%s_close_%s.png" % [base, asset_id])
		_frame(Vector3(4.4, 0, 2.2), 11.5)
		await _settle(4)
	if silhouette:
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(0.16, 0.15, 0.14)
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for child in find_children("*", "MeshInstance3D", true, false):
			(child as MeshInstance3D).material_override = flat
		await _settle(6)
		_save(base + "_silhouette.png")
	print("LAB CAPTURE COMPLETE")
	get_tree().quit()


func _settle(frames: int) -> void:
	for i in frames:
		await RenderingServer.frame_post_draw


func _save(path: String) -> void:
	_viewport.get_texture().get_image().save_png(path)
	print("SHOT SAVED: " + path)
