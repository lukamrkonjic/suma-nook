extends Node3D

var _camera: Camera3D


func _ready() -> void:
	var lighting := (
		load("res://scenes/visual/SumaSoftDaylight.tscn") as PackedScene
	).instantiate()
	add_child(lighting)

	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(3.0, 0.08, 3.0)
	floor_mesh.mesh = floor_box
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#80a35c")
	floor_material.roughness = 0.92
	floor_mesh.material_override = floor_material
	floor_mesh.position.y = -0.04
	add_child(floor_mesh)

	var mascot := (
		load("res://characters/mascots/pigeon_mascot.tscn") as PackedScene
	).instantiate() as CharacterBody3D
	add_child(mascot)
	mascot.visible = true
	mascot.rotation.y = deg_to_rad(25.0)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 1.35
	_camera.current = true
	_camera.position = Vector3(1.6, 1.1, -2.25)
	add_child(_camera)
	_camera.look_at(Vector3(0.0, 0.42, 0.0), Vector3.UP)

	await get_tree().process_frame
	await get_tree().process_frame
	var output_dir := "C:/Dev/suma-nook/artifacts/pigeon_review"
	DirAccess.make_dir_recursive_absolute(output_dir)
	await _capture(output_dir.path_join("pigeon_rest.png"))
	var controller := mascot.get_node("MascotController") as PigeonMascotController
	controller.call("_reset_visual_pose")
	controller.call("_apply_ground_wing_tuck", 0.82)
	await _capture(output_dir.path_join("pigeon_bird_tuck.png"))
	controller.call("_reset_visual_pose")
	controller.set("_wing_phase", PI * 0.5)
	controller.call("_apply_flight_flap", 0.58)
	await _capture(output_dir.path_join("pigeon_flight_up.png"))
	controller.call("_reset_visual_pose")
	controller.set("_wing_phase", PI * 1.5)
	controller.call("_apply_flight_flap", 0.58)
	await _capture(output_dir.path_join("pigeon_flight_down.png"))
	get_tree().quit()


func _capture(path: String) -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var result := get_viewport().get_texture().get_image().save_png(path)
	print("PIGEON_VISUAL_REVIEW path=", path, " result=", result)
