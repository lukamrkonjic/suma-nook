class_name SleepSystem
extends RefCounted

signal sleep_started(actor_id: String, instance_id: int)
signal sleep_ended(actor_id: String, instance_id: int)

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


func check(actor_id: String, instance_id: int) -> Dictionary:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return {"ok": false, "reason": "That shelter is no longer placed."}
	var structure: WorldGrid.StructureState = found["structure"]
	var definition: Variant = definitions.structure(structure.structure_id)
	if definition == null or definition.sleep == null:
		return {"ok": false, "reason": "You cannot sleep here."}
	var shelter_check: Dictionary = shelters.can_occupy(instance_id, actor_id)
	if not bool(shelter_check["ok"]):
		return shelter_check
	var state: Variant = shelters.state_for(instance_id)
	if (
		not state.occupants.has(actor_id)
		and state.occupants.size() >= definition.sleep.capacity
	):
		return {"ok": false, "reason": "Every sleeping place is occupied."}
	return {"ok": true, "reason": ""}


func begin(actor_id: String, instance_id: int) -> bool:
	if not bool(check(actor_id, instance_id)["ok"]):
		return false
	if not shelters.add_occupant(instance_id, actor_id):
		return false
	sleep_started.emit(actor_id, instance_id)
	return true


func end(actor_id: String, instance_id: int) -> void:
	shelters.remove_occupant(instance_id, actor_id)
	sleep_ended.emit(actor_id, instance_id)
