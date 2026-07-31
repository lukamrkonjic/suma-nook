@tool
class_name PigeonFaceRig
extends Node3D

## Reimport-safe procedural 3D face for the Surma pigeon mascot.
## +X = mascot right, +Y = up, -Z = forward/out through the face.

enum EyeExpression {
	NEUTRAL,
	HAPPY,
	SLEEPY,
	SURPRISED,
}

const EYE_WHITE_COLOR := Color("f5f3ee")
const PUPIL_COLOR := Color("424651")
const CATCHLIGHT_COLOR := Color("ffffff")
const UPPER_BEAK_COLOR := Color("ff8f6e")
const LOWER_BEAK_COLOR := Color("e86a58")
const MOUTH_COLOR := Color("542731")

const BLINK_CLOSE_SECONDS := 0.055
const BLINK_HOLD_SECONDS := 0.035
const BLINK_OPEN_SECONDS := 0.075
const WINK_HOLD_SECONDS := 0.16
const DEFAULT_SYLLABLES_PER_SECOND := 7.2

@export_range(0.01, 2.0, 0.001, "suffix:m") var head_width: float = 0.20
@export var automatic_blinking: bool = true
@export_range(2.6, 5.8, 0.1, "suffix:s") var blink_interval_min: float = 2.6
@export_range(2.6, 5.8, 0.1, "suffix:s") var blink_interval_max: float = 5.8
@export_range(0.0, 1.0, 0.01) var double_blink_chance: float = 0.12
@export_range(1.0, 20.0, 0.1) var pupil_follow_speed: float = 10.0
@export var subtle_idle_eye_motion: bool = true

var _expression := EyeExpression.NEUTRAL
var _built := false
var _rng := RandomNumberGenerator.new()
var _next_blink_seconds := 3.5
var _auto_blink_running := false
var _eye_busy: Array[bool] = [false, false]

var _eye_roots: Array[Node3D] = []
var _open_groups: Array[Node3D] = []
var _eye_whites: Array[MeshInstance3D] = []
var _pupil_pivots: Array[Node3D] = []
var _pupils: Array[MeshInstance3D] = []
var _catchlights: Array[MeshInstance3D] = []
var _happy_arcs: Array[MeshInstance3D] = []
var _blink_lines: Array[MeshInstance3D] = []
var _pupil_base_z: Array[float] = []
var _target_pupil_direction := Vector2(-0.38, 0.18)
var _look_override_seconds := 0.0
var _idle_look_seconds := 1.4

var _upper_beak_pivot: Node3D
var _lower_beak_pivot: Node3D
var _mouth_interior: MeshInstance3D
var _upper_beak_rest_position := Vector3.ZERO
var _lower_beak_rest_position := Vector3.ZERO
var _talking := false
var _voice_driven := false
var _syllables_per_second := DEFAULT_SYLLABLES_PER_SECOND
var _speech_phase := 0.0
var _talk_amount := 0.0
var _target_talk_amount := 0.0


func _ready() -> void:
	_rng.randomize()
	_build_face()
	_apply_expression()
	_apply_beak_pose(0.0)
	_next_blink_seconds = _rng.randf_range(blink_interval_min, blink_interval_max)
	set_process(not Engine.is_editor_hint())


func _process(delta: float) -> void:
	_update_idle_eye_motion(delta)
	_update_pupils(delta)
	_update_speech(delta)
	_update_automatic_blink(delta)


func set_expression(expression: EyeExpression) -> void:
	_expression = expression
	if _built:
		_apply_expression()


func get_expression() -> EyeExpression:
	return _expression


func set_pupil_direction(direction: Vector2) -> void:
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	_target_pupil_direction = Vector2(
		clampf(direction.x, -1.0, 1.0),
		clampf(direction.y, -1.0, 1.0)
	)
	_look_override_seconds = 0.45


func look_at_world_point(world_point: Vector3) -> void:
	var local_target := to_local(world_point)
	# Targets behind the bird return the pupils toward center.
	if local_target.z >= -0.001:
		set_pupil_direction(Vector2.ZERO)
		return
	var perspective := Vector2(local_target.x, local_target.y) / maxf(-local_target.z, 0.001)
	set_pupil_direction(perspective * 1.15)


func blink() -> void:
	if _expression == EyeExpression.HAPPY or _eye_busy[0] or _eye_busy[1]:
		return
	_animate_eye_close(0, BLINK_CLOSE_SECONDS, BLINK_HOLD_SECONDS, BLINK_OPEN_SECONDS)
	_animate_eye_close(1, BLINK_CLOSE_SECONDS, BLINK_HOLD_SECONDS, BLINK_OPEN_SECONDS)
	await get_tree().create_timer(
		BLINK_CLOSE_SECONDS + BLINK_HOLD_SECONDS + BLINK_OPEN_SECONDS
	).timeout


func wink_left() -> void:
	if _expression != EyeExpression.HAPPY and not _eye_busy[0]:
		await _animate_eye_close(0, BLINK_CLOSE_SECONDS, WINK_HOLD_SECONDS, BLINK_OPEN_SECONDS)


func wink_right() -> void:
	if _expression != EyeExpression.HAPPY and not _eye_busy[1]:
		await _animate_eye_close(1, BLINK_CLOSE_SECONDS, WINK_HOLD_SECONDS, BLINK_OPEN_SECONDS)


func set_talking(active: bool, syllables_per_second: float = -1.0) -> void:
	_talking = active
	_voice_driven = false
	if syllables_per_second > 0.0:
		_syllables_per_second = syllables_per_second
	elif _syllables_per_second <= 0.0:
		_syllables_per_second = DEFAULT_SYLLABLES_PER_SECOND
	if active:
		_speech_phase = 0.0
	else:
		_target_talk_amount = 0.0


func set_voice_amplitude(value_0_to_1: float) -> void:
	_talking = false
	_voice_driven = true
	_target_talk_amount = clampf(value_0_to_1, 0.0, 1.0)


func set_talk_amount(value_0_to_1: float) -> void:
	set_voice_amplitude(value_0_to_1)


func talk_for(seconds: float, syllables_per_second: float = -1.0) -> void:
	set_talking(true, syllables_per_second)
	await get_tree().create_timer(maxf(seconds, 0.0)).timeout
	set_talking(false)


func _build_face() -> void:
	if _built:
		return
	_built = true

	var geometry := Node3D.new()
	geometry.name = "FaceGeometry"
	add_child(geometry)

	var eye_white_material := _make_material(EYE_WHITE_COLOR)
	var pupil_material := _make_material(PUPIL_COLOR)
	var catchlight_material := _make_material(CATCHLIGHT_COLOR)
	var upper_beak_material := _make_material(UPPER_BEAK_COLOR)
	var lower_beak_material := _make_material(LOWER_BEAK_COLOR)
	var mouth_material := _make_material(MOUTH_COLOR)

	var eyes := Node3D.new()
	eyes.name = "Eyes"
	geometry.add_child(eyes)
	_build_eye(eyes, "Left", -0.155 * head_width, 8.0, eye_white_material, pupil_material, catchlight_material)
	_build_eye(eyes, "Right", 0.155 * head_width, -8.0, eye_white_material, pupil_material, catchlight_material)

	var beak := Node3D.new()
	beak.name = "Beak"
	geometry.add_child(beak)
	_build_beak(beak, upper_beak_material, lower_beak_material, mouth_material)


func _build_eye(
	parent: Node3D,
	side_name: String,
	x_position: float,
	yaw_degrees: float,
	eye_white_material: StandardMaterial3D,
	pupil_material: StandardMaterial3D,
	catchlight_material: StandardMaterial3D
) -> void:
	var eye_width := 0.30 * head_width
	var eye_height := 0.30 * head_width
	var eye_depth := 0.065 * head_width
	var pupil_width := 0.72 * eye_width
	var pupil_height := 0.72 * eye_height
	var pupil_depth := 0.56 * eye_depth
	var catchlight_diameter := 0.20 * pupil_width

	var eye_root := Node3D.new()
	eye_root.name = "Eye%s" % side_name
	eye_root.position = Vector3(x_position, 0.055 * head_width, -0.030 * head_width)
	eye_root.rotation.y = deg_to_rad(yaw_degrees)
	parent.add_child(eye_root)
	_eye_roots.append(eye_root)

	var open_group := Node3D.new()
	open_group.name = "OpenGroup"
	eye_root.add_child(open_group)
	_open_groups.append(open_group)

	var eye_white := _make_sphere_instance(
		"EyeWhite%s" % side_name,
		Vector3(eye_width, eye_height, eye_depth),
		eye_white_material
	)
	open_group.add_child(eye_white)
	_eye_whites.append(eye_white)

	var pupil_pivot := Node3D.new()
	pupil_pivot.name = "PupilPivot%s" % side_name
	pupil_pivot.position.z = -(eye_depth * 0.5 + pupil_depth * 0.42)
	open_group.add_child(pupil_pivot)
	_pupil_pivots.append(pupil_pivot)
	_pupil_base_z.append(pupil_pivot.position.z)

	var pupil := _make_sphere_instance(
		"Pupil%s" % side_name,
		Vector3(pupil_width, pupil_height, pupil_depth),
		pupil_material
	)
	pupil_pivot.add_child(pupil)
	_pupils.append(pupil)

	var catchlight := _make_sphere_instance(
		"Catchlight%s" % side_name,
		Vector3(catchlight_diameter, catchlight_diameter, catchlight_diameter * 0.34),
		catchlight_material
	)
	catchlight.position = Vector3(
		-pupil_width * 0.17,
		pupil_height * 0.17,
		-pupil_depth * 0.48
	)
	pupil_pivot.add_child(catchlight)
	_catchlights.append(catchlight)

	var happy_arc := MeshInstance3D.new()
	happy_arc.name = "HappyArc%s" % side_name
	happy_arc.mesh = _make_happy_arc_mesh(eye_width * 0.90, eye_height * 0.30, eye_height * 0.09)
	happy_arc.material_override = pupil_material
	happy_arc.position.z = -(eye_depth * 0.5 + pupil_depth * 0.55)
	_disable_small_mesh_shadow(happy_arc)
	eye_root.add_child(happy_arc)
	_happy_arcs.append(happy_arc)

	var blink_line := MeshInstance3D.new()
	blink_line.name = "BlinkLine%s" % side_name
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(eye_width * 0.84, eye_height * 0.085, eye_depth * 0.16)
	blink_line.mesh = line_mesh
	blink_line.material_override = pupil_material
	blink_line.position.z = -(eye_depth * 0.5 + pupil_depth * 0.55)
	_disable_small_mesh_shadow(blink_line)
	eye_root.add_child(blink_line)
	_blink_lines.append(blink_line)


func _build_beak(
	parent: Node3D,
	upper_material: StandardMaterial3D,
	lower_material: StandardMaterial3D,
	mouth_material: StandardMaterial3D
) -> void:
	var width := 0.28 * head_width
	var length := 0.27 * head_width
	var upper_height := 0.105 * head_width
	var lower_height := 0.078 * head_width
	var hinge := Vector3(0.0, -0.110 * head_width, -0.025 * head_width)

	_upper_beak_pivot = Node3D.new()
	_upper_beak_pivot.name = "UpperBeakPivot"
	_upper_beak_pivot.position = hinge
	parent.add_child(_upper_beak_pivot)
	_upper_beak_rest_position = hinge

	var upper_beak := MeshInstance3D.new()
	upper_beak.name = "UpperBeak"
	upper_beak.mesh = _make_polyhedron(
		[
			Vector3(-width * 0.5, 0.0, 0.0),
			Vector3(0.0, upper_height, 0.0),
			Vector3(width * 0.5, 0.0, 0.0),
			Vector3(0.0, 0.0, -length),
		],
		[[0, 1, 3], [1, 2, 3], [0, 3, 2], [0, 2, 1]]
	)
	upper_beak.material_override = upper_material
	_disable_small_mesh_shadow(upper_beak)
	_upper_beak_pivot.add_child(upper_beak)

	_lower_beak_pivot = Node3D.new()
	_lower_beak_pivot.name = "LowerBeakPivot"
	_lower_beak_pivot.position = hinge
	parent.add_child(_lower_beak_pivot)
	_lower_beak_rest_position = hinge

	var lower_beak := MeshInstance3D.new()
	lower_beak.name = "LowerBeak"
	lower_beak.mesh = _make_polyhedron(
		[
			Vector3(-width * 0.5, 0.0, 0.0),
			Vector3(0.0, -lower_height, 0.0),
			Vector3(width * 0.5, 0.0, 0.0),
			Vector3(0.0, 0.0, -length),
		],
		[[0, 3, 1], [1, 3, 2], [0, 2, 3], [0, 1, 2]]
	)
	lower_beak.material_override = lower_material
	_disable_small_mesh_shadow(lower_beak)
	_lower_beak_pivot.add_child(lower_beak)

	_mouth_interior = MeshInstance3D.new()
	_mouth_interior.name = "MouthInterior"
	var mouth_mesh := BoxMesh.new()
	mouth_mesh.size = Vector3(width * 0.76, (upper_height + lower_height) * 0.72, 0.002 * head_width)
	_mouth_interior.mesh = mouth_mesh
	_mouth_interior.material_override = mouth_material
	_mouth_interior.position = Vector3(0.0, hinge.y, hinge.z - length * 0.48)
	_disable_small_mesh_shadow(_mouth_interior)
	parent.add_child(_mouth_interior)


func _make_sphere_instance(
	mesh_name: String,
	dimensions: Vector3,
	material: StandardMaterial3D
) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = sphere
	instance.scale = dimensions
	instance.material_override = material
	_disable_small_mesh_shadow(instance)
	return instance


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.0
	material.roughness = 0.78
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _make_happy_arc_mesh(width: float, height: float, thickness: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var segments := 6
	for index in range(segments + 1):
		var ratio := float(index) / float(segments)
		var x := lerpf(-width * 0.5, width * 0.5, ratio)
		var normalized_x := x / (width * 0.5)
		var curve_y := height * (1.0 - normalized_x * normalized_x) - height * 0.45
		vertices.append(Vector3(x, curve_y + thickness * 0.5, 0.0))
		vertices.append(Vector3(x, curve_y - thickness * 0.5, 0.0))
		normals.append(Vector3(0.0, 0.0, -1.0))
		normals.append(Vector3(0.0, 0.0, -1.0))
	if segments > 0:
		for index in range(segments):
			var top_left := index * 2
			var bottom_left := top_left + 1
			var top_right := top_left + 2
			var bottom_right := top_left + 3
			indices.append_array([top_left, top_right, bottom_left, top_right, bottom_right, bottom_left])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_polyhedron(vertices: Array[Vector3], faces: Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: Array in faces:
		if face.size() == 3:
			for vertex_index: int in face:
				surface.add_vertex(vertices[vertex_index])
		elif face.size() == 4:
			for vertex_index: int in [face[0], face[1], face[2], face[0], face[2], face[3]]:
				surface.add_vertex(vertices[vertex_index])
	surface.generate_normals()
	return surface.commit()


func _disable_small_mesh_shadow(instance: MeshInstance3D) -> void:
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _apply_expression() -> void:
	if not _built:
		return
	var eye_width := 0.30 * head_width
	var eye_height := 0.30 * head_width
	var eye_depth := 0.065 * head_width
	for index in range(_open_groups.size()):
		_open_groups[index].visible = _expression != EyeExpression.HAPPY
		_happy_arcs[index].visible = _expression == EyeExpression.HAPPY
		_blink_lines[index].visible = false
		_open_groups[index].scale = Vector3(
			1.0,
			0.55 if _expression == EyeExpression.SLEEPY else 1.0,
			1.0
		)
		_eye_whites[index].scale = Vector3(
			eye_width * (1.08 if _expression == EyeExpression.SURPRISED else 1.0),
			eye_height * (1.12 if _expression == EyeExpression.SURPRISED else 1.0),
			eye_depth
		)
		var pupil_scale := 0.78 if _expression == EyeExpression.SURPRISED else 1.0
		_pupil_pivots[index].scale = Vector3.ONE * pupil_scale


func _update_idle_eye_motion(delta: float) -> void:
	if _look_override_seconds > 0.0:
		_look_override_seconds -= delta
		return
	if not subtle_idle_eye_motion:
		return
	_idle_look_seconds -= delta
	if _idle_look_seconds <= 0.0:
		# A shared, restrained glance reads as curiosity without going cross-eyed.
		_target_pupil_direction = Vector2(
			_rng.randf_range(-0.42, 0.18),
			_rng.randf_range(-0.08, 0.26)
		)
		_idle_look_seconds = _rng.randf_range(1.35, 2.45)


func _update_pupils(delta: float) -> void:
	if not _built:
		return
	var eye_width := 0.30 * head_width
	var eye_height := 0.30 * head_width
	var pupil_width := 0.72 * eye_width
	var pupil_height := 0.72 * eye_height
	# Use only 55% of the available border so pupils never touch the white edge.
	var max_offset := Vector2(
		(eye_width - pupil_width) * 0.5 * 0.55,
		(eye_height - pupil_height) * 0.5 * 0.55
	)
	var desired := Vector2(
		_target_pupil_direction.x * max_offset.x,
		_target_pupil_direction.y * max_offset.y
	)
	if _expression == EyeExpression.SLEEPY:
		desired.y -= eye_height * 0.08
	var response := 1.0 - exp(-pupil_follow_speed * delta)
	for index in range(_pupil_pivots.size()):
		var pivot := _pupil_pivots[index]
		var current := Vector2(pivot.position.x, pivot.position.y)
		current = current.lerp(desired, response)
		pivot.position = Vector3(current.x, current.y, _pupil_base_z[index])


func _animate_eye_close(index: int, close_time: float, hold_time: float, open_time: float) -> void:
	if index < 0 or index >= _open_groups.size() or _eye_busy[index]:
		return
	_eye_busy[index] = true
	var open_group := _open_groups[index]
	var blink_line := _blink_lines[index]
	var rest_scale := open_group.scale
	var close_scale := Vector3(rest_scale.x, 0.01, rest_scale.z)
	var close_tween := create_tween()
	close_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	close_tween.tween_property(open_group, "scale", close_scale, close_time)
	await close_tween.finished
	open_group.visible = false
	blink_line.visible = true
	await get_tree().create_timer(hold_time).timeout
	blink_line.visible = false
	open_group.visible = _expression != EyeExpression.HAPPY
	open_group.scale = close_scale
	if _expression != EyeExpression.HAPPY:
		var open_tween := create_tween()
		open_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		open_tween.tween_property(open_group, "scale", rest_scale, open_time)
		await open_tween.finished
	else:
		open_group.scale = rest_scale
	_eye_busy[index] = false


func _update_automatic_blink(delta: float) -> void:
	if not automatic_blinking or _expression == EyeExpression.HAPPY or _auto_blink_running:
		return
	_next_blink_seconds -= delta
	if _next_blink_seconds <= 0.0:
		_run_auto_blink_sequence()


func _run_auto_blink_sequence() -> void:
	_auto_blink_running = true
	await blink()
	if _rng.randf() < double_blink_chance:
		await get_tree().create_timer(0.12).timeout
		await blink()
	_next_blink_seconds = _rng.randf_range(blink_interval_min, blink_interval_max)
	_auto_blink_running = false


func _update_speech(delta: float) -> void:
	if not _built:
		return
	if _talking:
		_speech_phase += delta * maxf(_syllables_per_second, 0.01)
		var cycle := fmod(_speech_phase, 1.0)
		if cycle < 0.72:
			var pulse := sin((cycle / 0.72) * PI)
			var variation := 0.86 + 0.14 * sin(floor(_speech_phase) * 2.399 + 0.7)
			_target_talk_amount = pow(maxf(pulse, 0.0), 1.25) * variation
		else:
			_target_talk_amount = 0.0
	elif not _voice_driven:
		_target_talk_amount = 0.0
	_talk_amount = move_toward(_talk_amount, _target_talk_amount, delta * 13.5)
	_apply_beak_pose(_talk_amount)


func _apply_beak_pose(amount: float) -> void:
	if not is_instance_valid(_upper_beak_pivot) or not is_instance_valid(_lower_beak_pivot):
		return
	amount = clampf(amount, 0.0, 1.0)
	_upper_beak_pivot.rotation.x = deg_to_rad(3.5) * amount
	_lower_beak_pivot.rotation.x = deg_to_rad(-22.0) * amount
	_upper_beak_pivot.position = _upper_beak_rest_position
	_lower_beak_pivot.position = _lower_beak_rest_position + Vector3(
		0.0,
		-0.010 * head_width * amount,
		0.0
	)
	_mouth_interior.visible = amount > 0.02
