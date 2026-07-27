class_name ShelterPresenter
extends RefCounted
## Read-model adapter for HUD/tooltips. No scene nodes or gameplay mutations.

var grid: WorldGrid
var definitions
var shelters


func _init(
	world_grid: WorldGrid,
	camping_definitions,
	shelter_system
) -> void:
	grid = world_grid
	definitions = camping_definitions
	shelters = shelter_system


func read_model(instance_id: int) -> Dictionary:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return {}
	var structure: WorldGrid.StructureState = found["structure"]
	var definition: Variant = definitions.structure(structure.structure_id)
	var state: Variant = shelters.state_for(instance_id)
	if definition == null or state == null:
		return {}
	return {
		"instance_id": instance_id,
		"capacity": definition.shelter.capacity,
		"occupants": state.occupants.size(),
		"durability": state.durability,
		"construction_progress": state.construction_progress,
		"weather_resistance": definition.shelter.weather_resistance,
	}
