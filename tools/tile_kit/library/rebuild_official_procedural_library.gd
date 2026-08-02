extends SceneTree
## Development-only content migration that replaces every imported ground tile
## with an original, editable Tile Kit recipe.
##
## Stable IDs intentionally survive: worlds and authored rewards refer to IDs,
## while names and geometry are allowed to evolve. No extracted mesh, texture,
## or material is copied; the configurations below use only Tile Kit's generic
## builders and Suma palette.
##
## This script is the single authoring authority for the official library:
## every one of the 56 recipes is composed here, in the shared premium-diorama
## language — macro sculpt first, a few deliberate medium clusters, sparse
## micro accents — and rebuilding re-derives recipes, bakes, and the compiled
## catalog in one pass.

const STAMP := "2026-08-02 12:00:00"
const CatalogTaxonomy := preload("res://tools/tile_kit/library/tile_catalog_taxonomy.gd")

## Human-facing names, scenery groups, and order live in
## TileCatalogTaxonomy. This rebuild owns geometry and applies that taxonomy;
## it never carries a second rename table that can drift from the editor.

## The complete official roster. This rebuild is the single authoring
## authority for every recipe: run it and the whole library re-derives from
## the compositions below — no tile is left on an older visual generation.
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
	"tile_kit_grass", "tile_proc_flower_meadow", "tile_proc_garden_path",
	"tile_proc_fenced_meadow", "tile_proc_pond_basin", "tile_proc_tilled_field",
	"tile_proc_boulder_ground", "tile_proc_mossy_forest_floor",
	"tile_proc_autumn_litter", "tile_proc_mulch_dirt_floor",
	"tile_proc_snow_field", "tile_proc_snow_drifts_study",
	"tile_proc_sandy_ground", "tile_proc_sand_dunes_study",
	"tile_proc_mud_bed", "tile_proc_gravel_yard",
	"tile_proc_cobblestone_paving", "tile_proc_wood_plank_deck",
	"tile_proc_concrete_slabs", "tile_proc_brick_court",
	"tile_proc_checker_slabs",
]

const GREEN_BASE := {
	"top_key": "tile_top", "bevel_key": "tile_top_bevel",
	"side_key": "tile_side", "lower_key": "tile_lower",
}
const MOSS_BASE := {
	"top_key": "moss_top", "bevel_key": "moss_bevel",
	"side_key": "earth_side", "lower_key": "earth_deep",
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
	# Fast iteration for visual tuning: recipes and manifests update, the
	# 16-mask bake is skipped. Ship only after a FULL run.
	var skip_bake := OS.get_cmdline_user_args().has("--skip-bake")
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
		var bake := {"ok": true, "roles": manifest.baked_roles, "statistics": {}}
		if not skip_bake:
			bake = service.baker.bake(preset, tile_id)
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


## Every recipe below composes the same shared vocabulary. The visual
## hierarchy contract, applied per tile:
##   MACRO   the base sculpt (relief, basin, paving field, turf mass)
##   MEDIUM  two to five deliberate clusters or features
##   MICRO   sparse punctuation only — never the tile's identity
func _make_recipe(tile_id: String) -> TileKitPreset:
	var preset := _fresh_preset()
	preset.preset_name = CatalogTaxonomy.display_name(tile_id)
	preset.master_seed = 20260801 + posmod(hash(tile_id), 9000)
	preset.separate_tiles = false
	match tile_id:
		# ------------------------------------------------------------ meadow
		"tile_grass":
			# GOLD MASTER 01 — Standard Grass. Thin soil body, distinct turf
			# cap with a wobbled perimeter, hand-directed cluster layout,
			# partial fringe. The library's quality contract derives from
			# this tile; nothing else ships until it passes.
			_set_base(preset, {"top_key": "tile_top",
				"bevel_key": "tile_top_bevel", "side_key": "earth_side",
				"lower_key": "earth_deep", "turf_side_key": "tile_side"},
				"pillow", 0.026,
				{"relief_frequency": 1.3, "relief_resolution": 16,
					"relief_edge_feather": 0.14,
					"turf_cap": true, "turf_thickness": 0.078,
					"turf_wobble": 0.013, "top_bevel": 0.034,
					"corner_radius": 0.05, "bevel_segments": 4})
			_grass(preset, {"coverage_mode": "gold_grass", "tuft_scale": 1.0})
		"tile_kit_grass":
			# Dense Grass: tighter interlock, thicker pile, more sculpted tips.
			_set_base(preset, GREEN_BASE, "pillow", 0.016)
			_turf(preset, {"turf_spacing": 0.21, "turf_footprint": [0.27, 0.40],
				"turf_height": [0.050, 0.072], "turf_skip_fraction": 0.05,
				"blade_fraction": 0.55, "accent_clumps": [1, 2]})
		"tile_grass_flower":
			_set_base(preset, GREEN_BASE, "pillow", 0.014)
			_turf(preset, {"turf_spacing": 0.23, "turf_footprint": [0.26, 0.38],
				"turf_height": [0.044, 0.064], "blade_fraction": 0.42})
			_scatter(preset, ["bud"], [5, 8], [0.10, 0.15],
				{"blossom_pink": 50.0, "blossom_cream": 32.0,
					"accent_terracotta": 18.0}, [0.018, 0.028],
				{"min_spacing": 0.14, "cluster_fraction": 0.85,
					"cluster_radius": 0.20})
		"tile_proc_flower_meadow":
			# The meadow reads as grass FIRST; flowers are two deliberate
			# drifts of large closed buds, never one of every colour.
			_set_base(preset, GREEN_BASE, "pillow", 0.015)
			_turf(preset, {"turf_spacing": 0.24, "turf_footprint": [0.25, 0.36],
				"turf_height": [0.040, 0.058], "turf_skip_fraction": 0.14,
				"blade_fraction": 0.40})
			_scatter(preset, ["bud"], [6, 9], [0.12, 0.17],
				{"blossom_pink": 55.0, "blossom_cream": 30.0,
					"accent_terracotta": 15.0}, [0.020, 0.032],
				{"min_spacing": 0.13, "cluster_fraction": 0.9,
					"cluster_radius": 0.17})
		"tile_master_grass":
			# PROTOTYPE — Wild Grass: tall dramatic wind-swept tufts over
			# larger turf masses; the strongest grass silhouette.
			_set_base(preset, GREEN_BASE, "pillow", 0.016)
			_grass(preset, {"coverage_mode": "tufts", "tuft_scale": 1.45,
				"mass_scale": 1.15, "mass_height": [0.034, 0.055],
				"tuft_lean": 0.9, "extra_tufts": [1, 2]})
		"tile_proc_fenced_meadow":
			_set_base(preset, GREEN_BASE, "pillow", 0.014)
			_turf(preset, {"turf_spacing": 0.24, "turf_footprint": [0.24, 0.35],
				"turf_height": [0.040, 0.058], "blade_fraction": 0.38,
				"turf_overhang": 0.0, "edge_margin": 0.12})
			_enable(preset, "fence", {"edges": [0, 1, 2, 3],
				"post_key": "wood_deep", "rail_key": "wood_medium"})

		# ------------------------------------------------------------ forest
		"tile_grove_mature":
			# PROTOTYPE — Forest Floor: one broad moss mass, one leaf-litter
			# drift, sparse dark tufts, a mushroom accent, exposed loam as
			# negative space.
			_set_base(preset, MOSS_BASE, "pillow", 0.020)
			_grass(preset, {"coverage_mode": "tufts", "tuft_scale": 0.85,
				"mass_scale": 1.1, "mass_height": [0.026, 0.042],
				"tuft_lean": 0.45, "extra_tufts": [0, 0],
				"primary_key": "moss_top", "blade_key": "moss_deep",
				"blade_light_key": "moss_clump"})
			_scatter(preset, ["leaf_litter", "leaf_litter", "twig",
				"mushroom"], [8, 12], [0.10, 0.17],
				{"autumn_amber": 45.0, "autumn_rust": 30.0,
					"wood_medium": 25.0}, [0.014, 0.026],
				{"placement_mode": "drift", "drift_bed_key": "autumn_rust",
					"min_spacing": 0.045})
		"tile_grove_birch":
			_set_base(preset, MOSS_BASE, "pillow", 0.020)
			_turf(preset, {"turf_spacing": 0.33, "turf_footprint": [0.20, 0.30],
				"turf_height": [0.024, 0.038], "turf_skip_fraction": 0.36,
				"blade_fraction": 0.22, "primary_key": "moss_top", "blade_key": "moss_deep",
				"secondary_key": "moss_clump"})
			_scatter(preset, ["wood_chip", "leaf_litter", "twig", "mushroom"],
				[7, 10], [0.08, 0.14],
				{"accent_cream": 38.0, "wood_light": 34.0, "moss_clump": 28.0},
				[0.012, 0.024])
		"tile_grove_flowering":
			_set_base(preset, GREEN_BASE, "pillow", 0.020)
			_turf(preset, {"turf_spacing": 0.28, "turf_footprint": [0.22, 0.33],
				"turf_height": [0.030, 0.048], "turf_skip_fraction": 0.24,
				"blade_fraction": 0.35})
			_scatter(preset, ["bud", "bud", "leaf_pair", "mushroom"], [8, 12],
				[0.09, 0.15],
				{"blossom_pink": 45.0, "blossom_cream": 35.0, "moss_clump": 20.0},
				[0.016, 0.028])
		"tile_grove_autumn":
			# Autumn Forest Floor: the litter is the identity — one or two
			# raked drifts of chunky chips over a low bedded mass.
			_set_base(preset, EARTH_BASE, "pillow", 0.024)
			_scatter(preset, ["leaf_litter", "leaf_litter", "leaf_litter",
				"twig", "mushroom"], [24, 32], [0.11, 0.19],
				{"autumn_amber": 45.0, "autumn_rust": 40.0, "wood_medium": 15.0},
				[0.014, 0.026],
				{"placement_mode": "drift", "drift_bed_key": "autumn_amber",
					"min_spacing": 0.035})
		"tile_grove_mossy":
			_set_base(preset, MOSS_BASE, "heaps", 0.032,
				{"relief_heap_count": [4, 7], "relief_heap_radius": [0.14, 0.28],
					"relief_resolution": 30})
			_turf(preset, {"turf_spacing": 0.26, "turf_footprint": [0.24, 0.36],
				"turf_height": [0.028, 0.046], "turf_skip_fraction": 0.12,
				"blade_fraction": 0.28, "primary_key": "moss_top", "blade_key": "moss_deep",
				"secondary_key": "moss_clump"})
			_scatter(preset, ["lobed_clump", "nub", "mushroom"], [4, 7],
				[0.10, 0.18],
				{"moss_clump": 60.0, "moss_deep": 22.0, "wood_medium": 18.0},
				[0.016, 0.030])
		"tile_proc_mossy_forest_floor":
			_set_base(preset, MOSS_BASE, "pillow", 0.024)
			_turf(preset, {"turf_spacing": 0.29, "turf_footprint": [0.22, 0.33],
				"turf_height": [0.026, 0.042], "turf_skip_fraction": 0.28,
				"blade_fraction": 0.24, "primary_key": "moss_top", "blade_key": "moss_deep",
				"secondary_key": "moss_clump"})
			_scatter(preset, ["lobed_clump", "twig", "mushroom", "leaf_litter"],
				[5, 8], [0.09, 0.16],
				{"moss_clump": 45.0, "moss_deep": 25.0, "wood_medium": 30.0},
				[0.014, 0.026], {"mushroom_cap_key": "accent_terracotta"})
		"tile_proc_autumn_litter":
			# Fallen Leaves: a lighter litter than the grove — the drift is
			# narrower and more ground shows through.
			_set_base(preset, EARTH_BASE, "pillow", 0.020)
			_scatter(preset, ["leaf_litter", "leaf_litter", "twig", "mushroom"],
				[18, 24], [0.10, 0.18],
				{"autumn_amber": 45.0, "autumn_rust": 35.0, "wood_medium": 20.0},
				[0.012, 0.024],
				{"placement_mode": "drift", "drift_bed_key": "autumn_rust",
					"min_spacing": 0.04,
					"mushroom_cap_key": "autumn_rust"})

		# ------------------------------------------------------------ garden
		"tile_garden":
			# Tended bed: worked soil, young shoots, a few buds — growth as
			# geometry, not colour stains.
			_set_base(preset, EARTH_BASE, "pillow", 0.022)
			_turf(preset, {"turf_spacing": 0.36, "turf_footprint": [0.16, 0.24],
				"turf_height": [0.020, 0.034], "turf_skip_fraction": 0.52,
				"blade_fraction": 0.55, "accent_clumps": [0, 1],
				"primary_key": "moss_top", "blade_key": "moss_deep", "secondary_key": "moss_clump"})
			_scatter(preset, ["bud", "leaf_pair", "pebble"], [5, 8],
				[0.07, 0.13],
				{"blossom_cream": 35.0, "moss_clump": 40.0, "stone_light": 25.0},
				[0.012, 0.024])
		"tile_proc_mulch_dirt_floor":
			_set_base(preset, EARTH_BASE, "pillow", 0.022)
			_scatter(preset, ["wood_chip", "wood_chip", "twig", "pebble",
				"mushroom"], [13, 18], [0.09, 0.18],
				{"wood_light": 35.0, "wood_medium": 35.0, "wood_deep": 20.0,
					"stone_medium": 10.0}, [0.014, 0.026],
				{"min_spacing": 0.06, "cluster_fraction": 0.8,
					"cluster_radius": 0.26,
					"mushroom_cap_key": "accent_cream"})
		"tile_path":
			_set_base(preset, GREEN_BASE, "pillow", 0.015)
			_pavers(preset, {"pattern": "trail", "trail_layout": "straight",
				"trail_width": 0.62, "trail_piece_length": [0.22, 0.45],
				"trail_jitter": 0.07, "gap": 0.022,
				"stone_height": [0.022, 0.034], "stone_corner": 0.06,
				"slab_key": "stone_light", "slab_key_alt": "stone_medium"})
			_turf(preset, {"turf_spacing": 0.30, "turf_footprint": [0.20, 0.30],
				"turf_height": [0.028, 0.044], "turf_skip_fraction": 0.30,
				"blade_fraction": 0.32})
			preset.separate_tiles = true
		"tile_proc_garden_path":
			_pavers(preset, {"pattern": "stepping", "stepping_count": [4, 6],
				"stepping_size": [0.28, 0.38], "stone_corner": 0.07,
				"stone_height": [0.024, 0.032], "slab_key": "stone_light"})
			_set_base(preset, GREEN_BASE, "pillow", 0.014)
			_turf(preset, {"turf_spacing": 0.27, "turf_footprint": [0.22, 0.32],
				"turf_height": [0.030, 0.046], "blade_fraction": 0.36})
			preset.separate_tiles = true
		"tile_plain_ground":
			_set_base(preset, SNOW_BASE, "pillow", 0.010)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.82,
				"stone_cell_z": 0.82, "gap": 0.025, "stone_jitter": 0.0,
				"stone_height": [0.014, 0.018], "stone_corner": 0.045,
				"slab_key": "snow_top", "slab_key_alt": "stone_light"})
			_scatter(preset, ["stone_chip"], [2, 4], [0.05, 0.09],
				{"snow_lump": 65.0, "stone_light": 35.0}, [0.008, 0.014])
			preset.separate_tiles = true

		# -------------------------------------------------------------- farm
		"tile_dirt":
			# PROTOTYPE — Dirt Ground: softly compressed loam with two
			# clusters of chunky flat-shaded clods, exactly the reference
			# soil language. No dots.
			_set_base(preset, EARTH_BASE, "pillow", 0.030)
			_scatter(preset, ["clod", "clod", "clod", "pebble"], [6, 9],
				[0.12, 0.20],
				{"earth_clump": 40.0, "earth_deep": 35.0, "earth_side": 25.0},
				[0.016, 0.030],
				{"cluster_fraction": 0.9, "cluster_radius": 0.22,
					"min_spacing": 0.075})
		"tile_clay":
			_set_base(preset, EARTH_BASE, "heaps", 0.026,
				{"relief_heap_count": [5, 8], "relief_heap_radius": [0.12, 0.23],
					"relief_resolution": 28})
			_scatter(preset, ["stone_chip", "twig"], [5, 8], [0.07, 0.13],
				{"earth_deep": 60.0, "earth_clump": 40.0}, [0.010, 0.020])
		"tile_proc_tilled_field":
			# Pure worked sculpt: the furrows ARE the tile.
			_set_base(preset, EARTH_BASE, "furrows", 0.034,
				{"relief_rows": 5, "relief_resolution": 30})
			_scatter(preset, ["nub", "pebble"], [2, 4], [0.06, 0.11],
				{"earth_clump": 70.0, "stone_medium": 30.0}, [0.010, 0.018])
		"tile_dirt_road":
			_set_base(preset, EARTH_BASE, "pillow", 0.015)
			_pavers(preset, {"pattern": "trail", "trail_layout": "straight",
				"trail_width": 0.58, "trail_piece_length": [0.28, 0.52],
				"trail_jitter": 0.08, "gap": 0.02,
				"stone_height": [0.008, 0.013], "stone_corner": 0.06,
				"slab_key": "earth_clump", "sink": 0.007})
			_scatter(preset, ["pebble", "leaf_litter"], [4, 7], [0.06, 0.11],
				{"stone_medium": 45.0, "autumn_amber": 55.0}, [0.010, 0.020])
		"tile_dirt_crossroad":
			_set_base(preset, EARTH_BASE, "pillow", 0.016)
			_pavers(preset, {"pattern": "trail", "trail_layout": "cross",
				"trail_width": 0.48, "trail_piece_length": [0.25, 0.48],
				"trail_jitter": 0.06, "gap": 0.018,
				"stone_height": [0.008, 0.012], "stone_corner": 0.05,
				"slab_key": "earth_clump", "sink": 0.007})
			_scatter(preset, ["pebble", "twig"], [4, 7], [0.06, 0.11],
				{"earth_deep": 55.0, "wood_medium": 45.0}, [0.010, 0.020])

		# ------------------------------------------------------------- swamp
		"tile_grass_pond_edge":
			_set_base(preset, GREEN_BASE, "pillow", 0.014,
				{"basin_depth": 0.12, "basin_rim": 0.23})
			_liquid(preset, {"level": -0.065, "inset": 0.25,
				"corner_radius": 0.18, "surface_key": "water_blue"})
			_fringe(preset, {"material_key": "moss_clump", "inset": 0.12,
				"width": 0.10, "height": 0.045, "pieces_per_edge": 9,
				"jitter": 0.25})
			_scatter(preset, ["lily_pad", "lily_pad", "bud"], [3, 5],
				[0.13, 0.22], {"lily_green": 75.0, "blossom_cream": 25.0},
				[0.008, 0.014])
			preset.separate_tiles = true
		"tile_proc_pond_basin":
			# PROTOTYPE — Small Pond: a real water volume — grass-rimmed
			# basin, translucent pale surface set well below the rim, one
			# lily group and a reed tuft on the rim.
			_set_base(preset, GREEN_BASE, "none", 0.0,
				{"basin_depth": 0.13, "basin_rim": 0.16,
					"water_key": "water_blue"})
			_scatter(preset, ["lily_pad", "lily_pad", "bud"], [2, 4],
				[0.20, 0.30], {"lily_green": 78.0, "blossom_cream": 22.0},
				[0.008, 0.014],
				{"min_spacing": 0.16, "edge_margin": 0.30,
					"cluster_fraction": 1.0, "cluster_radius": 0.15})
			preset.separate_tiles = true
		"tile_open_water":
			_set_base(preset, {"top_key": "water_deep", "bevel_key": "water_blue",
				"side_key": "water_deep", "lower_key": "stone_deep"},
				"pillow", 0.010)
			_liquid(preset, {"level": 0.018, "inset": 0.0,
				"corner_radius": 0.075, "surface_key": "water_blue",
				"ripple_count": [2, 3], "rim_width": 0.028})
			_scatter(preset, ["lily_pad", "lily_pad", "bud"], [2, 4],
				[0.13, 0.24], {"lily_green": 80.0, "blossom_cream": 20.0},
				[0.008, 0.014])
		"tile_proc_mud_bed":
			_set_base(preset, MUD_BASE, "pillow", 0.034,
				{"relief_bipolar": true, "relief_frequency": 2.6,
					"relief_resolution": 26})
			_scatter(preset, ["nub", "pebble", "twig"], [3, 5], [0.08, 0.14],
				{"earth_clump": 60.0, "stone_medium": 40.0}, [0.012, 0.024])
		"tile_mud":
			# Churned wet ground: troughs AND ridges, flat wet sheens pooling
			# in the lows, tracks pressed through — no painted rings.
			_set_base(preset, MUD_BASE, "pillow", 0.040,
				{"relief_bipolar": true, "relief_frequency": 2.6,
					"relief_resolution": 30})
			_patches(preset, {"patch_profile": "sheen",
				"large_count": [1, 2], "medium_count": [1, 2],
				"small_count": [0, 0], "large_radius": [0.16, 0.24],
				"medium_radius": [0.10, 0.15], "allow_overlap": false,
				"color_weights": {"mud_wet": 100.0}})
			_scatter(preset, ["footprint", "pebble", "nub"], [5, 8],
				[0.07, 0.13], {"mud_wet": 65.0, "stone_medium": 35.0},
				[0.010, 0.020])

		# ------------------------------------------------------------- beach
		"tile_sand":
			# Pure sculpt: one colour, one beautiful wind-shaped surface.
			_set_base(preset, SAND_BASE, "sculpted_dunes", 0.105,
				{"relief_resolution": 60, "relief_edge_feather": 0.22,
					"dune_scale": 0.76, "dune_amount": 0.46,
					"dune_softness": 0.55, "dune_irregularity": 0.62,
					"dune_lee_depth": 0.52, "dune_direction_degrees": 307.0,
					"dune_height_exponent": 1.30})
		"tile_proc_sandy_ground":
			_set_base(preset, SAND_BASE, "dunes", 0.045,
				{"relief_frequency": 1.8, "relief_resolution": 24})
			_scatter(preset, ["pebble", "oval"], [3, 5], [0.07, 0.12],
				{"stone_light": 55.0, "sand_side": 45.0}, [0.010, 0.020])
		"tile_proc_sand_dunes_study":
			# PROTOTYPE — Sand Dunes: few broad wind-swept ridges at LOW mesh
			# resolution, so the sculpt reads as confident hand-modelled
			# sweeps rather than simulation noise.
			_set_base(preset, SAND_BASE, "sculpted_dunes", 0.105,
				{"relief_resolution": 20, "relief_edge_feather": 0.24,
					"dune_scale": 0.85, "dune_amount": 0.40,
					"dune_softness": 0.62, "dune_irregularity": 0.55,
					"dune_lee_depth": 0.50, "dune_direction_degrees": 318.0,
					"dune_height_exponent": 1.25})
		"tile_wooden_planks":
			_set_base(preset, WOOD_BASE, "pillow", 0.010)
			_pavers(preset, {"pattern": "planks", "plank_width": 0.20,
				"plank_length": [0.48, 1.05], "gap": 0.020,
				"stone_height": [0.026, 0.038], "stone_corner": 0.016,
				"slab_key": "", "color_weights": {"wood_light": 58.0,
					"wood_medium": 42.0}})
			_scatter(preset, ["wood_chip", "twig"], [3, 6], [0.06, 0.11],
				{"wood_medium": 50.0, "wood_deep": 35.0, "autumn_amber": 15.0},
				[0.008, 0.016])
			preset.separate_tiles = true

		# ------------------------------------------------------------ tundra
		"tile_snowfield":
			# Fresh Snow: nearly untouched — the sculpt carries everything,
			# with at most a couple of large settled pillows.
			_set_base(preset, SNOW_BASE, "sculpted_dunes", 0.115,
				{"relief_resolution": 56, "relief_edge_feather": 0.28,
					"dune_scale": 0.96, "dune_amount": 0.58,
					"dune_softness": 0.80, "dune_irregularity": 0.45,
					"dune_lee_depth": 0.28, "dune_direction_degrees": 336.0,
					"dune_height_exponent": 1.12})
			_scatter(preset, ["snow_lump"], [1, 3], [0.14, 0.24],
				{"snow_lump": 100.0}, [0.014, 0.024],
				{"cluster_fraction": 0.9, "cluster_radius": 0.18})
		"tile_proc_snow_field":
			# The quietest tile in the kit: sculpt only.
			_set_base(preset, SNOW_BASE, "sculpted_dunes", 0.072,
				{"relief_resolution": 56, "relief_edge_feather": 0.30,
					"dune_scale": 0.92, "dune_amount": 0.58,
					"dune_softness": 0.90, "dune_irregularity": 0.40,
					"dune_lee_depth": 0.12, "dune_direction_degrees": 322.0})
		"tile_snow_drift":
			# PROTOTYPE — Deep Snow: a THICK sculpted snow volume (the
			# audited full-snow cap rises ~18% of tile width) with two or
			# three broad settled pillows fused into it.
			_set_base(preset, SNOW_BASE, "heaps", 0.150,
				{"relief_heap_count": [3, 4], "relief_heap_radius": [0.26, 0.44],
					"relief_resolution": 22, "relief_micro": 0.010})
			_scatter(preset, ["drift_mound", "snow_lump"], [2, 4],
				[0.22, 0.34], {"snow_lump": 100.0}, [0.018, 0.030],
				{"min_spacing": 0.12, "cluster_fraction": 0.9,
					"cluster_radius": 0.24})
			preset.separate_tiles = true
		"tile_proc_snow_drifts_study":
			_set_base(preset, SNOW_BASE, "sculpted_dunes", 0.105,
				{"relief_resolution": 64, "relief_edge_feather": 0.30,
					"dune_scale": 0.92, "dune_amount": 0.68,
					"dune_softness": 0.88, "dune_irregularity": 0.52,
					"dune_lee_depth": 0.16, "dune_direction_degrees": 322.0,
					"dune_height_exponent": 0.92})
		"tile_snow_path":
			_set_base(preset, SNOW_BASE, "sculpted_dunes", 0.055,
				{"relief_resolution": 48, "relief_edge_feather": 0.28,
					"dune_scale": 0.88, "dune_amount": 0.42,
					"dune_softness": 0.9, "dune_irregularity": 0.32,
					"dune_lee_depth": 0.12, "dune_direction_degrees": 22.0})
			_pavers(preset, {"pattern": "trail", "trail_layout": "straight",
				"trail_width": 0.52, "trail_piece_length": [0.20, 0.36],
				"trail_jitter": 0.06, "gap": 0.025,
				"stone_height": [0.007, 0.011], "stone_corner": 0.055,
				"slab_key": "snow_side", "sink": 0.008})
			_scatter(preset, ["footprint", "snow_lump"], [5, 8],
				[0.09, 0.15], {"snow_side": 70.0, "snow_lump": 30.0},
				[0.008, 0.014])
			preset.separate_tiles = true
		"tile_frosted_stone":
			# Frost as FORM: pillowed stone with two or three broad drift
			# masses gathering in the hollows.
			_set_base(preset, STONE_BASE, "pillow", 0.026)
			_scatter(preset, ["drift_mound", "snow_lump", "snow_lump"],
				[5, 8], [0.14, 0.24],
				{"snow_lump": 70.0, "snow_top": 30.0}, [0.016, 0.028],
				{"min_spacing": 0.02, "cluster_fraction": 0.9,
					"cluster_radius": 0.16})

		# ------------------------------------------------------------ market
		"tile_courtyard":
			_set_base(preset, EARTH_BASE, "pillow", 0.008)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.30,
				"stone_cell_z": 0.17, "gap": 0.016, "stone_jitter": 0.025,
				"stone_height": [0.018, 0.026], "stone_corner": 0.020,
				"slab_key": "", "color_weights": {"brick_light": 62.0,
					"brick_medium": 38.0}})
			_scatter(preset, ["leaf_litter", "pebble"], [2, 4], [0.06, 0.10],
				{"autumn_amber": 45.0, "stone_light": 55.0}, [0.008, 0.014])
			preset.separate_tiles = true
		"tile_proc_brick_court":
			_set_base(preset, {"top_key": "brick_medium",
				"bevel_key": "brick_medium", "side_key": "brick_medium",
				"lower_key": "earth_deep"}, "none", 0.0)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.31,
				"stone_cell_z": 0.16, "gap": 0.014, "stone_jitter": 0.03,
				"stone_height": [0.018, 0.024], "stone_corner": 0.020,
				"slab_key": "brick_light"})
			preset.separate_tiles = true
		"tile_proc_checker_slabs":
			_set_base(preset, STONE_BASE, "none", 0.0)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.83,
				"stone_cell_z": 0.83, "gap": 0.020, "stone_corner": 0.030,
				"stone_jitter": 0.008, "stone_height": [0.020, 0.026],
				"slab_key": "stone_light", "slab_key_alt": "sand_top"})
			preset.separate_tiles = true
		"tile_proc_wood_plank_deck":
			_set_base(preset, {"top_key": "wood_deep", "bevel_key": "wood_medium",
				"side_key": "wood_medium", "lower_key": "wood_deep"}, "none", 0.0)
			_pavers(preset, {"pattern": "planks", "plank_width": 0.215,
				"plank_length": [0.55, 0.95], "gap": 0.022,
				"stone_corner": 0.024, "stone_height": [0.018, 0.026],
				"slab_key": "wood_medium"})
			preset.separate_tiles = true
		"tile_master_wood":
			_set_base(preset, WOOD_BASE, "pillow", 0.008)
			_pavers(preset, {"pattern": "planks", "plank_width": 0.26,
				"plank_length": [0.55, 1.15], "gap": 0.018,
				"stone_height": [0.024, 0.032], "stone_corner": 0.016,
				"slab_key": "", "color_weights": {"wood_light": 62.0,
					"wood_medium": 38.0}})
			_scatter(preset, ["wood_chip", "twig"], [2, 4], [0.06, 0.10],
				{"wood_medium": 60.0, "wood_deep": 40.0}, [0.008, 0.014])
			preset.separate_tiles = true

		# ------------------------------------------------------------- urban
		"tile_cobblestone":
			# PROTOTYPE — Cobblestone: hand-cut faceted stones in a dark
			# seam bed, one moss clump growing in a joint. The audited
			# cobble field is exactly this language.
			_set_base(preset, {"top_key": "stone_deep",
				"bevel_key": "stone_medium", "side_key": "stone_medium",
				"lower_key": "stone_deep"}, "none", 0.0)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.34,
				"stone_cell_z": 0.27, "gap": 0.030, "stone_jitter": 0.09,
				"stone_height": [0.034, 0.055], "stone_profile": "faceted",
				"slab_key": "", "color_weights": {"stone_medium": 50.0,
					"stone_light": 50.0}})
			_scatter(preset, ["lobed_clump"], [1, 3], [0.08, 0.13],
				{"moss_clump": 100.0}, [0.012, 0.020])
			preset.separate_tiles = true
		"tile_proc_cobblestone_paving":
			_set_base(preset, {"top_key": "stone_deep",
				"bevel_key": "stone_medium", "side_key": "stone_medium",
				"lower_key": "stone_deep"}, "none", 0.0)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.55,
				"stone_cell_z": 0.42, "gap": 0.026, "stone_jitter": 0.06,
				"stone_height": [0.026, 0.038], "stone_corner": 0.05,
				"stone_profile": "cushion", "slab_key": "stone_light"})
			preset.separate_tiles = true
		"tile_master_pavers":
			_set_base(preset, STONE_BASE, "pillow", 0.012)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.36,
				"stone_cell_z": 0.22, "gap": 0.018, "stone_jitter": 0.08,
				"stone_height": [0.024, 0.040], "stone_corner": 0.03,
				"slab_key": "stone_light", "slab_key_alt": "stone_medium"})
			_scatter(preset, ["stone_chip", "lobed_clump"], [3, 5],
				[0.06, 0.11], {"stone_deep": 55.0, "moss_clump": 45.0},
				[0.010, 0.018])
			preset.separate_tiles = true
		"tile_proc_concrete_slabs":
			_set_base(preset, {"top_key": "stone_deep",
				"bevel_key": "stone_medium", "side_key": "stone_medium",
				"lower_key": "stone_deep"}, "none", 0.0)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.83,
				"stone_cell_z": 0.83, "gap": 0.020, "stone_corner": 0.030,
				"stone_jitter": 0.015, "stone_height": [0.020, 0.026],
				"slab_key": "stone_light"})
			preset.separate_tiles = true
		"tile_concrete_brutalist":
			_set_base(preset, STONE_BASE, "none", 0.0)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.82,
				"stone_cell_z": 0.82, "gap": 0.05, "stone_jitter": 0.0,
				"stone_height": [0.036, 0.046], "stone_corner": 0.015,
				"slab_key": "stone_medium"})
			_scatter(preset, ["stone_chip"], [1, 3], [0.06, 0.11],
				{"stone_light": 35.0, "stone_deep": 65.0}, [0.008, 0.014])
			preset.separate_tiles = true
		"tile_flagstone":
			_set_base(preset, STONE_BASE, "pillow", 0.010)
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.61,
				"stone_cell_z": 0.43, "gap": 0.032, "stone_jitter": 0.12,
				"stone_height": [0.022, 0.036], "stone_corner": 0.055,
				"slab_key": "", "color_weights": {"stone_light": 66.0,
					"stone_medium": 34.0}})
			_scatter(preset, ["lobed_clump", "leaf_litter"], [3, 5],
				[0.07, 0.12], {"moss_clump": 85.0, "autumn_amber": 15.0},
				[0.012, 0.022])
			preset.separate_tiles = true
		"tile_proc_gravel_yard":
			_set_base(preset, STONE_BASE, "pillow", 0.014,
				{"relief_frequency": 3.0})
			_scatter(preset, ["pebble", "pebble", "stone_chip"], [12, 16],
				[0.10, 0.17],
				{"stone_light": 45.0, "stone_medium": 35.0, "stone_deep": 20.0},
				[0.014, 0.028],
				{"min_spacing": 0.055, "cluster_fraction": 0.8,
					"cluster_radius": 0.28})

		# ------------------------------------------------------------- ruins
		"tile_proc_boulder_ground":
			# One or two hero rocks whose silhouette reads at any distance.
			_set_base(preset, MOSS_BASE, "pillow", 0.018)
			_turf(preset, {"turf_spacing": 0.31, "turf_footprint": [0.20, 0.30],
				"turf_height": [0.024, 0.040], "turf_skip_fraction": 0.34,
				"blade_fraction": 0.24, "primary_key": "moss_top", "blade_key": "moss_deep",
				"secondary_key": "moss_clump"})
			_scatter(preset, ["boulder", "pebble"], [3, 5], [0.26, 0.46],
				{"stone_light": 40.0, "stone_medium": 45.0, "stone_deep": 15.0},
				[0.030, 0.070], {"min_spacing": 0.24})
		"tile_stone_clearing":
			_set_base(preset, STONE_BASE, "heaps", 0.028,
				{"relief_heap_count": [4, 7], "relief_heap_radius": [0.12, 0.25],
					"relief_resolution": 30})
			_turf(preset, {"turf_spacing": 0.36, "turf_footprint": [0.16, 0.24],
				"turf_height": [0.020, 0.034], "turf_skip_fraction": 0.55,
				"blade_fraction": 0.30, "accent_clumps": [0, 1],
				"primary_key": "moss_top", "blade_key": "moss_deep", "secondary_key": "moss_clump"})
			_scatter(preset, ["pebble", "stone_chip", "lobed_clump"], [7, 10],
				[0.07, 0.15],
				{"stone_light": 35.0, "stone_deep": 40.0, "moss_clump": 25.0},
				[0.012, 0.024])
		"tile_stone_crystal":
			# One strong focal cluster, supported by quiet terrain forms.
			_set_base(preset, STONE_BASE, "heaps", 0.030,
				{"relief_heap_count": [3, 6], "relief_heap_radius": [0.14, 0.26],
					"relief_resolution": 30})
			_scatter(preset, ["crystal", "crystal", "pebble"], [5, 7],
				[0.18, 0.30],
				{"water_blue": 45.0, "water_light": 25.0, "blossom_cream": 30.0},
				[0.050, 0.100],
				{"cluster_fraction": 1.0, "cluster_radius": 0.14,
					"min_spacing": 0.08})
		"tile_stone_mossy":
			# Moss takes the stone by GROWING over it: turf masses ride the
			# pillowed stone, the grey showing through in worn gaps.
			_set_base(preset, STONE_BASE, "pillow", 0.024)
			_turf(preset, {"turf_spacing": 0.28, "turf_footprint": [0.22, 0.34],
				"turf_height": [0.026, 0.044], "turf_skip_fraction": 0.26,
				"blade_fraction": 0.22, "primary_key": "moss_top", "blade_key": "moss_deep",
				"secondary_key": "moss_clump"})
			_scatter(preset, ["lobed_clump", "nub", "pebble"], [5, 8],
				[0.08, 0.14], {"moss_clump": 65.0, "stone_deep": 35.0},
				[0.014, 0.026])
		"tile_stone_road":
			_set_base(preset, STONE_BASE, "pillow", 0.015)
			_pavers(preset, {"pattern": "trail", "trail_layout": "straight",
				"trail_width": 0.76, "trail_piece_length": [0.24, 0.50],
				"trail_jitter": 0.10, "gap": 0.028,
				"stone_height": [0.020, 0.034], "stone_corner": 0.055,
				"slab_key": "stone_light", "slab_key_alt": "stone_medium"})
			_scatter(preset, ["stone_chip", "lobed_clump", "leaf_litter"],
				[5, 8], [0.07, 0.12],
				{"stone_deep": 45.0, "moss_clump": 40.0, "autumn_amber": 15.0},
				[0.010, 0.020])
			preset.separate_tiles = true
		"tile_stone_ruin":
			# Missing, cracked, displaced pieces in large readable arrangements.
			_set_base(preset, STONE_BASE, "heaps", 0.028,
				{"relief_heap_count": [3, 5], "relief_heap_radius": [0.16, 0.30],
					"relief_resolution": 30})
			_pavers(preset, {"pattern": "cobbles", "stone_cell": 0.62,
				"stone_cell_z": 0.55, "gap": 0.05, "stone_jitter": 0.14,
				"stone_height": [0.028, 0.052], "stone_corner": 0.04,
				"slab_key": "stone_medium", "slab_key_alt": "stone_light"})
			_fringe(preset, {"material_key": "stone_deep", "inset": 0.07,
				"width": 0.10, "height": 0.06, "pieces_per_edge": 6,
				"jitter": 0.32})
			_scatter(preset, ["boulder", "stone_chip", "lobed_clump"], [4, 7],
				[0.12, 0.26], {"stone_deep": 60.0, "moss_clump": 40.0},
				[0.025, 0.060])
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


## A clean four-layer starting stack built from schema defaults — never from
## a stored recipe, so re-running this script always re-derives geometry from
## the code below rather than echoing whatever was on disk.
func _fresh_preset() -> TileKitPreset:
	var preset := TileKitPreset.new()
	var base := TileLayerParameterSchema.new_layer("base")
	base.params.merge({
		"top_bevel": 0.075, "corner_radius": 0.075, "bevel_segments": 6,
		"bottom_chamfer": 0.016,
	}, true)
	var dressing := TileLayerParameterSchema.new_layer("dressing")
	dressing.enabled = false
	var clutter := TileLayerParameterSchema.new_layer("clutter")
	clutter.enabled = false
	var grass := TileLayerParameterSchema.new_layer("grass_clusters")
	grass.enabled = false
	preset.layers = [base, dressing, clutter, grass]
	return preset


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


## The sculpted-turf grass carpet — the kit's premium organic surface.
func _turf(preset: TileKitPreset, params: Dictionary) -> void:
	var merged := {"coverage_mode": "turf"}
	merged.merge(params, true)
	_enable(preset, "grass_clusters", merged)


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
	if base != null and float(base.value("basin_depth", 0.0)) > 0.001:
		return true
	for layer in preset.layers:
		if layer.enabled and layer.kind != "base":
			return true
	return false
