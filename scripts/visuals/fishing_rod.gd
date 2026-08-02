class_name FishingRod
extends Node3D

var _color_system := PaletteDefinition.shared()
## Compact procedural rod used by the live character rig. Its LineOrigin
## marker is the authoritative endpoint for the viewport-space fishing line.

var _shaft_pivot: Node3D
var _idle_active := false
var _idle_time := 0.0
var _rng := RandomNumberGenerator.new()
var _time_to_bump := 1.0
var _bump_elapsed := 0.0
var _bump_duration := 0.0
var _bump_strength := 0.0
var _bump_side := 0.0
var _bump_count := 0
var _flick_time := -1.0


func _ready() -> void:
	_rng.randomize()
	_build()


func _process(delta: float) -> void:
	if not _idle_active or _shaft_pivot == null:
		return
	_idle_time += delta
	var base_x := (
		sin(_idle_time * 0.72) * 0.007
		+ sin(_idle_time * 1.31 + 0.8) * 0.003
	)
	var base_y := sin(_idle_time * 0.54 + 1.7) * 0.004
	_shaft_pivot.rotation = Vector3(base_x, base_y, 0.0)
	if _flick_time >= 0.0:
		_flick_time += delta
		var flick_progress := _flick_time / 0.42
		if flick_progress >= 1.0:
			_flick_time = -1.0
		elif flick_progress < 0.3:
			# Back-swing: the tip lifts as the keeper loads the cast.
			_shaft_pivot.rotation.x += (
				sin(flick_progress / 0.3 * PI * 0.5) * 0.2
			)
		else:
			# Forward whip past neutral, settling as the line drops.
			var whip_progress := (flick_progress - 0.3) / 0.7
			_shaft_pivot.rotation.x -= (
				sin(whip_progress * PI)
				* 0.26
				* (1.0 - whip_progress * 0.35)
			)
	if _bump_duration > 0.0:
		_bump_elapsed += delta
		var progress := clampf(
			_bump_elapsed / _bump_duration,
			0.0,
			1.0
		)
		var lift := sin(progress * PI)
		var settle := (
			sin(progress * TAU * 2.0)
			* (1.0 - progress)
			* 0.2
		)
		var bump := _bump_strength * (lift + settle)
		_shaft_pivot.rotation.x -= bump
		_shaft_pivot.rotation.y += bump * _bump_side * 0.18
		_shaft_pivot.rotation.z += bump * _bump_side * 0.26
		if progress >= 1.0:
			_bump_duration = 0.0
			_bump_elapsed = 0.0
	else:
		_time_to_bump -= delta
		if _time_to_bump <= 0.0:
			_start_bump()


func set_idle_active(active: bool) -> void:
	var was_active := _idle_active
	_idle_active = active
	if active and not was_active:
		_time_to_bump = _rng.randf_range(0.65, 1.35)
	if not active and _shaft_pivot != null:
		_shaft_pivot.rotation = Vector3.ZERO
		_bump_duration = 0.0
		_bump_elapsed = 0.0


func bump_animation_enabled() -> bool:
	return _idle_active


func bump_count() -> int:
	return _bump_count


func bump_is_visibly_active() -> bool:
	if _bump_duration <= 0.0:
		return false
	var progress := _bump_elapsed / _bump_duration
	return progress >= 0.22 and progress <= 0.72


func _start_bump() -> void:
	_bump_elapsed = 0.0
	_bump_duration = _rng.randf_range(0.3, 0.48)
	_bump_strength = _rng.randf_range(0.05, 0.09)
	_bump_side = -1.0 if _rng.randf() < 0.5 else 1.0
	_time_to_bump = _rng.randf_range(2.4, 5.6)
	_bump_count += 1


## The seated cast: a quick wrist flick — back-swing, then a forward whip
## that sends the line out over the void.
func cast_flick() -> void:
	_flick_time = 0.0


## The moment something takes the lure: a firm tip dip that reads clearly
## through the idle sway, independent of the random bump schedule.
func bite_dip() -> void:
	_bump_elapsed = 0.0
	_bump_duration = 0.5
	_bump_strength = 0.17
	_bump_side = -1.0 if _rng.randf() < 0.5 else 1.0
	_time_to_bump = _rng.randf_range(2.4, 5.6)
	_bump_count += 1


func line_origin() -> Marker3D:
	return get_node_or_null("ShaftPivot/LineOrigin") as Marker3D


func support_hand_marker() -> Marker3D:
	return get_node_or_null(
		"ShaftPivot/SupportHandMarker"
	) as Marker3D


func _build() -> void:
	_shaft_pivot = Node3D.new()
	_shaft_pivot.name = "ShaftPivot"
	add_child(_shaft_pivot)

	var wood := _material(_color_system.color("fishing_rod_wood"), 0.72)
	var wood_tip := _material(_color_system.color("fishing_rod_wood_tip"), 0.68)
	var grip := _material(_color_system.color("fishing_rod_grip"), 0.88)
	var metal := _material(_color_system.color("fishing_rod_metal"), 0.55)
	var guide_material := _material(_color_system.color("fishing_rod_guide"), 0.62)
	# The shaft runs dead straight ahead (-Z) and rises toward the tip: the
	# rod's forward axis IS the cast direction, so aiming the rod at an edge
	# needs no compensation for any authored side-curve.
	var points := PackedVector3Array([
		Vector3(0.0, 0.0, 0.02),
		Vector3(0.0, 0.05, -0.21),
		Vector3(0.0, 0.13, -0.49),
		Vector3(0.0, 0.22, -0.76),
		Vector3(0.0, 0.30, -1.0),
	])
	_add_segment(
		_shaft_pivot,
		"DarkHandle",
		points[0],
		points[1],
		0.035,
		0.030,
		grip
	)
	for index in range(1, points.size() - 1):
		var ratio := float(index - 1) / 3.0
		_add_segment(
			_shaft_pivot,
			"ShaftSegment%02d" % index,
			points[index],
			points[index + 1],
			lerpf(0.024, 0.010, ratio),
			lerpf(0.019, 0.006, ratio),
			wood_tip if index >= 3 else wood
		)

	var reel_pivot := Node3D.new()
	reel_pivot.name = "ReelPivot"
	reel_pivot.position = Vector3(0.052, 0.036, -0.25)
	_shaft_pivot.add_child(reel_pivot)
	var reel := MeshInstance3D.new()
	reel.name = "Reel"
	var reel_mesh := CylinderMesh.new()
	reel_mesh.top_radius = 0.065
	reel_mesh.bottom_radius = 0.065
	reel_mesh.height = 0.042
	reel_mesh.radial_segments = 12
	reel.mesh = reel_mesh
	reel.rotation.z = PI * 0.5
	reel.material_override = metal
	reel_pivot.add_child(reel)
	_add_segment(
		reel_pivot,
		"ReelHandle",
		Vector3.ZERO,
		Vector3(0.082, 0.0, 0.0),
		0.011,
		0.011,
		grip
	)

	for index in range(1, points.size()):
		var previous := points[index - 1]
		var current := points[index]
		var direction := (current - previous).normalized()
		var guide := MeshInstance3D.new()
		guide.name = "LineGuide%02d" % index
		var torus := TorusMesh.new()
		torus.inner_radius = 0.014
		torus.outer_radius = (
			0.025 if index < points.size() - 1 else 0.020
		)
		torus.rings = 10
		torus.ring_segments = 6
		guide.mesh = torus
		guide.position = current.lerp(previous, 0.06)
		guide.quaternion = Quaternion(Vector3.UP, direction)
		guide.material_override = guide_material
		_shaft_pivot.add_child(guide)

	var support := Marker3D.new()
	support.name = "SupportHandMarker"
	support.position = points[1].lerp(points[2], 0.16)
	_shaft_pivot.add_child(support)
	var origin := Marker3D.new()
	origin.name = "LineOrigin"
	origin.position = points[points.size() - 1]
	_shaft_pivot.add_child(origin)


func _add_segment(
	parent: Node3D,
	node_name: String,
	start: Vector3,
	end: Vector3,
	radius_start: float,
	radius_end: float,
	material: Material
) -> MeshInstance3D:
	var direction := end - start
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.bottom_radius = radius_start
	cylinder.top_radius = radius_end
	cylinder.height = direction.length()
	cylinder.radial_segments = 10
	cylinder.rings = 2
	mesh_instance.mesh = cylinder
	mesh_instance.position = (start + end) * 0.5
	mesh_instance.quaternion = Quaternion(
		Vector3.UP,
		direction.normalized()
	)
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	parent.add_child(mesh_instance)
	return mesh_instance


func _material(
	color: Color,
	roughness: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material
