class_name WorldCuriosityService
extends RefCounted
## Persistent themed breakables. A container and its complete bundle are rolled
## once, saved in world state, and granted atomically by one interaction.

signal curiosity_landed(instance_id: int, state: Dictionary)
signal curiosity_opened(instance_id: int, result: Dictionary)

const STRUCTURE_ID := "struct_reward_drop"
const RUNTIME_KEY := "world_curiosity"

var registries: Registries
var rng: RngService
var grid: WorldGrid
var nooks: NookModule
var rewards: BuildRewardService
var collections: CreativeCollectionService
var gifts: WorldGiftService
var sequence := 0
var land_dry_streak := 0
var new_land_opportunities := 0
var rare_misses: Dictionary = {}


func _init(
	content: Registries,
	rng_service: RngService,
	world_grid: WorldGrid,
	nook_module: NookModule,
	build_rewards: BuildRewardService,
	creative_collections: CreativeCollectionService,
	world_gifts: WorldGiftService
) -> void:
	registries = content
	rng = rng_service
	grid = world_grid
	nooks = nook_module
	rewards = build_rewards
	collections = creative_collections
	gifts = world_gifts


func entry_for_instance(instance_id: int) -> Dictionary:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return {}
	var structure: WorldGrid.StructureState = found["structure"]
	var state: Dictionary = structure.runtime_state.get(RUNTIME_KEY, {})
	return state.duplicate(true) if not state.is_empty() and not bool(state.get("claimed", false)) else {}


func active_count() -> int:
	var count := 0
	for slot: Dictionary in grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			var curiosity: Dictionary = structure.runtime_state.get(RUNTIME_KEY, {})
			if not curiosity.is_empty() and not bool(curiosity.get("claimed", false)):
				count += 1
	return count


func active_cap() -> int:
	return maxi(1, int(registries.build_cadence_config.get("curiosity_active_cap", 1)))


func land_skyfall(preferred_coord: Vector2i) -> Dictionary:
	return _land(preferred_coord, null, Vector2i(2147483647, 2147483647))


func spawn_for_new_land(coord: Vector2i, force := false) -> Dictionary:
	if active_count() >= active_cap():
		return {}
	var guarantee := (
		force
		or bool(registries.build_cadence_config.get("first_new_land_curiosity_guaranteed", true))
		and new_land_opportunities == 0
		or land_dry_streak >= maxi(1, int(registries.build_cadence_config.get("new_land_dry_streak_guarantee", 3)))
	)
	var chance := float(registries.build_cadence_config.get("new_land_curiosity_chance", 0.25))
	new_land_opportunities += 1
	if not guarantee and not rng.chance("diorama_land_curiosity:%d" % sequence, chance):
		land_dry_streak += 1
		return {}
	var preferred := nooks.world.chunk_origin(coord) + Vector2i(
		nooks.world.nook_size / 2,
		nooks.world.nook_size / 2
	)
	var result := _land(preferred, null, coord)
	if result.is_empty():
		land_dry_streak += 1
	else:
		land_dry_streak = 0
	return result


func claim(instance_id: int) -> Dictionary:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return {"accepted": false, "reason": "missing"}
	var structure: WorldGrid.StructureState = found["structure"]
	var state: Dictionary = structure.runtime_state.get(RUNTIME_KEY, {})
	if state.is_empty() or bool(state.get("claimed", false)):
		return {"accepted": false, "reason": "already_claimed"}
	# Mark before any grants so duplicate input can never open the bundle twice.
	state["claimed"] = true
	var granted: Array[Dictionary] = []
	for raw_reward: Variant in state.get("loot", []):
		if not raw_reward is Dictionary:
			continue
		var reward: Dictionary = (
			raw_reward.duplicate(true)
			if bool(raw_reward.get("pregranted", false))
			else rewards.grant(raw_reward)
		)
		if reward.is_empty():
			state["claimed"] = false
			return {"accepted": false, "reason": "grant_failed"}
		granted.append(reward)
	var granted_gifts := {}
	for gift_id: String in state.get("gifts", {}):
		var amount := int(state["gifts"][gift_id])
		if gifts.add(
			gift_id,
			amount,
			"curiosity:%s:%s" % [state.get("curiosity_id", ""), state.get("roll_id", "")]
		):
			granted_gifts[gift_id] = amount
	grid.remove_structure(found["coord"], instance_id, int(found["elevation"]))
	var result := {
		"accepted": true,
		"rewards": granted,
		"gifts": granted_gifts,
		"style": (state.get("style", {}) as Dictionary).duplicate(true),
		"reveal_profile_id": String(state.get("reveal_profile_id", "reveal_visitor_vase")),
		"position_coord": found["coord"],
	}
	curiosity_opened.emit(instance_id, result.duplicate(true))
	return result


func to_save_dict() -> Dictionary:
	return {
		"sequence": sequence,
		"land_dry_streak": land_dry_streak,
		"new_land_opportunities": new_land_opportunities,
		"rare_misses": rare_misses.duplicate(),
	}


func from_save_dict(data: Dictionary) -> void:
	sequence = maxi(0, int(data.get("sequence", 0)))
	land_dry_streak = maxi(0, int(data.get("land_dry_streak", 0)))
	new_land_opportunities = maxi(0, int(data.get("new_land_opportunities", 0)))
	rare_misses = (data.get("rare_misses", {}) as Dictionary).duplicate()


## Old Falling Objects already occupy a safe world structure. Re-skin their
## saved one-time reward in place, so migration cannot move or reroll it.
func migrate_legacy_reward_drops() -> int:
	var migrated := 0
	for slot: Dictionary in grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			if structure.structure_id != STRUCTURE_ID:
				continue
			var legacy: Dictionary = structure.runtime_state.get("reward_drop", {})
			if legacy.is_empty() or structure.runtime_state.has(RUNTIME_KEY):
				continue
			sequence += 1
			structure.runtime_state[RUNTIME_KEY] = _legacy_state(
				legacy,
				String(legacy.get("collection_id", "")),
				"home_meadow"
			)
			structure.runtime_state.erase("reward_drop")
			migrated += 1
	return migrated


## A waiting visitor/vase becomes the same kind of themed curiosity, keeping
## its exact pre-rolled reward and its original landing character.
func migrate_legacy_visitor(event: Dictionary) -> Dictionary:
	var reward: Dictionary = (event.get("reward", {}) as Dictionary).duplicate(true)
	if reward.is_empty():
		return {}
	var raw_cell: Array = event.get("cell", [])
	var preferred := grid.home_cell
	if raw_cell.size() >= 2:
		preferred = Vector2i(int(raw_cell[0]), int(raw_cell[1]))
	sequence += 1
	var saved := _legacy_state(
		reward,
		String(event.get("landing_collection", "")),
		String(event.get("landing_family", "home_meadow"))
	)
	# Migration may legitimately preserve both an old Falling Object and a
	# visitor. The normal one-active cap resumes after these are collected.
	for coord: Vector2i in _landing_candidates(
		preferred, Vector2i(2147483647, 2147483647)
	):
		var elevation := grid.top_elevation(coord)
		var structure := grid.add_structure(coord, STRUCTURE_ID, 1, 0, elevation)
		if structure == null:
			continue
		saved["landed_coord"] = [coord.x, coord.y]
		structure.runtime_state[RUNTIME_KEY] = saved.duplicate(true)
		curiosity_landed.emit(structure.instance_id, saved.duplicate(true))
		return {"accepted": true, "instance_id": structure.instance_id, "coord": coord}
	return {}


func _land(
	preferred_coord: Vector2i,
	forced_definition,
	restrict_nook: Vector2i
) -> Dictionary:
	if active_count() >= active_cap():
		return {}
	var definition = forced_definition if forced_definition != null else _roll_definition()
	if definition == null:
		return {}
	sequence += 1
	var saved := _roll_state(definition)
	for coord: Vector2i in _landing_candidates(preferred_coord, restrict_nook):
		var elevation := grid.top_elevation(coord)
		var structure := grid.add_structure(coord, STRUCTURE_ID, 1, 0, elevation)
		if structure == null:
			continue
		saved["landed_coord"] = [coord.x, coord.y]
		structure.runtime_state[RUNTIME_KEY] = saved.duplicate(true)
		curiosity_landed.emit(structure.instance_id, saved.duplicate(true))
		return {
			"accepted": true,
			"instance_id": structure.instance_id,
			"coord": coord,
			"state": saved.duplicate(true),
		}
	return {}


func _roll_definition():
	var candidates: Array[Dictionary] = []
	for definition in registries.world_curiosities.values():
		if collections.eligible_members("", definition.collection_id).is_empty():
			continue
		candidates.append({"definition": definition, "weight": definition.weight})
	var chosen := rng.weighted("diorama_curiosity_kind:%d" % sequence, candidates)
	return chosen.get("definition")


func _roll_state(definition) -> Dictionary:
	var collection_id: String = definition.collection_id
	var miss_count := int(rare_misses.get(collection_id, 0))
	var rare_probability: float = definition.rare_chance
	if miss_count >= 6:
		rare_probability = minf(0.75, rare_probability + float(miss_count - 5) * 0.08)
	var rare_hit := rng.chance("diorama_curiosity_rare:%d" % sequence, rare_probability)
	rare_misses[collection_id] = 0 if rare_hit else miss_count + 1
	var amount := rng.randi_range(
		"diorama_curiosity_amount:%d" % sequence,
		definition.loot_min,
		definition.loot_max
	)
	var loot: Array[Dictionary] = []
	var exclude: Array[String] = []
	for index in amount:
		var entry := collections.roll_member(
			collection_id,
			"diorama_curiosity_loot:%d:%d" % [sequence, index],
			rare_hit and index == 0,
			exclude
		)
		if entry.is_empty():
			continue
		loot.append(entry)
		exclude.append("%s:%s" % [entry.get("kind", ""), entry.get("id", "")])
	var rolled_gifts := {}
	if rng.chance("diorama_curiosity_gift:%d" % sequence, definition.gift_chance):
		rolled_gifts["expansion_ripple"] = 1
	return {
		"roll_id": "%d" % sequence,
		"curiosity_id": definition.id,
		"display_name": definition.display_name,
		"collection_id": collection_id,
		"loot": loot,
		"gifts": rolled_gifts,
		"claimed": false,
		"reveal_profile_id": definition.reveal_profile_id,
		"style": {
			"category": definition.category,
			"family": definition.family,
		},
	}


func _legacy_state(
	reward: Dictionary,
	collection_hint: String,
	family: String
) -> Dictionary:
	var kind := String(reward.get("kind", ""))
	var content_id := String(reward.get("id", ""))
	var membership := collections.membership(kind, content_id)
	var collection_id := String(membership.get("collection_id", collection_hint))
	if registries.creative_collection(collection_id) == null:
		collection_id = "meadow"
	return {
		"roll_id": "legacy:%d" % sequence,
		"curiosity_id": "legacy_keepsake",
		"display_name": "Sky Keepsake",
		"collection_id": collection_id,
		"loot": [reward.duplicate(true)],
		"gifts": {},
		"claimed": false,
		"reveal_profile_id": "reveal_visitor_vase",
		"style": {
			"category": collection_hint if collection_hint != "" else collection_id,
			"family": family if family != "" else "home_meadow",
		},
		"migrated": true,
	}


func _landing_candidates(
	preferred_coord: Vector2i,
	restrict_nook: Vector2i
) -> Array[Vector2i]:
	var candidates: Array[Dictionary] = []
	for coord: Vector2i in grid.cells:
		if (
			restrict_nook.x != 2147483647
			and nooks.world.chunk_of_cell(coord) != restrict_nook
		):
			continue
		var elevation := grid.top_elevation(coord)
		var state := grid.cell_at(coord, elevation)
		var tile := grid.tile_def_at(coord, elevation)
		if (
			state == null
			or tile == null
			or not tile.walkable
			or tile.surface_kind == "water"
			or not state.structures.is_empty()
			or state.landmark_id != ""
		):
			continue
		candidates.append({
			"coord": coord,
			"score": coord.distance_squared_to(preferred_coord),
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) < int(b["score"])
	)
	var result: Array[Vector2i] = []
	for candidate: Dictionary in candidates:
		result.append(candidate["coord"])
	return result
