@tool
class_name TileTemplateLibrary
extends RefCounted
## Generic starting points for creating a NEW procedural tile.
##
## These are intentionally not official tile records and never appear in the
## Tile browser. A template is copied into an unsaved working recipe, then the
## designer gives that new tile its own stable ID and identity.

const TEMPLATES := [
	{
		"id": "organic_ground",
		"name": "Organic Ground",
		"description": "Fused soil cap with editable carpet vegetation.",
	},
	{
		"id": "bare_ground",
		"name": "Bare Ground",
		"description": "Clean fused terrain with all scatter layers disabled.",
	},
	{
		"id": "sculpted_dunes",
		"name": "Sculpted Dunes",
		"description": "Wind-shaped periodic relief for sand, snow, or soil.",
	},
	{
		"id": "constructed_surface",
		"name": "Constructed Surface",
		"description": "Separated hard-surface blocks for paving and decking.",
	},
	{
		"id": "shallow_basin",
		"name": "Shallow Basin",
		"description": "A depressed organic surface for ponds and wet ground.",
	},
	{
		"id": "liquid_surface",
		"name": "Liquid Surface",
		"description": "Level water with optional waterfall edges and surface scatter.",
	},
	{
		"id": "fringed_ground",
		"name": "Fringed Ground",
		"description": "Organic ground with a connection-aware segmented border.",
	},
]


static func instantiate(template_id: String) -> TileKitPreset:
	var preset: TileKitPreset
	match template_id:
		"bare_ground":
			preset = TileKitPreset.reference_clean_grass()
			for kind in ["dressing", "clutter", "grass_clusters"]:
				var layer := preset.layer_of_kind(kind)
				if layer != null:
					layer.enabled = false
		"sculpted_dunes":
			preset = TileKitPreset.sand_dune_study()
		"constructed_surface":
			preset = TileKitPreset.concrete_slabs()
		"shallow_basin":
			preset = TileKitPreset.pond_basin()
		"liquid_surface":
			preset = TileKitPreset.reference_clean_grass()
			preset.separate_tiles = true
			for kind in ["dressing", "clutter", "grass_clusters"]:
				var layer := preset.layer_of_kind(kind)
				if layer != null:
					layer.enabled = false
			var base := preset.layer_of_kind("base")
			base.params.merge({"top_key": "water_deep", "bevel_key": "water_deep",
				"side_key": "water_deep", "lower_key": "stone_deep"}, true)
			preset.layers.insert(1, TileKitLayer.new("liquid", {
				"level": 0.012, "inset": 0.018, "corner_radius": 0.06,
				"surface_key": "water_blue", "fall_edges": [],
				"fall_depth": 0.65, "fall_width": 0.72,
			}))
		"fringed_ground":
			preset = TileKitPreset.reference_clean_grass()
			preset.layers.append(TileKitLayer.new("fringe", {
				"edges": [0, 1, 2, 3], "exposed_only": true,
				"pieces_per_edge": 7, "width": 0.085, "height": 0.045,
				"inset": 0.045, "gap": 0.018, "jitter": 0.16,
				"material_key": "earth_clump",
			}))
		_:
			preset = TileKitPreset.reference_clean_grass()
	if preset == null:
		return null
	var copy := preset.duplicate_preset()
	copy.preset_name = "New %s" % display_name(template_id)
	copy.master_seed = randi() % 1000000
	return copy


static func display_name(template_id: String) -> String:
	for template in TEMPLATES:
		if String(template["id"]) == template_id:
			return String(template["name"])
	return "Organic Ground"
