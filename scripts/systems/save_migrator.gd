class_name SaveMigrator
extends RefCounted
## Pure raw-save migration boundary.
##
## Structural migrations run before any manager hydrates. Content IDs are then
## canonicalized across every persisted subsystem, and compatibility
## definitions are registered for genuinely missing content so it remains
## visible/recoverable instead of being deleted.

var registries: Registries
var compatibility: ContentCompatibility


func _init(regs: Registries, compat: ContentCompatibility) -> void:
	registries = regs
	compatibility = compat


func migrate(raw: Dictionary) -> Dictionary:
	var data: Dictionary = raw.duplicate(true)
	var warnings: PackedStringArray = []
	var changed := false
	var version := int(data.get("save_version", 1))
	var target_version := registries.tunei("save_version", 1)

	while version < target_version:
		match version:
			1:
				_migrate_v1_to_v2(data)
			2:
				_migrate_v2_to_v3(data)
			3:
				_migrate_v3_to_v4(data)
			4:
				_migrate_v4_to_v5(data)
			5:
				_migrate_v5_to_v6(data)
			6:
				_migrate_v6_to_v7(data)
			7:
				_migrate_v7_to_v8(data)
			_:
				warnings.append("no explicit migration for save version %d" % version)
		version += 1
		data["save_version"] = version
		changed = true

	if _rewrite_content_ids(data):
		changed = true
	if int(data.get("content_revision", 0)) != compatibility.revision:
		data["content_revision"] = compatibility.revision
		changed = true
	_register_missing_compatibility_definitions(data, warnings)

	return {"data": data, "changed": changed, "warnings": warnings}


func _migrate_v1_to_v2(data: Dictionary) -> void:
	if not data.has("legacy_inventory"):
		data["legacy_inventory"] = data.get("inventory", {}).duplicate(true)
	data["inventory"] = {}
	var grid: Dictionary = data.get("grid", {})
	var cells: Array = grid.get("cells", [])
	for entry: Dictionary in cells:
		if (
			int(entry.get("e", 0)) == 0
			and bool(entry.get("starter", false))
			and Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
				in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
		):
			entry["tile"] = "tile_open_water"
			entry["rot"] = 0
			entry["landmark"] = ""
			entry["structs"] = []
			entry["a_done"] = 0
			entry["a_rest"] = false
			entry["a_regen"] = 0.0
			entry["a_up"] = 0
	var next_iid := int(grid.get("next_iid", 1))
	next_iid = _restore_starter_props(cells, Vector2i(-1, 0), [
		["struct_pine", 3],
	], next_iid)
	next_iid = _restore_starter_props(cells, Vector2i(1, 0), [
		["struct_chest", 2],
	], next_iid)
	grid["next_iid"] = next_iid
	data["grid"] = grid


func _migrate_v2_to_v3(_data: Dictionary) -> void:
	# Version 3 formalized the legacy/active inventory split. Version 2 saves
	# already contain the required fields, so this step is deliberately pure.
	pass


func _migrate_v3_to_v4(data: Dictionary) -> void:
	data["content_revision"] = compatibility.revision


func _migrate_v4_to_v5(data: Dictionary) -> void:
	# Version 5 introduces persistent object-support edges. Existing objects are
	# tile-rooted, so the migration is lossless and intentionally conservative.
	var grid: Dictionary = data.get("grid", {})
	for cell: Dictionary in grid.get("cells", []):
		for structure: Dictionary in cell.get("structs", []):
			if not structure.has("parent"):
				structure["parent"] = 0
			if not structure.has("support"):
				structure["support"] = ""


func _migrate_v5_to_v6(data: Dictionary) -> void:
	# Version 6 separates resource-bearing objects from their terrain. Legacy
	# grove runtime is transferred onto a real tree instance so progress and
	# ownership survive; the previously authored starter plants return to stock.
	var grid: Dictionary = data.get("grid", {})
	var cells: Array = grid.get("cells", [])
	var next_iid := int(grid.get("next_iid", 1))
	for cell: Dictionary in cells:
		for structure: Dictionary in cell.get("structs", []):
			_ensure_structure_anchor_fields(structure)
			next_iid = maxi(next_iid, int(structure.get("iid", 0)) + 1)

	var stock: Dictionary = data.get("stock", {})
	var stored_structures: Dictionary = stock.get("structures", {})
	for cell: Dictionary in cells:
		var structures: Array = cell.get("structs", [])
		if (
			bool(cell.get("starter", false))
			and int(cell.get("e", 0)) == 0
			and int(cell.get("x", 0)) == -1
			and int(cell.get("y", 0)) == 0
		):
			var retained: Array = []
			for structure: Dictionary in structures:
				var structure_id := String(structure.get("id", ""))
				var is_legacy_starter_plant := (
					int(structure.get("parent", 0)) == 0
					and (
						(structure_id == "struct_pine" and int(structure.get("socket", 0)) == 3)
						or (structure_id == "struct_bush" and int(structure.get("socket", 0)) == 2)
					)
				)
				if is_legacy_starter_plant:
					stored_structures[structure_id] = (
						int(stored_structures.get(structure_id, 0)) + 1
					)
				else:
					retained.append(structure)
			structures = retained
			cell["structs"] = structures

		if not String(cell.get("tile", "")).begins_with("tile_grove_"):
			continue
		var has_tree := false
		for structure: Dictionary in structures:
			var definition := registries.structure(String(structure.get("id", "")))
			if definition != null and definition.anchor_id == "grove_anchor":
				has_tree = true
				break
		if not has_tree:
			var tree := {
				"iid": next_iid,
				"id": "struct_pine",
				"socket": 1,
				"rot": 0,
				"parent": 0,
				"support": "",
				"a_done": int(cell.get("a_done", 0)),
				"a_rest": bool(cell.get("a_rest", false)),
				"a_regen": float(cell.get("a_regen", 0.0)),
				"a_up": int(cell.get("a_up", 0)),
			}
			# Give the migrated resource object first claim on the tile's direct
			# decor slot. If an old save also decorated this grove, reconciliation
			# returns that decoration to stock instead of discarding tree progress.
			structures.push_front(tree)
			cell["structs"] = structures
			next_iid += 1
		cell["a_done"] = 0
		cell["a_rest"] = false
		cell["a_regen"] = 0.0
		cell["a_up"] = 0

	stock["structures"] = stored_structures
	data["stock"] = stock
	grid["cells"] = cells
	grid["next_iid"] = next_iid
	data["grid"] = grid


func _migrate_v6_to_v7(data: Dictionary) -> void:
	# The northern dock used to be an unpickable scene decoration. Version 7
	# makes it authoritative world data without duplicating an existing dock.
	var grid: Dictionary = data.get("grid", {})
	var cells: Array = grid.get("cells", [])
	var has_dock := false
	var middle_water: Dictionary = {}
	var next_iid := int(grid.get("next_iid", 1))
	for cell: Dictionary in cells:
		for structure: Dictionary in cell.get("structs", []):
			next_iid = maxi(next_iid, int(structure.get("iid", 0)) + 1)
			if String(structure.get("id", "")) == "struct_dock":
				has_dock = true
		if (
			int(cell.get("e", 0)) == 0
			and int(cell.get("x", 0)) == 0
			and int(cell.get("y", 0)) == -1
			and String(cell.get("tile", "")) == "tile_open_water"
		):
			middle_water = cell
	if not has_dock and not middle_water.is_empty():
		var structures: Array = middle_water.get("structs", [])
		if structures.is_empty():
			structures.append({
				"iid": next_iid,
				"id": "struct_dock",
				"socket": 0,
				"rot": 2,
				"parent": 0,
				"support": "",
				"a_done": 0,
				"a_rest": false,
				"a_regen": 0.0,
				"a_up": 0,
			})
			middle_water["structs"] = structures
			next_iid += 1
	grid["next_iid"] = next_iid
	data["grid"] = grid
	var view: Dictionary = data.get("view", {})
	if is_equal_approx(float(view.get("distance", 40.0)), 40.0):
		view["distance"] = registries.tunef("camera_default_size", 32.0)
	if not view.has("pan"):
		view["pan"] = [0.0, 0.0]
	data["view"] = view


func _migrate_v7_to_v8(data: Dictionary) -> void:
	# Version 8 reduces the horizontal grid footprint from 1.70 m to 1.35 m.
	# Grid content is coordinate-based already; only the player's continuous
	# world-space X/Z needs conversion to remain over the same saved tile.
	const OLD_TILE_SIZE := 1.7
	var new_tile_size := registries.tunef("tile_size", 1.35)
	var horizontal_scale := new_tile_size / OLD_TILE_SIZE
	var profile: Dictionary = data.get("profile", {})
	profile["px"] = float(profile.get("px", 0.0)) * horizontal_scale
	profile["pz"] = float(profile.get("pz", 0.0)) * horizontal_scale
	data["profile"] = profile


func _ensure_structure_anchor_fields(structure: Dictionary) -> void:
	if not structure.has("a_done"):
		structure["a_done"] = 0
	if not structure.has("a_rest"):
		structure["a_rest"] = false
	if not structure.has("a_regen"):
		structure["a_regen"] = 0.0
	if not structure.has("a_up"):
		structure["a_up"] = 0


func _restore_starter_props(
	cells: Array,
	coord: Vector2i,
	props: Array,
	next_iid: int
) -> int:
	for entry: Dictionary in cells:
		if (
			int(entry.get("e", 0)) == 0
			and int(entry.get("x", 0)) == coord.x
			and int(entry.get("y", 0)) == coord.y
		):
			var structures: Array = entry.get("structs", [])
			if not structures.is_empty():
				return next_iid
			for prop: Array in props:
				structures.append({
					"iid": next_iid,
					"id": String(prop[0]),
					"socket": int(prop[1]),
					"rot": 0,
					"parent": 0,
					"support": "",
					"a_done": 0,
					"a_rest": false,
					"a_regen": 0.0,
					"a_up": 0,
				})
				next_iid += 1
			entry["structs"] = structures
			return next_iid
	return next_iid


func _rewrite_content_ids(data: Dictionary) -> bool:
	var changed := false
	var grid: Dictionary = data.get("grid", {})
	for cell: Dictionary in grid.get("cells", []):
		changed = _rewrite_field(cell, "tile", "tiles") or changed
		changed = _rewrite_field(cell, "landmark", "landmarks") or changed
		for structure: Dictionary in cell.get("structs", []):
			changed = _rewrite_field(structure, "id", "structures") or changed

	var stock: Dictionary = data.get("stock", {})
	changed = _rewrite_count_map(stock, "tiles", "tiles") or changed
	changed = _rewrite_count_map(stock, "structures", "structures") or changed
	changed = _rewrite_array(stock, "deeds", "landmarks") or changed

	var inventory: Dictionary = data.get("inventory", {})
	changed = _rewrite_count_map(inventory, "counts", "items") or changed
	if data.get("legacy_inventory", {}) is Dictionary:
		var legacy_inventory: Dictionary = data.get("legacy_inventory", {})
		if legacy_inventory.get("counts", {}) is Dictionary and legacy_inventory.has("counts"):
			changed = _rewrite_count_map(legacy_inventory, "counts", "items") or changed
		else:
			var legacy := {"counts": legacy_inventory}
			if _rewrite_count_map(legacy, "counts", "items"):
				data["legacy_inventory"] = legacy["counts"]
				changed = true

	var equipment: Dictionary = data.get("equipment", {})
	changed = _rewrite_array(equipment, "owned", "items") or changed
	changed = _rewrite_array(equipment, "appearance", "items") or changed
	var equipped: Dictionary = equipment.get("equipped", {})
	for slot: String in equipped.keys():
		var before := String(equipped[slot])
		var after := compatibility.resolve_id("items", before)
		if before != after:
			equipped[slot] = after
			changed = true

	var parcels: Dictionary = data.get("parcels", {})
	changed = _rewrite_field(parcels, "pending_parcel", "parcels") or changed
	changed = _rewrite_array(parcels, "pending_options", "tiles") or changed
	var arrivals: Dictionary = data.get("arrivals", {})
	var payload: Dictionary = arrivals.get("payload", {})
	changed = _rewrite_field(payload, "parcel_id", "parcels") or changed

	var landmarks: Dictionary = data.get("landmarks", {})
	for state: Dictionary in landmarks.get("active", []):
		changed = _rewrite_field(state, "id", "landmarks") or changed
		changed = _rewrite_enemy_slots(state, "enemies") or changed
	changed = _rewrite_count_map(landmarks, "resolved", "landmarks") or changed

	var skills: Dictionary = data.get("skills", {})
	for field in ["xp", "levels", "actions"]:
		changed = _rewrite_count_map(skills, field, "skills") or changed

	var collection: Dictionary = data.get("collection", {})
	var entries: Dictionary = collection.get("entries", {})
	var rewritten_entries := {}
	for raw_key: String in entries:
		var slash := raw_key.find("/")
		if slash < 0:
			rewritten_entries[raw_key] = entries[raw_key]
			continue
		var category := raw_key.left(slash)
		var content_id := raw_key.substr(slash + 1)
		var kind := _collection_kind(category)
		var canonical := compatibility.resolve_id(kind, content_id) if kind != "" else content_id
		var canonical_key := "%s/%s" % [category, canonical]
		if canonical_key != raw_key:
			changed = true
		_merge_collection_entry(rewritten_entries, canonical_key, entries[raw_key])
	collection["entries"] = rewritten_entries

	var combat: Dictionary = data.get("combat", {})
	var health: Dictionary = combat.get("enemy_health", {})
	var rewritten_health := {}
	for slot_id: String in health:
		var canonical_slot := _canonical_enemy_slot(slot_id)
		rewritten_health[canonical_slot] = health[slot_id]
		if canonical_slot != slot_id:
			changed = true
	combat["enemy_health"] = rewritten_health
	return changed


func _rewrite_field(holder: Dictionary, field: String, kind: String) -> bool:
	if not holder.has(field):
		return false
	var before := String(holder[field])
	var after := compatibility.resolve_id(kind, before)
	holder[field] = after
	return before != after


func _rewrite_count_map(holder: Dictionary, field: String, kind: String) -> bool:
	if not holder.has(field) or not holder[field] is Dictionary:
		return false
	var source: Dictionary = holder.get(field, {})
	var target := {}
	var changed := false
	for raw_id: String in source:
		var canonical := compatibility.resolve_id(kind, raw_id)
		target[canonical] = int(target.get(canonical, 0)) + int(source[raw_id])
		if canonical != raw_id:
			changed = true
	holder[field] = target
	return changed


func _rewrite_array(holder: Dictionary, field: String, kind: String) -> bool:
	if not holder.has(field) or not holder[field] is Array:
		return false
	var target: Array = []
	var changed := false
	for raw_id in holder.get(field, []):
		var before := String(raw_id)
		var after := compatibility.resolve_id(kind, before)
		target.append(after)
		if after != before:
			changed = true
	holder[field] = target
	return changed


func _rewrite_enemy_slots(holder: Dictionary, field: String) -> bool:
	if not holder.has(field) or not holder[field] is Array:
		return false
	var target: Array = []
	var changed := false
	for raw_slot in holder.get(field, []):
		var before := String(raw_slot)
		var after := _canonical_enemy_slot(before)
		target.append(after)
		if before != after:
			changed = true
	holder[field] = target
	return changed


func _canonical_enemy_slot(slot_id: String) -> String:
	var enemy_id := slot_id.get_slice(":", 0)
	var suffix := slot_id.trim_prefix(enemy_id)
	return compatibility.resolve_id("enemies", enemy_id) + suffix


func _collection_kind(category: String) -> String:
	match category:
		"tiles": return "tiles"
		"structures": return "structures"
		"gear": return "items"
		"landmarks": return "landmarks"
		"enemies": return "enemies"
	return ""


func _merge_collection_entry(target: Dictionary, key: String, raw_entry: Variant) -> void:
	if not raw_entry is Dictionary:
		target[key] = raw_entry
		return
	var incoming: Dictionary = raw_entry
	if not target.has(key):
		target[key] = incoming.duplicate(true)
		return
	var existing: Dictionary = target[key]
	existing["count"] = int(existing.get("count", 0)) + int(incoming.get("count", 0))
	existing["placed"] = int(existing.get("placed", 0)) + int(incoming.get("placed", 0))
	var existing_time := String(existing.get("first_time", ""))
	var incoming_time := String(incoming.get("first_time", ""))
	if existing_time == "" or (incoming_time != "" and incoming_time < existing_time):
		existing["first_time"] = incoming_time


func _register_missing_compatibility_definitions(
	data: Dictionary,
	warnings: PackedStringArray
) -> void:
	var found := {
		"tiles": {},
		"structures": {},
		"items": {},
		"parcels": {},
		"landmarks": {},
		"enemies": {},
		"skills": {},
	}
	for cell: Dictionary in (data.get("grid", {}) as Dictionary).get("cells", []):
		_found(found, "tiles", String(cell.get("tile", "")))
		_found(found, "landmarks", String(cell.get("landmark", "")))
		for structure: Dictionary in cell.get("structs", []):
			_found(found, "structures", String(structure.get("id", "")))
	var stock: Dictionary = data.get("stock", {})
	for content_id in (stock.get("tiles", {}) as Dictionary).keys():
		_found(found, "tiles", String(content_id))
	for content_id in (stock.get("structures", {}) as Dictionary).keys():
		_found(found, "structures", String(content_id))
	for content_id in stock.get("deeds", []):
		_found(found, "landmarks", String(content_id))
	for content_id in ((data.get("inventory", {}) as Dictionary).get("counts", {}) as Dictionary).keys():
		_found(found, "items", String(content_id))
	var legacy_inventory: Dictionary = data.get("legacy_inventory", {})
	var legacy_counts: Dictionary = (
		legacy_inventory["counts"]
		if legacy_inventory.has("counts") and legacy_inventory["counts"] is Dictionary
		else legacy_inventory
	)
	for content_id in legacy_counts.keys():
		_found(found, "items", String(content_id))
	var equipment: Dictionary = data.get("equipment", {})
	for content_id in equipment.get("owned", []):
		_found(found, "items", String(content_id))
	for content_id in equipment.get("appearance", []):
		_found(found, "items", String(content_id))
	for content_id in (equipment.get("equipped", {}) as Dictionary).values():
		_found(found, "items", String(content_id))
	var parcels: Dictionary = data.get("parcels", {})
	_found(found, "parcels", String(parcels.get("pending_parcel", "")))
	for content_id in parcels.get("pending_options", []):
		_found(found, "tiles", String(content_id))
	var arrivals: Dictionary = data.get("arrivals", {})
	var payload: Dictionary = arrivals.get("payload", {})
	_found(found, "parcels", String(payload.get("parcel_id", "")))
	var skills: Dictionary = data.get("skills", {})
	for field in ["xp", "levels", "actions"]:
		for content_id in (skills.get(field, {}) as Dictionary).keys():
			_found(found, "skills", String(content_id))
	var landmarks: Dictionary = data.get("landmarks", {})
	for state: Dictionary in landmarks.get("active", []):
		_found(found, "landmarks", String(state.get("id", "")))
		for slot_id in state.get("enemies", []):
			_found(found, "enemies", String(slot_id).get_slice(":", 0))
	for content_id in (landmarks.get("resolved", {}) as Dictionary).keys():
		_found(found, "landmarks", String(content_id))
	var combat: Dictionary = data.get("combat", {})
	for slot_id in (combat.get("enemy_health", {}) as Dictionary).keys():
		_found(found, "enemies", String(slot_id).get_slice(":", 0))
	var entries: Dictionary = (data.get("collection", {}) as Dictionary).get("entries", {})
	for raw_key: String in entries:
		var slash := raw_key.find("/")
		if slash < 0:
			continue
		var category := raw_key.left(slash)
		var kind := _collection_kind(category)
		if kind != "":
			_found(found, kind, raw_key.substr(slash + 1))
	for kind: String in found:
		for content_id: String in found[kind]:
			if not registries.has_definition(kind, content_id):
				registries.ensure_compatibility_definition(kind, content_id)
				warnings.append(
					"preserved missing %s id '%s' through a compatibility definition"
					% [kind, content_id]
				)


func _found(found: Dictionary, kind: String, content_id: String) -> void:
	if content_id != "":
		found[kind][content_id] = true
