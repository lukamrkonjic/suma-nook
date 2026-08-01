extends SceneTree
## One-time deterministic migration from hardcoded presets/JSON entries to the
## file-backed Tile Library. Safe to re-run while developing schema changes.

const RECIPES := {
	"tile_kit_grass": ["Reference Clean Grass", "reference_clean_grass"],
	"tile_proc_flower_meadow": ["Flower Meadow", "flower_meadow"],
	"tile_proc_garden_path": ["Garden Path", "garden_path"],
	"tile_proc_fenced_meadow": ["Fenced Meadow", "fenced_meadow"],
	"tile_proc_pond_basin": ["Pond Basin", "pond_basin"],
	"tile_proc_tilled_field": ["Tilled Field", "tilled_field"],
	"tile_proc_boulder_ground": ["Boulder Ground", "boulder_ground"],
	"tile_proc_mossy_forest_floor": ["Mossy Forest Floor", "mossy_forest_floor"],
	"tile_proc_autumn_litter": ["Autumn Litter", "autumn_litter"],
	"tile_proc_mulch_dirt_floor": ["Mulch Dirt Floor", "mulch_dirt_floor"],
	"tile_proc_snow_field": ["Snow Field", "snow_field"],
	"tile_proc_snow_drifts_study": ["Snow Drifts (Study)", "snow_drift_study"],
	"tile_proc_sandy_ground": ["Sandy Ground", "sandy_ground"],
	"tile_proc_sand_dunes_study": ["Sand Dunes (Study)", "sand_dune_study"],
	"tile_proc_mud_bed": ["Mud Bed", "mud_bed"],
	"tile_proc_gravel_yard": ["Gravel Yard", "gravel_yard"],
	"tile_proc_cobblestone_paving": ["Cobblestone Paving", "cobblestone_paving"],
	"tile_proc_wood_plank_deck": ["Wood Plank Deck", "wood_plank_deck"],
	"tile_proc_concrete_slabs": ["Concrete Slabs", "concrete_slabs"],
	"tile_proc_brick_court": ["Brick Court", "brick_court"],
	"tile_proc_checker_slabs": ["Checker Slabs", "checker_slabs"],
}


func _init() -> void:
	for directory in [
		TileLibraryService.OFFICIAL_RECIPE_DIRECTORY,
		TileLibraryService.OFFICIAL_MANIFEST_DIRECTORY,
	]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var recipes: Dictionary = {}
	for tile_id: String in RECIPES:
		var factory_name := String((RECIPES[tile_id] as Array)[1])
		var recipe := _make_recipe(factory_name)
		var path := "%s/%s.tres" % [
			TileLibraryService.OFFICIAL_RECIPE_DIRECTORY, tile_id
		]
		var error := ResourceSaver.save(recipe, path)
		if error != OK:
			printerr("Recipe migration failed %s: %s" % [tile_id, error_string(error)])
			quit(1)
			return
		recipes[tile_id] = path

	var catalog := _read_json("res://data/tiles.json")
	var tuning := _read_json("res://data/tuning.json")
	if catalog.is_empty() or tuning.is_empty():
		quit(1)
		return
	var active: Array = tuning.get("active_tile_ids", [])
	var preview: Array = tuning.get("preview_tile_ids", [])
	var existing_ids: Dictionary = {}
	for raw: Variant in catalog.get("tiles", []):
		if not (raw is Dictionary):
			continue
		var definition := raw as Dictionary
		var tile_id := String(definition.get("id", ""))
		if tile_id.is_empty():
			continue
		existing_ids[tile_id] = true
		var manifest := _manifest_from_runtime(definition, active, preview)
		if recipes.has(tile_id):
			manifest.source_kind = TileLibraryManifest.SOURCE_PROCEDURAL
			manifest.recipe_path = String(recipes[tile_id])
			manifest.runtime_definition = {}
			var recipe := ResourceLoader.load(
				manifest.recipe_path, "", ResourceLoader.CACHE_MODE_IGNORE
			) as TileKitPreset
			manifest.separate_tiles = recipe != null and recipe.separate_tiles
		var path := "%s/%s.tres" % [
			TileLibraryService.OFFICIAL_MANIFEST_DIRECTORY, tile_id
		]
		if ResourceSaver.save(manifest, path) != OK:
			printerr("Manifest migration failed: %s" % tile_id)
			quit(1)
			return

	# Tile Kit recipes that are not runtime content yet enter as project drafts.
	# They are editable and publishable, but do not alter a game roster merely by
	# existing in source control.
	for tile_id: String in RECIPES:
		if existing_ids.has(tile_id):
			continue
		var recipe := ResourceLoader.load(
			String(recipes[tile_id]), "", ResourceLoader.CACHE_MODE_IGNORE
		) as TileKitPreset
		var manifest := TileLibraryManifest.new()
		manifest.tile_id = tile_id
		manifest.display_name = String((RECIPES[tile_id] as Array)[0])
		manifest.source_kind = TileLibraryManifest.SOURCE_PROCEDURAL
		manifest.recipe_path = String(recipes[tile_id])
		manifest.separate_tiles = recipe != null and recipe.separate_tiles
		manifest.lifecycle = TileLibraryManifest.LIFECYCLE_DRAFT
		manifest.visibility = TileLibraryManifest.VISIBILITY_HIDDEN
		manifest.family = _family_for(tile_id)
		manifest.connection_group = tile_id
		manifest.biome_tags = _biome_tags_for(tile_id)
		manifest.placement_sound = _placement_sound_for(tile_id)
		manifest.created_at = "2026-08-01 00:00:00"
		manifest.updated_at = manifest.created_at
		var path := "%s/%s.tres" % [
			TileLibraryService.OFFICIAL_MANIFEST_DIRECTORY, tile_id
		]
		if ResourceSaver.save(manifest, path) != OK:
			printerr("Draft manifest migration failed: %s" % tile_id)
			quit(1)
			return
	print("TILE LIBRARY BOOTSTRAPPED — %d recipes" % RECIPES.size())
	quit(0)


func _manifest_from_runtime(
	definition: Dictionary,
	active: Array,
	preview: Array
) -> TileLibraryManifest:
	var manifest := TileLibraryManifest.new()
	manifest.tile_id = String(definition.get("id", ""))
	manifest.display_name = String(definition.get("name", manifest.tile_id.capitalize()))
	manifest.lifecycle = TileLibraryManifest.LIFECYCLE_PUBLISHED
	manifest.visibility = (
		TileLibraryManifest.VISIBILITY_ACTIVE
		if active.has(manifest.tile_id)
		else (
			TileLibraryManifest.VISIBILITY_PREVIEW
			if preview.has(manifest.tile_id)
			else TileLibraryManifest.VISIBILITY_HIDDEN
		)
	)
	manifest.source_kind = TileLibraryManifest.SOURCE_EXTERNAL
	manifest.runtime_definition = definition.duplicate(true)
	manifest.family = String(definition.get("family", "legacy"))
	manifest.connection_group = String(
		definition.get("connection_group", manifest.family)
	)
	manifest.biome_tags = PackedStringArray(definition.get("biome_tags", []))
	manifest.rarity = String(definition.get("rarity", "common"))
	manifest.weight = float(definition.get("weight", 1.0))
	manifest.obtainable = bool(definition.get("obtainable", true))
	manifest.placement_sound = String(definition.get("placement_sound", "grass"))
	manifest.collection_hint = String(definition.get("collection_hint", ""))
	manifest.stackable = bool(definition.get("stackable", false))
	manifest.supports_tiles = bool(definition.get("supports_tiles", false))
	manifest.supports_decor = bool(definition.get("supports_decor", true))
	manifest.walkable = bool(definition.get("walkable", true))
	manifest.surface_kind = String(definition.get("surface_kind", "flat"))
	manifest.collision_profile = String(definition.get("collision_profile", "flat"))
	manifest.soft_surface_profile = String(definition.get("soft_surface_profile", ""))
	manifest.walk_surface_height = float(definition.get("walk_surface_height", 0.0))
	manifest.revision = 1
	manifest.created_at = "2026-08-01 00:00:00"
	manifest.updated_at = manifest.created_at
	manifest.published_at = manifest.created_at
	return manifest


func _read_json(path: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK \
			or not (parser.data is Dictionary):
		printerr("Invalid JSON: %s" % path)
		return {}
	return parser.data as Dictionary


func _make_recipe(factory_name: String) -> TileKitPreset:
	match factory_name:
		"flower_meadow": return TileKitPreset.flower_meadow()
		"garden_path": return TileKitPreset.garden_path()
		"fenced_meadow": return TileKitPreset.fenced_meadow()
		"pond_basin": return TileKitPreset.pond_basin()
		"tilled_field": return TileKitPreset.tilled_field()
		"boulder_ground": return TileKitPreset.boulder_ground()
		"mossy_forest_floor": return TileKitPreset.mossy_forest_floor()
		"autumn_litter": return TileKitPreset.autumn_litter()
		"mulch_dirt_floor": return TileKitPreset.mulch_dirt_floor()
		"snow_field": return TileKitPreset.snow_field()
		"snow_drift_study": return TileKitPreset.snow_drift_study()
		"sandy_ground": return TileKitPreset.sandy_ground()
		"sand_dune_study": return TileKitPreset.sand_dune_study()
		"mud_bed": return TileKitPreset.mud_bed()
		"gravel_yard": return TileKitPreset.gravel_yard()
		"cobblestone_paving": return TileKitPreset.cobblestone_paving()
		"wood_plank_deck": return TileKitPreset.wood_plank_deck()
		"concrete_slabs": return TileKitPreset.concrete_slabs()
		"brick_court": return TileKitPreset.brick_court()
		"checker_slabs": return TileKitPreset.checker_slabs()
	return TileKitPreset.reference_clean_grass()


func _family_for(tile_id: String) -> String:
	if "snow" in tile_id:
		return "winter"
	if "sand" in tile_id:
		return "beach"
	if tile_id in ["tile_proc_cobblestone_paving", "tile_proc_concrete_slabs",
			"tile_proc_brick_court", "tile_proc_checker_slabs"]:
		return "stonebound"
	if "wood" in tile_id:
		return "woodland"
	return "home_meadow"


func _biome_tags_for(tile_id: String) -> PackedStringArray:
	if "snow" in tile_id:
		return PackedStringArray(["winter"])
	if "sand" in tile_id:
		return PackedStringArray(["beach"])
	return PackedStringArray(["meadow"])


func _placement_sound_for(tile_id: String) -> String:
	if tile_id in ["tile_proc_cobblestone_paving", "tile_proc_concrete_slabs",
			"tile_proc_brick_court", "tile_proc_checker_slabs"]:
		return "stone"
	if "wood" in tile_id:
		return "wood"
	return "grass"
