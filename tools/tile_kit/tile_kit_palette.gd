class_name TileKitPalette
extends RefCounted
## The locked palette and shared materials for Tile Kit tiles.
##
## Every colour a generated tile may use lives here, by name, as an exact
## value. Builders ask for materials by key and NEVER construct colours —
## that single rule is what makes "no randomizer can produce an off-palette
## colour" a structural guarantee instead of a code-review hope.
##
## Materials are cached per key, so a tile with ten thousand blades still
## carries a handful of material resources, and two baked variants share the
## same resources when instanced side by side.
##
## The keys are deliberately prefixed "tilekit_" so MaterialLibrary's semantic
## rebinding (which matches resource_name against palette keys) leaves these
## untouched: the kit's palette is locked by design, including at runtime.

## The kit's closed colour set, organised as material families in the same
## desaturated clay register as the approved grass reference. Family values
## are original picks informed by the tile research inventory (grass, moss,
## earth, stone, wood, snow — docs/TILE_IMAGE_GENERATION_PROMPTS.md); nothing
## here is sampled from another game's assets. Exact, never randomized, never
## interpolated into new colours.
const COLORS := {
	"background": Color("#F5DAB3"),
	# Grass-family tile shell. Anchored to Suma's mossy Pacific-Northwest
	# range, retuned for confident value separation: the top is a richer mid
	# moss green, the bevel a clear sunlit lift, and the side the SAME hue a
	# full value step (~25%) darker — the volume must read at gameplay zoom,
	# not only in close renders. Lightest greens appear only as sunlit tips.
	# Grass family: confident warm yellow-green in the reference register —
	# the audited grass reads far yellower than a "grass green" — pulled a
	# step mossier for Suma. Sides are earthy olive, a full value below.
	"tile_top": Color("#A3B944"),
	"tile_top_bevel": Color("#B5CA51"),
	"tile_side": Color("#6E7C34"),
	"tile_lower": Color("#57642A"),
	"dressing_light": Color("#B0C24F"),
	"dressing_medium": Color("#93A93E"),
	"dressing_dark": Color("#7E9536"),
	"clutter_light": Color("#C2D05E"),
	"clutter_medium": Color("#9DB245"),
	# Blade tones: tufts sit slightly darker OR lighter than the top, never
	# a different hue family. Root shadow anchors the tuft bases.
	"grass_primary": Color("#87A139"),
	"grass_secondary": Color("#C3D45E"),
	"grass_root": Color("#5C7029"),
	# Moss / forest family: deeper cooler green, still lively.
	"moss_top": Color("#71903B"),
	"moss_bevel": Color("#81A146"),
	"moss_deep": Color("#4B6329"),
	"moss_clump": Color("#5E7C31"),
	# Earth family: warm loam, clearly darker and redder than sand.
	"earth_top": Color("#A06B3E"),
	"earth_bevel": Color("#B37A49"),
	"earth_side": Color("#7A4E2B"),
	"earth_deep": Color("#59371D"),
	"earth_clump": Color("#8A5A32"),
	# Stone family: warm greys — reference stone never goes blue.
	"stone_light": Color("#CDC5AB"),
	"stone_medium": Color("#A69E83"),
	"stone_deep": Color("#75705A"),
	# Wood family: golden cedar tops over darker sides.
	"wood_light": Color("#BE8D58"),
	"wood_medium": Color("#96683A"),
	"wood_deep": Color("#66451F"),
	# Snow family: warm ivory tops, cool pale-blue shadow sides.
	"snow_top": Color("#F6F1E1"),
	"snow_bevel": Color("#FBF7EB"),
	"snow_side": Color("#B7C4CB"),
	"snow_lump": Color("#EDEADB"),
	# Sand family: creamy golden dunes — brighter and yellower than dirt.
	"sand_top": Color("#EFD08F"),
	"sand_bevel": Color("#F8DFA4"),
	"sand_side": Color("#C09A5F"),
	"sand_deep": Color("#8F7040"),
	"sand_patch": Color("#E2C17C"),
	# Mud family: dark damp earth with a wet-patch accent.
	"mud_top": Color("#7A5B38"),
	"mud_bevel": Color("#886745"),
	"mud_wet": Color("#4E3A24"),
	# Brick / clay family: confident warm terracotta.
	"brick_light": Color("#C97E52"),
	"brick_medium": Color("#A05A3C"),
	# Water family: restrained pale blue-green, translucent in material.
	"water_blue": Color("#7FB2AB"),
	"water_deep": Color("#3E7570"),
	"water_light": Color("#A8D3C6"),
	"lily_green": Color("#6B934C"),
	# Blossom and autumn accents.
	"blossom_pink": Color("#E39DAD"),
	"blossom_cream": Color("#F2E6C8"),
	"autumn_amber": Color("#D29140"),
	"autumn_rust": Color("#B3653A"),
	# Small whimsical accents (mushroom caps, buds).
	"accent_terracotta": Color("#C97A54"),
	"accent_cream": Color("#EFE3C8"),
}

static var _materials: Dictionary = {}


static func color(key: String) -> Color:
	assert(COLORS.has(key), "TileKitPalette: unknown colour key %s" % key)
	return COLORS[key]


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
		result.roughness = 0.18
		result.metallic_specular = 0.55
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
