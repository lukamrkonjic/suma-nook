class_name TileKitPalette
extends RefCounted
## Tile Kit semantic roles backed by Suma's canonical color design system.
##
## Every colour a generated tile may use lives in
## assets/palettes/gg_material_palette.tres. Builders ask for materials by key
## and NEVER construct colours —
## that single rule is what makes "no randomizer can produce an off-palette
## colour" a structural guarantee instead of a code-review hope.
##
## Materials are cached per key, so a tile with ten thousand blades still
## carries a handful of material resources, and two baked variants share the
## same resources when instanced side by side.
##
## Baked resource names stay prefixed "tilekit_" while this mapping resolves
## their authoring roles through the same scheme controls as the rest of the
## game.

## The kit's closed colour set, organised as material families in the same
## desaturated clay register as the approved grass reference. Family values
## are original picks informed by the tile research inventory (grass, moss,
## earth, stone, wood, snow — docs/TILE_IMAGE_GENERATION_PROMPTS.md); nothing
## here is sampled from another game's assets. Exact, never randomized, never
## interpolated into new colours.
const DESIGN_SYSTEM: PaletteDefinition = preload(
	"res://assets/palettes/gg_material_palette.tres"
)

const COLORS := {
	"background": "tilekit_background",
	# Grass-family tile shell. Anchored to Suma's mossy Pacific-Northwest
	# range, retuned for confident value separation: the top is a richer mid
	# moss green, the bevel a clear sunlit lift, and the side the SAME hue a
	# full value step (~25%) darker — the volume must read at gameplay zoom,
	# not only in close renders. Lightest greens appear only as sunlit tips.
	# Grass family: the approved Suma moss greens — natural, never neon.
	# Primary #6E9140 dominates; supporting and recessed greens stay close
	# in hue; the highlight is a restrained accent, never a surface.
	"tile_top": "tilekit_tile_top",
	"tile_top_bevel": "tilekit_tile_top_bevel",
	"tile_side": "tilekit_tile_side",
	"tile_lower": "tilekit_tile_lower",
	"dressing_light": "tilekit_tile_top_bevel",
	"dressing_medium": "tilekit_tile_top",
	"dressing_dark": "tilekit_tile_side",
	"clutter_light": "tilekit_clutter_light",
	"clutter_medium": "tilekit_tile_top_bevel",
	# Blade tones: supporting green carries most tufts, recessed green
	# anchors bases and shaded clusters, highlight is rare sunlit tips.
	"grass_primary": "tilekit_tile_top_bevel",
	"grass_secondary": "tilekit_clutter_light",
	"grass_root": "tilekit_tile_side",
	# Clay-grass redesign: a quieter sage ramp from the canonical GG palette.
	# These roles are intentionally tile-specific so the standard grass can
	# establish the new art direction without recolouring every legacy meadow
	# asset at once. Top and bevel share one calm mid-value so the shell reads
	# as a single clay piece; sides and leaf bodies supply the darker step.
	"grass_clay_top": "leaf_medium",
	"grass_clay_bevel": "leaf_medium",
	"grass_clay_side": "leaf_olive",
	"grass_clay_lower": "leaf_olive",
	"grass_clay_blade": "leaf_olive",
	"grass_clay_tip": "leaf_medium",
	# Moss / forest family: deeper cooler green, still lively.
	"moss_top": "tilekit_moss_top",
	"moss_bevel": "tilekit_tile_top",
	"moss_deep": "tilekit_moss_deep",
	"moss_clump": "tilekit_moss_clump",
	# Clay-moss redesign: a deep olive floor with a restrained, slightly
	# lighter pad and shoot ramp. The brown body ties it to the redesigned
	# dirt tile; these targeted roles avoid recolouring legacy forest assets.
	"moss_clay_top": "moss_primary",
	"moss_clay_bevel": "moss_primary",
	"moss_clay_side": "leaf_olive",
	"moss_clay_lower": "leaf_olive",
	"moss_clay_pad": "leaf_medium",
	"moss_clay_shoot": "leaf_medium",
	# GG-aligned moss studies. Moss is paired with a contrasting substrate or
	# becomes the surface itself; none of these place light-green decals over a
	# green slab. Stone stays warm, soil stays terracotta, and vegetation uses
	# the yellow-olive family that ties into Suma's established grass palette.
	"moss_gg_stone_top": "stone_light",
	"moss_gg_stone_bevel": "stone_mid_light",
	"moss_gg_stone_side": "stone_warm_shadow",
	"moss_gg_stone_lower": "stone_shadow",
	"moss_gg_stone_growth": "grass_secondary",
	"moss_gg_stone_edge": "leaf_olive",
	"moss_gg_stone_chip": "stone_mid",
	"moss_gg_earth_growth": "grass_primary",
	"moss_gg_earth_highlight": "grass_sunlit",
	"moss_gg_carpet_top": "grass_secondary",
	"moss_gg_carpet_bevel": "grass_secondary",
	"moss_gg_carpet_side": "earth_shadow",
	"moss_gg_carpet_lower": "earth_deep",
	"moss_gg_carpet_detail": "grass_shade",
	"moss_gg_carpet_highlight": "grass_primary",
	# Full-ground moss studies: coherent monochrome ramps with no exposed
	# stone, soil, or leaf-litter layer.
	"moss_sheet_top": "leaf_olive",
	"moss_sheet_bevel": "moss_primary",
	"moss_sheet_side": "leaf_olive",
	"moss_sheet_lower": "deep_grass",
	"moss_cushion_base": "moss_primary",
	"moss_cushion_body": "moss_primary",
	"moss_cushion_light": "leaf_medium",
	"moss_cushion_side": "leaf_olive",
	"moss_cushion_lower": "deep_grass",
	"moss_shag_base": "moss_primary",
	"moss_shag_body": "leaf_medium",
	"moss_shag_light": "grass_secondary",
	"moss_shag_side": "grass_shade",
	"moss_shag_lower": "deep_grass",
	# Earth family: warm loam, clearly darker and redder than sand.
	"earth_top": "tilekit_earth_top",
	"earth_bevel": "tilekit_earth_bevel",
	"earth_side": "tilekit_earth_side",
	"earth_deep": "tilekit_earth_deep",
	"earth_clump": "tilekit_earth_clump",
	# Clay-dirt redesign: use the canonical warm loam ramp instead of the old
	# yellow Tile Kit earth tokens. Like the grass master, this is deliberately
	# tile-specific while the new art direction is rolled through the library.
	# The shell stays one calm terracotta piece; light/dark chips are sparse
	# modelling accents, not an all-over texture treatment.
	"dirt_clay_top": "earth_mid",
	"dirt_clay_bevel": "earth_mid",
	"dirt_clay_side": "earth_shadow",
	"dirt_clay_lower": "earth_deep",
	"dirt_clay_chip_light": "earth_primary",
	"dirt_clay_chip_dark": "earth_deep",
	# Stone family: warm greys — reference stone never goes blue.
	"stone_light": "tilekit_stone_light",
	"stone_medium": "tilekit_stone_medium",
	"stone_deep": "tilekit_stone_deep",
	# Wood family: golden cedar tops over darker sides.
	"wood_light": "tilekit_wood_light",
	"wood_medium": "tilekit_wood_medium",
	"wood_deep": "tilekit_wood_deep",
	# Snow family: warm ivory tops, cool pale-blue shadow sides.
	"snow_top": "tilekit_snow_top",
	"snow_bevel": "tilekit_snow_bevel",
	"snow_side": "tilekit_snow_side",
	"snow_lump": "tilekit_snow_lump",
	# Sand family: creamy golden dunes — brighter and yellower than dirt.
	"sand_top": "tilekit_sand_top",
	"sand_bevel": "tilekit_sand_bevel",
	"sand_side": "tilekit_sand_side",
	"sand_deep": "tilekit_sand_deep",
	"sand_patch": "tilekit_sand_patch",
	# Mud family: dark damp earth with a wet-patch accent.
	"mud_top": "tilekit_mud_top",
	"mud_bevel": "tilekit_mud_bevel",
	"mud_wet": "tilekit_mud_wet",
	# Brick / clay family: confident warm terracotta.
	"brick_light": "tilekit_brick_light",
	"brick_medium": "tilekit_brick_medium",
	# Water family: restrained pale blue-green, translucent in material.
	"water_blue": "tilekit_water_blue",
	"water_deep": "tilekit_water_deep",
	"water_light": "tilekit_water_light",
	"lily_green": "tilekit_lily_green",
	# Blossom and autumn accents.
	"blossom_pink": "tilekit_blossom_pink",
	"blossom_cream": "tilekit_blossom_cream",
	"autumn_amber": "tilekit_autumn_amber",
	"autumn_rust": "tilekit_autumn_rust",
	# Small whimsical accents (mushroom caps, buds).
	"accent_terracotta": "tilekit_accent_terracotta",
	"accent_cream": "tilekit_accent_cream",
}

static var _materials: Dictionary = {}


static func color(key: String) -> Color:
	assert(COLORS.has(key), "TileKitPalette: unknown colour key %s" % key)
	return DESIGN_SYSTEM.color(COLORS[key])


## The one shared material per palette key. Solid colour and matte across the
## board — with the single sanctioned exception of still water, which is a
## slightly translucent, slightly glossy plane exactly like the reference's
## basin water. Everything else stays opaque toy clay.
static func material(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var result := StandardMaterial3D.new()
	result.resource_name = "tilekit_%s" % key
	result.albedo_color = color(key)
	result.metallic = 0.0
	result.roughness = 0.9
	result.metallic_specular = 0.2
	result.vertex_color_use_as_albedo = false
	if key in ["water_blue", "water_light"]:
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		result.albedo_color.a = 0.86
		# Soft sheen only: a tight glossy highlight interpolates visibly
		# across the water plane's long fan triangles and draws an X.
		result.roughness = 0.34
		result.metallic_specular = 0.32
	_materials[key] = result
	return result


## Weighted pick from a {key: weight} table, on the layer's own RNG. The only
## sanctioned way for a builder to choose a colour.
static func weighted_key(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for key: String in weights:
		total += float(weights[key])
	var roll := rng.randf() * total
	for key: String in weights:
		roll -= float(weights[key])
		if roll <= 0.0:
			return key
	return weights.keys().back()
