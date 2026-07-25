class_name RewardManager
extends RefCounted
## Deterministic loot with explicit generosity rules:
## - seeded, saved RNG streams (no save-scumming, no divergence on reload);
## - tutorial guarantee: the Nth fishing catch always carries a Land Fragment,
##   and reaching Fishing 2 always grants the first Wild Land Parcel;
## - rare pity: every dry rare roll raises the odds until a rare lands;
## - all pity counters are saved and visible in the debug panel.

signal loot_granted(grants: Array)   # [{item_id, count, rare}]

var registries: Registries
var rng: RngService
var inventory: InventoryManager

var rare_dry_streak: Dictionary = {}     # skill_id -> rolls since last rare
var tutorial_catches: int = 0
var tutorial_fragment_granted := false
var first_parcel_granted := false


func _init(regs: Registries, rng_service: RngService, inv: InventoryManager) -> void:
	registries = regs
	rng = rng_service
	inventory = inv


## One completed skill action → guaranteed XP handled by caller; this rolls
## materials + the rare layer. yield_bonus/rare_bonus come from equipment.
func roll_action_loot(skill: Defs.SkillDefinition, yield_bonus := 0.0, rare_bonus := 0.0) -> Array:
	var grants: Array = []
	var table := registries.loot_table(skill.loot_table)
	if table != null and not table.entries.is_empty():
		var entry := rng.weighted("loot_" + skill.id, table.entries)
		var count := rng.randi_range("loot_" + skill.id, int(entry["min"]), int(entry["max"]))
		if yield_bonus > 0.0 and rng.chance("loot_" + skill.id, yield_bonus):
			count += 1
		grants.append({"item_id": entry["item"], "count": count, "rare": false})

	# Tutorial guarantee: early fishing must produce a Land Fragment quickly.
	if skill.id == "fishing":
		tutorial_catches += 1
		if not tutorial_fragment_granted and tutorial_catches >= registries.tunei("tutorial_fragment_by_catch", 3):
			tutorial_fragment_granted = true
			grants.append({"item_id": "land_fragment", "count": 1, "rare": false, "guaranteed": true})

	# Rare layer with pity.
	var rare_table := registries.loot_table(skill.rare_table)
	if rare_table != null and not rare_table.entries.is_empty():
		var dry := int(rare_dry_streak.get(skill.id, 0))
		var pity_max := registries.tunei("rare_pity_max_dry", 9)
		var chance := registries.tunef("rare_roll_chance", 0.22) + rare_bonus
		chance += (float(dry) / pity_max) * 0.5   # pity ramp
		if dry >= pity_max or rng.chance("rare_" + skill.id, chance):
			var entry := rng.weighted("rare_" + skill.id, rare_table.entries)
			var count := rng.randi_range("rare_" + skill.id, int(entry["min"]), int(entry["max"]))
			grants.append({"item_id": entry["item"], "count": count, "rare": bool(entry["rare"])})
			rare_dry_streak[skill.id] = 0
		else:
			rare_dry_streak[skill.id] = dry + 1

	_apply(grants)
	return grants


## Level-up hook: the first Land Parcel is deterministic at Fishing 2.
func on_level_unlocks(unlocks: Array) -> Array:
	var grants: Array = []
	for unlock in unlocks:
		if String(unlock.get("kind", "")) == "parcel":
			var parcel_id := String(unlock.get("id", "parcel_wild"))
			if parcel_id == "parcel_wild" and not first_parcel_granted:
				first_parcel_granted = true
			grants.append({"item_id": parcel_id, "count": 1, "rare": false, "guaranteed": true})
	_apply(grants)
	return grants


func roll_table(table_id: String, stream := "loot_misc") -> Array:
	var grants: Array = []
	var table := registries.loot_table(table_id)
	if table != null and not table.entries.is_empty():
		var entry := rng.weighted(stream, table.entries)
		var count := rng.randi_range(stream, int(entry["min"]), int(entry["max"]))
		grants.append({"item_id": entry["item"], "count": count, "rare": bool(entry["rare"])})
	_apply(grants)
	return grants


func grant_fixed(requirements: Dictionary) -> Array:
	var grants: Array = []
	for item_id: String in requirements:
		grants.append({"item_id": item_id, "count": int(requirements[item_id]), "rare": false})
	_apply(grants)
	return grants


func _apply(grants: Array) -> void:
	for grant in grants:
		inventory.grant(grant["item_id"], grant["count"], bool(grant.get("rare", false)))
	if not grants.is_empty():
		loot_granted.emit(grants)


func to_save_dict() -> Dictionary:
	return {
		"rare_dry": rare_dry_streak.duplicate(),
		"tutorial_catches": tutorial_catches,
		"tutorial_fragment": tutorial_fragment_granted,
		"first_parcel": first_parcel_granted,
	}


func from_save_dict(data: Dictionary) -> void:
	rare_dry_streak = data.get("rare_dry", {}).duplicate()
	tutorial_catches = int(data.get("tutorial_catches", 0))
	tutorial_fragment_granted = bool(data.get("tutorial_fragment", false))
	first_parcel_granted = bool(data.get("first_parcel", false))
