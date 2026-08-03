extends Node3D
## Deterministic low-cost review scene for the live SDF player renderer.

const ProceduralCritterScript := preload(
	"res://scripts/player/procedural_critter_player.gd"
)

var _camera: Camera3D
var _critter: Node3D
var _output_dir := "res://artifacts/sdf_blend_shell_review"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	_build_stage()
	for _frame in 8:
		await get_tree().process_frame
	await _capture("sdf_reference.png")
	_camera.position = Vector3(1.35, 1.00, -1.60)
	_camera.look_at(Vector3(0.0, 0.42, 0.0))
	for _frame in 3:
		await get_tree().process_frame
	await _capture("sdf_orbit.png")
	_camera.position = Vector3(1.85, 0.68, 0.0)
	_camera.look_at(Vector3(0.0, 0.42, 0.0))
	for _frame in 3:
		await get_tree().process_frame
	await _capture("sdf_side.png")
	_critter.call("equip_outfit", "res://data/outfits/cozy_scout.json")
	_camera.position = Vector3(0.78, 1.02, -1.70)
	_camera.look_at(Vector3(0.0, 0.42, 0.0))
	for _frame in 3:
		await get_tree().process_frame
	await _capture("sdf_styled.png")
	get_tree().quit(0)


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

	var controller := CharacterBody3D.new()
	controller.name = "ReviewController"
	controller.set_meta("procedural_review_grounded", true)
	add_child(controller)
	var visual_root := Node3D.new()
	visual_root.name = "ReviewVisual"
	controller.add_child(visual_root)
	_critter = ProceduralCritterScript.new()
	_critter.name = "ProceduralCritterPlayer"
	visual_root.add_child(_critter)
	_critter.call("build")
	# Geometry review stays bare so accessories cannot hide silhouette defects.
	_critter.call("clear_outfit")

	_camera = Camera3D.new()
	_camera.fov = 32.0
	_camera.position = Vector3(0.78, 1.02, -1.70)
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.42, 0.0))
	_camera.current = true


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_output_dir.path_join(file_name))
	if error != OK:
		push_error("Could not save SDF review image: %s" % error_string(error))
