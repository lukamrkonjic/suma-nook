extends Node

var _failures := 0


func _ready() -> void:
	var lab := (
		load("res://characters/lab/clothing_lab.tscn") as PackedScene
	).instantiate() as ClothingLab
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
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		var output_dir := "C:/Dev/suma-nook/artifacts/pigeon_review"
		DirAccess.make_dir_recursive_absolute(output_dir)
		var image := get_viewport().get_texture().get_image()
		GGCaptureEncode.encode_srgb(image)
		_check(
			image.save_png(output_dir.path_join("pigeon_clothing_lab.png")) == OK,
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
		var base: Quaternion = lab._pigeon_base_rotations[wing_index]
		lab._pigeon_rotation_controls[0].value = 24.0
		await get_tree().process_frame
		_check(
			not lab._pigeon_skeleton.get_bone_pose_rotation(wing_index).is_equal_approx(base),
			"bone rotation control poses the selected wing",
		)
		lab._reset_selected_pigeon_bone()
		_check(
			lab._pigeon_skeleton.get_bone_pose_rotation(wing_index).is_equal_approx(base),
			"bone reset restores the authored pose",
		)
	lab._rig_subject_option.select(0)
	lab._on_rig_subject_selected(0)
	await get_tree().process_frame
	_check(not lab._pigeon_mode, "human subject can be restored")
	print("PIGEON_CLOTHING_LAB failures=", _failures)
	lab.free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS ", label)
	else:
		_failures += 1
		push_error("PIGEON_CLOTHING_LAB: " + label)
