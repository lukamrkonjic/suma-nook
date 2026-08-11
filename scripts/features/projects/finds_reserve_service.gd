class_name FindsReserveService
extends RefCounted
## A deliberately tiny rare-find reserve. Common Timber, Stone and Provisions
## never enter this service or the general inventory.

signal reserve_changed
signal find_added(find_id: String, amount: int)
signal find_spent(find_id: String, amount: int)

var registries: Registries
var _amounts: Dictionary = {}


func _init(content: Registries) -> void:
	registries = content


func amount(find_id: String) -> int:
	return maxi(0, int(_amounts.get(find_id, 0)))


func add(find_id: String, count := 1) -> bool:
	if registries.special_find(find_id) == null or count <= 0:
		return false
	_amounts[find_id] = amount(find_id) + count
	find_added.emit(find_id, count)
	reserve_changed.emit()
	return true


func spend(find_id: String, count := 1) -> bool:
	if count <= 0 or amount(find_id) < count:
		return false
	var remaining := amount(find_id) - count
	if remaining <= 0:
		_amounts.erase(find_id)
	else:
		_amounts[find_id] = remaining
	find_spent.emit(find_id, count)
	reserve_changed.emit()
	return true


func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = _amounts.keys()
	ids.sort()
	for find_id: String in ids:
		var definition = registries.special_find(find_id)
		if definition == null or amount(find_id) <= 0:
			continue
		result.append({
			"id": find_id,
			"name": definition.display_name,
			"amount": amount(find_id),
			"icon": definition.icon,
		})
	return result


func to_save_dict() -> Dictionary:
	return {"amounts": _amounts.duplicate()}


func from_save_dict(data: Dictionary) -> void:
	_amounts.clear()
	for raw_id: Variant in (data.get("amounts", {}) as Dictionary):
		var find_id := String(raw_id)
		var count := maxi(0, int(data["amounts"][raw_id]))
		if count > 0 and registries.special_find(find_id) != null:
			_amounts[find_id] = count
	reserve_changed.emit()
