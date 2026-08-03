class_name ProceduralCritterPlayer
extends Node3D
## The playable character as a generic ProceduralCreature. This node is a
## thin driver: it reads the CharacterBody3D's velocity and floor state and
## feeds the shared creature core; every visible proportion, color, and
## juice value lives in the creature's JSON definition.

const ProceduralCreatureScript := preload(
	"res://scripts/creatures/procedural_creature.gd"
)
const DEFAULT_DEFINITION := "res://data/creatures/islander.json"

## Re-broadcast of the creature action engine's phase events so PlayerVisual
## can keep its legacy animation_event contract.
signal action_event(action_name: String, event_name: String)

var _creature: Node3D
var _controller: CharacterBody3D
var _was_grounded := true
var _previous_velocity_y := 0.0
var _previous_controller_yaw := 0.0
var _has_previous_controller_yaw := false


func build(definition_path := DEFAULT_DEFINITION) -> void:
	if is_instance_valid(_creature):
		return
	_creature = ProceduralCreatureScript.new() as Node3D
	_creature.name = "Creature"
	add_child(_creature)
	_creature.call("build_from_path", definition_path)
	_creature.connect(
		"action_event",
		func(action_name: String, event_name: String) -> void:
			action_event.emit(action_name, event_name)
	)


## Action layer pass-throughs (chop, mine, fish_cast, ... from
## data/creature_actions.json). "idle"/"walk" resolve to stopping.
func play_action(action_name: String, seconds := -1.0) -> void:
	if not is_instance_valid(_creature):
		return
	if action_name == "idle" or action_name == "walk":
		_creature.call("stop_action")
	else:
		_creature.call("play_action", action_name, seconds)


func stop_action() -> void:
	if is_instance_valid(_creature):
		_creature.call("stop_action")


func action_impact_ratio(action_name: String, fallback: float) -> float:
	if is_instance_valid(_creature):
		return float(_creature.call("action_impact_ratio", action_name, fallback))
	return fallback


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
	var controller_yaw := _controller.global_rotation.y
	if _has_previous_controller_yaw:
		state.yaw_rate = angle_difference(
			_previous_controller_yaw, controller_yaw
		) / maxf(delta, 0.0001)
	_previous_controller_yaw = controller_yaw
	_has_previous_controller_yaw = true
	_creature.call("advance", delta, state)


func _is_grounded() -> bool:
	return (
		_controller.is_on_floor()
		or bool(_controller.get_meta("procedural_review_grounded", false))
	)
