extends Node3D
## Deterministic player-only capture harness for final morphology and motion QA.

const ProceduralCreatureScript := preload(
	"res://scripts/creatures/procedural_creature.gd"
)

var _camera: Camera3D
var _player: Node3D
var _chop_target: MeshInstance3D
var _fishing_water: MeshInstance3D
var _fishing_line: MeshInstance3D
var _fishing_line_target := Vector3(0.0, 0.012, -0.82)
var _fishing_review_time := -1.0
var _output_dir := "res://artifacts/player_final_polish/final"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot-dir="):
			_output_dir = argument.trim_prefix("--shot-dir=")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	DirAccess.make_dir_recursive_absolute(_output_dir.path_join("walk_cycle"))
	DirAccess.make_dir_recursive_absolute(_output_dir.path_join("jump_cycle"))
	DirAccess.make_dir_recursive_absolute(_output_dir.path_join("chop_cycle"))
	DirAccess.make_dir_recursive_absolute(_output_dir.path_join("fishing_cycle"))
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
	_set_camera(Vector3(-1.05, 1.18, 1.34))
	await _capture("03b_player_gameplay_back.png")

	_set_camera(Vector3(0.68, 0.76, -1.43))
	await _step(55, idle)
	await _capture("04_player_idle.png")

	var walk := ProceduralCreatureScript.MotionState.new()
	walk.grounded = true
	walk.local_velocity = Vector3(0.0, 0.0, -1.10)
	walk.look_target = Vector3(0.0, 0.38, -2.0)
	await _step(9, walk)
	await _capture("05_player_walk_frame_a.png")
	await _step(15, walk)
	await _capture("06_player_walk_frame_b.png")

	var turn := ProceduralCreatureScript.MotionState.new()
	turn.grounded = true
	turn.local_velocity = Vector3(0.0, 0.0, -0.95)
	turn.yaw_rate = 2.8
	turn.look_target = Vector3(-1.4, 0.40, -1.3)
	await _step(8, turn)
	await _capture("07_player_turn.png")

	# One complete walk cycle at a compact 30 fps sampling rate. The PNGs are
	# retained for inspection and assembled into the requested GIF externally.
	# First let the captured turn follow-through settle back into locomotion so
	# the loop starts and ends on the same forward-facing motion envelope.
	await _step(30, walk)
	for frame_index in 30:
		await _step(2, walk)
		await _capture(
			"walk_cycle/frame_%02d.png" % frame_index
		)

	# A complete airborne leg contract: tuck below the hips on ascent, gather
	# at the apex, extend for landing, then return to the planted stance.
	await _step(30, idle)
	var jump := ProceduralCreatureScript.MotionState.new()
	jump.grounded = false
	jump.local_velocity = Vector3(0.0, 4.4, -0.60)
	await _step(8, jump)
	await _capture("jump_cycle/01_ascent.png")
	jump.local_velocity = Vector3(0.0, 0.0, -0.60)
	await _step(12, jump)
	await _capture("jump_cycle/02_apex.png")
	jump.local_velocity = Vector3(0.0, -3.8, -0.60)
	await _step(10, jump)
	await _capture("jump_cycle/03_descent.png")
	await _step(20, idle)
	await _capture("jump_cycle/04_landed.png")

	# Reference-shaped chop: settle, equip the visible procedural axe, then
	# sample the full side-loaded arc against a visible trunk contact target.
	await _step(40, idle)
	_chop_target.visible = true
	_set_camera(Vector3(0.88, 0.92, -1.34))
	_player.call("set_held_tool", "axe")
	_player.call("play_action", "chop", 1.9)
	for frame_index in 38:
		await _step(3, idle)
		await _capture("chop_cycle/frame_%02d.png" % frame_index)
		match frame_index:
			16:
				await _capture("chop_cycle/01_load.png")
			21:
				await _capture("chop_cycle/02_impact.png")
			24:
				await _capture("chop_cycle/03_hold.png")
			30:
				await _capture("chop_cycle/04_recovery.png")

	# Readable fishing silhouette: both hands lift the rod into a backswing,
	# whip the tip over the water, then settle into a quiet forward hold. The
	# review line is anchored to the same live procedural tip used by gameplay.
	await _step(40, idle)
	_chop_target.visible = false
	_fishing_water.visible = true
	_fishing_line.visible = true
	_set_camera(Vector3(1.46, 0.82, -0.30))
	_player.call("set_held_tool", "rod")
	_player.call("play_action", "fish_cast", 1.15)
	_fishing_review_time = 0.0
	for frame_index in 24:
		await _step(3, idle)
		await _capture("fishing_cycle/frame_%02d.png" % frame_index)
		match frame_index:
			5:
				await _capture("fishing_cycle/01_backswing.png")
			9:
				await _capture("fishing_cycle/02_apex.png")
			13:
				await _capture("fishing_cycle/03_release.png")
			18:
				await _capture("fishing_cycle/04_follow_through.png")
	_player.call("play_action", "fish_wait", 2.6)
	await _step(32, idle)
	await _capture("fishing_cycle/05_wait.png")

	print("PLAYER_FINAL_POLISH_REVIEW_DONE")
	get_tree().quit(0)


func _step(frame_count: int, state: ProceduralCreatureScript.MotionState) -> void:
	for _frame in frame_count:
		_player.call("advance", 1.0 / 60.0, state)
		if _fishing_review_time >= 0.0:
			_fishing_review_time += 1.0 / 60.0
		_update_review_fishing_line()
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

	_chop_target = MeshInstance3D.new()
	_chop_target.name = "ChopTarget"
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.105
	trunk.bottom_radius = 0.12
	trunk.height = 0.62
	trunk.radial_segments = 14
	_chop_target.mesh = trunk
	_chop_target.position = Vector3(0.0, 0.31, -0.45)
	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color("#91613f")
	trunk_material.roughness = 1.0
	_chop_target.material_override = trunk_material
	_chop_target.visible = false
	add_child(_chop_target)

	_fishing_water = MeshInstance3D.new()
	_fishing_water.name = "FishingWater"
	var water := PlaneMesh.new()
	water.size = Vector2(1.25, 0.85)
	_fishing_water.mesh = water
	_fishing_water.position = Vector3(0.0, 0.004, -0.76)
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color("#76c9ca")
	water_material.roughness = 0.82
	_fishing_water.material_override = water_material
	_fishing_water.visible = false
	add_child(_fishing_water)

	_fishing_line = MeshInstance3D.new()
	_fishing_line.name = "FishingLine"
	var line_mesh := CylinderMesh.new()
	line_mesh.top_radius = 0.0022
	line_mesh.bottom_radius = 0.0022
	line_mesh.height = 1.0
	line_mesh.radial_segments = 6
	_fishing_line.mesh = line_mesh
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = Color("#f6f1d9")
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fishing_line.material_override = line_material
	_fishing_line.visible = false
	add_child(_fishing_line)

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


func _update_review_fishing_line() -> void:
	if not is_instance_valid(_fishing_line) or not _fishing_line.visible:
		return
	var current_outfit := _player.call("outfit") as Node3D
	if current_outfit == null:
		return
	var tip := current_outfit.call("held_tip_world") as Vector3
	var release_time := (
		float(_player.call("action_duration", "fish_cast", 1.15))
		* float(_player.call("action_impact_ratio", "fish_cast", 0.60))
	)
	var release_progress := clampf(
		(_fishing_review_time - release_time) / 0.24,
		0.0,
		1.0
	)
	release_progress = 1.0 - pow(1.0 - release_progress, 3.0)
	var visible_endpoint := tip.lerp(_fishing_line_target, release_progress)
	var delta := visible_endpoint - tip
	var length := delta.length()
	if length <= 0.001:
		_fishing_line.scale = Vector3.ZERO
		return
	var basis := Basis.IDENTITY
	basis.y = delta / length
	basis.x = basis.y.cross(Vector3.FORWARD).normalized()
	if basis.x.length_squared() < 0.001:
		basis.x = basis.y.cross(Vector3.RIGHT).normalized()
	basis.z = basis.x.cross(basis.y).normalized()
	_fishing_line.transform = Transform3D(
		basis.scaled(Vector3(1.0, length, 1.0)), tip.lerp(visible_endpoint, 0.5)
	)


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(
		_output_dir.path_join(file_name)
	)
	if error != OK:
		push_error(
			"Could not save final player review image: %s" % error_string(error)
		)
