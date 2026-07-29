extends SceneTree
## Compares the jacket skin's inverse-bind poses with the mannequin body's
## own working skin binds for the same bones.


func _bind_for(skin: Skin, bone_name: String) -> Transform3D:
	for bind_index in skin.get_bind_count():
		if String(skin.get_bind_name(bind_index)) == bone_name:
			return skin.get_bind_pose(bind_index)
	return Transform3D.IDENTITY


func _initialize() -> void:
	var body_scene := load(
		"res://assets/3d/reworked/player_male_mannequin.glb"
	) as PackedScene
	var body_root := body_scene.instantiate()
	var body_mesh := body_root.find_child(
		"PlayerMaleBody", true, false
	) as MeshInstance3D
	var jacket_scene := load(
		"res://assets/characters/parts/top_jacket_cozy.glb"
	) as PackedScene
	var jacket_root := jacket_scene.instantiate()
	var jacket_mesh := jacket_root.find_child(
		"JacketCozy", true, false
	) as MeshInstance3D
	for bone_name in ["mixamorigHips", "mixamorigSpine2", "mixamorigLeftArm"]:
		var body_bind := _bind_for(body_mesh.skin, bone_name)
		var jacket_bind := _bind_for(jacket_mesh.skin, bone_name)
		print("BONE ", bone_name)
		print("  body   ", body_bind)
		print("  jacket ", jacket_bind)
	var skeleton := body_root.find_child("Skeleton3D", true, false) as Skeleton3D
	print("SKELETON_NODE_TRANSFORM ", skeleton.transform)
	var jacket_skeleton := jacket_root.find_child(
		"Skeleton3D", true, false
	) as Skeleton3D
	print("JACKET_SKELETON_NODE_TRANSFORM ", jacket_skeleton.transform)
	print("JACKET_MESH_TRANSFORM ", jacket_mesh.transform)
	print("BODY_MESH_TRANSFORM ", body_mesh.transform)
	body_root.free()
	jacket_root.free()
	print("SKIN_BIND_PROBE_DONE")
	quit(0)
