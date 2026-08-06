class_name ProgressionModule
extends RefCounted
## Composition root for progression v4: lifetime practice, milestones, and the
## ferry's periodic discovery gift. Building rewards now arrive exclusively
## through the fishing feature module; this class only counts activity and
## publishes narrow completion events other features may adapt.

## Emitted when an activity finishes a full source cycle (a tree rests, a
## future stone seam is worked out). Adapters — not this module — decide what
## a completed cycle is worth.
signal activity_cycle_completed(skill_id: String)

var registries: Registries
var discovery: DiscoverySystem
var milestones: MilestoneSystem

var activity_actions: Dictionary = {}
var archived_v1: Dictionary = {}
var archived_v2: Dictionary = {}
var archived_v3: Dictionary = {}


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
	milestones = MilestoneSystem.new(regs, stock, equipment, collection)
	collection.discovered.connect(func(_category: String, _id: String):
		milestones.check_all(activity_actions)
	)


## One ordinary activity action (a chop, a pond cast). Counts practice only —
## activities no longer roll placeable rewards directly.
func on_activity_action(skill_id: String) -> void:
	activity_actions[skill_id] = int(activity_actions.get(skill_id, 0)) + 1
	milestones.check_all(activity_actions)


## A full source cycle completed (tree rested, seam exhausted). Publishes the
## narrow event Spirit adapters listen to.
func on_activity_cycle_completed(skill_id: String) -> void:
	activity_cycle_completed.emit(skill_id)


## One fishing haul physically committed to the Catch Basket.
func on_fishing_haul_committed() -> void:
	activity_actions["fishing"] = int(activity_actions.get("fishing", 0)) + 1
	milestones.check_all(activity_actions)


func actions_done(skill_id: String) -> int:
	return int(activity_actions.get(skill_id, 0))


func is_activity_playable(skill_id: String) -> bool:
	var definition := registries.skill(skill_id)
	return definition != null and not definition.future


func is_recipe_unlocked(recipe: Defs.RecipeDefinition) -> bool:
	return milestones.is_recipe_unlocked(recipe)


func to_save_dict() -> Dictionary:
	return {
		"version": 4,
		"discovery": discovery.to_save_dict(),
		"milestones": milestones.to_save_dict(),
		"activity_actions": activity_actions.duplicate(),
		"archived_v1": archived_v1.duplicate(true),
		"archived_v2": archived_v2.duplicate(true),
		"archived_v3": archived_v3.duplicate(true),
	}


func from_save_dict(data: Dictionary) -> void:
	discovery.from_save_dict(data.get("discovery", {}))
	milestones.from_save_dict(data.get("milestones", {}))
	activity_actions.clear()
	for skill_id: String in data.get("activity_actions", {}):
		if registries.skill(skill_id) != null:
			activity_actions[skill_id] = int(data["activity_actions"][skill_id])
	archived_v1 = data.get("archived_v1", {}).duplicate(true)
	archived_v2 = data.get("archived_v2", {}).duplicate(true)
	archived_v3 = data.get("archived_v3", {}).duplicate(true)


## Runs before strict validation. Retired progression generations are archived
## verbatim; v1/v2 first migrate through the historical v3 shape, then v3
## migrates to v4 (fishing rework: the three-spare exchange refunds its
## partial offerings and local skill discovery retires).
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
	_migrate_v3_to_v4(migrated)
	return migrated


## v3 → v4: the fishing rework. Deterministic order, loss-proof:
## 1. Partial exchange offerings refund to stock (they were real removed
##    copies), sorted by key so the result never depends on hash order.
## 2. Local discovery progress retires (it was progress, not currency).
## 3. first_void_discovery_done moves to the fishing feature payload.
## 4. Collectible-fish journal entries are removed with the fish page.
## 5. Onboarding stages that taught local discovery complete themselves.
## No bait, hook, or reservoir state ever shipped, so there is nothing to
## convert into Spirits.
static func _migrate_v3_to_v4(data: Dictionary) -> void:
	var progression: Dictionary = data.get("progression", {})
	if int(progression.get("version", 0)) != 3:
		return
	var archived_v3 := {}
	var exchange: Dictionary = progression.get("void_exchange", {})
	var offerings: Dictionary = exchange.get("offerings", {})
	if not offerings.is_empty():
		archived_v3["void_exchange"] = exchange.duplicate(true)
		var keys: Array = offerings.keys()
		keys.sort()
		for key: String in keys:
			var parts := key.split(":", false, 1)
			if parts.size() != 2:
				continue
			var count := clampi(int(offerings[key]), 0, 2)
			if count <= 0:
				continue
			_refund_to_stock(data, parts[0], parts[1], count)
	progression.erase("void_exchange")
	var discovery: Dictionary = progression.get("discovery", {})
	if discovery.has("progress"):
		archived_v3["discovery_progress"] = discovery.get("progress", {})
		discovery.erase("progress")
	var first_done := bool(discovery.get("first_void_discovery_done", false))
	discovery.erase("first_void_discovery_done")
	progression["discovery"] = discovery
	var features: Dictionary = data.get("features", {})
	var fishing: Dictionary = features.get("fishing", {})
	if not fishing.has("first_catch_done"):
		fishing["first_catch_done"] = first_done
	features["fishing"] = fishing
	data["features"] = features
	_scrub_fish_collection(data, archived_v3)
	var onboarding: Dictionary = data.get("onboarding", {})
	if String(onboarding.get("stage", "")) in ["tend_tree", "place_biome_discovery"]:
		onboarding["stage"] = "complete"
		onboarding["guided_kind"] = ""
		onboarding["guided_id"] = ""
	if not archived_v3.is_empty():
		progression["archived_v3"] = archived_v3
	progression["version"] = 4


static func _refund_to_stock(
	data: Dictionary,
	kind: String,
	content_id: String,
	count: int
) -> void:
	if kind not in ["tile", "structure"] or content_id == "":
		return
	if not data.has("stock"):
		data["stock"] = {}
	var stock: Dictionary = data["stock"]
	var bucket_name := "tiles" if kind == "tile" else "structures"
	var bucket: Dictionary = stock.get(bucket_name, {})
	bucket[content_id] = int(bucket.get(content_id, 0)) + count
	stock[bucket_name] = bucket


## Fish were never catchable in the new design: released-fish journal records
## retire with the fishing rework. The rest of the journal is untouched.
static func _scrub_fish_collection(data: Dictionary, archived_v3: Dictionary) -> void:
	var collection: Dictionary = data.get("collection", {})
	var entries: Dictionary = collection.get("entries", {})
	var removed := {}
	for key: String in entries.keys():
		if key.begins_with("fish/"):
			removed[key] = entries[key]
			entries.erase(key)
	if not removed.is_empty():
		archived_v3["fish_collection"] = removed


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
		"place_tree", "wait_tree", "harvest_tree", "place_forest_reward",
		"wait_visitor", "place_visitor_reward",
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
