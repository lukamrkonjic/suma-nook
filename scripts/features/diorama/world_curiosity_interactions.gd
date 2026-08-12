class_name WorldCuriosityInteractions
extends RefCounted

const InteractionOptionScript := preload(
	"res://scripts/core/interaction_option.gd"
)

var curiosities: WorldCuriosityService


func _init(service: WorldCuriosityService) -> void:
	curiosities = service


func options_for(_actor_id: String, instance_id: int) -> Array:
	var state := curiosities.entry_for_instance(instance_id)
	if state.is_empty():
		return []
	return [InteractionOptionScript.new(
		"open_curiosity",
		"Break open %s" % String(state.get("display_name", "curiosity")),
		"world_curiosity",
		instance_id,
		true,
		"",
		{"busy": false},
		140
	)]


func execute(option_id: String, _actor_id: String, instance_id: int) -> bool:
	return (
		option_id == "open_curiosity"
		and bool(curiosities.claim(instance_id).get("accepted", false))
	)
