extends Node
## Prints the screen-space direction of the sun's ground shadow for the live
## gameplay camera. Diagnostic only.

const SAVE_PATH := "user://gg_shadow_probe_save.json"

var _main: Main


func _ready() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	creator._preview()
	creator._name_edit.text = "Probe"
	creator._finish()
	await get_tree().create_timer(0.7).timeout
	for frame in 10:
		await get_tree().process_frame
	var sun: DirectionalLight3D = _main.lighting._sun
	var travel := -sun.global_transform.basis.z
	var camera := get_viewport().get_camera_3d()
	var origin := _main.player.global_position
	var flat := Vector3(travel.x, 0.0, travel.z).normalized()
	var a := camera.unproject_position(origin)
	var b := camera.unproject_position(origin + flat * 2.0)
	print("PROBE sun_rotation=", sun.rotation_degrees)
	print("PROBE light_travel=", travel)
	print("PROBE camera_rig_yaw=", _main.camera_rig.rotation_degrees.y)
	print("PROBE screen_shadow_delta=", b - a)
	get_tree().quit(0)
