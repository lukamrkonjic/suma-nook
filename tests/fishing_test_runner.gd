extends SceneTree
## Headless validation suite for the void-fishing rework. Run:
##   Godot --headless --path . --script tests/fishing_test_runner.gd
## Must print "ALL FISHING TESTS PASSED".
##
## Covers the fishing contract end to end: Wild Cast, bounded timing, the
## explicit session state machine, 3x3 habitat sampling, pool composition,
## Spirits, haul multiplicity, keepsakes, hidden protection, the physical
## Catch Basket, persistence, determinism, and large-run distributions.

var failures: PackedStringArray = []
var assertions := 0
const GameContentCatalogScript := preload("res://scripts/core/game_content_catalog.gd")


func _init() -> void:
	_run()
	if failures.is_empty():
		print("ALL FISHING TESTS PASSED — %d assertions" % assertions)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		print("FISHING TESTS FAILED — %d failures / %d assertions" % [failures.size(), assertions])
		quit(1)


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func fresh_core(seed_value := 12345) -> GameCore:
	var core := GameCore.new()
	core.setup("res://data", seed_value)
	core.save_manager.save_path = "user://fishing_test_save.json"
	core.save_manager.backup_path = "user://fishing_test_save.json.backup"
	var profile := PlayerProfile.new()
	profile.display_name = "Testkeeper"
	core.new_game(profile)
	return core


## Ticks the session until one haul commits (or a generous simulated-time cap
## runs out). Returns the committed haul, or null.
func run_one_catch(core: GameCore, manual := false, anchor := Vector2i.ZERO):
	var committed: Array = []
	var handler := func(haul): committed.append(haul)
	core.fishing.session.haul_committed.connect(handler)
	if not core.fishing.session.is_active():
		core.fishing.session.begin_session(anchor)
	var elapsed := 0.0
	while committed.is_empty() and elapsed < 120.0:
		core.fishing.tick(0.1)
		elapsed += 0.1
		if manual and core.fishing.session.state == FishingSessionStates.State.BITE:
			core.fishing.session.request_manual_reel()
	core.fishing.session.haul_committed.disconnect(handler)
	return committed[0] if not committed.is_empty() else null


func _run() -> void:
	_test_wild_cast_needs_nothing()
	_test_no_failure_path_and_bounded_timing()
	_test_manual_faster_same_reward()
	_test_auto_recast_and_cancellation()
	_test_context_snapshot_at_cast()
	_test_habitat_reads_exactly_3x3()
	_test_habitat_composition_and_cache()
	_test_habitat_model_tags_capped()
	_test_habitat_never_clones_model_ids()
	_test_pool_composition_and_fallbacks()
	_test_locked_loot_excluded()
	_test_data_driven_loot_extension()
	_test_no_catchable_fish_possible()
	_test_fishing_never_touches_fauna_or_combat()
	_test_haul_multiplicity()
	_test_bundle_quantities_respect_rarity()
	_test_keepsake_independent_bonus()
	_test_hidden_luck_protection()
	_test_spirit_pouch_rules()
	_test_spirit_targets_theme_only()
	_test_spirit_lifecycle_through_session()
	_test_activity_adapters_grant_spirits()
	_test_basket_stores_three_hauls()
	_test_basket_full_pauses_and_resumes()
	_test_bundle_placement_roundtrip()
	_test_model_and_keepsake_taking()
	_test_basket_persistence()
	_test_first_catch_guarantee()
	_test_determinism_with_seed()
	_test_distribution_simulation()
	_test_grove_and_stone_habitats_distinct()


# ---------------------------------------------------------------- session

func _test_wild_cast_needs_nothing() -> void:
	var core := fresh_core(101)
	check(core.fishing.pouch.slots().is_empty(), "fishing starts with an empty Spirit Pouch")
	check(core.inventory.counts.is_empty(), "fishing starts with no material inventory")
	var haul = run_one_catch(core)
	check(haul != null, "Wild Cast succeeds with no bait, Spirit, workshop, or preparation")
	check(haul.entry_count() >= 1, "every catch carries at least one reward entry")
	check(core.inventory.counts.is_empty(), "fishing consumed no materials")


func _test_no_failure_path_and_bounded_timing() -> void:
	var core := fresh_core(102)
	var max_seconds: float = core.fishing.balance.timing("total_max_seconds", 30.0)
	var recast: float = core.fishing.balance.timing("recast_pause_seconds", 0.8)
	var committed: Array = []
	core.fishing.session.haul_committed.connect(func(haul): committed.append(haul))
	core.fishing.session.begin_session(Vector2i.ZERO)
	for attempt in 6:
		var target := attempt + 1
		var waited := 0.0
		while committed.size() < target and waited < 90.0:
			core.fishing.tick(0.1)
			waited += 0.1
			# Empty the basket so auto-recasting continues unhindered.
			for haul in core.fishing.basket.hauls.duplicate():
				core.fishing.basket.discard_haul(haul.haul_id)
		check(committed.size() == target, "idle catch %d cannot fail" % attempt)
		check(
			waited <= max_seconds + recast + 1.0,
			"idle catch %d resolves inside the configured maximum (%.1fs)"
			% [attempt, waited]
		)
	core.fishing.session.cancel("test")
	var states := FishingSessionStates.NAMES.values()
	check(not states.has("failed"), "there is deliberately no FAILED session state")


func _test_manual_faster_same_reward() -> void:
	var manual_core := fresh_core(303)
	var auto_core := fresh_core(303)
	var manual_time := [0.0]
	var auto_time := [0.0]
	var manual_haul = null
	var auto_haul = null
	# Manual retrieval.
	var committed_m: Array = []
	manual_core.fishing.session.haul_committed.connect(func(h): committed_m.append(h))
	manual_core.fishing.session.begin_session(Vector2i.ZERO)
	while committed_m.is_empty() and manual_time[0] < 90.0:
		manual_core.fishing.tick(0.05)
		manual_time[0] += 0.05
		if manual_core.fishing.session.state == FishingSessionStates.State.BITE:
			manual_core.fishing.session.request_manual_reel()
	manual_haul = committed_m[0]
	manual_core.fishing.session.cancel("test")
	# Automatic retrieval on an identical seed.
	var committed_a: Array = []
	auto_core.fishing.session.haul_committed.connect(func(h): committed_a.append(h))
	auto_core.fishing.session.begin_session(Vector2i.ZERO)
	while committed_a.is_empty() and auto_time[0] < 90.0:
		auto_core.fishing.tick(0.05)
		auto_time[0] += 0.05
	auto_haul = committed_a[0]
	auto_core.fishing.session.cancel("test")
	check(manual_haul != null and auto_haul != null, "both retrieval paths deliver")
	check(
		manual_time[0] < auto_time[0],
		"manual retrieval (%.1fs) is faster than automatic (%.1fs)"
		% [manual_time[0], auto_time[0]]
	)
	var manual_dict = manual_haul.to_dict()
	var auto_dict = auto_haul.to_dict()
	manual_dict.erase("haul_id")
	auto_dict.erase("haul_id")
	check(
		str(manual_dict) == str(auto_dict),
		"manual and automatic retrieval produce the identical catch on one seed"
	)


func _test_auto_recast_and_cancellation() -> void:
	var core := fresh_core(104)
	var haul = run_one_catch(core)
	check(haul != null, "first catch commits")
	check(
		core.fishing.session.is_active()
		and core.fishing.session.state != FishingSessionStates.State.PAUSED_BASKET_FULL,
		"the rod automatically casts again after a catch"
	)
	core.fishing.session.cancel("player_moved")
	check(
		not core.fishing.session.is_active(),
		"cancelling ends the session immediately"
	)


func _test_context_snapshot_at_cast() -> void:
	var core := fresh_core(105)
	# Surround home with grove tiles mid-cast; the in-flight catch keeps its
	# original mostly-wild context, the next cast samples the grove.
	var generated: Array = []
	core.fishing.session.haul_generated.connect(func(h): generated.append(h))
	core.fishing.session.begin_session(Vector2i.ZERO)
	core.fishing.tick(0.1)
	for x in range(-1, 2):
		for y in range(-1, 2):
			var coord := Vector2i(x, y)
			if core.grid.has_cell(coord):
				core.grid.place_tile_at(coord, 0, "tile_grove_mature", 0)
	var elapsed := 0.0
	while generated.size() < 2 and elapsed < 200.0:
		core.fishing.tick(0.1)
		elapsed += 0.1
		for basket_haul in core.fishing.basket.hauls.duplicate():
			core.fishing.basket.discard_haul(basket_haul.haul_id)
	core.fishing.session.cancel("test")
	check(generated.size() >= 2, "two casts complete for the snapshot comparison")
	if generated.size() >= 2:
		check(
			String(generated[0].dominant_theme) != "grove",
			"the in-flight catch keeps the context from when its line went out"
		)
		check(
			String(generated[1].dominant_theme) == "grove",
			"the next cast samples the changed world"
		)


# ---------------------------------------------------------------- habitat

func _test_habitat_reads_exactly_3x3() -> void:
	var core := fresh_core(201)
	# Distinctive grove tiles at Chebyshev distance 1 versus distance 2.
	core.grid.place_tile(Vector2i(2, 0), "tile_grass")
	core.grid.place_tile(Vector2i(3, 0), "tile_grove_mature")
	var sample: FishingHabitatSample = core.fishing.habitat.sample(Vector2i.ZERO)
	check(
		sample.weight("grove") == 0.0,
		"a grove tile two cells away is outside the 3x3 sample"
	)
	core.grid.place_tile_at(Vector2i(1, 0), 0, "tile_grove_mature", 0)
	sample = core.fishing.habitat.sample(Vector2i.ZERO)
	check(
		sample.weight("grove") > 0.0,
		"a grove tile inside the 3x3 window contributes its theme"
	)


func _test_habitat_composition_and_cache() -> void:
	var core := fresh_core(202)
	var mixed: FishingHabitatSample = core.fishing.habitat.sample(Vector2i.ZERO)
	check(mixed.dominant_theme() == "wild", "an all-meadow 3x3 is strongly wild")
	for x in range(-1, 2):
		for y in range(-1, 2):
			core.grid.place_tile_at(Vector2i(x, y), 0, "tile_grove_mature", 0)
	var grove: FishingHabitatSample = core.fishing.habitat.sample(Vector2i.ZERO)
	check(grove.dominant_theme() == "grove", "a mostly grove 3x3 is strongly grove")
	check(
		grove.weight("grove") > mixed.weight("grove"),
		"terrain composition changes habitat weights"
	)
	var again: FishingHabitatSample = core.fishing.habitat.sample(Vector2i.ZERO)
	check(again == grove, "unchanged worlds reuse the cached habitat sample")
	core.grid.place_tile(Vector2i(5, 0), "tile_grass")
	var after_change: FishingHabitatSample = core.fishing.habitat.sample(Vector2i.ZERO)
	check(after_change != grove, "any grid change invalidates the edge cache")


func _test_habitat_model_tags_capped() -> void:
	var core := fresh_core(203)
	var bare: FishingHabitatSample = core.fishing.habitat.sample(Vector2i.ZERO)
	core.grid.add_structure(Vector2i(0, 0), "struct_pine", 1)
	var one_pine: FishingHabitatSample = core.fishing.habitat.sample(Vector2i.ZERO)
	check(
		one_pine.weight("grove") > bare.weight("grove"),
		"a placed model contributes its broad theme"
	)
	core.grid.add_structure(Vector2i(1, 0), "struct_pine", 1)
	core.grid.add_structure(Vector2i(0, 1), "struct_pine", 1)
	core.grid.add_structure(Vector2i(1, 1), "struct_pine", 1)
	var many_pines: FishingHabitatSample = core.fishing.habitat.sample(Vector2i.ZERO)
	check(
		is_equal_approx(many_pines.weight("grove"), one_pine.weight("grove")),
		"duplicate identical models never stack their contribution"
	)
	var config: Dictionary = core.fishing.balance.habitat_config()
	var cap := float(config.get("model_theme_cap", 2.0))
	var terrain_grove: float = bare.weight("grove")
	check(
		many_pines.weight("grove") - terrain_grove <= cap + 0.001,
		"model theme contributions stay under the configured cap"
	)


func _test_habitat_never_clones_model_ids() -> void:
	var core := fresh_core(204)
	core.grid.add_structure(Vector2i(0, 0), "struct_snowman", 1)
	var sample: FishingHabitatSample = core.fishing.habitat.sample(Vector2i.ZERO)
	for theme: String in sample.theme_weights:
		check(
			not theme.begins_with("struct_") and not theme.begins_with("tile_"),
			"the habitat sample carries broad themes, never exact item ids ('%s')" % theme
		)
	# The nearby snowman may raise the ODDITY theme, but reward selection
	# still weighs the whole oddity pool — no direct-clone shortcut exists.
	check(sample.weight("oddity") > 0.0, "an oddity model raises its broad theme")


# ---------------------------------------------------------------- loot pools

func _test_pool_composition_and_fallbacks() -> void:
	var core := fresh_core(301)
	# Force local-pool selection against a habitat that matches nothing.
	core.fishing.balance._data["source_pools"] = {"local": 1.0}
	var context := FishingRollContext.new(
		FishingHabitatSample.new(Vector2i.ZERO, 1, {"nonexistent_theme": 1.0})
	)
	context.unlock_groups = core.fishing.balance.unlock_groups()
	var before: int = core.fishing.generator.empty_pool_fallbacks
	var haul = core.fishing.generator.generate_haul(context)
	check(haul != null and haul.entry_count() >= 1, "an empty local pool still returns a real catch")
	check(
		core.fishing.generator.empty_pool_fallbacks > before,
		"the empty local pool logged its safe fallback to the global pool"
	)


func _test_locked_loot_excluded() -> void:
	var core := fresh_core(302)
	var locked := Defs.FishingLootDefinition.from_dict({
		"id": "loot_test_locked",
		"reward_kind": "tile_bundle",
		"building_definition_id": "tile_grass",
		"theme_tags": ["wild"],
		"pool_tags": ["global"],
		"rarity": "common",
		"base_weight": 9999.0,
		"unlock_group": "future_isles",
	})
	core.registries.fishing_loot["loot_test_locked"] = locked
	var catalog := BuildCatalogAdapter.new(core.registries, core.fishing.balance)
	var core_groups: Array[String] = ["core"]
	var with_future: Array[String] = ["core", "future_isles"]
	var visible_ids: Array = []
	for definition in catalog.candidates("tile_bundle", "global", core_groups):
		visible_ids.append(definition.id)
	check(
		not visible_ids.has("loot_test_locked"),
		"loot outside the active unlock groups is never a candidate"
	)
	var unlocked_ids: Array = []
	for definition in catalog.candidates("tile_bundle", "global", with_future):
		unlocked_ids.append(definition.id)
	check(
		unlocked_ids.has("loot_test_locked"),
		"activating an unlock group exposes its loot with no code change"
	)
	core.registries.fishing_loot.erase("loot_test_locked")


func _test_data_driven_loot_extension() -> void:
	var core := fresh_core(303)
	# A brand-new tagged definition — pure data — must flow through the same
	# generator untouched.
	var added := Defs.FishingLootDefinition.from_dict({
		"id": "loot_test_radio",
		"reward_kind": "model",
		"building_definition_id": "struct_sign",
		"theme_tags": ["oddity"],
		"pool_tags": ["local", "global", "wildcard"],
		"rarity": "uncommon",
		"base_weight": 100000.0,
	})
	core.registries.fishing_loot["loot_test_radio"] = added
	var catalog := BuildCatalogAdapter.new(core.registries, core.fishing.balance)
	var generator := FishingRewardGenerator.new(
		core.fishing.balance, catalog, core.fishing.composer,
		HiddenLuckService.new(core.fishing.balance), core.rng
	)
	core.fishing.balance._data["source_pools"] = {"global": 1.0}
	core.fishing.balance._data["single_form_weights"] = {"model": 1.0}
	core.fishing.balance._data["haul_sizes"] = {"single": 1.0}
	var context := FishingRollContext.new(
		FishingHabitatSample.new(Vector2i.ZERO, 1, {"oddity": 1.0})
	)
	context.unlock_groups = core.fishing.balance.unlock_groups()
	var haul = generator.generate_haul(context)
	check(
		haul.entries[0].loot_id == "loot_test_radio",
		"a new tagged loot definition works with no reward-generator change"
	)
	core.registries.fishing_loot.erase("loot_test_radio")


func _test_no_catchable_fish_possible() -> void:
	var core := fresh_core(304)
	var allowed_kinds := ["tile_bundle", "model", "keepsake"]
	for loot: Defs.FishingLootDefinition in core.registries.fishing_loot.values():
		check(
			allowed_kinds.has(loot.reward_kind),
			"loot '%s' uses an allowed reward form" % loot.id
		)
		var resolves_to_building := (
			core.registries.tile(loot.building_definition_id) != null
			or core.registries.structure(loot.building_definition_id) != null
			or core.registries.keepsake(loot.building_definition_id) != null
		)
		check(
			resolves_to_building,
			"loot '%s' resolves only to building content" % loot.id
		)
		check(
			core.registries.enemy(loot.building_definition_id) == null,
			"loot '%s' can never reference a creature" % loot.id
		)


## Static guard: the fishing feature never imports or calls ambient-fauna,
## creature, or combat systems — decoupling is verified mechanically.
func _test_fishing_never_touches_fauna_or_combat() -> void:
	var forbidden := [
		"ambient_fauna", "AmbientFauna", "CombatManager", "EnemyDefinition",
		"registries.enemy(", "water_interaction", "pigeon",
	]
	var root := "res://scripts/features/fishing"
	var stack: Array[String] = [root]
	var scanned := 0
	while not stack.is_empty():
		var directory_path: String = stack.pop_back()
		var directory := DirAccess.open(directory_path)
		if directory == null:
			continue
		directory.list_dir_begin()
		var entry := directory.get_next()
		while entry != "":
			var full := directory_path + "/" + entry
			if directory.current_is_dir() and not entry.begins_with("."):
				stack.append(full)
			elif entry.ends_with(".gd"):
				scanned += 1
				var source := FileAccess.get_file_as_string(full)
				for token: String in forbidden:
					check(
						not source.contains(token),
						"%s must not reference '%s'" % [full, token]
					)
			entry = directory.get_next()
	check(scanned >= 15, "the fauna/combat decoupling scan covered the fishing module")


# ---------------------------------------------------------------- composition

func _test_haul_multiplicity() -> void:
	var core := fresh_core(401)
	var context := FishingRollContext.new(core.fishing.habitat.sample(Vector2i.ZERO))
	context.unlock_groups = core.fishing.balance.unlock_groups()
	core.fishing.balance._data["haul_sizes"] = {"single": 1.0}
	var single = core.fishing.generator.generate_haul(context)
	check(single.entry_count() == 1, "a Normal Catch returns exactly one entry")
	core.fishing.balance._data["haul_sizes"] = {"rich": 1.0}
	for _index in 6:
		var rich = core.fishing.generator.generate_haul(context)
		check(rich.entry_count() == 2, "a Rich Catch returns exactly two entries")
		check(
			rich.tile_bundle_count() >= 1,
			"a Rich Catch guarantees at least one tile bundle"
		)
	core.fishing.balance._data["haul_sizes"] = {"bountiful": 1.0}
	for _index in 6:
		var bountiful = core.fishing.generator.generate_haul(context)
		check(bountiful.entry_count() == 3, "a Bountiful Catch returns exactly three entries")
		check(
			bountiful.tile_bundle_count() >= 2,
			"a Bountiful Catch prefers two tile bundles"
		)


func _test_bundle_quantities_respect_rarity() -> void:
	var core := fresh_core(402)
	var context := FishingRollContext.new(core.fishing.habitat.sample(Vector2i.ZERO))
	context.unlock_groups = core.fishing.balance.unlock_groups()
	for _index in 120:
		var haul = core.fishing.generator.generate_haul(context)
		for entry: FishingReward in haul.entries:
			if entry.form != FishingReward.FORM_TILE_BUNDLE:
				check(entry.quantity == 1, "models are caught individually")
				continue
			var definition := core.registries.fishing_loot_definition(entry.loot_id)
			var expected := Vector2i(definition.bundle_min, definition.bundle_max)
			if expected.x <= 0 or expected.y < expected.x:
				expected = core.fishing.balance.bundle_range(definition.rarity)
			check(
				entry.quantity >= expected.x and entry.quantity <= expected.y,
				"bundle '%s' quantity %d respects its %s range %s"
				% [entry.loot_id, entry.quantity, entry.rarity, expected]
			)


func _test_keepsake_independent_bonus() -> void:
	var core := fresh_core(403)
	var context := FishingRollContext.new(core.fishing.habitat.sample(Vector2i.ZERO))
	context.unlock_groups = core.fishing.balance.unlock_groups()
	core.fishing.balance._data["keepsake"] = {
		"base_chance": 1.0, "pity_start": 999, "pity_bonus_per_catch": 0.0,
	}
	core.fishing.balance._data["haul_sizes"] = {"rich": 1.0}
	var haul = core.fishing.generator.generate_haul(context)
	check(haul.has_keepsake(), "a guaranteed keepsake roll appends the bonus")
	check(
		haul.entry_count() == 2,
		"the keepsake never replaces a normal reward entry"
	)
	check(
		haul.keepsake.form == FishingReward.FORM_KEEPSAKE
		and core.registries.keepsake(haul.keepsake.building_id) != null,
		"the bonus is a real keepsake definition"
	)
	# Owned unique keepsakes never re-roll.
	context.owned_keepsake_ids = ["keepsake_growth"] as Array[String]
	var repeat = core.fishing.generator.generate_haul(context)
	check(
		not repeat.has_keepsake(),
		"a unique keepsake already owned is excluded from the bonus roll"
	)


func _test_hidden_luck_protection() -> void:
	var core := fresh_core(404)
	var luck := HiddenLuckService.new(core.fishing.balance as FishingBalance)
	check(is_equal_approx(luck.rare_weight_multiplier(), 1.0), "protection sleeps below its threshold")
	luck.state.catches_since_rare = core.fishing.balance.rare_pity_start() + 4
	check(
		luck.rare_weight_multiplier() > 1.0,
		"a long dry streak quietly raises rare weights"
	)
	var boosted_chance: float = core.fishing.balance.keepsake_base_chance()
	luck.state.catches_since_keepsake = core.fishing.balance.keepsake_pity_start() + 10
	check(luck.keepsake_chance() > boosted_chance, "keepsake protection ramps separately")
	# Resets happen only on the committed matching reward.
	var plain := FishingHaul.new()
	plain.entries.append(FishingReward.make("tile_bundle", "loot_tile_grass", "tile_grass", 4, "common"))
	var rare_streak := luck.state.catches_since_rare
	luck.on_haul_committed(plain)
	check(luck.state.catches_since_rare == rare_streak + 1, "a plain catch deepens the rare streak")
	var rare := FishingHaul.new()
	rare.entries.append(FishingReward.make("model", "loot_model_stone_well", "struct_stone_well", 1, "rare"))
	luck.on_haul_committed(rare)
	check(luck.state.catches_since_rare == 0, "a committed rare reward resets rare protection")
	check(luck.state.catches_since_keepsake > 0, "the keepsake counter is untouched by a rare tile")
	var with_keepsake := FishingHaul.new()
	with_keepsake.entries.append(FishingReward.make("tile_bundle", "loot_tile_grass", "tile_grass", 4, "common"))
	with_keepsake.keepsake = FishingReward.make("keepsake", "loot_keepsake_growth", "keepsake_growth", 1, "rare")
	luck.on_haul_committed(with_keepsake)
	check(luck.state.catches_since_keepsake == 0, "a committed keepsake resets its protection")
	var round_trip := HiddenLuckService.new(core.fishing.balance)
	round_trip.from_save_dict(luck.to_save_dict())
	check(
		round_trip.state.catches_since_rare == luck.state.catches_since_rare
		and round_trip.state.catches_since_keepsake == luck.state.catches_since_keepsake,
		"hidden protection state saves and loads"
	)


# ---------------------------------------------------------------- spirits

func _test_spirit_pouch_rules() -> void:
	var core := fresh_core(501)
	var pouch: SpiritPouchService = core.fishing.pouch
	for index in 7:
		pouch.add_spirit("spirit_grove" if index % 2 == 0 else "spirit_stone")
	check(pouch.slots().size() == 5, "the pouch never exceeds five charms")
	check(pouch.is_full(), "a full pouch reports itself")
	var rejected: Array = []
	pouch.spirit_rejected_full.connect(func(id): rejected.append(id))
	check(not pouch.add_spirit("spirit_grove"), "a sixth charm is refused")
	check(rejected.size() == 1, "refusal emits gentle feedback instead of overflow storage")
	check(not pouch.add_spirit("spirit_unknown"), "unknown spirit ids are refused")
	check(pouch.arm_slot(2), "any held charm can be armed")
	check(pouch.armed_index() == 2, "the armed slot is visible")
	pouch.select_wild_cast()
	check(pouch.armed_index() == -1, "selecting Wild Cast clears the armed charm")
	check(pouch.slots().size() == 5, "clearing the armed charm destroys nothing")


func _test_spirit_targets_theme_only() -> void:
	var core := fresh_core(502)
	var generator: FishingRewardGenerator = core.fishing.generator
	var context := FishingRollContext.new(
		FishingHabitatSample.new(Vector2i.ZERO, 1, {"wild": 1.0})
	)
	context.unlock_groups = core.fishing.balance.unlock_groups()
	var grove_common := core.registries.fishing_loot_definition("loot_model_pine")
	var grove_rare := core.registries.fishing_loot_definition("loot_model_stone_well")
	# Weight ratio between two candidates must be unchanged by the spirit
	# unless the theme differs — spirits never touch rarity itself.
	var plain_common: float = generator._candidate_weight(grove_common, "global", context)
	var plain_rare: float = generator._candidate_weight(grove_rare, "global", context)
	context.spirit_theme = "grove"
	var spirit_common: float = generator._candidate_weight(grove_common, "global", context)
	var spirit_rare: float = generator._candidate_weight(grove_rare, "global", context)
	check(
		spirit_common > plain_common,
		"a Grove Spirit strongly weights grove-tagged content"
	)
	check(
		is_equal_approx(spirit_rare, plain_rare),
		"non-matching content keeps its exact weight — no hidden rarity change"
	)
	# Multiplicity and keepsake odds are drawn from independent streams: the
	# same seed produces the same size and keepsake pattern with or without a
	# Spirit armed.
	var wild_report: Dictionary = core.fishing.run_simulation(4242, 1500, Vector2i.ZERO, "")
	var spirit_report: Dictionary = core.fishing.run_simulation(4242, 1500, Vector2i.ZERO, "grove")
	check(
		str(wild_report["sizes"]) == str(spirit_report["sizes"]),
		"Spirits do not affect single/rich/bountiful multiplicity"
	)
	check(
		int(wild_report["keepsakes"]) == int(spirit_report["keepsakes"]),
		"Spirits do not affect Keepsake odds"
	)
	check(
		int(spirit_report["themes"].get("grove", 0)) > int(wild_report["themes"].get("grove", 0)),
		"the Grove Spirit visibly leans results toward grove content"
	)


func _test_spirit_lifecycle_through_session() -> void:
	var core := fresh_core(503)
	core.fishing.pouch.add_spirit("spirit_grove")
	core.fishing.pouch.arm_slot(0)
	# Cancelled cast: the reservation returns to the pouch.
	core.fishing.session.begin_session(Vector2i.ZERO)
	core.fishing.tick(0.1)
	check(core.fishing.pouch.state.has_reservation(), "a starting cast reserves the armed charm")
	core.fishing.session.cancel("player_moved")
	check(
		not core.fishing.pouch.state.has_reservation()
		and core.fishing.pouch.slots() == ["spirit_grove"]
		and core.fishing.pouch.armed_index() == 0,
		"a cancelled cast returns the reserved Spirit unharmed"
	)
	# Committed catch: consumed exactly once.
	var haul = run_one_catch(core)
	check(haul != null, "the spirit-armed catch commits")
	check(haul.spirit_id == "spirit_grove", "the haul records the charm that shaped it")
	check(core.fishing.pouch.slots().is_empty(), "the Spirit is consumed after the commit")
	core.fishing.session.cancel("test")
	var second = run_one_catch(core)
	check(second != null and second.spirit_id == "", "the next cast is Wild again — one Spirit, one catch")
	core.fishing.session.cancel("test")


func _test_activity_adapters_grant_spirits() -> void:
	var core := fresh_core(504)
	core.progression.on_activity_cycle_completed("woodcutting")
	check(
		core.fishing.pouch.slots() == ["spirit_grove"],
		"a completed tree cycle grants one Grove Spirit through the event adapter"
	)
	core.progression.on_activity_cycle_completed("mining")
	check(
		core.fishing.pouch.slots() == ["spirit_grove", "spirit_stone"],
		"a completed rock cycle grants one Stone Spirit through the same narrow event"
	)
	core.progression.on_activity_cycle_completed("unknown_activity")
	check(
		core.fishing.pouch.slots().size() == 2,
		"unmapped activities grant nothing"
	)


# ---------------------------------------------------------------- basket

func _test_basket_stores_three_hauls() -> void:
	var core := fresh_core(601)
	check(core.fishing.basket.capacity() == 3, "the Catch Basket holds three hauls")
	core.fishing.debug_force_catch(Vector2i.ZERO)   # burn the water guarantee
	core.fishing.debug_clear_basket()
	core.fishing.balance._data["haul_sizes"] = {"bountiful": 1.0}
	var haul = core.fishing.debug_force_catch(Vector2i.ZERO, "bountiful")
	check(
		haul != null and haul.entry_count() == 3
		and core.fishing.basket.haul_count() == 1,
		"one Bountiful triple occupies exactly one basket slot"
	)
	core.fishing.debug_force_catch(Vector2i.ZERO)
	core.fishing.debug_force_catch(Vector2i.ZERO)
	check(core.fishing.basket.is_full(), "three hauls fill the basket")
	check(
		core.fishing.debug_force_catch(Vector2i.ZERO) == null,
		"a full basket accepts nothing more — no overwrite, no discard"
	)


func _test_basket_full_pauses_and_resumes() -> void:
	var core := fresh_core(602)
	for _index in 3:
		core.fishing.debug_force_catch(Vector2i.ZERO)
	var paused: Array = []
	core.fishing.session.basket_full_paused.connect(func(): paused.append(true))
	core.fishing.session.begin_session(Vector2i.ZERO)
	check(
		core.fishing.session.state == FishingSessionStates.State.PAUSED_BASKET_FULL
		and not paused.is_empty(),
		"fishing pauses with clear feedback while the basket is full"
	)
	for _index in 50:
		core.fishing.tick(1.0)
	check(
		core.fishing.session.state == FishingSessionStates.State.PAUSED_BASKET_FULL,
		"a paused session never quietly resumes on its own"
	)
	var first_id: int = core.fishing.basket.hauls[0].haul_id
	core.fishing.basket.discard_haul(first_id)
	check(
		core.fishing.session.is_active()
		and core.fishing.session.state != FishingSessionStates.State.PAUSED_BASKET_FULL,
		"freeing a slot resumes the session automatically"
	)
	core.fishing.session.cancel("test")


func _test_bundle_placement_roundtrip() -> void:
	var core := fresh_core(603)
	var haul = core.fishing.debug_force_catch(Vector2i.ZERO)
	check(haul != null, "a haul lands for the placement round trip")
	# The guaranteed first catch is a water tile bundle.
	var entry = haul.primary_entry()
	check(
		entry.form == FishingReward.FORM_TILE_BUNDLE,
		"the first catch stages a tile bundle"
	)
	var quantity: int = entry.quantity
	var taken: Dictionary = core.fishing.basket.take_tile_bundle(haul.haul_id, 0)
	check(
		int(taken["quantity"]) == quantity
		and core.stock.tile_count(entry.building_id) == quantity,
		"activating the bundle checks its copies into the Build Library"
	)
	check(
		core.place_tile_from_stock(Vector2i(2, 0), entry.building_id, 0),
		"bundle tiles place through the existing placement pipeline"
	)
	core.fishing.basket.reconcile_bundle_checkout()
	var remaining = core.fishing.basket.haul_by_id(haul.haul_id)
	if quantity > 1:
		check(
			remaining != null
			and remaining.entries[0].quantity == quantity - 1
			and core.stock.tile_count(entry.building_id) == 0,
			"cancelled placement returns the unused quantity to the basket"
		)
	else:
		check(remaining == null, "an exhausted bundle frees its haul slot")


func _test_model_and_keepsake_taking() -> void:
	var core := fresh_core(604)
	core.fishing.debug_force_catch(Vector2i.ZERO)   # burn the water guarantee
	core.fishing.debug_clear_basket()
	core.fishing.balance._data["haul_sizes"] = {"single": 1.0}
	core.fishing.balance._data["single_form_weights"] = {"model": 1.0}
	core.fishing.balance._data["keepsake"] = {
		"base_chance": 1.0, "pity_start": 999, "pity_bonus_per_catch": 0.0,
	}
	var haul = core.fishing.debug_force_catch(Vector2i.ZERO)
	check(haul != null and haul.model_count() == 1, "a model haul lands")
	check(haul.has_keepsake(), "the forced keepsake bonus rides along")
	var model_entry = haul.entries[0]
	var structure_id: String = core.fishing.basket.take_model(haul.haul_id, 0)
	check(
		structure_id == model_entry.building_id
		and core.stock.structure_count(structure_id) >= 1,
		"taking a model hands it to the Build Library placement flow"
	)
	var slot_freed_early: bool = core.fishing.basket.haul_by_id(haul.haul_id) != null
	check(slot_freed_early, "the keepsake keeps its slot until it is taken")
	var keepsake_id: String = core.fishing.activate_keepsake_from_basket(haul.haul_id)
	check(keepsake_id == "keepsake_growth", "the keepsake activates through its service")
	check(core.fishing.basket.haul_by_id(haul.haul_id) == null, "the emptied haul frees its slot")
	check(
		core.fishing.keepsakes.is_effect_active("growth"),
		"the Growth effect is live after activation"
	)
	# The Growth Keepsake shifts placed trees between authored variants.
	var tree = core.grid.add_structure(Vector2i(0, 0), "struct_pine", 1)
	check(tree != null, "a pine places for the growth test")
	check(
		core.fishing.keepsakes.cycle_tree_variant(tree.instance_id),
		"an appropriate tree accepts the growth interaction"
	)
	var found := core.grid.find_structure(tree.instance_id)
	check(
		not found.is_empty()
		and (found["structure"] as WorldGrid.StructureState).structure_id == "struct_pine_tall",
		"growth cycles the pine to its next authored size variant"
	)
	var discarded_stock := core.stock.total_tiles()
	core.fishing.debug_force_catch(Vector2i.ZERO)
	var to_discard = core.fishing.basket.hauls[0]
	check(core.fishing.basket.discard_haul(to_discard.haul_id), "an unwanted haul returns to the void")
	check(
		core.stock.total_tiles() == discarded_stock,
		"returning a haul grants no currency or compensation"
	)


func _test_basket_persistence() -> void:
	var core := fresh_core(605)
	core.fishing.balance._data["keepsake"] = {
		"base_chance": 1.0, "pity_start": 999, "pity_bonus_per_catch": 0.0,
	}
	core.fishing.debug_force_catch(Vector2i.ZERO)
	core.fishing.debug_force_catch(Vector2i.ZERO)
	var saved_payload := str(core.fishing.basket.to_save_dict())
	check(core.save(), "the basket saves")
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	check(restored.load_game(), "the basket loads")
	check(
		str(restored.fishing.basket.to_save_dict()) == saved_payload,
		"pending basket hauls survive save/load exactly"
	)


func _test_first_catch_guarantee() -> void:
	var core := fresh_core(606)
	var haul = run_one_catch(core)
	core.fishing.session.cancel("test")
	check(
		haul != null
		and haul.entry_count() == 1
		and haul.primary_entry().building_id == "tile_open_water",
		"the first-ever catch guarantees buildable water"
	)
	check(core.fishing.first_catch_done, "the guarantee is recorded once")
	var second = run_one_catch(core)
	core.fishing.session.cancel("test")
	check(second != null, "later catches roll the normal pools")


# ---------------------------------------------------------------- statistics

func _test_determinism_with_seed() -> void:
	var core := fresh_core(701)
	var report_a: Dictionary = core.fishing.run_simulation(2024, 800, Vector2i.ZERO)
	var report_b: Dictionary = core.fishing.run_simulation(2024, 800, Vector2i.ZERO)
	check(str(report_a) == str(report_b), "an injected seed makes generation fully deterministic")
	var report_c: Dictionary = core.fishing.run_simulation(2025, 800, Vector2i.ZERO)
	check(str(report_a) != str(report_c), "different seeds diverge")


func _test_distribution_simulation() -> void:
	var core := fresh_core(702)
	var catches := 20000
	var report: Dictionary = core.fishing.run_simulation(90210, catches, Vector2i.ZERO)
	var singles := float(report["sizes"]["single"]) / catches
	var riches := float(report["sizes"]["rich"]) / catches
	var bountifuls := float(report["sizes"]["bountiful"]) / catches
	check(absf(singles - 0.80) < 0.02, "Normal Catch rate ~80%% (got %.3f)" % singles)
	check(absf(riches - 0.17) < 0.02, "Rich Catch rate ~17%% (got %.3f)" % riches)
	check(absf(bountifuls - 0.03) < 0.01, "Bountiful Catch rate ~3%% (got %.3f)" % bountifuls)
	var tiles := int(report["forms"]["tile_bundle"])
	var models := int(report["forms"]["model"])
	var tile_share := float(tiles) / float(tiles + models)
	check(
		tile_share > 0.58 and tile_share < 0.82,
		"most rewards are tile bundles without starving models (got %.3f)" % tile_share
	)
	check(
		int(report["tiles_granted"]) > catches * 2,
		"fishing supplies useful building volume, never single scraps"
	)
	var keepsake_rate := float(report["keepsakes"]) / catches
	check(
		keepsake_rate > 0.02 and keepsake_rate < 0.12,
		"keepsakes stay rare bonuses (got %.3f)" % keepsake_rate
	)
	check(int(report["empty_pool_fallbacks"]) == 0, "shipped content never hits the empty-pool fallback")
	check(int(report["invalid_definitions"]) == 0, "no shipped loot definition is invalid")
	check(
		int(report["rarities"]["rare"]) > 0
		and int(report["rarities"]["uncommon"]) > 0,
		"rare and uncommon outcomes both occur"
	)


func _test_grove_and_stone_habitats_distinct() -> void:
	var core := fresh_core(703)
	for x in range(-1, 2):
		for y in range(-1, 2):
			core.grid.place_tile_at(Vector2i(x, y), 0, "tile_grove_mature", 0)
	var grove_report: Dictionary = core.fishing.run_simulation(555, 3000, Vector2i.ZERO)
	core.grid.place_tile(Vector2i(20, 20), "tile_concrete_brutalist")
	for x in range(19, 22):
		for y in range(19, 22):
			if not core.grid.has_cell(Vector2i(x, y)):
				core.grid.place_tile(Vector2i(x, y), "tile_concrete_brutalist")
			else:
				core.grid.place_tile_at(Vector2i(x, y), 0, "tile_concrete_brutalist", 0)
	var stone_report: Dictionary = core.fishing.run_simulation(555, 3000, Vector2i(20, 20))
	check(
		int(grove_report["themes"].get("grove", 0)) > int(stone_report["themes"].get("grove", 0)),
		"a grove cove leans its catches toward grove content"
	)
	check(
		int(stone_report["themes"].get("stone", 0)) > int(grove_report["themes"].get("stone", 0)),
		"a stone terrace leans its catches toward stone content"
	)
	check(
		str(grove_report["sizes"]) == str(stone_report["sizes"]),
		"habitats change themes, never haul multiplicity"
	)
