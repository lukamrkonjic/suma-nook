class_name ContentRemovalMigrator
extends RefCounted
## Repairs saves after optional build content is retired. Generated terrain is
## persisted as ordinary cells, never replayed from a catalog snapshot: a tile
## definition that no longer exists becomes the configured safe grass block.
## Missing models are omitted, including children whose support was removed.


static func repair(raw_data: Dictionary, registries: Registries) -> Dictionary:
	var data := raw_data.duplicate(true)
	var state := {"changed": false}
	var fallback := _fallback_tile_id(registries)
	var known_iids := _repair_grid(data, registries, fallback, state)
	_repair_stock(data, registries, fallback, known_iids, state)
	_repair_feature_payloads(data, registries, fallback, known_iids, state)
	_repair_collection(data, registries, fallback, state)
	_repair_onboarding(data, registries, fallback, state)
	return {"data": data, "changed": bool(state["changed"])}


static func _fallback_tile_id(registries: Registries) -> String:
	var configured := String(registries.nook_config.get(
		"safe_ground_tile_id", "tile_grass"
	))
	if registries.tile(configured) != null:
		return configured
	if registries.tile("tile_grass") != null:
		return "tile_grass"
	var active := registries.active_tile_ids()
	return active[0] if not active.is_empty() else ""


static func _repair_grid(
	data: Dictionary,
	registries: Registries,
	fallback: String,
	state: Dictionary
) -> Dictionary:
	var known_iids := {}
	var grid: Dictionary = data.get("grid", {})
	var cells: Array = grid.get("cells", [])
	for cell: Dictionary in cells:
		if registries.tile(String(cell.get("tile", ""))) == null:
			cell["tile"] = fallback
			state["changed"] = true
		var candidates: Array = []
		for raw_structure: Variant in cell.get("structs", []):
			if not raw_structure is Dictionary:
				state["changed"] = true
				continue
			var structure: Dictionary = raw_structure
			if registries.structure(String(structure.get("id", ""))) == null:
				state["changed"] = true
				continue
			candidates.append(structure)
		var local_iids := {}
		for structure: Dictionary in candidates:
			var iid := int(structure.get("iid", 0))
			if iid > 0:
				local_iids[iid] = true
		var repaired: Array = []
		for structure: Dictionary in candidates:
			var parent := int(structure.get("parent", 0))
			if parent != 0 and not local_iids.has(parent):
				state["changed"] = true
				continue
			var iid := int(structure.get("iid", 0))
			if iid <= 0 or known_iids.has(iid):
				state["changed"] = true
				continue
			known_iids[iid] = true
			repaired.append(structure)
		cell["structs"] = repaired
	grid["cells"] = cells
	data["grid"] = grid
	return known_iids


static func _repair_stock(
	data: Dictionary,
	registries: Registries,
	fallback: String,
	known_iids: Dictionary,
	state: Dictionary
) -> void:
	var stock: Dictionary = data.get("stock", {})
	var repaired_tiles := {}
	for tile_id: String in stock.get("tiles", {}):
		var amount := int(stock["tiles"][tile_id])
		var destination := tile_id
		if registries.tile(tile_id) == null:
			destination = fallback
			state["changed"] = true
		repaired_tiles[destination] = int(repaired_tiles.get(destination, 0)) + amount
	stock["tiles"] = repaired_tiles
	var repaired_structures := {}
	for structure_id: String in stock.get("structures", {}):
		if registries.structure(structure_id) == null:
			state["changed"] = true
			continue
		repaired_structures[structure_id] = stock["structures"][structure_id]
	stock["structures"] = repaired_structures
	var repaired_instances: Array = []
	for raw_instance: Variant in stock.get("structure_instances", []):
		if not raw_instance is Dictionary:
			state["changed"] = true
			continue
		var instance: Dictionary = raw_instance
		var definition := registries.structure(String(instance.get("id", "")))
		var iid := int(instance.get("iid", 0))
		if definition == null or iid <= 0 or known_iids.has(iid):
			state["changed"] = true
			continue
		known_iids[iid] = true
		repaired_instances.append(instance)
	stock["structure_instances"] = repaired_instances
	data["stock"] = stock


static func _repair_feature_payloads(
	data: Dictionary,
	registries: Registries,
	fallback: String,
	known_iids: Dictionary,
	state: Dictionary
) -> void:
	var features: Dictionary = data.get("features", {})
	var camping: Dictionary = features.get("camping", {})
	var shelters: Array = []
	for raw_shelter: Variant in camping.get("shelters", []):
		if raw_shelter is Dictionary \
			and known_iids.has(int(raw_shelter.get("iid", 0))):
			shelters.append(raw_shelter)
		else:
			state["changed"] = true
	camping["shelters"] = shelters
	features["camping"] = camping
	var fishing: Dictionary = features.get("fishing", {})
	var basket: Dictionary = fishing.get("basket", {})
	for haul: Dictionary in basket.get("hauls", []):
		haul["entries"] = _repair_rewards(
			haul.get("entries", []), registries, fallback, state,
			"form", "building_id"
		)
	fishing["basket"] = basket
	features["fishing"] = fishing
	var visitors: Dictionary = features.get("visitors", {})
	var event: Dictionary = visitors.get("current_event", {})
	if not event.is_empty():
		var reward: Dictionary = event.get("reward", {})
		if not _repair_reward(reward, registries, fallback, "kind", "id"):
			visitors["current_event"] = {}
			state["changed"] = true
		elif reward != event.get("reward", {}):
			event["reward"] = reward
			visitors["current_event"] = event
			state["changed"] = true
	features["visitors"] = visitors
	data["features"] = features
	var progression: Dictionary = data.get("progression", {})
	var discovery: Dictionary = progression.get("discovery", {})
	discovery["pending"] = _repair_rewards(
		discovery.get("pending", []), registries, fallback, state
	)
	discovery["wish_choices"] = _repair_rewards(
		discovery.get("wish_choices", []), registries, fallback, state
	)
	progression["discovery"] = discovery
	data["progression"] = progression
	var harvesting: Dictionary = features.get("harvesting", {})
	var history: Dictionary = harvesting.get("reward_history", {})
	for collection_id: String in history:
		var entry: Dictionary = history[collection_id]
		var recent: Array = []
		for raw_token: Variant in entry.get("recent", []):
			var token := String(raw_token)
			var kind := token.get_slice(":", 0)
			var content_id := token.get_slice(":", 1)
			if (kind == "tile" and registries.tile(content_id) != null) \
				or (kind == "structure" and registries.structure(content_id) != null):
				recent.append(token)
			else:
				state["changed"] = true
		entry["recent"] = recent
		history[collection_id] = entry
	harvesting["reward_history"] = history
	features["harvesting"] = harvesting
	data["features"] = features


static func _repair_rewards(
	raw_entries: Variant,
	registries: Registries,
	fallback: String,
	state: Dictionary,
	kind_field := "kind",
	id_field := "id"
) -> Array:
	var result: Array = []
	if not raw_entries is Array:
		return result
	for raw_entry: Variant in raw_entries:
		if not raw_entry is Dictionary:
			state["changed"] = true
			continue
		var entry: Dictionary = raw_entry
		var before := entry.duplicate(true)
		if _repair_reward(entry, registries, fallback, kind_field, id_field):
			result.append(entry)
		else:
			state["changed"] = true
		if entry != before:
			state["changed"] = true
	return result


static func _repair_reward(
	entry: Dictionary,
	registries: Registries,
	fallback: String,
	kind_field: String,
	id_field: String
) -> bool:
	var kind := String(entry.get(kind_field, ""))
	var content_id := String(entry.get(id_field, ""))
	if kind in ["tile", "tile_bundle"]:
		if registries.tile(content_id) == null:
			entry[id_field] = fallback
		return true
	if kind in ["structure", "model"]:
		return registries.structure(content_id) != null
	return true


static func _repair_collection(
	data: Dictionary,
	registries: Registries,
	fallback: String,
	state: Dictionary
) -> void:
	var collection: Dictionary = data.get("collection", {})
	var entries: Dictionary = collection.get("entries", {})
	var repaired := {}
	for key: String in entries:
		var category := key.get_slice("/", 0)
		var content_id := key.trim_prefix(category + "/")
		var destination := key
		if category == "tiles" and registries.tile(content_id) == null:
			destination = "tiles/%s" % fallback
			state["changed"] = true
		elif category == "structures" and registries.structure(content_id) == null:
			state["changed"] = true
			continue
		if repaired.has(destination):
			var target: Dictionary = repaired[destination]
			var incoming: Dictionary = entries[key]
			target["count"] = int(target.get("count", 0)) + int(incoming.get("count", 0))
			target["placed"] = int(target.get("placed", 0)) + int(incoming.get("placed", 0))
		else:
			repaired[destination] = (entries[key] as Dictionary).duplicate(true)
	collection["entries"] = repaired
	data["collection"] = collection


static func _repair_onboarding(
	data: Dictionary,
	registries: Registries,
	fallback: String,
	state: Dictionary
) -> void:
	var onboarding: Dictionary = data.get("onboarding", {})
	var kind := String(onboarding.get("guided_kind", ""))
	var content_id := String(onboarding.get("guided_id", ""))
	if kind == "tile" and content_id != "" and registries.tile(content_id) == null:
		onboarding["guided_id"] = fallback
		state["changed"] = true
	elif kind == "structure" and content_id != "" \
		and registries.structure(content_id) == null:
		onboarding["guided_kind"] = ""
		onboarding["guided_id"] = ""
		onboarding["stage"] = OnboardingState.COMPLETE
		state["changed"] = true
	data["onboarding"] = onboarding
