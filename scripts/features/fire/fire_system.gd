class_name FireSystem
extends RefCounted
## Authoritative per-structure burning state.
##
## State lives on WorldGrid.StructureState so it survives save/load and moving
## the same stable object instance.

signal burning_changed(instance_id: int, burning: bool)

const STATE_KEY := "fire_lit"

var registries: Registries
var grid: WorldGrid


func _init(content: Registries, world_grid: WorldGrid) -> void:
	registries = content
	grid = world_grid


func supports(instance_id: int) -> bool:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return false
	var structure: WorldGrid.StructureState = found["structure"]
	var definition := registries.structure(structure.structure_id)
	return definition != null and definition.has_capability("fire")


func is_burning(instance_id: int) -> bool:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return false
	var structure: WorldGrid.StructureState = found["structure"]
	var definition := registries.structure(structure.structure_id)
	if definition == null or not definition.has_capability("fire"):
		return false
	if structure.runtime_state.has(STATE_KEY):
		return bool(structure.runtime_state[STATE_KEY])
	return bool(definition.capability("fire").get("starts_lit", false))


func set_burning(instance_id: int, active: bool) -> bool:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return false
	var structure: WorldGrid.StructureState = found["structure"]
	var definition := registries.structure(structure.structure_id)
	if definition == null or not definition.has_capability("fire"):
		return false
	var previous := is_burning(instance_id)
	structure.runtime_state[STATE_KEY] = active
	if previous != active:
		burning_changed.emit(instance_id, active)
	return true


func toggle(instance_id: int) -> bool:
	if not supports(instance_id):
		return false
	return set_burning(instance_id, not is_burning(instance_id))
