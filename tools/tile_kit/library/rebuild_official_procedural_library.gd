extends SceneTree
## Development-only content migration that replaces every imported ground tile
## with an original, editable Tile Kit recipe.
##
## Stable IDs intentionally survive: worlds and authored rewards refer to IDs,
## while names and geometry are allowed to evolve. No extracted mesh, texture,
## or material is copied; the configurations below use only Tile Kit's generic
## builders and Suma palette.

const STAMP := "2026-08-01 16:00:00"
const CatalogTaxonomy := preload("res://tools/tile_kit/library/tile_catalog_taxonomy.gd")

## Human-facing names, scenery groups, and order live in
## TileCatalogTaxonomy. This rebuild owns geometry and applies that taxonomy;
## it never carries a second rename table that can drift from the editor.

## Only these entries were still sourced from imported geometry. Existing
## recipes are renamed below but retain their approved geometry.
const CONVERTED_IDS := [
	"tile_clay", "tile_cobblestone", "tile_concrete_brutalist",
	"tile_courtyard", "tile_dirt", "tile_dirt_crossroad", "tile_dirt_road",
	"tile_flagstone", "tile_frosted_stone", "tile_garden", "tile_grass",
	"tile_grass_flower", "tile_grass_pond_edge", "tile_grove_autumn",
	"tile_grove_birch", "tile_grove_flowering", "tile_grove_mature",
	"tile_grove_mossy", "tile_master_grass", "tile_master_pavers",
	"tile_master_wood", "tile_mud", "tile_open_water", "tile_path",
	"tile_plain_ground", "tile_sand", "tile_snow_drift", "tile_snow_path",
	"tile_snowfield", "tile_stone_clearing", "tile_stone_crystal",
	"tile_stone_mossy", "tile_stone_road", "tile_stone_ruin",
	"tile_wooden_planks",
]

const GREEN_BASE := {
	"top_key": "tile_top", "bevel_key": "tile_top_bevel",
	"side_key": "tile_side", "lower_key": "tile_lower",
}
const EARTH_BASE := {
	"top_key": "earth_top", "bevel_key": "earth_bevel",
	"side_key": "earth_side", "lower_key": "earth_deep",
}
const STONE_BASE := {
	"top_key": "stone_medium", "bevel_key": "stone_light",
	"side_key": "stone_deep", "lower_key": "stone_deep",
}
const SNOW_BASE := {
	"top_key": "snow_top", "bevel_key": "snow_bevel",
	"side_key": "snow_side", "lower_key": "stone_deep",
}
const SAND_BASE := {
	"top_key": "sand_top", "bevel_key": "sand_bevel",
	"side_key": "sand_side", "lower_key": "sand_deep",
}
const MUD_BASE := {
	"top_key": "mud_top", "bevel_key": "mud_bevel",
	"side_key": "earth_deep", "lower_key": "earth_deep",
}
const WOOD_BASE := {
	"top_key": "wood_light", "bevel_key": "wood_light",
	"side_key": "wood_medium", "lower_key": "wood_deep",
}


func _init() -> void:
	var service := TileLibraryService.new()
	if not service.can_mutate_official():
		push_error("Official procedural rebuild is disabled in release builds.")
		quit(1)
		return
	service.reload()
	var metadata_only := OS.get_cmdline_user_args().has("--metadata-only")
	var failures := CatalogTaxonomy.validation_errors()
	var converted := 0
	var conversion_ids: Array = [] if metadata_only else CONVERTED_IDS
	for tile_id: String in conversion_ids:
		var manifest := service.official_manifest(tile_id)
		if manifest == null:
			failures.append("Missing official manifest: %s" % tile_id)
			continue
		var preset := _make_recipe(tile_id)
		if not _has_authored_detail(preset):
			failures.append("%s produced no authored surface detail" % tile_id)
			continue
		var recipe_path := "%s/%s.tres" % [
			TileLibraryService.OFFICIAL_RECIPE_DIRECTORY, tile_id,
		]
		if ResourceSaver.save(preset, recipe_path) != OK:
			failures.append("Could not save recipe: %s" % tile_id)
			continue
		var bake := service.baker.bake(preset, tile_id)
		if not bool(bake.get("ok", false)):
			failures.append("Bake failed for %s: %s" % [
				tile_id, "; ".join(bake.get("errors", PackedStringArray())),
			])
			continue
		manifest.source_kind = TileLibraryManifest.SOURCE_PROCEDURAL
		manifest.recipe_path = recipe_path
		manifest.runtime_definition = {}
		_apply_catalog_taxonomy(manifest)
		manifest.separate_tiles = preset.separate_tiles
		manifest.baked_roles = bake.get("roles", PackedStringArray())
		if tile_id == "tile_grass_pond_edge" and not manifest.landmark_tags.has("pond"):
			manifest.landmark_tags.append("pond")
		_apply_runtime_semantics(manifest)
		manifest.revision = maxi(manifest.revision, 2)
		manifest.updated_at = STAMP
		manifest.notes = (
			"Original Suma procedural composition. Stable ID retained for runtime "
			+ "references; no extracted source geometry is used."
		)
		if ResourceSaver.save(manifest, manifest.resource_path) != OK:
			failures.append("Could not save manifest: %s" % tile_id)
			continue
		converted += 1
		var stats: Dictionary = bake.get("statistics", {})
		print("PROCEDURALIZED %s — %s triangles" % [
			tile_id, int(stats.get("triangles", 0)),
		])

	# Every official composition receives the current human-facing taxonomy.
	service.reload()
	for manifest in service.official_manifests():
		if not CatalogTaxonomy.has_tile(manifest.tile_id):
			continue
		_apply_catalog_taxonomy(manifest)
		manifest.updated_at = STAMP
		_apply_runtime_semantics(manifest)
		_apply_modular_defaults(manifest)
		if manifest.source_kind == TileLibraryManifest.SOURCE_PROCEDURAL:
			var preset := service.load_recipe(manifest)
			if preset != null:
				preset.preset_name = manifest.display_name
				ResourceSaver.save(preset, manifest.recipe_path)
		if ResourceSaver.save(manifest, manifest.resource_path) != OK:
			failures.append("Could not apply catalog taxonomy: %s" % manifest.tile_id)

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	service.reload()
	var compile_result := service.compiler.compile(service.official_manifests())
	if not bool(compile_result.get("ok", false)):
		for error in compile_result.get("errors", PackedStringArray()):
			push_error(String(error))
		quit(1)
		return
	print("OFFICIAL PROCEDURAL REBUILD COMPLETE — %d converted, %d named" % [
		converted, CatalogTaxonomy.RECIPES.size(),
	])
	quit(0)


func _apply_catalog_taxonomy(manifest: TileLibraryManifest) -> void:
	manifest.display_name = CatalogTaxonomy.display_name(manifest.tile_id)
	manifest.family = CatalogTaxonomy.runtime_family(manifest.tile_id)
	manifest.catalog_category = CatalogTaxonomy.category(manifest.tile_id)
	manifest.catalog_order = CatalogTaxonomy.catalog_order(manifest.tile_id)
	# The current official library is shipped gameplay content, not a staging
	# gallery. Future drafts remain hidden until their Create Tile action.
	manifest.visibility = TileLibraryManifest.VISIBILITY_ACTIVE


func _make_recipe(tile_id: String) -> TileKitPreset:
	var preset := TileKitPreset.reference_clean_grass()
	preset.preset_name = CatalogTaxonomy.display_name(tile_id)
	preset.master_seed = 20260801 + posmod(hash(tile_id), 9000)
	preset.separate_tiles = false
	for layer in preset.layers:
		if layer.kind != "base":
			layer.enabled = false
	match tile_id:
		"tile_clay":
			_set_base(preset, EARTH_BASE, "heaps", 0.026, {"relief_heap_count": [5, 8], "relief_heap_radius": [0.12, 0.23], "relief_resolution": 28})
			_scatter(preset, ["stone_chip", "twig", "stone_chip"], [8, 13], [0.045, 0.11], {"earth_deep": 60.0, "earth_clump": 40.0})
		"tile_cobblestone":
			_set_base(preset, STONE_BASE, "pillow", 0.012)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.31, "stone_cell_z": 0.24, "gap": 0.025, "stone_jitter": 0.09, "stone_height": [0.022, 0.038], "stone_corner": 0.035, "slab_key": "stone_medium", "slab_key_alt": "stone_light"})
			_scatter(preset, ["lobed_clump", "leaf_litter", "pebble"], [4, 7], [0.04, 0.09], {"moss_clump": 70.0, "stone_deep": 30.0})
			preset.separate_tiles = true
		"tile_concrete_brutalist":
			_set_base(preset, STONE_BASE, "none", 0.0)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.82, "stone_cell_z": 0.82, "gap": 0.05, "stone_jitter": 0.0, "stone_height": [0.036, 0.046], "stone_corner": 0.015, "slab_key": "stone_medium"})
			_scatter(preset, ["stone_chip", "pebble"], [3, 5], [0.05, 0.12], {"stone_light": 35.0, "stone_deep": 65.0})
			preset.separate_tiles = true
		"tile_courtyard":
			_set_base(preset, EARTH_BASE, "pillow", 0.008)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.30, "stone_cell_z": 0.17, "gap": 0.014, "stone_jitter": 0.025, "stone_height": [0.016, 0.024], "stone_corner": 0.018, "slab_key": "brick_light", "slab_key_alt": "brick_medium"})
			_scatter(preset, ["leaf_litter", "pebble"], [3, 6], [0.035, 0.075], {"autumn_amber": 45.0, "stone_light": 55.0})
			preset.separate_tiles = true
		"tile_dirt":
			# GG rule: no painted patches. Identity = sculpted ground + a few
			# readable chunky fragments settling in clusters.
			_set_base(preset, EARTH_BASE, "pillow", 0.030)
			_scatter(preset, ["pebble", "nub", "twig", "leaf_litter"], [9, 14], [0.05, 0.12], {"earth_clump": 45.0, "wood_medium": 30.0, "stone_medium": 25.0}, [0.012, 0.028])
		"tile_dirt_crossroad":
			_set_base(preset, EARTH_BASE, "pillow", 0.016)
			_pavers(preset, {"pattern": "trail", "trail_layout": "cross", "trail_width": 0.48, "trail_piece_length": [0.25, 0.48], "trail_jitter": 0.06, "gap": 0.018, "stone_height": [0.008, 0.012], "stone_corner": 0.05, "slab_key": "earth_clump", "sink": 0.007})
			_scatter(preset, ["pebble", "twig"], [6, 10], [0.04, 0.09], {"earth_deep": 55.0, "wood_medium": 45.0})
		"tile_dirt_road":
			_set_base(preset, EARTH_BASE, "pillow", 0.015)
			_pavers(preset, {"pattern": "trail", "trail_layout": "straight", "trail_width": 0.58, "trail_piece_length": [0.28, 0.52], "trail_jitter": 0.08, "gap": 0.02, "stone_height": [0.008, 0.013], "stone_corner": 0.06, "slab_key": "earth_clump", "sink": 0.007})
			_scatter(preset, ["pebble", "leaf_litter"], [5, 9], [0.04, 0.09], {"stone_medium": 45.0, "autumn_amber": 55.0})
		"tile_flagstone":
			_set_base(preset, STONE_BASE, "pillow", 0.010)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.61, "stone_cell_z": 0.43, "gap": 0.032, "stone_jitter": 0.12, "stone_height": [0.020, 0.034], "stone_corner": 0.055, "slab_key": "stone_light", "slab_key_alt": "stone_medium"})
			_scatter(preset, ["lobed_clump", "leaf_litter"], [4, 7], [0.04, 0.09], {"moss_clump": 85.0, "autumn_amber": 15.0})
			preset.separate_tiles = true
		"tile_frosted_stone":
			# Frost as FORM: pillowed stone with drifts of merged snow lumps
			# gathering in hollows — never a white circle painted on grey.
			_set_base(preset, STONE_BASE, "pillow", 0.026)
			# Near-zero spacing and tight clusters: lumps FUSE into two or
			# three drift masses instead of dotting the top as marshmallows.
			_scatter(preset, ["snow_lump", "snow_lump", "snow_lump", "pebble"], [13, 19], [0.10, 0.21], {"snow_lump": 60.0, "snow_top": 25.0, "stone_light": 15.0}, [0.02, 0.045], {"min_spacing": 0.015, "cluster_fraction": 0.88, "cluster_radius": 0.15})
		"tile_garden":
			# Tended bed: soft worked soil with young moss-green shoots and a
			# few buds — growth as geometry, not colour stains.
			_set_base(preset, EARTH_BASE, "pillow", 0.022)
			_grass(preset, {"carpet_spacing": 0.40, "carpet_skip_fraction": 0.45, "leaf_height": [0.055, 0.095], "primary_key": "moss_clump", "secondary_key": "moss_deep"})
			_scatter(preset, ["bud", "pebble", "leaf_pair"], [7, 11], [0.05, 0.11], {"blossom_cream": 35.0, "moss_clump": 40.0, "stone_light": 25.0})
		"tile_grass", "tile_master_grass":
			_set_base(preset, GREEN_BASE, "pillow", 0.020)
			_grass(preset, {"carpet_spacing": 0.27 if tile_id == "tile_master_grass" else 0.31, "carpet_skip_fraction": 0.05 if tile_id == "tile_master_grass" else 0.12, "carpet_jitter": 0.34, "leaf_height": [0.08, 0.15], "leaf_width": [0.045, 0.085]})
			_scatter(preset, ["leaf_pair", "lobed_clump", "nub"], [5, 9], [0.04, 0.10], {"grass_primary": 60.0, "grass_secondary": 40.0})
		"tile_grass_flower":
			_set_base(preset, GREEN_BASE, "pillow", 0.018)
			_grass(preset, {"carpet_spacing": 0.32, "carpet_skip_fraction": 0.16, "carpet_jitter": 0.36})
			_scatter(preset, ["bud", "bud", "leaf_pair"], [10, 16], [0.055, 0.12], {"blossom_pink": 45.0, "blossom_cream": 35.0, "accent_terracotta": 20.0})
		"tile_grass_pond_edge":
			_set_base(preset, GREEN_BASE, "pillow", 0.016, {"basin_depth": 0.12, "basin_rim": 0.23})
			_liquid(preset, {"level": -0.065, "inset": 0.25, "corner_radius": 0.18, "surface_key": "water_blue"})
			_fringe(preset, {"material_key": "moss_clump", "inset": 0.12, "width": 0.10, "height": 0.045, "pieces_per_edge": 9, "jitter": 0.25})
			_scatter(preset, ["lily_pad", "lily_pad", "bud"], [4, 7], [0.10, 0.20], {"lily_green": 75.0, "blossom_cream": 25.0})
			preset.separate_tiles = true
		"tile_grove_autumn":
			# The reference leaf-floor is a DENSE bed of chunky 3D chips, not
			# amber circles under sparse chips. The litter is the whole tile.
			_set_base(preset, EARTH_BASE, "pillow", 0.025)
			_scatter(preset, ["leaf_litter", "leaf_litter", "leaf_litter", "twig", "mushroom"], [30, 44], [0.075, 0.16], {"autumn_amber": 45.0, "autumn_rust": 40.0, "wood_medium": 15.0}, [0.012, 0.024], {"min_spacing": 0.03, "cluster_fraction": 0.75, "cluster_radius": 0.30})
		"tile_grove_birch":
			_set_base(preset, {"top_key": "moss_top", "bevel_key": "moss_bevel", "side_key": "earth_side", "lower_key": "earth_deep"}, "pillow", 0.020)
			_grass(preset, {"carpet_spacing": 0.39, "carpet_skip_fraction": 0.42, "leaf_height": [0.05, 0.10], "primary_key": "moss_clump", "secondary_key": "moss_deep"})
			_scatter(preset, ["wood_chip", "leaf_litter", "twig", "mushroom"], [12, 18], [0.04, 0.11], {"accent_cream": 40.0, "wood_light": 35.0, "moss_clump": 25.0})
		"tile_grove_flowering":
			_set_base(preset, GREEN_BASE, "pillow", 0.024)
			_grass(preset, {"carpet_spacing": 0.36, "carpet_skip_fraction": 0.28, "leaf_height": [0.06, 0.12]})
			_scatter(preset, ["bud", "bud", "leaf_pair", "mushroom"], [15, 23], [0.05, 0.13], {"blossom_pink": 45.0, "blossom_cream": 35.0, "moss_clump": 20.0})
		"tile_grove_mature":
			_set_base(preset, {"top_key": "moss_top", "bevel_key": "moss_bevel", "side_key": "earth_side", "lower_key": "earth_deep"}, "pillow", 0.028)
			_grass(preset, {"carpet_spacing": 0.37, "carpet_skip_fraction": 0.32, "leaf_height": [0.06, 0.12], "primary_key": "moss_clump", "secondary_key": "moss_deep"})
			_scatter(preset, ["lobed_clump", "twig", "leaf_litter", "mushroom"], [11, 18], [0.05, 0.13], {"moss_clump": 50.0, "wood_medium": 30.0, "autumn_amber": 20.0})
		"tile_grove_mossy":
			# Mossy floor: heaped ground under a real moss carpet — low dense
			# rosettes — with cushion clumps riding the mounds.
			_set_base(preset, {"top_key": "moss_top", "bevel_key": "moss_bevel", "side_key": "earth_side", "lower_key": "earth_deep"}, "heaps", 0.034, {"relief_heap_count": [4, 7], "relief_heap_radius": [0.14, 0.28], "relief_resolution": 30})
			_grass(preset, {"carpet_spacing": 0.30, "carpet_skip_fraction": 0.16, "leaf_height": [0.05, 0.10], "primary_key": "moss_clump", "secondary_key": "moss_deep"})
			_scatter(preset, ["lobed_clump", "nub", "mushroom", "twig"], [10, 16], [0.05, 0.14], {"moss_clump": 65.0, "moss_deep": 20.0, "wood_medium": 15.0})
		"tile_master_pavers":
			_set_base(preset, STONE_BASE, "pillow", 0.014)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.34, "stone_cell_z": 0.21, "gap": 0.018, "stone_jitter": 0.08, "stone_height": [0.024, 0.040], "stone_corner": 0.03, "slab_key": "stone_light", "slab_key_alt": "stone_medium"})
			_scatter(preset, ["stone_chip", "pebble", "lobed_clump"], [5, 9], [0.04, 0.10], {"stone_deep": 55.0, "moss_clump": 45.0})
			preset.separate_tiles = true
		"tile_master_wood":
			_set_base(preset, WOOD_BASE, "pillow", 0.008)
			_pavers(preset, {"pattern": "planks", "plank_width": 0.18, "plank_length": [0.42, 0.92], "gap": 0.016, "stone_height": [0.024, 0.032], "stone_corner": 0.014, "slab_key": "wood_light", "slab_key_alt": "wood_medium"})
			_scatter(preset, ["wood_chip", "twig"], [5, 8], [0.04, 0.10], {"wood_medium": 60.0, "wood_deep": 40.0})
			preset.separate_tiles = true
		"tile_mud":
			# Churned wet ground carried entirely by the sculpt: troughs AND
			# ridges, with tracks and half-sunk stones. No painted wet rings.
			_set_base(preset, MUD_BASE, "pillow", 0.040, {"relief_bipolar": true, "relief_frequency": 2.6, "relief_resolution": 30})
			_scatter(preset, ["footprint", "pebble", "nub"], [7, 12], [0.05, 0.12], {"mud_wet": 65.0, "stone_medium": 35.0})
		"tile_open_water":
			_set_base(preset, {"top_key": "water_deep", "bevel_key": "water_blue", "side_key": "water_deep", "lower_key": "stone_deep"}, "pillow", 0.010)
			_liquid(preset, {"level": 0.018, "inset": 0.0, "corner_radius": 0.075, "surface_key": "water_blue"})
			_scatter(preset, ["lily_pad", "lily_pad", "bud"], [3, 6], [0.11, 0.22], {"lily_green": 80.0, "blossom_cream": 20.0})
		"tile_path":
			_set_base(preset, GREEN_BASE, "pillow", 0.018)
			_pavers(preset, {"pattern": "trail", "trail_layout": "straight", "trail_width": 0.62, "trail_piece_length": [0.22, 0.45], "trail_jitter": 0.07, "gap": 0.022, "stone_height": [0.022, 0.034], "stone_corner": 0.06, "slab_key": "stone_light", "slab_key_alt": "stone_medium"})
			_grass(preset, {"carpet_spacing": 0.38, "carpet_skip_fraction": 0.34, "leaf_height": [0.06, 0.11]})
			_scatter(preset, ["pebble", "leaf_pair"], [5, 9], [0.04, 0.09], {"stone_medium": 45.0, "grass_secondary": 55.0})
			preset.separate_tiles = true
		"tile_plain_ground":
			_set_base(preset, SNOW_BASE, "pillow", 0.010)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.82, "stone_cell_z": 0.82, "gap": 0.025, "stone_jitter": 0.0, "stone_height": [0.012, 0.016], "stone_corner": 0.035, "slab_key": "snow_top", "slab_key_alt": "stone_light"})
			_scatter(preset, ["dot", "stone_chip"], [4, 7], [0.025, 0.055], {"snow_lump": 65.0, "stone_light": 35.0})
			preset.separate_tiles = true
		"tile_sand":
			# Sand is pure sculpt — the reference dune tile is one colour, one
			# beautiful surface. A few worn stones, nothing else.
			_set_base(preset, SAND_BASE, "sculpted_dunes", 0.065, {"relief_resolution": 56, "relief_edge_feather": 0.25, "dune_scale": 0.74, "dune_amount": 0.56, "dune_softness": 0.72, "dune_irregularity": 0.62, "dune_lee_depth": 0.28, "dune_direction_degrees": 307.0})
			_scatter(preset, ["pebble", "stone_chip"], [4, 7], [0.05, 0.11], {"sand_side": 60.0, "stone_light": 40.0})
		"tile_snow_drift":
			_set_base(preset, SNOW_BASE, "heaps", 0.115, {"relief_heap_count": [3, 6], "relief_heap_radius": [0.18, 0.38], "relief_resolution": 44})
			_scatter(preset, ["snow_lump", "snow_lump", "pebble"], [7, 12], [0.07, 0.18], {"snow_lump": 85.0, "stone_light": 15.0})
			preset.separate_tiles = true
		"tile_snow_path":
			_set_base(preset, SNOW_BASE, "sculpted_dunes", 0.060, {"relief_resolution": 48, "relief_edge_feather": 0.28, "dune_scale": 0.88, "dune_amount": 0.42, "dune_softness": 0.9, "dune_irregularity": 0.32, "dune_lee_depth": 0.12, "dune_direction_degrees": 22.0})
			_pavers(preset, {"pattern": "trail", "trail_layout": "straight", "trail_width": 0.52, "trail_piece_length": [0.20, 0.36], "trail_jitter": 0.06, "gap": 0.025, "stone_height": [0.007, 0.011], "stone_corner": 0.055, "slab_key": "snow_side", "sink": 0.008})
			_scatter(preset, ["footprint", "footprint", "snow_lump"], [9, 14], [0.055, 0.115], {"snow_side": 75.0, "snow_lump": 25.0})
			preset.separate_tiles = true
		"tile_snowfield":
			_set_base(preset, SNOW_BASE, "sculpted_dunes", 0.085, {"relief_resolution": 56, "relief_edge_feather": 0.30, "dune_scale": 0.96, "dune_amount": 0.64, "dune_softness": 0.92, "dune_irregularity": 0.45, "dune_lee_depth": 0.13, "dune_direction_degrees": 336.0})
			_scatter(preset, ["snow_lump", "snow_lump", "dot"], [6, 10], [0.06, 0.15], {"snow_lump": 90.0, "snow_side": 10.0})
		"tile_stone_clearing":
			# Worn stone ground with moss growing in the low seams — sparse
			# real sprouts and clustered gravel instead of green stains.
			_set_base(preset, STONE_BASE, "heaps", 0.030, {"relief_heap_count": [4, 7], "relief_heap_radius": [0.12, 0.25], "relief_resolution": 30})
			_grass(preset, {"carpet_spacing": 0.44, "carpet_skip_fraction": 0.55, "leaf_height": [0.045, 0.085], "primary_key": "moss_clump", "secondary_key": "moss_deep"})
			_scatter(preset, ["pebble", "stone_chip", "lobed_clump", "pebble"], [11, 17], [0.05, 0.15], {"stone_light": 35.0, "stone_deep": 40.0, "moss_clump": 25.0})
		"tile_stone_crystal":
			_set_base(preset, STONE_BASE, "heaps", 0.032, {"relief_heap_count": [3, 6], "relief_heap_radius": [0.14, 0.26], "relief_resolution": 30})
			_scatter(preset, ["crystal", "crystal", "pebble", "stone_chip"], [8, 13], [0.08, 0.20], {"stone_light": 55.0, "blossom_cream": 25.0, "water_blue": 20.0}, [0.025, 0.07])
		"tile_stone_mossy":
			# Moss takes the stone by GROWING over it: a dense low sprout
			# carpet with clump masses, the stone showing through in worn gaps.
			_set_base(preset, STONE_BASE, "pillow", 0.025)
			_grass(preset, {"carpet_spacing": 0.32, "carpet_skip_fraction": 0.26, "leaf_height": [0.045, 0.095], "primary_key": "moss_clump", "secondary_key": "moss_deep"})
			_scatter(preset, ["lobed_clump", "nub", "pebble"], [9, 15], [0.045, 0.11], {"moss_clump": 65.0, "stone_deep": 35.0})
		"tile_stone_road":
			_set_base(preset, STONE_BASE, "pillow", 0.015)
			_pavers(preset, {"pattern": "trail", "trail_layout": "straight", "trail_width": 0.76, "trail_piece_length": [0.24, 0.50], "trail_jitter": 0.10, "gap": 0.028, "stone_height": [0.020, 0.034], "stone_corner": 0.055, "slab_key": "stone_light", "slab_key_alt": "stone_medium"})
			_scatter(preset, ["stone_chip", "lobed_clump", "leaf_litter"], [8, 13], [0.045, 0.11], {"stone_deep": 45.0, "moss_clump": 40.0, "autumn_amber": 15.0})
			preset.separate_tiles = true
		"tile_stone_ruin":
			_set_base(preset, STONE_BASE, "heaps", 0.028, {"relief_heap_count": [3, 5], "relief_heap_radius": [0.16, 0.30], "relief_resolution": 30})
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.62, "stone_cell_z": 0.55, "gap": 0.05, "stone_jitter": 0.14, "stone_height": [0.028, 0.052], "stone_corner": 0.04, "slab_key": "stone_medium", "slab_key_alt": "stone_light"})
			_fringe(preset, {"material_key": "stone_deep", "inset": 0.07, "width": 0.10, "height": 0.06, "pieces_per_edge": 6, "jitter": 0.32})
			_scatter(preset, ["boulder", "stone_chip", "lobed_clump"], [5, 9], [0.10, 0.25], {"stone_deep": 60.0, "moss_clump": 40.0}, [0.025, 0.06])
			preset.separate_tiles = true
		"tile_wooden_planks":
			_set_base(preset, WOOD_BASE, "pillow", 0.010)
			_pavers(preset, {"pattern": "planks", "plank_width": 0.20, "plank_length": [0.48, 1.05], "gap": 0.018, "stone_height": [0.026, 0.038], "stone_corner": 0.016, "slab_key": "wood_light", "slab_key_alt": "wood_medium"})
			_scatter(preset, ["wood_chip", "twig", "leaf_litter"], [6, 10], [0.04, 0.10], {"wood_medium": 50.0, "wood_deep": 35.0, "autumn_amber": 15.0})
			preset.separate_tiles = true
	return preset


func _apply_runtime_semantics(manifest: TileLibraryManifest) -> void:
	match manifest.tile_id:
		"tile_garden":
			manifest.unlock_level = {"fishing": 10.0}
		"tile_grass_pond_edge", "tile_proc_pond_basin":
			manifest.water_cells = PackedStringArray(["pond"])
			manifest.anchor_id = "pond_anchor"
			manifest.collision_profile = "pond_basin"
			if manifest.tile_id == "tile_grass_pond_edge":
				manifest.unlock_level = {"fishing": 6.0}
		"tile_grove_autumn":
			manifest.unlock_level = {"woodcutting": 7.0}
		"tile_open_water":
			manifest.water_cells = PackedStringArray(["open_water"])
			manifest.anchor_id = "pond_anchor"
			manifest.decor_sockets = 0
			manifest.structure_sockets = 1
			manifest.render_profile = "continuous_water"
			manifest.collision_profile = "none"
		"tile_stone_clearing", "tile_stone_mossy", "tile_stone_road", "tile_stone_ruin":
			manifest.landmark_tags = PackedStringArray(["ruin"])
		"tile_stone_crystal":
			manifest.anchor_id = "stone_anchor"


func _apply_modular_defaults(manifest: TileLibraryManifest) -> void:
	var special_surface := manifest.tile_id in [
		"tile_grass_pond_edge", "tile_proc_pond_basin", "tile_open_water",
	]
	manifest.stackable = not special_surface
	manifest.supports_tiles = not special_surface


func _set_base(preset: TileKitPreset, palette: Dictionary, style: String,
		amplitude: float, extras: Dictionary = {}) -> void:
	var layer := _layer(preset, "base")
	layer.params.merge(palette, true)
	layer.params.merge({
		"relief_style": style,
		"relief_amplitude": amplitude,
		"relief_resolution": 24,
		"relief_edge_feather": 0.20,
	}, true)
	layer.params.merge(extras, true)


func _patches(preset: TileKitPreset, params: Dictionary) -> void:
	_enable(preset, "dressing", params)


func _pavers(preset: TileKitPreset, params: Dictionary) -> void:
	_enable(preset, "pavers", params)


func _grass(preset: TileKitPreset, params: Dictionary) -> void:
	_enable(preset, "grass_clusters", params)


func _liquid(preset: TileKitPreset, params: Dictionary) -> void:
	_enable(preset, "liquid", params)


func _fringe(preset: TileKitPreset, params: Dictionary) -> void:
	_enable(preset, "fringe", params)


func _scatter(preset: TileKitPreset, shapes: Array, count: Array,
		diameter: Array, colors: Dictionary, height: Array = [0.008, 0.022],
		overrides: Dictionary = {}) -> void:
	var params := {
		"shapes": shapes,
		"count": count,
		"diameter": diameter,
		"height": height,
		"min_spacing": 0.055,
		"edge_margin": 0.035,
		"on_dressing_fraction": 0.55,
		"color_weights": colors,
	}
	params.merge(overrides, true)
	_enable(preset, "clutter", params)


func _enable(preset: TileKitPreset, kind: String, params: Dictionary) -> void:
	var layer := _layer(preset, kind)
	layer.enabled = true
	layer.params.merge(params, true)


func _layer(preset: TileKitPreset, kind: String) -> TileKitLayer:
	var existing := preset.layer_of_kind(kind)
	if existing != null:
		return existing
	var created := TileLayerParameterSchema.new_layer(kind)
	var index := TileLayerParameterSchema.ordered_insertion_index(preset.layers, kind)
	preset.layers.insert(index, created)
	return created


func _has_authored_detail(preset: TileKitPreset) -> bool:
	var base := preset.layer_of_kind("base")
	if base != null and (
		String(base.value("relief_style", "none")) != "none"
		and float(base.value("relief_amplitude", 0.0)) > 0.001
	):
		return true
	for layer in preset.layers:
		if layer.enabled and layer.kind != "base":
			return true
	return false
