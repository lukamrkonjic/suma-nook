extends Node3D
## Deterministic low-cost review scene for the procedural SDF owl mascot.
## A stub controller supplies movement_state and a fake player, so the owl's
## full ground/flight anatomy can be photographed without a world or grid.

const ProceduralOwlScript := preload(
	"res://scripts/characters/owl/procedural_owl_mascot.gd"
)

enum ReviewMode { HOLD, WALK, FLY }


class StubMascotController:
	extends Node
	var movement_state := PigeonMascotController.MovementState.IDLE
	var player: Node3D


var _camera: Camera3D
var _root: CharacterBody3D
var _stub: StubMascotController
var _mode := ReviewMode.HOLD
var _output_dir := "res://artifacts/sdf_owl_review"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	_build_stage()

	for _frame in 14:
		await get_tree().process_frame
	await _capture("owl_idle_front.png")

	_camera.position = Vector3(0.95, 0.34, 0.12)
	_camera.look_at(Vector3(0.0, 0.22, 0.0))
	for _frame in 4:
		await get_tree().process_frame
	await _capture("owl_idle_side.png")

	_root.position = Vector3(0.0, 0.0, 0.30)
	_root.rotation.y = 0.0
	_stub.movement_state = PigeonMascotController.MovementState.WALKING
	_mode = ReviewMode.WALK
	_camera.position = Vector3(1.05, 0.38, -0.25)
	_camera.look_at(Vector3(0.0, 0.20, 0.1))
	for _frame in 26:
		await get_tree().process_frame
	await _capture("owl_walk.png")

	_stub.movement_state = PigeonMascotController.MovementState.FLYING
	_mode = ReviewMode.FLY
	_root.position = Vector3(0.0, 1.05, 0.0)
	_camera.position = Vector3(1.05, 1.55, -1.15)
	_camera.look_at(Vector3(0.0, 1.22, 0.0))
	for _frame in 16:
		await get_tree().process_frame
	await _capture("owl_fly_a.png")
	for _frame in 5:
		await get_tree().process_frame
	await _capture("owl_fly_b.png")
	for _frame in 5:
		await get_tree().process_frame
	await _capture("owl_fly_c.png")
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	match _mode:
		ReviewMode.WALK:
			_root.position.z -= 0.62 * delta
		ReviewMode.FLY:
			# A slow turn while hovering exercises the banking response.
			_root.rotation.y += 1.2 * delta
		ReviewMode.HOLD:
			pass


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
	# The owl is ~0.35 m tall; default directional shadow settings acne-stripe
	# a character this small, and crisp self-shadows read as dirt blotches on
	# a toy-styled toon body — soften them instead.
	key.directional_shadow_max_distance = 6.0
	key.shadow_blur = 3.0
	add_child(key)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.0, 3.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#d7e5b4")
	ground.material_override = ground_material
	ground.mesh.surface_set_material(0, ground_material)
	add_child(ground)

	var fake_player := Node3D.new()
	fake_player.name = "FakePlayer"
	fake_player.position = Vector3(0.85, 0.0, -1.15)
	add_child(fake_player)

	_root = CharacterBody3D.new()
	_root.name = "OwlReviewRoot"
	add_child(_root)
	_stub = StubMascotController.new()
	_stub.name = "MascotController"
	_stub.player = fake_player
	_root.add_child(_stub)
	var owl := ProceduralOwlScript.new() as Node3D
	owl.name = "ProceduralOwlVisual"
	_root.add_child(owl)
	owl.call("build")
	owl.call("setup", _stub)

	_camera = Camera3D.new()
	_camera.fov = 30.0
	_camera.position = Vector3(0.55, 0.44, -0.95)
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.22, 0.0))
	_camera.current = true


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_output_dir.path_join(file_name))
	if error != OK:
		push_error("Could not save SDF owl review image: %s" % error_string(error))
