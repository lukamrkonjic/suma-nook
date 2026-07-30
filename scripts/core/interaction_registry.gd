class_name InteractionRegistry
extends RefCounted
## Presentation-neutral registry of structure interaction providers.
##
## Mouse targeting, proximity focus, and controller input all query this one
## registry, so a capability added by a feature behaves identically everywhere.

var _providers: Dictionary = {}
var _provider_order: Array[String] = []


func register_provider(feature_id: String, provider: RefCounted) -> void:
	if feature_id == "" or provider == null:
		return
	if not _providers.has(feature_id):
		_provider_order.append(feature_id)
	_providers[feature_id] = provider


func options_for(actor_id: String, instance_id: int) -> Array:
	var result: Array = []
	for feature_id in _provider_order:
		var provider: RefCounted = _providers.get(feature_id)
		if provider == null or not provider.has_method("options_for"):
			continue
		result.append_array(provider.options_for(actor_id, instance_id))
	return result


func primary_for(actor_id: String, instance_id: int):
	var options := options_for(actor_id, instance_id)
	return options[0] if not options.is_empty() else null


func execute(option, actor_id: String) -> bool:
	if option == null:
		return false
	var provider: RefCounted = _providers.get(String(option.feature_id))
	if provider == null or not provider.has_method("execute"):
		return false
	return bool(provider.execute(
		String(option.id),
		actor_id,
		int(option.target_instance_id)
	))
