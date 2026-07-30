class_name FireInteractions
extends RefCounted

const InteractionOptionScript := preload(
	"res://scripts/core/interaction_option.gd"
)

var fire: FireSystem


func _init(fire_system: FireSystem) -> void:
	fire = fire_system


func options_for(_actor_id: String, instance_id: int) -> Array:
	if not fire.supports(instance_id):
		return []
	var burning := fire.is_burning(instance_id)
	return [InteractionOptionScript.new(
		"toggle_fire",
		"Extinguish fire" if burning else "Light fire",
		"fire",
		instance_id,
		true,
		"",
		{"burning": burning}
	)]


func execute(option_id: String, _actor_id: String, instance_id: int) -> bool:
	if option_id != "toggle_fire":
		return false
	return fire.toggle(instance_id)
