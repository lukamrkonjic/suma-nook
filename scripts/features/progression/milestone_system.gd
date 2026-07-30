class_name MilestoneSystem
extends RefCounted
## One-time reward moments that replace level unlocks. Practice milestones
## fire on lifetime activity actions; journal milestones fire when a page's
## entries are complete. Grants happen exactly once; claimed ids persist.
## Recipes gate themselves via `unlock_milestone` on the recipe definition —
## the recipe side is the single source of truth for crafting availability,
## this system only decides when a milestone is reached.

signal milestone_reached(milestone_id: String, rewards: Array)

var registries: Registries
var stock: StockManager
var equipment: EquipmentManager
var collection: CollectionManager

var claimed: Dictionary = {}   # milestone_id -> true


func _init(
	regs: Registries,
	stock_manager: StockManager,
	equipment_manager: EquipmentManager,
	collection_manager: CollectionManager
) -> void:
	registries = regs
	stock = stock_manager
	equipment = equipment_manager
	collection = collection_manager


func is_claimed(milestone_id: String) -> bool:
	return claimed.has(milestone_id)


func is_recipe_unlocked(recipe: Defs.RecipeDefinition) -> bool:
	return recipe != null and (recipe.unlock_milestone == "" or is_claimed(recipe.unlock_milestone))


## Re-evaluates every unclaimed milestone against live state. Cheap: the
## milestone catalog is small and checks are dictionary lookups.
func check_all(activity_actions: Dictionary) -> void:
	for definition: Defs.MilestoneDefinition in registries.milestones.values():
		if claimed.has(definition.id) or not _is_met(definition, activity_actions):
			continue
		claimed[definition.id] = true
		_grant(definition)
		milestone_reached.emit(definition.id, definition.rewards.duplicate(true))


## Upcoming goals for one activity, nearest first — the journal panel's
## replacement for the old "next unlocks at level N" list.
func upcoming_for_activity(activity_id: String, actions_done: int, limit := 3) -> Array:
	var upcoming: Array = []
	for definition: Defs.MilestoneDefinition in registries.milestones.values():
		if (
			definition.kind == "practice"
			and definition.activity_id == activity_id
			and not claimed.has(definition.id)
		):
			upcoming.append({
				"milestone": definition,
				"remaining": maxi(0, definition.action_count - actions_done),
			})
	upcoming.sort_custom(func(a, b): return a["remaining"] < b["remaining"])
	return upcoming.slice(0, limit)


func _is_met(definition: Defs.MilestoneDefinition, activity_actions: Dictionary) -> bool:
	match definition.kind:
		"practice":
			return int(activity_actions.get(definition.activity_id, 0)) >= definition.action_count
		"journal_page":
			for entry_id: String in definition.entries:
				if not collection.is_discovered(definition.category, entry_id):
					return false
			return not definition.entries.is_empty()
	return false


## Mirrors the retired level-unlock grant rules: world pieces only when the
## catalog still ships them; gear acquisitions are idempotent.
func _grant(definition: Defs.MilestoneDefinition) -> void:
	for reward: Dictionary in definition.rewards:
		var reward_id := String(reward.get("id", ""))
		match String(reward.get("kind", "note")):
			"tile":
				if registries.tile(reward_id) != null and registries.is_tile_active(reward_id):
					stock.add_tile(reward_id)
					collection.record("tiles", reward_id, 0)
			"structure":
				if registries.structure(reward_id) != null:
					stock.add_structure(reward_id)
					collection.record("structures", reward_id, 0)
			"gear":
				if registries.item(reward_id) != null and not equipment.owns(reward_id):
					equipment.acquire(reward_id)
					collection.record("gear", reward_id)
			"note":
				pass


func to_save_dict() -> Dictionary:
	return {"claimed": claimed.keys()}


func from_save_dict(data: Dictionary) -> void:
	claimed.clear()
	for raw_id in data.get("claimed", []):
		var milestone_id := String(raw_id)
		if registries.milestone(milestone_id) != null:
			claimed[milestone_id] = true
