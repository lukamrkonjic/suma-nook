class_name ProgressionModule
extends RefCounted
## Composition root for progression v3: immediate discoveries shaped by local
## biomes, the three-spare void exchange, lifetime practice, and milestones.

var registries: Registries
var discovery: DiscoverySystem
var void_exchange: VoidExchangeSystem
var milestones: MilestoneSystem

var activity_actions: Dictionary = {}
var archived_v1: Dictionary = {}
var archived_v2: Dictionary = {}


func _init(
	regs: Registries,
	rng: RngService,
	grid: WorldGrid,
	stock: StockManager,
	collection: CollectionManager,
	equipment: EquipmentManager
) -> void:
	registries = regs
	discovery = DiscoverySystem.new(regs, rng, grid, stock, collection)
	void_exchange = VoidExchangeSystem.new(regs, rng, grid, stock, discovery)
	milestones = MilestoneSystem.new(regs, stock, equipment, collection)
	collection.discovered.connect(func(_category: String, _id: String):
		milestones.check_all(activity_actions)
	)


func on_activity_action(
	skill_id: String,
	coord: Vector2i = Vector2i.ZERO,
	source_structure_id: String = ""
) -> Dictionary:
	activity_actions[skill_id] = int(activity_actions.get(skill_id, 0)) + 1
	var feedback := discovery.record_local_action(
		skill_id,
		coord,
		source_structure_id
	)
	milestones.check_all(activity_actions)
	return feedback


func on_void_fishing_catch() -> Dictionary:
	activity_actions["fishing"] = int(activity_actions.get("fishing", 0)) + 1
	var reward := discovery.discover_void()
	milestones.check_all(activity_actions)
	return {
		"pool_id": "void",
		"progress": 0,
		"required": 1,
		"reward": reward,
	}


func actions_done(skill_id: String) -> int:
	return int(activity_actions.get(skill_id, 0))


func is_activity_playable(skill_id: String) -> bool:
	var definition := registries.skill(skill_id)
	return definition != null and not definition.future


func is_recipe_unlocked(recipe: Defs.RecipeDefinition) -> bool:
	return milestones.is_recipe_unlocked(recipe)


func to_save_dict() -> Dictionary:
	return {
		"version": 3,
		"discovery": discovery.to_save_dict(),
		"void_exchange": void_exchange.to_save_dict(),
		"milestones": milestones.to_save_dict(),
		"activity_actions": activity_actions.duplicate(),
		"archived_v1": archived_v1.duplicate(true),
		"archived_v2": archived_v2.duplicate(true),
	}


func from_save_dict(data: Dictionary) -> void:
	discovery.from_save_dict(data.get("discovery", {}))
	void_exchange.from_save_dict(data.get("void_exchange", {}))
	milestones.from_save_dict(data.get("milestones", {}))
	activity_actions.clear()
	for skill_id: String in data.get("activity_actions", {}):
		if registries.skill(skill_id) != null:
			activity_actions[skill_id] = int(data["activity_actions"][skill_id])
	archived_v1 = data.get("archived_v1", {}).duplicate(true)
	archived_v2 = data.get("archived_v2", {}).duplicate(true)


## Runs before strict validation. Both retired progression generations are
## archived verbatim, pending old rewards become owned discoveries, and the
## removed ritual structures become their ordinary decorative counterparts.
static func migrate_save_payload(data: Dictionary) -> Dictionary:
	var migrated := data.duplicate(true)
	var old_progression: Dictionary = migrated.get("progression", {})
	var is_v3 := int(old_progression.get("version", 0)) >= 3
	if not is_v3:
		var next_progression := {
			"version": 3,
			"activity_actions": {},
			"discovery": {
				"progress": {},
				"pending": [],
				"first_void_discovery_done": false,
			},
			"void_exchange": {"offerings": {}},
			"milestones": old_progression.get("milestones", {}),
			"archived_v1": old_progression.get("archived_v1", {}),
			"archived_v2": old_progression.duplicate(true),
		}
		if not old_progression.is_empty():
			next_progression["activity_actions"] = old_progression.get(
				"activity_actions", {}
			)
			var old_pending: Array = (
				old_progression.get("visions", {}) as Dictionary
			).get("pending", [])
			if not old_pending.is_empty():
				var chosen: Dictionary = old_pending[0]
				_grant_migrated_entry(migrated, chosen)
				next_progression["discovery"]["pending"].append({
					"kind": String(chosen.get("kind", "")),
					"id": String(chosen.get("id", "")),
					"pool_id": "legacy_vision",
					"source": "migration",
					"was_new": false,
				})
		elif migrated.has("skills") or migrated.has("parcels"):
			var archived_v1 := {}
			if migrated.has("skills"):
				archived_v1["skills"] = migrated["skills"]
				next_progression["activity_actions"] = (
					migrated["skills"] as Dictionary
				).get("actions", {})
				migrated.erase("skills")
			if migrated.has("parcels"):
				archived_v1["parcels"] = migrated["parcels"]
				var options: Array = (
					migrated["parcels"] as Dictionary
				).get("pending_options", [])
				if not options.is_empty():
					var entry := {"kind": "tile", "id": String(options[0])}
					_grant_migrated_entry(migrated, entry)
					entry.merge({
						"pool_id": "legacy_parcel",
						"source": "migration",
						"was_new": false,
					})
					next_progression["discovery"]["pending"].append(entry)
				migrated.erase("parcels")
			next_progression["archived_v1"] = archived_v1
		migrated["progression"] = next_progression
	_retire_progression_structures(migrated)
	_retire_old_onboarding(migrated)
	_retire_old_inventory(migrated)
	_retire_old_arrival_payload(migrated)
	return migrated


static func _grant_migrated_entry(data: Dictionary, entry: Dictionary) -> void:
	var kind := String(entry.get("kind", ""))
	var content_id := String(entry.get("id", ""))
	if kind == "" or content_id == "":
		return
	if not data.has("stock"):
		data["stock"] = {}
	var stock: Dictionary = data["stock"]
	var bucket_name := "tiles" if kind == "tile" else "structures"
	var bucket: Dictionary = stock.get(bucket_name, {})
	bucket[content_id] = int(bucket.get(content_id, 0)) + 1
	stock[bucket_name] = bucket


static func _retire_progression_structures(data: Dictionary) -> void:
	var replacements := {
		"struct_wishing_well": "struct_stone_well",
		"struct_shrine": "struct_birdbath",
	}
	var world: Dictionary = data.get("grid", {})
	for raw_cell in world.get("cells", []):
		if raw_cell is Dictionary:
			_replace_cell_structures(raw_cell, replacements)
	var stock: Dictionary = data.get("stock", {})
	var structures: Dictionary = stock.get("structures", {})
	for old_id: String in replacements:
		if structures.has(old_id):
			var new_id: String = replacements[old_id]
			structures[new_id] = int(structures.get(new_id, 0)) + int(structures[old_id])
			structures.erase(old_id)
	for raw_state in stock.get("structure_instances", []):
		if raw_state is Dictionary and replacements.has(String(raw_state.get("id", ""))):
			raw_state["id"] = replacements[String(raw_state["id"])]
	var collection: Dictionary = data.get("collection", {})
	var entries: Dictionary = collection.get("entries", {})
	for old_id: String in replacements:
		var old_key := "structures/%s" % old_id
		if not entries.has(old_key):
			continue
		var new_key := "structures/%s" % replacements[old_id]
		var old_entry: Dictionary = entries[old_key]
		if entries.has(new_key):
			var new_entry: Dictionary = entries[new_key]
			new_entry["count"] = (
				int(new_entry.get("count", 0))
				+ int(old_entry.get("count", 0))
			)
			new_entry["placed"] = (
				int(new_entry.get("placed", 0))
				+ int(old_entry.get("placed", 0))
			)
		else:
			entries[new_key] = old_entry
		entries.erase(old_key)


static func _replace_cell_structures(
	raw_cell: Dictionary,
	replacements: Dictionary
) -> void:
	for raw_structure in raw_cell.get("structs", []):
		if raw_structure is Dictionary:
			var structure_id := String(raw_structure.get("id", ""))
			if replacements.has(structure_id):
				raw_structure["id"] = replacements[structure_id]


static func _retire_old_onboarding(data: Dictionary) -> void:
	var onboarding: Dictionary = data.get("onboarding", {})
	if not onboarding.is_empty() and String(onboarding.get("stage", "")) not in [
		"land_choice", "try_void_fishing", "place_discovery",
		"tend_tree", "place_biome_discovery", "complete",
	]:
		onboarding["stage"] = "complete"


static func _retire_old_inventory(data: Dictionary) -> void:
	var counts: Dictionary = (data.get("inventory", {}) as Dictionary).get("counts", {})
	var removed := {}
	for item_id in [
		"pattern_dust", "parcel_wild", "parcel_meadow",
		"parcel_grove", "parcel_stone", "parcel_winter",
	]:
		if counts.has(item_id):
			removed[item_id] = counts[item_id]
			counts.erase(item_id)
	if not removed.is_empty():
		var progression: Dictionary = data.get("progression", {})
		var archived: Dictionary = progression.get("archived_v1", {})
		archived["inventory_counts"] = removed
		progression["archived_v1"] = archived


static func _retire_old_arrival_payload(data: Dictionary) -> void:
	var arrivals: Dictionary = data.get("arrivals", {})
	var payload: Dictionary = arrivals.get("payload", {})
	if String(payload.get("gift_kind", "")) == "vision":
		payload["gift_kind"] = "discovery"
	elif not payload.is_empty() and String(payload.get("gift_kind", "")) == "":
		var progression: Dictionary = data.get("progression", {})
		var archived: Dictionary = progression.get("archived_v1", {})
		archived["arrival_payload"] = payload.duplicate(true)
		progression["archived_v1"] = archived
		arrivals["payload"] = {}
		arrivals["state"] = "idle"
