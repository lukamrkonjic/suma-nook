class_name CurrentSaveValidator
extends RefCounted
## Current-format development saves either reference the live catalog cleanly
## or are rejected. There are no aliases, placeholders, repairs, or partial
## migrations before launch.


static func validate(data: Dictionary, registries: Registries) -> PackedStringArray:
	var errors: PackedStringArray = []
	var known_instance_ids := {}
	var grid: Dictionary = data.get("grid", {})
	for index in (grid.get("cells", []) as Array).size():
		var cell: Dictionary = grid["cells"][index]
		var tile_id := String(cell.get("tile", ""))
		_require(
			errors, registries.tile(tile_id) != null,
			"grid.cells[%d].tile references missing tile '%s'" % [index, tile_id]
		)
		for structure_index in (cell.get("structs", []) as Array).size():
			var structure: Dictionary = cell["structs"][structure_index]
			var structure_id := String(structure.get("id", ""))
			var definition := registries.structure(structure_id)
			_require(
				errors, definition != null,
				"grid.cells[%d].structs[%d] references missing structure '%s'"
				% [index, structure_index, structure_id]
			)
			_validate_structure_runtime(
				errors,
				structure.get("runtime", {}),
				definition,
				registries,
				"grid.cells[%d].structs[%d].runtime" % [index, structure_index]
			)
			var instance_id := int(structure.get("iid", 0))
			_require(
				errors, instance_id > 0 and not known_instance_ids.has(instance_id),
				"grid.cells[%d].structs[%d] has invalid or duplicate iid %d"
				% [index, structure_index, instance_id]
			)
			if instance_id > 0 and not known_instance_ids.has(instance_id):
				known_instance_ids[instance_id] = true
	var stock: Dictionary = data.get("stock", {})
	_validate_dictionary_ids(errors, stock.get("tiles", {}), registries.tiles, "stock.tiles")
	_validate_dictionary_ids(
		errors, stock.get("structures", {}), registries.structures, "stock.structures"
	)
	for index in (stock.get("structure_instances", []) as Array).size():
		var state: Dictionary = stock["structure_instances"][index]
		var structure_id := String(state.get("id", ""))
		var definition := registries.structure(structure_id)
		_require(
			errors, definition != null,
			"stock.structure_instances[%d] references missing structure '%s'"
			% [index, structure_id]
		)
		_validate_structure_runtime(
			errors,
			state.get("runtime", {}),
			definition,
			registries,
			"stock.structure_instances[%d].runtime" % index
		)
		var instance_id := int(state.get("iid", 0))
		_require(
			errors, instance_id > 0 and not known_instance_ids.has(instance_id),
			"stock.structure_instances[%d] has invalid or duplicate iid %d"
			% [index, instance_id]
		)
		if instance_id > 0 and not known_instance_ids.has(instance_id):
			known_instance_ids[instance_id] = true
	for index in (stock.get("deeds", []) as Array).size():
		var landmark_id := String(stock["deeds"][index])
		_require(
			errors, registries.landmark(landmark_id) != null,
			"stock.deeds[%d] references missing landmark '%s'" % [index, landmark_id]
		)
	var inventory: Dictionary = data.get("inventory", {})
	_validate_dictionary_ids(
		errors, inventory.get("counts", {}), registries.items, "inventory.counts"
	)
	_validate_progression(errors, data.get("progression", {}), registries)
	var equipment: Dictionary = data.get("equipment", {})
	_validate_array_ids(
		errors, equipment.get("owned", []), registries.items, "equipment.owned"
	)
	_validate_dictionary_values(
		errors, equipment.get("equipped", {}), registries.items,
		"equipment.equipped"
	)
	_validate_array_ids(
		errors, equipment.get("appearance", []), registries.items,
		"equipment.appearance"
	)
	_validate_landmarks(errors, data.get("landmarks", {}), registries)
	_validate_combat(errors, data.get("combat", {}), registries)
	_validate_collection(errors, data.get("collection", {}), registries)
	var feature_data: Dictionary = data.get("features", {})
	var camping: Dictionary = feature_data.get("camping", {})
	for index in (camping.get("shelters", []) as Array).size():
		var state: Dictionary = camping["shelters"][index]
		var instance_id := int(state.get("iid", 0))
		_require(
			errors, known_instance_ids.has(instance_id),
			"features.camping.shelters[%d] references missing iid %d"
			% [index, instance_id]
		)
	_validate_fishing(errors, feature_data.get("fishing", {}), registries)
	_validate_harvesting(errors, feature_data.get("harvesting", {}), registries)
	_validate_visitors(errors, feature_data.get("visitors", {}), registries)
	_validate_onboarding(
		errors, data.get("onboarding", {}), registries, known_instance_ids
	)
	return errors


static func _validate_structure_runtime(
	errors: PackedStringArray,
	raw: Variant,
	definition,
	registries: Registries,
	field: String
) -> void:
	if not raw is Dictionary:
		errors.append("%s must be an object" % field)
		return
	var runtime: Dictionary = raw
	if not runtime.has("harvest"):
		return
	var harvest: Variant = runtime.get("harvest")
	if not harvest is Dictionary:
		errors.append("%s.harvest must be an object" % field)
		return
	var profile_id := String((harvest as Dictionary).get("profile_id", ""))
	var declared_profile_id := ""
	if definition != null and definition.has_capability("harvest_source"):
		declared_profile_id = String(
			definition.capability("harvest_source").get("profile_id", "")
		)
	_require(
		errors,
		profile_id != ""
		and registries.harvest_profile(profile_id) != null
		and profile_id == declared_profile_id,
		"%s.harvest.profile_id references missing or mismatched harvest profile '%s'"
		% [field, profile_id]
	)
	_require(
		errors,
		String((harvest as Dictionary).get("state", "")) in [
			"maturing", "ready", "regrowing",
		],
		"%s.harvest.state is invalid" % field
	)


static func _validate_harvesting(
	errors: PackedStringArray,
	raw: Variant,
	registries: Registries
) -> void:
	if not raw is Dictionary:
		errors.append("features.harvesting must be an object")
		return
	var data: Dictionary = raw
	var claims: Variant = data.get("first_rewards_claimed", {})
	if not claims is Dictionary:
		errors.append("features.harvesting.first_rewards_claimed must be an object")
		return
	for profile_id: String in claims:
		_require(
			errors, registries.harvest_profile(profile_id) != null,
			"features.harvesting.first_rewards_claimed references missing harvest profile '%s'"
			% profile_id
		)
	var history: Variant = data.get("reward_history", {})
	if not history is Dictionary:
		errors.append("features.harvesting.reward_history must be an object")
		return
	for collection_id: String in history:
		var entry: Variant = history[collection_id]
		if collection_id == "" or not entry is Dictionary:
			errors.append(
				"features.harvesting.reward_history entries need a collection id and object"
			)
			continue
		var recent: Variant = (entry as Dictionary).get("recent", [])
		if not recent is Array:
			errors.append(
				"features.harvesting.reward_history.%s.recent must be an array"
				% collection_id
			)
			continue
		for token: Variant in recent:
			var parts := String(token).split(":", false, 1)
			var known := false
			if parts.size() == 2:
				known = (
					(parts[0] == "tile" and registries.tile(parts[1]) != null)
					or (
						parts[0] == "structure"
						and registries.structure(parts[1]) != null
					)
				)
			_require(
				errors, known,
				"features.harvesting.reward_history.%s contains unknown reward '%s'"
				% [collection_id, token]
			)
		_require(
			errors, int((entry as Dictionary).get("rare_misses", 0)) >= 0,
			"features.harvesting.reward_history.%s.rare_misses cannot be negative"
			% collection_id
		)


static func _validate_visitors(
	errors: PackedStringArray,
	raw: Variant,
	registries: Registries
) -> void:
	if not raw is Dictionary:
		errors.append("features.visitors must be an object")
		return
	var data: Dictionary = raw
	if data.is_empty():
		return
	var program_id := String(data.get("program_id", ""))
	_require(
		errors, registries.visitor_program(program_id) != null,
		"features.visitors.program_id references missing visitor program '%s'"
		% program_id
	)
	var event: Variant = data.get("current_event", {})
	if not event is Dictionary:
		errors.append("features.visitors.current_event must be an object")
		return
	if (event as Dictionary).is_empty():
		return
	var presentation_id := String((event as Dictionary).get("presentation_id", ""))
	_require(
		errors, registries.visitor_presentation(presentation_id) != null,
		"features.visitors.current_event references missing visitor presentation '%s'"
		% presentation_id
	)
	var reward: Variant = (event as Dictionary).get("reward", {})
	if not reward is Dictionary:
		errors.append("features.visitors.current_event.reward must be an object")
		return
	var kind := String((reward as Dictionary).get("kind", ""))
	var content_id := String((reward as Dictionary).get("id", ""))
	var known_reward := (
		(kind == "tile" and registries.tile(content_id) != null)
		or (kind == "structure" and registries.structure(content_id) != null)
	)
	_require(
		errors, known_reward and int((reward as Dictionary).get("amount", 0)) > 0,
		"features.visitors.current_event.reward references missing %s '%s'"
		% [kind, content_id]
	)


static func _validate_onboarding(
	errors: PackedStringArray,
	raw: Variant,
	registries: Registries,
	known_instance_ids: Dictionary
) -> void:
	if not raw is Dictionary:
		errors.append("onboarding must be an object")
		return
	var data: Dictionary = raw
	var stage := String(data.get("stage", OnboardingState.COMPLETE))
	_require(
		errors, stage in OnboardingState.STAGES,
		"onboarding.stage '%s' is not supported" % stage
	)
	var guided_kind := String(data.get("guided_kind", ""))
	var guided_id := String(data.get("guided_id", ""))
	if guided_kind != "" or guided_id != "":
		var known_guided := (
			(guided_kind == "tile" and registries.tile(guided_id) != null)
			or (guided_kind == "structure" and registries.structure(guided_id) != null)
		)
		_require(
			errors, known_guided,
			"onboarding guided piece references missing %s '%s'"
			% [guided_kind, guided_id]
		)
	var starter_iid := int(data.get("starter_tree_instance_id", 0))
	if starter_iid > 0 and stage in [
		OnboardingState.PLACE_TREE,
		OnboardingState.WAIT_TREE,
		OnboardingState.HARVEST_TREE,
	]:
		_require(
			errors, known_instance_ids.has(starter_iid),
			"onboarding.starter_tree_instance_id references missing iid %d"
			% starter_iid
		)


static func _validate_fishing(
	errors: PackedStringArray,
	raw: Variant,
	registries: Registries
) -> void:
	if not raw is Dictionary:
		errors.append("features.fishing must be an object")
		return
	var data: Dictionary = raw
	if data.is_empty():
		return
	var pouch: Dictionary = data.get("pouch", {})
	for index in (pouch.get("slots", []) as Array).size():
		var spirit_id := String(pouch["slots"][index])
		_require(
			errors, registries.spirit(spirit_id) != null,
			"features.fishing.pouch.slots[%d] references missing spirit '%s'"
			% [index, spirit_id]
		)
	var basket: Dictionary = data.get("basket", {})
	for index in (basket.get("hauls", []) as Array).size():
		var raw_haul: Variant = basket["hauls"][index]
		if not raw_haul is Dictionary:
			errors.append("features.fishing.basket.hauls[%d] must be an object" % index)
			continue
		for entry_index in ((raw_haul as Dictionary).get("entries", []) as Array).size():
			var entry: Dictionary = raw_haul["entries"][entry_index]
			var form := String(entry.get("form", ""))
			var building_id := String(entry.get("building_id", ""))
			var known := (
				(form == "tile_bundle" and registries.tile(building_id) != null)
				or (form == "model" and registries.structure(building_id) != null)
				or (form == "keepsake" and registries.keepsake(building_id) != null)
			)
			_require(
				errors, known,
				"features.fishing.basket.hauls[%d].entries[%d] references missing %s '%s'"
				% [index, entry_index, form, building_id]
			)


## Archived v1/v2 blobs are deliberately not validated: they preserve retired
## payloads verbatim and reference nothing the live catalog must still ship.
static func _validate_progression(
	errors: PackedStringArray,
	raw: Variant,
	registries: Registries
) -> void:
	if not raw is Dictionary:
		errors.append("progression must be an object")
		return
	var data: Dictionary = raw
	_require(
		errors, int(data.get("version", 0)) == 4,
		"progression.version must be 4"
	)
	_require(
		errors, not data.has("void_exchange"),
		"progression.void_exchange was retired in v4"
	)
	var discovery: Dictionary = data.get("discovery", {})
	for index in (discovery.get("pending", []) as Array).size():
		var entry: Variant = discovery["pending"][index]
		if not entry is Dictionary:
			errors.append("progression.discovery.pending[%d] must be an object" % index)
			continue
		var kind := String(entry.get("kind", ""))
		var content_id := String(entry.get("id", ""))
		var known := (
			(kind == "tile" and registries.tile(content_id) != null)
			or (kind == "structure" and registries.structure(content_id) != null)
		)
		_require(
			errors, known,
			"progression.discovery.pending[%d] references missing %s '%s'"
			% [index, kind, content_id]
		)
	_validate_array_ids(
		errors, data.get("milestones", {}).get("claimed", []), registries.milestones,
		"progression.milestones.claimed"
	)
	_validate_dictionary_ids(
		errors, data.get("activity_actions", {}), registries.skills,
		"progression.activity_actions"
	)


static func _validate_landmarks(
	errors: PackedStringArray,
	raw: Variant,
	registries: Registries
) -> void:
	if not raw is Dictionary:
		errors.append("landmarks must be an object")
		return
	var data: Dictionary = raw
	for index in (data.get("active", []) as Array).size():
		var state: Dictionary = data["active"][index]
		var landmark_id := String(state.get("id", ""))
		_require(
			errors, registries.landmark(landmark_id) != null,
			"landmarks.active[%d] references missing landmark '%s'"
			% [index, landmark_id]
		)
		for enemy_index in (state.get("enemies", []) as Array).size():
			var slot_id := String(state["enemies"][enemy_index])
			var enemy_id := slot_id.get_slice(":", 0)
			_require(
				errors, registries.enemy(enemy_id) != null,
				"landmarks.active[%d].enemies[%d] references missing enemy '%s'"
				% [index, enemy_index, enemy_id]
			)
	_validate_dictionary_ids(
		errors, data.get("resolved", {}), registries.landmarks,
		"landmarks.resolved"
	)


static func _validate_combat(
	errors: PackedStringArray,
	raw: Variant,
	registries: Registries
) -> void:
	if not raw is Dictionary:
		errors.append("combat must be an object")
		return
	var enemy_health: Variant = (raw as Dictionary).get("enemy_health", {})
	if not enemy_health is Dictionary:
		errors.append("combat.enemy_health must be an object")
		return
	for runtime_key: String in enemy_health:
		var landmark_id := runtime_key.get_slice("|", 0)
		var slot_id := runtime_key.get_slice("|", 1)
		var enemy_id := slot_id.get_slice(":", 0)
		_require(
			errors,
			registries.landmark(landmark_id) != null
			and registries.enemy(enemy_id) != null,
			"combat.enemy_health key '%s' references retired content" % runtime_key
		)


static func _validate_collection(
	errors: PackedStringArray,
	raw: Variant,
	registries: Registries
) -> void:
	if not raw is Dictionary:
		errors.append("collection must be an object")
		return
	var entries: Variant = (raw as Dictionary).get("entries", {})
	if not entries is Dictionary:
		errors.append("collection.entries must be an object")
		return
	var category_kinds := {
		"gear": "items",
		"tiles": "tiles",
		"structures": "structures",
		"landmarks": "landmarks",
		"creatures": "enemies",
		"keepsakes": "keepsakes",
	}
	for key: String in entries:
		var category := key.get_slice("/", 0)
		if not category_kinds.has(category):
			continue
		var content_id := key.trim_prefix(category + "/")
		_require(
			errors,
			registries.has_definition(category_kinds[category], content_id),
			"collection.entries references missing %s '%s'"
			% [category_kinds[category], content_id]
		)


static func _validate_array_ids(
	errors: PackedStringArray,
	raw: Variant,
	definitions: Dictionary,
	field: String
) -> void:
	if not raw is Array:
		errors.append("%s must be an array" % field)
		return
	for index in raw.size():
		var content_id := String(raw[index])
		_require(
			errors, definitions.has(content_id),
			"%s[%d] references missing content '%s'"
			% [field, index, content_id]
		)


static func _validate_dictionary_values(
	errors: PackedStringArray,
	raw: Variant,
	definitions: Dictionary,
	field: String
) -> void:
	if not raw is Dictionary:
		errors.append("%s must be an object" % field)
		return
	for key: String in raw:
		var content_id := String(raw[key])
		_require(
			errors, definitions.has(content_id),
			"%s.%s references missing content '%s'" % [field, key, content_id]
		)


static func _validate_optional_id(
	errors: PackedStringArray,
	raw: Variant,
	definitions: Dictionary,
	field: String,
	optional := true
) -> void:
	var content_id := String(raw)
	if optional and content_id == "":
		return
	_require(
		errors, definitions.has(content_id),
		"%s references missing content '%s'" % [field, content_id]
	)


static func _validate_dictionary_ids(
	errors: PackedStringArray,
	raw: Variant,
	definitions: Dictionary,
	field: String
) -> void:
	if not raw is Dictionary:
		errors.append("%s must be an object" % field)
		return
	for content_id: String in raw:
		_require(
			errors, definitions.has(content_id),
			"%s references missing content '%s'" % [field, content_id]
		)


static func _require(
	errors: PackedStringArray,
	condition: bool,
	message: String
) -> void:
	if not condition:
		errors.append(message)
