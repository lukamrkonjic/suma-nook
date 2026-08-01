class_name FishingBalance
extends RefCounted
## Typed façade over data/fishing_balance.json. Every probability, timing, and
## habitat mapping the fishing system uses flows through here — application
## code never hardcodes a tunable.

var _data: Dictionary = {}


func _init(raw: Dictionary = {}) -> void:
	_data = raw.duplicate(true)


func section(key: String) -> Dictionary:
	var raw: Variant = _data.get(key, {})
	return raw if raw is Dictionary else {}


func timing(key: String, fallback: float) -> float:
	return float(section("timing").get(key, fallback))


func source_pool_weights() -> Dictionary:
	var weights := section("source_pools")
	if weights.is_empty():
		weights = {"local": 0.6, "global": 0.3, "wildcard": 0.1}
	return weights


func haul_size_weights() -> Dictionary:
	var weights := section("haul_sizes")
	if weights.is_empty():
		weights = {"single": 0.8, "rich": 0.17, "bountiful": 0.03}
	return weights


func single_form_weights() -> Dictionary:
	var weights := section("single_form_weights")
	if weights.is_empty():
		weights = {"tile_bundle": 0.7, "model": 0.3}
	return weights


func rich_second_form_weights() -> Dictionary:
	var weights := section("rich_second_form_weights")
	if weights.is_empty():
		weights = single_form_weights()
	return weights


## [min, max] copies for a bundle of the given rarity when the loot definition
## does not author its own range.
func bundle_range(rarity: String) -> Vector2i:
	var ranges := section("bundle_ranges")
	var raw: Variant = ranges.get(rarity, [1, 1])
	if raw is Array and raw.size() >= 2:
		return Vector2i(maxi(1, int(raw[0])), maxi(1, int(raw[1])))
	return Vector2i.ONE


func keepsake_base_chance() -> float:
	return float(section("keepsake").get("base_chance", 0.04))


func keepsake_pity_start() -> int:
	return int(section("keepsake").get("pity_start", 20))


func keepsake_pity_bonus() -> float:
	return float(section("keepsake").get("pity_bonus_per_catch", 0.02))


func rare_pity_start() -> int:
	return int(section("rare_luck").get("pity_start", 10))


func rare_pity_bonus() -> float:
	return float(section("rare_luck").get("weight_bonus_per_catch", 0.35))


func spirit_theme_multiplier() -> float:
	return float(_data.get("spirit_theme_multiplier", 6.0))


func habitat_theme_multiplier() -> float:
	return float(_data.get("habitat_theme_multiplier", 2.5))


func pouch_capacity() -> int:
	return int(_data.get("pouch_capacity", 5))


func basket_capacity() -> int:
	return int(_data.get("basket_capacity", 3))


func unlock_groups() -> Array[String]:
	var groups: Array[String] = []
	for raw in _data.get("unlock_groups", ["core"]):
		groups.append(String(raw))
	if groups.is_empty():
		groups.append("core")
	return groups


func first_catch_loot_id() -> String:
	return String(_data.get("first_catch_loot_id", ""))


func fallback_loot_id() -> String:
	return String(_data.get("fallback_loot_id", ""))


func habitat_config() -> Dictionary:
	return section("habitat")
