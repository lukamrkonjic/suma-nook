class_name WorldheartService
extends RefCounted
## Saved, deterministic source and exchange sink for buildable pieces. Rewards
## are rolled before their arrival animation and remain in the reserve until
## the player explicitly collects them.

signal state_changed
signal pulse_queued(entry: Dictionary)
signal rewards_claimed(entries: Array[Dictionary])
signal exchange_completed(offered: Dictionary, reward: Dictionary)
signal exchange_rejected(message: String)
signal attunement_changed(collection_id: String)
signal contribution_changed(
	collection_id: String,
	progress: int,
	required: int,
	completed: bool,
	reward: Dictionary
)
signal worldheart_moved(from: Vector2i, to: Vector2i)
signal worldheart_rotated(rotation_quarters: int)
signal vibe_changed(collection_id: String)

const SAVE_VERSION := 3

var registries: Registries
var rng: RngService
var grid: WorldGrid
var stock: StockManager
var journal: CollectionManager
var build_rewards: BuildRewardService
var collections: CreativeCollectionService

var reward_queue: Array[Dictionary] = []
var next_pulse_seconds := 0.0
var pulse_sequence := 0
var entry_sequence := 0
var recent_tokens: Array[String] = []
var attuned_collection_id := ""
var vibe_collection_id := ""
var worldheart_cell := Vector2i.ZERO
var worldheart_rotation_quarters := 0
var contributions: Dictionary = {}
var active_contribution_collection_id := ""
var pending_exchange: Dictionary = {}
var _generation_pause_sources: Dictionary = {}


func _init(
	content: Registries,
	rng_service: RngService,
	world_grid: WorldGrid,
	player_stock: StockManager,
	collection_journal: CollectionManager,
	reward_service: BuildRewardService,
	creative_collections: CreativeCollectionService
) -> void:
	registries = content
	rng = rng_service
	grid = world_grid
	stock = player_stock
	journal = collection_journal
	build_rewards = reward_service
	collections = creative_collections


func new_game() -> void:
	_generation_pause_sources.clear()
	reward_queue.clear()
	recent_tokens.clear()
	pulse_sequence = 0
	entry_sequence = 0
	attuned_collection_id = ""
	vibe_collection_id = ""
	worldheart_cell = Vector2i.ZERO
	worldheart_rotation_quarters = 0
	contributions.clear()
	active_contribution_collection_id = ""
	pending_exchange.clear()
	next_pulse_seconds = maxf(0.1, float(_config().get("first_pulse_delay", 2.5)))
	state_changed.emit()


func tick(delta: float) -> void:
	if (
		delta <= 0.0
		or generation_paused()
		or reward_queue.size() >= reserve_cap()
	):
		return
	next_pulse_seconds -= delta
	if next_pulse_seconds > 0.0:
		return
	var reward := _roll_pulse_reward()
	_schedule_next_pulse()
	if not reward.is_empty():
		_enqueue(reward, "worldheart")
	state_changed.emit()


## Presentation pauses are transient and deliberately excluded from saves.
## Using named sources keeps a future modal or cutscene from accidentally
## resuming generation while a move preview still owns its pause.
func set_generation_paused(source: StringName, paused: bool) -> void:
	if source == &"":
		return
	if paused:
		_generation_pause_sources[source] = true
	else:
		_generation_pause_sources.erase(source)


func generation_paused() -> bool:
	return not _generation_pause_sources.is_empty()


func visible_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in mini(visible_cap(), reward_queue.size()):
		result.append(reward_queue[index].duplicate(true))
	return result


func queued_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in reward_queue:
		result.append(entry.duplicate(true))
	return result


func visible_cap() -> int:
	return maxi(1, int(_config().get("visible_reward_cap", 4)))


func reserve_cap() -> int:
	return maxi(visible_cap(), int(_config().get("reserve_cap", 12)))


func claim(entry_id: String) -> Dictionary:
	for index in reward_queue.size():
		if String(reward_queue[index].get("entry_id", "")) != entry_id:
			continue
		var entry := reward_queue[index].duplicate(true)
		var granted := build_rewards.grant(entry)
		if granted.is_empty():
			return {}
		reward_queue.remove_at(index)
		_ensure_visible_reward_landings()
		rewards_claimed.emit([granted.duplicate(true)])
		state_changed.emit()
		return granted
	return {}


func claim_all_visible() -> Array[Dictionary]:
	var claimed: Array[Dictionary] = []
	for entry: Dictionary in visible_entries():
		var granted := build_rewards.grant(entry)
		if not granted.is_empty():
			claimed.append(granted)
			for index in reward_queue.size():
				if (
					String(reward_queue[index].get("entry_id", ""))
					== String(entry.get("entry_id", ""))
				):
					reward_queue.remove_at(index)
					break
	if not claimed.is_empty():
		_ensure_visible_reward_landings()
		rewards_claimed.emit(claimed.duplicate(true))
		state_changed.emit()
	return claimed


func enqueue_external_reward(reward: Dictionary, source := "visitor") -> bool:
	if reward_queue.size() >= reserve_cap() or not _valid_reward(reward):
		return false
	_enqueue(reward, source)
	state_changed.emit()
	return true


func can_offer(kind: String, content_id: String) -> bool:
	if collections.membership(kind, content_id).is_empty():
		return false
	if kind == "tile":
		return stock.tile_count(content_id) > 0 and _owned_total(kind, content_id) > 1
	if kind == "structure":
		return (
			not stock.is_unlimited_structure(content_id)
			and stock.structure_count(content_id) > 0
			and _owned_total(kind, content_id) > 1
		)
	return false


func contribution_required() -> int:
	return maxi(2, int(_config().get("contributions_required", 2)))


func contribution_progress(collection_id: String) -> int:
	return clampi(int(contributions.get(collection_id, 0)), 0, contribution_required())


func contribute_from_stock(kind: String, content_id: String) -> Dictionary:
	if not can_offer(kind, content_id):
		_reject("Keep one copy in your world or Build Bag before offering a spare.")
		return {"accepted": false}
	var membership := collections.membership(kind, content_id)
	var collection_id := String(membership.get("collection_id", ""))
	var required := contribution_required()
	var next_progress := contribution_progress(collection_id) + 1
	var reward: Dictionary = {}
	if next_progress >= required:
		reward = _roll_exchange_reward(collection_id, kind, content_id)
		if reward.is_empty():
			_reject("The Worldheart cannot find another unlocked piece in that set yet.")
			return {"accepted": false}
	pending_exchange = {
		"offered": {"kind": kind, "id": content_id, "amount": 1},
		"reward": reward.duplicate(true),
		"collection_id": collection_id,
		"previous_progress": contribution_progress(collection_id),
	}
	var structure_token: Dictionary = {}
	var removed := false
	if kind == "tile":
		removed = stock.take_tile(content_id)
	else:
		structure_token = stock.take_structure_token(content_id)
		removed = not structure_token.is_empty()
	if not removed:
		pending_exchange.clear()
		_reject("That spare is no longer in the Build Bag.")
		return {"accepted": false}
	var granted: Dictionary = {}
	if next_progress >= required:
		granted = build_rewards.grant(reward)
	if next_progress >= required and granted.is_empty():
		if kind == "tile":
			stock.add_tile(content_id)
		else:
			stock.return_structure_token(structure_token)
		pending_exchange.clear()
		_reject("The ritual failed, so your offered piece was returned.")
		return {"accepted": false}
	var offered: Dictionary = pending_exchange.get("offered", {}).duplicate(true)
	var completed := next_progress >= required
	contributions[collection_id] = 0 if completed else next_progress
	active_contribution_collection_id = collection_id
	pending_exchange.clear()
	contribution_changed.emit(
		collection_id,
		required if completed else next_progress,
		required,
		completed,
		granted.duplicate(true)
	)
	if completed:
		exchange_completed.emit(offered, granted.duplicate(true))
	state_changed.emit()
	return {
		"accepted": true,
		"completed": completed,
		"collection_id": collection_id,
		"progress": required if completed else next_progress,
		"required": required,
		"reward": granted.duplicate(true),
	}


## Compatibility for callers from the first prototype. A contribution that
## has not filled its collection meter intentionally returns no reward yet.
func offer_from_stock(kind: String, content_id: String) -> Dictionary:
	var result := contribute_from_stock(kind, content_id)
	return (result.get("reward", {}) as Dictionary).duplicate(true)


func can_move_to(cell: Vector2i) -> bool:
	if not grid.has_cell(cell):
		return false
	var state := grid.cell(cell)
	if (
		state == null
		or state.landmark_id != ""
		or not state.structures.is_empty()
		or grid.top_elevation(cell) > 0
	):
		return false
	return true


func move_to(cell: Vector2i) -> bool:
	if cell == worldheart_cell:
		return true
	if not can_move_to(cell):
		return false
	var previous := worldheart_cell
	var previous_state := grid.cell(previous)
	if previous_state != null:
		previous_state.movement_locked = false
	var next_state := grid.cell(cell)
	if next_state != null:
		next_state.movement_locked = true
	worldheart_cell = cell
	grid.cell_changed.emit(previous)
	grid.cell_changed.emit(cell)
	worldheart_moved.emit(previous, cell)
	state_changed.emit()
	return true


func rotate_clockwise() -> int:
	worldheart_rotation_quarters = posmod(
		worldheart_rotation_quarters + 1, 4
	)
	worldheart_rotated.emit(worldheart_rotation_quarters)
	state_changed.emit()
	return worldheart_rotation_quarters


func lock_host_tile() -> void:
	var state := grid.cell(worldheart_cell)
	if state != null:
		state.movement_locked = true


func choose_starting_vibe(collection_id: String) -> bool:
	if registries.creative_collection(collection_id) == null:
		return false
	vibe_collection_id = collection_id
	vibe_changed.emit(collection_id)
	state_changed.emit()
	return true


func can_attune(collection_id: String) -> bool:
	if registries.creative_collection(collection_id) == null:
		return false
	return collections.discovered_count(collection_id) >= int(
		_config().get("attunement_unlock_discoveries", 4)
	)


func set_attunement(collection_id: String) -> bool:
	if collection_id != "" and not can_attune(collection_id):
		return false
	if attuned_collection_id == collection_id:
		return true
	attuned_collection_id = collection_id
	attunement_changed.emit(collection_id)
	state_changed.emit()
	return true


func migrate_tray_offers(offers: Array[Dictionary]) -> void:
	if not reward_queue.is_empty():
		return
	for offer: Dictionary in offers:
		if reward_queue.size() >= reserve_cap():
			break
		var reward: Dictionary = offer.get("reward", offer).duplicate(true)
		if _valid_reward(reward):
			_enqueue(reward, "tray_migration", false)
	_ensure_visible_reward_landings()
	if next_pulse_seconds <= 0.0:
		_schedule_next_pulse()
	state_changed.emit()


func to_save_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"reward_queue": queued_entries(),
		"next_pulse_seconds": maxf(0.0, next_pulse_seconds),
		"pulse_sequence": pulse_sequence,
		"entry_sequence": entry_sequence,
		"recent_tokens": recent_tokens.duplicate(),
		"attuned_collection_id": attuned_collection_id,
		"vibe_collection_id": vibe_collection_id,
		"worldheart_cell": [worldheart_cell.x, worldheart_cell.y],
		"worldheart_rotation_quarters": worldheart_rotation_quarters,
		"contributions": contributions.duplicate(true),
		"active_contribution_collection_id": active_contribution_collection_id,
		"pending_exchange": pending_exchange.duplicate(true),
	}


func from_save_dict(data: Dictionary) -> void:
	_generation_pause_sources.clear()
	reward_queue.clear()
	for raw_entry in data.get("reward_queue", []):
		if raw_entry is Dictionary and _valid_reward(raw_entry):
			reward_queue.append((raw_entry as Dictionary).duplicate(true))
	pulse_sequence = maxi(0, int(data.get("pulse_sequence", reward_queue.size())))
	entry_sequence = maxi(
		reward_queue.size(), int(data.get("entry_sequence", reward_queue.size()))
	)
	next_pulse_seconds = maxf(0.0, float(data.get("next_pulse_seconds", 0.0)))
	recent_tokens.clear()
	for raw_token in data.get("recent_tokens", []):
		recent_tokens.append(String(raw_token))
	attuned_collection_id = String(data.get("attuned_collection_id", ""))
	if attuned_collection_id != "" and registries.creative_collection(attuned_collection_id) == null:
		attuned_collection_id = ""
	vibe_collection_id = String(data.get("vibe_collection_id", ""))
	if vibe_collection_id != "" and registries.creative_collection(vibe_collection_id) == null:
		vibe_collection_id = ""
	var raw_cell: Array = data.get("worldheart_cell", [0, 0])
	worldheart_cell = Vector2i(int(raw_cell[0]), int(raw_cell[1])) if raw_cell.size() >= 2 else Vector2i.ZERO
	worldheart_rotation_quarters = posmod(
		int(data.get("worldheart_rotation_quarters", 0)), 4
	)
	if not grid.has_cell(worldheart_cell):
		worldheart_cell = grid.home_cell if grid.has_cell(grid.home_cell) else Vector2i.ZERO
	# Old saves did not persist loot landings. Resolve them only after restoring
	# the saved wardrobe transform, then keep them immutable from this point on.
	_ensure_visible_reward_landings()
	contributions.clear()
	for collection_id: String in data.get("contributions", {}):
		if registries.creative_collection(collection_id) != null:
			contributions[collection_id] = clampi(
				int(data["contributions"][collection_id]), 0, contribution_required() - 1
			)
	active_contribution_collection_id = String(data.get("active_contribution_collection_id", ""))
	# Exchange is synchronous. A persisted marker can only come from an older
	# interrupted build, so preserve ownership by returning its offered piece.
	pending_exchange = (data.get("pending_exchange", {}) as Dictionary).duplicate(true)
	if not pending_exchange.is_empty():
		var offered: Dictionary = pending_exchange.get("offered", {})
		var offered_kind := String(offered.get("kind", ""))
		var offered_id := String(offered.get("id", ""))
		if offered_kind == "tile" and registries.tile(offered_id) != null:
			stock.add_tile(offered_id)
		elif offered_kind == "structure" and registries.structure(offered_id) != null:
			stock.add_structure(offered_id)
		pending_exchange.clear()
	if next_pulse_seconds <= 0.0:
		_schedule_next_pulse()
	lock_host_tile()
	state_changed.emit()


func _roll_pulse_reward() -> Dictionary:
	var starters: Array = _config().get("starter_rewards", [])
	if pulse_sequence < starters.size():
		var starter := _roll_vibe_starter(pulse_sequence)
		if starter.is_empty():
			starter = starters[pulse_sequence].duplicate(true)
		pulse_sequence += 1
		return _decorate_reward(starter, "starter")
	var roles: Array = _config().get("roles", ["terrain", "substantial", "detail"])
	var role := String(roles[pulse_sequence % roles.size()]) if not roles.is_empty() else "any"
	var candidates := collections.eligible_members(role)
	var convergence := _convergence_candidates(candidates)
	if not convergence.is_empty():
		candidates = convergence
	var weighted: Array[Dictionary] = []
	for member: Dictionary in candidates:
		var kind := String(member.get("kind", ""))
		var content_id := String(member.get("id", ""))
		var token := "%s:%s" % [kind, content_id]
		var category := "tiles" if kind == "tile" else "structures"
		var weight := 1.0
		if not journal.is_discovered(category, content_id):
			weight *= float(_config().get("undiscovered_weight_multiplier", 2.2))
		if recent_tokens.has(token):
			weight *= float(_config().get("recent_weight_multiplier", 0.16))
		if attuned_collection_id != "" and String(member.get("collection_id", "")) == attuned_collection_id:
			weight *= float(_config().get("attunement_weight_multiplier", 4.0))
		var candidate := member.duplicate(true)
		candidate["weight"] = maxf(0.0001, weight)
		weighted.append(candidate)
	var chosen := rng.weighted("worldheart:pulse:%d" % pulse_sequence, weighted)
	pulse_sequence += 1
	if chosen.is_empty():
		return {}
	return _decorate_reward(chosen, role)


func _roll_exchange_reward(
	collection_id: String,
	offered_kind: String,
	offered_id: String
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var missing: Array[Dictionary] = []
	for member: Dictionary in collections.eligible_members("", collection_id):
		var kind := String(member.get("kind", ""))
		var content_id := String(member.get("id", ""))
		if kind == offered_kind and content_id == offered_id:
			continue
		var category := "tiles" if kind == "tile" else "structures"
		var candidate := member.duplicate(true)
		candidate["weight"] = (
			float(_config().get("undiscovered_weight_multiplier", 2.2))
			if not journal.is_discovered(category, content_id)
			else 1.0
		)
		candidates.append(candidate)
		if not journal.is_discovered(category, content_id):
			missing.append(candidate)
	if _at_convergence(collection_id) and not missing.is_empty():
		candidates = missing
	var chosen := rng.weighted(
		"worldheart:exchange:%s:%d" % [collection_id, pulse_sequence], candidates
	)
	if chosen.is_empty():
		return {}
	return _decorate_reward(chosen, "exchange")


func _roll_vibe_starter(index: int) -> Dictionary:
	if vibe_collection_id == "":
		return {}
	var roles: Array = _config().get("roles", ["terrain", "substantial", "detail"])
	var role := String(roles[index % roles.size()]) if not roles.is_empty() else "any"
	var candidates := collections.eligible_members(role, vibe_collection_id)
	if candidates.is_empty():
		candidates = collections.eligible_members("any", vibe_collection_id)
	var weighted: Array[Dictionary] = []
	for member: Dictionary in candidates:
		var candidate := member.duplicate(true)
		var token := "%s:%s" % [member.get("kind", ""), member.get("id", "")]
		candidate["weight"] = 0.05 if recent_tokens.has(token) else 1.0
		weighted.append(candidate)
	return rng.weighted("worldheart:vibe:%s:%d" % [vibe_collection_id, index], weighted)


func _convergence_candidates(candidates: Array[Dictionary]) -> Array[Dictionary]:
	if attuned_collection_id == "" or not _at_convergence(attuned_collection_id):
		return []
	var result: Array[Dictionary] = []
	for member: Dictionary in candidates:
		var kind := String(member.get("kind", ""))
		var content_id := String(member.get("id", ""))
		var category := "tiles" if kind == "tile" else "structures"
		if (
			String(member.get("collection_id", "")) == attuned_collection_id
			and not journal.is_discovered(category, content_id)
		):
			result.append(member)
	return result


func _at_convergence(collection_id: String) -> bool:
	var total := collections.total_count(collection_id)
	return total > 0 and (
		float(collections.discovered_count(collection_id)) / float(total)
		>= float(_config().get("convergence_threshold", 0.75))
	)


func _decorate_reward(source: Dictionary, role: String) -> Dictionary:
	var kind := String(source.get("kind", ""))
	var content_id := String(source.get("id", ""))
	var membership := collections.membership(kind, content_id)
	var tier := int(membership.get("tier", source.get("tier", 0)))
	return {
		"kind": kind,
		"id": content_id,
		"amount": 1,
		"rarity": "rare" if tier >= 2 else "uncommon" if tier == 1 else "common",
		"role": role,
		"creative_collection_id": String(membership.get("collection_id", "")),
	}


func _enqueue(source: Dictionary, source_name: String, announce := true) -> void:
	var entry := source.duplicate(true)
	entry_sequence += 1
	entry["entry_id"] = "worldheart:%d" % entry_sequence
	entry["source"] = source_name
	reward_queue.append(entry)
	_ensure_visible_reward_landings()
	_remember(String(entry.get("kind", "")), String(entry.get("id", "")))
	if announce:
		pulse_queued.emit(entry.duplicate(true))


func _ensure_visible_reward_landings() -> void:
	var occupied := {}
	var visible_count := mini(visible_cap(), reward_queue.size())
	for index in visible_count:
		var existing: Dictionary = reward_queue[index]
		var raw_cell: Variant = existing.get("landing_cell", [])
		var raw_position: Variant = existing.get("landing_position", [])
		if (
			raw_cell is Array
			and (raw_cell as Array).size() >= 2
			and raw_position is Array
			and (raw_position as Array).size() >= 3
		):
			occupied[Vector2i(int(raw_cell[0]), int(raw_cell[1]))] = true
	for index in visible_count:
		var entry: Dictionary = reward_queue[index]
		var raw_position: Variant = entry.get("landing_position", [])
		if raw_position is Array and (raw_position as Array).size() >= 3:
			continue
		var landing_cell := worldheart_cell
		var landing_offset := Vector2i.ZERO
		for local_offset: Vector2i in [
			Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP
		]:
			var rotated := _rotate_landing_offset(local_offset)
			var candidate := worldheart_cell + rotated
			if not occupied.has(candidate):
				landing_cell = candidate
				landing_offset = rotated
				break
		occupied[landing_cell] = true
		var inset := Vector3(
			-float(landing_offset.x), 0.0, -float(landing_offset.y)
		) * grid.tile_size * 0.23
		var landing_position := (
			grid.cell_to_world(landing_cell) + inset + Vector3.UP * 0.28
		)
		entry["landing_cell"] = [landing_cell.x, landing_cell.y]
		entry["landing_position"] = [
			landing_position.x, landing_position.y, landing_position.z
		]


func _rotate_landing_offset(local_offset: Vector2i) -> Vector2i:
	match posmod(worldheart_rotation_quarters, 4):
		1:
			return Vector2i(local_offset.y, -local_offset.x)
		2:
			return -local_offset
		3:
			return Vector2i(-local_offset.y, local_offset.x)
	return local_offset


func _schedule_next_pulse() -> void:
	var minimum := maxf(0.1, float(_config().get("pulse_interval_min", 15.0)))
	var maximum := maxf(minimum, float(_config().get("pulse_interval_max", 25.0)))
	next_pulse_seconds = rng.randf_range("worldheart:cadence", minimum, maximum)


func _remember(kind: String, content_id: String) -> void:
	var token := "%s:%s" % [kind, content_id]
	recent_tokens.erase(token)
	recent_tokens.push_front(token)
	var memory := maxi(1, int(_config().get("recent_memory", 7)))
	while recent_tokens.size() > memory:
		recent_tokens.pop_back()


func _owned_total(kind: String, content_id: String) -> int:
	var total := stock.tile_count(content_id) if kind == "tile" else stock.structure_count(content_id)
	for slot: Dictionary in grid.all_cell_slots():
		var state: WorldGrid.CellState = slot.get("state")
		if kind == "tile" and state.tile_id == content_id:
			total += 1
		elif kind == "structure":
			for structure: WorldGrid.StructureState in state.structures:
				if structure.structure_id == content_id:
					total += 1
	return total


func _valid_reward(reward: Dictionary) -> bool:
	var kind := String(reward.get("kind", ""))
	var content_id := String(reward.get("id", ""))
	return (
		(kind == "tile" and registries.tile(content_id) != null)
		or (kind == "structure" and registries.structure(content_id) != null)
	)


func _reject(message: String) -> Dictionary:
	exchange_rejected.emit(message)
	return {}


func _config() -> Dictionary:
	return registries.worldheart_config
