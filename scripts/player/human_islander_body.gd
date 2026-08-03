class_name HumanIslanderBody
extends Node3D
## Semantic, animation-ready procedural body for the human islander.
##
## Unlike the generic creature shell, unrelated parts never share an SDF or
## material interpolation domain. Each pivot owns one small procedural shell;
## only the two skin volumes that form the head blend together.

const SdfBlendShellScript := preload("res://scripts/player/sdf_blend_shell.gd")

const HEAD_WIDTH := 0.290
const HEAD_HEIGHT_RATIO := 0.92
const HEAD_DEPTH_RATIO := 0.80
const HEAD_BLEND := HEAD_WIDTH * 0.05
const HAIR_THICKNESS := HEAD_WIDTH * 0.04

var _palette: Dictionary
var _head: Dictionary
var _torso: Dictionary
var _legs: Dictionary
var _arms: Dictionary

var _pelvis: Node3D
var _parts: Dictionary = {}
var _face_anchor: Node3D


func build(
	palette: Dictionary,
	head_definition: Dictionary,
	torso_definition: Dictionary,
	leg_definition: Dictionary,
	arm_definition: Dictionary
) -> void:
	if is_instance_valid(_pelvis):
		return
	_palette = palette
	_head = head_definition
	_torso = torso_definition
	_legs = leg_definition
	_arms = arm_definition

	_pelvis = Node3D.new()
	_pelvis.name = "Pelvis"
	add_child(_pelvis)

	var torso_part := _add_sdf_part(_pelvis, "Torso", 1)
	var head_part := _add_sdf_part(torso_part.pivot, "Head", 2)
	_add_limb_chain(torso_part.pivot, "ArmLeft")
	_add_limb_chain(torso_part.pivot, "ArmRight")
	_add_leg_chain(_pelvis, "LegLeft")
	_add_leg_chain(_pelvis, "LegRight")

	_configure_torso(torso_part)
	_configure_head(head_part)
	_build_ears(head_part.pivot)
	_build_hair(head_part.pivot)
	_build_face(head_part.pivot)


func update_pose(pose: Dictionary) -> void:
	if not is_instance_valid(_pelvis):
		return
	var body: Transform3D = pose.get("body", Transform3D.IDENTITY)
	var head: Transform3D = pose.get("head", Transform3D.IDENTITY)
	var torso_part: Dictionary = _parts.get("Torso", {})
	var head_part: Dictionary = _parts.get("Head", {})
	(torso_part.pivot as Node3D).transform = body
	(head_part.pivot as Node3D).transform = body.affine_inverse() * head

	var arm_anchors: Array = pose.get("arms", [])
	for arm_index in mini(arm_anchors.size(), 2):
		var arm_anchor := arm_anchors[arm_index] as Dictionary
		var shoulder: Vector3 = arm_anchor.get("shoulder", Vector3.ZERO)
		var local_shoulder: Vector3 = body.affine_inverse() * shoulder
		_update_arm_chain(
			"Left" if local_shoulder.x < 0.0 else "Right",
			arm_anchor,
			body
		)

	var leg_anchors: Array = pose.get("legs", [])
	for leg_index in mini(leg_anchors.size(), 2):
		var leg_anchor := leg_anchors[leg_index] as Dictionary
		var hip: Vector3 = leg_anchor.get("hip", Vector3.ZERO)
		var local_hip: Vector3 = body.affine_inverse() * hip
		_update_leg_chain(
			"Left" if local_hip.x < 0.0 else "Right",
			leg_anchor,
			body
		)


func component_names() -> PackedStringArray:
	var names := PackedStringArray(["Pelvis"])
	for part_name: String in _parts:
		names.append(part_name)
	for extra_name in [
		"EarLeft", "EarRight", "Hair", "FaceAnchor", "EyeLeftAnchor",
		"EyeRightAnchor", "NoseAnchor", "MouthAnchor", "BlushLeftAnchor",
		"BlushRightAnchor",
	]:
		names.append(extra_name)
	return names


func face_anchor_positions() -> Dictionary:
	var result := {}
	if not is_instance_valid(_face_anchor):
		return result
	for child in _face_anchor.get_children():
		if child is Node3D:
			result[child.name] = (child as Node3D).position
	return result


func _add_limb_chain(parent: Node3D, side_name: String) -> void:
	var side := side_name.trim_prefix("Arm")
	var upper := _add_sdf_part(parent, "UpperArm%s" % side, 1)
	var lower := _add_sdf_part(upper.pivot, "LowerArm%s" % side, 1)
	_add_sdf_part(lower.pivot, "Hand%s" % side, 1)


func _add_leg_chain(parent: Node3D, side_name: String) -> void:
	var side := side_name.trim_prefix("Leg")
	var upper := _add_sdf_part(parent, "UpperLeg%s" % side, 1)
	var lower := _add_sdf_part(upper.pivot, "LowerLeg%s" % side, 1)
	_add_sdf_part(lower.pivot, "Foot%s" % side, 1)


func _add_sdf_part(parent: Node3D, part_name: String, shape_count: int) -> Dictionary:
	var pivot := Node3D.new()
	pivot.name = part_name
	parent.add_child(pivot)
	var surface := SdfBlendShellScript.new() as MeshInstance3D
	surface.name = "Surface"
	pivot.add_child(surface)
	surface.call("build", shape_count)
	surface.call("set_outline_width", 0.0035)
	var neighbors: Array = []
	for shape_index in shape_count:
		var shape_neighbors: Array = []
		for other_index in shape_count:
			if other_index != shape_index:
				shape_neighbors.append(other_index)
		neighbors.append(shape_neighbors)
	surface.call("set_neighbors", neighbors)
	var part := {"pivot": pivot, "surface": surface}
	_parts[part_name] = part
	return part


func _configure_torso(part: Dictionary) -> void:
	var radius := float(_torso.get("radius", HEAD_WIDTH * 0.22))
	var half_length := float(_torso.get("length", HEAD_WIDTH * 0.16)) * 0.5
	var taper := clampf(float(_torso.get("taper", 1.05)), 0.82, 1.12)
	var surface := part.surface as MeshInstance3D
	surface.scale = Vector3(1.0, 1.0, float(_torso.get("depth_scale", 0.63)))
	_update_surface(
		surface,
		[Vector4(0.0, -half_length, 0.0, radius)],
		[Vector4(0.0, half_length, 0.0, HEAD_WIDTH * 0.035)],
		[_color4(_color_for("torso"))],
		[radius * taper]
	)


func _configure_head(part: Dictionary) -> void:
	var surface := part.surface as MeshInstance3D
	surface.scale = Vector3(1.0, HEAD_HEIGHT_RATIO, HEAD_DEPTH_RATIO)
	var main_radius := HEAD_WIDTH * 0.49
	var lower_radius := HEAD_WIDTH * 0.38
	var lower_center := Vector3(
		0.0,
		-HEAD_WIDTH * 0.10 / HEAD_HEIGHT_RATIO,
		-HEAD_WIDTH * 0.035 / HEAD_DEPTH_RATIO
	)
	_update_surface(
		surface,
		[
			Vector4(-HEAD_WIDTH * 0.005, 0.0, 0.0, main_radius),
			Vector4(lower_center.x, lower_center.y, lower_center.z, lower_radius),
		],
		[
			Vector4(HEAD_WIDTH * 0.005, 0.0, 0.0, HEAD_BLEND),
			Vector4(lower_center.x, lower_center.y, lower_center.z, HEAD_BLEND),
		],
		[_color4(_color_for("head")), _color4(_color_for("head"))],
		[main_radius, lower_radius]
	)


func _update_arm_chain(side: String, anchors: Dictionary, body: Transform3D) -> void:
	var shoulder: Vector3 = anchors.get("shoulder", Vector3.ZERO)
	var hand: Vector3 = anchors.get("hand", shoulder)
	var elbow: Vector3 = anchors.get("elbow", shoulder.lerp(hand, 0.52))
	var upper_frame := _segment_frame(shoulder, elbow)
	var lower_frame := _segment_frame(elbow, hand)
	var upper: Dictionary = _parts.get("UpperArm%s" % side, {})
	var lower: Dictionary = _parts.get("LowerArm%s" % side, {})
	var mitten: Dictionary = _parts.get("Hand%s" % side, {})
	(upper.pivot as Node3D).transform = body.affine_inverse() * upper_frame
	(lower.pivot as Node3D).transform = upper_frame.affine_inverse() * lower_frame
	(mitten.pivot as Node3D).transform = lower_frame.affine_inverse() * Transform3D(
		lower_frame.basis.orthonormalized(), hand
	)

	var arm_radius := float(_arms.get("radius", HEAD_WIDTH * 0.065))
	_configure_segment(upper, shoulder.distance_to(elbow), arm_radius, arm_radius * 0.94, _color_for("arm"))
	_configure_segment(lower, elbow.distance_to(hand), arm_radius * 0.94, arm_radius * 0.82, _color_for("arm"))
	_configure_ball(
		mitten,
		arm_radius * 1.14,
		Vector3(1.0, 1.08, 0.86),
		_color_for("arm")
	)


func _update_leg_chain(side: String, anchors: Dictionary, body: Transform3D) -> void:
	var hip: Vector3 = anchors.get("hip", Vector3.ZERO)
	var knee: Vector3 = anchors.get("knee", hip)
	var foot: Vector3 = anchors.get("foot", knee)
	var upper_frame := _segment_frame(hip, knee)
	var lower_end := foot + Vector3.UP * HEAD_WIDTH * 0.025
	var lower_frame := _segment_frame(knee, lower_end)
	var foot_basis := Basis.from_euler(Vector3(0.0, body.basis.get_euler().y, 0.0))
	var foot_frame := Transform3D(foot_basis, foot)
	var upper: Dictionary = _parts.get("UpperLeg%s" % side, {})
	var lower: Dictionary = _parts.get("LowerLeg%s" % side, {})
	var foot_part: Dictionary = _parts.get("Foot%s" % side, {})
	(upper.pivot as Node3D).transform = upper_frame
	(lower.pivot as Node3D).transform = upper_frame.affine_inverse() * lower_frame
	(foot_part.pivot as Node3D).transform = lower_frame.affine_inverse() * foot_frame

	var leg_radius := float(_legs.get("radius", HEAD_WIDTH * 0.072))
	_configure_segment(upper, hip.distance_to(knee), leg_radius, leg_radius * 0.91, _color_for("limb"))
	_configure_segment(lower, knee.distance_to(lower_end), leg_radius * 0.91, leg_radius * 0.78, _color_for("limb"))
	_configure_foot(foot_part)


func _configure_segment(
	part: Dictionary,
	length: float,
	radius_a: float,
	radius_b: float,
	color: Color
) -> void:
	var surface := part.surface as MeshInstance3D
	surface.scale = Vector3.ONE
	_update_surface(
		surface,
		[Vector4(0.0, 0.0, 0.0, radius_a)],
		[Vector4(0.0, maxf(length, 0.001), 0.0, HEAD_WIDTH * 0.025)],
		[_color4(color)],
		[radius_b]
	)


func _configure_ball(part: Dictionary, radius: float, scale_value: Vector3, color: Color) -> void:
	var surface := part.surface as MeshInstance3D
	surface.scale = scale_value
	_update_surface(
		surface,
		[Vector4(0.0, 0.0, 0.0, radius)],
		[Vector4(0.0, 0.0, 0.0, HEAD_WIDTH * 0.02)],
		[_color4(color)],
		[radius]
	)


func _configure_foot(part: Dictionary) -> void:
	var radius := float(_legs.get("foot_radius", HEAD_WIDTH * 0.078))
	var surface := part.surface as MeshInstance3D
	surface.scale = Vector3(1.0, 0.68, 1.0)
	_update_surface(
		surface,
		[Vector4(0.0, 0.0, radius * 0.18, radius)],
		[Vector4(0.0, 0.0, -radius * 0.82, HEAD_WIDTH * 0.02)],
		[_color4(_color_for("foot"))],
		[radius * 0.94]
	)


func _build_ears(head_pivot: Node3D) -> void:
	var ear_color := _color_for("head")
	for side in [-1.0, 1.0]:
		var side_name := "Left" if side < 0.0 else "Right"
		var pivot := Node3D.new()
		pivot.name = "Ear%s" % side_name
		pivot.position = Vector3(side * HEAD_WIDTH * 0.50, 0.0, HEAD_WIDTH * 0.025)
		head_pivot.add_child(pivot)
		_add_ellipsoid(
			pivot,
			"Surface",
			Vector3.ZERO,
			Vector3(HEAD_WIDTH * 0.050, HEAD_WIDTH * 0.075, HEAD_WIDTH * 0.030),
			ear_color
		)


func _build_hair(head_pivot: Node3D) -> void:
	var hair_root := Node3D.new()
	hair_root.name = "Hair"
	head_pivot.add_child(hair_root)
	var cap := MeshInstance3D.new()
	cap.name = "ScalpShell"
	cap.mesh = _hair_cap_mesh()
	cap.material_override = _flat_material(_color("hair"), false)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hair_root.add_child(cap)

	var fringe_y := HEAD_WIDTH * 0.16
	var fringe_z := -HEAD_WIDTH * 0.355
	_add_ellipsoid(
		hair_root, "FringeLeft",
		Vector3(-HEAD_WIDTH * 0.17, fringe_y, fringe_z),
		Vector3(HEAD_WIDTH * 0.16, HEAD_WIDTH * 0.095, HEAD_WIDTH * 0.040),
		_color("hair"), Vector3(0.0, 0.0, -0.18)
	)
	_add_ellipsoid(
		hair_root, "FringeCenter",
		Vector3(0.0, fringe_y - HEAD_WIDTH * 0.018, fringe_z - HEAD_WIDTH * 0.012),
		Vector3(HEAD_WIDTH * 0.18, HEAD_WIDTH * 0.10, HEAD_WIDTH * 0.043),
		_color("hair")
	)
	_add_ellipsoid(
		hair_root, "FringeRight",
		Vector3(HEAD_WIDTH * 0.17, fringe_y, fringe_z),
		Vector3(HEAD_WIDTH * 0.16, HEAD_WIDTH * 0.095, HEAD_WIDTH * 0.040),
		_color("hair"), Vector3(0.0, 0.0, 0.18)
	)


func _build_face(head_pivot: Node3D) -> void:
	_face_anchor = Node3D.new()
	_face_anchor.name = "FaceAnchor"
	head_pivot.add_child(_face_anchor)

	var eye_size := Vector3(HEAD_WIDTH * 0.0315, HEAD_WIDTH * 0.054, HEAD_WIDTH * 0.006)
	for side in [-1.0, 1.0]:
		var side_name := "Left" if side < 0.0 else "Right"
		var eye_anchor := _feature_anchor(
			"Eye%sAnchor" % side_name,
			Vector2(side * 0.16, -0.04),
			HEAD_WIDTH * 0.007
		)
		_add_ellipsoid(eye_anchor, "Eye%s" % side_name, Vector3.ZERO, eye_size, _color("ink"))
		_add_ellipsoid(
			eye_anchor,
			"Highlight%s" % side_name,
			Vector3(-HEAD_WIDTH * 0.012, HEAD_WIDTH * 0.020, HEAD_WIDTH * 0.008),
			Vector3.ONE * HEAD_WIDTH * 0.009,
			Color("#FFF8E4")
		)

	var nose_anchor := _feature_anchor("NoseAnchor", Vector2(0.0, -0.095), HEAD_WIDTH * 0.006)
	_add_ellipsoid(
		nose_anchor, "Nose", Vector3.ZERO,
		Vector3(HEAD_WIDTH * 0.020, HEAD_WIDTH * 0.014, HEAD_WIDTH * 0.004),
		_color_for("head").darkened(0.12)
	)
	var mouth_anchor := _feature_anchor("MouthAnchor", Vector2(0.0, -0.19), HEAD_WIDTH * 0.007)
	_add_ellipsoid(
		mouth_anchor, "Mouth", Vector3.ZERO,
		Vector3(HEAD_WIDTH * 0.045, HEAD_WIDTH * 0.008, HEAD_WIDTH * 0.004),
		_color("ink")
	)
	for side in [-1.0, 1.0]:
		var side_name := "Left" if side < 0.0 else "Right"
		var blush_anchor := _feature_anchor(
			"Blush%sAnchor" % side_name,
			Vector2(side * 0.30, -0.13),
			HEAD_WIDTH * 0.006
		)
		_add_ellipsoid(
			blush_anchor, "Blush%s" % side_name, Vector3.ZERO,
			Vector3(HEAD_WIDTH * 0.034, HEAD_WIDTH * 0.016, HEAD_WIDTH * 0.003),
			_color("accent")
		)


func _feature_anchor(anchor_name: String, face_uv: Vector2, offset: float) -> Node3D:
	var projected := _project_to_face(face_uv)
	var surface_position: Vector3 = projected.position
	var surface_normal: Vector3 = projected.normal
	var axis_z := surface_normal
	var axis_x := axis_z.cross(Vector3.UP).normalized()
	if axis_x.length_squared() < 0.001:
		axis_x = Vector3.RIGHT
	var axis_y := axis_x.cross(axis_z).normalized()
	var anchor := Node3D.new()
	anchor.name = anchor_name
	anchor.transform = Transform3D(
		Basis(axis_x, axis_y, axis_z).orthonormalized(),
		surface_position + surface_normal * offset
	)
	_face_anchor.add_child(anchor)
	return anchor


func _project_to_face(face_uv: Vector2) -> Dictionary:
	var radii := Vector3(
		HEAD_WIDTH * 0.50,
		HEAD_WIDTH * HEAD_HEIGHT_RATIO * 0.50,
		HEAD_WIDTH * HEAD_DEPTH_RATIO * 0.50
	)
	var x := face_uv.x * HEAD_WIDTH
	var y := face_uv.y * HEAD_WIDTH
	var ellipse_term := clampf(
		1.0 - x * x / (radii.x * radii.x) - y * y / (radii.y * radii.y),
		0.0,
		1.0
	)
	var z := -radii.z * sqrt(ellipse_term)
	var normal := Vector3(
		x / (radii.x * radii.x),
		y / (radii.y * radii.y),
		z / (radii.z * radii.z)
	).normalized()
	return {"position": Vector3(x, y, z), "normal": normal}


func _hair_cap_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var segments := 32
	var rings := 10
	var radii := Vector3(
		HEAD_WIDTH * 0.50 + HAIR_THICKNESS,
		HEAD_WIDTH * HEAD_HEIGHT_RATIO * 0.50 + HAIR_THICKNESS,
		HEAD_WIDTH * HEAD_DEPTH_RATIO * 0.50 + HAIR_THICKNESS
	)
	vertices.append(Vector3(0.0, radii.y, 0.0))
	normals.append(Vector3.UP)
	for ring in range(1, rings + 1):
		var fraction := float(ring) / float(rings)
		for segment in range(segments + 1):
			var phi := TAU * float(segment) / float(segments)
			var frontness := maxf(-sin(phi), 0.0)
			var backness := maxf(sin(phi), 0.0)
			var theta_max := 1.54 - frontness * 0.28 + backness * 0.20
			var theta := theta_max * fraction
			var point := Vector3(
				radii.x * sin(theta) * cos(phi),
				radii.y * cos(theta),
				radii.z * sin(theta) * sin(phi)
			)
			vertices.append(point)
			normals.append(Vector3(
				point.x / (radii.x * radii.x),
				point.y / (radii.y * radii.y),
				point.z / (radii.z * radii.z)
			).normalized())
	for segment in segments:
		indices.append(0)
		indices.append(1 + segment)
		indices.append(1 + segment + 1)
	for ring in range(1, rings):
		var row_start := 1 + (ring - 1) * (segments + 1)
		var next_start := row_start + segments + 1
		for segment in segments:
			var a := row_start + segment
			var b := a + 1
			var c := next_start + segment
			var d := c + 1
			indices.append(a)
			indices.append(c)
			indices.append(b)
			indices.append(b)
			indices.append(c)
			indices.append(d)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_ellipsoid(
	parent: Node3D,
	node_name: String,
	position_value: Vector3,
	scale_value: Vector3,
	color: Color,
	rotation_value := Vector3.ZERO
) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = sphere
	instance.position = position_value
	instance.rotation = rotation_value
	instance.scale = scale_value
	instance.material_override = _flat_material(color)
	# Hair, ears, and face graphics are surface decals: the skin volumes own
	# the ground shadow, and decal shadows carve spikes into the face and floor.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _flat_material(color: Color, receive_shadows := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.0
	material.roughness = 0.88
	material.disable_receive_shadows = not receive_shadows
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _segment_frame(from: Vector3, to: Vector3) -> Transform3D:
	var direction := to - from
	var length := maxf(direction.length(), 0.0001)
	var axis_y := direction / length
	var helper := Vector3.RIGHT if absf(axis_y.dot(Vector3.UP)) > 0.92 else Vector3.UP
	var axis_x := helper.cross(axis_y).normalized()
	var axis_z := axis_x.cross(axis_y).normalized()
	return Transform3D(Basis(axis_x, axis_y, axis_z).orthonormalized(), from)


func _update_surface(
	surface: MeshInstance3D,
	shape_a: Array,
	shape_b: Array,
	colors: Array,
	radii_b: Array
) -> void:
	surface.call(
		"update_shapes",
		PackedVector4Array(shape_a),
		PackedVector4Array(shape_b),
		PackedVector4Array(colors),
		PackedFloat32Array(radii_b)
	)


func _color(key: String) -> Color:
	return Color(String(_palette.get(key, "#FFFFFF")))


func _color_for(part: String) -> Color:
	match part:
		"torso":
			return _color("body")
		"head", "arm":
			return _color("body_light") if _palette.has("body_light") else _color("body")
		"limb":
			return _color("limb") if _palette.has("limb") else _color("body").darkened(0.08)
		"foot":
			return _color("foot") if _palette.has("foot") else _color("accent").darkened(0.1)
		_:
			return _color("body")


func _color4(color: Color) -> Vector4:
	return Vector4(color.r, color.g, color.b, color.a)
