class_name RewardRevealPresenterRegistry
extends RefCounted
## Application-owned presenter factories. Reward selection and harvest saves
## retain only stable reveal-profile ids; concrete animation scenes remain
## replaceable composition-root dependencies.

var _factories: Dictionary = {}


func register(presenter_type: String, factory: Callable) -> void:
	if presenter_type != "" and factory.is_valid():
		_factories[presenter_type] = factory


func unregister(presenter_type: String) -> void:
	_factories.erase(presenter_type)


func create(presenter_type: String) -> Node3D:
	var factory: Callable = _factories.get(presenter_type, Callable())
	return factory.call() as Node3D if factory.is_valid() else null


func supports(presenter_type: String) -> bool:
	return _factories.has(presenter_type)
