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
	# Grass-family tile shell (the approved reference values).
	"tile_top": Color("#C0CD78"),
	"tile_top_bevel": Color("#C9D281"),
	"tile_side": Color("#849140"),
	"tile_lower": Color("#718138"),
	"dressing_light": Color("#B9C771"),
	"dressing_medium": Color("#B3C26A"),
	"dressing_dark": Color("#ABBA5C"),
	"clutter_light": Color("#C9D281"),
	"clutter_medium": Color("#B9C771"),
	"grass_primary": Color("#9EAF51"),
	"grass_secondary": Color("#8FA145"),
	"grass_root": Color("#718138"),
	# Moss family: deeper, cooler greens for forest-floor tops.
	"moss_top": Color("#93A75B"),
	"moss_bevel": Color("#9DB065"),
	"moss_deep": Color("#6C7F3E"),
	"moss_clump": Color("#7E9448"),
	# Earth family: warm clay browns for soil, mulch, and mud beds.
	"earth_top": Color("#B08D5F"),
	"earth_bevel": Color("#BC9968"),
	"earth_side": Color("#8A6B45"),
	"earth_deep": Color("#75593A"),
	"earth_clump": Color("#9C7B50"),
	# Stone family: warm greys for pebbles, slabs, and paving.
	"stone_light": Color("#C6BFB2"),
	"stone_medium": Color("#AFA795"),
	"stone_deep": Color("#8E8674"),
	# Wood family: cut-timber tans for chips, twigs, and planks.
	"wood_light": Color("#C2A06A"),
	"wood_medium": Color("#A98652"),
	"wood_deep": Color("#8C6C40"),
	# Snow family: soft warm whites.
	"snow_top": Color("#F2EFE8"),
	"snow_bevel": Color("#F7F4EE"),
	"snow_side": Color("#D9D4C8"),
	"snow_lump": Color("#EDE9E0"),
	# Sand family: pale warm dune tones.
	"sand_top": Color("#E3CC9A"),
	"sand_bevel": Color("#EBD6A8"),
	"sand_side": Color("#C3A778"),
	"sand_deep": Color("#A78C60"),
	"sand_patch": Color("#D9C08C"),
	# Mud family: dark damp earth with a wet-patch accent.
	"mud_top": Color("#8F6F4C"),
	"mud_bevel": Color("#997A55"),
	"mud_wet": Color("#6E5238"),
	# Brick family: warm terracotta paving.
	"brick_light": Color("#C89070"),
	"brick_medium": Color("#B57C5C"),
	# Still-water family for basin pools.
	"water_blue": Color("#8FB5AC"),
	"water_deep": Color("#7BA39A"),
	"lily_green": Color("#7E9C4C"),
	# Blossom and autumn accents.
	"blossom_pink": Color("#D9A0A8"),
	"blossom_cream": Color("#E9DAC0"),
	"autumn_amber": Color("#C68A4F"),
	"autumn_rust": Color("#B06B45"),
	# Small whimsical accents (mushroom caps, buds).
	"accent_terracotta": Color("#C97F5A"),
	"accent_cream": Color("#E8DDC4"),
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
