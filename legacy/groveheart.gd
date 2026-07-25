extends Node3D
# legacy-disabled class_name Groveheart

signal hovered(active: bool)

const Factory := preload("res://scripts/visual_factory.gd")

var area: Area3D
var glow: OmniLight3D
var crown: Node3D
var busy := false
var _idle_time := 0.0


func setup() -> void:
	name = "Bloomforge"
	_build_visual()
	_build_area()


func _process(delta: float) -> void:
	_idle_time += delta
	if not busy and crown != null:
		crown.rotation.y = sin(_idle_time * 0.55) * 0.08
		crown.position.y = 1.18 + sin(_idle_time * 1.35) * 0.035
		glow.light_energy = 0.58 + sin(_idle_time * 1.9) * 0.10


func _build_visual() -> void:
	# The Bloomforge is an original flower-kiln: recognisably interactive without
	# borrowing the reference game's pot silhouette.
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.68
	base_mesh.bottom_radius = 0.78
	base_mesh.height = 0.42
	base_mesh.radial_segments = 14
	base.mesh = base_mesh
	base.material_override = Factory.material("forge_base", Color("#983f29"))
	base.position.y = 0.24
	add_child(base)

	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.58
	body_mesh.bottom_radius = 0.68
	body_mesh.height = 0.72
	body_mesh.radial_segments = 14
	body.mesh = body_mesh
	body.material_override = Factory.material("forge_body", Color("#d3622d"))
	body.position.y = 0.68
	add_child(body)

	var collar := MeshInstance3D.new()
	var collar_mesh := CylinderMesh.new()
	collar_mesh.top_radius = 0.70
	collar_mesh.bottom_radius = 0.62
	collar_mesh.height = 0.22
	collar_mesh.radial_segments = 14
	collar.mesh = collar_mesh
	collar.material_override = Factory.material("forge_collar", Color("#f0a127"))
	collar.position.y = 1.08
	add_child(collar)

	var mouth := MeshInstance3D.new()
	var mouth_mesh := CylinderMesh.new()
	mouth_mesh.top_radius = 0.49
	mouth_mesh.bottom_radius = 0.49
	mouth_mesh.height = 0.025
	mouth_mesh.radial_segments = 14
	mouth.mesh = mouth_mesh
	mouth.material_override = Factory.material("forge_mouth", Color("#673125"))
	mouth.position.y = 1.205
	add_child(mouth)

	for i: int in 4:
		var foot := MeshInstance3D.new()
		var foot_mesh := SphereMesh.new()
		foot_mesh.radius = 0.20
		foot_mesh.height = 0.22
		foot_mesh.radial_segments = 10
		foot_mesh.rings = 4
		foot.mesh = foot_mesh
		foot.material_override = Factory.material("forge_foot", Color("#f0ddbd"))
		var angle := float(i) * TAU / 4.0 + PI * 0.25
		foot.position = Vector3(cos(angle) * 0.67, 0.11, sin(angle) * 0.67)
		foot.scale = Vector3(1.15, 0.70, 0.85)
		add_child(foot)

	crown = Node3D.new()
	crown.name = "BloomFlame"
	crown.position.y = 1.18
	add_child(crown)
	for i: int in 5:
		var petal := MeshInstance3D.new()
		var petal_mesh := SphereMesh.new()
		petal_mesh.radius = 0.23
		petal_mesh.height = 0.36
		petal_mesh.radial_segments = 11
		petal_mesh.rings = 5
		petal.mesh = petal_mesh
		petal.material_override = Factory.material("forge_petal_%d" % (i % 2),
			Color("#ffb22d") if i % 2 == 0 else Color("#f27a29"), Color("#ff9c24"))
		var angle := float(i) * TAU / 5.0
		petal.position = Vector3(cos(angle) * 0.20, 0.17 + (i % 2) * 0.06, sin(angle) * 0.20)
		petal.rotation = Vector3(0.22, -angle, cos(angle) * 0.45)
		petal.scale = Vector3(0.62, 1.15, 0.72)
		crown.add_child(petal)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.22
	core_mesh.height = 0.46
	core_mesh.radial_segments = 12
	core_mesh.rings = 6
	core.mesh = core_mesh
	core.material_override = Factory.material("forge_core", Color("#ffe16a"), Color("#ffc22f"))
	core.position.y = 0.17
	crown.add_child(core)

	glow = OmniLight3D.new()
	glow.light_color = Color("#ffb33a")
	glow.light_energy = 0.58
	glow.omni_range = 4.2
	glow.position = Vector3(0, 1.36, 0)
	glow.shadow_enabled = false
	add_child(glow)


func _build_area() -> void:
	area = Area3D.new()
	area.name = "BloomforgeArea"
	area.collision_layer = 2
	area.collision_mask = 0
	area.set_meta("groveheart", self)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.95
	shape.height = 2.4
	collision.shape = shape
	collision.position.y = 0.82
	area.add_child(collision)
	add_child(area)
	area.mouse_entered.connect(func() -> void:
		set_highlight(true)
		hovered.emit(true))
	area.mouse_exited.connect(func() -> void:
		set_highlight(false)
		hovered.emit(false))


func set_highlight(active: bool) -> void:
	var target := 1.16 if active else 1.0
	var tween := create_tween()
	tween.tween_property(crown, "scale", Vector3.ONE * target, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	glow.light_energy = 1.15 if active else 0.58


func play_offer(callback: Callable) -> void:
	if busy:
		return
	busy = true
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.08, 0.88, 1.08), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(glow, "light_energy", 2.5, 0.15)
	tween.tween_property(self, "scale", Vector3(0.94, 1.17, 0.94), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(crown, "rotation:y", crown.rotation.y + TAU, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void:
		busy = false
		glow.light_energy = 0.58
		if callback.is_valid():
			callback.call())
