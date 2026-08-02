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
var _scarf_root: Node3D
var _sleeve_roots: Array[Node3D] = []
var _pants_roots: Array[Node3D] = []
var _shoe_roots: Array[Node3D] = []
var _held_root: Node3D
var _held_tip_local := Vector3.ZERO


func build(outfit: Dictionary, creature: Node3D) -> void:
	_creature = creature
	var anchors: Dictionary = creature.call("pose_anchors")
	if outfit.has("hat"):
		_build_hat(outfit.get("hat") as Dictionary, anchors)
	if outfit.has("shirt"):
		_build_shirt(outfit.get("shirt") as Dictionary, anchors)
	if outfit.has("pants"):
		_build_pants(outfit.get("pants") as Dictionary, anchors)
	if outfit.has("shoes"):
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
		_shirt_root.transform = body
	if is_instance_valid(_scarf_root):
		var head_radius := float(anchors.get("head_radius", 0.1))
		_scarf_root.transform = Transform3D(
			head.basis, head.origin - head.basis.y * head_radius * 0.95
		)
	for sleeve_index in _sleeve_roots.size():
		if sleeve_index >= arms.size():
			break
		var arm := arms[sleeve_index] as Dictionary
		var shoulder := arm.get("shoulder") as Vector3
		var hand := arm.get("hand") as Vector3
		_sleeve_roots[sleeve_index].transform = _segment_transform(
			shoulder, shoulder.lerp(hand, 0.42)
		)
	for pants_index in _pants_roots.size():
		if pants_index >= legs.size():
			break
		var leg := legs[pants_index] as Dictionary
		var hip := leg.get("hip") as Vector3
		var knee := leg.get("knee") as Vector3
		_pants_roots[pants_index].transform = _segment_transform(
			hip.lerp(knee, -0.1), hip.lerp(knee, 0.72)
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
	match String(item.get("kind", "cap")):
		"straw":
			_add_mesh(_hat_root, "Dome", _sphere_mesh(), Vector3(0.0, head_radius * 0.74, 0.0), Vector3(head_radius * 1.02, head_radius * 0.56, head_radius * 1.02), color)
			_add_mesh(_hat_root, "Brim", _cylinder_mesh(), Vector3(0.0, head_radius * 0.6, 0.0), Vector3(head_radius * 1.62, 0.006, head_radius * 1.62), color)
			_add_mesh(_hat_root, "Band", _cylinder_mesh(), Vector3(0.0, head_radius * 0.68, 0.0), Vector3(head_radius * 1.04, head_radius * 0.1, head_radius * 1.04), accent)
		"cone":
			_add_mesh(_hat_root, "Cone", _cone_mesh(), Vector3(0.0, head_radius * 1.05, 0.0), Vector3(head_radius * 0.52, head_radius * 1.05, head_radius * 0.52), color)
			_add_mesh(_hat_root, "Pom", _sphere_mesh(), Vector3(0.0, head_radius * 1.62, 0.0), Vector3(head_radius * 0.16, head_radius * 0.16, head_radius * 0.16), accent)
		_:
			_add_mesh(_hat_root, "Dome", _sphere_mesh(), Vector3(0.0, head_radius * 0.66, 0.0), Vector3(head_radius * 1.1, head_radius * 0.6, head_radius * 1.1), color)
			_add_mesh(_hat_root, "Brim", _sphere_mesh(), Vector3(0.0, head_radius * 0.52, -head_radius * 0.88), Vector3(head_radius * 0.52, 0.008, head_radius * 0.6), color)
			_add_mesh(_hat_root, "Button", _sphere_mesh(), Vector3(0.0, head_radius * 1.28, 0.0), Vector3(head_radius * 0.12, head_radius * 0.12, head_radius * 0.12), accent)


func _build_shirt(item: Dictionary, anchors: Dictionary) -> void:
	var torso_radius := float(anchors.get("torso_radius", 0.1))
	var torso_half := float(anchors.get("torso_half", 0.05))
	var upright := bool(anchors.get("upright", true))
	var color := _item_color(item, "color", "#7FA8D9")
	match String(item.get("kind", "tee")):
		"scarf":
			_scarf_root = _slot_root("Scarf")
			var head_radius := float(anchors.get("head_radius", 0.1))
			_add_mesh(_scarf_root, "Loop", _torus_mesh(), Vector3.ZERO, Vector3(head_radius * 0.92, head_radius * 0.92, head_radius * 0.92), color)
			_add_mesh(_scarf_root, "TailA", _sphere_mesh(), Vector3(head_radius * 0.3, -head_radius * 0.42, head_radius * 0.62), Vector3(head_radius * 0.2, head_radius * 0.44, head_radius * 0.1), color)
			_add_mesh(_scarf_root, "TailB", _sphere_mesh(), Vector3(head_radius * 0.34, -head_radius * 0.7, head_radius * 0.6), Vector3(head_radius * 0.16, head_radius * 0.3, head_radius * 0.09), color)
		_:
			_shirt_root = _slot_root("Shirt")
			var wrap_scale := (
				Vector3(torso_radius * 1.13, torso_half + torso_radius * 0.6, torso_radius * 1.13)
				if upright
				else Vector3(torso_radius * 1.13, torso_radius * 1.13, torso_half + torso_radius * 0.6)
			)
			_add_mesh(_shirt_root, "Wrap", _sphere_mesh(), Vector3.ZERO, wrap_scale, color)
			var arms: Array = anchors.get("arms", [])
			_sleeve_roots = []
			for arm_index in arms.size():
				var sleeve := _slot_root("Sleeve%d" % arm_index)
				_add_mesh(sleeve, "Tube", _cylinder_mesh(), Vector3.ZERO, Vector3(torso_radius * 0.4, 0.62, torso_radius * 0.4), color)
				_sleeve_roots.append(sleeve)


func _build_pants(item: Dictionary, anchors: Dictionary) -> void:
	var color := _item_color(item, "color", "#5E6E8A")
	var torso_radius := float(anchors.get("torso_radius", 0.1))
	var legs: Array = anchors.get("legs", [])
	_pants_roots = []
	for leg_index in legs.size():
		var leg_root := _slot_root("PantLeg%d" % leg_index)
		_add_mesh(leg_root, "Tube", _cylinder_mesh(), Vector3.ZERO, Vector3(torso_radius * 0.34, 0.62, torso_radius * 0.34), color)
		_pants_roots.append(leg_root)


func _build_shoes(item: Dictionary, anchors: Dictionary) -> void:
	var color := _item_color(item, "color", "#8A5138")
	var foot_radius := float(anchors.get("foot_radius", 0.026))
	var legs: Array = anchors.get("legs", [])
	_shoe_roots = []
	for leg_index in legs.size():
		var shoe_root := _slot_root("Shoe%d" % leg_index)
		_add_mesh(shoe_root, "Boot", _sphere_mesh(), Vector3(0.0, foot_radius * 0.05, -foot_radius * 0.12), Vector3(foot_radius * 1.28, foot_radius * 1.08, foot_radius * 1.44), color)
		_add_mesh(shoe_root, "Cuff", _cylinder_mesh(), Vector3(0.0, foot_radius * 0.85, foot_radius * 0.15), Vector3(foot_radius * 0.85, foot_radius * 0.5, foot_radius * 0.85), Color(color).darkened(0.15))
		_shoe_roots.append(shoe_root)


func _build_held(item: Dictionary, anchors: Dictionary) -> void:
	if (anchors.get("arms", []) as Array).is_empty():
		return
	_held_root = _slot_root("Held")
	var torso_radius := float(anchors.get("torso_radius", 0.1))
	var color := _item_color(item, "color", "#8A6B48")
	var accent := _item_color(item, "accent", "#D96F5E")
	match String(item.get("kind", "stick")):
		"axe":
			var handle_length := torso_radius * 2.9
			_add_mesh(_held_root, "Handle", _cylinder_mesh(), Vector3(0.0, handle_length * 0.38, 0.0), Vector3(torso_radius * 0.075, handle_length, torso_radius * 0.075), color)
			_add_mesh(_held_root, "Head", _box_mesh(), Vector3(0.0, handle_length * 0.82, -torso_radius * 0.3), Vector3(torso_radius * 0.14, torso_radius * 0.42, torso_radius * 0.52), accent)
			_held_tip_local = Vector3(0.0, handle_length * 0.82, -torso_radius * 0.55)
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
	parent.add_child(instance)
	return instance


func _item_color(item: Dictionary, key: String, fallback: String) -> Color:
	return Color(String(item.get(key, fallback)))
