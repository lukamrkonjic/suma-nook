class_name TokenPouchService
extends RefCounted
## Shared wallet for biome tokens. Tokens are stored by InventoryManager, so
## grants and spends already participate in the normal save and dirty-state
## contracts. This service owns only the themed-box transaction boundary.

signal balance_changed(token_id: String, amount: int)
signal tokens_gained(token_id: String, amount: int, source: String)
signal box_opened(box_id: String, reward: Dictionary)

var registries: Registries
var inventory: InventoryManager
var rewards: BuildRewardService


func _init(
	content: Registries,
	player_inventory: InventoryManager,
	build_reward_service: BuildRewardService
) -> void:
	registries = content
	inventory = player_inventory
	rewards = build_reward_service
	var pouch_ref: WeakRef = weakref(self)
	inventory.items_changed.connect(func():
		var pouch := pouch_ref.get_ref() as TokenPouchService
		if pouch == null:
			return
		for token_id: String in pouch.token_ids():
			pouch.balance_changed.emit(token_id, pouch.balance(token_id))
	)


func token_ids() -> Array[String]:
	var result: Array[String] = []
	for item_id: String in registries.items:
		var definition := registries.item(item_id)
		if definition != null and definition.category == "token":
			result.append(item_id)
	result.sort()
	return result


func balance(token_id: String) -> int:
	return inventory.count(token_id) if _is_token(token_id) else 0


func grant(token_id: String, amount: int, source := "") -> Dictionary:
	if not _is_token(token_id) or amount <= 0:
		return {}
	inventory.grant(token_id, amount, false, true)
	var receipt := {
		"kind": "token",
		"id": token_id,
		"amount": amount,
		"source": source,
		"balance": balance(token_id),
	}
	tokens_gained.emit(token_id, amount, source)
	return receipt


func can_spend(token_id: String, amount: int) -> bool:
	return _is_token(token_id) and amount > 0 and balance(token_id) >= amount


func spend(token_id: String, amount: int) -> bool:
	if not can_spend(token_id, amount):
		return false
	return inventory.take(token_id, amount)


func can_open_box(box_id: String) -> bool:
	var box := registries.token_box(box_id)
	return box != null and can_spend(box.token_id, box.cost)


## Spending and granting happen synchronously. A failed or retired reward roll
## refunds its cost, so closing the game can never consume tokens without also
## putting the rolled piece in the Build Bag.
func open_box(box_id: String) -> Dictionary:
	var box := registries.token_box(box_id)
	if box == null or not spend(box.token_id, box.cost):
		return {}
	var reward := rewards.roll_and_grant(
		box.reward_pool_id,
		"token_box:%s" % box.id,
		box.roll_policy_id
	)
	if reward.is_empty():
		grant(box.token_id, box.cost, "box_refund:%s" % box.id)
		return {}
	reward["box_id"] = box.id
	reward["token_id"] = box.token_id
	reward["token_cost"] = box.cost
	reward["reveal_profile_id"] = box.reveal_profile_id
	box_opened.emit(box.id, reward.duplicate(true))
	return reward


func _is_token(token_id: String) -> bool:
	var definition := registries.item(token_id)
	return definition != null and definition.category == "token"
