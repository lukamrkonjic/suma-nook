@tool
class_name TileRecipe
extends Resource
## One logical tile, described entirely as data.
##
## This is the file a designer creates to make a new tile. If making an
## ordinary tile requires editing anything under generators/, the system has
## failed its own contract — see the "Adding a tile" section of
## README_TILE_FORGE.md.
##
## A recipe describes the TOP ASSEMBLY. The structural block is referenced, not
## restated, because Suma already owns two canonical bases.

@export_group("Identity")
## Stable id. Becomes the baked asset id, the manifest key, and the string a
## data/tiles.json layer refers to. Never rename a shipped id.
@export var tile_id := "tf_new_tile"
@export var display_name := "New Tile"
@export var category: TileForgeConstants.Category = TileForgeConstants.Category.ORGANIC_SURFACE
## Free tags for search, discovery pools, and transition matching. The first
## tag is treated as the surface family.
@export var tags: PackedStringArray = []
@export_multiline var preview_notes := ""

@export_group("Determinism")
## Base seed. Same recipe + same seed = same tile, always.
@export var seed_value := 1
## Variant index folded into every channel. Use it to bake a curated set.
@export var variant := 0

@export_group("Geometry")
## LIVE tile size. Defaults to the grid; overriding it is a deliberate act.
@export var tile_size := TileForgeConstants.LIVE_TILE_SIZE
@export var base_profile: TileBaseProfile
@export var palette: TilePalette
## Shared art direction: bevels, relief band, detail scale, colour separation.
## Left null the Forge loads the project default, so a recipe cannot silently
## opt out of the collection's look.
@export var art_profile: SumaTileArtProfile

@export_group("Composition")
## Evaluated in order. Heightfield layers accumulate into one top; mesh layers
## append their own geometry after it.
@export var surface_layers: Array[TileSurfaceLayer] = []
## Evaluated after the surface exists, so every module can sample its height.
@export var detail_rules: Array[TileDetailRule] = []
@export var transition_rules: Array[TileTransitionRule] = []

@export_group("Edges")
## Default behaviour for every edge without a matching transition rule.
@export var edge_policy: TileForgeConstants.EdgePolicy = TileForgeConstants.EdgePolicy.CONNECTED_SAME_SURFACE
## Height every connected edge must meet, metres. Shared across the whole
## connected family — changing it on one tile breaks the seam with all of them.
@export var connected_edge_height := 0.0
## Quarter turns this tile may be placed at. Fewer allowed rotations lets a
## composition be authored for one orientation.
@export var allowed_rotations: PackedInt32Array = PackedInt32Array([0, 1, 2, 3])

@export_group("Runtime contract")
@export var collision_mode: TileForgeConstants.CollisionMode = TileForgeConstants.CollisionMode.FLAT_BOX
## Mirrors Defs.TileDefinition.walk_surface_height. Left at -1 the baker
## measures the median top and writes the honest value into the manifest.
@export var walk_surface_height := -1.0
@export var navigation_walkable := true
## Emitted into the manifest so data/tiles.json can be written correctly.
@export var connection_mode := "full_flush"

@export_group("Detail policy")
## Distance beyond which small details may be hidden. 0 = never.
@export var detail_lod_distance := 0.0
## Default output mode for detail rules that do not override it.
@export var default_detail_output: TileForgeConstants.DetailOutput = TileForgeConstants.DetailOutput.MERGED_STATIC_MESH

@export_group("Custom")
## Consumed by a custom_mesh layer or a project-specific generator.
@export var custom_params: Dictionary = {}


func half_extent() -> float:
	return tile_size * 0.5


func surface_family() -> String:
	return tags[0] if tags.size() > 0 else "generic"


func effective_seed() -> int:
	return TileSeedUtil.channel_seed(seed_value, tile_id, variant)


## Baked asset id for a given variant. Variant 0 keeps the plain id so the
## common case reads cleanly in data/tiles.json.
func baked_asset_id(for_variant := -1) -> String:
	var index := variant if for_variant < 0 else for_variant
	return tile_id if index == 0 else "%s_v%02d" % [tile_id, index]


func enabled_surface_layers() -> Array[TileSurfaceLayer]:
	var result: Array[TileSurfaceLayer] = []
	for layer in surface_layers:
		if layer != null and layer.enabled:
			result.append(layer)
	return result


func enabled_detail_rules() -> Array[TileDetailRule]:
	var result: Array[TileDetailRule] = []
	for rule in detail_rules:
		if rule != null and rule.is_valid():
			result.append(rule)
	return result


func transition_for(edge_name: String, neighbour_family: String) -> TileTransitionRule:
	for rule in transition_rules:
		if rule != null and rule.matches(edge_name, neighbour_family):
			return rule
	return null


## True when every edge must reach the shared connected height exactly.
func is_connected_surface() -> bool:
	return (
		edge_policy == TileForgeConstants.EdgePolicy.CONNECTED_SAME_SURFACE
		or edge_policy == TileForgeConstants.EdgePolicy.CONNECTED_TRANSITION
	)


## Produces a copy configured for another variant seed. Used by the variant-set
## generator so the source recipe is never mutated.
func with_variant(index: int) -> TileRecipe:
	var copy: TileRecipe = duplicate(false)
	copy.variant = index
	return copy
