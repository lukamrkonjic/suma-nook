class_name InventoryManager
extends RefCounted
## Generous categorized storage. Everything stacks by item id; unique placed
## objects live in the WorldGrid, not here. Rewards can NEVER be lost: grants
## always succeed (no capacity limit in the MVP — the chest is a viewpoint,
## not a warehouse).

signal items_changed
signal item_gained(item_id: String, count: int, rare: bool)

var registries: Registries
var counts: Dictionary = {}          # item_id -> int


func _init(regs: Registries) -> void:
	registries = regs


func count(item_id: String) -> int:
	return int(counts.get(item_id, 0))


func grant(item_id: String, amount: int = 1, rare := false, silent := false) -> void:
	if amount <= 0:
		return
	if registries.item(item_id) == null:
		push_warning("InventoryManager: grant for unknown item '%s' stored anyway" % item_id)
	counts[item_id] = count(item_id) + amount
	if not silent:
		item_gained.emit(item_id, amount, rare)
	items_changed.emit()


func take(item_id: String, amount: int = 1) -> bool:
	if count(item_id) < amount:
		return false
	counts[item_id] -= amount
	if counts[item_id] <= 0:
		counts.erase(item_id)
	items_changed.emit()
	return true


func has_all(requirements: Dictionary) -> bool:
	for item_id: String in requirements:
		if count(item_id) < int(requirements[item_id]):
			return false
	return true


## Atomic multi-take: either everything is consumed or nothing is.
func take_all(requirements: Dictionary) -> bool:
	if not has_all(requirements):
		return false
	for item_id: String in requirements:
		take(item_id, int(requirements[item_id]))
	return true


func items_in_category(category: String) -> Array:
	var result: Array = []
	for item_id: String in counts:
		var def := registries.item(item_id)
		if def != null and def.category == category:
			result.append({"item": def, "count": counts[item_id]})
	result.sort_custom(func(a, b): return a["item"].display_name < b["item"].display_name)
	return result


func to_save_dict() -> Dictionary:
	return {"counts": counts.duplicate()}


func from_save_dict(data: Dictionary) -> void:
	counts.clear()
	var saved: Dictionary = data.get("counts", {})
	for item_id: String in saved:
		if registries.item(item_id) == null:
			push_warning("InventoryManager: dropping unknown saved item '%s'" % item_id)
			continue
		counts[item_id] = int(saved[item_id])
	items_changed.emit()
