@tool
class_name TileBaseProfile
extends Resource
## Describes the structural block under the generated top.
##
## Suma already ships two canonical bases (docs/TILE_AUTHORING.md), and the
## right answer for almost every recipe is to REFERENCE one rather than
## generate another. `mode` defaults accordingly: the Forge normally produces
## only the useful top assembly and lets data/tiles.json compose it with the
## shared base, exactly like the hand-authored sand and snow surfaces do.
##
## GENERATED exists for a genuinely new depth contract (a standardized planter
## bed, a sunken pool) and still obeys the same footprint and stacking rules.

@export var mode: TileForgeConstants.BaseMode = TileForgeConstants.BaseMode.SHARED_STANDARD

@export_group("Footprint")
## LIVE metres. Overriding these is almost always a mistake — the grid is
## square and every neighbour assumes it.
@export var width := TileForgeConstants.LIVE_TILE_SIZE
@export var depth := TileForgeConstants.LIVE_TILE_SIZE

@export_group("Vertical")
## Where the generated top assembly starts, metres. For SHARED_STANDARD this
## is the shipped -0.055 seam; for SHARED_DEEP_RECESS it is -0.18.
@export var seam_y := TileForgeConstants.SEAM_STANDARD
## Bottom of a GENERATED block. Must stay on the 0.5 m stacking step.
@export var bottom_y := -TileForgeConstants.BLOCK_DEPTH
## Nominal top elevation of the finished surface, metres. The heightfield
## modulates around this.
@export var top_elevation := 0.0

@export_group("Treatment")
## Generate the short vertical skirt from `seam_y` up to the surface boundary
## height. Required whenever the surface sits above the seam, or a stacked
## neighbour shows daylight through the gap.
@export var generate_side_wall := true
## Close the underside. Only needed for a GENERATED base or a free-standing
## preview; a shared base already has one.
@export var generate_underside := false
## Soft chamfer along the top outer edge, LIVE metres. Keep it small: the
## reference silhouette is a crisp block with a catchlight on the corner, not a
## rounded pillow. 0 disables it.
@export_range(0.0, 0.06, 0.001) var bevel_width := 0.0
@export_range(1, 3, 1) var bevel_segments := 1

@export_group("Material")
@export var side_slot := TileForgeConstants.SLOT_SIDE
@export var underside_slot := TileForgeConstants.SLOT_UNDERSIDE


func half_extent() -> float:
	return width * 0.5


func uses_shared_base() -> bool:
	return (
		mode == TileForgeConstants.BaseMode.SHARED_STANDARD
		or mode == TileForgeConstants.BaseMode.SHARED_DEEP_RECESS
	)


## Asset id of the shared base this profile expects data/tiles.json to compose
## the generated top with. Empty for GENERATED/NONE.
func shared_base_asset() -> String:
	match mode:
		TileForgeConstants.BaseMode.SHARED_STANDARD:
			return TileForgeConstants.BASE_STANDARD_ASSET
		TileForgeConstants.BaseMode.SHARED_DEEP_RECESS:
			return TileForgeConstants.BASE_DEEP_RECESS_ASSET
	return ""


## The seam the shared base actually ends at, so a recipe cannot silently
## disagree with the shipped block.
func canonical_seam() -> float:
	match mode:
		TileForgeConstants.BaseMode.SHARED_STANDARD:
			return TileForgeConstants.SEAM_STANDARD
		TileForgeConstants.BaseMode.SHARED_DEEP_RECESS:
			return TileForgeConstants.SEAM_DEEP_RECESS
	return seam_y
