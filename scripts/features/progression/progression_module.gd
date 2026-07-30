class_name ProgressionModule
extends RefCounted
## Composition root for progression v2: Inspiration domains, the well's
## Vision bank, honest three-choice reveals, the refund meter, the shrine,
## and milestone rewards. GameCore owns exactly one of these; scene-side
## systems subscribe to the subsystems' signals and never own state.
##
## Progression v1 (XP levels, Land Parcels, Pattern Dust) is archived in
## legacy/progression_v1/ and its save payloads are preserved verbatim under
## `archived_v1` so a future levels revival loses nothing.

var registries: Registries
var inspiration: InspirationSystem
var shrine: ShrineSystem
var visions: VisionSystem
var refunds: RefundSystem
var milestones: MilestoneSystem

var activity_actions: Dictionary = {}   # skill_id -> lifetime actions
var archived_v1: Dictionary = {}        # untouched v1 save payloads


func _init(
	regs: Registries,
	rng: RngService,
	grid: WorldGrid,
	stock: StockManager,
	collection: CollectionManager,
	equipment: EquipmentManager
) -> void:
	registries = regs
	shrine = ShrineSystem.new(regs, collection)
	inspiration = InspirationSystem.new(regs)
	visions = VisionSystem.new(regs, rng, grid, stock, collection, shrine)
	refunds = RefundSystem.new(regs, stock, visions)
	milestones = MilestoneSystem.new(regs, stock, equipment, collection)
	# Journal discoveries can complete journal-page milestones on their own
	# (e.g. a rare catch finishing a page outside any action flow).
	collection.discovered.connect(func(_category: String, _id: String):
		milestones.check_all(activity_actions)
	)


## One completed activity action: counts practice, pays Inspiration into the
## activity's domain, and re-checks milestones. Returns presentation
## feedback: {domain_id, amount, added, banked, blocked}.
func on_activity_action(skill_id: String) -> Dictionary:
	var domain := registries.domain_for_activity(skill_id)
	if domain == null:
		return {"domain_id": "", "amount": 0.0, "added": false, "banked": false, "blocked": false}
	activity_actions[skill_id] = int(activity_actions.get(skill_id, 0)) + 1
	var amount := registries.tunef("inspiration_per_action", 12.0)
	var feedback := inspiration.add(domain.id, amount)
	feedback["domain_id"] = domain.id
	feedback["amount"] = amount
	milestones.check_all(activity_actions)
	return feedback


func actions_done(skill_id: String) -> int:
	return int(activity_actions.get(skill_id, 0))


## Earning gate for activity loops: the current action always completes,
## the next one refuses while the well is full.
func can_earn() -> bool:
	return inspiration.can_earn()


func is_activity_playable(skill_id: String) -> bool:
	var definition := registries.skill(skill_id)
	return definition != null and not definition.future


func is_recipe_unlocked(recipe: Defs.RecipeDefinition) -> bool:
	return milestones.is_recipe_unlocked(recipe)


func speed_multiplier() -> float:
	return inspiration.speed_multiplier()


func to_save_dict() -> Dictionary:
	return {
		"inspiration": inspiration.to_save_dict(),
		"visions": visions.to_save_dict(),
		"refunds": refunds.to_save_dict(),
		"shrine": shrine.to_save_dict(),
		"milestones": milestones.to_save_dict(),
		"activity_actions": activity_actions.duplicate(),
		"archived_v1": archived_v1.duplicate(true),
	}


func from_save_dict(data: Dictionary) -> void:
	inspiration.from_save_dict(data.get("inspiration", {}))
	visions.from_save_dict(data.get("visions", {}))
	refunds.from_save_dict(data.get("refunds", {}))
	shrine.from_save_dict(data.get("shrine", {}))
	milestones.from_save_dict(data.get("milestones", {}))
	activity_actions.clear()
	var saved_actions: Dictionary = data.get("activity_actions", {})
	for skill_id: String in saved_actions:
		if registries.skill(skill_id) != null:
			activity_actions[skill_id] = int(saved_actions[skill_id])
	archived_v1 = data.get("archived_v1", {}).duplicate(true)


## Pre-validation migration of a whole v1 save payload, called by GameCore
## BEFORE CurrentSaveValidator sees the data. Transforms retired shapes into
## v2 and preserves every v1 payload verbatim under progression.archived_v1.
## The validator then applies its normal strictness to the migrated result.
static func migrate_save_payload(data: Dictionary) -> Dictionary:
	if data.has("progression") or (not data.has("skills") and not data.has("parcels")):
		return data
	var migrated := data.duplicate(true)
	var archived := {}
	if migrated.has("skills"):
		archived["skills"] = migrated["skills"]
		migrated.erase("skills")
	if migrated.has("parcels"):
		archived["parcels"] = migrated["parcels"]
		migrated.erase("parcels")
	var progression := {"archived_v1": archived}
	# A reveal pending at migration time is honored: its tile options become
	# a pending Vision, so the promised choice is never lost.
	var pending_options: Array = (archived.get("parcels", {}) as Dictionary).get("pending_options", [])
	if not pending_options.is_empty():
		var pending: Array = []
		for raw_tile_id in pending_options:
			pending.append({"kind": "tile", "id": String(raw_tile_id)})
		progression["visions"] = {"pending": pending, "pending_domain": "", "pending_wild": false, "claims": 1}
	# Lifetime action counts continue live (they still drive milestones).
	var actions: Dictionary = (archived.get("skills", {}) as Dictionary).get("actions", {})
	if not actions.is_empty():
		progression["activity_actions"] = actions.duplicate()
	migrated["progression"] = progression
	# Retired currencies leave the inventory; their counts stay readable in
	# the archived payload above via the original inventory snapshot below.
	var inventory: Dictionary = migrated.get("inventory", {})
	var counts: Dictionary = inventory.get("counts", {})
	var retired_items := ["pattern_dust", "parcel_wild", "parcel_meadow", "parcel_grove", "parcel_stone", "parcel_winter"]
	var removed := {}
	for item_id: String in retired_items:
		if counts.has(item_id):
			removed[item_id] = counts[item_id]
			counts.erase(item_id)
	if not removed.is_empty():
		archived["inventory_counts"] = removed
	# A ferry payload mid-delivery re-schedules cleanly as a fresh arrival.
	var arrivals: Dictionary = migrated.get("arrivals", {})
	if not (arrivals.get("payload", {}) as Dictionary).is_empty():
		archived["arrival_payload"] = arrivals["payload"]
		arrivals["payload"] = {}
		arrivals["state"] = "idle"
	return migrated
