class_name DiscoverySystem
extends RefCounted
## Immediate, level-free discovery rewards. Void fishing uses a broad pool;
## local activities resolve the best pool from the biome the player built.

signal discovery_ready(entry: Dictionary)
signal progress_changed(pool_id: String, current: int, required: int)

const KIND_TILE := "tile"
const KIND_STRUCTURE := "structure"

var registries: Registries
var rng: RngService
var grid: WorldGrid
var stock: StockManager
var collection: CollectionManager

var progress: Dictionary = {}
var pending: Array[Dictionary] = []
var first_void_discovery_done := false


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


func discover_void() -> Dictionary:
	var pool := _void_pool()
	if pool == null:
		return {}
	if not first_void_discovery_done:
		first_void_discovery_done = true
		var first_id := String(registries.tune("first_void_reward", "tile_open_water"))
		if registries.tile(first_id) != null:
			return _grant({
				"kind": KIND_TILE,
				"id": first_id,
				"pool_id": pool.id,
				"source": "void",
			})
	return _roll_and_grant(pool, "void")


func discover_delivery() -> Dictionary:
	var pool := _void_pool()
	return _roll_and_grant(pool, "delivery") if pool != null else {}


func record_local_action(
	skill_id: String,
	coord: Vector2i,
	source_structure_id: String = ""
) -> Dictionary:
	var pool := resolve_local_pool(skill_id, coord, source_structure_id)
	if pool == null:
		return {
			"pool_id": "",
			"progress": 0,
			"required": 0,
			"reward": {},
		}
	var current := int(progress.get(pool.id, 0)) + 1
	var reward: Dictionary = {}
	if current >= pool.actions_per_reward:
		current = 0
		reward = _roll_and_grant(pool, "local")
	progress[pool.id] = current
	progress_changed.emit(pool.id, current, pool.actions_per_reward)
	return {
		"pool_id": pool.id,
		"progress": current,
		"required": pool.actions_per_reward,
		"reward": reward,
	}


func resolve_local_pool(
	skill_id: String,
	coord: Vector2i,
	source_structure_id: String = ""
) -> Defs.DiscoveryPoolDefinition:
	var context := context_manifest(coord, source_structure_id)
	var winner: Defs.DiscoveryPoolDefinition = null
	var winner_score := -1
	var fallback: Defs.DiscoveryPoolDefinition = null
	for pool: Defs.DiscoveryPoolDefinition in registries.discovery_pools.values():
		if pool.source != "local" or pool.skill_id != skill_id:
			continue
		if pool.fallback and (fallback == null or pool.priority > fallback.priority):
			fallback = pool
		var score := 0
		for tag: String in pool.context_tags:
			score += int(context.get(tag, 0))
		if (
			score > 0
			and (
				score > winner_score
				or (
					score == winner_score
					and (winner == null or pool.priority > winner.priority)
				)
			)
		):
			winner = pool
			winner_score = score
	return winner if winner != null else fallback


func context_manifest(
	coord: Vector2i,
	source_structure_id: String = ""
) -> Dictionary:
	var result := {}
	var radius := maxi(1, registries.tunei("discovery_context_radius", 2))
	for x in range(coord.x - radius, coord.x + radius + 1):
		for y in range(coord.y - radius, coord.y + radius + 1):
			var definition := grid.top_tile_def(Vector2i(x, y))
			if definition == null:
				continue
			var distance := absi(x - coord.x) + absi(y - coord.y)
			var influence := maxi(1, radius + 1 - distance)
			_add_context(result, "family:%s" % definition.family, influence)
			for tag: String in definition.biome_tags:
				_add_context(result, "biome:%s" % tag, influence)
			var top := grid.top_elevation(Vector2i(x, y))
			for elevation in range(0, top + 1):
				var state := grid.cell_at(Vector2i(x, y), elevation)
				if state == null:
					continue
				for placed: WorldGrid.StructureState in state.structures:
					var placed_definition := registries.structure(
						placed.structure_id
					)
					if placed_definition == null:
						continue
					for tag: String in placed_definition.traits.tags:
						if tag.begins_with("biome_"):
							_add_context(
								result,
								"biome:%s" % tag.trim_prefix("biome_"),
								influence
							)
	if source_structure_id != "":
		var structure := registries.structure(source_structure_id)
		if structure != null:
			for tag: String in structure.placement_tags:
				_add_context(result, "source:%s" % tag, radius + 1)
	return result


func grant_exchange_reward(
	kind: String,
	content_id: String,
	category: String,
	offered_id: String
) -> Dictionary:
	return _grant({
		"kind": kind,
		"id": content_id,
		"pool_id": "void_exchange:%s" % category,
		"source": "exchange",
		"offered_id": offered_id,
	})


func has_pending() -> bool:
	return not pending.is_empty()


func peek_pending() -> Dictionary:
	return pending[0].duplicate(true) if not pending.is_empty() else {}


func acknowledge_next() -> Dictionary:
	return pending.pop_front() if not pending.is_empty() else {}


func _void_pool() -> Defs.DiscoveryPoolDefinition:
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


func _add_context(context: Dictionary, key: String, amount: int) -> void:
	context[key] = int(context.get(key, 0)) + amount


func to_save_dict() -> Dictionary:
	return {
		"progress": progress.duplicate(),
		"pending": pending.duplicate(true),
		"first_void_discovery_done": first_void_discovery_done,
	}


func from_save_dict(data: Dictionary) -> void:
	progress.clear()
	for pool_id: String in data.get("progress", {}):
		if registries.discovery_pool(pool_id) != null:
			progress[pool_id] = maxi(0, int(data["progress"][pool_id]))
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
	first_void_discovery_done = bool(
		data.get("first_void_discovery_done", false)
	)
