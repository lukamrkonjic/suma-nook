class_name DiscoverySystem
extends RefCounted
## Periodic sky wishes. An offer is three broad collections; the player chooses
## what kind of thing to wish for, then the sky resolves one physical piece
## from that category. Only that copy enters stock and the world.

signal discovery_ready(entry: Dictionary)
signal wish_ready(choices: Array[Dictionary])
signal wish_changed

const KIND_TILE := "tile"
const KIND_STRUCTURE := "structure"
const WISH_CHOICE_COUNT := 3

var registries: Registries
var rng: RngService
var grid: WorldGrid
var stock: StockManager
var collection: CollectionManager

var pending: Array[Dictionary] = []
var wish_choices: Array[Dictionary] = []
var seconds_until_wish := -1.0
var wishes_completed := 0


func _init(
	regs: Registries,
	rng_service: RngService,
	world_grid: WorldGrid,
	player_stock: StockManager,
	journal: CollectionManager
) -> void:
	registries = regs
	rng = rng_service
	grid = world_grid
	stock = player_stock
	collection = journal
	_schedule_next_wish(true)


func tick(delta: float) -> void:
	if has_pending() or has_wish_offer():
		return
	seconds_until_wish = maxf(0.0, seconds_until_wish - delta)
	if seconds_until_wish <= 0.0:
		prepare_wish_offer()


func has_wish_offer() -> bool:
	return not wish_choices.is_empty()


func current_wish_choices() -> Array[Dictionary]:
	return wish_choices.duplicate(true)


## Rolls categories without replacement. Exact pieces remain a surprise until
## the player commits to the kind of collection they want.
func prepare_wish_offer(force := false) -> Array[Dictionary]:
	if has_wish_offer() or (has_pending() and not force):
		return current_wish_choices()
	var pool := _delivery_pool()
	if pool == null:
		return []
	var available: Array = pool.wish_categories.filter(
		func(category: Dictionary) -> bool:
			var category_id := String(category.get("id", ""))
			return pool.rewards.any(func(reward: Dictionary) -> bool:
				return String(reward.get("category", "")) == category_id
			)
	).duplicate(true)
	var offer: Array[Dictionary] = []
	for choice_index in mini(WISH_CHOICE_COUNT, available.size()):
		var category: Dictionary = rng.weighted(
			"wish_offer:%d:%d" % [wishes_completed, choice_index],
			available
		)
		if category.is_empty():
			break
		offer.append(_wish_entry(category, pool.id))
		available.erase(category)
	wish_choices = offer
	if not wish_choices.is_empty():
		seconds_until_wish = 0.0
		wish_ready.emit(current_wish_choices())
		wish_changed.emit()
	return current_wish_choices()


func choose_wish(index: int) -> Dictionary:
	if index < 0 or index >= wish_choices.size():
		return {}
	var choice := wish_choices[index].duplicate(true)
	wish_choices.clear()
	wishes_completed += 1
	_schedule_next_wish(false)
	var granted := _roll_category_and_grant(choice)
	wish_changed.emit()
	return granted


## Compatibility entry point for retired ferry saves and debug tools.
func discover_delivery() -> Dictionary:
	var pool := _delivery_pool()
	return _roll_and_grant(pool, "delivery") if pool != null else {}


func has_pending() -> bool:
	return not pending.is_empty()


func peek_pending() -> Dictionary:
	return pending[0].duplicate(true) if not pending.is_empty() else {}


func acknowledge_next() -> Dictionary:
	return pending.pop_front() if not pending.is_empty() else {}


func _delivery_pool() -> Defs.DiscoveryPoolDefinition:
	for pool: Defs.DiscoveryPoolDefinition in registries.discovery_pools.values():
		if pool.source == "void":
			return pool
	return null


func _schedule_next_wish(first: bool) -> void:
	var prefix := "first" if first else "later"
	var fallback_min := 18.0 if first else 120.0
	var fallback_max := 28.0 if first else 180.0
	var minimum := registries.tunef(
		"wish_%s_min_seconds" % prefix,
		fallback_min
	)
	var maximum := registries.tunef(
		"wish_%s_max_seconds" % prefix,
		fallback_max
	)
	seconds_until_wish = rng.randf_range(
		"wish_schedule",
		minimum,
		maxf(minimum, maximum)
	)


func _roll_and_grant(
	pool: Defs.DiscoveryPoolDefinition,
	source: String
) -> Dictionary:
	var choice := rng.weighted("discovery:%s" % pool.id, pool.rewards)
	if choice.is_empty():
		return {}
	return _grant({
		"kind": String(choice.get("kind", "")),
		"id": String(choice.get("id", "")),
		"pool_id": pool.id,
		"source": source,
	})


func _roll_category_and_grant(category_choice: Dictionary) -> Dictionary:
	var pool := registries.discovery_pool(String(category_choice.get("pool_id", "")))
	if pool == null:
		pool = _delivery_pool()
	if pool == null:
		return {}
	var category_id := String(category_choice.get("category", ""))
	var category_rewards: Array[Dictionary] = []
	for reward: Dictionary in pool.rewards:
		if String(reward.get("category", "")) == category_id:
			category_rewards.append(reward)
	var reward := rng.weighted(
		"wish_reward:%d:%s" % [wishes_completed, category_id],
		category_rewards
	)
	if reward.is_empty():
		return {}
	return _grant({
		"kind": String(reward.get("kind", "")),
		"id": String(reward.get("id", "")),
		"category": category_id,
		"category_name": String(category_choice.get("name", category_id.capitalize())),
		"pool_id": pool.id,
		"source": "wish",
	})


func _grant(raw_entry: Dictionary) -> Dictionary:
	var entry := raw_entry.duplicate(true)
	var kind := String(entry.get("kind", ""))
	var content_id := String(entry.get("id", ""))
	var was_new := false
	match kind:
		KIND_TILE:
			if registries.tile(content_id) == null:
				return {}
			stock.add_tile(content_id)
			was_new = collection.record("tiles", content_id)
		KIND_STRUCTURE:
			if registries.structure(content_id) == null:
				return {}
			stock.add_structure(content_id)
			was_new = collection.record("structures", content_id)
		_:
			return {}
	entry["was_new"] = was_new
	pending.append(entry)
	discovery_ready.emit(entry.duplicate(true))
	return entry


func to_save_dict() -> Dictionary:
	return {
		"pending": pending.duplicate(true),
		"wish_choices": wish_choices.duplicate(true),
		"seconds_until_wish": seconds_until_wish,
		"wishes_completed": wishes_completed,
	}


func from_save_dict(data: Dictionary) -> void:
	pending.clear()
	for raw_entry in data.get("pending", []):
		if not raw_entry is Dictionary:
			continue
		var kind := String(raw_entry.get("kind", ""))
		var content_id := String(raw_entry.get("id", ""))
		if _valid_content(kind, content_id):
			pending.append(raw_entry.duplicate(true))
	wish_choices.clear()
	for raw_choice in data.get("wish_choices", []):
		if not raw_choice is Dictionary:
			continue
		var category_id := String(raw_choice.get("category", ""))
		if _valid_category(category_id):
			wish_choices.append(raw_choice.duplicate(true))
			continue
		# Old exact-item wish saves are migrated to their authored collection.
		var kind := String(raw_choice.get("kind", ""))
		var content_id := String(raw_choice.get("id", ""))
		var migrated := _category_for_reward(kind, content_id)
		if not migrated.is_empty():
			wish_choices.append(migrated)
	seconds_until_wish = maxf(
		0.0,
		float(data.get("seconds_until_wish", seconds_until_wish))
	)
	wishes_completed = maxi(0, int(data.get("wishes_completed", 0)))


func _valid_content(kind: String, content_id: String) -> bool:
	return (
		(kind == KIND_TILE and registries.tile(content_id) != null)
		or (kind == KIND_STRUCTURE and registries.structure(content_id) != null)
	)


func _valid_category(category_id: String) -> bool:
	var pool := _delivery_pool()
	if pool == null:
		return false
	return pool.wish_categories.any(func(category: Dictionary) -> bool:
		return String(category.get("id", "")) == category_id
	)


func _category_for_reward(kind: String, content_id: String) -> Dictionary:
	var pool := _delivery_pool()
	if pool == null or not _valid_content(kind, content_id):
		return {}
	var category_id := ""
	for reward: Dictionary in pool.rewards:
		if (
			String(reward.get("kind", "")) == kind
			and String(reward.get("id", "")) == content_id
		):
			category_id = String(reward.get("category", ""))
			break
	for category: Dictionary in pool.wish_categories:
		if String(category.get("id", "")) != category_id:
			continue
		return _wish_entry(category, pool.id)
	return {}


func _wish_entry(category: Dictionary, pool_id: String) -> Dictionary:
	var category_id := String(category.get("id", ""))
	var presentation := BuildCategoryResolver.category(category_id)
	return {
		"category": category_id,
		"name": String(presentation.get(
			"label", category.get("name", category_id.capitalize())
		)),
		"description": String(presentation.get(
			"wish_description", category.get("description", "")
		)),
		"icon": String(category.get(
			"icon", BuildCategoryResolver.icon_path(category_id)
		)),
		"pool_id": pool_id,
		"source": "wish",
	}
