extends Node
class_name EconomyManager

signal tokens_changed(token_id: StringName, amount: int)
signal recycle_progress_changed(progress: int, target: int)
signal coin_created(token_id: StringName)

var data: GameData
var token_counts: Dictionary = {}
var recycle_progress := 0
var recycle_target := 5


func setup(game_data: GameData) -> void:
	data = game_data
	recycle_target = maxi(2, int(data.tuning.get("recycle_seed_cost", 5)))
	for token_id: StringName in data.tokens:
		token_counts[token_id] = 0


func amount(token_id: StringName) -> int:
	return int(token_counts.get(token_id, 0))


func add(token_id: StringName, quantity: int = 1) -> bool:
	if data.token(token_id) == null or quantity <= 0:
		return false
	token_counts[token_id] = amount(token_id) + quantity
	tokens_changed.emit(token_id, amount(token_id))
	return true


func spend(token_id: StringName, quantity: int = 1) -> bool:
	if quantity <= 0 or amount(token_id) < quantity:
		return false
	token_counts[token_id] = amount(token_id) - quantity
	tokens_changed.emit(token_id, amount(token_id))
	return true


func recycle(value: int, preferred_token: StringName = &"meadow_coin") -> int:
	recycle_progress += maxi(0, value)
	var created := 0
	while recycle_progress >= recycle_target:
		recycle_progress -= recycle_target
		add(preferred_token, 1)
		coin_created.emit(preferred_token)
		created += 1
	recycle_progress_changed.emit(recycle_progress, recycle_target)
	return created


func sell(value: int, preferred_token: StringName = &"meadow_coin") -> int:
	return recycle(value, preferred_token)


func snapshot() -> Dictionary:
	var serialized: Dictionary = {}
	for token_id: StringName in token_counts:
		serialized[String(token_id)] = int(token_counts[token_id])
	return {"tokens": serialized, "recycle_progress": recycle_progress}


func restore_snapshot(state: Dictionary) -> void:
	for token_id: StringName in data.tokens:
		token_counts[token_id] = maxi(0, int((state.get("tokens", {}) as Dictionary).get(String(token_id), 0)))
		tokens_changed.emit(token_id, amount(token_id))
	recycle_progress = clampi(int(state.get("recycle_progress", 0)), 0, recycle_target - 1)
	recycle_progress_changed.emit(recycle_progress, recycle_target)
