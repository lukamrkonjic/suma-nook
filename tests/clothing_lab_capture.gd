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
	if marker_root == null or marker_root.get_child_count() < 28:
		push_error("Clothing Lab full-body landmark overlay is incomplete.")
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
	var garment_toggle: CheckBox = lab.get("_show_equipped_clothing")
	var raw_preview: MeshInstance3D = lab.get("_raw_preview")
	var underlayer_preview: MeshInstance3D = lab.get("_underlayer_preview")
	if (
		garment_toggle == null
		or raw_preview == null
		or underlayer_preview == null
		or not ClothingUnderlayerBuilder.is_generated_underlayer(
			underlayer_preview
		)
	):
		push_error("Clothing Lab garment visibility control is missing.")
		get_tree().quit(1)
		return
	garment_toggle.button_pressed = false
	await get_tree().process_frame
	if raw_preview.visible or underlayer_preview.visible:
		push_error(
			"Clothing Lab did not hide the garment and fabric underlayer."
		)
		get_tree().quit(1)
		return
	garment_toggle.button_pressed = true
	await get_tree().process_frame
	if not raw_preview.visible or not underlayer_preview.visible:
		push_error(
			"Clothing Lab did not restore the garment and fabric underlayer."
		)
		get_tree().quit(1)
		return
	var detail_button: Button = lab.get("_detail_erase_button")
	if detail_button == null:
		push_error("Clothing Lab Detail Eraser control is missing.")
		get_tree().quit(1)
		return
	var detail_snapshot: Dictionary = lab.call("_capture_fit_snapshot")
	var detail_source_arrays: Array = lab.get("_raw_surface_arrays")
	var first_source_arrays := detail_source_arrays[0] as Array
	var first_source_vertices: PackedVector3Array = (
		first_source_arrays[Mesh.ARRAY_VERTEX]
	)
	var detail_vertices_before: PackedVector3Array = (
		(raw_preview.mesh as ArrayMesh).surface_get_arrays(0)[
			Mesh.ARRAY_VERTEX
		]
	)
	# The upper jacket button is a cluster of small source components centered
	# near this point. The adjacent torso panels are large components and must
	# remain stationary when the detail is erased.
	var source_center := Vector3(0.0, -0.02, 0.16)
	var fabric_sample: Dictionary = lab.call(
		"_detail_fabric_sample",
		source_center,
		Vector3(0.0, 0.0, 1.0),
		0.065,
	)
	var fabric_normal: Vector3 = fabric_sample.get(
		"fabric_normal", Vector3(0.0, 0.0, 1.0)
	)
	if float(fabric_sample.get("target_offset", -1.0)) < -0.040:
		push_error(
			"Detail Eraser sampled the garment's inside shell as fabric."
		)
		get_tree().quit(1)
		return
	fit.detail_erase_strokes.append({
		"version": 2,
		"selection": "small_source_components",
		"center": [source_center.x, source_center.y, source_center.z],
		"normal": [fabric_normal.x, fabric_normal.y, fabric_normal.z],
		"radius": 0.065,
		"strength": 1.0,
		"target_offset": float(
			fabric_sample.get("target_offset", -0.028)
		),
		"sample_uv": fabric_sample.get("sample_uv", [0.5, 0.5]),
	})
	lab.call("_preview_fit")
	await get_tree().process_frame
	var detail_vertices_after: PackedVector3Array = (
		(raw_preview.mesh as ArrayMesh).surface_get_arrays(0)[
			Mesh.ARRAY_VERTEX
		]
	)
	var maximum_detail_displacement := 0.0
	var maximum_tangent_displacement := 0.0
	var maximum_large_panel_displacement := 0.0
	var preview_fabric_normal := fabric_normal.normalized()
	for vertex_index in mini(
		detail_vertices_before.size(),
		detail_vertices_after.size(),
	):
		var displacement_vector := (
			detail_vertices_after[vertex_index]
			- detail_vertices_before[vertex_index]
		)
		var displacement := displacement_vector.length()
		var normal_displacement := (
			preview_fabric_normal
			* displacement_vector.dot(preview_fabric_normal)
		)
		maximum_tangent_displacement = maxf(
			maximum_tangent_displacement,
			(displacement_vector - normal_displacement).length(),
		)
		maximum_detail_displacement = maxf(
			maximum_detail_displacement, displacement
		)
		if absf(first_source_vertices[vertex_index].x) > 0.20:
			maximum_large_panel_displacement = maxf(
				maximum_large_panel_displacement, displacement
			)
	if (
		maximum_detail_displacement < 0.005
		or maximum_detail_displacement > 0.035
		or maximum_tangent_displacement > 0.010
		or maximum_large_panel_displacement > 0.000001
	):
		push_error(
			(
				"Detail Eraser local smoothing failed: "
				+ "detail=%f tangent=%f panel=%f"
			) % [
				maximum_detail_displacement,
				maximum_tangent_displacement,
				maximum_large_panel_displacement,
			]
		)
		get_tree().quit(1)
		return
	lab.call("_apply_fit_snapshot", detail_snapshot)
	lab.call("_set_detail_erase_mode", true)
	var detail_pick := {
		"local_position": detail_vertices_before[0],
		"local_normal": Vector3.BACK,
		"source_position": source_center,
		"source_normal": Vector3.BACK,
	}
	lab.call("_update_detail_brush_cursor_from_pick", detail_pick)
	await get_tree().process_frame
	marker_root = lab.get("_marker_root")
	var detail_cursor: MeshInstance3D = lab.get("_detail_brush_cursor")
	if (
		not bool(lab.get("_detail_erase_enabled"))
		or marker_root.visible
		or not raw_preview.visible
		or detail_cursor == null
		or not detail_cursor.visible
	):
		push_error(
			(
				"Detail Eraser mode failed: enabled=%s markers=%s raw=%s "
				+ "cursor=%s cursor_visible=%s"
			) % [
				lab.get("_detail_erase_enabled"),
				marker_root.visible,
				raw_preview.visible,
				detail_cursor != null,
				(
					detail_cursor.visible
					if detail_cursor != null
					else false
				),
			]
		)
		get_tree().quit(1)
		return
	lab.call("_set_detail_erase_mode", false)
	var smoothing_slider: HSlider = lab.get("_surface_smoothing_slider")
	if smoothing_slider == null:
		push_error("Clothing Lab surface-smoothing slider is missing.")
		get_tree().quit(1)
		return
	var mesh_before := raw_preview.mesh as ArrayMesh
	var arrays_before := mesh_before.surface_get_arrays(0)
	var vertices_before: PackedVector3Array = arrays_before[Mesh.ARRAY_VERTEX]
	var normals_before: PackedVector3Array = arrays_before[Mesh.ARRAY_NORMAL]
	var smoothing_assembler: CharacterAssembler = lab.get("assembler")
	var smoothing_selected_part := (
		lab.get("_selected_part") as CharacterPartDefinition
	)
	var bound_garment := smoothing_assembler.equipped_node(
		smoothing_selected_part.slot
	) as MeshInstance3D
	var bound_source_mesh := bound_garment.mesh
	smoothing_slider.value = 0.01
	await get_tree().process_frame
	var one_percent_arrays := (
		(raw_preview.mesh as ArrayMesh).surface_get_arrays(0)
	)
	var one_percent_normals: PackedVector3Array = (
		one_percent_arrays[Mesh.ARRAY_NORMAL]
	)
	var minimum_zero_to_one_dot := 1.0
	for normal_index in mini(
		normals_before.size(),
		one_percent_normals.size(),
	):
		minimum_zero_to_one_dot = minf(
			minimum_zero_to_one_dot,
			normals_before[normal_index].dot(
				one_percent_normals[normal_index]
			),
		)
	if (
		normals_before.size() != vertices_before.size()
		or one_percent_normals.size() != vertices_before.size()
		or minimum_zero_to_one_dot < 0.999
	):
		push_error(
			"Surface smoothing is discontinuous between 0% and 1%."
		)
		get_tree().quit(1)
		return
	smoothing_slider.value = 0.65
	await get_tree().process_frame
	var mesh_smoothed := raw_preview.mesh as ArrayMesh
	var arrays_smoothed := mesh_smoothed.surface_get_arrays(0)
	var vertices_smoothed: PackedVector3Array = (
		arrays_smoothed[Mesh.ARRAY_VERTEX]
	)
	var normals_smoothed: PackedVector3Array = (
		arrays_smoothed[Mesh.ARRAY_NORMAL]
	)
	var bound_smoothed_arrays := bound_garment.mesh.surface_get_arrays(0)
	var bound_smoothed_vertices: PackedVector3Array = (
		bound_smoothed_arrays[Mesh.ARRAY_VERTEX]
	)
	var bound_smoothed_bones: PackedInt32Array = (
		bound_smoothed_arrays[Mesh.ARRAY_BONES]
	)
	var bound_smoothed_weights: PackedFloat32Array = (
		bound_smoothed_arrays[Mesh.ARRAY_WEIGHTS]
	)
	if (
		not is_equal_approx(fit.surface_smoothing, 0.65)
		or vertices_smoothed != vertices_before
		or normals_smoothed.size() != vertices_smoothed.size()
		or bound_garment.mesh == bound_source_mesh
		or bound_smoothed_bones.size()
		!= bound_smoothed_vertices.size() * 4
		or bound_smoothed_weights.size()
		!= bound_smoothed_vertices.size() * 4
	):
		push_error(
			"Live smoothing failed raw/bound preview or damaged skin data."
		)
		get_tree().quit(1)
		return
	smoothing_slider.value = 0.0
	await get_tree().process_frame
	if bound_garment.mesh != bound_source_mesh:
		push_error("Zero smoothing did not restore the authored bound mesh.")
		get_tree().quit(1)
		return
	var marker_region_preview: CheckBox = lab.get("_preview_hidden_regions")
	var marker_body_mesh := lab.get("_character").find_child(
		"PlayerMaleBody", true, false
	) as MeshInstance3D
	lab.call("_set_marker_edit_mode", true)
	var marker_editor: VBoxContainer = lab.get("_marker_editor")
	var marker_toggle: CheckBox = lab.get("_marker_toggle")
	var marker_nodes: Dictionary = lab.get("_marker_nodes")
	var marker_group_option: OptionButton = lab.get("_marker_group_option")
	var marker_option: OptionButton = lab.get("_marker_option")
	var landmarks_before: Dictionary = (
		lab.get("_landmarks") as Dictionary
	).duplicate(true)
	var required_full_body_markers := [
		"center.crown",
		"center.head",
		"center.face",
		"center.neck",
		"center.chest",
		"center.abdomen",
		"center.waist",
		"center.hips",
		"left.clavicle",
		"left.shoulder",
		"left.elbow",
		"left.wrist",
		"left.hand",
		"right.clavicle",
		"right.shoulder",
		"right.elbow",
		"right.wrist",
		"right.hand",
		"left.hip",
		"left.knee",
		"left.ankle",
		"left.foot",
		"left.toe",
		"right.hip",
		"right.knee",
		"right.ankle",
		"right.foot",
		"right.toe",
	]
	for marker_key in required_full_body_markers:
		if not marker_nodes.has(marker_key):
			push_error("Missing full-body clothing marker: %s" % marker_key)
			get_tree().quit(1)
			return
	var crown_marker := marker_nodes["center.crown"] as MeshInstance3D
	var face_marker := marker_nodes["center.face"] as MeshInstance3D
	var hips_marker := marker_nodes["center.hips"] as MeshInstance3D
	var ankle_marker := marker_nodes["left.ankle"] as MeshInstance3D
	if (
		crown_marker.position.y <= face_marker.position.y
		or face_marker.position.y <= hips_marker.position.y
		or ankle_marker.position.y >= hips_marker.position.y
		or absf(crown_marker.position.z) >= 0.08
		or absf(face_marker.position.z) >= 0.08
	):
		push_error(
			"Clothing Lab rig markers are not in Godot Y-up character space."
		)
		get_tree().quit(1)
		return
	if (
		marker_editor == null
		or not marker_editor.visible
		or marker_toggle == null
		or not marker_toggle.disabled
		or marker_group_option == null
		or marker_group_option.item_count != 5
		or marker_option == null
		or "base of skull" not in marker_option.get_item_text(
			marker_option.selected
		).to_lower()
		or garment_toggle.button_pressed
		or not garment_toggle.disabled
		or raw_preview.visible
		or marker_region_preview.button_pressed
		or not marker_region_preview.disabled
		or int(
			marker_body_mesh.get_instance_shader_parameter("hide_mask")
		) != 0
	):
		push_error(
			"Clothing Lab rig-marker mode did not isolate the complete body."
		)
		get_tree().quit(1)
		return
	var active_body_profile: CharacterBodyProfile = lab.call("_active_body_profile")
	if (
		active_body_profile == null
		or not active_body_profile.resource_path.begins_with(
			"res://assets/characters/body_profiles/"
		)
	):
		push_error("Rig markers are not owned by the global body profile.")
		get_tree().quit(1)
		return
	var lab_assembler: CharacterAssembler = lab.get("assembler")
	for clothing_slot in [
		CharacterSlots.TOP_INNER,
		CharacterSlots.TOP_OUTER,
		CharacterSlots.BOTTOM,
		CharacterSlots.SHOES,
		CharacterSlots.GLOVES,
		CharacterSlots.HEADWEAR,
	]:
		var equipped := lab_assembler.equipped_node(clothing_slot)
		if equipped != null and equipped.visible:
			push_error(
				"Rig-marker mode left clothing slot %s visible."
				% clothing_slot
			)
			get_tree().quit(1)
			return
	var left_shoulder := marker_nodes["left.shoulder"] as MeshInstance3D
	var marker_screen := orbit_camera.unproject_position(
		left_shoulder.global_position
	)
	if not bool(lab.call("_begin_marker_drag", marker_screen)):
		push_error("Clothing Lab could not pick a visible rig marker.")
		get_tree().quit(1)
		return
	lab.call("_drag_marker", marker_screen + Vector2(14.0, -8.0))
	lab.call("_end_marker_drag", true)
	var landmarks_after: Dictionary = lab.get("_landmarks")
	var left_after: Vector3 = (
		landmarks_after["left"] as Dictionary
	)["shoulder"]
	var right_after: Vector3 = (
		landmarks_after["right"] as Dictionary
	)["shoulder"]
	var left_before: Vector3 = (
		landmarks_before["left"] as Dictionary
	)["shoulder"]
	if (
		left_after.distance_to(left_before) < 0.0001
		or not is_equal_approx(right_after.x, -left_after.x)
		or not is_equal_approx(right_after.y, left_after.y)
		or not is_equal_approx(right_after.z, left_after.z)
	):
		push_error("Clothing Lab marker drag or bilateral mirroring failed.")
		get_tree().quit(1)
		return
	lab.call("_undo")
	var landmarks_undone: Dictionary = lab.get("_landmarks")
	var left_undone: Vector3 = (
		landmarks_undone["left"] as Dictionary
	)["shoulder"]
	if left_undone.distance_to(left_before) > 0.00001:
		push_error("Clothing Lab marker drag was not restored by undo.")
		get_tree().quit(1)
		return
	marker_nodes = lab.get("_marker_nodes")
	left_shoulder = marker_nodes["left.shoulder"] as MeshInstance3D
	marker_screen = orbit_camera.unproject_position(left_shoulder.global_position)
	var x_key := InputEventKey.new()
	x_key.keycode = KEY_X
	x_key.physical_keycode = KEY_X
	x_key.pressed = true
	Input.parse_input_event(x_key)
	await get_tree().process_frame
	if not bool(lab.call("_begin_marker_drag", marker_screen)):
		push_error("Clothing Lab could not begin an axis-constrained drag.")
		get_tree().quit(1)
		return
	lab.call("_drag_marker", marker_screen + Vector2(24.0, 7.0))
	lab.call("_end_marker_drag", true)
	x_key.pressed = false
	Input.parse_input_event(x_key)
	await get_tree().process_frame
	var x_locked_landmarks: Dictionary = lab.get("_landmarks")
	var x_locked_left: Vector3 = (
		x_locked_landmarks["left"] as Dictionary
	)["shoulder"]
	if (
		is_equal_approx(x_locked_left.x, left_before.x)
		or not is_equal_approx(x_locked_left.y, left_before.y)
		or not is_equal_approx(x_locked_left.z, left_before.z)
	):
		push_error("Holding X did not constrain marker drag to the X axis.")
		get_tree().quit(1)
		return
	lab.call("_undo")
	lab.call("_set_marker_edit_mode", false)
	if (
		marker_editor.visible
		or marker_toggle.disabled
		or not garment_toggle.button_pressed
		or garment_toggle.disabled
		or not raw_preview.visible
		or not marker_region_preview.button_pressed
		or marker_region_preview.disabled
	):
		push_error(
			"Clothing Lab rig-marker mode did not restore preview visibility."
		)
		get_tree().quit(1)
		return
	marker_root = lab.get("_marker_root")
	var pose_option: OptionButton = lab.get("_preview_pose_option")
	if pose_option == null or pose_option.item_count < 6:
		push_error("Clothing Lab pose/animation dropdown is incomplete.")
		get_tree().quit(1)
		return
	var walk_index := -1
	for pose_index in pose_option.item_count:
		if String(pose_option.get_item_metadata(pose_index)) == "walk":
			walk_index = pose_index
			break
	if walk_index < 0:
		push_error("Clothing Lab pose dropdown has no walk preview.")
		get_tree().quit(1)
		return
	raw_preview = lab.get("_raw_preview")
	underlayer_preview = lab.get("_underlayer_preview")
	var speed_slider: HSlider = lab.get("_preview_speed_slider")
	if speed_slider == null:
		push_error("Clothing Lab animation-speed slider is missing.")
		get_tree().quit(1)
		return
	speed_slider.value = 0.5
	pose_option.select(walk_index)
	lab.call("_on_preview_pose_selected", walk_index)
	for _frame in 4:
		await get_tree().process_frame
	var preview_character := lab.get("_character") as Node3D
	var preview_animation_player := preview_character.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	var preview_skeleton := preview_character.find_child(
		"Skeleton3D", true, false
	) as Skeleton3D
	var preview_mode: OptionButton = lab.get("_preview_mode_option")
	var selected_part := lab.get("_selected_part") as CharacterPartDefinition
	var live_bound_garment := (
		lab_assembler.equipped_node(selected_part.slot)
		if selected_part != null
		else null
	)
	if (
		preview_animation_player == null
		or preview_animation_player.assigned_animation != "walk"
		or not preview_animation_player.is_playing()
		or not is_equal_approx(preview_animation_player.speed_scale, 0.5)
	):
		push_error(
			"Clothing Lab walk animation preview did not play at the "
			+ "selected speed."
		)
		get_tree().quit(1)
		return
	if (
		preview_mode == null
		or preview_mode.selected != 1
		or raw_preview.visible
		or underlayer_preview.visible
		or live_bound_garment == null
		or not live_bound_garment.visible
		or live_bound_garment.get_parent() != preview_skeleton
		or (live_bound_garment as MeshInstance3D).skeleton != NodePath("..")
	):
		push_error(
			"Animated preview did not replace the static Raw Fit with the "
			+ "garment bound to the live body skeleton."
		)
		get_tree().quit(1)
		return
	var lowest_walk_toe_y := INF
	for toe_name in ["mixamorigLeftToeBase", "mixamorigRightToeBase"]:
		var toe_index := preview_skeleton.find_bone(toe_name)
		if toe_index >= 0:
			var toe_world := (
				preview_skeleton.global_transform
				* preview_skeleton.get_bone_global_pose(toe_index)
			).origin
			lowest_walk_toe_y = minf(lowest_walk_toe_y, toe_world.y)
	if (
		is_inf(lowest_walk_toe_y)
		or lowest_walk_toe_y < -0.01
		or lowest_walk_toe_y > 0.06
	):
		push_error(
			"Animated Clothing Lab preview is not grounded at the feet "
			+ "(lowest toe %.3f m)." % lowest_walk_toe_y
		)
		get_tree().quit(1)
		return
	pose_option.select(0)
	lab.call("_on_preview_pose_selected", 0)
	if (
		preview_animation_player.is_playing()
		or preview_mode.selected != 0
		or not raw_preview.visible
		or live_bound_garment.visible
	):
		push_error("Clothing Lab rest-pose selection did not stop animation.")
		get_tree().quit(1)
		return
	var scale_lock: CheckBox = lab.get("_lock_scale_proportions")
	var vector_controls: Dictionary = lab.get("_vector_controls")
	var scale_controls := vector_controls["scale"] as Array
	var original_scale := fit.scale
	if scale_lock == null or not scale_lock.button_pressed:
		push_error("Clothing Lab proportional XYZ scale lock is missing.")
		get_tree().quit(1)
		return
	(scale_controls[0] as SpinBox).value = original_scale.x * 1.1
	await get_tree().process_frame
	var scale_factor := fit.scale.x / original_scale.x
	if (
		not is_equal_approx(fit.scale.y, original_scale.y * scale_factor)
		or not is_equal_approx(fit.scale.z, original_scale.z * scale_factor)
	):
		push_error("Clothing Lab XYZ scale lock did not preserve proportions.")
		get_tree().quit(1)
		return
	lab.call("_undo")
	if fit.scale.distance_to(original_scale) > 0.00001:
		push_error("Clothing Lab proportional scale edit was not undoable.")
		get_tree().quit(1)
		return
	marker_root = lab.get("_marker_root")
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
	lab.call("_input", middle_press)
	await get_tree().process_frame
	if not bool(lab.get("_orbiting")):
		push_error("Clothing Lab input-routed MMB did not begin orbiting.")
		get_tree().quit(1)
		return
	var middle_motion := InputEventMouseMotion.new()
	middle_motion.relative = Vector2(18.0, -12.0)
	before_orbit = orbit_camera.position
	lab.call("_input", middle_motion)
	await get_tree().process_frame
	var middle_release := InputEventMouseButton.new()
	middle_release.button_index = MOUSE_BUTTON_MIDDLE
	middle_release.pressed = false
	middle_release.position = middle_press.position
	lab.call("_input", middle_release)
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
	if loaded_final:
		pose_option.select(walk_index)
		lab.call("_on_preview_pose_selected", walk_index)
		for _frame in 5:
			await get_tree().process_frame
		var source_skeleton := lab.get("_character").find_child(
			"Skeleton3D", true, false
		) as Skeleton3D
		var final_root := lab.get("_final_preview_root") as Node3D
		var final_skeleton := final_root.find_child(
			"Skeleton3D", true, false
		) as Skeleton3D
		var source_forearm := source_skeleton.find_bone(
			"mixamorigLeftForeArm"
		)
		var final_forearm := final_skeleton.find_bone(
			"mixamorigLeftForeArm"
		)
		if (
			source_forearm < 0
			or final_forearm < 0
			or source_skeleton.get_bone_pose_rotation(
				source_forearm
			).angle_to(
				final_skeleton.get_bone_pose_rotation(final_forearm)
			) > 0.01
		):
			push_error(
				"Bound Final Output did not follow the selected animation."
			)
			get_tree().quit(1)
			return
		pose_option.select(0)
		lab.call("_on_preview_pose_selected", 0)
		for _frame in 2:
			await get_tree().process_frame
	var output_path := OUTPUT
	var region_detail := ""
	var capture_underlayer_walk := false
	var capture_underlayer_three_quarter := false
	var capture_animated_underside := false
	var capture_smoothing_preview := false
	var capture_rig_markers := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--region-detail="):
			region_detail = argument.trim_prefix("--region-detail=")
		elif argument == "--underlayer-walk":
			capture_underlayer_walk = true
		elif argument == "--underlayer-walk-3q":
			capture_underlayer_walk = true
			capture_underlayer_three_quarter = true
		elif argument == "--animated-underside":
			capture_animated_underside = true
		elif argument == "--smoothing-preview":
			capture_smoothing_preview = true
		elif argument == "--rig-markers":
			capture_rig_markers = true
	if capture_rig_markers:
		output_path = (
			"res://artifacts/character_lab/"
			+ "clothing_lab_rig_markers.png"
		)
		lab.call("_set_marker_edit_mode", true)
		lab.call("_set_camera_view", "3Q")
		orbit_camera.size = 0.68
		pose_option.select(0)
		lab.call("_on_preview_pose_selected", 0)
		for _frame in 4:
			await get_tree().process_frame
	elif capture_smoothing_preview:
		output_path = (
			"res://artifacts/character_lab/"
			+ "clothing_lab_smoothing_100.png"
		)
		smoothing_slider.value = 1.0
		marker_root = lab.get("_marker_root")
		marker_root.visible = false
		lab.call("_set_camera_view", "+Z")
		orbit_camera.size = 0.42
		pose_option.select(0)
		lab.call("_on_preview_pose_selected", 0)
		var smoothing_mode := lab.get(
			"_preview_mode_option"
		) as OptionButton
		smoothing_mode.select(0)
		lab.call("_on_preview_mode_selected", 0)
		for _frame in 4:
			await get_tree().process_frame
	elif not region_detail.is_empty():
		for check: CheckBox in region_checks.values():
			check.button_pressed = false
		if region_detail == "clavicles":
			(region_checks["clavicle_l"] as CheckBox).button_pressed = true
			(region_checks["clavicle_r"] as CheckBox).button_pressed = true
		elif region_checks.has(region_detail):
			(region_checks[region_detail] as CheckBox).button_pressed = true
		else:
			push_error("Unknown Clothing Lab region detail: %s" % region_detail)
			get_tree().quit(1)
			return
		lab.call("_apply_body_mask")
		output_path = (
			"res://artifacts/character_lab/clothing_lab_region_%s.png"
			% region_detail
		)
		marker_root.visible = false
		var detail_camera := lab.call("_active_preview_camera") as Camera3D
		detail_camera.size = 0.42
		for _frame in 4:
			await get_tree().process_frame
	elif "--wrist-detail" in OS.get_cmdline_user_args():
		output_path = WRIST_DETAIL_OUTPUT
		marker_root.visible = false
		orbit_camera.size = 0.42
		for _frame in 4:
			await get_tree().process_frame
	if capture_underlayer_walk:
		output_path = (
			"res://artifacts/character_lab/"
			+ "clothing_lab_underlayer_walk.png"
		)
		marker_root = lab.get("_marker_root")
		if marker_root != null and is_instance_valid(marker_root):
			marker_root.visible = false
		lab.call(
			"_set_camera_view",
			"3Q" if capture_underlayer_three_quarter else "+Z",
		)
		orbit_camera.size = 0.68
		pose_option.select(walk_index)
		lab.call("_on_preview_pose_selected", walk_index)
		preview_animation_player.seek(0.34, true)
		lab.call("_sync_final_output_pose")
		for _frame in 3:
			await get_tree().process_frame
	elif capture_animated_underside:
		output_path = (
			"res://artifacts/character_lab/"
			+ "clothing_lab_animated_underside.png"
		)
		marker_root = lab.get("_marker_root")
		if marker_root != null and is_instance_valid(marker_root):
			marker_root.visible = false
		lab.set("_orbit_yaw", deg_to_rad(32.0))
		lab.set("_orbit_pitch", deg_to_rad(-28.0))
		lab.call("_update_orbit_camera")
		orbit_camera.size = 0.36
		pose_option.select(walk_index)
		lab.call("_on_preview_pose_selected", walk_index)
		preview_animation_player.seek(0.34, true)
		lab.call("_sync_final_output_pose")
		for _frame in 3:
			await get_tree().process_frame
	print(
		"CLOTHING_LAB_FIT_ERRORS ",
		lab.call("_fit_validation_errors"),
	)
	var advisory_warnings: PackedStringArray = lab.call(
		"_fit_diagnostic_warnings"
	)
	var technical_bind_errors: PackedStringArray = lab.call(
		"_technical_bind_errors"
	)
	for advisory in advisory_warnings:
		if technical_bind_errors.has(advisory):
			push_error(
				"Clothing Lab advisory warning still blocks binding: %s"
				% advisory
			)
			get_tree().quit(1)
			return
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
	if (
		not region_detail.is_empty()
		or capture_smoothing_preview
		or capture_rig_markers
	):
		get_tree().quit(0)
		return
	var acceptance: CheckBox = lab.get("_accept_final_check")
	var final_errors: PackedStringArray = lab.call("_final_validation_errors")
	print("CLOTHING_LAB_ACCEPTED_FINAL_ERRORS ", final_errors)
	if not final_errors.is_empty():
		push_error("A built Final Output was incorrectly blocked by advice.")
		get_tree().quit(1)
		return
	acceptance.button_pressed = true
	if "--publish-final" in OS.get_cmdline_user_args():
		lab.call("_publish_final_output")
		for _frame in 8:
			await get_tree().process_frame
		print("CLOTHING_LAB_PUBLISH_STATUS ", status.text)
		if not status.text.contains("READY FOR STEP 4"):
			push_error("Accepted Final Output did not publish for runtime.")
			get_tree().quit(1)
			return
	get_tree().quit(0)
