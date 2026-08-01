class_name FishingKeepsakeService
extends RefCounted
## Applies Keepsake behavior through the existing world-modification surface.
## The reward generator only ever grants a Keepsake id; the effects live here,
## outside the reward pipeline.

signal keepsake_activated(keepsake_id: String)

## The Growth Keepsake lets appropriate trees shift between existing authored
## variants — it reuses the placed-structure architecture, no upgrade tree.
const TREE_GROWTH_CYCLE: Array[String] = [
	"struct_pine_young",
	"struct_pine",
	"struct_pine_tall",
]

var registries: Registries
var grid: WorldGrid

var activated: Dictionary = {}   # keepsake_id -> true


func _init(regs: Registries, world_grid: WorldGrid) -> void:
	registries = regs
	grid = world_grid


func activate(keepsake_id: String) -> bool:
	if registries.keepsake(keepsake_id) == null:
		return false
	activated[keepsake_id] = true
	keepsake_activated.emit(keepsake_id)
	return true


func is_effect_active(effect_id: String) -> bool:
	for keepsake_id: String in activated:
		var definition := registries.keepsake(keepsake_id)
		if definition != null and definition.effect_id == effect_id:
			return true
	return false


func can_cycle_tree_variant(structure_id: String) -> bool:
	return is_effect_active("growth") and TREE_GROWTH_CYCLE.has(structure_id)


## Shifts a placed tree to its next authored size variant in place.
func cycle_tree_variant(instance_id: int) -> bool:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return false
	var structure: WorldGrid.StructureState = found["structure"]
	if not can_cycle_tree_variant(structure.structure_id):
		return false
	var index := TREE_GROWTH_CYCLE.find(structure.structure_id)
	structure.structure_id = TREE_GROWTH_CYCLE[
		(index + 1) % TREE_GROWTH_CYCLE.size()
	]
	grid.slot_changed.emit(found["coord"], int(found["elevation"]))
	return true


func clear() -> void:
	activated.clear()


func to_save_dict() -> Dictionary:
	return {"activated": activated.keys()}


func from_save_dict(data: Dictionary) -> void:
	activated.clear()
	for raw_id in data.get("activated", []):
		var keepsake_id := String(raw_id)
		if registries.keepsake(keepsake_id) != null:
			activated[keepsake_id] = true
