class_name InteractionOption
extends RefCounted
## Presentation-neutral interaction offered by a feature module.

var id: String
var label: String
var feature_id: String
var target_instance_id: int
var enabled := true
var disabled_reason: String
var payload: Dictionary = {}


func _init(
	option_id: String,
	option_label: String,
	option_feature: String,
	option_target_instance_id: int,
	option_enabled := true,
	option_reason: String = "",
	option_payload: Dictionary = {}
) -> void:
	id = option_id
	label = option_label
	feature_id = option_feature
	target_instance_id = option_target_instance_id
	enabled = option_enabled
	disabled_reason = option_reason
	payload = option_payload.duplicate(true)
