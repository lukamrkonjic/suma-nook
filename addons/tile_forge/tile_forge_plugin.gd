@tool
extends EditorPlugin
## Editor entry points for the Tile Forge.
##
## Godot requires a plugin to live under res://addons/, so this thin shim is
## the only Tile Forge file outside tools/tile_forge/. It owns no logic: every
## action calls the same TileBaker / TileValidator / TileGeneratorRegistry code
## the headless scripts use, so an editor bake and a CI bake cannot diverge.

const LAB_SCENE := "res://tools/tile_forge/editor/tile_lab.tscn"
const RECIPE_DIR := "res://tools/tile_forge/recipes/proof_set"
const PALETTE_PATH := "res://assets/palettes/gg_material_palette.tres"

var _items: PackedStringArray = [
	"Tile Forge: Open Tile Lab",
	"Tile Forge: Bake All Proof Recipes",
	"Tile Forge: Validate All Recipes",
	"Tile Forge: List Generators",
]


func _enter_tree() -> void:
	add_tool_menu_item(_items[0], _open_lab)
	add_tool_menu_item(_items[1], _bake_all)
	add_tool_menu_item(_items[2], _validate_all)
	add_tool_menu_item(_items[3], _list_generators)


func _exit_tree() -> void:
	for item in _items:
		remove_tool_menu_item(item)


func _open_lab() -> void:
	get_editor_interface().open_scene_from_path(LAB_SCENE)


func _bake_all() -> void:
	var cozy: CozyPalette = load(PALETTE_PATH)
	var materials := MaterialLibrary.new(cozy)
	var shared: Dictionary = {}
	var failures := 0
	for recipe in _recipes():
		var manifest := TileBaker.bake(
			recipe, TileForgeConstants.BAKED_DIR, materials, cozy, shared
		)
		print(manifest.summary_line())
		for error in manifest.errors:
			push_error("%s: %s" % [manifest.tile_id, error])
		if not manifest.passed:
			failures += 1
	print("Tile Forge: baked with %d failures" % failures)
	get_editor_interface().get_resource_filesystem().scan()


func _validate_all() -> void:
	for recipe in _recipes():
		var result := TileForgeBuilder.build(recipe)
		var report := TileValidator.validate(result)
		print("=== %s ===" % recipe.tile_id)
		print(report.text())


func _list_generators() -> void:
	var registry := TileGeneratorRegistry.refresh()
	for entry in registry.report():
		print("%-22s %-28s %s" % [
			entry["id"], ", ".join(entry["kinds"]), entry["description"]
		])
	for error in registry.load_errors():
		push_warning(error)


func _recipes() -> Array[TileRecipe]:
	var result: Array[TileRecipe] = []
	var dir := DirAccess.open(RECIPE_DIR)
	if dir == null:
		return result
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var loaded: Variant = load(RECIPE_DIR.path_join(clean))
		if loaded is TileRecipe:
			result.append(loaded)
	return result
