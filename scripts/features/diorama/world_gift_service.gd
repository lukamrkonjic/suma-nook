class_name WorldGiftService
extends RefCounted
## Saved one-use powers. Expansion is reserved before generation and consumed
## only after the new Nook has committed.

signal inventory_changed
signal targeting_changed(gift_id: String)
signal expansion_requested(coord: Vector2i, seed_card: Dictionary)
signal gift_consumed(gift_id: String)

var registries: Registries
var nooks: NookModule
var counts: Dictionary = {}
var targeting_gift_id := ""
var pending_expansion: Dictionary = {}
var receipts: Dictionary = {}


func _init(content: Registries, nook_module: NookModule) -> void:
	registries = content
	nooks = nook_module


func count(gift_id: String) -> int:
	return int(counts.get(gift_id, 0))


func add(gift_id: String, amount := 1, receipt_id := "") -> bool:
	var definition = registries.world_gift(gift_id)
	if definition == null or amount <= 0:
		return false
	if receipt_id != "" and receipts.has(receipt_id):
		return false
	if receipt_id != "":
		receipts[receipt_id] = true
	counts[gift_id] = mini(definition.max_stack, count(gift_id) + amount)
	inventory_changed.emit()
	return true


func begin_targeting(gift_id: String) -> bool:
	if count(gift_id) <= 0 or not pending_expansion.is_empty():
		return false
	targeting_gift_id = gift_id
	targeting_changed.emit(gift_id)
	return true


func cancel_targeting() -> void:
	if targeting_gift_id == "":
		return
	targeting_gift_id = ""
	targeting_changed.emit("")


func is_targeting_expansion() -> bool:
	var definition = registries.world_gift(targeting_gift_id)
	return definition != null and definition.kind == "expand_nook"


func prepare_expansion(coord: Vector2i) -> Dictionary:
	if not pending_expansion.is_empty():
		return pending_expansion.duplicate(true)
	if not is_targeting_expansion() or nooks.world.has_nook(coord):
		return {}
	var reserved := nooks.offers.roll_direct(coord)
	if reserved.is_empty():
		return {}
	pending_expansion = {
		"gift_id": targeting_gift_id,
		"coord": [coord.x, coord.y],
		"seed_card": (reserved.get("card", {}) as Dictionary).duplicate(true),
	}
	targeting_gift_id = ""
	targeting_changed.emit("")
	expansion_requested.emit(coord, (pending_expansion["seed_card"] as Dictionary).duplicate(true))
	return pending_expansion.duplicate(true)


func finish_expansion(coord: Vector2i, succeeded: bool) -> bool:
	if pending_expansion.is_empty() or _pending_coord() != coord:
		return false
	var gift_id := String(pending_expansion.get("gift_id", ""))
	if not succeeded:
		pending_expansion.clear()
		inventory_changed.emit()
		return false
	if count(gift_id) <= 0:
		return false
	counts[gift_id] = count(gift_id) - 1
	if counts[gift_id] <= 0:
		counts.erase(gift_id)
	pending_expansion.clear()
	inventory_changed.emit()
	gift_consumed.emit(gift_id)
	return true


func recover_pending() -> void:
	if pending_expansion.is_empty():
		return
	var coord := _pending_coord()
	if nooks.world.has_nook(coord):
		finish_expansion(coord, true)
	else:
		expansion_requested.emit(
			coord,
			(pending_expansion.get("seed_card", {}) as Dictionary).duplicate(true)
		)


func to_save_dict() -> Dictionary:
	return {
		"counts": counts.duplicate(),
		"pending_expansion": pending_expansion.duplicate(true),
		"receipts": receipts.duplicate(true),
	}


func from_save_dict(data: Dictionary) -> void:
	counts.clear()
	for gift_id: String in data.get("counts", {}):
		var definition = registries.world_gift(gift_id)
		if definition != null:
			counts[gift_id] = clampi(
				int(data["counts"][gift_id]), 0, definition.max_stack
			)
	pending_expansion = (data.get("pending_expansion", {}) as Dictionary).duplicate(true)
	var pending_gift_id := String(pending_expansion.get("gift_id", ""))
	if (
		registries.world_gift(pending_gift_id) == null
		or count(pending_gift_id) <= 0
		or not pending_expansion.get("coord", []) is Array
		or (pending_expansion.get("coord", []) as Array).size() < 2
		or (pending_expansion.get("seed_card", {}) as Dictionary).is_empty()
	):
		pending_expansion.clear()
	receipts = (data.get("receipts", {}) as Dictionary).duplicate(true)
	targeting_gift_id = ""
	inventory_changed.emit()


func _pending_coord() -> Vector2i:
	var raw: Variant = pending_expansion.get("coord", [0, 0])
	return Vector2i(int(raw[0]), int(raw[1])) if raw is Array and raw.size() >= 2 else Vector2i.ZERO
