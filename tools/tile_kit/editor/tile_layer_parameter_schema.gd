@tool
class_name TileLayerParameterSchema
extends RefCounted
## Declarative authoring schema for every reusable Tile Kit capability.
##
## Builders remain the source of geometry. This schema only describes their
## public authoring surface, so the inspector can be generated from data rather
## than accumulating one-off controls for Sand, Snow, Leaves, and every future
## tile. A new builder becomes editor-ready by adding one definition here.

const KIND_ORDER := [
	"base", "liquid", "dressing", "pavers", "clutter", "grass_clusters",
	"fringe", "fence",
]

const SHAPES := [
	"dot", "oval", "leaf_pair", "lobed_clump", "nub", "clod", "rock",
	"pebble", "stone_chip", "twig", "wood_chip", "leaf_litter", "mushroom",
	"snow_lump", "drift_mound", "bud", "boulder", "lily_pad", "crystal",
	"footprint",
]

const DEFINITIONS := {
	"base": {
		"label": "Foundation & Relief",
		"description": "Structural block, terrain relief, basins, and water.",
		"defaults": {
			"top_bevel": 0.075,
			"corner_radius": 0.075,
			"turf_cap": false,
			"turf_thickness": 0.078,
			"turf_wobble": 0.013,
			"relief_style": "none",
			"relief_amplitude": 0.0,
			"relief_frequency": 2.2,
			"relief_resolution": 18,
			"relief_edge_feather": 0.16,
			"relief_bipolar": false,
			"basin_depth": 0.0,
			"basin_rim": 0.17,
		},
		"parameters": [
			{"section": "BLOCK PROFILE", "key": "top_bevel", "label": "Top bevel",
				"type": "float", "min": 0.015, "max": 0.16, "step": 0.005},
			{"key": "corner_radius", "label": "Corner roundness", "type": "float",
				"min": 0.0, "max": 0.18, "step": 0.005},
			{"key": "turf_cap", "label": "Turf cap over soil", "type": "bool",
				"randomize": false},
			{"key": "turf_thickness", "label": "Turf thickness", "type": "float",
				"min": 0.04, "max": 0.12, "step": 0.002,
				"when": {"turf_cap": [true]}},
			{"key": "turf_wobble", "label": "Turf edge wobble", "type": "float",
				"min": 0.0, "max": 0.03, "step": 0.001,
				"when": {"turf_cap": [true]}},
			{"section": "SURFACE RELIEF", "key": "relief_style", "label": "Relief style",
				"type": "enum", "values": ["none", "pillow", "dunes",
					"sculpted_dunes", "heaps", "furrows"], "randomize": false},
			{"key": "relief_amplitude", "label": "Relief amount", "type": "float",
				"min": 0.0, "max": 0.20, "step": 0.005,
				"when": {"relief_style": ["pillow", "dunes", "sculpted_dunes", "heaps", "furrows"]}},
			{"key": "relief_frequency", "label": "Relief scale", "type": "float",
				"min": 0.35, "max": 6.0, "step": 0.05,
				"when": {"relief_style": ["pillow", "dunes"]}},
			{"key": "relief_resolution", "label": "Surface detail", "type": "int",
				"min": 12, "max": 64, "step": 2,
				"when": {"relief_style": ["pillow", "dunes", "sculpted_dunes", "heaps", "furrows"]}},
			{"key": "relief_edge_feather", "label": "Edge blend", "type": "float",
				"min": 0.02, "max": 0.40, "step": 0.01,
				"when": {"relief_style": ["pillow", "dunes", "sculpted_dunes", "heaps", "furrows"]}},
			{"key": "relief_bipolar", "label": "Carve troughs and ridges", "type": "bool",
				"when": {"relief_style": ["pillow", "dunes"]}},
			{"key": "relief_heap_count", "label": "Heap amount", "type": "range_int",
				"min": 1, "max": 12, "step": 1, "fallback": [4, 6],
				"when": {"relief_style": ["heaps"]}},
			{"key": "relief_heap_radius", "label": "Heap size", "type": "range_float",
				"min": 0.08, "max": 0.46, "step": 0.01, "fallback": [0.16, 0.28],
				"when": {"relief_style": ["heaps"]}},
			{"key": "relief_rows", "label": "Furrow amount", "type": "int",
				"min": 2, "max": 12, "step": 1, "when": {"relief_style": ["furrows"]}},
			{"key": "relief_axis", "label": "Furrow direction", "type": "enum",
				"values": [0, 1], "value_labels": ["East / west", "North / south"],
				"when": {"relief_style": ["furrows"]}},
			{"section": "SCULPTED DUNES", "key": "dune_scale", "label": "Dune scale",
				"type": "float", "min": 0.35, "max": 1.25, "step": 0.01,
				"when": {"relief_style": ["sculpted_dunes"]}},
			{"key": "dune_amount", "label": "Dune amount", "type": "float",
				"min": 0.0, "max": 1.0, "step": 0.01,
				"when": {"relief_style": ["sculpted_dunes"]}},
			{"key": "dune_softness", "label": "Dune softness", "type": "float",
				"min": 0.0, "max": 1.0, "step": 0.01,
				"when": {"relief_style": ["sculpted_dunes"]}},
			{"key": "dune_irregularity", "label": "Irregularity", "type": "float",
				"min": 0.0, "max": 1.0, "step": 0.01,
				"when": {"relief_style": ["sculpted_dunes"]}},
			{"key": "dune_lee_depth", "label": "Lee shoulder", "type": "float",
				"min": 0.0, "max": 1.0, "step": 0.01,
				"when": {"relief_style": ["sculpted_dunes"]}},
			{"key": "dune_direction_degrees", "label": "Wind direction", "type": "float",
				"min": 0.0, "max": 360.0, "step": 1.0,
				"when": {"relief_style": ["sculpted_dunes"]}},
			{"section": "BASIN & WATER", "key": "basin_depth", "label": "Basin depth",
				"type": "float", "min": 0.0, "max": 0.30, "step": 0.01},
			{"key": "basin_rim", "label": "Basin rim", "type": "float",
				"min": 0.08, "max": 0.38, "step": 0.01,
				"when_number": {"basin_depth": 0.001}},
		],
	},
	"dressing": {
		"label": "Surface Patches",
		"description": "Soft raised cushions or flat sheens: moss, snow pillows, soil beds, wet marks.",
		"defaults": {"large_count": [2, 4], "medium_count": [3, 6],
			"small_count": [2, 5], "scale_multiplier": 1.0, "allow_overlap": true,
			"patch_profile": "cushion", "height_scale": 1.0, "edge_softness": 0.55},
		"parameters": [
			{"section": "PATCH FORM", "key": "patch_profile", "label": "Patch form",
				"type": "enum", "values": ["cushion", "sheen"],
				"value_labels": ["Raised cushion", "Flat sheen"], "randomize": false},
			{"key": "height_scale", "label": "Cushion height", "type": "float",
				"min": 0.0, "max": 2.0, "step": 0.01,
				"when": {"patch_profile": ["cushion"]}},
			{"key": "edge_softness", "label": "Edge roll", "type": "float",
				"min": 0.0, "max": 1.0, "step": 0.01,
				"when": {"patch_profile": ["cushion"]}},
			{"section": "PATCH COMPOSITION", "key": "large_count", "label": "Large amount",
				"type": "range_int", "min": 0, "max": 16, "step": 1, "fallback": [2, 4]},
			{"key": "medium_count", "label": "Medium amount", "type": "range_int",
				"min": 0, "max": 24, "step": 1, "fallback": [3, 6]},
			{"key": "small_count", "label": "Small amount", "type": "range_int",
				"min": 0, "max": 32, "step": 1, "fallback": [2, 5]},
			{"key": "scale_multiplier", "label": "Patch size", "type": "float",
				"min": 0.25, "max": 2.0, "step": 0.01},
			{"key": "region_count", "label": "Region amount", "type": "range_int",
				"min": 1, "max": 10, "step": 1, "fallback": [2, 3]},
			{"key": "region_spread", "label": "Region spread", "type": "float",
				"min": 0.02, "max": 0.70, "step": 0.01},
			{"key": "irregularity", "label": "Edge irregularity", "type": "range_float",
				"min": 0.0, "max": 0.45, "step": 0.01, "fallback": [0.08, 0.14]},
			{"key": "allow_overlap", "label": "Patches may overlap", "type": "bool"},
		],
	},
	"clutter": {
		"label": "Surface Scatter",
		"description": "A generic distribution of leaves, chips, stones, flowers, crystals, imprints, or lumps.",
		"defaults": {"count": [7, 13], "diameter": [0.05, 0.11],
			"height": [0.008, 0.018], "min_spacing": 0.06,
			"edge_margin": 0.03, "on_dressing_fraction": 0.0,
			"scale_multiplier": 1.0, "shapes": ["pebble"],
			"placement_mode": "clusters", "cluster_fraction": 0.7,
			"cluster_radius": 0.24},
		"parameters": [
			{"section": "SCATTER CONTENT", "key": "shapes", "label": "Piece types",
				"type": "multi", "values": SHAPES, "randomize": false},
			{"section": "DISTRIBUTION", "key": "placement_mode", "label": "Placement",
				"type": "enum", "values": ["clusters", "drift"],
				"value_labels": ["Clustered groups", "Raked drifts"],
				"randomize": false},
			{"key": "cluster_fraction", "label": "Grouping strength", "type": "float",
				"min": 0.0, "max": 1.0, "step": 0.01,
				"when": {"placement_mode": ["clusters"]}},
			{"key": "cluster_radius", "label": "Group radius", "type": "float",
				"min": 0.08, "max": 0.55, "step": 0.01,
				"when": {"placement_mode": ["clusters"]}},
			{"key": "count", "label": "Amount",
				"type": "range_int", "min": 0, "max": 80, "step": 1,
				"fallback": [7, 13]},
			{"key": "diameter", "label": "Piece size", "type": "range_float",
				"min": 0.015, "max": 0.32, "step": 0.005, "fallback": [0.05, 0.11]},
			{"key": "height", "label": "Piece height", "type": "range_float",
				"min": 0.003, "max": 0.12, "step": 0.003, "fallback": [0.008, 0.018]},
			{"key": "min_spacing", "label": "Minimum spacing", "type": "float",
				"min": 0.0, "max": 0.32, "step": 0.005},
			{"key": "edge_margin", "label": "Edge margin", "type": "float",
				"min": 0.0, "max": 0.30, "step": 0.005},
			{"key": "on_dressing_fraction", "label": "Patch attraction", "type": "float",
				"min": 0.0, "max": 1.0, "step": 0.01},
			{"key": "scale_multiplier", "label": "Overall scale", "type": "float",
				"min": 0.25, "max": 2.5, "step": 0.01},
		],
	},
	"grass_clusters": {
		"label": "Organic Carpet",
		"description": "Repeated sprouts or sparse feature clusters.",
		"defaults": {"coverage_mode": "tufts", "tuft_scale": 1.0,
			"mass_scale": 1.0, "mass_height": [0.026, 0.042],
			"tuft_lean": 0.55, "extra_tufts": [0, 1],
			"carpet_spacing": 0.315,
			"carpet_jitter": 0.30, "carpet_skip_fraction": 0.10,
			"rosette_footprint": [0.14, 0.20], "rosette_leaves": [3, 5],
			"leaf_height": [0.095, 0.15], "leaf_width": [0.058, 0.088],
			"turf_spacing": 0.26, "turf_footprint": [0.22, 0.34],
			"turf_height": [0.030, 0.055], "turf_skip_fraction": 0.10,
			"turf_lobe_depth": 0.20, "turf_overhang": 0.035,
			"blade_fraction": 0.42, "blades_per_tuft": [2, 4],
			"accent_clumps": [1, 2]},
		"parameters": [
			{"section": "CARPET MODE", "key": "coverage_mode", "label": "Composition",
				"type": "enum",
				"values": ["gold_grass", "tufts", "turf", "carpet", "clusters"],
				"randomize": false},
			{"section": "TUFT COMPOSITION", "key": "tuft_scale",
				"label": "Tuft size", "type": "float", "min": 0.5, "max": 2.0,
				"step": 0.01, "when": {"coverage_mode": ["tufts"]}},
			{"key": "mass_scale", "label": "Turf mass size", "type": "float",
				"min": 0.4, "max": 1.6, "step": 0.01,
				"when": {"coverage_mode": ["tufts"]}},
			{"key": "mass_height", "label": "Turf mass height",
				"type": "range_float", "min": 0.008, "max": 0.09,
				"step": 0.002, "fallback": [0.026, 0.042],
				"when": {"coverage_mode": ["tufts"]}},
			{"key": "tuft_lean", "label": "Wind lean", "type": "float",
				"min": 0.0, "max": 1.2, "step": 0.01,
				"when": {"coverage_mode": ["tufts"]}},
			{"key": "extra_tufts", "label": "Stray tufts", "type": "range_int",
				"min": 0, "max": 4, "step": 1, "fallback": [0, 1],
				"when": {"coverage_mode": ["tufts"]}},
			{"section": "TURF SCULPT", "key": "turf_spacing", "label": "Tuft spacing",
				"type": "float", "min": 0.16, "max": 0.55, "step": 0.005,
				"when": {"coverage_mode": ["turf"]}},
			{"key": "turf_footprint", "label": "Tuft size", "type": "range_float",
				"min": 0.10, "max": 0.48, "step": 0.005, "fallback": [0.22, 0.34],
				"when": {"coverage_mode": ["turf"]}},
			{"key": "turf_height", "label": "Turf thickness", "type": "range_float",
				"min": 0.012, "max": 0.10, "step": 0.002, "fallback": [0.030, 0.055],
				"when": {"coverage_mode": ["turf"]}},
			{"key": "turf_skip_fraction", "label": "Open ground", "type": "float",
				"min": 0.0, "max": 0.70, "step": 0.01,
				"when": {"coverage_mode": ["turf"]}},
			{"key": "turf_lobe_depth", "label": "Tuft lumpiness", "type": "float",
				"min": 0.0, "max": 0.40, "step": 0.01,
				"when": {"coverage_mode": ["turf"]}},
			{"key": "turf_overhang", "label": "Edge overhang", "type": "float",
				"min": 0.0, "max": 0.09, "step": 0.005,
				"when": {"coverage_mode": ["turf"]}},
			{"key": "blade_fraction", "label": "Blade coverage", "type": "float",
				"min": 0.0, "max": 1.0, "step": 0.01,
				"when": {"coverage_mode": ["turf"]}},
			{"key": "blades_per_tuft", "label": "Blades per tuft", "type": "range_int",
				"min": 0, "max": 8, "step": 1, "fallback": [2, 4],
				"when": {"coverage_mode": ["turf"]}},
			{"key": "accent_clumps", "label": "Accent clumps", "type": "range_int",
				"min": 0, "max": 5, "step": 1, "fallback": [1, 2],
				"when": {"coverage_mode": ["turf"]}},
			{"key": "carpet_spacing", "label": "Sprout spacing", "type": "float",
				"min": 0.12, "max": 0.58, "step": 0.005,
				"when": {"coverage_mode": ["carpet"]}},
			{"key": "carpet_skip_fraction", "label": "Open ground", "type": "float",
				"min": 0.0, "max": 0.80, "step": 0.01,
				"when": {"coverage_mode": ["carpet"]}},
			{"key": "carpet_jitter", "label": "Placement jitter", "type": "float",
				"min": 0.0, "max": 0.75, "step": 0.01,
				"when": {"coverage_mode": ["carpet"]}},
			{"section": "SPROUT SHAPE", "key": "rosette_footprint", "label": "Sprout size",
				"type": "range_float", "min": 0.05, "max": 0.38, "step": 0.005,
				"fallback": [0.14, 0.20], "when": {"coverage_mode": ["carpet"]}},
			{"key": "rosette_leaves", "label": "Leaves per sprout", "type": "range_int",
				"min": 2, "max": 12, "step": 1, "fallback": [3, 5],
				"when": {"coverage_mode": ["carpet"]}},
			{"key": "leaf_height", "label": "Leaf height", "type": "range_float",
				"min": 0.025, "max": 0.30, "step": 0.005, "fallback": [0.095, 0.15]},
			{"key": "leaf_width", "label": "Leaf width", "type": "range_float",
				"min": 0.012, "max": 0.18, "step": 0.003, "fallback": [0.058, 0.088]},
			{"key": "splay_degrees", "label": "Leaf splay", "type": "range_float",
				"min": 0.0, "max": 75.0, "step": 1.0, "fallback": [16.0, 34.0]},
			{"key": "height_multiplier", "label": "Height scale", "type": "float",
				"min": 0.35, "max": 2.2, "step": 0.01},
			{"key": "width_multiplier", "label": "Width scale", "type": "float",
				"min": 0.35, "max": 2.2, "step": 0.01},
			{"key": "bend_multiplier", "label": "Leaf bend", "type": "float",
				"min": 0.0, "max": 1.8, "step": 0.01},
			{"section": "FEATURE CLUSTERS", "key": "large_clusters", "label": "Large amount",
				"type": "int", "min": 0, "max": 8, "step": 1,
				"when": {"coverage_mode": ["clusters"]}},
			{"key": "medium_clusters", "label": "Medium amount", "type": "int",
				"min": 0, "max": 12, "step": 1,
				"when": {"coverage_mode": ["clusters"]}},
			{"key": "small_clusters", "label": "Small amount", "type": "int",
				"min": 0, "max": 16, "step": 1,
				"when": {"coverage_mode": ["clusters"]}},
		],
	},
	"pavers": {
		"label": "Patterned Surface",
		"description": "Cobbles, slabs, bricks, boards, or stepping stones.",
		"defaults": {"pattern": "cobbles", "stone_cell": 0.55, "gap": 0.026,
			"stone_height": [0.02, 0.03], "stone_corner": 0.028},
		"parameters": [
			{"section": "PATTERN", "key": "pattern", "label": "Pattern type",
				"type": "enum", "values": ["cobbles", "planks", "stepping", "trail"],
				"randomize": false},
			{"key": "stone_cell", "label": "Cell width", "type": "float",
				"min": 0.12, "max": 0.90, "step": 0.01,
				"when": {"pattern": ["cobbles"]}},
			{"key": "stone_cell_z", "label": "Cell length", "type": "float",
				"min": 0.08, "max": 0.90, "step": 0.01,
				"when": {"pattern": ["cobbles"]}},
			{"key": "stone_jitter", "label": "Joint jitter", "type": "float",
				"min": 0.0, "max": 0.18, "step": 0.005,
				"when": {"pattern": ["cobbles"]}},
			{"key": "plank_width", "label": "Board width", "type": "float",
				"min": 0.08, "max": 0.45, "step": 0.01,
				"when": {"pattern": ["planks"]}},
			{"key": "plank_length", "label": "Board length", "type": "range_float",
				"min": 0.25, "max": 1.65, "step": 0.01, "fallback": [0.55, 0.95],
				"when": {"pattern": ["planks"]}},
			{"key": "stepping_count", "label": "Stone amount", "type": "range_int",
				"min": 1, "max": 16, "step": 1, "fallback": [4, 6],
				"when": {"pattern": ["stepping"]}},
			{"key": "stepping_size", "label": "Stone size", "type": "range_float",
				"min": 0.10, "max": 0.58, "step": 0.01, "fallback": [0.24, 0.34],
				"when": {"pattern": ["stepping"]}},
			{"section": "TRAIL COMPOSITION", "key": "trail_layout", "label": "Trail layout",
				"type": "enum", "values": ["straight", "cross"], "randomize": false,
				"when": {"pattern": ["trail"]}},
			{"key": "trail_width", "label": "Trail width", "type": "float",
				"min": 0.18, "max": 1.25, "step": 0.01,
				"when": {"pattern": ["trail"]}},
			{"key": "trail_piece_length", "label": "Piece length", "type": "range_float",
				"min": 0.12, "max": 0.72, "step": 0.01, "fallback": [0.24, 0.42],
				"when": {"pattern": ["trail"]}},
			{"key": "trail_jitter", "label": "Trail irregularity", "type": "float",
				"min": 0.0, "max": 0.24, "step": 0.005,
				"when": {"pattern": ["trail"]}},
			{"section": "JOINTS & PROFILE", "key": "gap", "label": "Gap width",
				"type": "float", "min": 0.004, "max": 0.09, "step": 0.002},
			{"key": "stone_height", "label": "Piece height", "type": "range_float",
				"min": 0.006, "max": 0.12, "step": 0.002, "fallback": [0.02, 0.03]},
			{"key": "stone_corner", "label": "Piece roundness", "type": "float",
				"min": 0.0, "max": 0.12, "step": 0.003},
			{"key": "stone_profile", "label": "Piece profile", "type": "enum",
				"values": ["slab", "cushion", "faceted"],
				"value_labels": ["Beveled slab", "Rounded cushion",
					"Hand-cut stone"],
				"randomize": false},
		],
	},
	"liquid": {
		"label": "Liquid Surface",
		"description": "Level water with optional falling sheets on selected edges.",
		"defaults": {"level": 0.012, "inset": 0.018, "corner_radius": 0.06,
			"fall_edges": [], "fall_depth": 0.65, "fall_width": 0.72},
		"parameters": [
			{"section": "SURFACE", "key": "level", "label": "Water level",
				"type": "float", "min": -0.18, "max": 0.14, "step": 0.005},
			{"key": "inset", "label": "Surface inset", "type": "float",
				"min": 0.0, "max": 0.35, "step": 0.005},
			{"key": "corner_radius", "label": "Corner roundness", "type": "float",
				"min": 0.0, "max": 0.30, "step": 0.005},
			{"key": "ripple_count", "label": "Wave forms", "type": "range_int",
				"min": 0, "max": 4, "step": 1, "fallback": [1, 2]},
			{"key": "rim_width", "label": "Meniscus ring", "type": "float",
				"min": 0.0, "max": 0.06, "step": 0.002},
			{"section": "FALLING EDGES", "key": "fall_edges", "label": "Waterfall edges",
				"type": "multi", "values": [0, 1, 2, 3],
				"value_labels": ["North", "East", "South", "West"],
				"fallback": [], "allow_empty": true, "randomize": false},
			{"key": "fall_depth", "label": "Fall distance", "type": "float",
				"min": 0.10, "max": 3.0, "step": 0.05},
			{"key": "fall_width", "label": "Fall width", "type": "float",
				"min": 0.08, "max": 1.0, "step": 0.01},
		],
	},
	"fringe": {
		"label": "Connection Fringe",
		"description": "Segmented rims for soil beds, ponds, banks, and borders.",
		"defaults": {"edges": [0, 1, 2, 3], "exposed_only": true,
			"inset": 0.045, "width": 0.085, "height": 0.045,
			"pieces_per_edge": 7, "gap": 0.018, "jitter": 0.16},
		"parameters": [
			{"section": "EDGE COVERAGE", "key": "edges", "label": "Fringe edges",
				"type": "multi", "values": [0, 1, 2, 3],
				"value_labels": ["North", "East", "South", "West"], "randomize": false},
			{"key": "exposed_only", "label": "Hide on connected edges", "type": "bool"},
			{"section": "FRINGE SHAPE", "key": "pieces_per_edge", "label": "Piece amount",
				"type": "int", "min": 2, "max": 20, "step": 1},
			{"key": "width", "label": "Rim width", "type": "float",
				"min": 0.025, "max": 0.28, "step": 0.005},
			{"key": "height", "label": "Rim height", "type": "float",
				"min": 0.008, "max": 0.18, "step": 0.004},
			{"key": "inset", "label": "Edge inset", "type": "float",
				"min": 0.01, "max": 0.30, "step": 0.005},
			{"key": "gap", "label": "Piece gap", "type": "float",
				"min": 0.0, "max": 0.09, "step": 0.003},
			{"key": "jitter", "label": "Irregularity", "type": "float",
				"min": 0.0, "max": 0.48, "step": 0.01},
		],
	},
	"fence": {
		"label": "Edge Border",
		"description": "Reusable posts and rails on selected cardinal edges.",
		"defaults": {"edges": [0, 1, 2, 3], "inset": 0.055,
			"post_size": 0.07, "post_height": 0.19, "post_spacing": 0.44,
			"rail_height": 0.12, "rail_thickness": 0.034},
		"parameters": [
			{"section": "EDGE COVERAGE", "key": "edges", "label": "Border edges",
				"type": "multi", "values": [0, 1, 2, 3],
				"value_labels": ["North", "East", "South", "West"], "randomize": false},
			{"key": "inset", "label": "Edge inset", "type": "float",
				"min": 0.015, "max": 0.30, "step": 0.005},
			{"section": "POSTS & RAILS", "key": "post_height", "label": "Post height",
				"type": "float", "min": 0.06, "max": 0.60, "step": 0.01},
			{"key": "post_size", "label": "Post size", "type": "float",
				"min": 0.025, "max": 0.18, "step": 0.005},
			{"key": "post_spacing", "label": "Post spacing", "type": "float",
				"min": 0.18, "max": 0.85, "step": 0.01},
			{"key": "rail_height", "label": "Rail height", "type": "float",
				"min": 0.04, "max": 0.48, "step": 0.01},
			{"key": "rail_thickness", "label": "Rail thickness", "type": "float",
				"min": 0.015, "max": 0.12, "step": 0.003},
		],
	},
}


static func label(kind: String) -> String:
	return String(DEFINITIONS.get(kind, {}).get("label", kind.capitalize()))


static func description(kind: String) -> String:
	return String(DEFINITIONS.get(kind, {}).get("description", ""))


static func parameters(kind: String) -> Array:
	return DEFINITIONS.get(kind, {}).get("parameters", [])


static func new_layer(kind: String) -> TileKitLayer:
	if not DEFINITIONS.has(kind):
		return null
	return TileKitLayer.new(
		kind,
		(DEFINITIONS[kind].get("defaults", {}) as Dictionary).duplicate(true)
	)


static func is_visible(parameter: Dictionary, layer: TileKitLayer) -> bool:
	for key: String in (parameter.get("when", {}) as Dictionary):
		var allowed: Array = parameter["when"][key]
		if layer.value(key, "") not in allowed:
			return false
	for key: String in (parameter.get("when_number", {}) as Dictionary):
		if float(layer.value(key, 0.0)) < float(parameter["when_number"][key]):
			return false
	return true


static func fallback(parameter: Dictionary, kind := "") -> Variant:
	if parameter.has("fallback"):
		return parameter["fallback"]
	var key := String(parameter.get("key", ""))
	if DEFINITIONS.has(kind):
		var defaults := DEFINITIONS[kind].get("defaults", {}) as Dictionary
		if defaults.has(key):
			return defaults[key]
	match String(parameter.get("type", "float")):
		"bool":
			return false
		"enum", "multi":
			var values: Array = parameter.get("values", [])
			return values[0] if not values.is_empty() else ""
	return parameter.get("min", 0.0)


static func randomize_parameters(layer: TileKitLayer, rng: RandomNumberGenerator) -> void:
	for raw: Variant in parameters(layer.kind):
		var parameter := raw as Dictionary
		if not bool(parameter.get("randomize", true)) or not is_visible(parameter, layer):
			continue
		var key := String(parameter["key"])
		var minimum := float(parameter.get("min", 0.0))
		var maximum := float(parameter.get("max", 1.0))
		match String(parameter.get("type", "float")):
			"float":
				layer.params[key] = snappedf(rng.randf_range(minimum, maximum),
					float(parameter.get("step", 0.01)))
			"int":
				layer.params[key] = rng.randi_range(int(minimum), int(maximum))
			"range_float":
				var a := rng.randf_range(minimum, maximum)
				var b := rng.randf_range(minimum, maximum)
				var step := float(parameter.get("step", 0.01))
				layer.params[key] = [snappedf(minf(a, b), step), snappedf(maxf(a, b), step)]
			"range_int":
				var a := rng.randi_range(int(minimum), int(maximum))
				var b := rng.randi_range(int(minimum), int(maximum))
				layer.params[key] = [mini(a, b), maxi(a, b)]
			"enum":
				var values: Array = parameter.get("values", [])
				if not values.is_empty():
					layer.params[key] = values[rng.randi() % values.size()]


static func ordered_insertion_index(layers: Array[TileKitLayer], kind: String) -> int:
	var target_order := KIND_ORDER.find(kind)
	for index in layers.size():
		var other_order := KIND_ORDER.find(layers[index].kind)
		if other_order >= 0 and other_order > target_order:
			return index
	return layers.size()
