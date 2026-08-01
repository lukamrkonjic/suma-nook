class_name LootCatalogPort
extends RefCounted
## Narrow contract for reward candidates. Implementations index the authored
## loot content; the generator only ever asks for filtered candidate lists.


## Valid candidates of one reward form in one source pool, filtered to the
## given unlock groups. Returns Array[Defs.FishingLootDefinition].
func candidates(
	_form: String,
	_pool: String,
	_unlock_groups: Array[String]
) -> Array:
	return []


## The known-safe tile bundle used when every pool is somehow empty.
func fallback_definition() -> Defs.FishingLootDefinition:
	return null


func definition(_loot_id: String) -> Defs.FishingLootDefinition:
	return null
