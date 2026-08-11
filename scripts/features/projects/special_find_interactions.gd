class_name SpecialFindInteractions
extends RefCounted

const InteractionOptionScript := preload("res://scripts/core/interaction_option.gd")

var service: SpecialFindService
var registries: Registries


func _init(find_service: SpecialFindService, content: Registries) -> void:
	service = find_service
	registries = content


func options_for(_actor_id: String, instance_id: int) -> Array:
	var state := service.active_for_instance(instance_id)
	if state.is_empty():
		return []
	var definition = registries.special_find(String(state.get("id", "")))
	if definition == null:
		return []
	return [InteractionOptionScript.new(
		"collect_special_find",
		"Gather %s" % definition.display_name,
		"special_find",
		instance_id,
		true,
		"",
		{"find_id": definition.id, "busy": false},
		100
	)]


func execute(option_id: String, _actor_id: String, instance_id: int) -> bool:
	return (
		option_id == "collect_special_find"
		and bool(service.collect(instance_id).get("accepted", false))
	)
