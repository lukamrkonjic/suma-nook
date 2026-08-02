extends Node3D
## Contact-sheet review for the generic procedural creature core: one of each
## body plan side by side, idle then walking, photographed front and 3/4.
## Creatures are driven directly through MotionState — no controllers needed.

const ProceduralCreatureScript := preload(
	"res://scripts/creatures/procedural_creature.gd"
)

const CREATURE_DIRECTORY := "res://data/creatures"
const COLUMNS := 8
const SPACING_X := 0.72
const SPACING_Z := 0.95

var _camera: Camera3D
var _creatures: Array[Node3D] = []
var _walking := false
var _output_dir := "res://artifacts/creature_menagerie_review"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	_build_stage()

	for _frame in 14:
		await get_tree().process_frame
	await _capture("menagerie_idle_front.png")

	_camera.position = Vector3(1.7, 0.72, -1.9)
	_camera.look_at(Vector3(0.0, 0.22, 0.0))
	for _frame in 4:
		await get_tree().process_frame
	await _capture("menagerie_idle_quarter.png")

	_walking = true
	for _frame in 30:
		await get_tree().process_frame
	await _capture("menagerie_walk_a.png")
	for _frame in 9:
		await get_tree().process_frame
	await _capture("menagerie_walk_b.png")
	_camera.position = Vector3(0.0, 0.62, -2.75)
	_camera.look_at(Vector3(0.0, 0.24, 0.0))
	for _frame in 4:
		await get_tree().process_frame
	await _capture("menagerie_walk_front.png")
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	var state := ProceduralCreatureScript.MotionState.new()
	if _walking:
		state.local_velocity = Vector3(0.0, 0.0, -1.4)
	state.grounded = true
	state.look_target = Vector3(0.0, 0.35, -1.6)
	for creature in _creatures:
		creature.call("advance", delta, state)


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

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(9.0, 8.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#d7e5b4")
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	add_child(ground)

	var lineup := _discover_creatures()
	var rows := ceili(float(lineup.size()) / float(COLUMNS))
	for lineup_index in lineup.size():
		var column := lineup_index % COLUMNS
		var row := lineup_index / COLUMNS
		var creature := ProceduralCreatureScript.new() as Node3D
		creature.position = Vector3(
			(float(column) - float(COLUMNS - 1) * 0.5) * SPACING_X,
			0.0,
			(float(row) - float(rows - 1) * 0.5) * SPACING_Z
		)
		add_child(creature)
		creature.call("build_from_path", lineup[lineup_index])
		_creatures.append(creature)
		print("menagerie[%d,%d] = %s" % [row, column, lineup[lineup_index]])

	_camera = Camera3D.new()
	_camera.fov = 42.0
	_camera.position = Vector3(0.0, 3.1, -4.9)
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.05, 0.55))
	_camera.current = true


func _discover_creatures() -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(CREATURE_DIRECTORY)
	if directory == null:
		return result
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			result.append(CREATURE_DIRECTORY.path_join(file_name))
		file_name = directory.get_next()
	directory.list_dir_end()
	result.sort()
	return result


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_output_dir.path_join(file_name))
	if error != OK:
		push_error("Could not save menagerie image: %s" % error_string(error))
