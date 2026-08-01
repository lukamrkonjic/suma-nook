class_name DiscoverySystem
extends RefCounted
## The ferry's periodic gift: one owned discovery from the broad delivery
## pool, staged through a loss-proof pending queue. Fishing rewards no longer
## flow through here — the fishing feature module stages catches physically
## in the Catch Basket instead.

signal discovery_ready(entry: Dictionary)

const KIND_TILE := "tile"
const KIND_STRUCTURE := "structure"

var registries: Registries
var rng: RngService
var grid: WorldGrid
var stock: StockManager
var collection: CollectionManager

var pending: Array[Dictionary] = []


func _init(
	regs: Registries,
	rng_service: RngService,
	world_grid: WorldGrid,
	player_stock: StockManager,
	journal: CollectionManager
) -> void:
	registries = regs
	rng = rng_service
	grid = world_grid
	stock = player_stock
	collection = journal


func discover_delivery() -> Dictionary:
	var pool := _delivery_pool()
	return _roll_and_grant(pool, "delivery") if pool != null else {}


func has_pending() -> bool:
	return not pending.is_empty()


func peek_pending() -> Dictionary:
	return pending[0].duplicate(true) if not pending.is_empty() else {}


func acknowledge_next() -> Dictionary:
	return pending.pop_front() if not pending.is_empty() else {}


func _delivery_pool() -> Defs.DiscoveryPoolDefinition:
	for pool: Defs.DiscoveryPoolDefinition in registries.discovery_pools.values():
		if pool.source == "void":
			return pool
	return null


func _roll_and_grant(
	pool: Defs.DiscoveryPoolDefinition,
	source: String
) -> Dictionary:
	var choice := rng.weighted("discovery:%s" % pool.id, pool.rewards)
	if choice.is_empty():
		return {}
	return _grant({
		"kind": String(choice.get("kind", "")),
		"id": String(choice.get("id", "")),
		"pool_id": pool.id,
		"source": source,
	})


func _grant(raw_entry: Dictionary) -> Dictionary:
	var entry := raw_entry.duplicate(true)
	var kind := String(entry.get("kind", ""))
	var content_id := String(entry.get("id", ""))
	var was_new := false
	match kind:
		KIND_TILE:
			if registries.tile(content_id) == null:
				return {}
			stock.add_tile(content_id)
			was_new = collection.record("tiles", content_id)
		KIND_STRUCTURE:
			if registries.structure(content_id) == null:
				return {}
			stock.add_structure(content_id)
			was_new = collection.record("structures", content_id)
		_:
			return {}
	entry["was_new"] = was_new
	pending.append(entry)
	discovery_ready.emit(entry.duplicate(true))
	return entry


func to_save_dict() -> Dictionary:
	return {
		"pending": pending.duplicate(true),
	}


func from_save_dict(data: Dictionary) -> void:
	pending.clear()
	for raw_entry in data.get("pending", []):
		if not raw_entry is Dictionary:
			continue
		var kind := String(raw_entry.get("kind", ""))
		var content_id := String(raw_entry.get("id", ""))
		if (
			(kind == KIND_TILE and registries.tile(content_id) != null)
			or (kind == KIND_STRUCTURE and registries.structure(content_id) != null)
		):
			pending.append(raw_entry.duplicate(true))
