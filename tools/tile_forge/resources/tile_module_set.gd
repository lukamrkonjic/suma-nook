@tool
class_name TileModuleSet
extends Resource
## A curated family of interchangeable detail modules — "short grass clumps",
## "pebbles", "rubble". A detail rule picks from a set; it never names a mesh.
##
## Sets are the unit of art direction. Every member must be the same kind of
## object at the same visual scale, so a placer can swap one for another
## without changing the composition's read.

@export var set_id := ""
@export var display_name := ""
## Family folder under tools/tile_forge/modules/ this set draws from. Used by
## the loader's cache key and by the module-library report.
@export var family := "grass"
@export var modules: Array[TileModuleEntry] = []

@export_group("Set-wide limits")
## Extra separation multiplier applied on top of each module's footprint. Above
## 1.0 the field opens up; below 1.0 modules are allowed to nestle.
@export_range(0.5, 3.0, 0.05) var separation_scale := 1.25
## Cap on how many times one module may repeat inside a single tile. This is
## the direct defence against "obvious module repetition" in review.
@export_range(1, 12, 1) var max_repeats_per_module := 3


func is_empty() -> bool:
	return modules.is_empty()


func weights() -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for entry in modules:
		result.append(entry.weight if entry != null else 0.0)
	return result


## Weighted pick honouring `max_repeats_per_module`. `used` counts placements
## already made this tile, keyed by module index.
func pick(rng: RandomNumberGenerator, used: Dictionary) -> int:
	var available := weights()
	for index in available.size():
		if int(used.get(index, 0)) >= max_repeats_per_module:
			available[index] = 0.0
	var total := 0.0
	for w in available:
		total += w
	if total <= 0.0:
		# Every module hit its repeat cap. Reset rather than fail: the caller's
		# count is simply larger than the set can vary across.
		available = weights()
	return TileSeedUtil.weighted_index(rng, available)


func entry(index: int) -> TileModuleEntry:
	if index < 0 or index >= modules.size():
		return null
	return modules[index]


## Largest footprint in the set. Used to size border exclusion up front.
func max_footprint_radius() -> float:
	var result := 0.0
	for module in modules:
		if module != null:
			result = maxf(result, module.footprint_radius * module.scale_range.y)
	return result


func max_height() -> float:
	var result := 0.0
	for module in modules:
		if module != null:
			result = maxf(result, module.height * module.scale_range.y)
	return result
