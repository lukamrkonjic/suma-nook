extends Node
## Focused runtime acceptance check for the ambient pigeon mascot.

const SAVE_PATH := "user://pigeon_in_world_review_save.json"
const OUTPUT_DIR := "C:/Dev/suma-nook/artifacts/pigeon_review"

var _main: Main
var _failures := 0


func _ready() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	await _enter_gameplay()
	_main.debug_build_mock_world()
	_main.pigeon_controller.flight_duration_min = 0.9
	_main.pigeon_controller.flight_duration_max = 0.9
	_main.pigeon_controller.spawn_near_player()
	_hide_ui_and_frame_mascot()
	await get_tree().create_timer(0.8).timeout
	_check_mascot_is_renderable()
	await _capture("pigeon_in_world_ground.png")
	await _check_forward_walk()
	_main.pigeon_controller.call("_begin_takeoff")
	await get_tree().create_timer(0.9).timeout
	_check(
		_main.pigeon_controller.movement_state_name() == "flying",
		"takeoff reaches the flying state"
	)
	await _capture("pigeon_in_world_flying.png")
	await _wait_for_grounded_state(4.0)
	_check(
		not _main.pigeon_controller.is_flying(),
		"flight returns to a grounded state"
	)
	print("PIGEON_IN_WORLD failures=", _failures)
	_main.free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	_check(creator != null, "character creator is available")
	if creator == null:
		return
	creator._name_edit.text = "Pigeon Keeper"
	creator._finish()
	await get_tree().create_timer(0.7).timeout
	_check(_main._gameplay_started, "test enters gameplay")


func _hide_ui_and_frame_mascot() -> void:
	for child in _main.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	_main.camera_rig._size_target = 14.0
	_main.camera_rig.camera.position.z = 14.0
	_main.camera_rig.global_position = _main.pigeon_mascot.global_position
	_main.camera_rig.set_process(false)


func _check_mascot_is_renderable() -> void:
	_check(_main.pigeon_mascot.visible, "mascot root is visible")
	_check(_main.pigeon_mascot.get_node("Model").visible, "mascot body is visible")
	var body := _main.pigeon_mascot.get_node(
		"Model/PigeonRig/Skeleton3D/PigeonBody"
	) as MeshInstance3D
	_check(body != null and body.is_visible_in_tree(), "skinned body renders in tree")
	_check(body != null and body.extra_cull_margin >= 1.0, "animated body has safe culling bounds")


func _check_forward_walk() -> void:
	var started := bool(_main.pigeon_controller.call("_begin_walk_to_neighbor"))
	_check(started, "mascot finds a safe neighboring tile")
	if not started:
		return
	var start := _main.pigeon_mascot.global_position
	await get_tree().create_timer(0.35).timeout
	var displacement := _main.pigeon_mascot.global_position - start
	displacement.y = 0.0
	var forward := -_main.pigeon_mascot.global_basis.z
	forward.y = 0.0
	var alignment := 1.0
	if displacement.length_squared() > 0.0001:
		alignment = forward.normalized().dot(displacement.normalized())
	_check(displacement.length() > 0.05, "mascot advances while walking")
	_check(alignment > 0.9, "mascot walks beak-first instead of backwards")


func _wait_for_grounded_state(timeout_seconds: float) -> void:
	var elapsed := 0.0
	while _main.pigeon_controller.is_flying() and elapsed < timeout_seconds:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	GGCaptureEncode.encode_srgb(image)
	var result := image.save_png(OUTPUT_DIR.path_join(file_name))
	_check(result == OK, "capture writes %s" % file_name)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS ", label)
	else:
		_failures += 1
		push_error("PIGEON_IN_WORLD: " + label)
