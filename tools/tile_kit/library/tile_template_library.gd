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
