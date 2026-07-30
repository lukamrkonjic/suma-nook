class_name CraftingManager
extends RefCounted
## Converts materials into creative possibilities. Recipes unlock
## deterministically from milestones (never from rare drops), transactions
## are atomic, and outputs route to the right home: structures → stock,
## items → inventory, tools → inventory + equipment ownership.

signal crafted(recipe_id: String, output_id: String)

var registries: Registries
var inventory: InventoryManager
var stock: StockManager
var progression: ProgressionModule
var equipment: EquipmentManager
var collection: CollectionManager


func _init(regs: Registries, inv: InventoryManager, stock_mgr: StockManager, progression_module: ProgressionModule, equip: EquipmentManager, coll: CollectionManager) -> void:
	registries = regs
	inventory = inv
	stock = stock_mgr
	progression = progression_module
	equipment = equip
	collection = coll


func available_recipes() -> Array:
	var result: Array = []
	if not registries.feature("material_crafting_enabled", false):
		return result
	for recipe: Defs.RecipeDefinition in registries.recipes.values():
		if progression.is_recipe_unlocked(recipe):
			result.append(recipe)
	result.sort_custom(func(a, b): return a.category + a.display_name < b.category + b.display_name)
	return result


func can_craft(recipe_id: String) -> bool:
	if not registries.feature("material_crafting_enabled", false):
		return false
	var recipe := registries.recipe(recipe_id)
	return recipe != null and progression.is_recipe_unlocked(recipe) and inventory.has_all(recipe.inputs)


func craft(recipe_id: String, batches := 1) -> bool:
	if not registries.feature("material_crafting_enabled", false):
		return false
	var recipe := registries.recipe(recipe_id)
	if recipe == null or not progression.is_recipe_unlocked(recipe):
		return false
	batches = maxi(1, batches if recipe.batchable else 1)
	for batch in batches:
		if not inventory.take_all(recipe.inputs):
			return batch > 0
		_deliver(recipe)
		crafted.emit(recipe.id, recipe.output_id)
	return true


func _deliver(recipe: Defs.RecipeDefinition) -> void:
	match recipe.output_kind:
		"structure":
			stock.add_structure(recipe.output_id, recipe.output_count)
			collection.record("structures", recipe.output_id, recipe.output_count)
		"parcel", "item":
			inventory.grant(recipe.output_id, recipe.output_count)
			var def := registries.item(recipe.output_id)
			if def != null and (def.category == "tool" or def.category == "equipment"):
				equipment.acquire(recipe.output_id)
				collection.record("gear", recipe.output_id)
		_:
			inventory.grant(recipe.output_id, recipe.output_count)
