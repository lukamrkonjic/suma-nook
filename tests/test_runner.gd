extends SceneTree
## Headless validation suite. Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/test_runner.gd
## Must print "ALL TESTS PASSED".

var failures: PackedStringArray = []
var assertions := 0


func _init() -> void:
	_run()
	if failures.is_empty():
		print("ALL TESTS PASSED — %d assertions" % assertions)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		print("TESTS FAILED — %d failures / %d assertions" % [failures.size(), assertions])
		quit(1)


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func fresh_core(seed_value := 12345) -> GameCore:
	var core := GameCore.new()
	core.setup("res://data", seed_value)
	core.save_manager.save_path = "user://test_save.json"
	core.save_manager.backup_path = "user://test_save.json.backup"
	var profile := PlayerProfile.new()
	profile.display_name = "Testkeeper"
	core.new_game(profile)
	return core


func _run() -> void:
	_test_input_bindings()
	_test_registries()
	_test_starting_world()
	_test_xp_only_hobbies()
	_test_hobby_journal_and_direct_rewards()
	_test_disabled_legacy_systems()
	_test_arrival_and_parcel_loop()
	_test_arrival_queue_and_presentation_swap()
	_test_tile_adjacency_overlap_rotation()
	_test_connectivity_and_relocation()
	_test_sockets_and_overlap_prevention()
	_test_anchor_cycle_and_regen()
	_test_rework_save_round_trip()
	_test_missing_definition_load()


func _test_input_bindings() -> void:
	check(_action_has_key("move_up", KEY_W), "W remains bound to character movement")
	check(_action_has_key("move_left", KEY_A), "A remains bound to character movement")
	check(not _action_has_key("move_up", KEY_UP), "up arrow no longer moves the character")
	check(not _action_has_key("move_left", KEY_LEFT), "left arrow no longer moves the character")
	check(_action_has_key("camera_rotate_right", KEY_LEFT), "left arrow uses the reversed camera spin")
	check(_action_has_key("camera_rotate_left", KEY_RIGHT), "right arrow uses the reversed camera spin")
	check(_action_has_key("camera_zoom_in", KEY_UP), "up arrow zooms the camera in")
	check(_action_has_key("camera_zoom_out", KEY_DOWN), "down arrow zooms the camera out")


func _action_has_key(action: StringName, physical_keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event != null and key_event.physical_keycode == physical_keycode:
			return true
	return false


func _test_registries() -> void:
	var regs := Registries.new()
	check(regs.load_all(), "all data files load and cross-validate: " + ", ".join(regs.load_errors))
	check(regs.skills.size() == 3, "three skills defined")
	check(regs.tiles.size() >= 15, "at least 15 tile variants")
	check(regs.skill("mining").future, "mining is a future (data-only) skill")
	check(not regs.feature("legacy_material_loot_enabled"), "ordinary material loot is disabled")
	check(not regs.feature("combat_enabled"), "combat is disabled")
	check(regs.feature("ferry_arrivals_enabled"), "periodic arrivals are enabled")
	var fishing := regs.skill("fishing")
	check(fishing.xp_to_next(1) > 0 and fishing.xp_to_next(2) > fishing.xp_to_next(1), "xp curve increases")


func _test_starting_world() -> void:
	var core := fresh_core()
	check(core.grid.cells.size() == 9, "fresh save starts with exactly nine cells")
	var water: Array[Vector2i] = []
	var walkable := 0
	for coord: Vector2i in core.grid.cells:
		if core.grid.tile_def(coord).id == "tile_open_water":
			water.append(coord)
		if core.grid.is_walkable(coord):
			walkable += 1
	check(water.size() == 3, "starting world has exactly three water cells")
	check(water.has(Vector2i(-1, -1)) and water.has(Vector2i(0, -1)) and water.has(Vector2i(1, -1)), "water occupies the northern/top row")
	check(walkable == 6, "the other six starting cells are walkable land")
	check(water[0].distance_squared_to(water[1]) <= 4 and water[1].distance_squared_to(water[2]) <= 4, "the water cells form one connected edge")
	check(core.grid.is_walkable(Vector2i.ZERO), "home cell walkable")
	check(core.grid.world_to_cell(core.profile.position) == Vector2i.ZERO, "player spawns safely on central land")
	check(core.equipment.owns("tool_rod_basic"), "starter rod owned")


func _test_xp_only_hobbies() -> void:
	var core := fresh_core(404)
	var inventory_before := core.inventory.counts.duplicate()
	for hobby_id in ["fishing", "woodcutting"]:
		var skill := core.registries.skill(hobby_id)
		var old_chance := skill.direct_tile_reward_chance
		skill.direct_tile_reward_chance = 0.0
		var result := core.rewards.resolve_hobby_action(skill)
		core.skills.record_action(hobby_id)
		core.skills.add_xp(hobby_id, result.xp_awarded)
		check(result.xp_awarded == skill.action_xp, "%s action returns configured XP" % hobby_id)
		check(core.skills.xp_progress(hobby_id)["current"] == skill.action_xp, "%s XP reaches hobby progression" % hobby_id)
		check(not result.has_world_reward(), "ordinary %s action has no forced world reward" % hobby_id)
		skill.direct_tile_reward_chance = old_chance
	check(str(core.inventory.counts) == str(inventory_before), "Fishing and Woodland Tending add no common inventory items")
	check(core.rewards.roll_action_loot(core.registries.skill("fishing")).is_empty(), "disabled legacy fishing table cannot produce materials")
	check(core.rewards.roll_action_loot(core.registries.skill("woodcutting")).is_empty(), "disabled legacy wood table cannot produce materials")


func _test_hobby_journal_and_direct_rewards() -> void:
	var core := fresh_core(505)
	var fishing := core.registries.skill("fishing")
	core.registries.tuning["fishing_collection_chance"] = 1.0
	var old_entries := fishing.collection_entries.duplicate()
	fishing.collection_entries = ["test_sunfish"] as Array[String]
	var first := core.rewards.resolve_hobby_action(fishing)
	check(first.collection_discovery_id == "test_sunfish", "first-time fish resolves a journal entry")
	check(first.was_new_discovery, "first journal catch is marked new")
	check(core.collection.is_discovered("fish", "test_sunfish"), "journal metadata is recorded")
	check(core.inventory.counts.is_empty(), "journal discovery creates no fish item stack")
	var before_tiles := core.stock.tile_count("tile_open_water")
	var old_chance := fishing.direct_tile_reward_chance
	var old_pool := fishing.direct_tile_reward_pool.duplicate()
	fishing.direct_tile_reward_chance = 1.0
	fishing.direct_tile_reward_pool = ["tile_open_water"] as Array[String]
	var rare := core.rewards.resolve_hobby_action(fishing)
	check(rare.optional_tile_reward_id == "tile_open_water", "rare hobby reward is already a finished tile")
	check(core.stock.tile_count("tile_open_water") == before_tiles + 1, "rare tile enters the Tile Library directly")
	check(core.inventory.counts.is_empty(), "rare world reward bypasses material inventory")
	fishing.collection_entries = old_entries
	fishing.direct_tile_reward_chance = old_chance
	fishing.direct_tile_reward_pool = old_pool


func _test_disabled_legacy_systems() -> void:
	var core := fresh_core()
	check(core.crafting.available_recipes().is_empty(), "material crafting recipes are hidden")
	check(not core.crafting.craft("recipe_meadow_parcel"), "material-to-land crafting is disabled")
	for i in 20:
		core.stock.add_tile("tile_grass")
		var coord := Vector2i(2 + i, 0)
		core.place_tile_from_stock(coord, "tile_grass", 0)
	check(core.landmarks.active.is_empty(), "world growth creates no hostile landmarks")
	check(not core.registries.feature("monsters_enabled"), "monster spawning flag remains disabled")
	check(not core.registries.feature("hostile_landmarks_enabled"), "hostile landmark flag remains disabled")


func _test_arrival_and_parcel_loop() -> void:
	var core := fresh_core(606)
	var requested: Array = []
	core.arrivals.arrival_requested.connect(func(payload): requested.append(payload))
	core.arrivals.time_until_next = 0.01
	core.tick(0.02)
	check(requested.size() == 1, "arrival timer requests exactly one presentation")
	check(core.arrivals.state == ArrivalScheduler.ARRIVING, "arrival enters presentation state")
	var payload := requested[0] as LandParcelPayload
	check(payload.parcel_id == "parcel_wild", "ferry payload is a Land Parcel")
	core.arrivals.mark_delivery_ready(payload)
	check(core.arrivals.has_waiting_package(), "ferry unloads one waiting package")
	var options := core.arrivals.open_waiting(core.parcels)
	check(options.size() == 3, "dock package reveals three tile choices")
	check(core.arrivals.state == ArrivalScheduler.OPENED, "scheduler pauses while parcel choice is open")
	var chosen := core.parcels.choose(0)
	check(chosen == options[0], "selected parcel option is authoritative")
	check(core.stock.tile_count(chosen) == 1, "selected tile enters the Tile Library")
	for index in range(1, options.size()):
		if options[index] != chosen:
			check(core.stock.tile_count(options[index]) == 0, "unselected tile does not enter any inventory")
	core.arrivals.resolve_delivery()
	check(core.arrivals.state == ArrivalScheduler.IDLE, "next timer begins after the choice is stored")
	check(core.arrivals.time_until_next >= 300.0, "later arrival uses configured relaxed timing")


func _test_arrival_queue_and_presentation_swap() -> void:
	var core := fresh_core(707)
	var requests := [0]
	core.arrivals.arrival_requested.connect(func(_payload): requests[0] += 1)
	check(core.arrivals.set_presentation("postcard"), "debug presentation can switch to postcard")
	check(core.arrivals.presentation_id == "postcard", "presentation selection is state only")
	check(core.arrivals.trigger_arrival(), "postcard uses the same scheduler")
	check(requests[0] == 1, "selected presentation receives one generic request")
	var payload := core.arrivals.current_payload
	core.arrivals.mark_delivery_ready(payload)
	check(not core.arrivals.trigger_arrival(), "unopened package blocks delivery accumulation")
	var fishing := core.registries.skill("fishing")
	fishing.direct_tile_reward_chance = 0.0
	core.rewards.resolve_hobby_action(fishing)
	check(core.arrivals.has_waiting_package(), "player can perform a hobby while ferry package waits")
	check(core.arrivals.deliveries_created == 0, "waiting never creates unattended delivery stacks")


func _test_xp_and_unlocks() -> void:
	var core := fresh_core()
	var levels: Array = []
	core.skills.level_up.connect(func(_s, l, _u): levels.append(l))
	var def := core.registries.skill("fishing")
	core.skills.add_xp("fishing", def.xp_to_next(1))
	check(core.skills.level("fishing") == 2, "xp reaching threshold levels up")
	check(levels == [2], "level_up signal fired once")
	check(core.inventory.count("parcel_wild") == 1, "fishing 2 unlock granted the first Land Parcel deterministically")
	check(core.skills.unlocked("fishing", "recipe").is_empty() == false or core.skills.level("fishing") < 3, "recipe unlock query consistent")
	# leveling far unlocks tile pool entries
	core.skills.add_xp("fishing", 100000)
	check(core.skills.level("fishing") == def.max_level, "xp clamps at max level")


func _test_deterministic_rng() -> void:
	var a := fresh_core(777)
	var b := fresh_core(777)
	var skill := a.registries.skill("fishing")
	var seq_a: Array = []
	var seq_b: Array = []
	for i in 12:
		seq_a.append(a.rewards.roll_action_loot(skill))
		seq_b.append(b.rewards.roll_action_loot(skill))
	check(str(seq_a) == str(seq_b), "identical seeds produce identical loot sequences")
	var c := fresh_core(778)
	var differs := false
	for i in 12:
		if str(c.rewards.roll_action_loot(skill)) != str(seq_a[i]):
			differs = true
	check(differs, "different seeds diverge")


func _test_fishing_rewards_and_tutorial() -> void:
	var core := fresh_core()
	var skill := core.registries.skill("fishing")
	var fragment_seen := false
	var by_catch := core.registries.tunei("tutorial_fragment_by_catch", 3)
	for i in by_catch:
		var grants := core.rewards.roll_action_loot(skill)
		for grant in grants:
			check(core.registries.item(grant["item_id"]) != null, "loot grants reference real items")
			if grant["item_id"] == "land_fragment":
				fragment_seen = true
	check(fragment_seen, "a Land Fragment is guaranteed within the first %d catches" % by_catch)


func _test_rare_pity() -> void:
	var core := fresh_core(4242)
	var skill := core.registries.skill("woodcutting")
	var pity_max := core.registries.tunei("rare_pity_max_dry", 9)
	var longest_dry := 0
	var dry := 0
	for i in 60:
		var grants := core.rewards.roll_action_loot(skill)
		var got_rare_layer := grants.size() > 1
		if got_rare_layer:
			dry = 0
		else:
			dry += 1
			longest_dry = maxi(longest_dry, dry)
	check(longest_dry <= pity_max, "pity caps rare-less streaks at %d (saw %d)" % [pity_max, longest_dry])


func _test_parcels_choice_and_duplicates() -> void:
	var core := fresh_core()
	core.inventory.grant("parcel_wild", 2, false, true)
	var options := core.parcels.open("parcel_wild")
	check(options.size() == 3, "parcel reveals three options")
	var guaranteed: Array = core.registries.tune("guaranteed_first_parcel_options", [])
	check(str(options) == str(guaranteed), "first-ever parcel offers the guaranteed grove trio")
	var chosen := core.parcels.choose(0)
	check(chosen == options[0], "choose returns the picked tile")
	check(core.stock.tile_count(chosen) == 1, "chosen tile lands in build stock")
	check(core.collection.is_discovered("tiles", chosen), "choice recorded in collection")
	# duplicate → pattern dust
	var before_dust := core.inventory.count("pattern_dust")
	core.parcels.open("parcel_wild")
	core.parcels.pending_options = [chosen, chosen, chosen] as Array[String]
	core.parcels.choose(0)
	check(core.inventory.count("pattern_dust") > before_dust, "duplicate choice converts to Pattern Dust")
	check(core.parcels.duplicate_streak == 1, "duplicate streak advanced")


func _test_new_tile_pity() -> void:
	var core := fresh_core()
	core.parcels.opened_count = 1   # skip tutorial guarantee
	core.parcels.duplicate_streak = core.registries.tunei("new_tile_pity_max_duplicates", 4)
	core.collection.record("tiles", "tile_grass")
	core.inventory.grant("parcel_wild", 1, false, true)
	var options := core.parcels.open("parcel_wild")
	var has_fresh := false
	for tile_id in options:
		if not core.collection.is_discovered("tiles", tile_id):
			has_fresh = true
	check(has_fresh, "duplicate pity forces an undiscovered tile into the reveal")


func _test_tile_adjacency_overlap_rotation() -> void:
	var core := fresh_core()
	check(not core.grid.can_place_tile(Vector2i(5, 5)), "detached placement rejected")
	check(not core.grid.can_place_tile(Vector2i.ZERO), "overlap rejected")
	check(core.grid.can_place_tile(Vector2i(2, 0)), "edge-adjacent placement accepted")
	core.stock.add_tile("tile_grass")
	check(core.place_tile_from_stock(Vector2i(2, 0), "tile_grass", 3), "placement from stock succeeds")
	check(core.grid.cell(Vector2i(2, 0)).rotation == 3, "rotation persists on the placed cell")
	check(not core.place_tile_from_stock(Vector2i(2, 0), "tile_grass", 0), "double placement rejected")
	check(core.stock.tile_count("tile_grass") == 0, "stock consumed exactly once")


func _test_connectivity_and_relocation() -> void:
	var core := fresh_core()
	core.stock.add_tile("tile_grass")
	core.stock.add_tile("tile_grass")
	core.place_tile_from_stock(Vector2i(2, 0), "tile_grass", 0)
	core.place_tile_from_stock(Vector2i(3, 0), "tile_grass", 0)
	check(not core.grid.connected_without(Vector2i(2, 0), core.grid.home_cell), "removing a bridge tile is detected as a split")
	check(core.grid.connected_without(Vector2i(3, 0), core.grid.home_cell), "removing a leaf tile keeps the world whole")
	var refuge := core.grid.nearest_walkable(Vector2i(3, 0), Vector2i(3, 0))
	check(refuge != Vector2i(3, 0) and core.grid.is_walkable(refuge), "safe relocation finds a nearby walkable cell")


func _test_sockets_and_overlap_prevention() -> void:
	var core := fresh_core()
	var coord := Vector2i(0, 0)
	var def := core.grid.tile_def(coord)
	var placed := 0
	while core.grid.free_socket(coord, "decor") >= 0:
		core.grid.add_structure(coord, "struct_pot", core.grid.free_socket(coord, "decor"))
		placed += 1
	check(placed == def.decor_sockets, "decor sockets are finite (%d)" % def.decor_sockets)
	check(core.grid.free_socket(coord, "decor") == -1, "no infinite stacking on one cell")
	var major := core.grid.free_socket(coord, "structure")
	check(major == 0, "major socket distinct from decor sockets")
	core.grid.add_structure(coord, "struct_campfire", major)
	check(core.grid.free_socket(coord, "structure") == -1, "single major structure per cell")


func _test_anchor_cycle_and_regen() -> void:
	var core := fresh_core()
	core.stock.add_tile("tile_grove_mature")
	core.place_tile_from_stock(Vector2i(2, 0), "tile_grove_mature", 0)
	var state := core.grid.cell(Vector2i(2, 0))
	var anchor := core.registries.anchor("grove_anchor")
	state.anchor_actions_done = anchor.cycle_actions
	state.anchor_resting = true
	state.anchor_regen_left = 2.0
	core.tick(1.0)
	check(state.anchor_resting, "grove still resting mid-regen")
	core.tick(1.5)
	check(not state.anchor_resting and state.anchor_actions_done == 0, "grove regenerates and resets after its rest")


func _test_crafting_transactions() -> void:
	var core := fresh_core()
	check(not core.crafting.craft("recipe_bench"), "crafting without skill/materials fails")
	core.skills.add_xp("fishing", 1000)   # reach level for bench
	check(not core.crafting.craft("recipe_bench"), "crafting without materials fails")
	var inv_before := core.inventory.count("softwood")
	core.inventory.grant("softwood", 2, false, true)
	core.inventory.grant("reeds", 2, false, true)
	check(core.crafting.craft("recipe_bench"), "crafting with everything succeeds")
	check(core.inventory.count("softwood") == inv_before and core.inventory.count("reeds") == 0, "materials consumed atomically")
	check(core.stock.structure_count("struct_bench") == 1, "crafted structure lands in stock")
	core.inventory.grant("hardwood", 2, false, true)
	core.inventory.grant("old_metal", 2, false, true)
	core.inventory.grant("resin", 1, false, true)
	core.skills.add_xp("woodcutting", 2000)
	check(core.crafting.craft("recipe_axe_fine"), "tool recipe crafts")
	check(core.equipment.owns("tool_axe_fine"), "crafted tool is owned equipment")
	check(core.equipment.best_tool("axe").id == "tool_axe_fine", "best tool resolves to the higher tier")


func _test_equipment() -> void:
	var core := fresh_core()
	core.equipment.acquire("cape_watchpost")
	check(core.equipment.equip("cape_watchpost"), "owned equipment can be equipped")
	check(core.equipment.equipped_in("back").id == "cape_watchpost", "slot query returns equipped item")
	check(core.equipment.appearance_unlocked.has("cape_watchpost"), "appearance unlock recorded separately from ownership")
	check(core.combat.defense() >= 1, "equipment stats aggregate")
	check(not core.equipment.equip("weapon_thorn_sword"), "unowned equipment cannot be equipped")


func _make_revealed_landmark(core: GameCore) -> LandmarkManager.LandmarkState:
	# Grow east until the watchpost spawns, then bridge to it.
	for i in range(2, 12):
		core.stock.add_tile("tile_grass")
		core.place_tile_from_stock(Vector2i(i, 0), "tile_grass", 0)
		if not core.landmarks.active.is_empty():
			break
	if core.landmarks.active.is_empty():
		return null
	var state: LandmarkManager.LandmarkState = core.landmarks.active[0]
	var guard := 0
	while state.phase == LandmarkManager.PHASE_SILHOUETTE and guard < 24:
		guard += 1
		var target := core.landmarks.footprint_cells(state)[0]
		var frontier := _frontier_toward(core, target)
		if frontier == Vector2i(9999, 9999):
			break
		core.stock.add_tile("tile_grass")
		core.place_tile_from_stock(frontier, "tile_grass", 0)
	return state


func _frontier_toward(core: GameCore, target: Vector2i) -> Vector2i:
	var best := Vector2i(9999, 9999)
	var best_distance := 999999
	for coord: Vector2i in core.grid.cells:
		for offset: Vector2i in WorldGrid.NEIGHBORS:
			var candidate: Vector2i = coord + offset
			if core.grid.has_cell(candidate) or not core.grid.can_place_tile(candidate):
				continue
			var distance := absi(candidate.x - target.x) + absi(candidate.y - target.y)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best


func _test_landmark_lifecycle() -> void:
	var core := fresh_core()
	var state := _make_revealed_landmark(core)
	check(state != null, "a horizon opportunity spawns as the world grows")
	if state == null:
		return
	var def := core.registries.landmark(state.landmark_id)
	for cell in core.landmarks.footprint_cells(state):
		check(not core.grid.has_cell(cell) or state.phase != LandmarkManager.PHASE_SILHOUETTE, "silhouette never overlaps placed land")
	check(state.phase == LandmarkManager.PHASE_REVEALED, "connecting land reveals the landmark")
	check(core.grid.has_cell(core.landmarks.footprint_cells(state)[0]), "revealed footprint becomes real ground")
	check(state.enemies_alive.size() == 3, "enemy roster spawned from definition")


func _test_guardian_idempotency() -> void:
	var core := fresh_core()
	var state := _make_revealed_landmark(core)
	if state == null:
		failures.append("guardian test could not build landmark")
		return
	var def := core.registries.landmark(state.landmark_id)
	var grants_a := core.landmarks.on_enemy_defeated(state, def.guardian_id + ":g", true)
	check(core.equipment.owns(def.guardian_reward), "guardian reward granted")
	check(state.phase == LandmarkManager.PHASE_RECLAIMED, "guardian defeat reclaims the landmark")
	var grants_b := core.landmarks.on_enemy_defeated(state, def.guardian_id + ":g", true)
	check(grants_b.is_empty(), "guardian reward is idempotent — no double grant")


func _test_pack_and_salvage() -> void:
	var core := fresh_core()
	var state := _make_revealed_landmark(core)
	if state == null:
		failures.append("pack test could not build landmark")
		return
	var def := core.registries.landmark(state.landmark_id)
	core.landmarks.on_enemy_defeated(state, def.guardian_id + ":g", true)
	var cells := core.landmarks.footprint_cells(state)
	core.landmarks.resolve(state, "packed")
	check(core.stock.landmark_deeds.has(state.landmark_id), "packing yields a deed")
	check(not core.grid.has_cell(cells[0]), "packed landmark releases its cells")
	# salvage path on a fresh core
	var core2 := fresh_core(999)
	var state2 := _make_revealed_landmark(core2)
	if state2 != null:
		var def2 := core2.registries.landmark(state2.landmark_id)
		core2.landmarks.on_enemy_defeated(state2, def2.guardian_id + ":g", true)
		var before := core2.inventory.count("carved_stone")
		core2.landmarks.resolve(state2, "salvaged")
		check(core2.inventory.count("carved_stone") > before, "salvage grants materials")


func _test_deed_replacement() -> void:
	var core := fresh_core()
	var state := _make_revealed_landmark(core)
	if state == null:
		return
	var def := core.registries.landmark(state.landmark_id)
	core.landmarks.on_enemy_defeated(state, def.guardian_id + ":g", true)
	core.landmarks.resolve(state, "packed")
	var placed_ok := false
	for y in range(-8, 9):
		for x in range(-8, 9):
			if core.landmarks.place_deed(state.landmark_id, Vector2i(x, y)):
				placed_ok = true
				break
		if placed_ok:
			break
	check(placed_ok, "deed re-places beside the world")
	var placed := core.landmarks.state_for(state.landmark_id)
	check(placed != null and placed.phase == LandmarkManager.PHASE_RECLAIMED, "re-placed landmark is peaceful")


func _test_rework_save_round_trip() -> void:
	var core := fresh_core(31415)
	core.skills.add_xp("fishing", 55)
	core.stock.add_tile("tile_grove_birch")
	core.profile.position = Vector3(0.234, 0.0, 0.345)   # continuous, between tile centers
	core.profile.facing = 1.11
	core.view_state = {"yaw": 135.0, "distance": 55.0}
	core.visual_state = {
		"weather": "snow",
		"time_of_day": "night",
		"background": "dusk",
		"particle_quality": "medium",
	}
	core.arrivals.trigger_arrival()
	core.arrivals.mark_delivery_ready(core.arrivals.current_payload)
	var rng_next := core.rng.randi_range("probe", 0, 999999)
	check(core.save(), "save writes")
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	check(restored.load_game(), "save loads")
	check(restored.skills.xp["fishing"] == core.skills.xp["fishing"], "xp round-trips")
	check(restored.inventory.counts.is_empty(), "active material inventory stays empty")
	check(restored.stock.tile_count("tile_grove_birch") == 1, "stock round-trips")
	check(restored.grid.cells.size() == core.grid.cells.size(), "grid round-trips")
	check(restored.profile.position.is_equal_approx(Vector3(0.234, 0.0, 0.345)), "exact float player position round-trips")
	check(absf(restored.profile.facing - 1.11) < 0.0001, "facing round-trips")
	check(restored.view_state == core.view_state, "camera orbit and distance round-trip")
	check(restored.visual_state == core.visual_state, "weather, time, background, and particle quality round-trip")
	check(restored.arrivals.has_waiting_package(), "unopened ferry parcel survives restart")
	check(restored.arrivals.current_payload.parcel_id == "parcel_wild", "delivery payload survives restart")
	# RNG stream continues identically after reload (probe stream was consumed once pre-save)
	var loaded_next := restored.rng.randi_range("probe", 0, 999999)
	var fresh_again := GameCore.new()
	fresh_again.setup("res://data", 31415)
	fresh_again.rng.randi_range("probe", 0, 999999)
	check(loaded_next == fresh_again.rng.randi_range("probe", 0, 999999), "rng stream state round-trips")


func _test_missing_definition_load() -> void:
	var core := fresh_core()
	core.inventory.counts["item_that_no_longer_exists"] = 3
	core.equipment.owned["gear_that_no_longer_exists"] = true
	core.grid.cells[Vector2i(4, 4)] = WorldGrid.CellState.new()
	core.grid.cells[Vector2i(4, 4)].tile_id = "tile_that_no_longer_exists"
	check(core.save(), "save with stale ids writes")
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	check(restored.load_game(), "load survives missing definitions")
	check(restored.inventory.count("item_that_no_longer_exists") == 0, "unknown items dropped safely")
	check(not restored.grid.has_cell(Vector2i(4, 4)), "unknown tiles dropped safely")
	check(restored.grid.cells.size() >= 9, "known world intact after fallback load")


func _test_interrupted_reveal_recovery() -> void:
	var core := fresh_core()
	core.inventory.grant("parcel_wild", 1, false, true)
	core.parcels.open("parcel_wild")
	check(core.parcels.has_pending(), "reveal pending")
	core.save()   # player closes the game mid-reveal
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	restored.load_game()
	check(restored.parcels.has_pending(), "pending reveal survives restart")
	check(restored.parcels.pending_options.size() == 3, "all three options intact")
	var chosen := restored.parcels.choose(1)
	check(chosen != "" and restored.stock.tile_count(chosen) == 1, "resumed reveal completes; nothing lost or duplicated")


func _test_player_defeat_safety() -> void:
	var core := fresh_core()
	core.inventory.grant("softwood", 3, false, true)
	var defeated := [false]   # lambdas capture locals by value; use a container
	core.combat.player_defeated.connect(func(): defeated[0] = true)
	var guard := 0
	while not defeated[0] and guard < 10:
		guard += 1
		core.combat.damage_player(2)
	check(defeated[0], "defeat fires")
	check(core.combat.health == core.combat.max_health, "defeat restores full health (no corpse run)")
	check(core.inventory.count("softwood") == 3, "nothing is lost on defeat")
