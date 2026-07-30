class_name VisionSystem
extends RefCounted
## The reward ritual: a claimed Vision reveals three options and the player
## keeps one. Draws are honest — no hidden pity, no dust conversion. The
## player-visible rules, in priority order:
##   1. The very first Vision offers the tuned starter trio (tutorial
##      guarantee — reachable hobbies without luck).
##   2. While the world is small, one slot is always plain land
##      ("land insurance", a published generosity rule, not secret math).
##   3. ~1 in 8 claims is a Wild Vision: all three slots roll from the full
##      catalog.
##   4. Otherwise composition is 2 + 1: two slots from the earning domain,
##      one stray from the full catalog.
## The shrine biases draws toward its focused item and family — the player's
## visible targeting tool. Duplicates are legitimate outcomes and arrive in
## stock like anything else; the refund meter is their deliberate sink.
## A pending reveal persists in the save: closing mid-reveal loses nothing.

signal options_revealed(context: Dictionary, options: Array)
signal vision_chosen(entry: Dictionary, was_new: bool)

const KIND_TILE := "tile"
const KIND_STRUCTURE := "structure"
const VISION_REWARD_TAG := "vision_reward"

var registries: Registries
var rng: RngService
var grid: WorldGrid
var stock: StockManager
var collection: CollectionManager
var shrine: ShrineSystem

var pending_options: Array[Dictionary] = []   # [{kind, id}]
var pending_domain_id := ""
var pending_wild := false
var claims_total := 0


func _init(
	regs: Registries,
	rng_service: RngService,
	world_grid: WorldGrid,
	stock_manager: StockManager,
	collection_manager: CollectionManager,
	shrine_system: ShrineSystem
) -> void:
	registries = regs
	rng = rng_service
	grid = world_grid
	stock = stock_manager
	collection = collection_manager
	shrine = shrine_system


func has_pending() -> bool:
	return not pending_options.is_empty()


## Every tile the player owns, placed or stored — the land-insurance gauge.
func owned_tile_count() -> int:
	return grid.placed_tile_count() + stock.total_tiles()


## Claims the oldest banked Vision from the well, or resumes a pending
## reveal. Returns the three options ([] when the well holds nothing).
func claim_from_well(inspiration: InspirationSystem) -> Array[Dictionary]:
	if has_pending():
		return pending_options.duplicate()
	var domain_id := inspiration.claim_next()
	if domain_id == "":
		return [] as Array[Dictionary]
	return _begin(domain_id, true)


## Guaranteed in-domain draw — the refund coin's reward. No wild roll, no
## stray slot: all three options belong to the coin's domain.
func begin_domain_locked(domain_id: String) -> Array[Dictionary]:
	if has_pending() or registries.inspiration_domain(domain_id) == null:
		return [] as Array[Dictionary]
	return _begin(domain_id, false)


## Ferry-gift draw: a full-catalog Vision that does not touch the bank.
func begin_delivered() -> Array[Dictionary]:
	if has_pending():
		return pending_options.duplicate()
	pending_domain_id = ""
	pending_wild = true
	pending_options = _roll_full_slots(3)
	_apply_land_insurance()
	options_revealed.emit(reveal_context(), pending_options.duplicate())
	return pending_options.duplicate()


func reveal_context() -> Dictionary:
	return {
		"domain_id": pending_domain_id,
		"wild": pending_wild,
		"claims_total": claims_total,
	}


func choose(option_index: int) -> Dictionary:
	if option_index < 0 or option_index >= pending_options.size():
		return {}
	var entry := pending_options[option_index]
	pending_options = [] as Array[Dictionary]   # reassign, never clear — callers may hold the old array
	pending_domain_id = ""
	pending_wild = false
	claims_total += 1
	var was_new := false
	match String(entry["kind"]):
		KIND_TILE:
			was_new = collection.record("tiles", String(entry["id"]))
			stock.add_tile(String(entry["id"]))
		KIND_STRUCTURE:
			was_new = collection.record("structures", String(entry["id"]))
			stock.add_structure(String(entry["id"]))
	vision_chosen.emit(entry.duplicate(), was_new)
	return {"entry": entry, "was_new": was_new}


# ------------------------------------------------------------------ rolling

func _begin(domain_id: String, allow_wild: bool) -> Array[Dictionary]:
	pending_domain_id = domain_id
	pending_wild = false
	# The tutorial trio and land insurance are well-claim generosity rules.
	# Domain-locked coin draws are a PROMISE — every option stays in-domain.
	if claims_total == 0 and allow_wild:
		pending_options = _first_vision_options()
	else:
		var wild := (
			allow_wild
			and rng.chance("vision_wild", registries.tunef("wild_vision_chance", 0.125))
		)
		var domain := registries.inspiration_domain(domain_id)
		if wild or (domain != null and domain.wildcard):
			pending_wild = wild
			pending_options = _roll_full_slots(3)
		elif allow_wild:
			pending_options = _roll_domain_slots(domain, 2)
			pending_options.append_array(_roll_full_slots(1))
		else:
			pending_options = _roll_domain_slots(domain, 3)
		if allow_wild:
			_apply_land_insurance()
	options_revealed.emit(reveal_context(), pending_options.duplicate())
	return pending_options.duplicate()


func _first_vision_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for raw_tile_id in registries.tune("first_vision_options", []):
		var tile_id := String(raw_tile_id)
		if registries.tile(tile_id) != null:
			options.append({"kind": KIND_TILE, "id": tile_id})
	if options.is_empty():
		options = _roll_full_slots(3)
	return options


## The published generosity rule: while the world is small, slot 0 is always
## a plain expansion tile so a new player is never starved for room.
func _apply_land_insurance() -> void:
	if owned_tile_count() >= registries.tunei("land_insurance_owned_tiles", 25):
		return
	var pool: Array[Dictionary] = []
	for raw_tile_id in registries.tune("land_insurance_pool", []):
		var tile_id := String(raw_tile_id)
		var tile := registries.tile(tile_id)
		if tile != null and registries.is_tile_active(tile_id):
			pool.append({"kind": KIND_TILE, "id": tile_id, "weight": tile.weight})
	if pool.is_empty() or pending_options.is_empty():
		return
	var pick := rng.weighted("vision", pool)
	pending_options[0] = {"kind": KIND_TILE, "id": String(pick["id"])}


func _roll_domain_slots(
	domain: Defs.InspirationDomainDefinition,
	count: int
) -> Array[Dictionary]:
	var pool := _domain_pool(domain)
	if pool.is_empty():
		return _roll_full_slots(count)
	return _pick_slots(pool, count)


func _roll_full_slots(count: int) -> Array[Dictionary]:
	return _pick_slots(_full_pool(), count)


func _pick_slots(pool: Array[Dictionary], count: int) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for slot in count:
		var pick := rng.weighted("vision", pool)
		if pick.is_empty():
			continue
		slots.append({"kind": String(pick["kind"]), "id": String(pick["id"])})
	return slots


func _domain_pool(domain: Defs.InspirationDomainDefinition) -> Array[Dictionary]:
	if domain == null:
		return _full_pool()
	if domain.wildcard:
		return _full_pool()
	var pool: Array[Dictionary] = []
	for family: String in domain.tile_families:
		for tile: Defs.TileDefinition in registries.tiles_in_family(family):
			pool.append(_tile_entry(tile))
	for structure: Defs.StructureDefinition in registries.structures.values():
		if (
			structure.traits.has_tag(VISION_REWARD_TAG)
			and structure.traits.has_tag(domain.id)
		):
			pool.append(_structure_entry(structure))
	return _apply_shrine_bias(pool)


func _full_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for tile: Defs.TileDefinition in registries.active_tiles():
		if tile.obtainable:
			pool.append(_tile_entry(tile))
	for structure: Defs.StructureDefinition in registries.structures.values():
		if structure.traits.has_tag(VISION_REWARD_TAG):
			pool.append(_structure_entry(structure))
	return _apply_shrine_bias(pool)


func _tile_entry(tile: Defs.TileDefinition) -> Dictionary:
	return {"kind": KIND_TILE, "id": tile.id, "family": tile.family, "weight": tile.weight}


func _structure_entry(structure: Defs.StructureDefinition) -> Dictionary:
	return {
		"kind": KIND_STRUCTURE,
		"id": structure.id,
		"family": "",
		"weight": registries.tunef("vision_structure_weight", 1.0),
	}


## The shrine's visible targeting: the focused item draws heavier, and its
## whole family leans in behind it.
func _apply_shrine_bias(pool: Array[Dictionary]) -> Array[Dictionary]:
	var focus := shrine.focus() if shrine != null else {}
	if focus.is_empty():
		return pool
	var focus_family := ""
	if String(focus.get("kind", "")) == KIND_TILE:
		var tile := registries.tile(String(focus.get("id", "")))
		focus_family = tile.family if tile != null else ""
	for entry: Dictionary in pool:
		if (
			String(entry["kind"]) == String(focus.get("kind", ""))
			and String(entry["id"]) == String(focus.get("id", ""))
		):
			entry["weight"] = float(entry["weight"]) * registries.tunef("shrine_bias_multiplier", 4.0)
		elif focus_family != "" and String(entry.get("family", "")) == focus_family:
			entry["weight"] = float(entry["weight"]) * registries.tunef("shrine_family_bias_multiplier", 2.0)
	return pool


# ------------------------------------------------------------------ persistence

func to_save_dict() -> Dictionary:
	var saved_options: Array = []
	for entry: Dictionary in pending_options:
		saved_options.append({"kind": entry["kind"], "id": entry["id"]})
	return {
		"pending": saved_options,
		"pending_domain": pending_domain_id,
		"pending_wild": pending_wild,
		"claims": claims_total,
	}


func from_save_dict(data: Dictionary) -> void:
	pending_options = [] as Array[Dictionary]
	for raw_entry in data.get("pending", []):
		if not raw_entry is Dictionary:
			continue
		var kind := String(raw_entry.get("kind", ""))
		var content_id := String(raw_entry.get("id", ""))
		var known := (
			(kind == KIND_TILE and registries.tile(content_id) != null)
			or (kind == KIND_STRUCTURE and registries.structure(content_id) != null)
		)
		if known:
			pending_options.append({"kind": kind, "id": content_id})
	pending_domain_id = String(data.get("pending_domain", ""))
	if registries.inspiration_domain(pending_domain_id) == null:
		pending_domain_id = ""
	pending_wild = bool(data.get("pending_wild", false))
	claims_total = maxi(0, int(data.get("claims", 0)))
