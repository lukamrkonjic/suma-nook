class_name HarvestingInteractions
extends RefCounted

const InteractionOptionScript := preload(
	"res://scripts/core/interaction_option.gd"
)

var harvesting: HarvestingModule


func _init(harvesting_module: HarvestingModule) -> void:
	harvesting = harvesting_module


func options_for(_actor_id: String, instance_id: int) -> Array:
	if not harvesting.can_harvest(instance_id):
		return []
	var status := harvesting.status(instance_id)
	if status.is_empty():
		return []
	var ready := String(status.get("state", "")) == HarvestingModule.STATE_READY
	var label := String(status.get("verb", "gather")).capitalize()
	var reason := ""
	if not ready:
		reason = "Growing — ready in %d seconds." % ceili(
			float(status.get("remaining", 0.0))
		)
		label = reason
	return [InteractionOptionScript.new(
		"harvest",
		label,
		"harvesting",
		instance_id,
		ready,
		reason,
		status
	)]


func execute(option_id: String, actor_id: String, instance_id: int) -> bool:
	if option_id != "harvest":
		return false
	return bool(harvesting.request_hit(instance_id, actor_id).get("accepted", false))
