@tool
class_name TileKitPreset
extends Resource
## A complete Tile Kit tile: master seed plus an ordered stack of layers.
##
## The preset is the unit of saving, loading, and baking. Identical preset →
## identical geometry, always: every random decision anywhere in the kit
## derives from `master_seed` and the layers' own offsets.

@export var preset_name := "Untitled Tile"
@export var master_seed := 20260801
## Keep each cell's authored rim even when the next cell uses this same preset.
## Organic ground normally leaves this off so neighbouring cells fuse into one
## land mass; constructed paving turns it on so its block-to-block cadence
## remains visible.
@export var separate_tiles := false
@export var layers: Array[TileKitLayer] = []

const OFFICIAL_RECIPE_DIRECTORY := "res://tools/tile_kit/library/recipes"
const OFFICIAL_RECIPES := [
	["Emberbaked Loam", "tile_clay"],
	["Bramblegate Cobbles", "tile_cobblestone"],
	["Monolith Garden", "tile_concrete_brutalist"],
	["Sunwell Court", "tile_courtyard"],
	["Rootrest Earth", "tile_dirt"],
	["Wayfarer Crossing", "tile_dirt_crossroad"],
	["Wrenfoot Lane", "tile_dirt_road"],
	["Timeworn Stepping", "tile_flagstone"],
	["Rimeglass Stone", "tile_frosted_stone"],
	["Tended Loam", "tile_garden"],
	["Cloverlight Meadow", "tile_grass"],
	["Buttercup Gleam", "tile_grass_flower"],
	["Reedwhisper Bank", "tile_grass_pond_edge"],
	["Coppercanopy Floor", "tile_grove_autumn"],
	["Silverbark Floor", "tile_grove_birch"],
	["Petalbloom Grove", "tile_grove_flowering"],
	["Elder Canopy", "tile_grove_mature"],
	["Velvetroot Moss", "tile_grove_mossy"],
	["Springleaf Carpet", "tile_kit_grass"],
	["Tile Forge: Verdant Master", "tile_master_grass"],
	["Tile Forge: Masonry Master", "tile_master_pavers"],
	["Tile Forge: Timber Master", "tile_master_wood"],
	["Rainpool Loam", "tile_mud"],
	["Starling Mere", "tile_open_water"],
	["Moonpebble Walk", "tile_path"],
	["Porcelain Seedbed", "tile_plain_ground"],
	["Copperfall Litter", "tile_proc_autumn_litter"],
	["Stonekin Scatter", "tile_proc_boulder_ground"],
	["Hearthbrick Court", "tile_proc_brick_court"],
	["Dapplecheck Slabs", "tile_proc_checker_slabs"],
	["Acornset Paving", "tile_proc_cobblestone_paving"],
	["Cloudstone Slabs", "tile_proc_concrete_slabs"],
	["Wrenrail Paddock", "tile_proc_fenced_meadow"],
	["Petalwink Meadow", "tile_proc_flower_meadow"],
	["Pebblethread Path", "tile_proc_garden_path"],
	["Finchstone Yard", "tile_proc_gravel_yard"],
	["Mosswhisper Floor", "tile_proc_mossy_forest_floor"],
	["Rainroot Bed", "tile_proc_mud_bed"],
	["Cedarcrumb Bed", "tile_proc_mulch_dirt_floor"],
	["Lilypad Hollow", "tile_proc_pond_basin"],
	["Honeywind Dunes", "tile_proc_sand_dunes_study"],
	["Sunmote Sand", "tile_proc_sandy_ground"],
	["Windhush Drifts", "tile_proc_snow_drifts_study"],
	["Hushsnow Blanket", "tile_proc_snow_field"],
	["Furrowglow Plot", "tile_proc_tilled_field"],
	["Ambergrain Decking", "tile_proc_wood_plank_deck"],
	["Saffronwind Sand", "tile_sand"],
	["Pillowdrift Snow", "tile_snow_drift"],
	["Hearthstep Snowpath", "tile_snow_path"],
	["Hushfall Field", "tile_snowfield"],
	["Lichenrest Clearing", "tile_stone_clearing"],
	["Glimmervein Ground", "tile_stone_crystal"],
	["Fernbound Stone", "tile_stone_mossy"],
	["Relicway Stone", "tile_stone_road"],
	["Hearthruin Foundation", "tile_stone_ruin"],
	["Sunkissed Boardwalk", "tile_wooden_planks"],
]


func layer_of_kind(kind: String) -> TileKitLayer:
	for layer in layers:
		if layer.kind == kind:
			return layer
	return null


func duplicate_preset() -> TileKitPreset:
	var copy := TileKitPreset.new()
	copy.preset_name = preset_name
	copy.master_seed = master_seed
	copy.separate_tiles = separate_tiles
	for layer in layers:
		copy.layers.append(layer.duplicate_layer())
	return copy


## Compatibility view of the official recipe library. Names are no longer the
## source of truth; every entry resolves to a project .tres below.
static func built_in_names() -> Array[String]:
	var result: Array[String] = []
	for entry: Array in OFFICIAL_RECIPES:
		result.append(String(entry[0]))
	return result


static func make_built_in(preset_name: String) -> TileKitPreset:
	for entry: Array in OFFICIAL_RECIPES:
		if String(entry[0]) == preset_name:
			var official := official_recipe(String(entry[1]))
			if official != null:
				return official
	return reference_clean_grass()


static func official_recipe(tile_id: String) -> TileKitPreset:
	var path := "%s/%s.tres" % [OFFICIAL_RECIPE_DIRECTORY, tile_id]
	if not ResourceLoader.exists(path):
		return null
	var loaded := ResourceLoader.load(
		path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as TileKitPreset
	return loaded.duplicate_preset() if loaded != null else null


## The built-in reference preset: the approved single-tile grass look, minus
## flowers. Values are authored against the 1.70 m catalog footprint (the
## reference tile was described against 2.0 m; horizontal figures are scaled
## by 0.85, verticals kept in the same visual proportion).
static func reference_clean_grass() -> TileKitPreset:
	var official := official_recipe("tile_kit_grass")
	if official != null:
		return official
	var preset := TileKitPreset.new()
	preset.preset_name = "Reference Clean Grass"
	preset.master_seed = 20260801

	var base := TileKitLayer.new("base", {
		"top_bevel": 0.075,
		"corner_radius": 0.075,
		"bevel_segments": 6,
		"bottom_chamfer": 0.016,
	})
	base.locked = true

	var dressing := TileKitLayer.new("dressing", {
		# The clay-reference tops are clean; dressing stays available as a
		# brick but ships disabled for this preset.
		"large_count": [3, 5],
		"medium_count": [4, 7],
		"small_count": [2, 5],
		"large_radius": [0.17, 0.29],
		"medium_radius": [0.094, 0.17],
		"small_radius": [0.047, 0.094],
		"aspect": [0.70, 1.35],
		"irregularity": [0.08, 0.14],
		"smoothing_passes": 3,
		"outline_points": 20,
		"region_count": [2, 3],
		"region_spread": 0.30,
		"edge_margin": 0.02,
		"scale_multiplier": 1.0,
		"color_weights": {
			"dressing_light": 50.0,
			"dressing_medium": 35.0,
			"dressing_dark": 15.0,
		},
	})

	var clutter := TileKitLayer.new("clutter", {
		"count": [3, 6],
		"diameter": [0.05, 0.11],
		"height": [0.008, 0.018],
		"min_spacing": 0.06,
		"edge_margin": 0.03,
		"on_dressing_fraction": 0.6,
		"scale_multiplier": 1.0,
		"color_weights": {
			"clutter_light": 55.0,
			"clutter_medium": 45.0,
		},
	})

	var grass := TileKitLayer.new("grass_clusters", {
		"coverage_mode": "carpet",
		"carpet_spacing": 0.315,
		"carpet_jitter": 0.30,
		"carpet_skip_fraction": 0.10,
		"rosette_footprint": [0.14, 0.20],
		"rosette_leaves": [3, 5],
		"leaf_height": [0.095, 0.150],
		"leaf_width": [0.058, 0.088],
		"splay_degrees": [16.0, 34.0],
		"thickness_ratio": [0.55, 0.72],
		"crown_radius": 0.020,
		"bend_multiplier": 0.75,
		"height_multiplier": 1.0,
		"width_multiplier": 1.0,
		"edge_margin": 0.02,
		"root_sink": [0.008, 0.015],
		"secondary_fraction": 0.2,
	})

	dressing.enabled = false
	clutter.enabled = false
	preset.layers = [base, dressing, clutter, grass]
	return preset


## Deep-green moss carpet over earth sides: sparse squat sprouts, mossy
## clumps, twigs, and the odd mushroom — the forest-floor family from the
## tile research, in the same clay register as the grass reference.
static func mossy_forest_floor() -> TileKitPreset:
	var official := official_recipe("tile_proc_mossy_forest_floor")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Mossy Forest Floor"
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"top_key": "moss_top", "bevel_key": "moss_bevel",
		"side_key": "earth_side", "lower_key": "earth_deep",
	}, true)
	base.params.merge({
		"relief_style": "pillow",
		"relief_amplitude": 0.026,
		"relief_frequency": 2.0,
	}, true)
	preset.layer_of_kind("dressing").enabled = false
	var clutter := preset.layer_of_kind("clutter")
	clutter.enabled = true
	clutter.params.merge({
		"count": [7, 11],
		"shapes": ["lobed_clump", "nub", "twig", "mushroom", "leaf_litter"],
		"color_weights": {"moss_clump": 45.0, "moss_deep": 25.0,
			"wood_medium": 30.0},
		"mushroom_cap_key": "accent_terracotta",
		"diameter": [0.060, 0.130],
	}, true)
	var grass := preset.layer_of_kind("grass_clusters")
	grass.params.merge({
		"carpet_spacing": 0.36,
		"carpet_skip_fraction": 0.30,
		"leaf_height": [0.06, 0.10],
		"primary_key": "moss_clump",
		"secondary_key": "moss_deep",
	}, true)
	return preset

## Warm earth bed under wood-chip mulch, pebbles, and twigs. No grass at all —
## the scatter IS the identity, straight from the dirt/mulch reference tiles.
static func mulch_dirt_floor() -> TileKitPreset:
	var official := official_recipe("tile_proc_mulch_dirt_floor")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Mulch Dirt Floor"
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"top_key": "earth_top", "bevel_key": "earth_bevel",
		"side_key": "earth_side", "lower_key": "earth_deep",
	}, true)
	base.params.merge({
		"relief_style": "pillow",
		"relief_amplitude": 0.024,
		"relief_frequency": 2.3,
	}, true)
	preset.layer_of_kind("dressing").enabled = false
	var clutter := preset.layer_of_kind("clutter")
	clutter.enabled = true
	clutter.params.merge({
		"count": [12, 18],
		"min_spacing": 0.07,
		"shapes": ["wood_chip", "wood_chip", "twig", "pebble", "mushroom"],
		"color_weights": {"wood_light": 35.0, "wood_medium": 35.0,
			"wood_deep": 20.0, "stone_medium": 10.0},
		"mushroom_cap_key": "accent_cream",
		"diameter": [0.065, 0.150],
		"height": [0.012, 0.024],
	}, true)
	preset.layer_of_kind("grass_clusters").enabled = false
	return preset


## Soft warm-white blanket with low settled lumps. Quietest preset in the
## kit: the snow family carries almost everything through the shell colours.
static func snow_field() -> TileKitPreset:
	var official := official_recipe("tile_proc_snow_field")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Snow Field"
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"top_key": "snow_top", "bevel_key": "snow_bevel",
		"side_key": "snow_side", "lower_key": "stone_deep",
		# The whole identity is the sculpt: one white, pillowed into soft
		# drifts like the reference snow block. No lumps sitting ON the
		# surface — the surface IS the softness.
		# Wind-blown drifts: broad directional waves, no discrete piles —
		# the smooth white block of the clay reference.
		"relief_style": "dunes",
		"relief_amplitude": 0.075,
		"relief_frequency": 1.1,
		"relief_resolution": 30,
	}, true)
	preset.layer_of_kind("clutter").enabled = false
	preset.layer_of_kind("grass_clusters").enabled = false
	return preset

## A preserved duplicate of Snow Field for judging the new procedural dune
## sculpt against the shipped source-derived snow. The original preset remains
## untouched until the study has earned its place.
static func snow_drift_study() -> TileKitPreset:
	var official := official_recipe("tile_proc_snow_drifts_study")
	if official != null:
		return official
	var preset := snow_field()
	preset.preset_name = "Snow Drifts (Study)"
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"relief_style": "sculpted_dunes",
		# The shipped snow surface has a measured 10.5 cm relief range and a
		# broad, highly polished silhouette.
		"relief_amplitude": 0.105,
		# The editor permits three times the shipped strength; extra samples keep
		# that dramatic end smooth instead of revealing the heightfield facets.
		"relief_resolution": 64,
		"relief_edge_feather": 0.30,
		"dune_scale": 0.92,
		"dune_amount": 0.68,
		"dune_softness": 0.88,
		"dune_irregularity": 0.52,
		"dune_lee_depth": 0.16,
		"dune_direction_degrees": 322.0,
		"dune_height_exponent": 0.92,
		"dune_seed_offset": 0,
	}, true)
	return preset


## Pale dune block with drifted patches and sparse pebbles — the sand family.
## Patches never merge: overlapping sand rings read as water stains.
static func sandy_ground() -> TileKitPreset:
	var official := official_recipe("tile_proc_sandy_ground")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Sandy Ground"
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"top_key": "sand_top", "bevel_key": "sand_bevel",
		"side_key": "sand_side", "lower_key": "sand_deep",
	}, true)
	base.params.merge({
		"relief_style": "dunes",
		"relief_amplitude": 0.048,
		"relief_frequency": 1.8,
		"relief_resolution": 24,
	}, true)
	preset.layer_of_kind("dressing").enabled = false
	var clutter := preset.layer_of_kind("clutter")
	clutter.enabled = true
	clutter.params.merge({
		"count": [4, 7],
		"shapes": ["pebble", "dot", "oval"],
		"color_weights": {"stone_light": 55.0, "sand_side": 45.0},
		"diameter": [0.055, 0.110],
	}, true)
	preset.layer_of_kind("grass_clusters").enabled = false
	return preset


## A preserved duplicate of Sandy Ground using staggered asymmetric wind
## strokes instead of the legacy sine/noise dunes. Tuned to the shipped sand's
## measured six-centimetre relief, with every shaping axis exposed in the UI.
static func sand_dune_study() -> TileKitPreset:
	var official := official_recipe("tile_proc_sand_dunes_study")
	if official != null:
		return official
	var preset := sandy_ground()
	preset.preset_name = "Sand Dunes (Study)"
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"relief_style": "sculpted_dunes",
		"relief_amplitude": 0.060,
		"relief_resolution": 64,
		"relief_edge_feather": 0.27,
		"dune_scale": 0.70,
		"dune_amount": 0.48,
		"dune_softness": 0.68,
		"dune_irregularity": 0.72,
		"dune_lee_depth": 0.34,
		"dune_direction_degrees": 318.0,
		"dune_height_exponent": 1.10,
		"dune_seed_offset": 0,
	}, true)
	return preset


## Dark damp earth with separated wet patches and settled nubs.
static func mud_bed() -> TileKitPreset:
	var official := official_recipe("tile_proc_mud_bed")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Mud Bed"
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"top_key": "mud_top", "bevel_key": "mud_bevel",
		"side_key": "earth_side", "lower_key": "earth_deep",
	}, true)
	base.params.merge({
		# Churned wet ground: bipolar noise digs troughs and pushes ridges
		# around the walk plane — mud, not moundland.
		"relief_style": "pillow",
		"relief_bipolar": true,
		"relief_amplitude": 0.034,
		"relief_frequency": 2.6,
		"relief_resolution": 26,
	}, true)
	preset.layer_of_kind("dressing").enabled = false
	var clutter := preset.layer_of_kind("clutter")
	clutter.enabled = true
	clutter.params.merge({
		"count": [3, 5],
		"shapes": ["nub", "pebble", "twig"],
		"color_weights": {"earth_clump": 60.0, "stone_medium": 40.0},
		"diameter": [0.060, 0.120],
	}, true)
	preset.layer_of_kind("grass_clusters").enabled = false
	return preset


## Rounded stone cobbles over a mortar-toned cap — the constructed paving
## family. The pavers brick does the work; everything else stays quiet.
static func cobblestone_paving() -> TileKitPreset:
	var official := official_recipe("tile_proc_cobblestone_paving")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Cobblestone Paving"
	preset.separate_tiles = true
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"top_key": "stone_deep", "bevel_key": "stone_medium",
		"side_key": "stone_medium", "lower_key": "stone_deep",
	}, true)
	preset.layer_of_kind("dressing").enabled = false
	preset.layer_of_kind("clutter").enabled = false
	preset.layer_of_kind("grass_clusters").enabled = false
	var pavers := TileKitLayer.new("pavers", {
		"pattern": "cobbles",
		"stone_cell": 0.55,
		"gap": 0.026,
		"stone_corner": 0.05,
		"stone_height": [0.024, 0.034],
		"slab_key": "stone_light",
	})
	preset.layers.append(pavers)
	return preset


## Long staggered boards over a shadowed cap — decking from the same brick
## as the cobbles, at a different aspect ratio.
static func wood_plank_deck() -> TileKitPreset:
	var official := official_recipe("tile_proc_wood_plank_deck")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Wood Plank Deck"
	preset.separate_tiles = true
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"top_key": "wood_deep", "bevel_key": "wood_medium",
		"side_key": "wood_medium", "lower_key": "wood_deep",
	}, true)
	preset.layer_of_kind("dressing").enabled = false
	preset.layer_of_kind("clutter").enabled = false
	preset.layer_of_kind("grass_clusters").enabled = false
	var pavers := TileKitLayer.new("pavers", {
		"pattern": "planks",
		"plank_width": 0.215,
		"gap": 0.022,
		"plank_length": [0.55, 0.95],
		"stone_corner": 0.024,
		"stone_height": [0.016, 0.024],
		"slab_key": "wood_medium",
	})
	preset.layers.append(pavers)
	return preset


## Four broad precast slabs per tile — the pale courtyard paving family.
## Crisp small corners, tight joints, one light stone colour.
static func concrete_slabs() -> TileKitPreset:
	var official := official_recipe("tile_proc_concrete_slabs")
	if official != null:
		return official
	var preset := cobblestone_paving()
	preset.preset_name = "Concrete Slabs"
	var pavers := preset.layer_of_kind("pavers")
	pavers.params.merge({
		"stone_cell": 0.83,
		"gap": 0.020,
		"stone_corner": 0.030,
		"stone_jitter": 0.015,
		"stone_height": [0.020, 0.026],
		"slab_key": "stone_light",
	}, true)
	return preset


## Terracotta running-bond bricks — the warm courtyard family.
static func brick_court() -> TileKitPreset:
	var official := official_recipe("tile_proc_brick_court")
	if official != null:
		return official
	var preset := cobblestone_paving()
	preset.preset_name = "Brick Court"
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"top_key": "brick_medium", "bevel_key": "brick_medium",
		"side_key": "brick_medium", "lower_key": "earth_deep",
	}, true)
	var pavers := preset.layer_of_kind("pavers")
	pavers.params.merge({
		"stone_cell": 0.31,
		"stone_cell_z": 0.16,
		"gap": 0.014,
		"stone_corner": 0.020,
		"stone_jitter": 0.03,
		"stone_height": [0.016, 0.022],
		"slab_key": "brick_light",
	}, true)
	return preset


## The grass tile with closed flower buds scattered through the carpet —
## floral colour without a single petal, so the clay language holds.
static func flower_meadow() -> TileKitPreset:
	var official := official_recipe("tile_proc_flower_meadow")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Flower Meadow"
	var grass := preset.layer_of_kind("grass_clusters")
	grass.params.merge({"carpet_spacing": 0.34,
		"carpet_skip_fraction": 0.14}, true)
	var clutter := preset.layer_of_kind("clutter")
	clutter.enabled = true
	clutter.params.merge({
		"count": [7, 11],
		"min_spacing": 0.16,
		"shapes": ["bud"],
		"color_weights": {"blossom_pink": 55.0, "blossom_cream": 30.0,
			"accent_terracotta": 15.0},
		"diameter": [0.105, 0.155],
		"height": [0.020, 0.030],
	}, true)
	return preset


## Stepping stones set INTO the grass carpet — the first hybrid preset: the
## pavers brick lays stones, and the grass layer reads them from context and
## grows around them.
static func garden_path() -> TileKitPreset:
	var official := official_recipe("tile_proc_garden_path")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Garden Path"
	preset.separate_tiles = true
	var stepping := TileKitLayer.new("pavers", {
		"pattern": "stepping",
		"stepping_count": [4, 6],
		"stepping_size": [0.26, 0.36],
		"stone_corner": 0.06,
		"stone_height": [0.022, 0.030],
		"slab_key": "stone_light",
	})
	# Order matters: stones must exist before the grass composes, so the
	# carpet can keep clear of them.
	var grass_index := preset.layers.find(preset.layer_of_kind("grass_clusters"))
	preset.layers.insert(grass_index, stepping)
	return preset


## Warm earth strewn with fallen leaves and twigs — the autumn forest floor.
static func autumn_litter() -> TileKitPreset:
	var official := official_recipe("tile_proc_autumn_litter")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Autumn Litter"
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"top_key": "earth_top", "bevel_key": "earth_bevel",
		"side_key": "earth_side", "lower_key": "earth_deep",
		"relief_style": "pillow",
		"relief_amplitude": 0.020,
		"relief_frequency": 2.2,
	}, true)
	var clutter := preset.layer_of_kind("clutter")
	clutter.enabled = true
	clutter.params.merge({
		"count": [12, 18],
		"min_spacing": 0.08,
		"shapes": ["leaf_litter", "leaf_litter", "leaf_litter", "twig",
			"mushroom"],
		"color_weights": {"autumn_amber": 45.0, "autumn_rust": 35.0,
			"wood_medium": 20.0},
		"mushroom_cap_key": "autumn_rust",
		"diameter": [0.075, 0.160],
	}, true)
	preset.layer_of_kind("grass_clusters").enabled = false
	return preset


## Dense grey pebble ground — the gravel courtyard.
static func gravel_yard() -> TileKitPreset:
	var official := official_recipe("tile_proc_gravel_yard")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Gravel Yard"
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"top_key": "stone_medium", "bevel_key": "stone_light",
		"side_key": "stone_deep", "lower_key": "stone_deep",
		"relief_style": "pillow",
		"relief_amplitude": 0.012,
		"relief_frequency": 3.0,
	}, true)
	var clutter := preset.layer_of_kind("clutter")
	clutter.enabled = true
	clutter.params.merge({
		"count": [14, 20],
		"min_spacing": 0.075,
		"shapes": ["pebble", "pebble", "stone_chip", "dot"],
		"color_weights": {"stone_light": 45.0, "stone_medium": 35.0,
			"stone_deep": 20.0},
		"diameter": [0.060, 0.120],
	}, true)
	preset.layer_of_kind("grass_clusters").enabled = false
	return preset


## Two-tone checkerboard slabs — the festival courtyard.
static func checker_slabs() -> TileKitPreset:
	var official := official_recipe("tile_proc_checker_slabs")
	if official != null:
		return official
	var preset := concrete_slabs()
	preset.preset_name = "Checker Slabs"
	var pavers := preset.layer_of_kind("pavers")
	pavers.params.merge({
		"slab_key": "stone_light",
		"slab_key_alt": "sand_top",
		"stone_jitter": 0.008,
	}, true)
	return preset


## The grass tile bordered by a low wooden rail fence — the paddock. First
## user of the schema's edge role.
static func fenced_meadow() -> TileKitPreset:
	var official := official_recipe("tile_proc_fenced_meadow")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Fenced Meadow"
	var grass := preset.layer_of_kind("grass_clusters")
	grass.params.merge({"edge_margin": 0.12}, true)
	preset.layers.append(TileKitLayer.new("fence", {
		"edges": [0, 1, 2, 3],
		"post_key": "wood_deep",
		"rail_key": "wood_medium",
	}))
	return preset


## A grass-rimmed pool with lily pads — the pond. The base's basin mode does
## the sculpt; water is a still plane; pads float on it.
static func pond_basin() -> TileKitPreset:
	var official := official_recipe("tile_proc_pond_basin")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Pond Basin"
	# A basin is a cell-sized authored object, not a continuous ground skin.
	# Keeping its rim also prevents connected-cap generation from replacing the
	# recessed pool sculpt when another basin sits beside it.
	preset.separate_tiles = true
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"basin_depth": 0.11,
		"basin_rim": 0.17,
		"water_key": "water_blue",
	}, true)
	preset.layer_of_kind("grass_clusters").enabled = false
	var clutter := preset.layer_of_kind("clutter")
	clutter.enabled = true
	clutter.params.merge({
		"count": [3, 5],
		"min_spacing": 0.16,
		"edge_margin": 0.30,
		"shapes": ["lily_pad"],
		"color_weights": {"lily_green": 100.0},
		"diameter": [0.14, 0.24],
	}, true)
	return preset


## Parallel tilled furrows in warm earth — the farm bed, pure sculpt.
static func tilled_field() -> TileKitPreset:
	var official := official_recipe("tile_proc_tilled_field")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Tilled Field"
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"top_key": "earth_top", "bevel_key": "earth_bevel",
		"side_key": "earth_side", "lower_key": "earth_deep",
		"relief_style": "furrows",
		"relief_amplitude": 0.034,
		"relief_rows": 5,
		"relief_resolution": 30,
	}, true)
	preset.layer_of_kind("grass_clusters").enabled = false
	return preset


## One or two hero rocks on mossy ground — the boulder outcrop whose
## silhouette reads at any distance.
static func boulder_ground() -> TileKitPreset:
	var official := official_recipe("tile_proc_boulder_ground")
	if official != null:
		return official
	var preset := reference_clean_grass()
	preset.preset_name = "Boulder Ground"
	var base := preset.layer_of_kind("base")
	base.params.merge({
		"top_key": "moss_top", "bevel_key": "moss_bevel",
		"side_key": "earth_side", "lower_key": "earth_deep",
		"relief_style": "pillow",
		"relief_amplitude": 0.018,
		"relief_frequency": 2.0,
	}, true)
	var grass := preset.layer_of_kind("grass_clusters")
	grass.params.merge({
		"carpet_spacing": 0.38,
		"carpet_skip_fraction": 0.35,
		"primary_key": "moss_clump",
		"secondary_key": "moss_deep",
	}, true)
	var clutter := preset.layer_of_kind("clutter")
	clutter.enabled = true
	clutter.params.merge({
		"count": [4, 6],
		"min_spacing": 0.22,
		"shapes": ["boulder", "pebble", "pebble"],
		"color_weights": {"stone_light": 40.0, "stone_medium": 45.0,
			"stone_deep": 15.0},
		"diameter": [0.24, 0.44],
		"height": [0.03, 0.07],
	}, true)
	return preset

