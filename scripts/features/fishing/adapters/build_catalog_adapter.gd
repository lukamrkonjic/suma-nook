class_name BuildCatalogAdapter
extends LootCatalogPort
## Indexes the authored fishing loot once by (form, pool) so per-cast lookups
## never rescan or re-deserialize content. Definitions with missing building
## references are excluded with one loud development error each.

var registries: Registries
var balance: FishingBalance
var invalid_definition_count := 0

var _by_form_pool: Dictionary = {}   # "form|pool" -> Array[FishingLootDefinition]


func _init(regs: Registries, balance_config: FishingBalance) -> void:
	registries = regs
	balance = balance_config
	_build_index()


func candidates(
	form: String,
	pool: String,
	unlock_groups: Array[String]
) -> Array:
	var indexed: Array = _by_form_pool.get("%s|%s" % [form, pool], [])
	var result: Array = []
	for definition: Defs.FishingLootDefinition in indexed:
		if unlock_groups.has(definition.unlock_group):
			result.append(definition)
	return result


func fallback_definition() -> Defs.FishingLootDefinition:
	return registries.fishing_loot_definition(balance.fallback_loot_id())


func definition(loot_id: String) -> Defs.FishingLootDefinition:
	return registries.fishing_loot_definition(loot_id)


func _build_index() -> void:
	_by_form_pool.clear()
	invalid_definition_count = 0
	for loot: Defs.FishingLootDefinition in registries.fishing_loot.values():
		if not _building_reference_valid(loot):
			invalid_definition_count += 1
			push_error(
				"Fishing: loot '%s' references missing %s '%s' and is excluded"
				% [loot.id, loot.reward_kind, loot.building_definition_id]
			)
			continue
		for pool: String in loot.pool_tags:
			var key := "%s|%s" % [loot.reward_kind, pool]
			if not _by_form_pool.has(key):
				_by_form_pool[key] = []
			(_by_form_pool[key] as Array).append(loot)


func _building_reference_valid(loot: Defs.FishingLootDefinition) -> bool:
	match loot.reward_kind:
		FishingReward.FORM_TILE_BUNDLE:
			return registries.tile(loot.building_definition_id) != null
		FishingReward.FORM_MODEL:
			return registries.structure(loot.building_definition_id) != null
		FishingReward.FORM_KEEPSAKE:
			return registries.keepsake(loot.building_definition_id) != null
	return false
