class_name HobbyActionResult
extends RefCounted
## The complete result of one peaceful hobby action. Common material-drop
## arrays intentionally do not exist in this contract.

var hobby_id: String = ""
var collection_discovery_id: String = ""
var personal_record_data: Dictionary = {}
var optional_tile_reward_id: String = ""
var optional_build_reward_id: String = ""
var optional_cosmetic_reward_id: String = ""
var reward_rarity: String = "common"
var was_new_discovery := false


func has_world_reward() -> bool:
	return optional_tile_reward_id != "" or optional_build_reward_id != ""


func to_dict() -> Dictionary:
	return {
		"hobby_id": hobby_id,
		"collection_discovery_id": collection_discovery_id,
		"personal_record_data": personal_record_data.duplicate(true),
		"optional_tile_reward_id": optional_tile_reward_id,
		"optional_build_reward_id": optional_build_reward_id,
		"optional_cosmetic_reward_id": optional_cosmetic_reward_id,
		"reward_rarity": reward_rarity,
		"was_new_discovery": was_new_discovery,
	}
