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
	"tile_top": Color("#7BA845"),
	"tile_top_bevel": Color("#92C154"),
	"tile_side": Color("#537537"),
	"tile_lower": Color("#3F5C2C"),
	"dressing_light": Color("#8CB554"),
	"dressing_medium": Color("#78A247"),
	"dressing_dark": Color("#67903E"),
	"clutter_light": Color("#9CBE62"),
	"clutter_medium": Color("#7FA84C"),
	# Blades sit DEEPER than the top they grow from, so vegetation reads as
	# richer material, and the sunlit tone stays reserved for accents.
	"grass_primary": Color("#527D38"),
	"grass_secondary": Color("#659647"),
	"grass_root": Color("#3A5A2B"),
	# Moss family: deeper, cooler greens for forest-floor tops.
	"moss_top": Color("#689545"),
	"moss_bevel": Color("#78A751"),
	"moss_deep": Color("#456636"),
	"moss_clump": Color("#55823E"),
	# Earth family: cedar-and-loam browns; sides drop a full step so the
	# block reads as compacted soil under a lit top.
	"earth_top": Color("#B08355"),
	"earth_bevel": Color("#C29464"),
	"earth_side": Color("#7C5938"),
	"earth_deep": Color("#573F26"),
	"earth_clump": Color("#9D7546"),
	# Stone family: cool grey-greens (wet PNW stone, not warm beige).
	"stone_light": Color("#C1BCA4"),
	"stone_medium": Color("#9B9A80"),
	"stone_deep": Color("#6A6D5C"),
	# Wood family: cedar tans, less yellow than the old cut-timber set.
	"wood_light": Color("#C59B64"),
	"wood_medium": Color("#A07A47"),
	"wood_deep": Color("#6E522C"),
	# Snow family: warm off-white tops over cool grey-green shadow sides —
	# never pure white, never a warm grey side.
	"snow_top": Color("#F4EFDF"),
	"snow_bevel": Color("#FAF6EA"),
	"snow_side": Color("#B2BEB6"),
	"snow_lump": Color("#E9E6D5"),
	# Sand family: warm golden dunes with a clearly darker shaded side.
	"sand_top": Color("#ECC98A"),
	"sand_bevel": Color("#F6DA9F"),
	"sand_side": Color("#B4925C"),
	"sand_deep": Color("#87683C"),
	"sand_patch": Color("#DFBC79"),
	# Mud family: dark damp earth with a wet-patch accent.
	"mud_top": Color("#7E5F3E"),
	"mud_bevel": Color("#8D6C48"),
	"mud_wet": Color("#523D28"),
	# Brick family: confident terracotta, warm and toy-like.
	"brick_light": Color("#CC8560"),
	"brick_medium": Color("#AB6146"),
	# Still-water family: teal read as a VOLUME — a lighter lit surface over
	# a deep interior, with one bright key reserved for ripple crests and
	# the meniscus ring, never for whole pools.
	"water_blue": Color("#48A79B"),
	"water_deep": Color("#1F5F58"),
	"water_light": Color("#85D3C2"),
	"lily_green": Color("#6B934C"),
	# Blossom and autumn accents, muted to sit inside the moss register.
	"blossom_pink": Color("#E09AA8"),
	"blossom_cream": Color("#F1E3C6"),
	"autumn_amber": Color("#D19349"),
	"autumn_rust": Color("#B5623B"),
	# Small whimsical accents (mushroom caps, buds).
	"accent_terracotta": Color("#C97A54"),
	"accent_cream": Color("#EFE3C8"),
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
