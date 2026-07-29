class_name CharacterAssembler
extends RefCounted
## Assembles a CharacterAppearancePreset onto a body instance: builds the
## head-following socket tree, instantiates parts, applies per-body fits and
## color channels, and resolves slot conflicts. Rebuilds only when asked —
## never per frame.
##
## The assembler is body-profile agnostic: everything it needs (skeleton
## contract, socket map, compatibility) comes from resources. Adding a body or
## a part must never require editing this class.

const HEAD_ATTACHMENT_NAME := "HeadAttachment"
const FACE_ROOT_NAME := "FaceRoot"

var last_warnings: PackedStringArray = []

var _body_root: Node3D
var _skeleton: Skeleton3D
var _profile: CharacterBodyProfile
var _sockets: Dictionary = {}          # socket name -> Node3D
var _equipped: Dictionary = {}         # slot -> Node3D (part instance root)
var _equipped_meshes: Dictionary = {}  # slot -> Array of skinned MeshInstance3D
var _equipped_parts: Dictionary = {}   # slot -> CharacterPartDefinition
var _suppressed_slots: Dictionary = {} # slot -> true
var _head_attachment: BoneAttachment3D


## Convenience for tools and the character lab: instantiates the body scene
## directly. Gameplay code that needs AssetLibrary materials should instantiate
## the body itself and call assemble_onto().
func assemble(preset: CharacterAppearancePreset) -> Node3D:
	last_warnings.clear()
	if preset == null or preset.body_profile == null:
		_warn("assemble called without a preset/body profile")
		return null
	if preset.body_profile.body_scene == null:
		_warn(
			"body profile '%s' has no body_scene"
			% preset.body_profile.profile_id
		)
		return null
	var body := preset.body_profile.body_scene.instantiate() as Node3D
	if not assemble_onto(body, preset):
		body.free()
		return null
	return body


## Attaches the preset's parts to an existing body instance. Returns false on
## contract failures (missing skeleton / head bone / FaceRoot).
func assemble_onto(body_root: Node3D, preset: CharacterAppearancePreset) -> bool:
	last_warnings.clear()
	var preset_errors := preset.validation_errors()
	for preset_error in preset_errors:
		_warn(preset_error)
	_profile = preset.body_profile
	_body_root = body_root
	_skeleton = _locate_skeleton(body_root)
	if _skeleton == null:
		_warn(
			"body '%s' has no %s node"
			% [_profile.profile_id, _profile.skeleton_node_name]
		)
		return false
	if _skeleton.find_bone(_profile.head_bone) < 0:
		_warn(
			"body '%s' is missing head bone '%s'"
			% [_profile.profile_id, _profile.head_bone]
		)
		return false
	clear_parts()
	_build_socket_tree()
	if _sockets.is_empty():
		return false
	_suppressed_slots.clear()
	for part in preset.parts:
		if part == null:
			continue
		for hidden_slot in part.hides_slots:
			_suppressed_slots[hidden_slot] = true
	for part in preset.parts:
		if part == null:
			continue
		if _suppressed_slots.has(part.slot):
			continue
		_equip_part(part, preset)
	_apply_suppressed_visibility()
	return true


## Removes every previously equipped part and the socket tree so a changed
## preset can be assembled cleanly.
func clear_parts() -> void:
	for slot in _equipped:
		var node := _equipped[slot] as Node3D
		if is_instance_valid(node):
			node.queue_free()
	for slot in _equipped_meshes:
		for mesh in _equipped_meshes[slot]:
			if is_instance_valid(mesh) and mesh != _equipped.get(slot):
				(mesh as Node).queue_free()
	_equipped.clear()
	_equipped_meshes.clear()
	_equipped_parts.clear()
	if is_instance_valid(_head_attachment):
		_head_attachment.queue_free()
	_head_attachment = null
	_sockets.clear()


func equipped_node(slot: String) -> Node3D:
	var node := _equipped.get(slot) as Node3D
	return node if is_instance_valid(node) else null


func equipped_part(slot: String) -> CharacterPartDefinition:
	return _equipped_parts.get(slot)


func equipped_slots() -> PackedStringArray:
	var slots: PackedStringArray = []
	for slot in _equipped:
		slots.append(slot)
	return slots


func socket_node(socket_name: String) -> Node3D:
	var node := _sockets.get(socket_name) as Node3D
	return node if is_instance_valid(node) else null


func socket_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for socket_name in _sockets:
		names.append(socket_name)
	return names


## Union of the equipped parts' hidden body regions; the body owner applies
## them (the player body uses its shader hide-mask).
func hidden_regions() -> Array[String]:
	var regions: Dictionary = {}
	for slot in _equipped_parts:
		var part := _equipped_parts[slot] as CharacterPartDefinition
		for region in part.hidden_regions:
			regions[region] = true
	var result: Array[String] = []
	for region in regions:
		result.append(region)
	return result


## Temporarily hides a slot's part (e.g. headwear hiding hair) without
## re-assembling.
func set_slot_visible(slot: String, visible: bool) -> void:
	for mesh in _equipped_meshes.get(slot, []):
		if is_instance_valid(mesh):
			(mesh as MeshInstance3D).visible = visible
	if _equipped_meshes.has(slot):
		return
	var node := equipped_node(slot)
	if node != null:
		node.visible = visible


func apply_color(slot: String, color: Color) -> void:
	for mesh in _equipped_meshes.get(slot, []):
		if is_instance_valid(mesh):
			_tint_mesh(mesh as MeshInstance3D, color)
	if _equipped_meshes.has(slot):
		return
	var node := equipped_node(slot)
	if node == null:
		return
	for mesh_instance in _mesh_instances(node):
		_tint_mesh(mesh_instance, color)


# ------------------------------------------------------------------ internal

func _locate_skeleton(body_root: Node3D) -> Skeleton3D:
	return body_root.find_child(
		_profile.skeleton_node_name, true, false
	) as Skeleton3D


func _build_socket_tree() -> void:
	_sockets.clear()
	if not _profile.face_sockets.has(FACE_ROOT_NAME):
		_warn(
			"body '%s' defines no FaceRoot socket" % _profile.profile_id
		)
		return
	_head_attachment = BoneAttachment3D.new()
	_head_attachment.name = HEAD_ATTACHMENT_NAME
	_head_attachment.bone_name = _profile.head_bone
	_skeleton.add_child(_head_attachment)

	# face_sockets are body-scene local positions measured at rest. Convert
	# them into the attachment's local space so they ride the head bone.
	var head_index := _skeleton.find_bone(_profile.head_bone)
	var bone_rest := _skeleton.get_bone_global_rest(head_index)
	var body_to_skeleton := (
		_body_root.global_transform.affine_inverse()
		* _skeleton.global_transform
	)
	var attachment_in_body := body_to_skeleton * bone_rest
	var to_head_local := attachment_in_body.affine_inverse()

	var face_root := Node3D.new()
	face_root.name = FACE_ROOT_NAME
	_head_attachment.add_child(face_root)
	var face_root_in_body := Transform3D(
		Basis.IDENTITY, _profile.face_sockets[FACE_ROOT_NAME]
	)
	face_root.transform = to_head_local * face_root_in_body
	_sockets[FACE_ROOT_NAME] = face_root

	for socket_name in _profile.face_sockets:
		if socket_name == FACE_ROOT_NAME:
			continue
		var socket := Node3D.new()
		socket.name = socket_name
		face_root.add_child(socket)
		var socket_in_body := Transform3D(
			Basis.IDENTITY, _profile.face_sockets[socket_name]
		)
		socket.transform = (
			face_root.transform.affine_inverse()
			* to_head_local
			* socket_in_body
		)
		_sockets[socket_name] = socket

	for socket_name in _profile.bone_sockets:
		var bone_name := String(_profile.bone_sockets[socket_name])
		if _skeleton.find_bone(bone_name) < 0:
			_warn(
				"socket '%s' targets missing bone '%s'"
				% [socket_name, bone_name]
			)
			continue
		var attachment := BoneAttachment3D.new()
		attachment.name = "%sAttachment" % socket_name
		attachment.bone_name = bone_name
		_skeleton.add_child(attachment)
		var socket := Node3D.new()
		socket.name = socket_name
		attachment.add_child(socket)
		_sockets[socket_name] = socket


func _equip_part(
	part: CharacterPartDefinition, preset: CharacterAppearancePreset
) -> void:
	if not part.supports_body(_profile.profile_id):
		_warn(
			"part '%s' is not compatible with body '%s'"
			% [part.part_id, _profile.profile_id]
		)
		return
	if part.scene == null:
		_warn("part '%s' has no scene" % part.part_id)
		return
	if part.attachment_type == CharacterPartDefinition.ATTACHMENT_SKINNED:
		_equip_skinned_part(part, preset)
		return
	var socket_name := part.resolved_socket()
	var socket := socket_node(socket_name)
	if socket == null:
		_warn(
			"part '%s' targets missing socket '%s' on body '%s'"
			% [part.part_id, socket_name, _profile.profile_id]
		)
		return
	var instance := part.scene.instantiate() as Node3D
	instance.name = "Part_%s" % part.part_id
	socket.add_child(instance)
	var fit := part.fit_for(_profile.profile_id)
	instance.transform = (
		fit.to_transform() if fit != null else Transform3D.IDENTITY
	)
	_strip_disallowed_children(instance, part)
	_equipped[part.slot] = instance
	_equipped_parts[part.slot] = part
	if not part.color_channel.is_empty():
		apply_color(part.slot, preset.color_for_channel(part.color_channel))


## Skinned clothing binds to the live skeleton; the garment scene must be
## authored against the same skeleton contract (bone names + rest pose) and
## must not bring its own runtime Skeleton3D.
##
## Meshes are parented directly under the live Skeleton3D with the skeleton
## path set BEFORE they enter the tree: Godot resolves the skin binding at
## ENTER_TREE, and a path corrected afterwards is not reliably re-resolved.
func _equip_skinned_part(
	part: CharacterPartDefinition, preset: CharacterAppearancePreset
) -> void:
	var bundle := part.scene.instantiate() as Node3D
	var source_skeleton := bundle.find_child(
		"Skeleton3D", true, false
	) as Skeleton3D
	var meshes := (
		source_skeleton.find_children("*", "MeshInstance3D", true, false)
		if source_skeleton != null
		else bundle.find_children("*", "MeshInstance3D", true, false)
	)
	if meshes.is_empty():
		_warn("skinned part '%s' contains no meshes" % part.part_id)
		bundle.free()
		return
	var attached: Array[MeshInstance3D] = []
	for child in meshes:
		var mesh_instance := child as MeshInstance3D
		mesh_instance.get_parent().remove_child(mesh_instance)
		mesh_instance.owner = null
		mesh_instance.name = "Part_%s_%s" % [part.part_id, mesh_instance.name]
		mesh_instance.transform = Transform3D.IDENTITY
		mesh_instance.skeleton = NodePath("..")
		_skeleton.add_child(mesh_instance)
		attached.append(mesh_instance)
	bundle.free()
	_equipped[part.slot] = attached[0]
	_equipped_meshes[part.slot] = attached
	_equipped_parts[part.slot] = part
	if not part.color_channel.is_empty():
		apply_color(part.slot, preset.color_for_channel(part.color_channel))


func _apply_suppressed_visibility() -> void:
	for slot in _suppressed_slots:
		set_slot_visible(slot, false)


func _strip_disallowed_children(
	instance: Node3D, part: CharacterPartDefinition
) -> void:
	for child in instance.find_children("*", "Camera3D", true, false):
		_warn("part '%s' shipped a camera; removing it" % part.part_id)
		child.queue_free()
	for child in instance.find_children("*", "Light3D", true, false):
		_warn("part '%s' shipped a light; removing it" % part.part_id)
		child.queue_free()
	if part.attachment_type == CharacterPartDefinition.ATTACHMENT_RIGID:
		for child in instance.find_children("*", "Skeleton3D", true, false):
			_warn(
				"rigid part '%s' shipped a skeleton; removing it"
				% part.part_id
			)
			child.queue_free()


func _mesh_instances(node: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.find_children("*", "MeshInstance3D", true, false):
		result.append(child as MeshInstance3D)
	return result


func _tint_mesh(mesh_instance: MeshInstance3D, color: Color) -> void:
	if mesh_instance.mesh == null:
		return
	for surface_index in mesh_instance.mesh.get_surface_count():
		var override := mesh_instance.get_surface_override_material(
			surface_index
		)
		if override is ShaderMaterial:
			# The game's palette shader owns the surface: drive its albedo.
			var styled := override as ShaderMaterial
			styled.set_shader_parameter("base_albedo", color)
			styled.set_shader_parameter("palette_tint", Color.WHITE)
			styled.set_shader_parameter("saturation", 1.0)
			styled.set_shader_parameter("value_scale", 1.0)
			continue
		var active := mesh_instance.get_active_material(surface_index)
		if active is BaseMaterial3D:
			var tinted := (active as BaseMaterial3D).duplicate() as BaseMaterial3D
			tinted.albedo_color = color
			mesh_instance.set_surface_override_material(surface_index, tinted)


func _warn(message: String) -> void:
	last_warnings.append(message)
	push_warning("CharacterAssembler: %s" % message)
