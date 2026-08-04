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
const MOSS_VELVET_SHADER: Shader = preload(
	"res://assets/materials/reworked/gg_moss_velvet.gdshader"
)
const TUFT_WIND_SHADER: Shader = preload(
	"res://assets/materials/reworked/gg_tuft_wind.gdshader"
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
	# GG-construction grass: one warm chartreuse family. The reference keeps
	# near-equal top/side ALBEDO and lets its harder sun darken the walls;
	# Suma's soft daylight doesn't deliver that step, so the side and lower
	# tokens carry it explicitly (side ≈ −20%, lower ≈ −30% of top — the
	# audit's terrain-side rule). The tuft tint sits a step deeper than the
	# top so sprite tips melt into the plane while their gradient bases
	# anchor them. Values are Suma picks, not sampled pixels.
	"grass_gg_top": "tilekit_grass_gg_top",
	"grass_gg_bevel": "tilekit_grass_gg_top",
	"grass_gg_side": "tilekit_grass_gg_side",
	"grass_gg_lower": "tilekit_grass_gg_lower",
	"grass_gg_tuft": "tilekit_grass_gg_tuft",
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
	# The contour tile is intentionally more olive than the vegetation ramp.
	# Broad smooth lighting gradients carry its identity; a dedicated role keeps
	# that quieter clay body from recolouring every existing moss asset.
	"moss_contour_top": "earthy_olive",
	"moss_contour_bevel": "earthy_olive",
	"moss_contour_side": "earth_shadow",
	"moss_contour_lower": "earth_deep",
	# Plush clay blanket: close moss values separate the puffs through broad
	# lighting without returning to neon spots or hard high-contrast blobs.
	"moss_plush_base": "leaf_olive",
	"moss_plush_bevel": "leaf_olive",
	"moss_plush_edge": "olive_shadow",
	"moss_plush_body": "leaf_olive",
	"moss_plush_light": "moss_primary",
	"moss_plush_deep": "olive_shadow",
	"moss_plush_soil_side": "earth_shadow",
	"moss_plush_soil_lower": "earth_deep",
	# Mossy garden ground uses a deeper, quieter soil cake than the standalone
	# dirt tile so exposed channels support the greenery instead of reading as
	# a bright orange plastic board.
	"moss_ground_soil_top": "earth_shadow",
	"moss_ground_soil_gradient": "earth_shadow",
	"moss_ground_soil_bevel": "earth_shadow",
	"moss_ground_soil_side": "earth_shadow",
	"moss_ground_soil_lower": "earth_deep",
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

## Generated sprite sheets used by the sprite-card detail layers. Every entry
## is an original Suma texture authored by art_source/sprites/*.py — white
## luminance with a baked top-to-base gradient, tinted by a palette colour at
## material level, exactly like the audited reference technique.
const SPRITE_TEXTURES := {
	"tuft_sprout": "res://assets/textures/tile_kit/tuft_sprout.png",
}

static var _materials: Dictionary = {}
static var _sprite_materials: Dictionary = {}


static func color(key: String) -> Color:
	assert(COLORS.has(key), "TileKitPalette: unknown colour key %s" % key)
	return DESIGN_SYSTEM.color(COLORS[key])


## The one shared material per palette key. Solid colour and matte across the
## board, with two narrow material exceptions: still water gets restrained
## translucency, and the dedicated contour-moss top gets a matte velvet nap.
## Both remain palette-bound; neither introduces image texture or colour noise.
static func material(key: String) -> Material:
	if _materials.has(key):
		return _materials[key]
	if key in ["moss_contour_top", "moss_plush_base", "moss_plush_body",
			"moss_plush_light", "moss_plush_deep"]:
		var velvet := ShaderMaterial.new()
		velvet.resource_name = "tilekit_%s" % key
		velvet.shader = MOSS_VELVET_SHADER
		velvet.set_shader_parameter("albedo", color(key))
		velvet.set_shader_parameter("roughness_val", 0.98)
		velvet.set_shader_parameter("specular_val", 0.10)
		velvet.set_shader_parameter("nap_strength", 0.012)
		velvet.set_shader_parameter("nap_scale", 1.65)
		velvet.set_shader_parameter("nap_speed", 0.075)
		velvet.set_shader_parameter("rim_amount", 0.16)
		velvet.set_shader_parameter("rim_tint_amount", 0.72)
		_materials[key] = velvet
		return velvet
	var result := StandardMaterial3D.new()
	result.resource_name = "tilekit_%s" % key
	result.albedo_color = color(key)
	result.metallic = 0.0
	result.roughness = 0.9
	result.metallic_specular = 0.2
	result.vertex_color_use_as_albedo = false
	if key in ["moss_ground_soil_top", "moss_ground_soil_gradient",
			"moss_ground_soil_bevel",
			"moss_ground_soil_side", "moss_ground_soil_lower"]:
		result.roughness = 0.98
		result.metallic_specular = 0.08
	if key == "moss_ground_soil_gradient":
		# The reveal meshes carry an authored moss→earth ramp in vertex colour.
		# White albedo preserves that exact palette-bound gradient. Palette values
		# are display-space swatches, so request the same sRGB decode that regular
		# material albedo colours receive; otherwise the ramp is washed toward white.
		result.albedo_color = Color.WHITE
		result.vertex_color_use_as_albedo = true
		result.vertex_color_is_srgb = true
	if key in ["water_blue", "water_light"]:
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		result.albedo_color.a = 0.86
		# Soft sheen only: a tight glossy highlight interpolates visibly
		# across the water plane's long fan triangles and draws an X.
		result.roughness = 0.34
		result.metallic_specular = 0.32
	_materials[key] = result
	return result


## The shared material for one (sprite, tint) pair: the sprite's white
## gradient carries form, the palette tint carries ALL hue — the audited
## reference card technique — plus a gentle vertex-stage wind sway (tips
## lean, roots pinned, world-phased so the whole meadow rides one wave).
## Alpha scissor + alpha-to-coverage rides the project's MSAA for soft
## silhouettes without transparency sorting; specular is fully disabled so
## cards can never catch a plastic glint. Culling stays ON: the card
## builder emits wound front/back pairs, which avoids Godot's back-face
## normal flip (it shaded half of every pair as if lit from below).
static func sprite_material(sprite: String, tint_key: String) -> Material:
	var cache_key := "%s|%s" % [sprite, tint_key]
	if _sprite_materials.has(cache_key):
		return _sprite_materials[cache_key]
	assert(SPRITE_TEXTURES.has(sprite),
		"TileKitPalette: unknown sprite %s" % sprite)
	var result := ShaderMaterial.new()
	result.resource_name = "tilekit_sprite_%s_%s" % [sprite, tint_key]
	result.shader = TUFT_WIND_SHADER
	result.set_shader_parameter("albedo_tex", load(SPRITE_TEXTURES[sprite]))
	result.set_shader_parameter("tint", color(tint_key))
	_sprite_materials[cache_key] = result
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
