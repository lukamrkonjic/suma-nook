class_name HumanIslanderBodyV2
extends Node3D
## Authored V2 player character: parametric meshes instead of SDF shells.
##
## The head and torso are lathed profile curves (designed silhouettes with
## cheeks, jaw taper, shoulders, waist, and seat). Arms and legs are smooth
## tubes swept per frame along the posed joint chain, so limbs bend as one
## continuous surface with zero segment seams. Clothing (shirt, overalls,
## scarf, shoes) is a set of separate layered meshes owned by this class;
## the outfit system keeps only hat and held-tool duties for the player.
##
## Every color resolves through the palette resource. An unresolved token
## renders debug_missing and logs an error naming the role.

const Forge := preload("res://scripts/player/player_mesh_forge.gd")

## Joint anchors arrive from the shared creature pose math; this class owns
## every visible volume. Total height ≈ 0.56 world units.
const HEAD_SCALE := Vector3(1.03, 1.0, 0.90)
const FACE_FLATTEN := 0.86
const TORSO_SCALE := Vector3(1.28, 1.0, 0.88)
const HEAD_PROFILE := [
	Vector2(0.000, -0.105), Vector2(0.034, -0.1025), Vector2(0.058, -0.095),
	Vector2(0.080, -0.070), Vector2(0.096, -0.020), Vector2(0.097, 0.020),
	Vector2(0.093, 0.055), Vector2(0.080, 0.082), Vector2(0.055, 0.100),
	Vector2(0.000, 0.110),
]
const TORSO_PROFILE := [
	Vector2(0.000, -0.095), Vector2(0.046, -0.088), Vector2(0.054, -0.062),
	Vector2(0.048, -0.020), Vector2(0.052, 0.030), Vector2(0.056, 0.058),
	Vector2(0.040, 0.078), Vector2(0.020, 0.088), Vector2(0.000, 0.094),
]
const SHIRT_PROFILE := [
	Vector2(0.000, -0.042), Vector2(0.049, -0.0415), Vector2(0.048, -0.020),
	Vector2(0.052, 0.030), Vector2(0.056, 0.058), Vector2(0.040, 0.076),
	Vector2(0.026, 0.082), Vector2(0.000, 0.086),
]
const SEAT_PROFILE := [
	Vector2(0.000, -0.095), Vector2(0.046, -0.088), Vector2(0.055, -0.060),
	Vector2(0.052, -0.030), Vector2(0.050, -0.024), Vector2(0.000, -0.024),
]
const ARM_RADII := [0.0235, 0.0215, 0.0195, 0.017, 0.0165, 0.023, 0.0235]
const SLEEVE_RADII := [0.0285, 0.0275, 0.0255]
const ARM_SKIN_RADII := [0.019, 0.0175, 0.0165, 0.023, 0.0235]
const LEG_RADII := [0.0305, 0.026, 0.0225, 0.019]
const TROUSER_RADII := [0.0345, 0.031, 0.029, 0.0315]
const SHIN_RADII := [0.0205, 0.019]
const FOOT_OUT_ANGLE := deg_to_rad(9.0)
const FOOT_REST_Y := 0.0187
const EYE_CENTER_X := 0.036
const EYE_CENTER_Y := -0.022
const EYE_WHITE_HALF := Vector2(0.017, 0.0265)
const PUPIL_RATIO := 0.66
const PALETTE_TOKENS := {
	"skin": "sand_650",
	"skin_shadow": "skin_shadow",
	"hair": "brown_600",
	"eye_white": "neutral_100",
	"eye_ink": "character_eye",
	"mouth": "character_mouth",
	"blush": "red_100",
	"shirt": "neutral_200",
	"overalls": "blue_450",
	"scarf": "yellow_700",
	"shoe": "brown_300",
	"sole": "brown_700",
	"button": "yellow_450",
}

var _body_pivot: Node3D
var _torso_motion_pivot: Node3D
var _head_pivot: Node3D
var _face_anchor: Node3D
var _hair_root: Node3D
var _dressed := true
var _naked_parts: Array[Node3D] = []
var _dressed_parts: Array[Node3D] = []
var _sweeps: Dictionary = {}
var _shoes: Array[Node3D] = []
var _naked_feet: Array[MeshInstance3D] = []
var _expression := "normal"
var _blink_timer := 2.6
var _blink_phase := 0.0
var _eye_anchors: Array[Node3D] = []
var _pupils: Array[MeshInstance3D] = []
var _mouth_states: Dictionary = {}
var _resolved_tokens: Dictionary = {}
var _missing_tokens: PackedStringArray = []


func build(
	_palette: Dictionary,
	_head_definition: Dictionary,
	_torso_definition: Dictionary,
	_leg_definition: Dictionary,
	_arm_definition: Dictionary
) -> void:
	if is_instance_valid(_body_pivot):
		return
	_body_pivot = Node3D.new()
	_body_pivot.name = "BodyPivot"
	add_child(_body_pivot)
	_torso_motion_pivot = Node3D.new()
	_torso_motion_pivot.name = "TorsoMotion"
	_body_pivot.add_child(_torso_motion_pivot)
	_head_pivot = Node3D.new()
	_head_pivot.name = "HeadPivot"
	add_child(_head_pivot)

	_build_torso()
	_build_head()
	_build_hair()
	_build_face()
	_build_garments()
	_build_limb_surfaces()
	_build_shoes()
	_build_contact_shadow()
	set_dressed(true)


func _process(delta: float) -> void:
	_advance_blink(delta)


func update_pose(pose: Dictionary) -> void:
	if not is_instance_valid(_body_pivot):
		return
	var body: Transform3D = pose.get("body", Transform3D.IDENTITY)
	_body_pivot.transform = body
	_torso_motion_pivot.transform = pose.get(
		"torso_motion", Transform3D.IDENTITY
	)
	_head_pivot.transform = pose.get("head", Transform3D.IDENTITY)
	_update_arms(body, pose.get("arms", []))
	_update_legs(body, pose.get("legs", []))


## Dressed shows the native garment layers; naked shows the full skin body
## for morphology review.
func set_dressed(dressed: bool) -> void:
	_dressed = dressed
	for part in _naked_parts:
		part.visible = not dressed
	for part in _dressed_parts:
		part.visible = dressed


func is_dressed() -> bool:
	return _dressed


func set_expression(expression_name: String) -> void:
	_expression = expression_name
	var eye_open := 1.0
	var pupil_scale := 1.0
	match expression_name:
		"happy":
			eye_open = 0.38
		"sleepy":
			eye_open = 0.45
			pupil_scale = 0.9
		"surprised":
			eye_open = 1.22
			pupil_scale = 0.72
	for eye_anchor in _eye_anchors:
		eye_anchor.scale = Vector3(1.0, eye_open, 1.0)
	for pupil in _pupils:
		pupil.scale = pupil.get_meta("base_scale") as Vector3 * pupil_scale
	var mouth_key := "smile"
	if expression_name == "talk_open" or expression_name == "surprised":
		mouth_key = "open"
	elif expression_name == "talk_closed":
		mouth_key = "dash"
	for state_key: String in _mouth_states:
		(_mouth_states[state_key] as MeshInstance3D).visible = (
			state_key == mouth_key
		)


func expression() -> String:
	return _expression


func measurements() -> Dictionary:
	return {
		"total_height": 0.56,
		"head_width": 0.097 * 2.0 * HEAD_SCALE.x,
		"head_height": 0.215,
		"head_depth": 0.097 * HEAD_SCALE.z * (1.0 + FACE_FLATTEN),
		"shoulder_width": 0.056 * 2.0 * TORSO_SCALE.x,
		"eye_white_width": EYE_WHITE_HALF.x * 2.0,
		"eye_white_height": EYE_WHITE_HALF.y * 2.0,
		"shoe_length": 0.078,
		"thigh_radius": LEG_RADII[0],
		"shin_radius": SHIN_RADII[1],
	}


func component_names() -> PackedStringArray:
	var names := PackedStringArray([
		"BodyPivot", "TorsoMotion", "HeadPivot", "TorsoSkin", "HeadMesh", "Hair",
		"FaceAnchor", "ContactShadow",
	])
	for child in _hair_root.get_children():
		names.append(child.name)
	for child in _face_anchor.get_children():
		names.append(child.name)
	for sweep_name: String in _sweeps:
		names.append(sweep_name)
	for shoe in _shoes:
		names.append(shoe.name)
	names.append_array(PackedStringArray([
		"ShirtTorso", "OverallsSeat", "ScarfWrap", "ScarfKnot",
	]))
	return names


func face_anchor_positions() -> Dictionary:
	var result := {}
	if not is_instance_valid(_face_anchor):
		return result
	for child in _face_anchor.get_children():
		if child is Node3D:
			result[child.name] = (child as Node3D).position
	return result


func missing_palette_tokens() -> PackedStringArray:
	return _missing_tokens


# ------------------------------------------------------------- construction

func _build_torso() -> void:
	var torso := _add_static_mesh(
		_torso_motion_pivot, "TorsoSkin",
		Forge.lathe(TORSO_PROFILE, 28, TORSO_SCALE),
		_soft_material(_token_color("skin"))
	)
	_naked_parts.append(torso)


func _build_head() -> void:
	_add_static_mesh(
		_head_pivot, "HeadMesh",
		Forge.lathe(HEAD_PROFILE, 30, HEAD_SCALE, FACE_FLATTEN),
		_soft_material(_token_color("skin"))
	)
	for side in [-1.0, 1.0]:
		var ear := _add_static_mesh(
			_head_pivot,
			"Ear%s" % ("Left" if side < 0.0 else "Right"),
			_unit_sphere_mesh(),
			_soft_material(_token_color("skin"))
		)
		ear.position = Vector3(side * 0.100, -0.012, 0.004)
		ear.scale = Vector3(0.011, 0.016, 0.012)
		ear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_hair() -> void:
	_hair_root = Node3D.new()
	_hair_root.name = "Hair"
	_head_pivot.add_child(_hair_root)
	var hair_material := _soft_material(_token_color("hair"))

	# A high, clean hairline leaves the forehead and ears visible. The scalp is
	# only the connective crown/rear mass; the readable silhouette comes from
	# five deliberately authored tapered locks below, never repeated spheres.
	var cap := _add_static_mesh(
		_hair_root, "ScalpCap",
		Forge.scalp(
			HEAD_PROFILE, 0.0055, 30, HEAD_SCALE, FACE_FLATTEN,
			0.052, 0.014, -0.038
		),
		hair_material
	)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_add_hair_lock(
		"FrontSweep",
		[
			Vector3(0.054, 0.091, -0.050),
			Vector3(0.032, 0.073, -0.070),
			Vector3(-0.004, 0.057, -0.080),
			Vector3(-0.038, 0.044, -0.078),
			Vector3(-0.052, 0.036, -0.072),
		],
		[0.015, 0.023, 0.025, 0.016, 0.0035], hair_material, 0.56, 1.20
	)
	_add_hair_lock(
		"TempleLeft",
		[
			Vector3(-0.060, 0.076, -0.047),
			Vector3(-0.081, 0.057, -0.040),
			Vector3(-0.091, 0.030, -0.025),
			Vector3(-0.090, 0.011, -0.010),
		],
		[0.015, 0.018, 0.013, 0.0035], hair_material, 0.62, 0.92
	)
	_add_hair_lock(
		"TempleRight",
		[
			Vector3(0.073, 0.075, -0.038),
			Vector3(0.087, 0.054, -0.028),
			Vector3(0.093, 0.031, -0.012),
			Vector3(0.090, 0.016, 0.002),
		],
		[0.014, 0.017, 0.012, 0.0035], hair_material, 0.60, 0.90
	)
	_add_hair_lock(
		"BackVolume",
		[
			Vector3(-0.050, 0.073, 0.052),
			Vector3(-0.024, 0.052, 0.081),
			Vector3(0.018, 0.024, 0.088),
			Vector3(0.045, -0.004, 0.076),
			Vector3(0.031, -0.021, 0.067),
		],
		[0.016, 0.023, 0.024, 0.016, 0.0035], hair_material, 0.76, 1.16
	)
	_add_hair_lock(
		"CrownLock",
		[
			Vector3(-0.038, 0.091, 0.012),
			Vector3(-0.012, 0.106, 0.006),
			Vector3(0.019, 0.104, -0.002),
			Vector3(0.040, 0.095, -0.011),
		],
		[0.008, 0.011, 0.009, 0.003], hair_material, 0.60, 1.02
	)


func _build_face() -> void:
	_face_anchor = Node3D.new()
	_face_anchor.name = "FaceAnchor"
	_head_pivot.add_child(_face_anchor)
	var white := _token_color("eye_white")
	var ink := _token_color("eye_ink")

	for side in [-1.0, 1.0]:
		var side_name := "Left" if side < 0.0 else "Right"
		var eye_anchor := _surface_anchor(
			"Eye%sAnchor" % side_name,
			Vector2(side * EYE_CENTER_X, EYE_CENTER_Y),
			0.0045,
			side * deg_to_rad(6.0)
		)
		_eye_anchors.append(eye_anchor)
		var eye_white := _add_feature(
			eye_anchor, "EyeWhite%s" % side_name, Vector3.ZERO,
			Vector3(EYE_WHITE_HALF.x, EYE_WHITE_HALF.y, 0.005), white
		)
		eye_white.rotation.z = side * 0.05
		var pupil := _add_feature(
			eye_anchor, "Pupil%s" % side_name, Vector3(0.0, -0.0015, 0.0058),
			Vector3(
				EYE_WHITE_HALF.x * PUPIL_RATIO,
				EYE_WHITE_HALF.y * PUPIL_RATIO,
				0.004
			),
			ink
		)
		pupil.set_meta("base_scale", pupil.scale)
		_pupils.append(pupil)
		_add_feature(
			eye_anchor, "Catchlight%s" % side_name,
			Vector3(-side * 0.0045, 0.0065, 0.0102),
			Vector3(0.0035, 0.0042, 0.002), white
		)
		_add_feature(
			eye_anchor, "Sparkle%s" % side_name,
			Vector3(side * 0.0035, -0.0075, 0.0102),
			Vector3(0.0016, 0.0019, 0.0015), white
		)

	var nose_anchor := _surface_anchor("NoseAnchor", Vector2(0.0, -0.034), 0.003)
	_add_feature(
		nose_anchor, "Nose", Vector3.ZERO,
		Vector3(0.0085, 0.0055, 0.004), _token_color("skin_shadow")
	)

	var mouth_anchor := _surface_anchor(
		"MouthAnchor", Vector2(0.0, -0.062), 0.0045
	)
	var smile := MeshInstance3D.new()
	smile.name = "MouthSmile"
	smile.mesh = _smile_arc_mesh(0.016, 0.0029)
	smile.material_override = _flat_material(ink)
	smile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mouth_anchor.add_child(smile)
	_mouth_states["smile"] = smile
	var open_mouth := _add_feature(
		mouth_anchor, "MouthOpen", Vector3.ZERO,
		Vector3(0.0085, 0.011, 0.004), _token_color("mouth")
	)
	open_mouth.visible = false
	_mouth_states["open"] = open_mouth
	var dash := _add_feature(
		mouth_anchor, "MouthDash", Vector3.ZERO,
		Vector3(0.010, 0.0028, 0.003), ink
	)
	dash.visible = false
	_mouth_states["dash"] = dash

	for side in [-1.0, 1.0]:
		var side_name := "Left" if side < 0.0 else "Right"
		var blush_anchor := _surface_anchor(
			"Blush%sAnchor" % side_name,
			Vector2(side * 0.063, -0.052),
			0.002
		)
		_add_feature(
			blush_anchor, "Blush%s" % side_name, Vector3.ZERO,
			Vector3(0.0135, 0.0075, 0.003), _token_color("blush")
		)


func _build_garments() -> void:
	var shirt := _add_static_mesh(
		_torso_motion_pivot, "ShirtTorso",
		Forge.lathe(SHIRT_PROFILE, 28, TORSO_SCALE),
		_soft_material(_token_color("shirt"))
	)
	var seat := _add_static_mesh(
		_body_pivot, "OverallsSeat",
		Forge.lathe(SEAT_PROFILE, 28, TORSO_SCALE * Vector3(1.03, 1.0, 1.03)),
		_soft_material(_token_color("overalls"))
	)
	_dressed_parts.append_array([shirt, seat])

	# Scarf: a snug wrap tucked under the chin, with a small knot and two
	# short hanging tails on the chest.
	var wrap := _add_static_mesh(
		_torso_motion_pivot, "ScarfWrap", _scarf_torus_mesh(),
		_soft_material(_token_color("scarf"))
	)
	wrap.position = Vector3(0.0, 0.086, -0.002)
	wrap.scale = Vector3(1.02, 0.72, 1.0)
	var knot := _add_static_mesh(
		_torso_motion_pivot, "ScarfKnot", _unit_sphere_mesh(),
		_soft_material(_token_color("scarf"))
	)
	knot.position = Vector3(0.006, 0.070, -0.043)
	knot.scale = Vector3.ONE * 0.0105
	var tail_a := _add_static_mesh(
		_torso_motion_pivot, "ScarfTailA", _unit_sphere_mesh(),
		_soft_material(_token_color("scarf"))
	)
	tail_a.position = Vector3(0.014, 0.053, -0.047)
	tail_a.scale = Vector3(0.009, 0.017, 0.006)
	tail_a.rotation.z = -0.18
	var tail_b := _add_static_mesh(
		_torso_motion_pivot, "ScarfTailB", _unit_sphere_mesh(),
		_soft_material(_token_color("scarf"))
	)
	tail_b.position = Vector3(0.000, 0.050, -0.048)
	tail_b.scale = Vector3(0.0075, 0.014, 0.005)
	tail_b.rotation.z = 0.14
	_dressed_parts.append_array([wrap, knot, tail_a, tail_b])


func _build_limb_surfaces() -> void:
	for sweep_name in [
		"ArmLeft", "ArmRight", "LegLeft", "LegRight",
		"SleeveLeft", "SleeveRight", "ArmSkinLeft", "ArmSkinRight",
		"TrouserLeft", "TrouserRight", "ShinLeft", "ShinRight",
	]:
		var token := "skin"
		if sweep_name.begins_with("Sleeve"):
			token = "shirt"
		elif sweep_name.begins_with("Trouser"):
			token = "overalls"
		var surface := MeshInstance3D.new()
		surface.name = sweep_name
		surface.material_override = _soft_material(_token_color(token))
		add_child(surface)
		_sweeps[sweep_name] = surface
		var is_naked_only: bool = (
			sweep_name.begins_with("ArmL") or sweep_name.begins_with("ArmR")
			or sweep_name.begins_with("LegL") or sweep_name.begins_with("LegR")
		)
		if is_naked_only:
			_naked_parts.append(surface)
		else:
			_dressed_parts.append(surface)

	for side in [-1.0, 1.0]:
		var side_name := "Left" if side < 0.0 else "Right"
		var foot := MeshInstance3D.new()
		foot.name = "Foot%s" % side_name
		foot.mesh = _unit_sphere_mesh()
		foot.material_override = _soft_material(_token_color("skin"))
		foot.scale = Vector3(0.022, 0.015, 0.035)
		add_child(foot)
		_naked_feet.append(foot)
		_naked_parts.append(foot)


func _build_shoes() -> void:
	for side in [-1.0, 1.0]:
		var side_name := "Left" if side < 0.0 else "Right"
		var shoe := Node3D.new()
		shoe.name = "Shoe%s" % side_name
		add_child(shoe)
		var sole := _add_static_mesh(
			shoe, "Sole", _unit_sphere_mesh(),
			_soft_material(_token_color("sole"))
		)
		sole.position = Vector3(0.0, 0.007, -0.010)
		sole.scale = Vector3(0.026, 0.009, 0.045)
		var upper := _add_static_mesh(
			shoe, "Upper", _unit_sphere_mesh(),
			_soft_material(_token_color("shoe"))
		)
		upper.position = Vector3(0.0, 0.021, -0.011)
		upper.scale = Vector3(0.024, 0.022, 0.039)
		_shoes.append(shoe)
		_dressed_parts.append(shoe)


func _build_contact_shadow() -> void:
	# Shadow-map bias at toy scale pushes the real contact shadow away from
	# the feet; a soft authored blob keeps the character visually planted.
	var vertices := PackedVector3Array()
	var vertex_colors := PackedColorArray()
	var indices := PackedInt32Array()
	var segments := 24
	vertices.append(Vector3(0.0, 0.0, -0.006))
	vertex_colors.append(Color(0.0, 0.0, 0.0, 0.26))
	for segment in range(segments + 1):
		var angle := TAU * float(segment) / float(segments)
		vertices.append(
			Vector3(cos(angle) * 0.102, 0.0, sin(angle) * 0.102 - 0.006)
		)
		vertex_colors.append(Color(0.0, 0.0, 0.0, 0.0))
	for segment in segments:
		indices.append(0)
		indices.append(1 + segment + 1)
		indices.append(1 + segment)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = vertex_colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var blob := MeshInstance3D.new()
	blob.name = "ContactShadow"
	blob.mesh = mesh
	blob.position = Vector3(0.0, 0.004, 0.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	blob.material_override = material
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blob)


# ------------------------------------------------------------------- pose

func _update_arms(body: Transform3D, arm_anchors: Array) -> void:
	for arm_index in 2:
		var anchor: Dictionary = (
			arm_anchors[arm_index] if arm_index < arm_anchors.size() else {}
		)
		var fallback_side := -1.0 if arm_index == 0 else 1.0
		var shoulder: Vector3 = anchor.get(
			"shoulder", body * Vector3(fallback_side * 0.070, 0.062, 0.0)
		)
		var side := -1.0 if (body.affine_inverse() * shoulder).x < 0.0 else 1.0
		var side_name := "Left" if side < 0.0 else "Right"
		var hand: Vector3 = anchor.get("hand", shoulder + Vector3.DOWN * 0.13)
		# Authored relaxed elbow: mostly backward, a whisper outward.
		var elbow := _two_bone_joint(
			shoulder, hand, 0.072, 0.068,
			body.basis * Vector3(side * 0.22, -0.08, 0.86)
		)
		var palm_direction := (
			(hand - elbow).normalized() * 0.6
			+ body.basis * Vector3(-side * 0.42, -0.55, -0.12)
		).normalized()
		var palm_end := hand + palm_direction * 0.021
		# The sweep root starts inside the torso so the shoulder cap never
		# reads as a detached bump beside the neck.
		var arm_root := shoulder + body.basis * Vector3(
			-side * 0.016, -0.006, 0.0
		)
		_set_sweep(
			"Arm%s" % side_name,
			[arm_root, elbow, hand, palm_end], ARM_RADII
		)
		if _dressed:
			_set_sweep(
				"Sleeve%s" % side_name,
				[arm_root, arm_root.lerp(elbow, 0.70)], SLEEVE_RADII
			)
			_set_sweep(
				"ArmSkin%s" % side_name,
				[arm_root.lerp(elbow, 0.52), elbow, hand, palm_end],
				ARM_SKIN_RADII
			)


func _update_legs(body: Transform3D, leg_anchors: Array) -> void:
	var yaw := body.basis.get_euler().y
	for leg_index in 2:
		var anchor: Dictionary = (
			leg_anchors[leg_index] if leg_index < leg_anchors.size() else {}
		)
		var fallback_side := -1.0 if leg_index == 0 else 1.0
		var hip: Vector3 = anchor.get(
			"hip", body * Vector3(fallback_side * 0.042, -0.093, 0.0)
		)
		var side := -1.0 if (body.affine_inverse() * hip).x < 0.0 else 1.0
		var side_name := "Left" if side < 0.0 else "Right"
		var foot: Vector3 = anchor.get("foot", Vector3(hip.x, FOOT_REST_Y, hip.z))
		var ankle := Vector3(foot.x, foot.y + 0.020, foot.z)
		var knee: Vector3 = anchor.get("knee", hip.lerp(ankle, 0.5))
		var hip_tucked := hip + Vector3.UP * 0.014
		_set_sweep(
			"Leg%s" % side_name, [hip_tucked, knee, ankle], LEG_RADII
		)
		if _dressed:
			_set_sweep(
				"Trouser%s" % side_name,
				[hip_tucked, knee, knee.lerp(ankle, 0.44)], TROUSER_RADII
			)
			_set_sweep(
				"Shin%s" % side_name,
				[knee.lerp(ankle, 0.30), ankle], SHIN_RADII
			)
		var lift := maxf(foot.y - FOOT_REST_Y, 0.0)
		var foot_pitch := float(anchor.get("foot_pitch", 0.0))
		var shoe := _shoes[leg_index] as Node3D
		shoe.position = Vector3(foot.x, lift, foot.z)
		shoe.rotation = Vector3(
			foot_pitch, yaw + side * FOOT_OUT_ANGLE, 0.0
		)
		if not _naked_feet.is_empty():
			var naked_foot := _naked_feet[leg_index]
			naked_foot.position = Vector3(foot.x, lift + 0.013, foot.z - 0.008)
			naked_foot.rotation = Vector3(
				foot_pitch, yaw + side * FOOT_OUT_ANGLE, 0.0
			)


func _set_sweep(sweep_name: String, points: Array, radii: Array) -> void:
	var surface := _sweeps.get(sweep_name) as MeshInstance3D
	if surface == null or (not surface.visible and surface.mesh != null):
		return
	surface.mesh = Forge.sweep(points, radii)


func _two_bone_joint(
	root: Vector3,
	tip: Vector3,
	upper_length: float,
	lower_length: float,
	bend_hint: Vector3
) -> Vector3:
	var span := tip - root
	var span_length := clampf(
		span.length(), 0.0001, upper_length + lower_length - 0.0005
	)
	var along := clampf(
		(
			span_length * span_length
			+ upper_length * upper_length
			- lower_length * lower_length
		) / (2.0 * span_length),
		0.0, upper_length
	)
	var lift := sqrt(maxf(upper_length * upper_length - along * along, 0.0))
	var axis := span / span_length
	var bend := (bend_hint - axis * bend_hint.dot(axis)).normalized()
	if not bend.is_finite() or bend.length_squared() < 0.5:
		bend = Vector3.FORWARD
	return root + axis * along + bend * lift


# ------------------------------------------------------------------- face

func _surface_anchor(
	anchor_name: String,
	face_offset: Vector2,
	lift: float,
	extra_yaw := 0.0
) -> Node3D:
	var projected := _project_to_face(face_offset)
	var surface_position: Vector3 = projected.position
	var surface_normal: Vector3 = projected.normal
	var axis_z: Vector3 = surface_normal.rotated(Vector3.UP, extra_yaw)
	var axis_x := axis_z.cross(Vector3.UP).normalized()
	if axis_x.length_squared() < 0.001:
		axis_x = Vector3.RIGHT
	var axis_y := axis_x.cross(axis_z).normalized()
	var anchor := Node3D.new()
	anchor.name = anchor_name
	anchor.transform = Transform3D(
		Basis(axis_x, axis_y, axis_z).orthonormalized(),
		surface_position + surface_normal * lift
	)
	_face_anchor.add_child(anchor)
	return anchor


func _project_to_face(face_offset: Vector2) -> Dictionary:
	# Analytic stand-in for the lathed head's front surface.
	var radii := Vector3(0.098, 0.106, 0.076)
	var center := Vector3(0.0, -0.004, 0.0)
	var x := face_offset.x
	var y := face_offset.y - center.y
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
	return {
		"position": center + Vector3(x, y, z),
		"normal": normal,
	}


func _smile_arc_mesh(radius: float, thickness: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var arc_segments := 12
	var tube_segments := 8
	var arc_start := deg_to_rad(210.0)
	var arc_end := deg_to_rad(330.0)
	for arc_index in range(arc_segments + 1):
		var arc_angle := lerpf(
			arc_start, arc_end, float(arc_index) / float(arc_segments)
		)
		var ring_center := Vector3(
			cos(arc_angle) * radius,
			sin(arc_angle) * radius + radius * 0.55,
			0.0
		)
		for tube_index in range(tube_segments + 1):
			var tube_angle := TAU * float(tube_index) / float(tube_segments)
			var radial := (
				Vector3(cos(arc_angle), sin(arc_angle), 0.0) * cos(tube_angle)
				+ Vector3(0.0, 0.0, 1.0) * sin(tube_angle)
			)
			vertices.append(ring_center + radial * thickness)
			normals.append(radial.normalized())
			if arc_index < arc_segments and tube_index < tube_segments:
				var a := arc_index * (tube_segments + 1) + tube_index
				var b := a + 1
				var c := a + tube_segments + 1
				var d := c + 1
				indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_feature(
	parent: Node3D,
	feature_name: String,
	position_value: Vector3,
	size_value: Vector3,
	color: Color
) -> MeshInstance3D:
	var feature := MeshInstance3D.new()
	feature.name = feature_name
	feature.mesh = _unit_sphere_mesh()
	feature.position = position_value
	feature.scale = size_value
	feature.material_override = _flat_material(color)
	feature.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(feature)
	return feature


func _advance_blink(delta: float) -> void:
	if _expression != "normal" or _eye_anchors.is_empty():
		return
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = randf_range(2.4, 5.4)
		_blink_phase = 0.13
	if _blink_phase <= 0.0:
		return
	_blink_phase = maxf(_blink_phase - delta, 0.0)
	var closed := sin(PI * clampf(_blink_phase / 0.13, 0.0, 1.0))
	for eye_anchor in _eye_anchors:
		eye_anchor.scale = Vector3(1.0, 1.0 - 0.93 * closed, 1.0)


# -------------------------------------------------------------- helpers

func _add_hair_lock(
	lock_name: String,
	points: Array,
	radii: Array,
	material: Material,
	depth_scale: float,
	width_scale: float
) -> void:
	var lock := _add_static_mesh(
		_hair_root, lock_name,
		Forge.sweep(
			points, radii, 12, 18, Vector2(depth_scale, width_scale)
		),
		material
	)
	lock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_static_mesh(
	parent: Node3D,
	mesh_name: String,
	mesh: Mesh,
	material: Material
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _token_color(role: String) -> Color:
	if _resolved_tokens.has(role):
		return _resolved_tokens[role]
	var palette := PaletteDefinition.shared()
	var token := String(PALETTE_TOKENS.get(role, ""))
	var resolved: Color
	if palette.has_color(token):
		resolved = palette.color(token)
	elif palette.swatches.get(token) is Color:
		resolved = palette.swatches[token]
	else:
		push_error(
			"HumanIslanderBodyV2: palette token '%s' (role '%s') is missing"
			% [token, role]
		)
		if role not in _missing_tokens:
			_missing_tokens.append(role)
		resolved = palette.color("debug_missing")
	_resolved_tokens[role] = resolved
	return resolved


func _soft_material(color: Color) -> StandardMaterial3D:
	# The premium-toy response: matte, zero specular, soft scene lighting —
	# the same family the approved props use, so the player sits in-world.
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.0
	material.roughness = 0.95
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.0
	material.roughness = 0.9
	material.disable_receive_shadows = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _scarf_torus_mesh() -> TorusMesh:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.023
	torus.outer_radius = 0.045
	torus.rings = 32
	torus.ring_segments = 16
	return torus


func _unit_sphere_mesh() -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	return sphere
