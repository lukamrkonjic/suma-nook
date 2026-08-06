class_name VisitorPresenterRegistry
extends RefCounted
## Small application-owned factory registry. Adding or replacing a presenter
## type does not modify VisitorModule or visitor save data.

var _factories: Dictionary = {}


func register(presenter_type: String, factory: Callable) -> void:
	if presenter_type != "" and factory.is_valid():
		_factories[presenter_type] = factory


func unregister(presenter_type: String) -> void:
	_factories.erase(presenter_type)


func create(presenter_type: String) -> Node3D:
	var factory: Callable = _factories.get(presenter_type, Callable())
	if not factory.is_valid():
		return null
	return factory.call() as Node3D


func supports(presenter_type: String) -> bool:
	return _factories.has(presenter_type)
