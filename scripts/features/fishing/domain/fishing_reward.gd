class_name FishingReward
extends RefCounted
## One reward entry inside a haul: a tied tile bundle, a single model, or a
## bonus keepsake charm. Pure data — placement, rendering, and effects are
## other systems' responsibilities.

const FORM_TILE_BUNDLE := "tile_bundle"
const FORM_MODEL := "model"
const FORM_KEEPSAKE := "keepsake"

var form := FORM_TILE_BUNDLE
var loot_id := ""                    # FishingLootDefinition id
var building_id := ""                # tile / structure / keepsake stable id
var quantity := 1
var rarity := "common"
var presentation_profile := ""


static func make(
	reward_form: String,
	source_loot_id: String,
	target_building_id: String,
	count: int,
	reward_rarity: String,
	profile := ""
) -> FishingReward:
	var reward := FishingReward.new()
	reward.form = reward_form
	reward.loot_id = source_loot_id
	reward.building_id = target_building_id
	reward.quantity = maxi(1, count)
	reward.rarity = reward_rarity
	reward.presentation_profile = profile
	return reward


## The building-content kind this reward hands to the placement pipeline.
func content_kind() -> String:
	match form:
		FORM_TILE_BUNDLE: return "tile"
		FORM_MODEL: return "structure"
		FORM_KEEPSAKE: return "keepsake"
	return ""


func is_rare() -> bool:
	return rarity == "rare"


func to_dict() -> Dictionary:
	return {
		"form": form,
		"loot_id": loot_id,
		"building_id": building_id,
		"quantity": quantity,
		"rarity": rarity,
		"presentation_profile": presentation_profile,
	}


static func from_dict(data: Dictionary) -> FishingReward:
	return make(
		String(data.get("form", FORM_TILE_BUNDLE)),
		String(data.get("loot_id", "")),
		String(data.get("building_id", "")),
		int(data.get("quantity", 1)),
		String(data.get("rarity", "common")),
		String(data.get("presentation_profile", ""))
	)
