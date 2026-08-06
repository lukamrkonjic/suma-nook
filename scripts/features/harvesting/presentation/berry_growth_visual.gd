class_name BerryGrowthVisual
extends Node3D
## Reusable fruit layer for any harvest source using the berry_cluster
## presenter. Placement is derived from the resolved model bounds, never from
## bush-specific node names, so replacing the authored model needs no code or
## save migration.

const READY_STATE := "ready"

const HIDDEN_SCALE := 0.04

var _pulse_scale := 1.055
var _nudge_radians := 0.028
var _nudge_interval := 1.15
var _transition: Tween
var _attention: Tween


func configure(
	materials: MaterialLibrary,
	settings: Dictionary,
	visual_seed: int,
	model_bounds: AABB
) -> void:
	set_meta("exclude_from_structural_bounds", true)
	_pulse_scale = clampf(float(settings.get("ready_pulse_scale", 1.055)), 1.0, 1.15)
	_nudge_radians = clampf(float(settings.get("ready_nudge_radians", 0.028)), 0.0, 0.08)
	_nudge_interval = clampf(float(settings.get("ready_nudge_interval", 1.15)), 0.4, 4.0)
	var count := maxi(1, int(settings.get("count", 7)))
	var radius_min := maxf(0.008, float(settings.get("radius_min", 0.035)))
	var radius_max := maxf(radius_min, float(settings.get("radius_max", 0.05)))
	var spread_x := clampf(float(settings.get("spread_x", 0.65)), 0.05, 1.0)
	var spread_z := clampf(float(settings.get("spread_z", 0.65)), 0.05, 1.0)
	var height_min := clampf(float(settings.get("height_min", 0.5)), 0.0, 1.0)
	var height_max := clampf(
		float(settings.get("height_max", 0.82)), height_min, 1.0
	)
	var material_key := String(settings.get("material", "tilekit_clay_berry"))

	# Keep the growth pivot inside the canopy. State changes then swell the
	# whole cluster around the plant rather than pulling fruit toward its foot.
	var center := model_bounds.position + Vector3(
		model_bounds.size.x * 0.5,
		model_bounds.size.y * (height_min + height_max) * 0.5,
		model_bounds.size.z * 0.5
	)
	position = center

	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(materials.material(material_key))
	var rng := RandomNumberGenerator.new()
	rng.seed = visual_seed if visual_seed != 0 else 1
	for index in count:
		# A golden-angle base avoids accidental rows; jitter and different berry
		# sizes keep repeated objects toy-like without per-frame simulation.
		var angle := float(index) * 2.399963 + rng.randf_range(-0.42, 0.42)
		var radial := sqrt((float(index) + 0.5) / float(count))
		radial *= rng.randf_range(0.62, 1.0)
		var world_position := Vector3(
			cos(angle) * model_bounds.size.x * spread_x * 0.5 * radial,
			model_bounds.size.y * rng.randf_range(
				height_min - (height_min + height_max) * 0.5,
				height_max - (height_min + height_max) * 0.5
			),
			sin(angle) * model_bounds.size.z * spread_z * 0.5 * radial
		)
		var radius := rng.randf_range(radius_min, radius_max)
		var berry_basis := Basis.IDENTITY.scaled(
			Vector3(radius * 2.0, radius * rng.randf_range(1.7, 2.0), radius * 2.0)
		)
		surface.append_from(
			sphere,
			0,
			Transform3D(berry_basis, world_position)
		)
	var combined := ArrayMesh.new()
	combined.resource_name = "berry_cluster"
	surface.commit(combined)
	var berries := MeshInstance3D.new()
	berries.name = "Berries"
	berries.mesh = combined
	berries.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(berries)
	# Fruit is a readiness signal, not permanent decoration. The lifecycle
	# explicitly reveals it only when this source can currently be gathered.
	visible = false
	scale = Vector3.ONE * HIDDEN_SCALE


func set_harvest_state(state: String, animate := true) -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	if _attention != null and _attention.is_valid():
		_attention.kill()
	rotation = Vector3.ZERO
	if state != READY_STATE:
		visible = false
		scale = Vector3.ONE * HIDDEN_SCALE
		return
	visible = true
	if not animate or not is_inside_tree():
		scale = Vector3.ONE
		if is_inside_tree():
			call_deferred("_start_attention")
		return
	scale = Vector3.ONE * HIDDEN_SCALE
	_transition = create_tween()
	_transition.tween_property(self, "scale", Vector3.ONE, 0.42).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	_transition.tween_callback(_start_attention)


func _start_attention() -> void:
	if not visible or not is_inside_tree():
		return
	if _attention != null and _attention.is_valid():
		_attention.kill()
	scale = Vector3.ONE
	rotation = Vector3.ZERO
	# A sparse tween-only pulse keeps ripe fruit readable without adding a
	# per-frame script to every harvestable model. The cluster moves in place;
	# no fruit is spawned, detached, or dropped by the interaction.
	_attention = create_tween().set_loops()
	_attention.tween_interval(_nudge_interval)
	_attention.tween_property(
		self, "scale", Vector3.ONE * _pulse_scale, 0.14
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_attention.tween_property(
		self, "rotation:z", _nudge_radians, 0.065
	).set_trans(Tween.TRANS_SINE)
	_attention.tween_property(
		self, "rotation:z", -_nudge_radians * 0.62, 0.09
	).set_trans(Tween.TRANS_SINE)
	_attention.tween_property(
		self, "rotation:z", 0.0, 0.075
	).set_trans(Tween.TRANS_SINE)
	_attention.tween_property(
		self, "scale", Vector3.ONE, 0.16
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
