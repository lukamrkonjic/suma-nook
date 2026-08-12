class_name DiscoveryTrayService
extends RefCounted
## Three loss-safe physical offers. An offer refills only after its exact first
## placement commits; rearranging owned pieces never reaches this service.

signal tray_changed
signal offer_committed(reward: Dictionary, replacement: Dictionary, slot: int)

var registries: Registries
var rng: RngService
var collections: CreativeCollectionService
var slots: Array[Dictionary] = []
var recent: Array[String] = []
var offer_sequence := 0
var placements_committed := 0


func _init(
	content: Registries,
	rng_service: RngService,
	creative_collections: CreativeCollectionService
) -> void:
	registries = content
	rng = rng_service
	collections = creative_collections


func initialize() -> void:
	if not slots.is_empty():
		return
	var roles: Array = registries.discovery_tray_config.get(
		"roles", ["terrain", "substantial", "detail"]
	)
	var starters: Array = registries.discovery_tray_config.get("starter_offers", [])
	for index in 3:
		var role := String(roles[index])
		var starter: Dictionary = starters[index] if index < starters.size() else {}
		slots.append(_make_offer(index, role, starter))
	tray_changed.emit()


func offers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for offer: Dictionary in slots:
		result.append(offer.duplicate(true))
	return result


func offer_at(slot: int) -> Dictionary:
	return slots[slot].duplicate(true) if slot >= 0 and slot < slots.size() else {}


func begin_hold(slot: int) -> Dictionary:
	if slot < 0 or slot >= slots.size():
		return {}
	var offer: Dictionary = slots[slot]
	if String(offer.get("state", "available")) != "available":
		return {}
	offer["state"] = "held"
	tray_changed.emit()
	return offer.duplicate(true)


func cancel_hold(offer_id: String) -> bool:
	for offer: Dictionary in slots:
		if String(offer.get("offer_id", "")) != offer_id:
			continue
		if String(offer.get("state", "")) == "held":
			offer["state"] = "available"
			tray_changed.emit()
		return true
	return false


func can_commit(offer_id: String, kind: String, content_id: String) -> bool:
	for offer: Dictionary in slots:
		if (
			String(offer.get("offer_id", "")) == offer_id
			and String(offer.get("kind", "")) == kind
			and String(offer.get("id", "")) == content_id
			and String(offer.get("state", "")) == "held"
		):
			return true
	return false


func commit(offer_id: String, kind: String, content_id: String) -> Dictionary:
	if not can_commit(offer_id, kind, content_id):
		return {}
	var slot_index := -1
	var previous: Dictionary = {}
	for index in slots.size():
		if String(slots[index].get("offer_id", "")) == offer_id:
			slot_index = index
			previous = slots[index].duplicate(true)
			break
	if slot_index < 0:
		return {}
	var category := "tiles" if kind == "tile" else "structures"
	var was_new := not collections.collection.is_discovered(category, content_id)
	collections.collection.record(category, content_id, 1)
	placements_committed += 1
	var token := "%s:%s" % [kind, content_id]
	recent.push_front(token)
	var memory := maxi(1, int(registries.discovery_tray_config.get("recent_memory", 6)))
	while recent.size() > memory:
		recent.pop_back()
	var replacement := _roll_offer(slot_index, String(previous.get("role", "detail")))
	slots[slot_index] = replacement
	var reward := {
		"kind": kind,
		"id": content_id,
		"amount": 1,
		"was_new": was_new,
		"creative_collection_id": collections.collection_for(kind, content_id),
		"offer_id": offer_id,
	}
	tray_changed.emit()
	offer_committed.emit(reward.duplicate(true), replacement.duplicate(true), slot_index)
	return reward


func to_save_dict() -> Dictionary:
	return {
		"version": 1,
		"slots": offers(),
		"recent": recent.duplicate(),
		"offer_sequence": offer_sequence,
		"placements_committed": placements_committed,
	}


func from_save_dict(data: Dictionary) -> void:
	slots.clear()
	for raw_offer: Variant in data.get("slots", []):
		if not raw_offer is Dictionary:
			continue
		var offer: Dictionary = raw_offer.duplicate(true)
		if _valid_offer(offer):
			offer["state"] = "available"
			slots.append(offer)
	recent.clear()
	for token: Variant in data.get("recent", []):
		recent.append(String(token))
	offer_sequence = maxi(0, int(data.get("offer_sequence", 0)))
	placements_committed = maxi(0, int(data.get("placements_committed", 0)))
	if slots.size() != 3:
		slots.clear()
	initialize()
	tray_changed.emit()


func _make_offer(slot: int, role: String, exact: Dictionary = {}) -> Dictionary:
	if not exact.is_empty():
		offer_sequence += 1
		return {
			"offer_id": "offer:%d" % offer_sequence,
			"slot": slot,
			"role": role,
			"kind": String(exact.get("kind", "")),
			"id": String(exact.get("id", "")),
			"state": "available",
		}
	return _roll_offer(slot, role)


func _roll_offer(slot: int, role: String) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var occupied: Array[String] = []
	for offer: Dictionary in slots:
		occupied.append("%s:%s" % [offer.get("kind", ""), offer.get("id", "")])
	var recent_multiplier := float(registries.discovery_tray_config.get("recent_weight_multiplier", 0.18))
	var new_multiplier := float(registries.discovery_tray_config.get("undiscovered_weight_multiplier", 1.8))
	for member: Dictionary in collections.eligible_members(role):
		var token := "%s:%s" % [member.get("kind", ""), member.get("id", "")]
		var weight := 1.0
		if occupied.has(token):
			weight *= 0.05
		if recent.has(token):
			weight *= recent_multiplier
		var category := "tiles" if member.get("kind", "") == "tile" else "structures"
		if not collections.collection.is_discovered(category, String(member.get("id", ""))):
			weight *= new_multiplier
		var candidate := member.duplicate(true)
		candidate["weight"] = weight
		candidates.append(candidate)
	if candidates.is_empty():
		for member: Dictionary in collections.eligible_members("any"):
			var candidate := member.duplicate(true)
			candidate["weight"] = 1.0
			candidates.append(candidate)
	var chosen := rng.weighted("diorama_tray:%d:%s" % [offer_sequence, role], candidates)
	offer_sequence += 1
	return {
		"offer_id": "offer:%d" % offer_sequence,
		"slot": slot,
		"role": role,
		"kind": String(chosen.get("kind", "")),
		"id": String(chosen.get("id", "")),
		"state": "available",
	}


func _valid_offer(offer: Dictionary) -> bool:
	var kind := String(offer.get("kind", ""))
	var content_id := String(offer.get("id", ""))
	return (
		(kind == "tile" and registries.tile(content_id) != null)
		or (kind == "structure" and registries.structure(content_id) != null)
	)
