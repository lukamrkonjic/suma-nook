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
	# range: the top is the mid moss green, the bevel a restrained sunlit lift,
	# and the side the SAME hue 14% darker — never a different family, which is
	# what made the old lime top on olive sides read as two stacked objects.
	# The old pale yellow-lime register is retired; the lightest greens now
	# appear only as rare sunlit tips, never as the dominant surface.
	"tile_top": Color("#91AA61"),
	"tile_top_bevel": Color("#9EB76B"),
	"tile_side": Color("#7C9153"),
	"tile_lower": Color("#5F7F4D"),
	"dressing_light": Color("#9BB26A"),
	"dressing_medium": Color("#8CA55E"),
	"dressing_dark": Color("#7E9854"),
	"clutter_light": Color("#A3B771"),
	"clutter_medium": Color("#93A962"),
	# Blades sit DEEPER than the top they grow from, so vegetation reads as
	# richer material, and the sunlit tone stays reserved for accents.
	"grass_primary": Color("#5F7F4D"),
	"grass_secondary": Color("#6E8E55"),
	"grass_root": Color("#46603E"),
	# Moss family: deeper, cooler greens for forest-floor tops.
	"moss_top": Color("#7E9757"),
	"moss_bevel": Color("#8AA361"),
	"moss_deep": Color("#5C764B"),
	"moss_clump": Color("#6C8752"),
	# Earth family: cedar-and-loam browns around the #A9865F anchor.
	"earth_top": Color("#A9865F"),
	"earth_bevel": Color("#B4906A"),
	"earth_side": Color("#907050"),
	"earth_deep": Color("#6E5540"),
	"earth_clump": Color("#9A7A56"),
	# Stone family: cool grey-greens (wet PNW stone, not warm beige).
	"stone_light": Color("#B8B5A4"),
	"stone_medium": Color("#9D9C8D"),
	"stone_deep": Color("#7D7F76"),
	# Wood family: cedar tans, less yellow than the old cut-timber set.
	"wood_light": Color("#B69169"),
	"wood_medium": Color("#9A7A50"),
	"wood_deep": Color("#7B603F"),
	# Snow family: warm off-white tops over cool grey-green shadow sides —
	# never pure white, never a warm grey side.
	"snow_top": Color("#F0ECE0"),
	"snow_bevel": Color("#F4F1E7"),
	"snow_side": Color("#C7CBC1"),
	"snow_lump": Color("#E5E3D7"),
	# Sand family: pale dune tones pulled toward the muted #E4B886 path anchor.
	"sand_top": Color("#DFC594"),
	"sand_bevel": Color("#E7CFA1"),
	"sand_side": Color("#BEA377"),
	"sand_deep": Color("#977F5B"),
	"sand_patch": Color("#D3B884"),
	# Mud family: dark damp earth with a wet-patch accent.
	"mud_top": Color("#86684A"),
	"mud_bevel": Color("#8F7252"),
	"mud_wet": Color("#64503C"),
	# Brick family: muted terracotta, restrained toward the #B95C48 accent.
	"brick_light": Color("#BB8168"),
	"brick_medium": Color("#A56C55"),
	# Still-water family: desaturated deep teal (#257476 anchor), with the
	# bright shallow teal reserved for highlights rather than whole pools.
	"water_blue": Color("#3E8F88"),
	"water_deep": Color("#2B6F6B"),
	"lily_green": Color("#6E8C52"),
	# Blossom and autumn accents, muted to sit inside the moss register.
	"blossom_pink": Color("#CB969E"),
	"blossom_cream": Color("#E6DAC1"),
	"autumn_amber": Color("#BD8A57"),
	"autumn_rust": Color("#A9684B"),
	# Small whimsical accents (mushroom caps, buds).
	"accent_terracotta": Color("#BC7A5C"),
	"accent_cream": Color("#E4DBC5"),
}

static var _materials: Dictionary = {}


static func color(key: String) -> Color:
	assert(COLORS.has(key), "TileKitPalette: unknown colour key %s" % key)
	return COLORS[key]


## The one shared material per palette key. Solid colour, matte, opaque —
## the reference's softness comes from lighting on smooth geometry, not from
## maps or transparency.
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
