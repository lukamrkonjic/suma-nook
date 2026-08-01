extends SceneTree
## Deterministic large-run fishing balance simulation. Run:
##   Godot --headless --path . --script tools/fishing_simulation.gd
##   Godot --headless --path . --script tools/fishing_simulation.gd -- seed=7 catches=250000 spirit=grove
##
## Performs at least 100,000 virtual catches through the SAME reward services
## as live gameplay (no animations, no approximation) and prints the
## distribution report used for tuning fishing_balance.json.

const DEFAULT_SEED := 133742
const DEFAULT_CATCHES := 100000


func _init() -> void:
	var seed_value := DEFAULT_SEED
	var catches := DEFAULT_CATCHES
	var spirit_theme := ""
	for argument in OS.get_cmdline_user_args():
		var parts := String(argument).split("=", false, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"seed": seed_value = int(parts[1])
			"catches": catches = maxi(1, int(parts[1]))
			"spirit": spirit_theme = parts[1]
	var core := GameCore.new()
	if not core.setup("res://data", seed_value):
		printerr("SIMULATION FAILED: content did not load")
		quit(1)
		return
	var profile := PlayerProfile.new()
	profile.display_name = "Simkeeper"
	core.save_manager.save_path = "user://fishing_simulation_scratch.json"
	core.save_manager.backup_path = "user://fishing_simulation_scratch.json.backup"
	core.new_game(profile)
	var started := Time.get_ticks_msec()
	var report: Dictionary = core.fishing.run_simulation(
		seed_value, catches, Vector2i.ZERO, spirit_theme
	)
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	print("FISHING SIMULATION — %d catches, seed %d, spirit '%s' (%.1fs)" % [
		catches, seed_value, spirit_theme, elapsed,
	])
	print("  habitat:            %s" % str(report["habitat"]))
	print("  sizes:              %s" % str(report["sizes"]))
	print("  forms:              %s" % str(report["forms"]))
	print("  rarities:           %s" % str(report["rarities"]))
	print("  themes:             %s" % str(report["themes"]))
	print("  keepsakes:          %d (%.4f/catch)" % [
		int(report["keepsakes"]), float(report["keepsakes"]) / catches,
	])
	print("  tiles granted:      %d (%.2f/catch)" % [
		int(report["tiles_granted"]), float(report["tiles_granted"]) / catches,
	])
	print("  empty-pool fallbacks: %d" % int(report["empty_pool_fallbacks"]))
	print("  safe fallbacks:       %d" % int(report["safe_fallback_uses"]))
	print("  invalid definitions:  %d" % int(report["invalid_definitions"]))
	var per_loot: Dictionary = report["loot"]
	var loot_ids := per_loot.keys()
	loot_ids.sort_custom(func(a, b): return int(per_loot[a]) > int(per_loot[b]))
	print("  loot (descending):")
	for loot_id in loot_ids:
		print("    %-32s %d" % [String(loot_id), int(per_loot[loot_id])])
	if int(report["invalid_definitions"]) > 0:
		printerr("SIMULATION FAILED: invalid loot definitions present")
		quit(1)
		return
	print("SIMULATION OK")
	quit(0)
