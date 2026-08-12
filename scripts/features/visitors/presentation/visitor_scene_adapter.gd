class_name VisitorSceneAdapter
extends Node3D
## Bridges VisitorModule events to replaceable world presenters.

signal reward_presented(reward: Dictionary)
signal vase_smashed(
	position: Vector3,
	reward: Dictionary,
	container_style: Dictionary
)
signal visitor_greeted(position: Vector3, display_name: String)

const VISUAL_POINTER_MARGIN := 12.0

var module: RefCounted
var registries: Registries
var grid: WorldGrid
var factories: VisitorPresenterRegistry
var container_visuals := VisitorContainerVisualFactory.new()
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
	if camera == null:
		return {}
	if current_vase != null and not _collecting:
		if _screen_hits_visual(camera, screen_position, current_vase):
			return _vase_target(current_vase)
	if current_presenter != null and not _presenter_is_departing():
		if _screen_hits_visual(camera, screen_position, current_presenter):
			return _visitor_target(current_presenter)
	return {}


func event_at_cell(cell: Vector2i) -> Dictionary:
	if (
		current_vase != null
		and not _collecting
		and current_vase.get_meta(
			"visitor_cell", Vector2i(999999, 999999)
		) == cell
	):
		return _vase_target(current_vase)
	if (
		current_presenter != null
		and not _presenter_is_departing()
		and current_presenter.get_meta(
			"visitor_cell", Vector2i(999999, 999999)
		) == cell
	):
		return _visitor_target(current_presenter)
	return {}


func interact(event_id: int) -> bool:
	if (
		current_presenter != null
		and not _presenter_is_departing()
		and int(current_presenter.get_meta("visitor_event_id", 0)) == event_id
	):
		if (
			not current_presenter.has_method("greet")
			or not bool(current_presenter.call("greet"))
		):
			return false
		visitor_greeted.emit(
			current_presenter.global_position,
			String(current_presenter.get_meta("visitor_display_name", "Visitor"))
		)
		return true
	return _smash_vase(event_id)


func _visitor_target(target: Node3D) -> Dictionary:
	var interaction_point := target.global_position + Vector3.UP * 0.35
	if target.has_method("interaction_world_point"):
		interaction_point = target.call("interaction_world_point")
	return {
		"kind": "visitor",
		"event_id": int(target.get_meta("visitor_event_id", 0)),
		"cell": target.get_meta("visitor_cell", Vector2i.ZERO),
		"point": interaction_point,
		"visual": target,
		"display_name": target.get_meta("visitor_display_name", "Visitor"),
		"collection_name": "Wandering Visitors",
	}


func _vase_target(target: Node3D) -> Dictionary:
	return {
		"kind": "visitor_vase",
		"event_id": int(target.get_meta("visitor_event_id", 0)),
		"cell": target.get_meta("visitor_cell", Vector2i.ZERO),
		"point": target.global_position,
		"visual": target,
		"display_name": target.get_meta(
			"visitor_container_name", "Visitor Gift"
		),
		"collection_name": target.get_meta(
			"visitor_collection_name", "Visitor Collection"
		),
	}


func _presenter_is_departing() -> bool:
	return (
		current_presenter == null
		or (
			current_presenter.has_method("is_departing")
			and bool(current_presenter.call("is_departing"))
		)
	)


## Screen-space bounds follow the actual procedural meshes. This keeps the
## generous visitor target on the creature itself instead of selecting the tile
## under it, and works for every body plan without a hand-authored collider.
func _screen_hits_visual(
	camera: Camera3D,
	screen_position: Vector2,
	visual: Node3D
) -> bool:
	var screen_bounds := Rect2()
	var has_bounds := false
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null or not mesh_instance.is_visible_in_tree():
			continue
		var bounds := mesh_instance.get_aabb()
		for endpoint_index in range(8):
			var world_point := mesh_instance.to_global(
				bounds.get_endpoint(endpoint_index)
			)
			if camera.is_position_behind(world_point):
				continue
			var projected := camera.unproject_position(world_point)
			if not has_bounds:
				screen_bounds = Rect2(projected, Vector2.ZERO)
				has_bounds = true
			else:
				screen_bounds = screen_bounds.expand(projected)
	return (
		has_bounds
		and screen_bounds.grow(VISUAL_POINTER_MARGIN).has_point(screen_position)
	)


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
	current_presenter.set_meta("visitor_display_name", presentation.display_name)
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
	var category := String(event.get("landing_collection", ""))
	var family := String(event.get("landing_family", ""))
	if category == "" or family == "":
		var landing_tile := grid.tile_def_at(cell, grid.top_elevation(cell))
		if landing_tile != null:
			category = landing_tile.catalog_category
			family = landing_tile.family
	var visual := container_visuals.create_for_context(category, family)
	var style: Dictionary = visual.get_meta(
		"visitor_container_style", {}
	)
	current_vase.set_meta("visitor_container_style", style.duplicate(true))
	current_vase.set_meta(
		"visitor_container_name", style.get("name", "Visitor Gift")
	)
	current_vase.set_meta(
		"visitor_collection_name",
		style.get("collection_name", "Visitor Collection")
	)
	current_vase.add_child(visual)
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
	var container_style: Dictionary = vase.get_meta(
		"visitor_container_style", {}
	).duplicate(true)
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
		vase_smashed.emit(
			position,
			reward.duplicate(true),
			container_style
		)
		reward_presented.emit(reward.duplicate(true))
	)
	return true


func _event_world_position(event: Dictionary) -> Vector3:
	var raw_cell: Array = event.get("cell", [0, 0])
	var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
	return grid.cell_to_world(cell, grid.top_elevation(cell)) + Vector3(0.0, 0.04, 0.0)
