extends Node3D
## Phase-capture review for the rebuilt V2 player.
##
## Produces the numbered acceptance captures in artifacts/player_rebuild_v2:
## naked morphology, face/hair, dressed outfit, and rig stress poses. The
## silhouette image is derived offline by thresholding the front capture.

const ProceduralCritterScript := preload(
	"res://scripts/player/procedural_critter_player.gd"
)

## Temporary grounding calibration: a small sphere resting exactly on the
## floor next to the character.
const SHOW_GROUND_MARKER := false

var _camera: Camera3D
var _controller: CharacterBody3D
var _critter: Node3D
var _output_dir := "res://artifacts/player_rebuild_v2"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	_build_stage()
	for _frame in 10:
		await get_tree().process_frame

	# Naked morphology first.
	_body().call("set_dressed", false)
	for _frame in 4:
		await get_tree().process_frame
	await _shot("01_body_front.png", Vector3(0.0, 0.52, -1.55), 0.27)
	await _shot("02_body_34.png", Vector3(1.05, 0.62, -1.30), 0.27)
	await _shot("03_body_side.png", Vector3(1.70, 0.52, 0.0), 0.27)

	# Face and hair.
	await _shot("05_face_close.png", Vector3(0.10, 0.50, -0.62), 0.44)
	await _shot("06_face_gameplay_scale.png", Vector3(3.6, 4.4, -7.2), 0.24)
	await _shot("07_hair_side.png", Vector3(0.85, 0.58, -0.30), 0.44)

	# Dressed.
	_body().call("set_dressed", true)
	for _frame in 4:
		await get_tree().process_frame
	await _shot("08_outfit_front.png", Vector3(0.0, 0.52, -1.55), 0.27)
	await _shot("09_outfit_34.png", Vector3(1.05, 0.62, -1.30), 0.27)
	await _shot("10_outfit_side.png", Vector3(1.70, 0.52, 0.0), 0.27)

	# Rig stress.
	_controller.velocity = Vector3(0.0, 0.0, -1.9)
	for _frame in 26:
		await get_tree().process_frame
	await _shot("15_stress_walk.png", Vector3(1.05, 0.62, -1.30), 0.27)
	await _shot("15b_stress_walk_side.png", Vector3(1.70, 0.52, 0.0), 0.27)
	_controller.velocity = Vector3.ZERO
	for _frame in 14:
		await get_tree().process_frame
	_critter.call("play_action", "celebrate", 1.2)
	for _frame in 20:
		await get_tree().process_frame
	await _shot("15c_stress_arm_raise.png", Vector3(1.05, 0.62, -1.30), 0.27)
	_critter.call("play_action", "dig", 1.4)
	for _frame in 26:
		await get_tree().process_frame
	await _shot("15d_stress_crouch.png", Vector3(1.05, 0.62, -1.30), 0.27)
	_critter.call("stop_action")

	get_tree().quit(0)


func _body() -> Node3D:
	return _critter.get_node("Creature/HumanBodyParts") as Node3D


func _shot(file_name: String, from: Vector3, focus_height: float) -> void:
	_camera.position = from
	_camera.look_at(Vector3(0.0, focus_height, 0.0))
	for _frame in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_output_dir.path_join(file_name))
	if error != OK:
		push_error("Could not save V2 review image: %s" % error_string(error))
	print("PLAYER_V2_CAPTURE %s" % file_name)


func _build_stage() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#b9dfd5")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#fff1d6")
	environment.ambient_light_energy = 0.48
	world_environment.environment = environment
	add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	key.light_color = Color("#fff0ce")
	key.light_energy = 0.78
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 8.0
	key.shadow_blur = 3.0
	add_child(key)

	# Soft front fill so review captures show true material colors even
	# though the key light sits behind the character.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30.0, 165.0, 0.0)
	fill.light_color = Color("#fff6e6")
	fill.light_energy = 0.30
	fill.shadow_enabled = false
	add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6.0, 6.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#d7e5b4")
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	add_child(ground)

	if SHOW_GROUND_MARKER:
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.03
		sphere.height = 0.06
		marker.mesh = sphere
		marker.position = Vector3(0.28, 0.03, 0.0)
		add_child(marker)

	_controller = CharacterBody3D.new()
	_controller.name = "ReviewController"
	_controller.set_meta("procedural_review_grounded", true)
	add_child(_controller)
	var visual_root := Node3D.new()
	visual_root.name = "ReviewVisual"
	_controller.add_child(visual_root)
	_critter = ProceduralCritterScript.new()
	_critter.name = "ProceduralCritterPlayer"
	visual_root.add_child(_critter)
	_critter.call("build")

	_camera = Camera3D.new()
	_camera.fov = 30.0
	add_child(_camera)
	_camera.current = true
