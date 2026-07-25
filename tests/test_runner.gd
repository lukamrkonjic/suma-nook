extends Node

const GameDataScript := preload("res://scripts/game_data.gd")
const GridScript := preload("res://scripts/grid_manager.gd")
const EconomyScript := preload("res://scripts/economy_manager.gd")
const StorageScript := preload("res://scripts/storage_manager.gd")
const CollectionScript := preload("res://scripts/collection_manager.gd")
const RewardScript := preload("res://scripts/reward_manager.gd")
const SaveScript := preload("res://scripts/save_manager.gd")

const TEST_SAVE := "user://tilegarden-test-save.json"

var failures: Array[String] = []
var assertions := 0
var data: GameData


func _ready() -> void:
	data = GameDataScript.new()
	check(data.load_all(), "all data files load")
	_test_placement_overlap()
	_test_ground_adjacency()
	_test_rotation_footprint()
	_test_token_transactions()
	_test_weighted_reward()
	_test_reward_modifiers()
	_test_recycling()
	_test_collection_discovery()
	_test_save_round_trip()
	_test_missing_definition()
	_test_reachable_destination()
	_test_initial_content_contract()
	if failures.is_empty():
		print("TILEGARDEN VALIDATION PASSED — %d assertions across 12 suites" % assertions)
		_quit_clean(0)
	else:
		for failure: String in failures:
			push_error("TEST FAILURE: %s" % failure)
		print("TILEGARDEN VALIDATION FAILED — %d failures / %d assertions" % [failures.size(), assertions])
		_quit_clean(1)


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func fresh_grid(radius := 2) -> GridManager:
	var result := GridScript.new() as GridManager
	result.setup(data)
	result.make_initial_island(radius)
	return result


func _test_placement_overlap() -> void:
	var target := fresh_grid()
	var id := target.place_prop(&"moss_rock", Vector3i(1, 1, 1), 0)
	check(not id.is_empty(), "first prop placement succeeds")
	var overlap := target.can_place_prop(data.item(&"seed_crate"), Vector3i(1, 1, 1), 0)
	check(not bool(overlap.valid), "overlapping prop placement is rejected")
	var adjacent := target.can_place_prop(data.item(&"seed_crate"), Vector3i(1, 1, 0), 0)
	check(bool(adjacent.valid), "adjacent prop placement remains valid")
	target.free()


func _test_ground_adjacency() -> void:
	var target := fresh_grid()
	check(bool(target.can_place_ground(Vector3i(3, 0, 0)).valid), "ground beside island is valid")
	check(not bool(target.can_place_ground(Vector3i(8, 0, 8)).valid), "detached ground is invalid")
	check(target.place_ground(&"ground_loam", Vector3i(3, 0, 0)), "valid ground can be placed")
	target.free()


func _test_rotation_footprint() -> void:
	var bench := data.item(&"root_bench")
	check(bench.rotated_footprint(0) == Vector2i(2, 1), "unrotated footprint is 2x1")
	check(bench.rotated_footprint(1) == Vector2i(1, 2), "quarter-turn footprint is 1x2")
	var target := fresh_grid()
	var horizontal := target.footprint_cells(bench, Vector3i(0, 1, 0), 0)
	var vertical := target.footprint_cells(bench, Vector3i(0, 1, 0), 1)
	check(horizontal != vertical and horizontal.size() == vertical.size(), "rotation changes occupied cells without changing area")
	target.free()


func _test_token_transactions() -> void:
	var manager := EconomyScript.new() as EconomyManager
	manager.setup(data)
	check(manager.add(&"meadow_coin", 3), "valid coins can be added")
	check(manager.spend(&"meadow_coin", 2), "available coins can be spent")
	check(manager.amount(&"meadow_coin") == 1, "coin balance is correct")
	check(not manager.spend(&"meadow_coin", 2), "overspending is rejected")
	manager.free()


func _test_weighted_reward() -> void:
	var manager := RewardScript.new() as RewardManager
	manager.setup(data, 99)
	manager.offers_made = 10
	manager.offers_by_pool["meadow"] = 10
	for _i: int in 30:
		var id := manager.draw(&"meadow_coin")
		check(data.item(id) != null, "weighted reward returns a valid definition")
		check("meadow" in data.item(id).reward_pools, "weighted reward stays in the coin's themed set")
	manager.free()


func _test_reward_modifiers() -> void:
	var manager := RewardScript.new() as RewardManager
	manager.setup(data, 772)
	manager.offers_by_pool["hearth"] = 10
	var context := {"placed_definition_counts": {"still_bell": 1}}
	for _i: int in 24:
		var id := manager.draw(&"hearth_coin", context)
		check(data.item(id).category != &"furniture", "a placed Hushbell suppresses furniture rewards")
	var summary := manager.modifier_summary({
		"placed_definition_counts": {"wish_lantern": 1, "still_bell": 1},
	})
	check(summary.size() == 2, "placed functional pieces expose both live odds effects")
	manager.free()


func _test_recycling() -> void:
	var manager := EconomyScript.new() as EconomyManager
	manager.setup(data)
	check(manager.sell(2) == 0, "a partial sale does not create a coin")
	check(manager.sell(2) == 1, "configured sale threshold creates one coin")
	check(manager.amount(&"meadow_coin") == 1 and manager.recycle_progress == 0, "sale balance and remainder are correct")
	manager.free()


func _test_collection_discovery() -> void:
	var manager := CollectionScript.new() as CollectionManager
	manager.setup(data)
	check(manager.record_obtained(&"sapling"), "first collection record reports discovery")
	check(not manager.record_obtained(&"sapling"), "duplicate record is not a first discovery")
	check(manager.total(&"sapling") == 2, "collection total counts duplicates")
	check(manager.new_markers.has(&"sapling"), "new discovery marker is retained")
	manager.free()


func _test_save_round_trip() -> void:
	SaveScript.delete_paths(TEST_SAVE)
	var target := fresh_grid()
	target.place_ground(&"ground_stone", Vector3i(3, 0, 0))
	target.place_prop(&"moss_rock", Vector3i(2, 1, 1), 1)
	var manager := SaveScript.new() as TilegardenSaveManager
	manager.setup(1, TEST_SAVE)
	var payload := {
		"world_seed": 77,
		"grid": target.snapshot(),
		"economy": {"tokens": {"meadow_coin": 4}, "recycle_progress": 2},
		"storage": {"moonflowers": 3},
	}
	check(manager.write_save(payload), "atomic test save succeeds")
	var loaded := manager.read_save()
	check(int(loaded.world_seed) == 77, "world seed survives save/load")
	check((loaded.grid.ground as Array).size() == target.ground.size(), "ground survives save/load")
	check(int(loaded.economy.tokens.meadow_coin) == 4, "coin count survives save/load")
	check(int(loaded.storage.moonflowers) == 3, "storage count survives save/load")
	SaveScript.delete_paths(TEST_SAVE)
	manager.free()
	target.free()


func _test_missing_definition() -> void:
	var target := fresh_grid()
	var state := target.snapshot()
	state.props.append({
		"instance_id": "missing-1",
		"definition_id": "retired_item",
		"coord": [1, 1, 1],
		"rotation": 0,
	})
	var missing: Array[String] = []
	target.restore_snapshot(state, missing)
	check("retired_item" in missing, "missing definitions are reported")
	check(not target.props.has("missing-1"), "missing definitions are skipped safely")
	target.free()


func _test_reachable_destination() -> void:
	var target := fresh_grid()
	target.place_prop(&"seed_crate", Vector3i(1, 1, 1), 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var start := Vector3i(-2, 1, -2)
	var destination := target.random_reachable_destination(start, rng)
	var path := target.reachable_path(start, destination)
	check(target.is_walkable(destination), "visitor destination is walkable")
	check(not path.is_empty() and path[0] == start and path.back() == destination, "visitor destination has a complete reachable path")
	target.free()


func _test_initial_content_contract() -> void:
	check(data.tokens.size() == 3, "MVP contains three themed coin categories")
	check(data.ground_ids().size() == 4, "MVP contains four visually distinct ground definitions")
	check(data.items.size() >= 18 and data.items.size() <= 24, "MVP content stays within vertical-slice scale")
	for pool: String in ["meadow", "hearth", "tide"]:
		var sequence: Array = (data.beginner.sequence_by_pool as Dictionary)[pool]
		var first := StringName(str(sequence[0]))
		var third := StringName(str(sequence[2]))
		check(data.item(first).is_ground() and data.item(third).is_ground(),
			"%s beginner rewards guarantee early expansion" % pool)
	check(data.item(&"wish_lantern").modifier_kind == &"boost", "the boost curio is data-driven")
	check(data.item(&"still_bell").modifier_kind == &"block", "the suppressor curio is data-driven")


func _quit_clean(code: int) -> void:
	data = null
	var tree := get_tree()
	tree.create_timer(0.10).timeout.connect(tree.quit.bind(code))
	queue_free()
