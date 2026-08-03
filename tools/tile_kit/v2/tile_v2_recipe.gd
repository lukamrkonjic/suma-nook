@tool
class_name TileV2Recipe
extends Resource
## One V2 tile: a generator FAMILY plus authored high-level parameters.
##
## V2 recipes never store raw geometry or op soups. The family's composer in
## TileV2Library maps (params, seed, layout) to a concrete field + structure
## set, deterministically: the same recipe always rebuilds the same tile,
## and a seed can only select an authored layout and apply bounded jitter —
## it cannot invent a composition.

## Bump when the composer contract changes; loaders migrate older data.
const CURRENT_VERSION := 2

@export var recipe_version := CURRENT_VERSION
@export var tile_id := ""
@export var display_name := "Untitled V2 Tile"
## One of TileV2Library.FAMILIES.
@export var family := "moss_cushion"
@export var seed := 20260803
## Which authored layout of the family to use (wrapped into range).
@export var layout := 0
## Family-specific high-level knobs (macro strength, lip size, palette
## nudges…). Only keys the family's composer documents are read.
@export var params: Dictionary = {}
## Mesh resolution (cells across the 1.70 m footprint).
@export var resolution := 80
## Declared walkable height for the collision profile (schema clamps 0..0.15).
@export var walk_surface_height := 0.03


func duplicate_recipe() -> TileV2Recipe:
	var copy := TileV2Recipe.new()
	copy.recipe_version = recipe_version
	copy.tile_id = tile_id
	copy.display_name = display_name
	copy.family = family
	copy.seed = seed
	copy.layout = layout
	copy.params = params.duplicate(true)
	copy.resolution = resolution
	copy.walk_surface_height = walk_surface_height
	return copy


## Stable fingerprint for mesh caching.
func fingerprint() -> String:
	return "%s|%s|%d|%d|%d|%s" % [
		tile_id, family, seed, layout, resolution, JSON.stringify(params)
	]


## Forward-compatibility hook: older serialized recipes are upgraded here.
static func migrate(data: TileV2Recipe) -> TileV2Recipe:
	if data.recipe_version < CURRENT_VERSION:
		# Version 1 never shipped as a V2 resource; nothing to rewrite yet.
		data.recipe_version = CURRENT_VERSION
	return data
