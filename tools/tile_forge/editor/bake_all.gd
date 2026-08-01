extends SceneTree
## Headless bake of every proof recipe. Run:
##
##   Godot --headless --path . --script tools/tile_forge/editor/bake_all.gd
##
## Optional user args:
##   --variants=8        also bake a curated variant set for each recipe
##   --recipes=a,b       restrict to specific tile ids
##   --report=<path>     write the combined validation report here
##
## Exits non-zero when any recipe fails validation, so this is usable as a
## content gate rather than only as a convenience.

const RECIPE_DIR := "res://tools/tile_forge/recipes/golden"
const PALETTE_PATH := "res://assets/palettes/gg_material_palette.tres"
const DEFAULT_REPORT := "res://tools/tile_forge/baked/BAKE_REPORT.md"


func _init() -> void:
	var variants := 0
	var only := PackedStringArray()
	var report_path := DEFAULT_REPORT
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--variants="):
			variants = int(argument.trim_prefix("--variants="))
		elif argument.begins_with("--recipes="):
			only = argument.trim_prefix("--recipes=").split(",", false)
		elif argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")

	var cozy: CozyPalette = load(PALETTE_PATH)
	var materials := MaterialLibrary.new(cozy)
	var shared_modules: Dictionary = {}

	var registry := TileGeneratorRegistry.refresh()
	print("generators: %s" % ", ".join(registry.ids()))
	for error in registry.load_errors():
		printerr("registry: %s" % error)

	var manifests: Array[TileBakeManifest] = []
	var failures := 0
	for recipe in _recipes(only):
		var manifest := TileBaker.bake(
			recipe, TileForgeConstants.BAKED_DIR, materials, cozy, shared_modules
		)
		manifests.append(manifest)
		print(manifest.summary_line())
		for error in manifest.errors:
			printerr("  ERROR   %s" % error)
		for warning in manifest.warnings:
			print("  warning %s" % warning)
		if not manifest.passed:
			failures += 1
		if variants > 0 and manifest.passed:
			var accepted := 0
			for variant_manifest in TileBaker.bake_variant_set(
				recipe, variants, TileForgeConstants.BAKED_DIR, materials, cozy
			):
				if variant_manifest.passed:
					accepted += 1
			print("  variants: %d/%d accepted" % [accepted, variants])

	_write_report(report_path, manifests, registry)
	print("TILE FORGE BAKE: %d recipes, %d failed" % [manifests.size(), failures])
	quit(1 if failures > 0 else 0)


func _recipes(only: PackedStringArray) -> Array[TileRecipe]:
	var result: Array[TileRecipe] = []
	var dir := DirAccess.open(RECIPE_DIR)
	if dir == null:
		printerr("no recipe directory at %s" % RECIPE_DIR)
		return result
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var loaded: Variant = load(RECIPE_DIR.path_join(clean))
		if not (loaded is TileRecipe):
			continue
		var recipe := loaded as TileRecipe
		if only.size() > 0 and not only.has(recipe.tile_id):
			continue
		result.append(recipe)
	return result


func _write_report(
	path: String,
	manifests: Array[TileBakeManifest],
	registry: TileGeneratorRegistry
) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("could not write %s" % path)
		return
	file.store_line("# Tile Forge bake report")
	file.store_line("")
	file.store_line("Generated %s by Tile Forge %s." % [
		Time.get_datetime_string_from_system(true),
		TileForgeBuilder.FORGE_VERSION,
	])
	file.store_line("")
	file.store_line("## Registered generators")
	file.store_line("")
	file.store_line("| id | kinds | purpose |")
	file.store_line("|---|---|---|")
	for entry in registry.report():
		file.store_line("| `%s` | %s | %s |" % [
			entry["id"], ", ".join(entry["kinds"]), entry["description"]
		])
	file.store_line("")
	file.store_line("## Baked tiles")
	file.store_line("")
	file.store_line(
		"| tile | tris | surface | detail | mats | nodes | modules | walk y | exposed top | result |"
	)
	file.store_line("|---|---:|---:|---:|---:|---:|---:|---:|---|---|")
	for manifest in manifests:
		file.store_line("| `%s` | %d | %d | %d | %d | %d | %d | %.3f | %s | %s |" % [
			manifest.tile_id,
			manifest.triangle_count,
			manifest.surface_triangle_count,
			manifest.detail_triangle_count,
			manifest.material_count,
			manifest.node_count,
			manifest.module_instance_count,
			manifest.measured_walk_height,
			manifest.exposed_top,
			"PASS" if manifest.passed else "**FAIL**",
		])
	file.store_line("")
	for manifest in manifests:
		if manifest.errors.is_empty() and manifest.warnings.is_empty():
			continue
		file.store_line("### %s" % manifest.tile_id)
		file.store_line("")
		for error in manifest.errors:
			file.store_line("- **error** %s" % error)
		for warning in manifest.warnings:
			file.store_line("- warning %s" % warning)
		file.store_line("")
	file.store_line("## data/tiles.json fragments")
	file.store_line("")
	for manifest in manifests:
		if not manifest.passed:
			continue
		file.store_line("```json")
		file.store_line(manifest.tiles_json_fragment())
		file.store_line("```")
		file.store_line("")
	file.close()
