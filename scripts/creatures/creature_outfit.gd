class_name CreatureOutfit
extends Node3D
## Procedural clothing and equipables for ProceduralCreature: hats, shirts,
## pants, shoes, and held items built from unshaded primitives and re-seated
## on the creature's live pose anchors every tick, so garments ride squash,
## waddle, hops, and flight for free on any body plan.
##
## An outfit is a tiny JSON: {"hat": {"kind": "straw", "color": "#..."}, ...}
## Kinds — hat: cap | straw | cone; shirt: tee | scarf; pants: shorts;
## shoes: boots; held: fishing_rod | stick.

var _creature: Node3D
var _hat_root: Node3D
var _shirt_root: Node3D
var _shirt_base_scale := Vector3.ONE
var _scarf_root: Node3D
var _scarf_drop := 0.1
var _sleeve_roots: Array[Node3D] = []
var _pants_roots: Array[Node3D] = []
var _shoe_roots: Array[Node3D] = []
var _held_root: Node3D
var _held_tip_local := Vector3.ZERO
var _held_kind := ""


func build(outfit: Dictionary, creature: Node3D) -> void:
	_creature = creature
	var anchors: Dictionary = creature.call("pose_anchors")
	# The V2 human body owns shirt/trousers/scarf/shoes as native layers;
	# outfits then only contribute headwear and held equipment.
	var body_owns_clothing := bool(anchors.get("human_v2", false))
	if outfit.has("hat"):
		_build_hat(outfit.get("hat") as Dictionary, anchors)
	if outfit.has("shirt") and not body_owns_clothing:
		_build_shirt(outfit.get("shirt") as Dictionary, anchors)
	if outfit.has("pants") and not body_owns_clothing:
		_build_pants(outfit.get("pants") as Dictionary, anchors)
	if outfit.has("shoes") and not body_owns_clothing:
		_build_shoes(outfit.get("shoes") as Dictionary, anchors)
	if outfit.has("held"):
		_build_held(outfit.get("held") as Dictionary, anchors)
	if creature.has_signal("pose_advanced"):
		creature.connect("pose_advanced", _sync)
	_sync()


## World-space tip of the held item (fishing rod point) for line effects.
func held_tip_world() -> Vector3:
	if is_instance_valid(_held_root):
		return _held_root.to_global(_held_tip_local)
	return global_position


## Creature-local tip position for deterministic action contracts and effects
## that already operate in the procedural body's coordinate space.
func held_tip_position() -> Vector3:
	if is_instance_valid(_held_root):
		return _held_root.transform * _held_tip_local
	return Vector3.ZERO


## Replace only the held item while preserving the player's native clothing.
## An empty dictionary clears the hand, which lets the equipment system keep
## the visible procedural hierarchy in sync with gameplay state.
func set_held(item: Dictionary) -> void:
	if is_instance_valid(_held_root):
		_held_root.free()
	_held_root = null
	_held_kind = ""
	_held_tip_local = Vector3.ZERO
	if item.is_empty() or _creature == null:
		return
	_build_held(item, _creature.call("pose_anchors") as Dictionary)
	_sync()


func _sync() -> void:
	if _creature == null:
		return
	var anchors: Dictionary = _creature.call("pose_anchors")
	var head: Transform3D = anchors.get("head", Transform3D.IDENTITY)
	var body: Transform3D = anchors.get("body", Transform3D.IDENTITY)
	var arms: Array = anchors.get("arms", [])
	var legs: Array = anchors.get("legs", [])

	if is_instance_valid(_hat_root):
		_hat_root.transform = head
	if is_instance_valid(_shirt_root):
		# The shirt breathes with the torso so the skin never pokes through.
		_shirt_root.transform = body
		_shirt_root.scale = _shirt_base_scale * float(anchors.get("breath", 1.0))
	if is_instance_valid(_scarf_root):
		_scarf_root.transform = Transform3D(
			head.basis, head.origin - head.basis.y * _scarf_drop
		)
	for pants_index in _pants_roots.size():
		if pants_index >= legs.size():
			break
		var leg := legs[pants_index] as Dictionary
		var hip := leg.get("hip") as Vector3
		var knee := leg.get("knee") as Vector3
		_pants_roots[pants_index].transform = _segment_transform(
			hip.lerp(knee, -0.08), hip.lerp(knee, 0.7)
		)
	for shoe_index in _shoe_roots.size():
		if shoe_index >= legs.size():
			break
		var leg := legs[shoe_index] as Dictionary
		_shoe_roots[shoe_index].transform = Transform3D(
			Basis.from_euler(Vector3(0.0, body.basis.get_euler().y, 0.0)),
			leg.get("foot") as Vector3
		)
	if is_instance_valid(_held_root) and not arms.is_empty():
		var uses_two_hands := (
			_held_kind in ["axe", "pickaxe", "fishing_rod"]
			and arms.size() >= 2
			and _creature.has_method("two_handed_action_active")
			and bool(_creature.call("two_handed_action_active"))
		)
		if uses_two_hands:
			var upper_hand := (arms[0] as Dictionary).get("hand") as Vector3
			var lower_hand := (arms[1] as Dictionary).get("hand") as Vector3
			var axis_y := (upper_hand - lower_hand).normalized()
			var axis_z := body.basis.z - axis_y * body.basis.z.dot(axis_y)
			if axis_z.length_squared() < 0.001:
				axis_z = body.basis.x - axis_y * body.basis.x.dot(axis_y)
			axis_z = axis_z.normalized()
			var axis_x := axis_y.cross(axis_z).normalized()
			_held_root.transform = Transform3D(
				Basis(axis_x, axis_y, axis_z).orthonormalized(), lower_hand
			)
		else:
			var holding_arm := arms[arms.size() - 1] as Dictionary
			var hand_position := holding_arm.get("hand") as Vector3
			# Tools lean well forward of vertical so they clear the face and read
			# at full length during swings and casts.
			_held_root.transform = Transform3D(
				body.basis * Basis.from_euler(Vector3(-1.02, -0.16, 0.0)),
				hand_position
			)


# ------------------------------------------------------------------ builders

func _build_hat(item: Dictionary, anchors: Dictionary) -> void:
	_hat_root = _slot_root("Hat")
	var head_radius := float(anchors.get("head_radius", 0.1))
	var color := _item_color(item, "color", "#D96F5E")
	var accent := _item_color(item, "accent", "#F2E3C0")
	# Wide ACNH-style heads stretch hats sideways to match.
	_hat_root.scale = Vector3(
		float(anchors.get("head_width", 1.0)), 1.0,
		1.0 + (float(anchors.get("head_width", 1.0)) - 1.0) * 0.6
	)
	# Hats perch ON the crown (high dome centers, small dome radii) so they
	# never swallow the face or clip the eyes.
	match String(item.get("kind", "cap")):
		"straw":
			_add_mesh(_hat_root, "Dome", _sphere_mesh(), Vector3(0.0, head_radius * 0.92, 0.0), Vector3(head_radius * 0.86, head_radius * 0.46, head_radius * 0.86), color)
			_add_mesh(_hat_root, "Brim", _cylinder_mesh(), Vector3(0.0, head_radius * 0.82, 0.0), Vector3(head_radius * 1.45, 0.006, head_radius * 1.45), color)
			_add_mesh(_hat_root, "Band", _cylinder_mesh(), Vector3(0.0, head_radius * 0.9, 0.0), Vector3(head_radius * 0.88, head_radius * 0.09, head_radius * 0.88), accent)
		"cone":
			_add_mesh(_hat_root, "Cone", _cone_mesh(), Vector3(0.0, head_radius * 1.22, 0.0), Vector3(head_radius * 0.46, head_radius * 0.95, head_radius * 0.46), color)
			_add_mesh(_hat_root, "Pom", _sphere_mesh(), Vector3(0.0, head_radius * 1.74, 0.0), Vector3(head_radius * 0.15, head_radius * 0.15, head_radius * 0.15), accent)
		_:
			# Low-profile cap that sits on top of the hair: a wide shallow
			# crown, a clear forward brim, and a matching button. It must
			# never engulf the head or hide the fringe.
			_add_mesh(_hat_root, "Dome", _dome_mesh(), Vector3(0.0, head_radius * 0.55, head_radius * 0.04), Vector3(head_radius * 1.10, head_radius * 0.60, head_radius * 1.12), color)
			_add_mesh(_hat_root, "Brim", _sphere_mesh(), Vector3(0.0, head_radius * 0.60, -head_radius * 1.02), Vector3(head_radius * 0.72, 0.006, head_radius * 0.50), color)
			# The button stays in the cap's own family — a light accent dot up
			# there reads as a specular error at gameplay scale.
			_add_mesh(_hat_root, "Button", _sphere_mesh(), Vector3(0.0, head_radius * 1.26, head_radius * 0.04), Vector3(head_radius * 0.09, head_radius * 0.09, head_radius * 0.09), color.darkened(0.22))


func _build_shirt(item: Dictionary, anchors: Dictionary) -> void:
	var torso_radius := float(anchors.get("torso_radius", 0.1))
	var torso_half := float(anchors.get("torso_half", 0.05))
	var upright := bool(anchors.get("upright", true))
	var color := _item_color(item, "color", "#7FA8D9")
	match String(item.get("kind", "tee")):
		"scarf":
			_scarf_root = _slot_root("Scarf")
			var head_radius := float(anchors.get("head_radius", 0.1))
			# The loop wraps the NECK, so it sizes to the smaller of head and
			# torso — a big chibi head must not inflate it down to the belly.
			var neck := minf(head_radius, float(anchors.get("torso_radius", 0.1)) * 1.15)
			_scarf_drop = head_radius * 0.8 + neck * 0.42
			_add_mesh(_scarf_root, "Loop", _torus_mesh(), Vector3(0.0, 0.0, neck * 0.04), Vector3(neck * 0.86, neck * 0.72, neck * 0.86), color)
			_add_mesh(_scarf_root, "Knot", _sphere_mesh(), Vector3(neck * 0.2, -neck * 0.26, -neck * 0.68), Vector3(neck * 0.18, neck * 0.15, neck * 0.13), Color(color).darkened(0.08))
			_add_mesh(_scarf_root, "TailA", _sphere_mesh(), Vector3(neck * 0.24, -neck * 0.58, -neck * 0.64), Vector3(neck * 0.14, neck * 0.36, neck * 0.09), color)
			_add_mesh(_scarf_root, "TailB", _sphere_mesh(), Vector3(neck * 0.02, -neck * 0.48, -neck * 0.68), Vector3(neck * 0.12, neck * 0.28, neck * 0.08), Color(color).darkened(0.05))
		_:
			_shirt_root = _slot_root("Shirt")
			_shirt_base_scale = (
				Vector3(torso_radius * 1.16, torso_half + torso_radius * 0.58, torso_radius * 1.16)
				if upright
				else Vector3(torso_radius * 1.16, torso_radius * 1.16, torso_half + torso_radius * 0.58)
			)
			_add_mesh(_shirt_root, "Wrap", _sphere_mesh(), Vector3.ZERO, Vector3.ONE, color)
			_shirt_root.scale = _shirt_base_scale


func _build_pants(item: Dictionary, anchors: Dictionary) -> void:
	var color := _item_color(item, "color", "#5E6E8A")
	# Pant legs wrap the actual leg radius instead of guessing from torso.
	var leg_radius := float(anchors.get("leg_radius", 0.028))
	var legs: Array = anchors.get("legs", [])
	_pants_roots = []
	for leg_index in legs.size():
		var leg_root := _slot_root("PantLeg%d" % leg_index)
		_add_mesh(leg_root, "Tube", _cylinder_mesh(), Vector3.ZERO, Vector3(leg_radius * 1.55, 0.66, leg_radius * 1.55), color)
		_pants_roots.append(leg_root)


func _build_shoes(item: Dictionary, anchors: Dictionary) -> void:
	var color := _item_color(item, "color", "#8A5138")
	var foot_radius := float(anchors.get("foot_radius", 0.026))
	var legs: Array = anchors.get("legs", [])
	_shoe_roots = []
	for leg_index in legs.size():
		var shoe_root := _slot_root("Shoe%d" % leg_index)
		_add_mesh(shoe_root, "Boot", _sphere_mesh(), Vector3(0.0, 0.0, -foot_radius * 0.14), Vector3(foot_radius * 1.38, foot_radius * 1.14, foot_radius * 1.52), color)
		_add_mesh(shoe_root, "Cuff", _cylinder_mesh(), Vector3(0.0, foot_radius * 0.92, foot_radius * 0.12), Vector3(foot_radius * 0.9, foot_radius * 0.55, foot_radius * 0.9), Color(color).darkened(0.15))
		_shoe_roots.append(shoe_root)


func _build_held(item: Dictionary, anchors: Dictionary) -> void:
	if (anchors.get("arms", []) as Array).is_empty():
		return
	_held_root = _slot_root("Held")
	_held_kind = String(item.get("kind", "stick"))
	var torso_radius := float(anchors.get("torso_radius", 0.1))
	var color := _item_color(item, "color", "#8A6B48")
	var accent := _item_color(
		item,
		"accent",
		("#747A80" if _held_kind in ["axe", "pickaxe"] else "#D96F5E")
	)
	match _held_kind:
		"axe":
			var handle_length := torso_radius * 3.6
			_add_mesh(_held_root, "Handle", _cylinder_mesh(), Vector3(0.0, handle_length * 0.38, 0.0), Vector3(torso_radius * 0.075, handle_length, torso_radius * 0.075), color)
			var head := _add_mesh(
				_held_root, "Head", _axe_head_mesh(),
				Vector3(0.0, handle_length * 0.82, -torso_radius * 0.10),
				Vector3(torso_radius * 0.30, torso_radius * 0.55, torso_radius * 0.76),
				accent
			)
			(head.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
			_add_mesh(
				_held_root, "Poll", _box_mesh(),
				Vector3(0.0, handle_length * 0.82, torso_radius * 0.20),
				Vector3(torso_radius * 0.22, torso_radius * 0.28, torso_radius * 0.28),
				accent.darkened(0.16)
			)
			_held_tip_local = Vector3(0.0, handle_length * 0.82, -torso_radius * 0.64)
		"pickaxe":
			var pick_handle := torso_radius * 3.1
			_add_mesh(_held_root, "Handle", _cylinder_mesh(), Vector3(0.0, pick_handle * 0.38, 0.0), Vector3(torso_radius * 0.075, pick_handle, torso_radius * 0.075), color)
			_add_mesh(_held_root, "SpikeFront", _cone_mesh(), Vector3(0.0, pick_handle * 0.8, -torso_radius * 0.46), Vector3(torso_radius * 0.14, torso_radius * 0.9, torso_radius * 0.14), accent, Vector3(-PI * 0.5, 0.0, 0.0))
			_add_mesh(_held_root, "SpikeBack", _cone_mesh(), Vector3(0.0, pick_handle * 0.8, torso_radius * 0.46), Vector3(torso_radius * 0.14, torso_radius * 0.9, torso_radius * 0.14), accent, Vector3(PI * 0.5, 0.0, 0.0))
			_held_tip_local = Vector3(0.0, pick_handle * 0.8, -torso_radius * 0.9)
		"fishing_rod":
			var rod_length := torso_radius * 5.2
			_add_mesh(_held_root, "Rod", _cylinder_mesh(), Vector3(0.0, rod_length * 0.42, 0.0), Vector3(torso_radius * 0.055, rod_length, torso_radius * 0.055), color)
			_add_mesh(_held_root, "Grip", _cylinder_mesh(), Vector3(0.0, torso_radius * 0.12, 0.0), Vector3(torso_radius * 0.085, torso_radius * 0.5, torso_radius * 0.085), Color(color).darkened(0.25))
			_add_mesh(_held_root, "Reel", _sphere_mesh(), Vector3(0.0, torso_radius * 0.55, torso_radius * 0.12), Vector3(torso_radius * 0.14, torso_radius * 0.14, torso_radius * 0.14), accent)
			_add_mesh(_held_root, "Tip", _sphere_mesh(), Vector3(0.0, rod_length * 0.92, 0.0), Vector3(torso_radius * 0.07, torso_radius * 0.07, torso_radius * 0.07), accent)
			_held_tip_local = Vector3(0.0, rod_length * 0.92, 0.0)
		_:
			var stick_length := torso_radius * 2.6
			_add_mesh(_held_root, "Stick", _cylinder_mesh(), Vector3(0.0, stick_length * 0.4, 0.0), Vector3(torso_radius * 0.07, stick_length, torso_radius * 0.07), color)
			_held_tip_local = Vector3(0.0, stick_length * 0.9, 0.0)


# ------------------------------------------------------------------ helpers

func _segment_transform(from: Vector3, to: Vector3) -> Transform3D:
	var direction := to - from
	var length := maxf(direction.length(), 0.0001)
	var axis_y := direction / length
	var helper := Vector3.RIGHT if absf(axis_y.y) > 0.92 else Vector3.UP
	var axis_x := helper.cross(axis_y).normalized()
	var axis_z := axis_x.cross(axis_y)
	return Transform3D(
		Basis(axis_x, axis_y * length, axis_z),
		(from + to) * 0.5
	)


func _slot_root(slot_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = slot_name
	add_child(root)
	return root


func _sphere_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 18
	mesh.rings = 9
	return mesh


func _dome_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var segments := 24
	var rings := 8
	vertices.append(Vector3.UP)
	normals.append(Vector3.UP)
	for ring in range(1, rings + 1):
		var theta := PI * 0.5 * float(ring) / float(rings)
		for segment in range(segments + 1):
			var phi := TAU * float(segment) / float(segments)
			var point := Vector3(
				sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi)
			)
			vertices.append(point)
			normals.append(point.normalized())
	for segment in segments:
		indices.append(0)
		indices.append(1 + segment)
		indices.append(2 + segment)
	for ring in range(1, rings):
		var row := 1 + (ring - 1) * (segments + 1)
		var next_row := row + segments + 1
		for segment in segments:
			var a := row + segment
			var b := a + 1
			var c := next_row + segment
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


func _cylinder_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 16
	return mesh


func _cone_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 16
	return mesh


func _box_mesh() -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	return mesh


## Broad flared wedge rather than a symmetric cube: even at gameplay scale
## the silhouette reads as an axe blade, not a hammer head or red paddle.
func _axe_head_mesh() -> ArrayMesh:
	var points := PackedVector3Array([
		Vector3(-0.5, -0.25, 0.20), Vector3(-0.5, 0.25, 0.20),
		Vector3(-0.5, 0.50, -0.70), Vector3(-0.5, -0.50, -0.70),
		Vector3(0.5, -0.25, 0.20), Vector3(0.5, 0.25, 0.20),
		Vector3(0.5, 0.50, -0.70), Vector3(0.5, -0.50, -0.70),
	])
	var triangles := PackedInt32Array([
		0, 3, 2, 0, 2, 1,
		4, 5, 6, 4, 6, 7,
		0, 1, 5, 0, 5, 4,
		3, 7, 6, 3, 6, 2,
		1, 2, 6, 1, 6, 5,
		0, 4, 7, 0, 7, 3,
	])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in triangles:
		surface.add_vertex(points[index])
	surface.generate_normals()
	return surface.commit()


func _torus_mesh() -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.55
	mesh.outer_radius = 1.0
	mesh.rings = 20
	mesh.ring_segments = 10
	return mesh


func _add_mesh(
	parent: Node3D,
	node_name: String,
	mesh: Mesh,
	position: Vector3,
	scale_value: Vector3,
	color: Color,
	rotation_value := Vector3.ZERO
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.rotation = rotation_value
	instance.scale = scale_value
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.disable_receive_shadows = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	instance.material_override = material
	# Garments are tight decorative shells; the body underneath owns the
	# ground shadow, and garment shadows carve dark bands into faces and limbs.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _item_color(item: Dictionary, key: String, fallback: String) -> Color:
	return Color(String(item.get(key, fallback)))
