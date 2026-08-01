class_name HaulComposer
extends RefCounted
## Decides how large a haul is and which reward forms fill it. Pure policy
## over balance data — no candidate selection happens here.

var balance: FishingBalance
var rng: RngService


func _init(balance_config: FishingBalance, rng_service: RngService) -> void:
	balance = balance_config
	rng = rng_service


func roll_catch_size() -> String:
	var entries: Array = []
	for size: String in balance.haul_size_weights():
		entries.append({
			"size": size,
			"weight": float(balance.haul_size_weights()[size]),
		})
	var choice := rng.weighted("fishing_haul_size", entries)
	return String(choice.get("size", FishingHaul.SIZE_SINGLE))


## The preferred form sequence for a catch size. Rich guarantees the first
## slot is a tile bundle; Bountiful prefers bundle + bundle + model. The
## generator may still substitute forms when a pool has no valid candidate.
func forms_for(catch_size: String) -> Array[String]:
	var forms: Array[String] = []
	match catch_size:
		FishingHaul.SIZE_RICH:
			forms.append(FishingReward.FORM_TILE_BUNDLE)
			forms.append(_roll_form(balance.rich_second_form_weights(), "fishing_form_rich"))
		FishingHaul.SIZE_BOUNTIFUL:
			forms.append(FishingReward.FORM_TILE_BUNDLE)
			forms.append(FishingReward.FORM_TILE_BUNDLE)
			forms.append(FishingReward.FORM_MODEL)
		_:
			forms.append(_roll_form(balance.single_form_weights(), "fishing_form_single"))
	return forms


func entry_count_for(catch_size: String) -> int:
	match catch_size:
		FishingHaul.SIZE_RICH: return 2
		FishingHaul.SIZE_BOUNTIFUL: return 3
	return 1


func _roll_form(weights: Dictionary, stream: String) -> String:
	var entries: Array = []
	for form: String in weights:
		entries.append({"form": form, "weight": float(weights[form])})
	var choice := rng.weighted(stream, entries)
	return String(choice.get("form", FishingReward.FORM_TILE_BUNDLE))
