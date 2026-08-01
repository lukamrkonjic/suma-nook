extends SceneTree
## Headless stable-ID bake using the same service as the Tile Library UI.
##
##   godot --headless --path . --script tools/tile_kit/bake_cli.gd -- \
##     --tile-id=tile_kit_grass
##   godot --headless --path . --script tools/tile_kit/bake_cli.gd -- \
##     --tile-id=tile_proc_sandy_ground \
##     --recipe=res://tools/tile_kit/library/recipes/tile_proc_sandy_ground.tres


func _init() -> void:
	var options := _options()
	var tile_id := String(options.get("tile-id", "tile_kit_grass"))
	var recipe_path := String(options.get("recipe", ""))
	if recipe_path.is_empty():
		var service := TileLibraryService.new()
		service.reload()
		var manifest := service.official_manifest(tile_id)
		if manifest != null:
			recipe_path = manifest.recipe_path
	var preset := ResourceLoader.load(
		recipe_path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as TileKitPreset
	if preset == null:
		push_error("No procedural recipe found for '%s': %s" % [tile_id, recipe_path])
		quit(1)
		return
	var result := TileKitBaker.new().bake(preset, tile_id)
	for path in result.get("written", PackedStringArray()):
		print("wrote %s" % path)
	if not bool(result.get("ok", false)):
		for error in result.get("errors", PackedStringArray()):
			push_error(String(error))
	print("BAKE %s · %s" % [
		"COMPLETE" if bool(result.get("ok", false)) else "FAILED",
		JSON.stringify(result.get("statistics", {})),
	])
	quit(0 if bool(result.get("ok", false)) else 1)


func _options() -> Dictionary:
	var result := {}
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if not text.begins_with("--") or "=" not in text:
			continue
		var split := text.trim_prefix("--").split("=", true, 1)
		result[split[0]] = split[1]
	return result
