@tool
class_name TileDetailRule
extends Resource
## One scattered-module pass: "5–9 broad grass clumps in three groups".
##
## A detail rule owns WHAT is placed (module set), WHERE (composition pattern
## plus mask), HOW MUCH (count range, separation), and HOW IT IS RENDERED
## (output mode). It never owns the surface height — it samples it — so a
## detail can never float above or sink into the top it sits on.

@export var rule_name := "details"
@export var enabled := true
## Registry id of the generator that interprets this rule. Almost always one of
## clump_field / pebble_field / rubble_field, but a new family only needs a new
## id here.
@export var generator_id := "clump_field"

@export_group("Content")
@export var module_set: TileModuleSet
@export var composition: TileCompositionPattern

@export_group("Count")
@export_range(0, 64, 1) var min_count := 4
@export_range(0, 64, 1) var max_count := 8
## Added to the recipe seed so two rules on one tile never correlate.
@export var seed_offset := 0

@export_group("Region")
## Restrict placement to where these shapes are active. Empty = whole tile.
@export var region_mask: Array[TileShapePrimitive] = []
@export_range(0.0, 1.0, 0.01) var region_threshold := 0.25
@export var region_invert := false
## Modules must keep this far from the tile boundary, in LIVE metres, measured
## from the module's own footprint edge. Modules tagged "edge_safe" ignore it.
@export_range(0.0, 0.4, 0.005) var border_exclusion := 0.06
## Minimum gap between two module footprints, LIVE metres. Negative values let
## a family nestle — correct for straw and leaf litter, wrong for stones.
@export_range(-0.2, 0.5, 0.005) var min_separation := 0.02
## Declares that this family is MEANT to interleave, so the validator does not
## report its overlaps as intersections. Use it honestly: it silences a real
## check, and everything except matted litter should leave it off.
@export var permit_intersection := false

@export_group("Transform")
@export var scale_range := Vector2(0.9, 1.15)
## Lifted above the sampled surface height. Normally 0 — use the module's own
## `sink` to bed it in instead.
@export var height_offset := 0.0
@export_range(0.0, 25.0, 0.5) var max_tilt_deg := 5.0
@export var rotation_mode: TileForgeConstants.RotationMode = TileForgeConstants.RotationMode.FREE_YAW
## Align the module's up axis to the surface normal. Right for pebbles resting
## on a slope; wrong for grass, which grows vertically regardless.
@export var align_to_surface_normal := false
@export_range(0.0, 1.0, 0.01) var normal_align_strength := 0.6

@export_group("Material")
## Relative weights for detail_a / detail_b / detail_c. Variation picks an
## approved slot; it never blends or jitters a colour.
@export var material_variant_weights := PackedFloat32Array([1.0, 0.55, 0.25])

@export_group("Output")
@export var output: TileForgeConstants.DetailOutput = TileForgeConstants.DetailOutput.MERGED_STATIC_MESH
## Give these modules their own collision. Grass, straw, leaves, and small
## pebbles must leave this off — they are visual only.
@export var detail_collision := false
## Beyond this distance the detail may be dropped by a detail-distance policy.
## 0 means "always keep".
@export var lod_distance := 0.0
## Modules smaller than this (LIVE metres of height) are the first to be culled
## by the LOD policy.
@export var lod_min_height := 0.0


func count_for(rng: RandomNumberGenerator) -> int:
	var low := mini(min_count, max_count)
	var high := maxi(min_count, max_count)
	if high <= low:
		return low
	return rng.randi_range(low, high)


## Region acceptance at a normalized tile coordinate.
func region_allows(u: float, v: float) -> bool:
	if region_mask.is_empty():
		return not region_invert
	var strongest := 0.0
	for shape in region_mask:
		if shape != null:
			strongest = maxf(strongest, absf(shape.weight(u, v)))
	var inside := strongest >= region_threshold
	return not inside if region_invert else inside


func is_valid() -> bool:
	return (
		enabled
		and module_set != null
		and not module_set.is_empty()
		and max_count > 0
	)
