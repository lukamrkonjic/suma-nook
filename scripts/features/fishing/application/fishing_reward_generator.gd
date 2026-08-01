class_name FishingRewardGenerator
extends RefCounted
## Pure reward generation: pool selection first, then candidates, then habitat
## and Spirit theme weights, then rarity with hidden protection, then the
## pick. Attention (manual vs automatic retrieval) never reaches this class.

var balance: FishingBalance
var catalog: LootCatalogPort
var composer: HaulComposer
var luck: HiddenLuckService
var rng: RngService

## Diagnostics for the simulation report and debug tools.
var empty_pool_fallbacks := 0
var safe_fallback_uses := 0
var last_warnings: PackedStringArray = []


func _init(
	balance_config: FishingBalance,
	loot_catalog: LootCatalogPort,
	haul_composer: HaulComposer,
	luck_service: HiddenLuckService,
	rng_service: RngService
) -> void:
	balance = balance_config
	catalog = loot_catalog
	composer = haul_composer
	luck = luck_service
	rng = rng_service


func generate_haul(context: FishingRollContext) -> FishingHaul:
	last_warnings.clear()
	var haul := FishingHaul.new()
	haul.dominant_theme = context.habitat.dominant_theme()
	if context.first_catch_pending:
		# The authored first catch teaches that water is a building material.
		var first := catalog.definition(balance.first_catch_loot_id())
		if first != null:
			haul.catch_size = FishingHaul.SIZE_SINGLE
			haul.entries.append(_reward_from(first))
			return haul
	haul.catch_size = composer.roll_catch_size()
	for form: String in composer.forms_for(haul.catch_size):
		var entry := _generate_entry(form, context)
		if entry != null:
			haul.entries.append(entry)
	if haul.entries.is_empty():
		# Never an empty catch: the safe fallback tile always exists.
		haul.entries.append(_reward_from(catalog.fallback_definition()))
		safe_fallback_uses += 1
	# The Keepsake is an independent bonus roll. It never replaces a normal
	# entry, and Spirits play no part in whether it appears.
	if rng.chance("fishing_keepsake", luck.keepsake_chance()):
		var bonus := _pick_keepsake(context)
		if bonus != null:
			haul.keepsake = bonus
	return haul


func _generate_entry(form: String, context: FishingRollContext) -> FishingReward:
	var pool := _roll_source_pool()
	var picked := _pick_candidate(form, pool, context)
	if picked == null and form == FishingReward.FORM_MODEL:
		# A missing model pool falls back to useful building volume.
		picked = _pick_candidate(FishingReward.FORM_TILE_BUNDLE, "global", context)
	if picked == null and form == FishingReward.FORM_TILE_BUNDLE:
		picked = _pick_candidate(FishingReward.FORM_MODEL, "global", context)
	if picked == null:
		picked = catalog.fallback_definition()
		safe_fallback_uses += 1
		_warn("all pools empty for form '%s'; using safe fallback" % form)
	return _reward_from(picked) if picked != null else null


func _pick_candidate(
	form: String,
	pool: String,
	context: FishingRollContext
) -> Defs.FishingLootDefinition:
	var pool_candidates := _valid_candidates(form, pool, context)
	if pool_candidates.is_empty() and pool != "global":
		empty_pool_fallbacks += 1
		_warn("pool '%s' had no '%s' candidates; falling back to global" % [pool, form])
		pool_candidates = _valid_candidates(form, "global", context)
	if pool_candidates.is_empty():
		return null
	var weighted: Array = []
	for candidate: Defs.FishingLootDefinition in pool_candidates:
		weighted.append({
			"definition": candidate,
			"weight": _candidate_weight(candidate, pool, context),
		})
	var choice := rng.weighted("fishing_loot", weighted)
	return choice.get("definition") as Defs.FishingLootDefinition


func _valid_candidates(
	form: String,
	pool: String,
	context: FishingRollContext
) -> Array:
	var result: Array = []
	for candidate: Defs.FishingLootDefinition in catalog.candidates(
		form, pool, context.unlock_groups
	):
		if candidate.unique and context.owned_keepsake_ids.has(
			candidate.building_definition_id
		):
			continue
		# The local pool is the built environment speaking: only content whose
		# themes are actually present around the edge belongs to it.
		if pool == "local" and _habitat_affinity(candidate, context) <= 0.0:
			continue
		result.append(candidate)
	return result


func _candidate_weight(
	candidate: Defs.FishingLootDefinition,
	pool: String,
	context: FishingRollContext
) -> float:
	var weight := maxf(0.001, candidate.base_weight)
	var affinity := _habitat_affinity(candidate, context)
	if affinity > 0.0:
		weight *= 1.0 + balance.habitat_theme_multiplier() * affinity
	if context.spirit_theme != "" and candidate.has_theme(context.spirit_theme):
		weight *= balance.spirit_theme_multiplier()
	if candidate.rarity == "rare":
		weight *= luck.rare_weight_multiplier()
	return weight


func _habitat_affinity(
	candidate: Defs.FishingLootDefinition,
	context: FishingRollContext
) -> float:
	var normalized := context.habitat.normalized()
	var affinity := 0.0
	for theme: String in candidate.theme_tags:
		affinity += float(normalized.get(theme, 0.0))
	return affinity


func _pick_keepsake(context: FishingRollContext) -> FishingReward:
	var pools: Array[String] = ["global", "wildcard", "local"]
	for pool: String in pools:
		var candidates := _valid_candidates(
			FishingReward.FORM_KEEPSAKE, pool, context
		)
		if candidates.is_empty():
			continue
		var weighted: Array = []
		for candidate: Defs.FishingLootDefinition in candidates:
			weighted.append({
				"definition": candidate,
				"weight": maxf(0.001, candidate.base_weight),
			})
		var choice := rng.weighted("fishing_keepsake_pick", weighted)
		return _reward_from(choice.get("definition") as Defs.FishingLootDefinition)
	return null


func _reward_from(definition: Defs.FishingLootDefinition) -> FishingReward:
	if definition == null:
		return null
	var quantity := 1
	if definition.reward_kind == FishingReward.FORM_TILE_BUNDLE:
		var bundle_range := Vector2i(definition.bundle_min, definition.bundle_max)
		if bundle_range.x <= 0 or bundle_range.y < bundle_range.x:
			bundle_range = balance.bundle_range(definition.rarity)
		quantity = rng.randi_range("fishing_bundle", bundle_range.x, bundle_range.y)
	return FishingReward.make(
		definition.reward_kind,
		definition.id,
		definition.building_definition_id,
		quantity,
		definition.rarity,
		definition.presentation_profile
	)


func _roll_source_pool() -> String:
	var entries: Array = []
	var weights := balance.source_pool_weights()
	for pool: String in weights:
		entries.append({"pool": pool, "weight": float(weights[pool])})
	var choice := rng.weighted("fishing_pool", entries)
	return String(choice.get("pool", "global"))


func _warn(message: String) -> void:
	last_warnings.append(message)
	if OS.is_debug_build():
		push_warning("Fishing: " + message)
