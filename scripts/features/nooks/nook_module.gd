class_name NookModule
extends RefCounted
## Composition root for the Unfolding World feature: chunk-Nook world model,
## seed offers, generation, reveal application, sapling growth, and the
## clearing bridge from harvesting to the world command layer.
##
## The module never talks to discovery systems directly — it publishes world
## events; treasures, firsts, dormants, and keepsakes are deletable
## listeners composed by GameCore.

signal nook_revealed(coord: Vector2i, plan: NookGenerator.NookPlan)

const GROWTH_RUNTIME_KEY := "growth"

var registries: Registries
var rng: RngService
var grid: WorldGrid
var events: WorldEvents
var commands: WorldCommandService
var world: NookWorld
var generator: NookGenerator
var offers: NookOffers
var enabled := true

var _now_provider: Callable


func _init(
	regs: Registries,
	rng_service: RngService,
	world_grid: WorldGrid,
	world_events: WorldEvents,
	command_service: WorldCommandService,
	now_provider: Callable = Callable()
) -> void:
	registries = regs
	rng = rng_service
	grid = world_grid
	events = world_events
	commands = command_service
	world = NookWorld.new(regs)
	generator = NookGenerator.new(regs)
	offers = NookOffers.new(regs, rng_service, world)
	enabled = regs.feature("nooks_enabled", true)
	_now_provider = now_provider
	var module_ref: WeakRef = weakref(self)
	events.world_signal.connect(func(name: String, payload: Dictionary):
		var module: NookModule = module_ref.get_ref() as NookModule
		if module != null:
			module._count_activity(name, payload)
	)


## Registers the hand-composed starter zone as the first Nook so frontier
## rhythm, discovery scopes, and the atlas treat it like any other chunk.
## Uses the same system as every later reveal — one implementation, two
## moments (first boot just frames it differently).
func bootstrap_starter_nook() -> void:
	if not enabled or world.has_nook(Vector2i.ZERO):
		return
	var record := NookWorld.NookRecord.new()
	record.coord = Vector2i.ZERO
	record.biome_id = "nook_biome_forest"
	record.mood_id = "mood_clear_noon"
	record.density = "open"
	record.seed_value = 1
	record.starter = true
	record.display_name = "Home"
	record.revealed_unix = _now()
	world.add_nook(record)


## Player accepted offer card `index` (or surprise). Generates and applies
## the new Nook, returning the plan for the reveal presentation.
func accept_offer(index: int, surprise := false) -> NookGenerator.NookPlan:
	if not enabled:
		return null
	var choice := offers.choose_surprise() if surprise else offers.choose(index)
	if choice.is_empty():
		return null
	return reveal_nook(choice["coord"], choice["card"])


## Expands immediately in the open slot selected by a frontier glow. The
## authored procedural pools still decide biome, density, mood, stamp, relief,
## features, and discoveries; there is no activity or inventory gate.
func expand_random(
	coord: Vector2i,
	preferences: Dictionary = {}
) -> NookGenerator.NookPlan:
	if not enabled:
		return null
	var choice := offers.roll_direct(coord, preferences)
	if choice.is_empty():
		return null
	return reveal_nook(choice["coord"], choice["card"])


## Live expansion counterpart to expand_random(). Generation remains
## deterministic, but command application yields between small batches so a
## 6x6 Nook never monopolizes the main thread. The caller finishes renderer
## reconciliation before calling finish_prepared_expansion(), which ensures
## the reveal animation starts only after every visual holder exists.
func prepare_random_expansion_async(
	coord: Vector2i,
	entries_per_frame := 1,
	preferences: Dictionary = {}
) -> Dictionary:
	if not enabled:
		return {}
	var choice := offers.roll_direct(coord, preferences)
	if choice.is_empty():
		return {}
	return await prepare_reveal_nook_async(
		choice["coord"],
		choice["card"],
		entries_per_frame
	)


func prepare_reveal_nook_async(
	coord: Vector2i,
	seed_card: Dictionary,
	entries_per_frame := 1
) -> Dictionary:
	if world.has_nook(coord):
		return {}
	# Let the click/press frame finish before procedural work begins.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.process_frame
	var plan := _generate_plan(coord, seed_card)
	if plan == null or plan.biome_id == "":
		return {}
	var origin := world.chunk_origin(coord)
	# Current placement rules keep unrevealed frontier zones clear. Preserve
	# this protection for legacy saves that may already contain authored columns
	# there: generation must never overwrite existing player work.
	var protected_locals := _protected_plan_locals(origin, plan)
	var ordered_tiles := _ordered_tiles(plan)
	var applied_tiles: Array[Dictionary] = []
	var batch_size := maxi(1, entries_per_frame)
	var applied_this_frame := 0
	for tile: Dictionary in ordered_tiles:
		var local: Vector2i = tile["local"]
		if not protected_locals.has(local):
			if _apply_generated_tile(coord, origin, tile):
				applied_tiles.append(tile)
			else:
				# Also protects against a player placing into this slot while the
				# cooperative generation loop is in progress.
				protected_locals[local] = true
		applied_this_frame += 1
		if applied_this_frame >= batch_size and tree != null:
			applied_this_frame = 0
			await tree.process_frame
	plan.tiles = applied_tiles
	var dormant_instance := 0
	var applied_features: Array[Dictionary] = []
	var applied_feature_cells := {}
	for feature: Dictionary in plan.features:
		var local: Vector2i = feature["local"]
		if not protected_locals.has(local):
			var placed_dormant := _apply_generated_feature(
				coord, origin, feature
			)
			if int(feature.get("instance_id", 0)) > 0:
				applied_features.append(feature)
				applied_feature_cells[NookWorld.cell_key(local)] = true
			if placed_dormant > 0:
				dormant_instance = placed_dormant
		applied_this_frame += 1
		if applied_this_frame >= batch_size and tree != null:
			applied_this_frame = 0
			await tree.process_frame
	plan.features = applied_features
	_prune_unapplied_discoveries(
		plan, applied_feature_cells, dormant_instance
	)
	return {
		"coord": coord,
		"plan": plan,
		"dormant_instance": dormant_instance,
	}


func finish_prepared_expansion(prepared: Dictionary) -> NookGenerator.NookPlan:
	if prepared.is_empty():
		return null
	var coord: Vector2i = prepared.get("coord", Vector2i.ZERO)
	var plan := prepared.get("plan") as NookGenerator.NookPlan
	if plan == null or world.has_nook(coord):
		return null
	_finalize_reveal(coord, plan, int(prepared.get("dormant_instance", 0)))
	return plan


## Applies a seed card to the world: generation is deterministic from the
## card, application flows through the command reducer, and the resulting
## record carries the invisible discovery assignments.
func reveal_nook(coord: Vector2i, seed_card: Dictionary) -> NookGenerator.NookPlan:
	if world.has_nook(coord):
		return null
	var plan := _generate_plan(coord, seed_card)
	if plan == null or plan.biome_id == "":
		return null
	var origin := world.chunk_origin(coord)
	var protected_locals := _protected_plan_locals(origin, plan)
	var applied_tiles: Array[Dictionary] = []
	for tile: Dictionary in _ordered_tiles(plan):
		var local: Vector2i = tile["local"]
		if protected_locals.has(local):
			continue
		if _apply_generated_tile(coord, origin, tile):
			applied_tiles.append(tile)
		else:
			protected_locals[local] = true
	plan.tiles = applied_tiles
	var dormant_instance := 0
	var applied_features: Array[Dictionary] = []
	var applied_feature_cells := {}
	for feature: Dictionary in plan.features:
		var local: Vector2i = feature["local"]
		if protected_locals.has(local):
			continue
		var placed_dormant := _apply_generated_feature(coord, origin, feature)
		if int(feature.get("instance_id", 0)) > 0:
			applied_features.append(feature)
			applied_feature_cells[NookWorld.cell_key(local)] = true
		if placed_dormant > 0:
			dormant_instance = placed_dormant
	plan.features = applied_features
	_prune_unapplied_discoveries(
		plan, applied_feature_cells, dormant_instance
	)
	_finalize_reveal(coord, plan, dormant_instance)
	return plan


func _generate_plan(
	coord: Vector2i,
	seed_card: Dictionary
) -> NookGenerator.NookPlan:
	# Shared field seeds and neighbour context are supplied at reveal time, not
	# stored as fragile generated-cell recipes. Once applied, tiles are ordinary
	# saved world state and later content changes never regenerate them.
	var generation_card := seed_card.duplicate(true)
	if not generation_card.has("terrain_seed"):
		generation_card["terrain_seed"] = int(generation_card.get("seed", rng.world_seed))
	if not generation_card.has("hydrology_seed"):
		generation_card["hydrology_seed"] = generation_card["terrain_seed"]
	return generator.generate(
		coord,
		generation_card,
		world.nook_size,
		_generation_context(coord)
	)


func _ordered_tiles(plan: NookGenerator.NookPlan) -> Array:
	# Ground before relief caps: stacked entries need their support first.
	var ordered_tiles := plan.tiles.duplicate()
	ordered_tiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("elevation", 0)) < int(b.get("elevation", 0))
	)
	return ordered_tiles


func _apply_generated_tile(
	nook_coord: Vector2i,
	origin: Vector2i,
	tile: Dictionary
) -> bool:
	var cell: Vector2i = origin + (tile["local"] as Vector2i)
	var elevation := int(tile.get("elevation", 0))
	if not grid.can_place_tile_at(
		cell, elevation, String(tile["tile_id"])
	):
		return false
	var result := commands.apply("place_tile", {
		"coord": cell,
		"tile_id": String(tile["tile_id"]),
		"elevation": elevation,
		"nook": nook_coord,
		"source": "generation",
	})
	return bool(result.get("ok", false))


func _protected_plan_locals(
	origin: Vector2i,
	plan: NookGenerator.NookPlan
) -> Dictionary:
	var protected := {}
	for tile: Dictionary in plan.tiles:
		var local: Vector2i = tile["local"]
		if grid.has_cell(origin + local):
			protected[local] = true
	return protected


func _prune_unapplied_discoveries(
	plan: NookGenerator.NookPlan,
	applied_feature_cells: Dictionary,
	dormant_instance: int
) -> void:
	# Treasure belongs to its generated host. If a player's authored column
	# displaced that host, silently retaining the buried assignment would leave
	# an impossible discovery in the save.
	for key: String in plan.treasures.keys():
		if not applied_feature_cells.has(key):
			plan.treasures.erase(key)
	if dormant_instance <= 0:
		plan.dormant = {}


func _apply_generated_feature(
	nook_coord: Vector2i,
	origin: Vector2i,
	feature: Dictionary
) -> int:
	var cell: Vector2i = origin + (feature["local"] as Vector2i)
	var placed := commands.apply("place_feature", {
			"coord": cell,
			"structure_id": String(feature["structure_id"]),
			# Features stand on whatever the relief pass left on top.
		"elevation": maxi(0, grid.top_elevation(cell)),
		"nook": nook_coord,
	})
	# Preserve the stable instance id on the presentation-only plan. The world
	# state is already authoritative; this lets the reveal animate precisely the
	# models born in this Nook instead of guessing by structure id or cell.
	if bool(placed.get("ok", false)):
		feature["instance_id"] = int(placed.get("instance_id", 0))
	if bool(feature.get("dormant", false)) and bool(placed.get("ok", false)):
		return int(placed.get("instance_id", 0))
	return 0


func _finalize_reveal(
	coord: Vector2i,
	plan: NookGenerator.NookPlan,
	dormant_instance: int
) -> void:
	var record := NookWorld.NookRecord.new()
	record.coord = coord
	record.biome_id = plan.biome_id
	record.mood_id = plan.mood_id
	record.density = plan.density
	record.terrain_shape = plan.terrain_shape
	record.seed_value = plan.seed_value
	record.stamp_ids = plan.stamp_ids.duplicate()
	record.revealed_unix = _now()
	record.treasures = plan.treasures.duplicate(true)
	if not plan.dormant.is_empty():
		record.dormant = plan.dormant.duplicate(true)
		record.dormant["instance_id"] = dormant_instance
		record.dormant["score"] = 0.0
		record.dormant["pending_wake"] = false
		record.dormant["woken"] = false
	world.add_nook(record)
	events.publish("nook_revealed", {
		"nook": coord,
		"biome": record.biome_id,
		"mood": record.mood_id,
		"density": record.density,
		"terrain_shape": record.terrain_shape,
	})
	for neighbor in world.revealed_neighbors(coord):
		events.publish("nook_connected", {
			"nook": coord,
			"other": neighbor.coord,
		})
	nook_revealed.emit(coord, plan)


func _generation_context(coord: Vector2i) -> Dictionary:
	var neighbors: Array[Dictionary] = []
	for offset: Vector2i in WorldGrid.NEIGHBORS:
		var record := world.nook(coord + offset)
		if record == null:
			continue
		neighbors.append({
			"offset": offset,
			"biome": record.biome_id,
		})
	return {"neighbors": neighbors}


func name_nook(coord: Vector2i, name: String) -> bool:
	var record := world.nook(coord)
	if record == null or name.strip_edges() == "":
		return false
	record.display_name = name.strip_edges()
	world.touch(coord)
	events.publish("nook_named", {"nook": coord, "name": record.display_name})
	return true


## --- Clearing bridge -----------------------------------------------------


## Wire this to HarvestingModule.source_cleared. The final hit already paid
## its reward; this turns the cleared source into world truth: feature gone,
## stump/rubble left, feature_cleared published for the treasure listener.
func on_source_cleared(instance_id: int, clearing: Dictionary) -> void:
	if not enabled:
		return
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return
	var coord: Vector2i = found["coord"]
	commands.apply("clear_feature", {
		"instance_id": instance_id,
		"leaves_structure_id": String(clearing.get("leaves_structure_id", "")),
		"verb": String(clearing.get("verb", "")),
		"nook": world.chunk_of_cell(coord),
	})


## --- Planting & growth ---------------------------------------------------


## Saplings are unlimited and free: planting is giving back, not spending.
func plant_sapling(coord: Vector2i, sapling_id: String) -> Dictionary:
	if not enabled:
		return {"ok": false, "reason": "disabled"}
	var line := _growth_line_for_sapling(sapling_id)
	if line.is_empty():
		return {"ok": false, "reason": "unknown_sapling"}
	var stages: Array = line.get("stages", [])
	var planted := commands.apply("plant_sapling", {
		"coord": coord,
		"structure_id": String(stages[0]),
		# Biome terrain is genuinely vertical now. Plant on the visible top
		# surface instead of silently targeting the buried elevation-zero tile.
		"elevation": maxi(0, grid.top_elevation(coord)),
		"nook": world.chunk_of_cell(coord),
	})
	if not bool(planted.get("ok", false)):
		return planted
	_write_growth_runtime(
		int(planted.get("instance_id", 0)),
		String(line.get("id", "")), 0
	)
	return planted


var _growth_poll_accum := 0.0

## Real-time growth with offline catch-up: deadlines are unix timestamps,
## so time away simply arrives due. Stage lengths are minutes, so a 2 s poll
## keeps the frame free; tests may call with a large delta to force a scan.
func tick(delta: float) -> void:
	if not enabled:
		return
	_growth_poll_accum += delta
	if _growth_poll_accum < 2.0 and delta < 2.0:
		return
	_growth_poll_accum = 0.0
	var now := _now()
	var due: Array[Dictionary] = []
	for slot: Dictionary in grid.all_cell_slots():
		var state := grid.cell_at(slot["coord"], int(slot["elevation"]))
		if state == null:
			continue
		for structure: WorldGrid.StructureState in state.structures:
			var growth: Variant = structure.runtime_state.get(GROWTH_RUNTIME_KEY)
			if growth is Dictionary and float(growth.get("deadline_unix", 0.0)) > 0.0 \
				and float(growth["deadline_unix"]) <= now:
				due.append({
					"instance_id": structure.instance_id,
					"growth": growth,
				})
	for entry: Dictionary in due:
		_advance_stage(int(entry["instance_id"]), entry["growth"] as Dictionary)


func _advance_stage(instance_id: int, growth: Dictionary) -> void:
	var line: Dictionary = (
		registries.nook_config.get("growth_lines", {}) as Dictionary
	).get(String(growth.get("line", "")), {})
	var stages: Array = line.get("stages", [])
	var stage := int(growth.get("stage", 0))
	var next_stage := stage + 1
	if next_stage >= stages.size():
		return
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return
	var coord: Vector2i = found["coord"]
	var advanced := commands.apply("advance_growth", {
		"instance_id": instance_id,
		"structure_id": String(stages[next_stage]),
		"final_stage": next_stage == stages.size() - 1,
		"nook": world.chunk_of_cell(coord),
	})
	if bool(advanced.get("ok", false)):
		_write_growth_runtime(
			int(advanced.get("instance_id", 0)),
			String(growth.get("line", "")), next_stage
		)


func _write_growth_runtime(instance_id: int, line_id: String, stage: int) -> void:
	if instance_id == 0:
		return
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return
	var structure: WorldGrid.StructureState = found["structure"]
	var line: Dictionary = (
		registries.nook_config.get("growth_lines", {}) as Dictionary
	).get(line_id, {})
	var stage_seconds: Array = line.get("stage_seconds", [])
	var deadline := 0.0
	if stage < stage_seconds.size():
		deadline = _now() + float(stage_seconds[stage])
	structure.runtime_state[GROWTH_RUNTIME_KEY] = {
		"line": line_id,
		"stage": stage,
		"deadline_unix": deadline,
	}


func _growth_line_for_sapling(sapling_id: String) -> Dictionary:
	for raw: Variant in registries.nook_config.get("saplings", []):
		if raw is Dictionary and String(raw.get("id", "")) == sapling_id:
			var line_id := String(raw.get("growth_line", ""))
			var line: Dictionary = (
				registries.nook_config.get("growth_lines", {}) as Dictionary
			).get(line_id, {})
			if not line.is_empty():
				var result := line.duplicate(true)
				result["id"] = line_id
				return result
	return {}


## Adopts a player-placed structure as a growing sapling when it matches a
## configured growth line's first stage. This is how the ordinary build
## flow plants: place a young tree from the (unlimited) Build Bag and it
## simply starts growing — no separate planting mode to learn.
func adopt_planted(instance_id: int, structure_id: String, coord: Vector2i) -> void:
	if not enabled:
		return
	var lines: Dictionary = registries.nook_config.get("growth_lines", {})
	for raw: Variant in registries.nook_config.get("saplings", []):
		if not raw is Dictionary:
			continue
		var line_id := String(raw.get("growth_line", ""))
		var line: Dictionary = lines.get(line_id, {})
		var stages: Array = line.get("stages", [])
		if stages.is_empty() or String(stages[0]) != structure_id:
			continue
		var found := grid.find_structure(instance_id)
		if found.is_empty():
			return
		var structure: WorldGrid.StructureState = found["structure"]
		if structure.runtime_state.has(GROWTH_RUNTIME_KEY):
			return
		_write_growth_runtime(instance_id, line_id, 0)
		events.publish("sapling_planted", {
			"coord": coord,
			"instance_id": instance_id,
			"structure_id": structure_id,
			"nook": world.chunk_of_cell(coord),
		})
		return


## First-stage structure ids for every configured sapling — the Build Bag
## marks these unlimited.
func sapling_stage_zero_ids() -> Array[String]:
	var result: Array[String] = []
	var lines: Dictionary = registries.nook_config.get("growth_lines", {})
	for raw: Variant in registries.nook_config.get("saplings", []):
		if raw is Dictionary:
			var line: Dictionary = lines.get(String(raw.get("growth_line", "")), {})
			var stages: Array = line.get("stages", [])
			if not stages.is_empty():
				result.append(String(stages[0]))
	return result


func sapling_ids() -> Array[String]:
	var result: Array[String] = []
	for raw: Variant in registries.nook_config.get("saplings", []):
		if raw is Dictionary:
			result.append(String(raw.get("id", "")))
	return result


## --- Activity (soft frontier rhythm) -------------------------------------


func _count_activity(name: String, payload: Dictionary) -> void:
	if not ["model_placed", "feature_cleared", "sapling_planted",
		"tile_placed"].has(name):
		return
	if name == "tile_placed" and String(payload.get("source", "")) == "generation":
		return
	var coord: Vector2i = payload.get("nook", Vector2i.ZERO)
	if not payload.has("nook") and payload.has("coord"):
		coord = world.chunk_of_cell(payload.get("coord", Vector2i.ZERO))
	var record := world.nook(coord)
	if record == null:
		return
	record.activity += 1
	world.touch(coord)


## --- Save ----------------------------------------------------------------


func to_save_dict() -> Dictionary:
	return {
		"world": world.to_save_dict(),
		"offers": offers.to_save_dict(),
	}


func from_save_dict(data: Dictionary) -> void:
	world.from_save_dict(data.get("world", {}) as Dictionary)
	offers.from_save_dict(data.get("offers", {}) as Dictionary)


func _now() -> float:
	if _now_provider.is_valid():
		return float(_now_provider.call())
	return Time.get_unix_time_from_system()
