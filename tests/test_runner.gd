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
	_test_registries()
	_test_starting_world()


func _test_registries() -> void:
	var regs := Registries.new()
	check(regs.load_all(), "all data files load and cross-validate: " + ", ".join(regs.load_errors))
	check(regs.skills.size() == 3, "three skills defined")
	check(regs.tiles.size() >= 15, "at least 15 tile variants")
	check(regs.skill("mining").future, "mining is a future skill")
	var fishing := regs.skill("fishing")
	check(fishing.xp_to_next(1) > 0 and fishing.xp_to_next(2) > fishing.xp_to_next(1), "xp curve increases")


func _test_starting_world() -> void:
	var core := fresh_core()
	check(core.grid.cells.size() == 9, "fresh save starts with exactly nine cells")
	var families := {}
	for coord: Vector2i in core.grid.cells:
		families[core.grid.tile_def(coord).id] = true
	check(families.size() >= 3, "starting world uses coordinated variants, not nine identical tiles")
	var has_pond := false
	for coord: Vector2i in core.grid.cells:
		if core.grid.tile_def(coord).anchor_id == "pond_anchor":
			has_pond = true
	check(has_pond, "starting world contains a fishable pond")
	check(core.grid.is_walkable(Vector2i.ZERO), "home cell walkable")
	check(core.equipment.owns("tool_rod_basic"), "starter rod owned")
