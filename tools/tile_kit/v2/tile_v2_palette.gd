class_name TileV2Palette
extends RefCounted
## Tile Art V2 colour roles backed by Suma's canonical design system.
##
## Same contract as TileKitPalette — builders ask for materials by key and
## never construct colours — but V2 keys resolve to the `tilev2_*` tokens:
## warm muted families with hue-shifted shadow steps (olive moss, butter and
## ochre sand, soft off-white snow, warm greys) instead of the V1 lime bevels
## and red sand seams. Each material family exposes 3–5 closely controlled
## roles; a recipe picks from ONE family plus the shared neutrals.

const DESIGN_SYSTEM: PaletteDefinition = preload(
	"res://assets/palettes/gg_material_palette.tres"
)

## Every key a V2 recipe may reference. Value = design-system token.
const COLORS := {
	"background": "tilekit_background",
	# Moss family — olive, never fluorescent.
	"moss_top": "tilev2_moss_top",
	"moss_light": "tilev2_moss_light",
	"moss_shadow": "tilev2_moss_shadow",
	"moss_deep": "tilev2_moss_deep",
	"moss_substrate": "tilev2_moss_substrate",
	"moss_side": "tilev2_moss_side",
	# Forest floor family — dark warm soil under ochre bark.
	"forest_soil": "tilev2_forest_soil",
	"forest_soil_light": "tilev2_forest_soil_light",
	"forest_soil_shadow": "tilev2_forest_soil_shadow",
	"forest_bark": "tilev2_forest_bark",
	"forest_bark_light": "tilev2_forest_bark_light",
	"forest_bark_deep": "tilev2_forest_bark_deep",
	"forest_side": "tilev2_forest_side",
	"forest_deep": "tilev2_forest_deep",
	# Sand family — butter and ochre, warm brown sides, no red seams.
	"sand_top": "tilev2_sand_top",
	"sand_high": "tilev2_sand_high",
	"sand_shadow": "tilev2_sand_shadow",
	"sand_side": "tilev2_sand_side",
	"sand_deep": "tilev2_sand_deep",
	# Snow family — warm off-white cap over a muted earth body.
	"snow_top": "tilev2_snow_top",
	"snow_high": "tilev2_snow_high",
	"snow_shadow": "tilev2_snow_shadow",
	"snow_body": "tilev2_snow_body",
	"snow_body_deep": "tilev2_snow_body_deep",
	# Rock family — warm greys, one coherent slab family.
	"rock_slab": "tilev2_rock_slab",
	"rock_slab_light": "tilev2_rock_slab_light",
	"rock_slab_warm": "tilev2_rock_slab_warm",
	"rock_groove": "tilev2_rock_groove",
	"rock_side": "tilev2_rock_side",
	"rock_deep": "tilev2_rock_deep",
	"rock_gravel": "tilev2_rock_gravel",
}

static var _tile_material: StandardMaterial3D = null
## Preview override: when set, tile_material() returns the override — the
## silhouette / value-study modes of the V2 editor and review rig.
static var _override_material: Material = null


static func color(key: String) -> Color:
	assert(COLORS.has(key), "TileV2Palette: unknown colour key %s" % key)
	return DESIGN_SYSTEM.color(COLORS[key])


## The one shared clay material for every V2 tile: vertex colours carry the
## paint, the material stays fully rough with restrained specular — the
## sculpt does the reading; the surface must never go shiny plastic.
static func tile_material() -> Material:
	if _override_material != null:
		return _override_material
	if _tile_material == null:
		_tile_material = StandardMaterial3D.new()
		_tile_material.resource_name = "tilev2_clay"
		_tile_material.vertex_color_use_as_albedo = true
		_tile_material.vertex_color_is_srgb = true
		_tile_material.albedo_color = Color.WHITE
		_tile_material.metallic = 0.0
		_tile_material.roughness = 1.0
		_tile_material.metallic_specular = 0.10
	return _tile_material


## Install/clear a global preview override (silhouette and value modes).
static func set_override_material(override: Material) -> void:
	_override_material = override
