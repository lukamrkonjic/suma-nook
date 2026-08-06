class_name BuildRewardService
extends RefCounted
## One loss-resistant grant path for buildable world pieces. Features may roll
## now or pre-roll and persist the returned dictionary before granting later.

signal reward_granted(reward: Dictionary)

var registries: Registries
var rng: RngService
var stock: StockManager
var collection: CollectionManager


func _init(
	regs: Registries,
	rng_service: RngService,
	player_stock: StockManager,
	journal: CollectionManager
) -> void:
	registries = regs
	rng = rng_service
	stock = player_stock
	collection = journal


func roll(
	pool_id: String,
	stream_name: String,
	policy_id := "",
	history: Dictionary = {}
) -> Dictionary:
	var pool := registries.reward_pool(pool_id)
	if pool == null:
		return {}
	var candidates := _weighted_candidates(pool.entries, policy_id, history)
	var chosen := rng.weighted(stream_name, candidates)
	if chosen.is_empty():
		return {}
	var minimum := maxi(1, int(chosen.get("min", 1)))
	var maximum := maxi(minimum, int(chosen.get("max", minimum)))
	return {
		"pool_id": pool.id,
		"kind": String(chosen.get("kind", "")),
		"id": String(chosen.get("id", "")),
		"amount": rng.randi_range(stream_name + ":quantity", minimum, maximum),
		"rarity": String(chosen.get("rarity", "common")),
		"roll_policy_id": policy_id,
	}


func roll_and_grant(
	pool_id: String,
	stream_name: String,
	policy_id := "",
	history: Dictionary = {}
) -> Dictionary:
	return grant(roll(pool_id, stream_name, policy_id, history))


func _weighted_candidates(
	entries: Array[Dictionary],
	policy_id: String,
	history: Dictionary
) -> Array[Dictionary]:
	var policy := registries.reward_roll_policy(policy_id)
	var result: Array[Dictionary] = []
	var recent: Array = history.get("recent", [])
	var rare_misses := maxi(0, int(history.get("rare_misses", 0)))
	for source: Dictionary in entries:
		var candidate := source.duplicate(true)
		var weight := float(candidate.get("weight", 1.0))
		if policy != null:
			var kind := String(candidate.get("kind", ""))
			var content_id := String(candidate.get("id", ""))
			var category := "tiles" if kind == "tile" else "structures"
			var token := "%s:%s" % [kind, content_id]
			if not collection.is_discovered(category, content_id):
				weight *= policy.undiscovered_weight_multiplier
				candidate["novelty_boosted"] = true
			if recent.has(token):
				weight *= policy.recent_weight_multiplier
				candidate["recently_seen"] = true
			if (
				String(candidate.get("rarity", "common")) == "rare"
				and policy.rare_pity_start > 0
				and rare_misses >= policy.rare_pity_start
			):
				var pity_steps := rare_misses - policy.rare_pity_start + 1
				var pity_multiplier := minf(
					policy.rare_pity_max_multiplier,
					1.0 + float(pity_steps) * policy.rare_pity_step
				)
				weight *= pity_multiplier
				candidate["pity_multiplier"] = pity_multiplier
		candidate["weight"] = maxf(0.0001, weight)
		result.append(candidate)
	return result


func grant(pre_rolled: Dictionary) -> Dictionary:
	var reward := pre_rolled.duplicate(true)
	var kind := String(reward.get("kind", ""))
	var content_id := String(reward.get("id", ""))
	var amount := maxi(1, int(reward.get("amount", 1)))
	var was_new := false
	match kind:
		"tile":
			if registries.tile(content_id) == null:
				return {}
			stock.add_tile(content_id, amount)
			was_new = collection.record("tiles", content_id, amount)
		"structure":
			if registries.structure(content_id) == null:
				return {}
			stock.add_structure(content_id, amount)
			was_new = collection.record("structures", content_id, amount)
		_:
			return {}
	reward["amount"] = amount
	reward["was_new"] = was_new
	reward_granted.emit(reward.duplicate(true))
	return reward


func display_name(reward: Dictionary) -> String:
	var kind := String(reward.get("kind", ""))
	var content_id := String(reward.get("id", ""))
	if kind == "tile":
		var tile := registries.tile(content_id)
		return tile.display_name if tile != null else content_id
	if kind == "structure":
		var structure := registries.structure(content_id)
		return structure.display_name if structure != null else content_id
	return content_id
