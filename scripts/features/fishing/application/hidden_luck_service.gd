class_name HiddenLuckService
extends RefCounted
## Invisible protection against long dry streaks. Returns temporary weight
## and chance adjustments from configurable thresholds; owns nothing visible.
## Spirits, attention, and haul size never touch these numbers.

var balance: FishingBalance
var state := HiddenLuckState.new()


func _init(balance_config: FishingBalance) -> void:
	balance = balance_config


## Multiplier applied to rare candidates' weights. 1.0 until the configured
## streak, then a linear ramp per unlucky catch.
func rare_weight_multiplier() -> float:
	var over := state.catches_since_rare - balance.rare_pity_start()
	if over <= 0:
		return 1.0
	return 1.0 + float(over) * balance.rare_pity_bonus()


## The keepsake bonus-roll chance including protection, clamped to [0, 1].
func keepsake_chance() -> float:
	var chance := balance.keepsake_base_chance()
	var over := state.catches_since_keepsake - balance.keepsake_pity_start()
	if over > 0:
		chance += float(over) * balance.keepsake_pity_bonus()
	return clampf(chance, 0.0, 1.0)


## Called only after a haul is safely committed — a cancelled or undelivered
## catch never advances or resets protection.
func on_haul_committed(haul: FishingHaul) -> void:
	if haul.has_rare_entry():
		state.catches_since_rare = 0
	else:
		state.catches_since_rare += 1
	if haul.has_keepsake():
		state.catches_since_keepsake = 0
	else:
		state.catches_since_keepsake += 1


func to_save_dict() -> Dictionary:
	return state.to_save_dict()


func from_save_dict(data: Dictionary) -> void:
	state.from_save_dict(data)
