class_name VisitorSceneAdapter
extends Node3D
## Bridges VisitorModule events to replaceable world presenters.

signal reward_presented(reward: Dictionary)

var module: RefCounted
var registries: Registries
var grid: WorldGrid
var factories: VisitorPresenterRegistry
var current_presenter: Node3D
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


func sync_from_module() -> void:
	var event: Dictionary = module.call("waiting_event")
	if not event.is_empty():
		_on_visitor_available(event)


func event_at_screen(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	if current_presenter == null or camera == null or _collecting:
		return {}
	var point := current_presenter.global_position + Vector3(0.0, 0.48, 0.0)
	if camera.is_position_behind(point):
		return {}
	if camera.unproject_position(point).distance_to(screen_position) > 72.0:
		return {}
	return {
		"kind": "visitor",
		"event_id": int(current_presenter.get_meta("visitor_event_id", 0)),
		"cell": current_presenter.get_meta("visitor_cell", Vector2i.ZERO),
		"point": current_presenter.global_position,
	}


func event_at_cell(cell: Vector2i) -> Dictionary:
	if (
		current_presenter == null
		or _collecting
		or current_presenter.get_meta("visitor_cell", Vector2i(999999, 999999)) != cell
	):
		return {}
	return {
		"kind": "visitor",
		"event_id": int(current_presenter.get_meta("visitor_event_id", 0)),
		"cell": cell,
		"point": current_presenter.global_position,
	}


func interact(event_id: int) -> bool:
	if (
		_collecting
		or current_presenter == null
		or int(current_presenter.get_meta("visitor_event_id", 0)) != event_id
		or not current_presenter.has_method("begin_departure")
	):
		return false
	_collecting = bool(current_presenter.call("begin_departure"))
	return _collecting


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
	current_presenter.connect("departure_finished", _on_departure_finished)


func _on_departure_finished(event_id: int) -> void:
	var reward: Dictionary = module.call("collect", event_id)
	if not reward.is_empty():
		reward_presented.emit(reward.duplicate(true))
	if current_presenter != null:
		current_presenter.queue_free()
	current_presenter = null
	_collecting = false
