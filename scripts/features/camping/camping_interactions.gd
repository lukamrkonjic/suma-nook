class_name CampingInteractions
extends RefCounted

const InteractionOptionScript := preload("res://scripts/core/interaction_option.gd")

var sleep


func _init(sleep_system) -> void:
	sleep = sleep_system


func options_for(actor_id: String, instance_id: int) -> Array:
	var result: Array = []
	var check: Dictionary = sleep.check(actor_id, instance_id)
	if String(check.get("reason", "")) == "You cannot sleep here.":
		return result
	result.append(InteractionOptionScript.new(
		"sleep",
		"Sleep",
		"camping",
		instance_id,
		bool(check["ok"]),
		String(check["reason"])
	))
	return result


func execute(option_id: String, actor_id: String, instance_id: int) -> bool:
	match option_id:
		"sleep":
			return sleep.begin(actor_id, instance_id)
	return false
