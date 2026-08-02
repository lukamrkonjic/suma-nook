class_name ProceduralOwlMascot
extends Node3D
## The bird mascot as a generic ProceduralCreature (flyer plan). This node is
## a thin driver: it converts PigeonMascotController movement states into the
## creature core's MotionState plus impulse notifications. The owl itself —
## proportions, palette, wings, tufts, juice — is entirely JSON.

const ProceduralCreatureScript := preload(
	"res://scripts/creatures/procedural_creature.gd"
)
const DEFAULT_DEFINITION := "res://data/creatures/nook_owl.json"
const State = PigeonMascotController.MovementState

const GROUND_STATES: Array = [State.IDLE, State.WALKING, State.PUSHED]
const FLIGHT_STATES: Array = [
	State.RECOVERING, State.TAKING_OFF, State.FLYING, State.LANDING
]

var _creature: Node3D
var _controller: Node
var _previous_state := State.DORMANT
var _previous_root_position := Vector3.ZERO
var _previous_root_yaw := 0.0
var _has_previous_root_sample := false


func build(definition_path := DEFAULT_DEFINITION) -> void:
	if is_instance_valid(_creature):
		return
	_creature = ProceduralCreatureScript.new() as Node3D
	_creature.name = "Creature"
	add_child(_creature)
	_creature.call("build_from_path", definition_path)


func setup(controller: Node) -> void:
	_controller = controller


func definition_id() -> String:
	return String(_creature.call("definition_id"))


func _physics_process(delta: float) -> void:
	if not visible or not is_instance_valid(_creature) or _controller == null:
		return
	var root := get_parent() as Node3D
	if root == null:
		return
	if not _has_previous_root_sample:
		_previous_root_position = root.global_position
		_previous_root_yaw = root.rotation.y
		_has_previous_root_sample = true

	var mascot_state := int(_controller.get("movement_state"))
	if mascot_state != _previous_state:
		_on_state_changed(_previous_state, mascot_state)
		_previous_state = mascot_state

	var velocity := (
		(root.global_position - _previous_root_position) / maxf(delta, 0.001)
	)
	var yaw_rate := (
		wrapf(root.rotation.y - _previous_root_yaw, -PI, PI) / maxf(delta, 0.001)
	)
	_previous_root_position = root.global_position
	_previous_root_yaw = root.rotation.y

	var state := ProceduralCreature.MotionState.new()
	state.local_velocity = root.global_basis.inverse() * velocity
	state.flying = FLIGHT_STATES.has(mascot_state)
	state.grounded = GROUND_STATES.has(mascot_state)
	state.yaw_rate = yaw_rate
	var player: Variant = _controller.get("player")
	if player is Node3D and is_instance_valid(player):
		state.look_target = to_local(
			(player as Node3D).global_position + Vector3.UP * 0.55
		)
	_creature.call("advance", delta, state)


func _on_state_changed(previous_state: int, mascot_state: int) -> void:
	var was_airborne: bool = not GROUND_STATES.has(previous_state)
	if was_airborne and GROUND_STATES.has(mascot_state):
		_creature.call("notify_landed", 0.6)
	match mascot_state:
		State.TAKING_OFF:
			_creature.call("notify_takeoff")
		State.PUSHED, State.FALLING:
			_creature.call("notify_surprise")
