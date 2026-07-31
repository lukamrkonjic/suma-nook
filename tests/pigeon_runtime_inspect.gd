extends SceneTree


func _initialize() -> void:
	call_deferred("_inspect")


func _inspect() -> void:
	var packed := load("res://characters/mascots/pigeon_mascot.tscn") as PackedScene
	var mascot := packed.instantiate() as CharacterBody3D
	root.add_child(mascot)
	await process_frame
	mascot.visible = true
	print("PIGEON_ROOT scale=", mascot.scale, " aabb children=", mascot.get_child_count())
	var skeleton := mascot.get_node("Model/PigeonRig/Skeleton3D") as Skeleton3D
	for bone_name in [
		"DEF-Wing.L",
		"DEF-Wing.001.L",
		"DEF-Wing.002.L",
		"DEF-Wing.R",
		"DEF-Wing.001.R",
		"DEF-Wing.002.R",
	]:
		var bone_index := skeleton.find_bone(bone_name)
		var rest := skeleton.get_bone_global_rest(bone_index)
		print(
			"BONE ", bone_name,
			" pose=", skeleton.get_bone_pose_rotation(bone_index),
			" origin=", rest.origin,
			" x=", rest.basis.x,
			" y=", rest.basis.y,
			" z=", rest.basis.z
		)
	for child in mascot.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		var mesh := mesh_instance.mesh
		var material_rows: Array[String] = []
		if mesh != null:
			for surface in mesh.get_surface_count():
				var material := mesh_instance.get_active_material(surface)
				if material is BaseMaterial3D:
					var base := material as BaseMaterial3D
					material_rows.append(
						"%s alpha=%.3f transparency=%s" % [
							base.resource_name,
							base.albedo_color.a,
							str(base.transparency),
						]
					)
				else:
					material_rows.append(str(material))
		print(
			"MESH ",
			mascot.get_path_to(mesh_instance),
			" visible=", mesh_instance.visible,
			" tree=", mesh_instance.is_visible_in_tree(),
			" scale=", mesh_instance.global_basis.get_scale(),
			" aabb=", mesh_instance.get_aabb(),
			" mats=", material_rows
		)
	quit()
