class_name FerryArrivalPresentation
extends ArrivalPresentationBase
## Charming low-poly ferry animation driven entirely by DeliveryPoint markers.

var ferry_visual: Node3D
var _tween: Tween
var _bob_time := 0.0
var _delivery_emitted := false


func setup(material_library: MaterialLibrary) -> void:
	super.setup(material_library)
	ferry_visual = _build_ferry()
	add_child(ferry_visual)
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_bob_time += delta
	if ferry_visual != null:
		ferry_visual.position.y = sin(_bob_time * 2.1) * 0.055
		ferry_visual.rotation.z = sin(_bob_time * 1.35) * 0.018


func play(point: DeliveryPoint, payload: LandParcelPayload, presentation_config: Dictionary) -> void:
	super.play(point, payload, presentation_config)
	if active:
		return
	active = true
	_delivery_emitted = false
	visible = true
	set_process(true)
	global_position = point.approach.global_position
	global_rotation = Vector3.ZERO
	arrival_started.emit()
	_tween = create_tween()
	_tween.tween_property(
		self,
		"global_position",
		point.arrival.global_position,
		float(config.get("ferry_approach_seconds", 4.2))
	).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_on_arrived)


func _on_arrived() -> void:
	arrived.emit()
	_tween = create_tween()
	_tween.tween_interval(float(config.get("ferry_dock_seconds", 1.0)))
	_tween.tween_callback(_emit_delivery)
	_tween.tween_interval(1.15)
	_tween.tween_callback(force_departure)


func _emit_delivery() -> void:
	if _delivery_emitted or active_payload == null:
		return
	_delivery_emitted = true
	delivery_ready.emit(active_payload)


func force_departure() -> void:
	if not active:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_emit_delivery()
	departure_started.emit()
	_tween = create_tween()
	_tween.tween_property(
		self,
		"global_position",
		delivery_point.departure.global_position,
		float(config.get("ferry_departure_seconds", 3.6))
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_finish_departure)


func _finish_departure() -> void:
	active = false
	active_payload = null
	visible = false
	set_process(false)
	departed.emit()


func _build_ferry() -> Node3D:
	var root := Node3D.new()
	root.name = "LittleFerry"
	var hull := _box(Vector3(1.45, 0.34, 1.7), materials.material("dark_wood"))
	hull.position.y = 0.02
	root.add_child(hull)
	var deck := _box(Vector3(1.3, 0.12, 1.5), materials.material("wood"))
	deck.position.y = 0.25
	root.add_child(deck)
	var cabin := _box(Vector3(0.82, 0.62, 0.68), materials.material("pale_stone"))
	cabin.position = Vector3(0, 0.6, -0.18)
	root.add_child(cabin)
	var roof := _box(Vector3(1.02, 0.12, 0.84), materials.material("fabric"))
	roof.position = Vector3(0, 0.96, -0.18)
	root.add_child(roof)
	var chimney := _cylinder(0.095, 0.11, 0.5, materials.material("dark_wood"))
	chimney.position = Vector3(0.35, 0.76, 0.44)
	root.add_child(chimney)
	for side in [-1.0, 1.0]:
		var bumper := _cylinder(0.13, 0.13, 0.22, materials.material("pale_stone"))
		bumper.rotation.z = PI * 0.5
		bumper.position = Vector3(side * 0.78, 0.12, 0.35)
		root.add_child(bumper)
	return root


func _box(size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	return instance


func _cylinder(top_radius: float, bottom_radius: float, height: float, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 10
	instance.mesh = mesh
	instance.material_override = material
	return instance
