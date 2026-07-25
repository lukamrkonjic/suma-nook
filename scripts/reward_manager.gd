extends Node
class_name RewardManager

signal reward_drawn(definition_id: StringName, token_id: StringName)

var data: GameData
var rng := RandomNumberGenerator.new()
var offers_made := 0
var offers_by_pool: Dictionary = {}
var rewards_since_ground := 0
var probability_modifiers: Array[Callable] = []
var prevention_hooks: Array[Callable] = []


func setup(game_data: GameData, world_seed: int = 730291) -> void:
	data = game_data
	rng.seed = world_seed


func draw(token_id: StringName, context: Dictionary = {}) -> StringName:
	var token := data.token(token_id)
	if token == null:
		return &""
	var pool := token.reward_pool
	var sequences: Dictionary = data.beginner.get("sequence_by_pool", {})
	var beginner_sequence: Array = sequences.get(String(pool), [])
	var pool_offers := int(offers_by_pool.get(String(pool), 0))
	var chosen := &""
	if pool_offers < beginner_sequence.size():
		chosen = StringName(str(beginner_sequence[pool_offers]))
	else:
		var pity_after := maxi(1, int(data.beginner.get("expansion_pity_after", 7)))
		if rewards_since_ground >= pity_after:
			var expansions: Array = data.beginner.get("expansion_ids", [])
			var matching_expansions: Array[StringName] = []
			for raw_id: Variant in expansions:
				var expansion_id := StringName(str(raw_id))
				var expansion := data.item(expansion_id)
				if expansion != null and String(pool) in expansion.reward_pools:
					matching_expansions.append(expansion_id)
			if not matching_expansions.is_empty():
				chosen = matching_expansions[rng.randi_range(0, matching_expansions.size() - 1)]
		if chosen == &"":
			chosen = _weighted_draw(pool, context)
			if chosen == &"":
				# A garden full of suppressors must never deadlock the economy.
				chosen = _weighted_draw(pool, {})
	offers_made += 1
	offers_by_pool[String(pool)] = pool_offers + 1
	var definition := data.item(chosen)
	if definition != null and definition.is_ground():
		rewards_since_ground = 0
	else:
		rewards_since_ground += 1
	reward_drawn.emit(chosen, token_id)
	return chosen


func _weighted_draw(pool: StringName, context: Dictionary) -> StringName:
	var rows: Array[Dictionary] = []
	var total := 0.0
	for raw_id: String in data.item_ids_for_pool(pool):
		var id := StringName(raw_id)
		var definition := data.item(id)
		var prevented := false
		for hook: Callable in prevention_hooks:
			if bool(hook.call(definition, context)):
				prevented = true
				break
		if prevented:
			continue
		var weight := definition.reward_weight
		for hook: Callable in probability_modifiers:
			weight = maxf(0.0, float(hook.call(definition, weight, context)))
		weight = _apply_placed_modifiers(definition, weight, context)
		if weight > 0.0:
			rows.append({"id": id, "weight": weight})
			total += weight
	if rows.is_empty() or total <= 0.0:
		return &""
	var roll := rng.randf() * total
	for row: Dictionary in rows:
		roll -= float(row.weight)
		if roll <= 0.0:
			return row.id
	return rows.back().id


func _apply_placed_modifiers(
		definition: BuildItemDefinition,
		weight: float,
		context: Dictionary
	) -> float:
	var counts: Dictionary = context.get("placed_definition_counts", {})
	var adjusted := weight
	for raw_id: Variant in counts:
		var modifier := data.item(StringName(str(raw_id)))
		if modifier == null or modifier.modifier_kind == &"":
			continue
		var tag_matches := (
			definition.category == modifier.modifier_tag
			or String(modifier.modifier_tag) in definition.tags
		)
		if not tag_matches:
			continue
		var count := maxi(0, int(counts[raw_id]))
		if modifier.modifier_kind == &"block" and count > 0:
			return 0.0
		if modifier.modifier_kind == &"boost":
			adjusted *= pow(modifier.modifier_strength, count)
	return adjusted


func modifier_summary(context: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	var counts: Dictionary = context.get("placed_definition_counts", {})
	for raw_id: Variant in counts:
		var definition := data.item(StringName(str(raw_id)))
		if definition == null or definition.modifier_kind == &"":
			continue
		var count := maxi(0, int(counts[raw_id]))
		if count <= 0:
			continue
		if definition.modifier_kind == &"boost":
			result.append("%s ×%.1f" % [String(definition.modifier_tag).capitalize(), pow(definition.modifier_strength, count)])
		else:
			result.append("No %s" % String(definition.modifier_tag).capitalize())
	return result


func snapshot() -> Dictionary:
	return {
		"offers_made": offers_made,
		"offers_by_pool": offers_by_pool.duplicate(true),
		"rewards_since_ground": rewards_since_ground,
		"rng_state": rng.state,
	}


func restore_snapshot(state: Dictionary) -> void:
	offers_made = maxi(0, int(state.get("offers_made", 0)))
	offers_by_pool = (state.get("offers_by_pool", {}) as Dictionary).duplicate(true)
	rewards_since_ground = maxi(0, int(state.get("rewards_since_ground", 0)))
	if state.has("rng_state"):
		rng.state = int(state.rng_state)
