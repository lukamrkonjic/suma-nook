class_name ProjectService
extends RefCounted
## Persistent, presentation-free state for Frontier and Collection Projects.
## Exact rewards are rolled once at creation and then saved concealed.

signal project_created(project: Dictionary)
signal tracked_project_changed(project: Dictionary)
signal project_progressed(project: Dictionary, slot: Dictionary)
signal project_completed(project: Dictionary)
signal project_reward_granted(project: Dictionary, reward: Dictionary)
signal offers_changed(offers: Array[Dictionary])

const TYPE_FRONTIER := "frontier"
const TYPE_COLLECTION := "collection"
const OFFER_COUNT := 3

var registries: Registries
var rng: RngService
var rewards: BuildRewardService
var finds: FindsReserveService

var projects: Dictionary = {}
var tracked_project_id := ""
var collection_offer_ids: Array[String] = []
var completed_count := 0
var offer_sequence := 0
var contribution_receipts: Dictionary = {}
var _recent_collections: Array[String] = []


func _init(
	content: Registries,
	rng_service: RngService,
	reward_service: BuildRewardService,
	finds_reserve: FindsReserveService
) -> void:
	registries = content
	rng = rng_service
	rewards = reward_service
	finds = finds_reserve
	ensure_collection_offers()


func ensure_collection_offers() -> void:
	collection_offer_ids = collection_offer_ids.filter(func(project_id: String) -> bool:
		return projects.has(project_id) and not bool(projects[project_id].get("complete", false))
	)
	while collection_offer_ids.size() < OFFER_COUNT:
		var definition: ProjectDefinitions.ProjectDefinition = (
			_choose_collection_definition(collection_offer_ids.size())
		)
		if definition == null:
			break
		offer_sequence += 1
		var project_id := "collection:%d:%s" % [offer_sequence, definition.id]
		var state := _create_state(definition, project_id, {
			"seed": _stable_seed(project_id),
		})
		projects[project_id] = state
		collection_offer_ids.append(project_id)
		project_created.emit(state.duplicate(true))
	offers_changed.emit(collection_offers())


func create_frontier(
	frontier_id: String,
	definition_id: String,
	seed_value: int,
	expansion_point_id: String,
	metadata: Dictionary = {}
) -> Dictionary:
	if projects.has(frontier_id):
		return project(frontier_id)
	var definition = registries.project_definition(definition_id)
	if definition == null or definition.project_type != TYPE_FRONTIER:
		return {}
	var context := metadata.duplicate(true)
	context["seed"] = seed_value
	context["expansion_point_id"] = expansion_point_id
	var state := _create_state(definition, frontier_id, context)
	projects[frontier_id] = state
	project_created.emit(state.duplicate(true))
	return state.duplicate(true)


func track(project_id: String) -> bool:
	if not projects.has(project_id):
		return false
	tracked_project_id = project_id
	var state: Dictionary = projects[project_id]
	var collection_id := String(state.get("collection_id", ""))
	if not collection_id.is_empty():
		_recent_collections.erase(collection_id)
		_recent_collections.push_front(collection_id)
		while _recent_collections.size() > 3:
			_recent_collections.pop_back()
	tracked_project_changed.emit(state.duplicate(true))
	return true


func tracked_project() -> Dictionary:
	return project(tracked_project_id)


func project(project_id: String) -> Dictionary:
	return (
		(projects[project_id] as Dictionary).duplicate(true)
		if projects.has(project_id)
		else {}
	)


func collection_offers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for project_id: String in collection_offer_ids:
		if projects.has(project_id):
			result.append((projects[project_id] as Dictionary).duplicate(true))
	return result


func target_for_tags(tags: Array[String]) -> Dictionary:
	if tracked_project_id.is_empty() or not projects.has(tracked_project_id):
		return {}
	return target_for_project(tracked_project_id, tags)


func target_for_project(project_id: String, tags: Array[String]) -> Dictionary:
	if not projects.has(project_id):
		return {}
	var state: Dictionary = projects[project_id]
	if bool(state.get("complete", false)):
		return {}
	for index in (state.get("slots", []) as Array).size():
		var slot: Dictionary = state["slots"][index]
		if int(slot.get("current", 0)) >= int(slot.get("required", 1)):
			continue
		if bool(slot.get("consumes_find", false)):
			continue
		if _tags_overlap(tags, slot.get("accepted_tags", []) as Array):
			return {"project_id": project_id, "slot_index": index}
	return {}


func contribute(
	project_id: String,
	slot_index: int,
	receipt_id: String,
	amount := 1,
	metadata: Dictionary = {}
) -> Dictionary:
	if receipt_id.is_empty() or contribution_receipts.has(receipt_id):
		return {"accepted": false, "reason": "duplicate"}
	if not projects.has(project_id):
		return {"accepted": false, "reason": "missing_project"}
	var state: Dictionary = projects[project_id]
	if bool(state.get("complete", false)):
		return {"accepted": false, "reason": "complete"}
	var slots: Array = state.get("slots", [])
	if slot_index < 0 or slot_index >= slots.size():
		return {"accepted": false, "reason": "missing_slot"}
	var slot: Dictionary = slots[slot_index]
	if bool(slot.get("consumes_find", false)):
		return {"accepted": false, "reason": "find_required"}
	var before := int(slot.get("current", 0))
	var required := int(slot.get("required", 1))
	if before >= required:
		return {"accepted": false, "reason": "slot_complete"}
	contribution_receipts[receipt_id] = {
		"project_id": project_id,
		"slot_index": slot_index,
		"metadata": metadata.duplicate(true),
	}
	slot["current"] = mini(required, before + maxi(1, amount))
	project_progressed.emit(state.duplicate(true), slot.duplicate(true))
	_finish_if_ready(state)
	return {
		"accepted": true,
		"project_id": project_id,
		"slot": slot.duplicate(true),
		"complete": bool(state.get("complete", false)),
	}


func spend_find(project_id: String, slot_index: int) -> Dictionary:
	if not projects.has(project_id):
		return {"accepted": false, "reason": "missing_project"}
	var state: Dictionary = projects[project_id]
	var slots: Array = state.get("slots", [])
	if slot_index < 0 or slot_index >= slots.size():
		return {"accepted": false, "reason": "missing_slot"}
	var slot: Dictionary = slots[slot_index]
	if not bool(slot.get("consumes_find", false)):
		return {"accepted": false, "reason": "not_find_slot"}
	if int(slot.get("current", 0)) >= int(slot.get("required", 1)):
		return {"accepted": false, "reason": "slot_complete"}
	var find_id := _find_id_for_slot(slot)
	if find_id.is_empty() or not finds.spend(find_id, 1):
		return {"accepted": false, "reason": "find_unavailable"}
	slot["current"] = int(slot.get("current", 0)) + 1
	project_progressed.emit(state.duplicate(true), slot.duplicate(true))
	_finish_if_ready(state)
	return {"accepted": true, "find_id": find_id, "complete": state["complete"]}


func mark_frontier_rewarded(project_id: String) -> bool:
	if not projects.has(project_id):
		return false
	var state: Dictionary = projects[project_id]
	if not bool(state.get("complete", false)) or bool(state.get("rewarded", false)):
		return false
	state["rewarded"] = true
	return true


func to_save_dict() -> Dictionary:
	return {
		"projects": projects.duplicate(true),
		"tracked_project_id": tracked_project_id,
		"collection_offer_ids": collection_offer_ids.duplicate(),
		"completed_count": completed_count,
		"offer_sequence": offer_sequence,
		"contribution_receipts": contribution_receipts.duplicate(true),
		"recent_collections": _recent_collections.duplicate(),
	}


func from_save_dict(data: Dictionary) -> void:
	projects = (data.get("projects", {}) as Dictionary).duplicate(true)
	tracked_project_id = String(data.get("tracked_project_id", ""))
	collection_offer_ids.clear()
	for raw_id: Variant in data.get("collection_offer_ids", []):
		var project_id := String(raw_id)
		if projects.has(project_id):
			collection_offer_ids.append(project_id)
	completed_count = maxi(0, int(data.get("completed_count", 0)))
	offer_sequence = maxi(0, int(data.get("offer_sequence", 0)))
	contribution_receipts = (
		data.get("contribution_receipts", {}) as Dictionary
	).duplicate(true)
	_recent_collections.clear()
	for raw_collection: Variant in data.get("recent_collections", []):
		_recent_collections.append(String(raw_collection))
	if not projects.has(tracked_project_id):
		tracked_project_id = ""
	for state: Dictionary in projects.values():
		if (
			String(state.get("type", "")) == TYPE_COLLECTION
			and bool(state.get("complete", false))
			and not bool(state.get("rewarded", false))
		):
			_grant_collection_reward(state, false)
	ensure_collection_offers()
	tracked_project_changed.emit(tracked_project())


func _create_state(definition, project_id: String, context: Dictionary) -> Dictionary:
	var slots: Array[Dictionary] = []
	for slot in definition.contribution_slots:
		slots.append(slot.to_state())
	var seed_value := int(context.get("seed", _stable_seed(project_id)))
	var hidden_reward: Dictionary = {}
	if definition.project_type == TYPE_COLLECTION:
		hidden_reward = rewards.roll_collection(
			definition.collection_id,
			"project_reward:%d:%s" % [seed_value, project_id],
			{"recent": []}
		)
	return {
		"id": project_id,
		"definition_id": definition.id,
		"type": definition.project_type,
		"name": definition.display_name,
		"collection_id": definition.collection_id,
		"slots": slots,
		"reward": hidden_reward,
		"reward_definition": definition.reward.duplicate(true),
		"seed": seed_value,
		"expansion_point_id": String(context.get("expansion_point_id", "")),
		"frontier_metadata": (
			context.get("frontier_metadata", {}) as Dictionary
		).duplicate(true),
		"complete": false,
		"rewarded": false,
		"special": definition.special,
		"rarity": definition.rarity,
		"presentation": definition.presentation.duplicate(true),
		"modifier_tags": definition.modifier_tags.duplicate(),
	}


func _finish_if_ready(state: Dictionary) -> void:
	if bool(state.get("complete", false)):
		return
	for slot: Dictionary in state.get("slots", []):
		if int(slot.get("current", 0)) < int(slot.get("required", 1)):
			return
	state["complete"] = true
	completed_count += 1
	var granted: Dictionary = {}
	if String(state.get("type", "")) == TYPE_COLLECTION:
		granted = _grant_collection_reward(state, false)
		if not granted.is_empty():
			collection_offer_ids.erase(String(state.get("id", "")))
			ensure_collection_offers()
	# Save listeners see the complete transaction: completion, ownership, and
	# replacement offer have all committed before this public boundary.
	project_completed.emit(state.duplicate(true))
	if not granted.is_empty():
		project_reward_granted.emit(
			state.duplicate(true), granted.duplicate(true)
		)


func _grant_collection_reward(state: Dictionary, emit_signal: bool) -> Dictionary:
	var reward: Dictionary = state.get("reward", {})
	if reward.is_empty() or bool(state.get("rewarded", false)):
		return {}
	var granted: Dictionary = rewards.grant(reward)
	if granted.is_empty():
		return {}
	state["rewarded"] = true
	if emit_signal:
		project_reward_granted.emit(state.duplicate(true), granted.duplicate(true))
	return granted


func _choose_collection_definition(choice_index: int):
	var excluded_definitions: Dictionary = {}
	for offer_id: String in collection_offer_ids:
		if projects.has(offer_id):
			excluded_definitions[String(projects[offer_id].get("definition_id", ""))] = true
	var candidates: Array[Dictionary] = []
	for definition in registries.project_definitions.values():
		if definition.project_type != TYPE_COLLECTION or definition.offer_weight <= 0.0:
			continue
		if excluded_definitions.has(definition.id):
			continue
		var weight: float = definition.offer_weight
		var recent_index := _recent_collections.find(definition.collection_id)
		if recent_index >= 0:
			weight *= 0.35 + float(recent_index) * 0.15
		candidates.append({"definition": definition, "weight": weight})
	if candidates.is_empty():
		return null
	var chosen := rng.weighted(
		"project_offer:%d:%d" % [offer_sequence, choice_index], candidates
	)
	return chosen.get("definition")


func _find_id_for_slot(slot: Dictionary) -> String:
	for raw_tag: Variant in slot.get("accepted_tags", []):
		var tag := String(raw_tag)
		if tag.begins_with("find:"):
			return tag.trim_prefix("find:")
	return ""


func _tags_overlap(source: Array[String], accepted: Array) -> bool:
	for tag: String in source:
		if accepted.has(tag.to_lower()):
			return true
	return false


func _stable_seed(value: String) -> int:
	return absi(hash("project|%d|%s" % [rng.world_seed, value]))
