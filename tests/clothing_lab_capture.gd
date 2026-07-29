extends Node
## Visual smoke test for the standalone Clothing Lab UI and full character.

const OUTPUT := "res://artifacts/character_lab/clothing_lab.png"
const WRIST_DETAIL_OUTPUT := (
	"res://artifacts/character_lab/clothing_lab_wrist_detail.png"
)
const LAB := preload("res://characters/lab/clothing_lab.tscn")
const FINAL_OUTPUT := (
	"res://art_source/imported/jacket_default/"
	+ "top_jacket_cozy_final_review.glb"
)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(
		"res://artifacts/character_lab"
	)
	var lab := LAB.instantiate()
	add_child(lab)
	for _frame in 8:
		await get_tree().process_frame
	var fit: ClothingFitSettings = lab.get("_fit")
	var orbit_camera: Camera3D = lab.get("_orbit_camera")
	var marker_root: Node3D = lab.get("_marker_root")
	if marker_root == null or marker_root.get_child_count() < 8:
		push_error("Clothing Lab landmark overlay markers are missing.")
		get_tree().quit(1)
		return
	for marker_node in marker_root.get_children():
		var marker := marker_node as MeshInstance3D
		var sphere := marker.mesh as SphereMesh
		var material := sphere.material as StandardMaterial3D
		if (
			sphere.radius < 0.012
			or not material.no_depth_test
			or material.depth_draw_mode
			!= BaseMaterial3D.DEPTH_DRAW_DISABLED
			or material.render_priority < 127
		):
			push_error("Clothing Lab landmark is not a large top overlay.")
			get_tree().quit(1)
			return
	var preview_regions: CheckBox = lab.get("_preview_hidden_regions")
	var region_checks: Dictionary = lab.get("_region_checks")
	var hand_left := region_checks["hand_l"] as CheckBox
	var body_mesh := lab.get("_character").find_child(
		"PlayerMaleBody", true, false
	) as MeshInstance3D
	preview_regions.button_pressed = false
	hand_left.button_pressed = true
	await get_tree().process_frame
	var live_mask := int(
		body_mesh.get_instance_shader_parameter("hide_mask")
	)
	var hand_left_bit := 1 << int(
		PlayerArmorRegions.REGION_IDS["hand_l"]
	)
	if (
		not preview_regions.button_pressed
		or live_mask & hand_left_bit == 0
	):
		push_error("Clothing Lab coverage checkbox did not live-update body mask.")
		get_tree().quit(1)
		return
	hand_left.button_pressed = false
	await get_tree().process_frame
	live_mask = int(body_mesh.get_instance_shader_parameter("hide_mask"))
	if live_mask & hand_left_bit != 0:
		push_error("Clothing Lab coverage uncheck did not live-update body mask.")
		get_tree().quit(1)
		return
	var orbit_pivot := Vector3(0.0, 0.48, 0.0)
	for axis_view in [
		["+X", Vector3.RIGHT],
		["-X", Vector3.LEFT],
		["+Y", Vector3.UP],
		["-Y", Vector3.DOWN],
		["+Z", Vector3.BACK],
		["-Z", Vector3.FORWARD],
	]:
		lab.call("_set_camera_view", axis_view[0])
		var view_direction := (
			orbit_camera.position - orbit_pivot
		).normalized()
		if view_direction.dot(axis_view[1]) < 0.999:
			push_error("Clothing Lab axis snap failed for %s." % axis_view[0])
			get_tree().quit(1)
			return
	lab.call("_set_camera_view", "+Z")
	var before_orbit := orbit_camera.position
	lab.call("_orbit_preview", Vector2(0.2, -0.15))
	if orbit_camera.position.is_equal_approx(before_orbit):
		push_error("Clothing Lab free orbit did not move the camera.")
		get_tree().quit(1)
		return
	lab.call("_set_camera_view", "+Z")
	var middle_press := InputEventMouseButton.new()
	middle_press.button_index = MOUSE_BUTTON_MIDDLE
	middle_press.pressed = true
	middle_press.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(middle_press)
	await get_tree().process_frame
	if not bool(lab.get("_orbiting")):
		push_error("Clothing Lab GUI-routed MMB did not begin orbiting.")
		get_tree().quit(1)
		return
	var middle_motion := InputEventMouseMotion.new()
	middle_motion.relative = Vector2(18.0, -12.0)
	before_orbit = orbit_camera.position
	Input.parse_input_event(middle_motion)
	await get_tree().process_frame
	var middle_release := InputEventMouseButton.new()
	middle_release.button_index = MOUSE_BUTTON_MIDDLE
	middle_release.pressed = false
	middle_release.position = middle_press.position
	Input.parse_input_event(middle_release)
	await get_tree().process_frame
	if (
		orbit_camera.position.is_equal_approx(before_orbit)
		or bool(lab.get("_orbiting"))
		or float(lab.get("_orbit_yaw")) >= 0.0
		or float(lab.get("_orbit_pitch")) >= 0.0
	):
		push_error(
			"Clothing Lab inverted MMB orbit/release contract failed."
		)
		get_tree().quit(1)
		return
	var fit_controls: Dictionary = lab.get("_fit_controls")
	var torso_width := fit_controls["torso_width"] as SpinBox
	var original_width := fit.torso_width
	lab.call(
		"_begin_field_drag",
		torso_width,
		"torso_width",
		get_viewport().get_visible_rect().size * 0.5,
	)
	var field_motion := InputEventMouseMotion.new()
	field_motion.relative = Vector2(8.0, 0.0)
	Input.parse_input_event(field_motion)
	await get_tree().process_frame
	var field_release := InputEventMouseButton.new()
	field_release.button_index = MOUSE_BUTTON_LEFT
	field_release.pressed = false
	Input.parse_input_event(field_release)
	await get_tree().process_frame
	var dragged_width := fit.torso_width
	if is_equal_approx(dragged_width, original_width):
		push_error("Clothing Lab numeric drag did not change its field.")
		get_tree().quit(1)
		return
	lab.call("_undo")
	if not is_equal_approx(fit.torso_width, original_width):
		push_error("Clothing Lab drag did not undo as one operation.")
		get_tree().quit(1)
		return
	lab.call("_redo")
	if not is_equal_approx(fit.torso_width, dragged_width):
		push_error("Clothing Lab drag redo did not restore its value.")
		get_tree().quit(1)
		return
	lab.call("_revert_numeric_field", "torso_width")
	if not is_equal_approx(fit.torso_width, original_width):
		push_error("Clothing Lab per-field revert did not restore baseline.")
		get_tree().quit(1)
		return
	torso_width.value = original_width + torso_width.step * 4.0
	var shortcut_value := fit.torso_width
	var undo_key := InputEventKey.new()
	undo_key.physical_keycode = KEY_Z
	undo_key.ctrl_pressed = true
	undo_key.pressed = true
	Input.parse_input_event(undo_key)
	await get_tree().process_frame
	if not is_equal_approx(fit.torso_width, original_width):
		push_error("Clothing Lab Ctrl+Z did not undo through InputMap.")
		get_tree().quit(1)
		return
	var redo_key := InputEventKey.new()
	redo_key.physical_keycode = KEY_Y
	redo_key.ctrl_pressed = true
	redo_key.pressed = true
	Input.parse_input_event(redo_key)
	await get_tree().process_frame
	if not is_equal_approx(fit.torso_width, shortcut_value):
		push_error("Clothing Lab Ctrl+Y did not redo through InputMap.")
		get_tree().quit(1)
		return
	lab.call("_revert_numeric_field", "torso_width")
	lab.call("_set_camera_view", "+Z")
	var loaded_final: bool = lab.call(
		"_load_final_output_preview",
		FINAL_OUTPUT,
	)
	print("CLOTHING_LAB_FINAL_OUTPUT_LOADED ", loaded_final)
	for _frame in 20:
		await get_tree().process_frame
	var output_path := OUTPUT
	if "--wrist-detail" in OS.get_cmdline_user_args():
		output_path = WRIST_DETAIL_OUTPUT
		marker_root.visible = false
		orbit_camera.size = 0.42
		for _frame in 4:
			await get_tree().process_frame
	print(
		"CLOTHING_LAB_FIT_ERRORS ",
		lab.call("_fit_validation_errors"),
	)
	print("CLOTHING_LAB_FIT ", fit.to_json_data())
	var status: RichTextLabel = lab.get("_status")
	print("CLOTHING_LAB_STATUS ", status.text)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	GGCaptureEncode.encode_srgb(image)
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save Clothing Lab capture (error %d)" % error)
		get_tree().quit(1)
		return
	print("CLOTHING_LAB_CAPTURE ", output_path)
	var acceptance: CheckBox = lab.get("_accept_final_check")
	acceptance.button_pressed = true
	var final_errors: PackedStringArray = lab.call("_final_validation_errors")
	print("CLOTHING_LAB_ACCEPTED_FINAL_ERRORS ", final_errors)
	if not final_errors.is_empty():
		push_error("Reviewed Final Output did not pass acceptance gating.")
		get_tree().quit(1)
		return
	if "--publish-final" in OS.get_cmdline_user_args():
		lab.call("_publish_final_output")
		for _frame in 8:
			await get_tree().process_frame
		print("CLOTHING_LAB_PUBLISH_STATUS ", status.text)
		if not status.text.contains("READY FOR GAME"):
			push_error("Accepted Final Output did not publish for runtime.")
			get_tree().quit(1)
			return
	get_tree().quit(0)
