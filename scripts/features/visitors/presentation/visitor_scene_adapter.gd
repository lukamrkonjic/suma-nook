class_name VisitorSceneAdapter
extends Node3D
## Bridges VisitorModule events to replaceable world presenters.

signal reward_presented(reward: Dictionary)
signal vase_smashed(position: Vector3, reward: Dictionary)

var module: RefCounted
var registries: Registries
var grid: WorldGrid
var factories: VisitorPresenterRegistry
var current_presenter: Node3D
var current_vase: Node3D
var _collecting := false


func setup(
	visitor_module: RefCounted,
	regs: Registries,
	world_grid: WorldGrid,
	presenter_factories: VisitorPresenterRegistry
) -> void:
	module = visitor_module
	registries = regs
	grid = world_grid
	factories = presenter_factories
	var adapter_ref: WeakRef = weakref(self)
	module.connect("visitor_available", func(event):
		var adapter := adapter_ref.get_ref() as VisitorSceneAdapter
		if adapter != null:
			adapter._on_visitor_available(event)
	)
	module.connect("visitor_vase_ready", func(event):
		var adapter := adapter_ref.get_ref() as VisitorSceneAdapter
		if adapter != null:
			adapter._on_visitor_vase_ready(event)
	)


func sync_from_module() -> void:
	var event: Dictionary = module.call("waiting_event")
	if not event.is_empty():
		if String(event.get("phase", "visiting")) == "vase":
			_on_visitor_vase_ready(event)
		else:
			_on_visitor_available(event)


func event_at_screen(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	var target := current_vase
	if target == null or camera == null or _collecting:
		return {}
	var point := target.global_position + Vector3(0.0, 0.28, 0.0)
	if camera.is_position_behind(point):
		return {}
	if camera.unproject_position(point).distance_to(screen_position) > 72.0:
		return {}
	return {
		"kind": "visitor_vase",
		"event_id": int(target.get_meta("visitor_event_id", 0)),
		"cell": target.get_meta("visitor_cell", Vector2i.ZERO),
		"point": target.global_position,
	}


func event_at_cell(cell: Vector2i) -> Dictionary:
	var target := current_vase
	if (
		target == null
		or _collecting
		or target.get_meta("visitor_cell", Vector2i(999999, 999999)) != cell
	):
		return {}
	return {
		"kind": "visitor_vase",
		"event_id": int(target.get_meta("visitor_event_id", 0)),
		"cell": cell,
		"point": target.global_position,
	}


func interact(event_id: int) -> bool:
	return _smash_vase(event_id)


func _on_visitor_available(event: Dictionary) -> void:
	if current_presenter != null:
		return
	var presentation := registries.visitor_presentation(
		String(event.get("presentation_id", ""))
	)
	if presentation == null:
		return
	var presenter := factories.create(presentation.presenter_type)
	if presenter == null:
		push_warning(
			"No visitor presenter registered for '%s'" % presentation.presenter_type
		)
		return
	current_presenter = presenter
	add_child(current_presenter)
	current_presenter.call("setup", event, presentation)
	var raw_cell: Array = event.get("cell", [0, 0])
	var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
	current_presenter.global_position = grid.cell_to_world(
		cell, grid.top_elevation(cell)
	) + Vector3(0.0, 0.04, 0.0)
	if current_presenter.has_method("set_wander_center"):
		current_presenter.call("set_wander_center")
	current_presenter.connect("departure_finished", _on_departure_finished)


func _on_visitor_vase_ready(event: Dictionary) -> void:
	if current_presenter != null and current_presenter.has_method("begin_departure"):
		current_presenter.call("begin_departure")
		return
	_spawn_vase(event, _event_world_position(event))


func _on_departure_finished(event_id: int, vase_position: Vector3) -> void:
	var event: Dictionary = module.call("waiting_event")
	if current_presenter != null:
		current_presenter.queue_free()
	current_presenter = null
	_collecting = false
	if int(event.get("event_id", 0)) == event_id:
		_spawn_vase(event, vase_position)


func _spawn_vase(event: Dictionary, world_position: Vector3) -> void:
	if current_vase != null or String(event.get("phase", "")) != "vase":
		return
	current_vase = Node3D.new()
	current_vase.name = "VisitorGiftVase"
	current_vase.add_to_group("visitor_gift_vases")
	current_vase.set_meta("visitor_event_id", int(event.get("event_id", 0)))
	var raw_cell: Array = event.get("cell", [0, 0])
	var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
	current_vase.set_meta("visitor_cell", cell)
	current_vase.add_child(_vase_visual())
	add_child(current_vase)
	current_vase.global_position = world_position
	current_vase.scale = Vector3(0.3, 0.08, 0.3)
	var settle := current_vase.create_tween()
	settle.tween_property(current_vase, "scale", Vector3.ONE * 1.08, 0.3).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	settle.tween_property(current_vase, "scale", Vector3.ONE, 0.12)


func _smash_vase(event_id: int) -> bool:
	if (
		_collecting
		or current_vase == null
		or int(current_vase.get_meta("visitor_event_id", 0)) != event_id
	):
		return false
	_collecting = true
	var vase := current_vase
	var position := vase.global_position
	var squash := vase.create_tween()
	squash.tween_property(vase, "scale", Vector3(1.18, 0.72, 1.18), 0.08).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	squash.tween_property(vase, "scale", Vector3(0.05, 1.3, 0.05), 0.08).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	squash.tween_callback(func() -> void:
		var reward: Dictionary = module.call("collect", event_id)
		vase.queue_free()
		current_vase = null
		_collecting = false
		if reward.is_empty():
			return
		vase_smashed.emit(position, reward.duplicate(true))
		reward_presented.emit(reward.duplicate(true))
	)
	return true


func _event_world_position(event: Dictionary) -> Vector3:
	var raw_cell: Array = event.get("cell", [0, 0])
	var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
	return grid.cell_to_world(cell, grid.top_elevation(cell)) + Vector3(0.0, 0.04, 0.0)


func _vase_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "CeramicVaseVisual"
	var palette := PaletteDefinition.shared()
	var clay := StandardMaterial3D.new()
	clay.albedo_color = palette.color("terracotta_primary", Color("c96f4d"))
	clay.roughness = 0.92
	var cream := StandardMaterial3D.new()
	cream.albedo_color = palette.color("warm_white", Color("f4dfb7"))
	cream.roughness = 0.88
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.22
	body_mesh.height = 0.38
	body_mesh.radial_segments = 14
	body_mesh.rings = 7
	var body := MeshInstance3D.new()
	body.name = "VaseBody"
	body.mesh = body_mesh
	body.scale = Vector3(1.0, 0.92, 1.0)
	body.position.y = 0.2
	body.material_override = clay
	root.add_child(body)
	var neck_mesh := CylinderMesh.new()
	neck_mesh.top_radius = 0.095
	neck_mesh.bottom_radius = 0.13
	neck_mesh.height = 0.19
	neck_mesh.radial_segments = 14
	var neck := MeshInstance3D.new()
	neck.name = "VaseNeck"
	neck.mesh = neck_mesh
	neck.position.y = 0.43
	neck.material_override = clay
	root.add_child(neck)
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 0.12
	rim_mesh.bottom_radius = 0.12
	rim_mesh.height = 0.035
	rim_mesh.radial_segments = 14
	var rim := MeshInstance3D.new()
	rim.name = "PaintedRim"
	rim.mesh = rim_mesh
	rim.position.y = 0.525
	rim.material_override = cream
	root.add_child(rim)
	var opening_mesh := CylinderMesh.new()
	opening_mesh.top_radius = 0.073
	opening_mesh.bottom_radius = 0.073
	opening_mesh.height = 0.008
	opening_mesh.radial_segments = 14
	var opening := MeshInstance3D.new()
	opening.name = "VaseOpening"
	opening.mesh = opening_mesh
	opening.position.y = 0.546
	var opening_material := StandardMaterial3D.new()
	opening_material.albedo_color = palette.color(
		"terracotta_shadow", Color("6b291b")
	)
	opening_material.roughness = 1.0
	opening.material_override = opening_material
	root.add_child(opening)
	for side in [-1.0, 1.0]:
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(0.07, 0.055, 0.025)
		var band := MeshInstance3D.new()
		band.name = "PaintedMark"
		band.mesh = band_mesh
		band.position = Vector3(side * 0.145, 0.25, -0.16)
		band.rotation.z = side * 0.28
		band.material_override = cream
		root.add_child(band)
	var shine_mesh := CylinderMesh.new()
	shine_mesh.top_radius = 0.3
	shine_mesh.bottom_radius = 0.3
	shine_mesh.height = 0.008
	shine_mesh.radial_segments = 24
	var shine := MeshInstance3D.new()
	shine.name = "GiftVaseShine"
	shine.mesh = shine_mesh
	shine.position.y = 0.015
	var shine_material := StandardMaterial3D.new()
	shine_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var shine_color := palette.color("gold", Color("f2ca69"))
	shine_color.a = 0.22
	shine_material.albedo_color = shine_color
	shine_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine_material.emission_enabled = true
	shine_material.emission = Color(shine_color.r, shine_color.g, shine_color.b)
	shine_material.emission_energy_multiplier = 0.7
	shine.material_override = shine_material
	root.add_child(shine)
	var pulse := shine.create_tween().set_loops()
	pulse.tween_property(shine, "scale", Vector3.ONE * 1.15, 0.9).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(shine, "scale", Vector3.ONE * 0.92, 0.9).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	return root
