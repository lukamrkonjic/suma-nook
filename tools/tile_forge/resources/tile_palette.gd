@tool
class_name TilePalette
extends Resource
## Binds the Forge's abstract material slots to Suma's semantic palette keys.
##
## A recipe never names a colour. It names a SLOT ("top_primary"). This
## resource maps that slot to a key in assets/palettes/gg_material_palette.tres,
## and MaterialLibrary turns the key into the one shared material every other
## object in the game already uses. A palette edit therefore re-skins generated
## tiles and hand-authored props together, which is the whole reason the
## semantic layer exists.
##
## Rules the art direction depends on:
##   - a palette holds a FEW deliberate entries, not a gradient;
##   - variation picks a different approved entry, never a jittered RGB value;
##   - roughness/specular are shared so one tile cannot shade unlike its
##     neighbour.

@export var palette_id := ""
@export var display_name := ""

@export_group("Top surface")
## The dominant colour of the tile top. Broad, matte, unmodulated.
@export var top_primary := "grass_primary"
## The second broad region. Keep it close in value to top_primary — the
## reference look is two restrained neighbours, not a contrast pair.
@export var top_secondary := "grass_secondary"
## Small deliberate lift, used sparingly on crests and detail highlights.
@export var accent := "grass_sunlit"
## Used where a form self-shadows (basin floors, board gaps, inset rims).
@export var shadow := "grass_shade"

@export_group("Structure")
## Structural side wall. Matches the shared base so a generated skirt cannot
## disagree with tile_layer_base_standard.
@export var side := "earth_mid"
@export var underside := "earth_deep"
## Recess/cavity interior.
@export var inset := "earth_shadow"

@export_group("Water")
@export var water := "water"

@export_group("Detail modules")
## Approved colours for scattered modules. Variation SELECTS from this list;
## it never invents a colour between entries.
@export var detail_a := "grass_lush"
@export var detail_b := "grass_tuft"
@export var detail_c := "moss_primary"

@export_group("Derived tones")
## Compute the side wall from the top colour using the art profile's darkening
## rule instead of taking it from an unrelated palette key.
##
## This is the fix for the single worst colour failure in the first pass: a
## green top on a brown wall read as two objects stacked, not as one tile. The
## derived value keeps the hue and drops only 10-18% of the value, which is what
## makes a tile read as one carved piece. A palette edit still re-skins it,
## because the derivation runs at bake time from this palette's own top colour.
@export var derive_side_from_top := true
## Same for the chamfer rim, lightened rather than darkened so the top edge
## catches a real highlight.
@export var derive_rim_from_top := true
@export_range(0.0, 0.4, 0.01) var rim_lighten := 0.10

@export_group("Shading")
## Terrain is matte. Values below ~0.8 start producing a plastic highlight
## that breaks the miniature-collection read.
@export_range(0.4, 1.0, 0.01) var roughness := 0.94
@export_range(0.0, 1.0, 0.01) var specular := 0.18
## Ordinary terrain is never metallic. Kept exposed only so a deliberate
## metal panel recipe does not need a second palette class.
@export_range(0.0, 1.0, 0.01) var metallic := 0.0


## Semantic palette key bound to a slot name, or "" when the slot is unused.
func key_for_slot(slot: String) -> String:
	match slot:
		TileForgeConstants.SLOT_TOP_PRIMARY:
			return top_primary
		TileForgeConstants.SLOT_TOP_SECONDARY:
			return top_secondary
		TileForgeConstants.SLOT_ACCENT:
			return accent
		TileForgeConstants.SLOT_SHADOW:
			return shadow
		TileForgeConstants.SLOT_SIDE:
			return side
		TileForgeConstants.SLOT_UNDERSIDE:
			return underside
		TileForgeConstants.SLOT_INSET:
			return inset
		TileForgeConstants.SLOT_WATER:
			return water
		TileForgeConstants.SLOT_DETAIL_A:
			return detail_a
		TileForgeConstants.SLOT_DETAIL_B:
			return detail_b
		TileForgeConstants.SLOT_DETAIL_C:
			return detail_c
	return ""


## Slots that actually resolve to something, used by validation and reports.
func active_slots() -> PackedStringArray:
	var result := PackedStringArray()
	for slot in TileForgeConstants.ALL_SLOTS:
		if key_for_slot(slot) != "":
			result.append(slot)
	return result


## Deterministically choose one of the detail slots by approved weight. This is
## how a scattered field gets colour variety without any RGB jitter.
func pick_detail_slot(rng: RandomNumberGenerator, weights: PackedFloat32Array) -> String:
	var slots := PackedStringArray([
		TileForgeConstants.SLOT_DETAIL_A,
		TileForgeConstants.SLOT_DETAIL_B,
		TileForgeConstants.SLOT_DETAIL_C,
	])
	var available := PackedStringArray()
	var available_weights := PackedFloat32Array()
	for index in slots.size():
		if key_for_slot(slots[index]) == "":
			continue
		available.append(slots[index])
		available_weights.append(
			weights[index] if index < weights.size() else 1.0
		)
	if available.is_empty():
		return TileForgeConstants.SLOT_TOP_PRIMARY
	return available[TileSeedUtil.weighted_index(rng, available_weights)]
