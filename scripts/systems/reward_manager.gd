class_name RewardManager
extends RefCounted
## Hobby reward resolver. Ordinary actions yield XP/collection metadata and
## optional finished world pieces; they never yield common material stacks.

signal loot_granted(grants: Array)   # [{item_id, count, rare}]
signal hobby_result_resolved(result: HobbyActionResult)

var registries: Registries
var rng: RngService
var inventory: InventoryManager
var stock: StockManager
var collection: CollectionManager

func _init(
	regs: Registries,
	rng_service: RngService,
	inv: InventoryManager,
	stock_manager: StockManager = null,
	collection_manager: CollectionManager = null
) -> void:
	registries = regs
	rng = rng_service
	inventory = inv
	stock = stock_manager
	collection = collection_manager


func resolve_hobby_action(skill: Defs.SkillDefinition) -> HobbyActionResult:
	var result := HobbyActionResult.new()
	result.hobby_id = skill.id

	if collection != null and skill.collection_category != "" and not skill.collection_entries.is_empty():
		var discovery_chance := (
			registries.tunef("fishing_collection_chance", 0.45)
			if skill.id == "fishing"
			else 0.18
		)
		if rng.chance("hobby_collection_" + skill.id, discovery_chance):
			var index := rng.randi_range("hobby_collection_" + skill.id, 0, skill.collection_entries.size() - 1)
			result.collection_discovery_id = skill.collection_entries[index]
			result.was_new_discovery = collection.record(
				skill.collection_category,
				result.collection_discovery_id
			)

	var reward_chance := skill.direct_tile_reward_chance
	if reward_chance < 0.0:
		reward_chance = registries.tunef("default_direct_tile_reward_chance", 0.0)
	var active_reward_pool: Array[String] = []
	for tile_id: String in skill.direct_tile_reward_pool:
		if registries.is_tile_active(tile_id):
			active_reward_pool.append(tile_id)
	if (
		stock != null
		and reward_chance > 0.0
		and not active_reward_pool.is_empty()
		and rng.chance("hobby_world_reward_" + skill.id, reward_chance)
	):
		var index := rng.randi_range(
			"hobby_world_reward_" + skill.id,
			0,
			active_reward_pool.size() - 1
		)
		result.optional_tile_reward_id = active_reward_pool[index]
		result.reward_rarity = "rare"
		stock.add_tile(result.optional_tile_reward_id)

	hobby_result_resolved.emit(result)
	return result


func roll_table(table_id: String, stream := "loot_misc") -> Array:
	var grants: Array = []
	var table := registries.loot_table(table_id)
	if table != null and not table.entries.is_empty():
		var entry := rng.weighted(stream, table.entries)
		var count := rng.randi_range(stream, int(entry["min"]), int(entry["max"]))
		grants.append({"item_id": entry["item"], "count": count, "rare": bool(entry["rare"])})
	_apply(grants)
	return grants


func grant_fixed(requirements: Dictionary) -> Array:
	var grants: Array = []
	for item_id: String in requirements:
		grants.append({"item_id": item_id, "count": int(requirements[item_id]), "rare": false})
	_apply(grants)
	return grants


func _apply(grants: Array) -> void:
	for grant in grants:
		inventory.grant(grant["item_id"], grant["count"], bool(grant.get("rare", false)))
	if not grants.is_empty():
		loot_granted.emit(grants)
