extends SceneTree
## Structural, proportion, palette, and grounding contract for the V2
## parametric human player body.

const ProceduralCreatureScript := preload(
	"res://scripts/creatures/procedural_creature.gd"
)

const REQUIRED_COMPONENTS := [
	"BodyPivot", "HeadPivot", "TorsoSkin", "HeadMesh", "Hair", "FaceAnchor",
	"ContactShadow", "ScalpCap",
	"FringeLeft", "FringeCenter", "FringeRight",
	"SideLockLeft", "SideLockRight", "RearVolume", "RearTuft", "CrownSwirl",
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
