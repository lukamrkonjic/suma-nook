extends Node3D
## Deterministic real-Godot review of the equipped skinned cowboy vest.

const DEFAULT_OUTPUT_DIR := "res://docs/cowboy_vest_review"

var _visual: PlayerVisual
var _camera: Camera3D
var _output_dir := DEFAULT_OUTPUT_DIR
var _asset_id := "cowboy_vest"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
		elif argument.begins_with("--asset-id="):
			_asset_id = argument.trim_prefix("--asset-id=")
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_output_dir)
	)

	var palette: CozyPalette = load(
		"res://assets/palettes/gg_material_palette.tres"
	)
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	var lighting := (
		load("res://scenes/visual/SumaSoftDaylight.tscn") as PackedScene
	).instantiate()
	lighting.name = "ReviewLighting"
	add_child(lighting)

	_add_ground()
	_visual = PlayerVisual.new()
	_visual.name = "EquippedPlayer"
	add_child(_visual)
	_visual.build(assets, palette)

	if _asset_id == "cowboy_vest":
		var core := GameCore.new()
		if not core.setup():
			push_error("Cowboy vest review could not load game content")
			get_tree().quit(1)
			return
		core.equipment.acquire("cosmetic_cowboy_vest")
		core.equipment.equip("cosmetic_cowboy_vest")
		_visual.apply_equipment(core.equipment)
	else:
		_visual._clear_body_garment()
		if not _visual._attach_skinned_body_bundle(_asset_id):
			push_error("Could not attach review garment: " + _asset_id)
			get_tree().quit(1)
			return
		_visual._set_body_region_mask([])

	_camera = Camera3D.new()
	_camera.name = "ReviewCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 1.48
	_camera.near = 0.05
	_camera.far = 30.0
	_camera.current = true
	add_child(_camera)
	_capture_review.call_deferred()


func _add_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "ReviewGround"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(6.0, 6.0)
	ground.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#d7cfbf")
	material.roughness = 1.0
	ground.material_override = material
	add_child(ground)


func _capture_review() -> void:
	await _settle(30)
	_visual._animation_player.play(_visual._asset_profile.idle_clip_name)
	_visual._animation_player.seek(0.35, true)
	await _shot(
		"cowboy_vest_reference.png",
		Vector3(0.0, 1.15, -4.0),
		Vector3(0.0, 0.59, 0.0),
		1.45
	)
	await _shot(
		"cowboy_vest_orbit.png",
		Vector3(2.6, 1.65, 3.2),
		Vector3(0.0, 0.59, 0.0),
		1.48
	)
	await _shot(
		"cowboy_vest_side.png",
		Vector3(4.0, 1.05, 0.0),
		Vector3(0.0, 0.57, 0.0),
		1.42
	)
	await _shot(
		"cowboy_vest_back.png",
		Vector3(0.0, 1.15, 4.0),
		Vector3(0.0, 0.58, 0.0),
		1.45
	)

	_visual._animation_player.play(_visual._asset_profile.walk_clip_name)
	_visual._animation_player.seek(0.44, true)
	await _shot(
		"cowboy_vest_grazing_walk.png",
		Vector3(-3.1, 0.62, -3.4),
		Vector3(0.0, 0.55, 0.0),
		1.50
	)
	print("COWBOY VEST GODOT REVIEW COMPLETE: " + _output_dir)
	for child in get_children():
		child.queue_free()
	await _settle(3)
	get_tree().quit()


func _shot(
	filename: String,
	position: Vector3,
	pivot: Vector3,
	ortho_size: float
) -> void:
	_camera.position = position
	_camera.look_at(pivot, Vector3.UP)
	_camera.size = ortho_size
	await _settle(12)
	await RenderingServer.frame_post_draw
	var path := _output_dir.path_join(filename)
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Could not save cowboy vest review: %s" % error_string(error))
	else:
		print("COWBOY VEST REVIEW SHOT: " + path)


func _settle(frame_count: int) -> void:
	for _frame_index in frame_count:
		await get_tree().process_frame
