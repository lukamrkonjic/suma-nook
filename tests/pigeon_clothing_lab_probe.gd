extends Node

const RIG_PROFILE_TEST_PATH := "user://pigeon_rig_profile_probe.json"

var _failures := 0


func _ready() -> void:
	var lab := (
		load("res://characters/lab/clothing_lab.tscn") as PackedScene
	).instantiate() as ClothingLab
	if FileAccess.file_exists(RIG_PROFILE_TEST_PATH):
		DirAccess.remove_absolute(RIG_PROFILE_TEST_PATH)
	lab._pigeon_rig_profile_path_override = RIG_PROFILE_TEST_PATH
	add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame
	lab._rig_subject_option.select(1)
	lab._on_rig_subject_selected(1)
	await get_tree().process_frame
	_check(lab._pigeon_mode, "pigeon subject mode activates")
	_check(lab._character != null and lab._character.visible, "pigeon is visible in the lab")
	_check(lab._pigeon_skeleton != null, "Rigify skeleton is exposed")
	_check(
		lab._pigeon_skeleton != null and lab._pigeon_skeleton.get_bone_count() >= 70,
		"complete bird deformation rig is available",
	)
	_check(
		lab._pigeon_bone_option.item_count >= 20,
		"DEF bones populate the rig editor",
	)
	_check(
		lab._pigeon_marker_root != null and lab._pigeon_marker_root.visible,
		"bird joint dots are visible",
	)
	_check(
		lab._pigeon_bone_markers.size() >= 28,
		"meaningful bird joints receive fitting dots",
	)
	_check(
		lab._pigeon_right_panel.visible and not lab._human_right_panel.visible,
		"right panel changes to pigeon-specific controls",
	)
	_check(
		lab._pigeon_right_panel.is_ancestor_of(lab._pigeon_rig_tools),
		"bird rig controls live in the normal right-hand rig sidebar",
	)
	_check(
		lab._pigeon_left_panel.visible and not lab._human_left_panel.visible,
		"pigeon mode hides the irrelevant human appearance controls on the left",
	)
	_check(
		lab._pigeon_animation_option.item_count == 5,
		"rest, idle, walk, fly, and fishing previews are offered",
	)
	lab._pigeon_show_bones.set_pressed_no_signal(false)
	lab._update_pigeon_marker_visibility()
	_check(not lab._pigeon_marker_root.visible, "bird markers can be hidden")
	lab._pigeon_show_bones.set_pressed_no_signal(true)
	lab._update_pigeon_marker_visibility()
	_check(lab._pigeon_marker_root.visible, "bird markers can be restored")
	if "--capture" in OS.get_cmdline_user_args():
		_check(
			await _capture_review("pigeon_clothing_lab.png"),
			"Clothing Lab review capture writes",
		)
	var wing_index := lab._pigeon_skeleton.find_bone("DEF-Wing.L")
	var wing_option := -1
	for option_index in lab._pigeon_bone_option.item_count:
		if int(lab._pigeon_bone_option.get_item_metadata(option_index)) == wing_index:
			wing_option = option_index
			break
	_check(wing_option >= 0, "left wing is selectable")
	if wing_option >= 0:
		_check(
			lab._pigeon_bone_markers.has(wing_index),
			"left wing has a selectable joint dot",
		)
		var wing_marker := (
			lab._pigeon_bone_markers[wing_index] as MeshInstance3D
		)
		_check(
			wing_marker.position.is_equal_approx(
				lab._pigeon_marker_applied_origins[wing_index]
			),
			"bird marker starts on its stable anatomical handle",
		)
		_check(
			wing_marker.position.y > -0.12
			and absf(wing_marker.position.x) > 0.18,
			"wing handle sits on the visible wing instead of its hidden DEF pivot",
		)
		var preview_camera := lab._active_preview_camera()
		_check(
			preview_camera != null
			and wing_marker != null
			and lab._select_pigeon_bone_marker(
				preview_camera.unproject_position(wing_marker.global_position)
			),
			"clicking a joint dot selects it",
		)
		_check(
			lab._selected_pigeon_bone_index() == wing_index,
			"joint dot targets its bird bone",
		)
		var paired_wing_index := lab._pigeon_skeleton.find_bone("DEF-Wing.R")
		var base_position: Vector3 = lab._pigeon_base_positions[wing_index]
		var marker_start := wing_marker.position
		lab._set_pigeon_marker_edit_mode(true)
		var marker_screen := preview_camera.unproject_position(
			wing_marker.global_position
		)
		var began_drag := lab._begin_pigeon_marker_drag(marker_screen)
		if began_drag:
			lab._drag_pigeon_marker(marker_screen + Vector2(24.0, -12.0))
			lab._end_pigeon_marker_drag(true)
		var position_offset: Vector3 = lab._pigeon_bone_position_offsets.get(
			wing_index,
			Vector3.ZERO,
		)
		var mirrored_offset: Vector3 = lab._pigeon_bone_position_offsets.get(
			paired_wing_index,
			Vector3.ZERO,
		)
		_check(began_drag, "edit mode begins a drag from a visible bird joint")
		_check(position_offset.length() > 0.002, "dragging changes the bird joint position")
		_check(
			mirrored_offset.is_equal_approx(
				Vector3(-position_offset.x, position_offset.y, position_offset.z)
			),
			"paired bird joints mirror position edits",
		)
		_check(
			lab._pigeon_skeleton.get_bone_pose_position(wing_index).is_equal_approx(
				base_position
			),
			"joint dragging leaves the bird unchanged before Save + Apply",
		)
		_check(
			not wing_marker.position.is_equal_approx(marker_start),
			"the selected rig marker follows its edited joint",
		)
		lab._save_and_apply_pigeon_rig_draft()
		_check(
			FileAccess.file_exists(RIG_PROFILE_TEST_PATH),
			"Save + Apply persists the bird rig draft",
		)
		_check(
			not lab._pigeon_skeleton.get_bone_pose_position(wing_index).is_equal_approx(
				base_position
			),
			"Save + Apply deforms the live DEF bone once",
		)
		var runtime_mascot := (
			load("res://characters/mascots/pigeon_mascot.tscn") as PackedScene
		).instantiate() as CharacterBody3D
		var runtime_skeleton := runtime_mascot.get_node(
			"Model/PigeonRig/Skeleton3D"
		) as Skeleton3D
		var runtime_wing_index := runtime_skeleton.find_bone("DEF-Wing.L")
		var runtime_base_position := runtime_skeleton.get_bone_pose_position(
			runtime_wing_index
		)
		runtime_mascot.set_meta(
			"pigeon_rig_profile_path",
			RIG_PROFILE_TEST_PATH,
		)
		add_child(runtime_mascot)
		await get_tree().process_frame
		_check(
			not runtime_skeleton.get_bone_pose_position(
				runtime_wing_index
			).is_equal_approx(runtime_base_position),
			"new runtime pigeons load the saved rig profile",
		)
		runtime_mascot.free()
		var saved_position := lab._pigeon_skeleton.get_bone_pose_position(wing_index)
		lab._select_pigeon_bone_index(wing_index)
		lab._reset_selected_pigeon_bone()
		_check(
			lab._pigeon_skeleton.get_bone_pose_position(wing_index).is_equal_approx(
				saved_position
			),
			"reset edits only the draft until it is saved",
		)
		lab._save_and_apply_pigeon_rig_draft()
		_check(
			lab._pigeon_skeleton.get_bone_pose_position(wing_index).is_equal_approx(
				base_position
			),
			"saving the reset restores the authored joint position",
		)
		lab._set_pigeon_marker_edit_mode(false)
		var base: Quaternion = lab._pigeon_base_rotations[wing_index]
		lab._pigeon_rotation_controls[0].value = 24.0
		await get_tree().process_frame
		_check(
			lab._pigeon_skeleton.get_bone_pose_rotation(wing_index).is_equal_approx(base),
			"rotation controls also remain staged before Save + Apply",
		)
		lab._save_and_apply_pigeon_rig_draft()
		_check(
			not lab._pigeon_skeleton.get_bone_pose_rotation(wing_index).is_equal_approx(base),
			"Save + Apply commits the staged bone rotation",
		)
		lab._reset_selected_pigeon_bone()
		lab._save_and_apply_pigeon_rig_draft()
		_check(
			lab._pigeon_skeleton.get_bone_pose_rotation(wing_index).is_equal_approx(base),
			"bone reset restores the authored pose",
		)
	var head_index := lab._pigeon_skeleton.find_bone("DEF-head")
	var wing_mid_index := lab._pigeon_skeleton.find_bone("DEF-Wing.001.L")
	var thigh_index := lab._pigeon_skeleton.find_bone("DEF-thigh.L")
	var idle_index := _pigeon_animation_index(lab, "idle")
	var walk_index := _pigeon_animation_index(lab, "walk")
	var fly_index := _pigeon_animation_index(lab, "fly")
	var fishing_index := _pigeon_animation_index(lab, "fishing")
	_check(
		idle_index >= 0 and walk_index >= 0 and fly_index >= 0 and fishing_index >= 0,
		"all requested pigeon animations are selectable",
	)
	if idle_index >= 0:
		lab._pigeon_animation_option.select(idle_index)
		lab._on_pigeon_animation_selected(idle_index)
		lab._pigeon_animation_time = 0.7
		lab._update_pigeon_animation_preview(0.0)
		_check(
			not lab._pigeon_skeleton.get_bone_pose_rotation(head_index).is_equal_approx(
				lab._pigeon_base_rotations[head_index]
			),
			"idle preview animates the bird's curious head movement",
		)
		_check(
			not lab._pigeon_skeleton.get_bone_pose_rotation(wing_mid_index).is_equal_approx(
				lab._pigeon_base_rotations[wing_mid_index]
			),
			"idle preview folds the complete wing chain backward",
		)
		_check(
			not lab._pigeon_marker_root.visible,
			"motion previews hide rig markers like the human preview",
		)
		if "--capture" in OS.get_cmdline_user_args():
			_check(
				await _capture_review("pigeon_clothing_lab_idle.png"),
				"idle preview capture writes",
			)
	if walk_index >= 0:
		lab._pigeon_animation_option.select(walk_index)
		lab._on_pigeon_animation_selected(walk_index)
		lab._pigeon_animation_time = 0.65
		lab._update_pigeon_animation_preview(0.0)
		_check(
			absf(lab._character.position.x - lab._pigeon_preview_origin.x) > 0.1,
			"walk preview moves between two stage positions",
		)
		_check(
			not lab._pigeon_skeleton.get_bone_pose_rotation(thigh_index).is_equal_approx(
				lab._pigeon_base_rotations[thigh_index]
			),
			"walk preview alternates the bird's legs",
		)
		if "--capture" in OS.get_cmdline_user_args():
			_check(
				await _capture_review("pigeon_clothing_lab_walk.png"),
				"walk preview capture writes",
			)
	if fly_index >= 0:
		lab._pigeon_animation_option.select(fly_index)
		lab._on_pigeon_animation_selected(fly_index)
		lab._pigeon_animation_time = ClothingLab.PIGEON_FLIGHT_PREVIEW_SECONDS * 0.5
		lab._update_pigeon_animation_preview(0.0)
		_check(
			lab._character.position.y > lab._pigeon_preview_origin.y + 0.18,
			"flight preview follows a takeoff-to-landing arc",
		)
		_check(
			not lab._pigeon_skeleton.get_bone_pose_rotation(wing_index).is_equal_approx(
				lab._pigeon_base_rotations[wing_index]
			),
			"flight preview flaps the Rigify wings",
		)
		if "--capture" in OS.get_cmdline_user_args():
			_check(
				await _capture_review("pigeon_clothing_lab_fly.png"),
				"flight preview capture writes",
			)
	if fishing_index >= 0:
		lab._pigeon_animation_option.select(fishing_index)
		lab._on_pigeon_animation_selected(fishing_index)
		lab._pigeon_animation_time = 0.36
		lab._update_pigeon_animation_preview(0.0)
		_check(
			not lab._pigeon_skeleton.get_bone_pose_rotation(head_index).is_equal_approx(
				lab._pigeon_base_rotations[head_index]
			),
			"fishing preview leans toward the bobber",
		)
		_check(
			not lab._pigeon_skeleton.get_bone_pose_rotation(wing_index).is_equal_approx(
				lab._pigeon_base_rotations[wing_index]
			),
			"fishing preview includes a casting wing motion",
		)
		if "--capture" in OS.get_cmdline_user_args():
			_check(
				await _capture_review("pigeon_clothing_lab_fishing.png"),
				"fishing preview capture writes",
			)
	lab._pigeon_animation_option.select(0)
	lab._on_pigeon_animation_selected(0)
	_check(
		lab._pigeon_marker_root.visible and not lab._pigeon_bone_option.disabled,
		"rest mode restores rig markers and manual bone controls",
	)
	lab._rig_subject_option.select(0)
	lab._on_rig_subject_selected(0)
	await get_tree().process_frame
	_check(not lab._pigeon_mode, "human subject can be restored")
	_check(
		lab._human_right_panel.visible and not lab._pigeon_right_panel.visible,
		"human Fit & Bind panel is restored",
	)
	print("PIGEON_CLOTHING_LAB failures=", _failures)
	lab.free()
	if FileAccess.file_exists(RIG_PROFILE_TEST_PATH):
		DirAccess.remove_absolute(RIG_PROFILE_TEST_PATH)
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS ", label)
	else:
		_failures += 1
		push_error("PIGEON_CLOTHING_LAB: " + label)


func _pigeon_animation_index(lab: ClothingLab, animation_name: String) -> int:
	for index in lab._pigeon_animation_option.item_count:
		if String(
			lab._pigeon_animation_option.get_item_metadata(index)
		) == animation_name:
			return index
	return -1


func _capture_review(file_name: String) -> bool:
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var output_dir := "C:/Dev/suma-nook/artifacts/pigeon_review"
	DirAccess.make_dir_recursive_absolute(output_dir)
	var image := get_viewport().get_texture().get_image()
	GGCaptureEncode.encode_srgb(image)
	return image.save_png(output_dir.path_join(file_name)) == OK
