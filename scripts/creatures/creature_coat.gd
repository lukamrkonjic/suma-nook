class_name CreatureCoat
extends Node3D
## Geometry accents that sell a creature's coat style: feather fans that
## flutter, wool puffs, spine ridges, and fur tufts that stir. Accents ride
## the live pose anchors (pose_advanced) and add their own gentle wind sway
## on top, so every creature feels alive even standing still.

var _creature: Node3D
var _body_accents: Node3D
var _head_accents: Node3D
var _sway_nodes: Array[MeshInstance3D] = []
var _sway_time := 0.0
var _sway_amount := 0.08
var _sway_speed := 2.4


func build(coat: Dictionary, creature: Node3D) -> void:
	_creature = creature
	var anchors: Dictionary = creature.call("pose_anchors")
	var torso_radius := float(anchors.get("torso_radius", 0.1))
	var torso_half := float(anchors.get("torso_half", 0.05))
	var head_radius := float(anchors.get("head_radius", 0.1))
	var upright := bool(anchors.get("upright", true))
	var tint := Color(String(coat.get("accent_color", coat.get("pattern_color", "#FFFFFF"))))
	_sway_amount = float(coat.get("sway", 0.08))
	_sway_speed = float(coat.get("sway_speed", 2.4))

	_body_accents = Node3D.new()
	_body_accents.name = "BodyAccents"
	add_child(_body_accents)
	_head_accents = Node3D.new()
	_head_accents.name = "HeadAccents"
	add_child(_head_accents)

	match String(coat.get("style", "")):
		"feathers":
			_build_feathers(torso_radius, torso_half, head_radius, upright, tint)
		"wool":
			_build_wool(torso_radius, torso_half, upright, tint)
		"scales":
			_build_ridge(torso_radius, torso_half, upright, tint)
		"fur":
			_build_fur_tufts(torso_radius, torso_half, head_radius, upright, tint)

	if creature.has_signal("pose_advanced"):
		creature.connect("pose_advanced", _sync)
	_sync()


func _process(delta: float) -> void:
	_sway_time += delta
	for sway_index in _sway_nodes.size():
		var accent := _sway_nodes[sway_index]
		var phase := _sway_time * _sway_speed + float(sway_index) * 1.7
		accent.rotation.z = sin(phase) * _sway_amount
		accent.rotation.x = cos(phase * 0.7) * _sway_amount * 0.5


func _sync() -> void:
	if _creature == null:
		return
	var anchors: Dictionary = _creature.call("pose_anchors")
	_body_accents.transform = anchors.get("body", Transform3D.IDENTITY)
	_head_accents.transform = anchors.get("head", Transform3D.IDENTITY)


# ------------------------------------------------------------------ styles

## A crest of layered feather cards down the back plus two head plumes.
func _build_feathers(
	torso_radius: float,
	torso_half: float,
	head_radius: float,
	upright: bool,
	tint: Color
) -> void:
	for feather_index in 3:
		var progress := float(feather_index) / 2.0
		var position := (
			Vector3(0.0, lerpf(torso_half * 0.9, -torso_half * 0.7, progress), torso_radius * 0.82)
			if upright
			else Vector3(0.0, torso_radius * 0.82, lerpf(-torso_half * 0.5, torso_half * 0.9, progress))
		)
		var feather := _add_accent(
			_body_accents, "BackFeather%d" % feather_index, _cone_mesh(),
			position,
			Vector3(torso_radius * 0.22, torso_radius * 0.55, torso_radius * 0.07),
			tint.darkened(0.06 * float(feather_index)),
			Vector3(deg_to_rad(-38.0) if upright else deg_to_rad(-52.0), 0.0, 0.0)
		)
		_sway_nodes.append(feather)
	for side in [-1.0, 1.0]:
		var plume := _add_accent(
			_head_accents, "Plume%s" % ("L" if side < 0.0 else "R"), _cone_mesh(),
			Vector3(side * head_radius * 0.22, head_radius * 0.88, 0.1 * head_radius),
			Vector3(head_radius * 0.13, head_radius * 0.42, head_radius * 0.06),
			tint.lightened(0.12),
			Vector3(deg_to_rad(-16.0), 0.0, side * deg_to_rad(18.0))
		)
		_sway_nodes.append(plume)


## Cloud puffs across the back — sheep clouds, static but anchor-ridden.
func _build_wool(
	torso_radius: float, torso_half: float, upright: bool, tint: Color
) -> void:
	var puff_seeds: Array = [
		Vector3(-0.5, 0.75, -0.45), Vector3(0.45, 0.8, 0.1),
		Vector3(-0.15, 0.9, 0.55), Vector3(0.55, 0.7, -0.55),
		Vector3(-0.6, 0.7, 0.5), Vector3(0.1, 0.95, -0.1),
	]
	for puff_index in puff_seeds.size():
		var seed_offset := puff_seeds[puff_index] as Vector3
		var position := (
			Vector3(seed_offset.x * torso_radius * 0.6, seed_offset.z * torso_half, seed_offset.y * torso_radius * 0.72)
			if upright
			else Vector3(seed_offset.x * torso_radius * 0.6, seed_offset.y * torso_radius * 0.72, seed_offset.z * torso_half)
		)
		_add_accent(
			_body_accents, "Puff%d" % puff_index, _sphere_mesh(),
			position,
			Vector3.ONE * torso_radius * (0.34 + 0.08 * float(puff_index % 3)),
			tint.lightened(0.04 * float(puff_index % 2))
		)


## Upright ridge plates along the spine — dragons, turtles, cacti.
func _build_ridge(
	torso_radius: float, torso_half: float, upright: bool, tint: Color
) -> void:
	for plate_index in 4:
		var progress := float(plate_index) / 3.0
		var position := (
			Vector3(0.0, lerpf(torso_half, -torso_half * 0.8, progress), torso_radius * 0.86)
			if upright
			else Vector3(0.0, torso_radius * 0.86, lerpf(-torso_half * 0.7, torso_half, progress))
		)
		var plate_scale := torso_radius * lerpf(0.3, 0.18, progress)
		_add_accent(
			_body_accents, "Ridge%d" % plate_index, _cone_mesh(),
			position,
			Vector3(plate_scale * 0.35, plate_scale, plate_scale * 0.9),
			tint.darkened(0.05 * float(plate_index)),
			Vector3(deg_to_rad(-90.0) if not upright else deg_to_rad(-24.0), 0.0, 0.0)
		)


## A few soft fur tufts: crown, chest, and rump — they stir in the wind.
func _build_fur_tufts(
	torso_radius: float,
	torso_half: float,
	head_radius: float,
	upright: bool,
	tint: Color
) -> void:
	var crown := _add_accent(
		_head_accents, "CrownTuft", _cone_mesh(),
		Vector3(0.0, head_radius * 0.94, 0.02),
		Vector3(head_radius * 0.16, head_radius * 0.3, head_radius * 0.12),
		tint,
		Vector3(deg_to_rad(-12.0), 0.0, deg_to_rad(8.0))
	)
	_sway_nodes.append(crown)
	var chest_position := (
		Vector3(0.0, torso_half * 0.7, -torso_radius * 0.86)
		if upright
		else Vector3(0.0, torso_radius * 0.5, -torso_half - torso_radius * 0.45)
	)
	var chest := _add_accent(
		_body_accents, "ChestTuft", _cone_mesh(),
		chest_position,
		Vector3(torso_radius * 0.16, torso_radius * 0.3, torso_radius * 0.1),
		tint.lightened(0.1),
		Vector3(deg_to_rad(-136.0), 0.0, 0.0)
	)
	_sway_nodes.append(chest)
	var rump_position := (
		Vector3(0.0, -torso_half * 0.2, torso_radius * 0.9)
		if upright
		else Vector3(0.0, torso_radius * 0.8, torso_half * 0.85)
	)
	var rump := _add_accent(
		_body_accents, "RumpTuft", _cone_mesh(),
		rump_position,
		Vector3(torso_radius * 0.14, torso_radius * 0.26, torso_radius * 0.1),
		tint,
		Vector3(deg_to_rad(-46.0), 0.0, deg_to_rad(-10.0))
	)
	_sway_nodes.append(rump)


# ------------------------------------------------------------------ helpers

func _cone_mesh() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 10
	return mesh


func _sphere_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 14
	mesh.rings = 7
	return mesh


func _add_accent(
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
