class_name EquipmentManager
extends RefCounted
## Ownership, equipped slots, appearance unlocks, and stat aggregation.
## Appearance unlocks are separate data from ownership (transmog-ready):
## once you've held an item its look is yours forever.

signal equipment_changed

const SLOTS := ["tool", "weapon", "head", "body", "back"]

var registries: Registries
var owned: Dictionary = {}            # item_id -> true
var equipped: Dictionary = {}         # slot -> item_id
var appearance_unlocked: Dictionary = {}  # item_id -> true


func _init(regs: Registries) -> void:
	registries = regs


func owns(item_id: String) -> bool:
	return owned.has(item_id)


func acquire(item_id: String) -> void:
	var def := registries.item(item_id)
	if def == null:
		push_warning("EquipmentManager: unknown item '%s'" % item_id)
		return
	owned[item_id] = true
	if def.appearance_unlock:
		appearance_unlocked[item_id] = true
	equipment_changed.emit()


func equip(item_id: String) -> bool:
	var def := registries.item(item_id)
	if def == null or def.slot == "" or not owns(item_id):
		return false
	equipped[def.slot] = item_id
	equipment_changed.emit()
	return true


func unequip(slot: String) -> void:
	if equipped.erase(slot):
		equipment_changed.emit()


func equipped_in(slot: String) -> Defs.ItemDefinition:
	return registries.item(equipped.get(slot, ""))


## Best owned tool of a type (highest tier) — used for auto-equip on interact.
func best_tool(tool_type: String) -> Defs.ItemDefinition:
	var best: Defs.ItemDefinition = null
	for item_id: String in owned:
		var def := registries.item(item_id)
		if def != null and def.tool_type == tool_type and def.category == "tool":
			if best == null or def.tier > best.tier:
				best = def
	return best


func stat_total(stat: String) -> float:
	var total := 0.0
	for slot: String in equipped:
		var def := registries.item(equipped[slot])
		if def != null:
			total += float(def.stats.get(stat, 0.0))
	return total


func tool_stat(tool_type: String, stat: String, fallback: float) -> float:
	var def := best_tool(tool_type)
	if def == null:
		return fallback
	return float(def.stats.get(stat, fallback))


func to_save_dict() -> Dictionary:
	return {
		"owned": owned.keys(),
		"equipped": equipped.duplicate(),
		"appearance": appearance_unlocked.keys(),
	}


func from_save_dict(data: Dictionary) -> void:
	owned.clear()
	equipped.clear()
	appearance_unlocked.clear()
	for item_id in data.get("owned", []):
		if registries.item(item_id) != null:
			owned[item_id] = true
		else:
			push_warning("EquipmentManager: dropping unknown owned item '%s' (definition removed?)" % item_id)
	for slot in data.get("equipped", {}):
		var item_id: String = data["equipped"][slot]
		if registries.item(item_id) != null:
			equipped[slot] = item_id
	for item_id in data.get("appearance", []):
		appearance_unlocked[item_id] = true
	equipment_changed.emit()
