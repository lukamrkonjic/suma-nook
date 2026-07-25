extends Node3D
# legacy-disabled class_name EffectsManager

const Factory := preload("res://scripts/visual_factory.gd")


func setup_ambient() -> void:
	var pollen := CPUParticles3D.new()
	pollen.name = "FloatingPollen"
	pollen.amount = 44
	pollen.lifetime = 7.0
	pollen.preprocess = 7.0
	pollen.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	pollen.emission_box_extents = Vector3(8.5, 2.6, 8.5)
	pollen.position.y = 1.2
	pollen.direction = Vector3(0.5, 0.20, 0.15)
	pollen.spread = 25.0
	pollen.initial_velocity_min = 0.04
	pollen.initial_velocity_max = 0.13
	pollen.gravity = Vector3(0, 0.015, 0)
	pollen.scale_amount_min = 0.5
	pollen.scale_amount_max = 1.2
	pollen.color = Color(0.91, 0.85, 0.62, 0.45)
	var pollen_mesh := QuadMesh.new()
	pollen_mesh.size = Vector2(0.025, 0.025)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.93, 0.86, 0.65, 0.65)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pollen_mesh.material = mat
	pollen.mesh = pollen_mesh
	add_child(pollen)


func burst(world_position: Vector3, category: StringName = &"dust", strong := false) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.86
	particles.amount = 18 if strong else 9
	particles.lifetime = 0.65 if strong else 0.42
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.20 if strong else 0.11
	particles.direction = Vector3.UP
	particles.spread = 55.0
	particles.initial_velocity_min = 0.45
	particles.initial_velocity_max = 1.15 if strong else 0.75
	particles.gravity = Vector3(0, -1.8, 0)
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.4
	particles.position = world_position
	var color := Color("#a38463")
	match category:
		&"leaves", &"pollen", &"spores":
			color = Color("#91a95a")
		&"pebbles":
			color = Color("#b5b2a2")
		&"sparks":
			color = Color("#efd0ae")
	particles.color = color
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * (0.055 if not strong else 0.085)
	mesh.material = Factory.material("particle_%s" % category, color, color if category == &"sparks" else Color.TRANSPARENT)
	particles.mesh = mesh
	add_child(particles)
	particles.finished.connect(particles.queue_free)
	particles.emitting = true


func magical_boundary(world_position: Vector3) -> void:
	burst(world_position, &"sparks", true)
	var ring := Node3D.new()
	ring.name = "PixelMagicRing"
	ring.position = world_position + Vector3(0, 0.12, 0)
	add_child(ring)
	for i: int in 12:
		var glint := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.08, 0.035, 0.08)
		glint.mesh = mesh
		glint.material_override = Factory.material("boundary_ring", Color("#9db8d6"), Color("#9db8d6"))
		var angle := float(i) / 12.0 * TAU
		glint.position = Vector3(cos(angle) * 0.38, 0, sin(angle) * 0.38)
		glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.add_child(glint)
	ring.scale = Vector3.ONE * 0.2
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * 1.5, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for glint: MeshInstance3D in ring.get_children():
		tween.tween_property(glint, "transparency", 1.0, 0.55)
	tween.chain().tween_callback(ring.queue_free)
