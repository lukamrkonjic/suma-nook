class_name ProceduralCritterPlayer
extends Node3D
## The playable character as a generic ProceduralCreature. This node is a
## thin driver: it reads the CharacterBody3D's velocity and floor state and
## feeds the shared creature core; every visible proportion, color, and
## juice value lives in the creature's JSON definition.

const ProceduralCreatureScript := preload(
	"res://scripts/creatures/procedural_creature.gd"
)
const DEFAULT_DEFINITION := "res://data/creatures/nook_kit.json"

var _creature: Node3D
var _controller: CharacterBody3D
var _was_grounded := true
var _previous_velocity_y := 0.0


func build(definition_path := DEFAULT_DEFINITION) -> void:
	if is_instance_valid(_creature):
		return
	_creature = ProceduralCreatureScript.new() as Node3D
	_creature.name = "Creature"
	add_child(_creature)
	_creature.call("build_from_path", definition_path)


func definition_id() -> String:
	return String(_creature.call("definition_id"))


## Runtime wardrobe: swap the whole outfit (hat/shirt/pants/shoes/held)
## from a data/outfits JSON, e.g. the angler set when fishing starts.
func equip_outfit(outfit_path: String) -> void:
	if is_instance_valid(_creature):
		_creature.call("set_outfit", outfit_path)


func clear_outfit() -> void:
	if is_instance_valid(_creature):
		_creature.call("clear_outfit")


## World-space tip of the held equipable (rod point) for line effects.
func held_tip_world() -> Vector3:
	if is_instance_valid(_creature):
		var current_outfit: Variant = _creature.call("outfit")
		if current_outfit is Node3D and is_instance_valid(current_outfit):
			return (current_outfit as Node3D).call("held_tip_world")
	return global_position


func foot_world_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	if is_instance_valid(_creature):
		for foot_position in _creature.call("foot_world_positions"):
			result.append(foot_position as Vector3)
	return result


func _physics_process(delta: float) -> void:
	if not visible or not is_instance_valid(_creature):
		return
	if _controller == null:
		_controller = get_parent().get_parent() as CharacterBody3D
	if _controller == null:
		return
	var local_velocity := global_basis.inverse() * _controller.velocity
	var grounded := _is_grounded()
	if not _was_grounded and grounded:
		_creature.call(
			"notify_landed", clampf(-_previous_velocity_y / 6.0, 0.28, 1.0)
		)
	if _was_grounded and not grounded and local_velocity.y > 0.0:
		_creature.call("notify_takeoff")
	_was_grounded = grounded
	_previous_velocity_y = local_velocity.y

	var state := ProceduralCreature.MotionState.new()
	state.local_velocity = local_velocity
	state.grounded = grounded
	_creature.call("advance", delta, state)


func _is_grounded() -> bool:
	return (
		_controller.is_on_floor()
		or bool(_controller.get_meta("procedural_review_grounded", false))
	)
