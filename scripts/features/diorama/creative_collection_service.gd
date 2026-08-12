class_name CreativeCollectionService
extends RefCounted
## Permanent thematic knowledge and vocabulary unlocks. This intentionally
## does not organize the Build Bag, which remains based on building function.

signal collection_progressed(collection_id: String, discovered: int, total: int)
signal milestone_reached(collection_id: String, milestone: Dictionary)

var registries: Registries
var collection: CollectionManager
var gifts
var reached_milestones: Dictionary = {}
var unlocked_tiers: Dictionary = {}
var _membership: Dictionary = {}


func _init(
	content: Registries,
	journal: CollectionManager,
	world_gifts = null
) -> void:
	registries = content
	collection = journal
	gifts = world_gifts
	_rebuild_membership()
	var self_ref: WeakRef = weakref(self)
	collection.discovered.connect(func(category: String, content_id: String):
		var service := self_ref.get_ref() as CreativeCollectionService
		if service != null:
			service._on_discovered(category, content_id)
	)


func membership(kind: String, content_id: String) -> Dictionary:
	return (_membership.get("%s:%s" % [kind, content_id], {}) as Dictionary).duplicate(true)


func collection_for(kind: String, content_id: String) -> String:
	return String(membership(kind, content_id).get("collection_id", ""))


func is_member_unlocked(member: Dictionary) -> bool:
	var collection_id := String(member.get("collection_id", ""))
	return int(member.get("tier", 0)) <= int(unlocked_tiers.get(collection_id, 0))


func eligible_members(role: String = "", collection_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for member: Dictionary in _membership.values():
		if collection_id != "" and String(member.get("collection_id", "")) != collection_id:
			continue
		if not is_member_unlocked(member) or not _matches_role(member, role):
			continue
		result.append(member.duplicate(true))
	return result


func roll_member(
	collection_id: String,
	stream_name: String,
	prefer_rare := false,
	exclude: Array[String] = []
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for member: Dictionary in eligible_members("", collection_id):
		var token := "%s:%s" % [member.get("kind", ""), member.get("id", "")]
		if exclude.has(token):
			continue
		var category := "tiles" if member.get("kind", "") == "tile" else "structures"
		var tier := int(member.get("tier", 0))
		var weight := 1.0
		if not collection.is_discovered(category, String(member.get("id", ""))):
			weight *= 1.75
		if prefer_rare:
			weight *= 1.0 + float(tier) * 2.0
		elif tier > 0:
			weight *= 0.72
		var candidate := member.duplicate(true)
		candidate["weight"] = weight
		candidate["rarity"] = "rare" if tier >= 2 else "uncommon" if tier == 1 else "common"
		candidates.append(candidate)
	var chosen := registries_rng().weighted(stream_name, candidates)
	if chosen.is_empty():
		return {}
	return {
		"kind": String(chosen.get("kind", "")),
		"id": String(chosen.get("id", "")),
		"amount": 1,
		"rarity": String(chosen.get("rarity", "common")),
		"creative_collection_id": collection_id,
	}


## Injected by DioramaModule so this service can stay easy to construct in
## tests without another constructor dependency cycle.
var _rng: RngService


func set_rng(rng_service: RngService) -> void:
	_rng = rng_service


func registries_rng() -> RngService:
	return _rng


func record_generated_plan(plan) -> void:
	if plan == null:
		return
	for tile: Dictionary in plan.tiles:
		collection.record("tiles", String(tile.get("tile_id", "")), 0)
	for feature: Dictionary in plan.features:
		collection.record("structures", String(feature.get("structure_id", "")), 0)


func discovered_count(collection_id: String) -> int:
	var count := 0
	for member: Dictionary in _membership.values():
		if String(member.get("collection_id", "")) != collection_id:
			continue
		var category := "tiles" if member.get("kind", "") == "tile" else "structures"
		if collection.is_discovered(category, String(member.get("id", ""))):
			count += 1
	return count


func total_count(collection_id: String) -> int:
	var definition = registries.creative_collection(collection_id)
	return definition.members.size() if definition != null else 0


func discovered_members(collection_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for member: Dictionary in _membership.values():
		if String(member.get("collection_id", "")) != collection_id:
			continue
		var category := "tiles" if member.get("kind", "") == "tile" else "structures"
		if collection.is_discovered(category, String(member.get("id", ""))):
			result.append(member.duplicate(true))
	return result


func sync_unlocks(grant_rewards := false) -> void:
	for definition in registries.creative_collections.values():
		_evaluate_collection(definition.id, grant_rewards)


func to_save_dict() -> Dictionary:
	return {
		"version": 1,
		"reached_milestones": reached_milestones.duplicate(true),
		"unlocked_tiers": unlocked_tiers.duplicate(true),
	}


func from_save_dict(data: Dictionary) -> void:
	reached_milestones = (data.get("reached_milestones", {}) as Dictionary).duplicate(true)
	unlocked_tiers = (data.get("unlocked_tiers", {}) as Dictionary).duplicate(true)
	# New data may add a threshold below existing discoveries. Unlock its
	# vocabulary without silently granting a one-use reward during load.
	sync_unlocks(false)


func _rebuild_membership() -> void:
	_membership.clear()
	for definition in registries.creative_collections.values():
		unlocked_tiers[definition.id] = int(unlocked_tiers.get(definition.id, 0))
		for raw_member: Dictionary in definition.members:
			var member := raw_member.duplicate(true)
			member["collection_id"] = definition.id
			_membership["%s:%s" % [member.get("kind", ""), member.get("id", "")]] = member


func _on_discovered(category: String, content_id: String) -> void:
	var kind := "tile" if category == "tiles" else "structure" if category == "structures" else ""
	if kind == "":
		return
	var collection_id := collection_for(kind, content_id)
	if collection_id != "":
		_evaluate_collection(collection_id, true)


func _evaluate_collection(collection_id: String, grant_rewards: bool) -> void:
	var definition = registries.creative_collection(collection_id)
	if definition == null:
		return
	var found := discovered_count(collection_id)
	var previous_tier := int(unlocked_tiers.get(collection_id, 0))
	var highest_tier := previous_tier
	for milestone: Dictionary in definition.milestones:
		if found < int(milestone.get("discoveries", 1)):
			continue
		highest_tier = maxi(highest_tier, int(milestone.get("unlock_tier", 0)))
		var milestone_id := String(milestone.get("id", ""))
		if reached_milestones.has(milestone_id):
			continue
		reached_milestones[milestone_id] = true
		if grant_rewards:
			var gift_id := String(milestone.get("gift_id", ""))
			if gift_id != "" and gifts != null:
				gifts.add(gift_id, int(milestone.get("gift_amount", 1)), "collection:%s" % milestone_id)
			milestone_reached.emit(collection_id, milestone.duplicate(true))
	unlocked_tiers[collection_id] = highest_tier
	if found > 0 or highest_tier != previous_tier:
		collection_progressed.emit(collection_id, found, definition.members.size())


func _matches_role(member: Dictionary, role: String) -> bool:
	if role == "" or role == "any":
		return true
	var kind := String(member.get("kind", ""))
	if role == "terrain":
		return kind == "tile"
	if kind != "structure":
		return false
	var definition := registries.structure(String(member.get("id", "")))
	if definition == null:
		return false
	var large := (
		definition.kind == "building"
		or definition.placement_tags.has("large")
		or definition.placement_tags.has("medium")
	)
	return large if role == "substantial" else not large
