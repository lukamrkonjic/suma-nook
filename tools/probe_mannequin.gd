extends SceneTree
## Contract probe for the mannequin GLB + assembled default appearance.
## Prints animations, bones, socket tree, and part attachment results.
##
## Run:
##   godot --headless --path . --script res://tools/probe_mannequin.gd

const PRESET := "res://assets/characters/presets/default_male_appearance.tres"


func _initialize() -> void:
	var preset := load(PRESET) as CharacterAppearancePreset
	assert(preset != null, "Could not load default preset")
	var errors := preset.validation_errors()
	print("PRESET_ERRORS ", errors)

	var assembler := CharacterAssembler.new()
	var character := assembler.assemble(preset)
	assert(character != null, "Assembly failed: %s" % assembler.last_warnings)
	root.add_child(character)

	var skeleton := character.find_child("Skeleton3D", true, false) as Skeleton3D
	print("BONES ", skeleton.get_bone_count())
	var required := [
		"mixamorigHips", "mixamorigHead", "mixamorigLeftToeBase",
		"mixamorigRightToeBase", "mixamorigRightHand",
	]
	for bone_name in required:
		assert(skeleton.find_bone(bone_name) >= 0, "missing bone %s" % bone_name)

	var player := character.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(player != null, "mannequin has no AnimationPlayer")
	print("ANIMATIONS ", player.get_animation_list())

	print("SOCKETS ", assembler.socket_names())
	print("EQUIPPED ", assembler.equipped_slots())
	print("WARNINGS ", assembler.last_warnings)

	var head_attachment := skeleton.find_child("HeadAttachment", false, false)
	assert(head_attachment is BoneAttachment3D, "HeadAttachment missing")
	var face_root := head_attachment.find_child("FaceRoot", false, false)
	assert(face_root != null, "FaceRoot missing")

	# BoneAttachment3D and global-transform propagation settle once the main
	# loop iterates; measure after two frames like the running game would.
	await process_frame
	await process_frame

	# Socket sanity: the eyes socket must sit in front of the face (+Z in the
	# body scene space) and above the shoulders.
	var eyes_socket := assembler.socket_node("EyesSocket")
	var body_local := (
		character.global_transform.affine_inverse()
		* eyes_socket.global_transform
	)
	print("EYES_SOCKET_BODY_LOCAL ", body_local.origin)
	assert(body_local.origin.z > 0.08, "eyes socket is not in front of the face")
	assert(body_local.origin.y > 0.18, "eyes socket is below the head")

	# Part meshes must carry geometry.
	for slot in assembler.equipped_slots():
		var node := assembler.equipped_node(slot)
		var meshes := node.find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D:
			meshes.append(node)
		assert(not meshes.is_empty(), "slot %s attached no meshes" % slot)
	print("MANNEQUIN_PROBE_OK")
	quit(0)
