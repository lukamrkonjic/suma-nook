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
			_require(
				errors, registries.structure(structure_id) != null,
				"grid.cells[%d].structs[%d] references missing structure '%s'"
				% [index, structure_index, structure_id]
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
		_require(
			errors, registries.structure(structure_id) != null,
			"stock.structure_instances[%d] references missing structure '%s'"
			% [index, structure_id]
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
	return errors


## The archived_v1 blob is deliberately NOT validated: it preserves retired
## v1 payloads verbatim for a possible levels revival and references nothing
## the live catalog must still ship.
static func _validate_progression(
	errors: PackedStringArray,
	raw: Variant,
	registries: Registries
) -> void:
	if not raw is Dictionary:
		errors.append("progression must be an object")
		return
	var data: Dictionary = raw
	var inspiration: Dictionary = data.get("inspiration", {})
	_validate_dictionary_ids(
		errors, inspiration.get("meters", {}), registries.inspiration_domains,
		"progression.inspiration.meters"
	)
	_validate_array_ids(
		errors, inspiration.get("banked", []), registries.inspiration_domains,
		"progression.inspiration.banked"
	)
	var visions: Dictionary = data.get("visions", {})
	for index in (visions.get("pending", []) as Array).size():
		var entry: Variant = visions["pending"][index]
		if not entry is Dictionary:
			errors.append("progression.visions.pending[%d] must be an object" % index)
			continue
		var kind := String(entry.get("kind", ""))
		var content_id := String(entry.get("id", ""))
		var known := (
			(kind == "tile" and registries.tile(content_id) != null)
			or (kind == "structure" and registries.structure(content_id) != null)
		)
		_require(
			errors, known,
			"progression.visions.pending[%d] references missing %s '%s'"
			% [index, kind, content_id]
		)
	_validate_optional_id(
		errors, visions.get("pending_domain", ""), registries.inspiration_domains,
		"progression.visions.pending_domain"
	)
	var refunds: Dictionary = data.get("refunds", {})
	_validate_dictionary_ids(
		errors, refunds.get("meters", {}), registries.inspiration_domains,
		"progression.refunds.meters"
	)
	_validate_dictionary_ids(
		errors, refunds.get("coins", {}), registries.inspiration_domains,
		"progression.refunds.coins"
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
