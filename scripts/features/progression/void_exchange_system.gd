class_name VoidExchangeSystem
extends RefCounted
## Three true spare copies of one exact piece may be offered to the void. The
## keeper copy is protected across stock and the placed world.

signal offering_changed(kind: String, content_id: String, offered: int)
signal exchange_completed(reward: Dictionary)

const REQUIRED := 3

var registries: Registries
var rng: RngService
var grid: WorldGrid
var stock: StockManager
var discovery: DiscoverySystem
var offerings: Dictionary = {}


func _init(
	regs: Registries,
	rng_service: RngService,
	world_grid: WorldGrid,
	player_stock: StockManager,
	discovery_system: DiscoverySystem
) -> void:
	registries = regs
	rng = rng_service
	grid = world_grid
	stock = player_stock
	discovery = discovery_system


func offered_count(kind: String, content_id: String) -> int:
	return int(offerings.get(_key(kind, content_id), 0))


func offerable_count(kind: String, content_id: String) -> int:
	var stored := (
		stock.tile_count(content_id)
		if kind == DiscoverySystem.KIND_TILE
		else stock.structure_count(content_id)
	)
	var protected_in_stock := 1 if _placed_count(kind, content_id) <= 0 else 0
	return maxi(0, stored - protected_in_stock)


func has_offerable_duplicates() -> bool:
	if not offerings.is_empty():
		return true
	for tile_id: String in stock.tiles:
		if offerable_count(DiscoverySystem.KIND_TILE, tile_id) > 0:
			return true
	for structure_id: String in stock.structures:
		if offerable_count(DiscoverySystem.KIND_STRUCTURE, structure_id) > 0:
			return true
	return false


func offerable_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for tile_id: String in stock.tiles:
		_append_if_offerable(entries, DiscoverySystem.KIND_TILE, tile_id)
	for structure_id: String in stock.structures:
		_append_if_offerable(entries, DiscoverySystem.KIND_STRUCTURE, structure_id)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0
	)
	return entries


func offer(kind: String, content_id: String) -> Dictionary:
	if offerable_count(kind, content_id) <= 0:
		return {"ok": false, "reason": "keeper_protected"}
	var taken := (
		stock.take_tile(content_id)
		if kind == DiscoverySystem.KIND_TILE
		else stock.take_structure(content_id)
	)
	if not taken:
		return {"ok": false, "reason": "not_in_stock"}
	var key := _key(kind, content_id)
	var count := offered_count(kind, content_id) + 1
	offerings[key] = count
	offering_changed.emit(kind, content_id, count)
	if count < REQUIRED:
		return {"ok": true, "offered": count, "required": REQUIRED, "reward": {}}
	offerings.erase(key)
	var reward := _resolve_reward(kind, content_id)
	if reward.is_empty():
		if kind == DiscoverySystem.KIND_TILE:
			stock.add_tile(content_id, REQUIRED)
		else:
			stock.add_structure(content_id, REQUIRED)
		return {"ok": false, "reason": "no_alternative"}
	exchange_completed.emit(reward.duplicate(true))
	return {"ok": true, "offered": REQUIRED, "required": REQUIRED, "reward": reward}


func _append_if_offerable(
	entries: Array[Dictionary],
	kind: String,
	content_id: String
) -> void:
	var available := offerable_count(kind, content_id)
	var already_offered := offered_count(kind, content_id)
	if available <= 0 and already_offered <= 0:
		return
	var definition: Variant = (
		registries.tile(content_id)
		if kind == DiscoverySystem.KIND_TILE
		else registries.structure(content_id)
	)
	if definition == null:
		return
	entries.append({
		"kind": kind,
		"id": content_id,
		"name": definition.display_name,
		"available": available,
		"offered": already_offered,
		"category": BuildCategoryResolver.category_for(kind, definition),
	})


func _resolve_reward(kind: String, offered_id: String) -> Dictionary:
	var offered_definition: Variant = (
		registries.tile(offered_id)
		if kind == DiscoverySystem.KIND_TILE
		else registries.structure(offered_id)
	)
	if offered_definition == null:
		return {}
	var category: String = BuildCategoryResolver.category_for(
		kind,
		offered_definition
	)
	var candidates: Array = []
	if kind == DiscoverySystem.KIND_TILE:
		for definition: Defs.TileDefinition in registries.active_tiles():
			if (
				definition.obtainable
				and definition.id != offered_id
				and BuildCategoryResolver.category_for_tile(definition) == category
			):
				candidates.append({
					"kind": kind,
					"id": definition.id,
					"weight": maxf(0.01, definition.weight),
				})
	else:
		for definition: Defs.StructureDefinition in registries.structures.values():
			if (
				definition.id != offered_id
				and BuildCategoryResolver.category_for_structure(definition) == category
			):
				candidates.append({"kind": kind, "id": definition.id, "weight": 1.0})
	if candidates.is_empty():
		return {}
	var choice := rng.weighted("void_exchange:%s" % category, candidates)
	return discovery.grant_exchange_reward(
		String(choice["kind"]),
		String(choice["id"]),
		category,
		offered_id
	)


func _placed_count(kind: String, content_id: String) -> int:
	var count := 0
	for slot: Dictionary in grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		if kind == DiscoverySystem.KIND_TILE and state.tile_id == content_id:
			count += 1
		elif kind == DiscoverySystem.KIND_STRUCTURE:
			for structure: WorldGrid.StructureState in state.structures:
				if structure.structure_id == content_id:
					count += 1
	return count


func _key(kind: String, content_id: String) -> String:
	return "%s:%s" % [kind, content_id]


func to_save_dict() -> Dictionary:
	return {"offerings": offerings.duplicate()}


func from_save_dict(data: Dictionary) -> void:
	offerings.clear()
	for key: String in data.get("offerings", {}):
		var count := clampi(int(data["offerings"][key]), 0, REQUIRED - 1)
		var parts := key.split(":", false, 1)
		if parts.size() != 2 or count <= 0:
			continue
		var known := (
			parts[0] == DiscoverySystem.KIND_TILE
			and registries.tile(parts[1]) != null
		) or (
			parts[0] == DiscoverySystem.KIND_STRUCTURE
			and registries.structure(parts[1]) != null
		)
		if known:
			offerings[key] = count
