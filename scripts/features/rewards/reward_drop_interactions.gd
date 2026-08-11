class_name RewardDropInteractions
extends RefCounted

const InteractionOptionScript := preload("res://scripts/core/interaction_option.gd")

var drops: RewardDropService


func _init(service: RewardDropService) -> void:
	drops = service


func options_for(_actor_id: String, instance_id: int) -> Array:
	var entry := drops.entry_for_instance(instance_id)
	if entry.is_empty():
		return []
	return [InteractionOptionScript.new(
		"claim_reward_drop",
		"Claim the fallen gift",
		"reward_drop",
		instance_id,
		true,
		"",
		{"busy": false},
		120
	)]


func execute(option_id: String, _actor_id: String, instance_id: int) -> bool:
	return (
		option_id == "claim_reward_drop"
		and bool(drops.claim(instance_id).get("accepted", false))
	)
