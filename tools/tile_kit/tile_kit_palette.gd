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
	# Moss / forest family: deeper cooler green, still lively.
	"moss_top": "tilekit_moss_top",
	"moss_bevel": "tilekit_tile_top",
	"moss_deep": "tilekit_moss_deep",
	"moss_clump": "tilekit_moss_clump",
	# Earth family: warm loam, clearly darker and redder than sand.
	"earth_top": "tilekit_earth_top",
	"earth_bevel": "tilekit_earth_bevel",
	"earth_side": "tilekit_earth_side",
	"earth_deep": "tilekit_earth_deep",
	"earth_clump": "tilekit_earth_clump",
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
