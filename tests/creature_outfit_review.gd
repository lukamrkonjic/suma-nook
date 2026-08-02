extends Node3D
## Review scene for the procedural clothing system: dressed creatures of
## different body plans, idle then walking, front and 3/4 captures.

const ProceduralCreatureScript := preload(
	"res://scripts/creatures/procedural_creature.gd"
)

const DRESSED: Array = [
	{"creature": "res://data/creatures/nook_kit.json", "outfit": ""},
	{
		"creature": "res://data/creatures/sprout_scout.json",
		"outfit": "res://data/outfits/angler_set.json",
	},
	{
		"creature": "res://data/creatures/meadow_pup.json",
		"outfit": "res://data/outfits/party_puff.json",
	},
	{
		"creature": "res://data/creatures/grumble_gob.json",
		"outfit": "res://data/outfits/cozy_scout.json",
	},
	{
		"creature": "res://data/creatures/clover_hop.json",
		"outfit": "res://data/outfits/party_puff.json",
	},
]
const SPACING := 0.66

var _camera: Camera3D
var _creatures: Array[Node3D] = []
var _walking := false
var _output_dir := "res://artifacts/creature_outfit_review"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	_build_stage()

	for _frame in 14:
		await get_tree().process_frame
	await _capture("outfits_idle_front.png")

	_camera.position = Vector3(1.5, 0.75, -1.75)
	_camera.look_at(Vector3(0.0, 0.24, 0.0))
	for _frame in 4:
		await get_tree().process_frame
	await _capture("outfits_idle_quarter.png")

	_walking = true
	for _frame in 26:
		await get_tree().process_frame
	await _capture("outfits_walk.png")
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	var state := ProceduralCreatureScript.MotionState.new()
	if _walking:
		state.local_velocity = Vector3(0.0, 0.0, -1.3)
	state.grounded = true
	state.look_target = Vector3(0.0, 0.35, -1.7)
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
	plane.size = Vector2(5.0, 4.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#d7e5b4")
	ground_material.roughness = 1.0
	ground.material_override = ground_material
	add_child(ground)

	for dressed_index in DRESSED.size():
		var entry := DRESSED[dressed_index] as Dictionary
		var creature := ProceduralCreatureScript.new() as Node3D
		creature.position = Vector3(
			(float(dressed_index) - float(DRESSED.size() - 1) * 0.5) * SPACING,
			0.0,
			0.0
		)
		add_child(creature)
		creature.call("build_from_path", String(entry.get("creature")))
		var outfit_path := String(entry.get("outfit"))
		if not outfit_path.is_empty():
			creature.call("set_outfit", outfit_path)
		_creatures.append(creature)

	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.position = Vector3(0.0, 0.6, -2.55)
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.26, 0.0))
	_camera.current = true


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_output_dir.path_join(file_name))
	if error != OK:
		push_error("Could not save outfit review image: %s" % error_string(error))
