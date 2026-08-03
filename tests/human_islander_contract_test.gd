extends SceneTree
## Structural, proportion, palette, and grounding contract for the V2
## parametric human player body.

const ProceduralCreatureScript := preload(
	"res://scripts/creatures/procedural_creature.gd"
)

const REQUIRED_COMPONENTS := [
	"BodyPivot", "TorsoMotion", "HeadPivot", "TorsoSkin", "HeadMesh", "Hair", "FaceAnchor",
	"ContactShadow", "ScalpCap",
	"FrontSweep", "TempleLeft", "TempleRight", "BackVolume", "CrownLock",
	"EyeLeftAnchor", "EyeRightAnchor", "NoseAnchor", "MouthAnchor",
	"BlushLeftAnchor", "BlushRightAnchor",
	"ArmLeft", "ArmRight", "LegLeft", "LegRight",
	"SleeveLeft", "SleeveRight", "ArmSkinLeft", "ArmSkinRight",
	"TrouserLeft", "TrouserRight", "ShinLeft", "ShinRight",
	"ShoeLeft", "ShoeRight",
	"ShirtTorso", "OverallsSeat", "ScarfWrap", "ScarfKnot",
]


func _init() -> void:
	var definition: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/creatures/islander.json")
	)
	assert(definition is Dictionary, "islander definition must parse")
	var creature := _build_creature(definition as Dictionary)
	var body := creature.get_node_or_null("HumanBodyParts") as Node3D

	var generic_shell := creature.get_node_or_null("CreatureSdfShell") as MeshInstance3D
	assert(generic_shell != null, "compatibility shell must remain addressable")
	assert(not generic_shell.visible, "human must not render the shared creature SDF")
	assert(body != null, "human must build the V2 semantic body hierarchy")
	var outfit := creature.get_node_or_null("Outfit") as Node3D
	assert(outfit != null, "default keeper outfit must build")
	assert(
		outfit.get_node_or_null("Hat") == null,
		"default keeper outfit must remain hatless"
	)

	var names: PackedStringArray = body.call("component_names")
	for component_name in REQUIRED_COMPONENTS:
		assert(
			names.has(component_name),
			"missing V2 component: %s" % component_name
		)

	# Every palette role must resolve; debug_missing fallbacks fail here.
	var missing: PackedStringArray = body.call("missing_palette_tokens")
	assert(missing.is_empty(), "unresolved palette tokens: %s" % str(missing))

	# Approved proportion ranges (fractions of total height / head size).
	var m: Dictionary = body.call("measurements")
	var total := float(m.get("total_height"))
	_assert_range(float(m.get("head_height")) / total, 0.37, 0.41, "head height")
	_assert_range(float(m.get("head_width")) / total, 0.32, 0.36, "head width")
	_assert_range(float(m.get("head_depth")) / total, 0.27, 0.33, "head depth")
	_assert_range(
		float(m.get("shoulder_width")) / total, 0.24, 0.28, "shoulder width"
	)
	_assert_range(
		float(m.get("eye_white_width")) / float(m.get("head_width")),
		0.15, 0.18, "eye white width"
	)
	_assert_range(
		float(m.get("eye_white_height")) / float(m.get("head_height")),
		0.21, 0.26, "eye white height"
	)
	assert(
		float(m.get("thigh_radius")) > float(m.get("shin_radius")),
		"thighs must be wider than shins"
	)
	_assert_range(
		float(m.get("shoe_length")) / total, 0.115, 0.145, "shoe length"
	)

	# Face anchors mirror; nose and mouth stay centered.
	var face: Dictionary = body.call("face_anchor_positions")
	_assert_mirrored(face, "EyeLeftAnchor", "EyeRightAnchor", 0.0001)
	_assert_mirrored(face, "BlushLeftAnchor", "BlushRightAnchor", 0.0001)
	assert(absf((face.get("NoseAnchor") as Vector3).x) < 0.0001, "nose must be centered")
	assert(absf((face.get("MouthAnchor") as Vector3).x) < 0.0001, "mouth must be centered")

	# Both arm skin surfaces resolve to the identical skin material color.
	var left_arm := body.get_node("ArmSkinLeft") as MeshInstance3D
	var right_arm := body.get_node("ArmSkinRight") as MeshInstance3D
	var left_color := (left_arm.material_override as StandardMaterial3D).albedo_color
	var right_color := (right_arm.material_override as StandardMaterial3D).albedo_color
	assert(left_color == right_color, "hand/arm skin materials must match")

	# Garments must sit outside the body as hollow, independently shaded shells.
	# A center vertex at the lowest shirt row would recreate the old solid cap,
	# which read as a bright skin-colored oval across the stomach under key light.
	var shirt := body.get_node("BodyPivot/TorsoMotion/ShirtTorso") as MeshInstance3D
	var torso_skin := body.get_node("BodyPivot/TorsoMotion/TorsoSkin") as MeshInstance3D
	assert(
		shirt.mesh.get_aabb().size.x > torso_skin.mesh.get_aabb().size.x,
		"shirt shell must clear the torso instead of lying directly on the skin"
	)
	var shirt_arrays := shirt.mesh.surface_get_arrays(0)
	var shirt_vertices := shirt_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var hem_y := INF
	for vertex in shirt_vertices:
		hem_y = minf(hem_y, vertex.y)
	var min_hem_radius := INF
	for vertex in shirt_vertices:
		if absf(vertex.y - hem_y) < 0.0001:
			min_hem_radius = minf(min_hem_radius, Vector2(vertex.x, vertex.z).length())
	assert(
		min_hem_radius > 0.04,
		"shirt hem must remain open; a center cap would recreate the stomach light ring"
	)

	# Grounding: at idle both shoe soles rest on the local floor plane.
	for shoe_name in ["ShoeLeft", "ShoeRight"]:
		var shoe := body.get_node(shoe_name) as Node3D
		assert(
			absf(shoe.position.y) < 0.005,
			"%s must rest on the floor plane (y=%f)" % [shoe_name, shoe.position.y]
		)
		var sole := shoe.get_node("Sole") as MeshInstance3D
		var sole_bottom := shoe.position.y + sole.position.y - sole.scale.y
		assert(
			absf(sole_bottom) < 0.005,
			"%s sole must touch the floor (bottom=%f)" % [shoe_name, sole_bottom]
		)

	# Locomotion: opposing feet must separate into stance/swing, shoes must
	# articulate, and the upper body must counter the pelvis rather than moving
	# as a rigid block.
	var walk := ProceduralCreatureScript.MotionState.new()
	walk.grounded = true
	walk.local_velocity = Vector3(0.0, 0.0, -1.65)
	for _frame in 12:
		creature.call("advance", 1.0 / 60.0, walk)
	var walk_anchors: Dictionary = creature.call("pose_anchors")
	var walk_legs: Array = walk_anchors.get("legs", [])
	assert(walk_legs.size() == 2, "player walk must expose two leg anchors")
	var foot_height_delta := absf(
		((walk_legs[0] as Dictionary).get("foot") as Vector3).y
		- ((walk_legs[1] as Dictionary).get("foot") as Vector3).y
	)
	assert(foot_height_delta > 0.004, "walk must separate stance and swing feet")
	var max_foot_pitch := maxf(
		absf(float((walk_legs[0] as Dictionary).get("foot_pitch", 0.0))),
		absf(float((walk_legs[1] as Dictionary).get("foot_pitch", 0.0)))
	)
	assert(max_foot_pitch > 0.025, "walk shoes must articulate heel/toe pitch")
	var torso_motion := body.get_node("BodyPivot/TorsoMotion") as Node3D
	assert(
		absf(torso_motion.rotation.y) > 0.01,
		"walk must counter-rotate the upper body"
	)
	for _frame in 90:
		creature.call("advance", 1.0 / 60.0, ProceduralCreatureScript.MotionState.new())
	for shoe_name in ["ShoeLeft", "ShoeRight"]:
		var settled_shoe := body.get_node(shoe_name) as Node3D
		assert(
			absf(settled_shoe.position.y) < 0.006,
			"%s must settle back onto the floor after stopping" % shoe_name
		)

	# Expression states switch without errors and toggle the mouth meshes.
	for expression_name in [
		"happy", "surprised", "sleepy", "talk_open", "talk_closed", "normal",
	]:
		body.call("set_expression", expression_name)
		assert(String(body.call("expression")) == expression_name)

	# Determinism: a second build reports identical measurements.
	var second := _build_creature(definition as Dictionary)
	var second_m: Dictionary = (
		second.get_node("HumanBodyParts") as Node3D
	).call("measurements")
	assert(str(second_m) == str(m), "V2 build must be deterministic")

	print("HUMAN ISLANDER V2 CONTRACT PASSED — components, palette, proportions, grounding")
	creature.free()
	second.free()
	quit(0)


func _build_creature(definition: Dictionary) -> Node3D:
	var creature := ProceduralCreatureScript.new() as Node3D
	root.add_child(creature)
	creature.call("build", definition)
	var state := ProceduralCreatureScript.MotionState.new()
	state.grounded = true
	for _frame in 30:
		creature.call("advance", 1.0 / 60.0, state)
	return creature


func _assert_range(value: float, low: float, high: float, label: String) -> void:
	assert(
		value >= low and value <= high,
		"%s out of range: %f not in [%f, %f]" % [label, value, low, high]
	)


func _assert_mirrored(
	face: Dictionary, left_name: String, right_name: String, tolerance: float
) -> void:
	var left: Vector3 = face.get(left_name, Vector3.ZERO)
	var right: Vector3 = face.get(right_name, Vector3.ZERO)
	assert(absf(left.x + right.x) <= tolerance, "%s/%s X positions must mirror" % [left_name, right_name])
	assert(absf(left.y - right.y) <= tolerance, "%s/%s heights must match" % [left_name, right_name])
	assert(absf(left.z - right.z) <= tolerance, "%s/%s depths must match" % [left_name, right_name])
