extends Node3D
## Deterministic player-only capture harness for final morphology and motion QA.

const ProceduralCreatureScript := preload(
	"res://scripts/creatures/procedural_creature.gd"
)

var _camera: Camera3D
var _player: Node3D
var _output_dir := "res://artifacts/player_final_polish/final"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	DirAccess.make_dir_recursive_absolute(_output_dir.path_join("walk_cycle"))
	_build_stage()

	var idle := ProceduralCreatureScript.MotionState.new()
	idle.grounded = true
	await _step(90, idle)

	_set_camera(Vector3(0.0, 0.73, -1.48))
	await _capture("01_player_hatless_front.png")
	_set_camera(Vector3(0.82, 0.78, -1.42))
	await _capture("02_player_hatless_34.png")
	_set_camera(Vector3(1.52, 0.66, 0.0))
	await _capture("03_player_hatless_side.png")

	_set_camera(Vector3(0.68, 0.76, -1.43))
	await _step(55, idle)
	await _capture("04_player_idle.png")

	var walk := ProceduralCreatureScript.MotionState.new()
	walk.grounded = true
	walk.local_velocity = Vector3(0.0, 0.0, -1.65)
	walk.look_target = Vector3(0.0, 0.38, -2.0)
	await _step(9, walk)
	await _capture("05_player_walk_frame_a.png")
	await _step(15, walk)
	await _capture("06_player_walk_frame_b.png")

	var turn := ProceduralCreatureScript.MotionState.new()
	turn.grounded = true
	turn.local_velocity = Vector3(0.0, 0.0, -1.45)
	turn.yaw_rate = 2.8
	turn.look_target = Vector3(-1.4, 0.40, -1.3)
	await _step(8, turn)
	await _capture("07_player_turn.png")

	# One complete walk cycle at a compact 30 fps sampling rate. The PNGs are
	# retained for inspection and assembled into the requested GIF externally.
	# First let the captured turn follow-through settle back into locomotion so
	# the loop starts and ends on the same forward-facing motion envelope.
	await _step(30, walk)
	for frame_index in 16:
		await _step(2, walk)
		await _capture(
			"walk_cycle/frame_%02d.png" % frame_index
		)

	print("PLAYER_FINAL_POLISH_REVIEW_DONE")
	get_tree().quit(0)


func _step(frame_count: int, state: ProceduralCreatureScript.MotionState) -> void:
	for _frame in frame_count:
		_player.call("advance", 1.0 / 60.0, state)
		await get_tree().process_frame


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
	key.directional_shadow_max_distance = 6.0
	key.shadow_blur = 3.0
	add_child(key)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.0, 3.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#d7e5b4")
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	add_child(ground)

	_player = ProceduralCreatureScript.new() as Node3D
	_player.name = "FinalPolishPlayer"
	add_child(_player)
	_player.call("build_from_path", "res://data/creatures/islander.json")
	assert(
		_player.find_child("Hat", true, false) == null,
		"Default final-polish player must be hatless"
	)

	_camera = Camera3D.new()
	_camera.fov = 27.0
	add_child(_camera)
	_set_camera(Vector3(0.0, 0.73, -1.48))
	_camera.current = true


func _set_camera(camera_position: Vector3) -> void:
	_camera.position = camera_position
	_camera.look_at(Vector3(0.0, 0.31, 0.0))
	for _frame in 2:
		await get_tree().process_frame


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(
		_output_dir.path_join(file_name)
	)
	if error != OK:
		push_error(
			"Could not save final player review image: %s" % error_string(error)
		)
