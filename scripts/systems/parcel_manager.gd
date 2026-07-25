class_name ParcelManager
extends RefCounted
## Land Parcels → three-choice tile reveals. Generosity contract:
## - the FIRST parcel ever opened always offers the tuned grove trio (tutorial
##   guarantee: Woodcutting is reachable without luck);
## - options are always placeable-or-storable (they go to stock on choose);
## - duplicates convert into Pattern Dust AND advance a new-discovery pity that
##   forces an undiscovered tile into the options once it fills;
## - pending reveals are saved — closing the game mid-reveal loses nothing
##   (the parcel item was consumed atomically at open, the options persist).

signal options_revealed(parcel_id: String, options: Array)   # [tile_id, ...]
signal tile_chosen(tile_id: String, was_new: bool, dust_gained: int)

var registries: Registries
var rng: RngService
var inventory: InventoryManager
var stock: StockManager
var collection: CollectionManager
var skills: SkillManager

var pending_parcel_id: String = ""
var pending_options: Array[String] = []
var opened_count: int = 0
var duplicate_streak: int = 0


func _init(regs: Registries, rng_service: RngService, inv: InventoryManager, stock_mgr: StockManager, coll: CollectionManager, skill_mgr: SkillManager) -> void:
	registries = regs
	rng = rng_service
	inventory = inv
	stock = stock_mgr
	collection = coll
	skills = skill_mgr


func has_pending() -> bool:
	return not pending_options.is_empty()


func can_open(parcel_id: String) -> bool:
	return not has_pending() and inventory.count(parcel_id) > 0


## Consumes the parcel item and rolls the three options (atomic: options are
## stored immediately, so a crash after this point still owns the reveal).
func open(parcel_id: String) -> Array[String]:
	if not can_open(parcel_id):
		return []
	var def := registries.parcel(parcel_id)
	if def == null:
		return []
	inventory.take(parcel_id, 1)
	opened_count += 1
	pending_parcel_id = parcel_id
	pending_options = _roll_options(def)
	options_revealed.emit(parcel_id, pending_options)
	return pending_options


func choose(option_index: int) -> String:
	if option_index < 0 or option_index >= pending_options.size():
		return ""
	var tile_id := pending_options[option_index]
	pending_options.clear()
	pending_parcel_id = ""
	var was_new := collection.record("tiles", tile_id)
	var dust := 0
	if was_new:
		duplicate_streak = 0
	else:
		duplicate_streak += 1
		dust = registries.tunei("pattern_dust_per_duplicate", 1)
		inventory.grant("pattern_dust", dust, false, true)
	stock.add_tile(tile_id)
	tile_chosen.emit(tile_id, was_new, dust)
	return tile_id


func can_reroll() -> bool:
	return has_pending() and (inventory.reroll_charges > 0 or inventory.count("pattern_dust") >= registries.tunei("reroll_dust_cost", 3))


func reroll() -> Array[String]:
	if not can_reroll():
		return pending_options
	if inventory.reroll_charges > 0:
		inventory.reroll_charges -= 1
		inventory.items_changed.emit()
	else:
		inventory.take("pattern_dust", registries.tunei("reroll_dust_cost", 3))
	var def := registries.parcel(pending_parcel_id)
	pending_options = _roll_options(def)
	options_revealed.emit(pending_parcel_id, pending_options)
	return pending_options


func _roll_options(def: Defs.ParcelDefinition) -> Array[String]:
	var options: Array[String] = []
	# Tutorial guarantee: first parcel is the grove trio.
	if opened_count == 1:
		for tile_id in registries.tune("guaranteed_first_parcel_options", []):
			options.append(String(tile_id))
		if not options.is_empty():
			return options
	var family_entries: Array = []
	for family: String in def.families:
		family_entries.append({"family": family, "weight": def.families[family]})
	for slot in def.option_count:
		var family: String = rng.weighted("parcel", family_entries).get("family", "home_meadow")
		var candidates := _eligible_tiles(family)
		if candidates.is_empty():
			candidates = _eligible_tiles("home_meadow")
		var weighted_entries: Array = []
		for tile: Defs.TileDefinition in candidates:
			weighted_entries.append({"tile": tile, "weight": tile.weight})
		var pick: Defs.TileDefinition = rng.weighted("parcel", weighted_entries).get("tile")
		if pick != null:
			options.append(pick.id)
	# New-discovery pity: too many duplicates in a row forces one fresh tile in.
	if duplicate_streak >= registries.tunei("new_tile_pity_max_duplicates", 4):
		var fresh := _any_undiscovered()
		if fresh != "" and not options.has(fresh):
			options[0] = fresh
	return options


func _eligible_tiles(family: String) -> Array:
	var result: Array = []
	for tile: Defs.TileDefinition in registries.tiles_in_family(family):
		var ok := true
		for skill_id: String in tile.unlock_level:
			if skills.level(skill_id) < int(tile.unlock_level[skill_id]):
				ok = false
		if ok:
			result.append(tile)
	return result


func _any_undiscovered() -> String:
	var fresh: Array[String] = []
	for tile: Defs.TileDefinition in registries.tiles.values():
		if not collection.is_discovered("tiles", tile.id) and _eligible_tiles(tile.family).has(tile):
			fresh.append(tile.id)
	fresh.sort()
	if fresh.is_empty():
		return ""
	return fresh[rng.randi_range("parcel", 0, fresh.size() - 1)]


func to_save_dict() -> Dictionary:
	return {
		"pending_parcel": pending_parcel_id,
		"pending_options": pending_options.duplicate(),
		"opened": opened_count,
		"dup_streak": duplicate_streak,
	}


func from_save_dict(data: Dictionary) -> void:
	pending_parcel_id = String(data.get("pending_parcel", ""))
	pending_options.clear()
	for option in data.get("pending_options", []):
		if registries.tile(option) != null:
			pending_options.append(String(option))
	opened_count = int(data.get("opened", 0))
	duplicate_streak = int(data.get("dup_streak", 0))
