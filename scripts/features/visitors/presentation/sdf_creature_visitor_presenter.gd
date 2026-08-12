class_name SdfCreatureVisitorPresenter
extends Node3D
## Initial visitor look only. It consumes a generic presentation definition and
## knows nothing about cadence, reward pools, stock, onboarding, or saves.

signal departure_finished(event_id: int, vase_position: Vector3)

const ProceduralCreatureScript := preload(
	"res://scripts/creatures/procedural_creature.gd"
)
const VISITOR_SCALE_MULTIPLIER := 2.0

var event_id := 0
var world_cell := Vector2i.ZERO
var _creature: Node3D
var _departing := false
var _motion_state
var _home_position := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _wander_elapsed := 0.0
var _wander_duration := 1.0
var _wander_radius := 0.42


func setup(
	event: Dictionary,
	presentation: Defs.VisitorPresentationDefinition
) -> void:
	event_id = int(event.get("event_id", 0))
	var raw_cell: Array = event.get("cell", [0, 0])
	world_cell = Vector2i(int(raw_cell[0]), int(raw_cell[1]))
	add_to_group("world_visitors")
	set_meta("visitor_event_id", event_id)
	set_meta("visitor_cell", world_cell)
	_creature = ProceduralCreatureScript.new() as Node3D
	_creature.name = "VisitorCreature"
	add_child(_creature)
	_creature.call("build_from_path", presentation.presentation_resource)
	# Visitor scale belongs to the shared presenter, so every current creature
	# and every later data-authored visitor inherits the same readable size.
	_creature.scale = (
		Vector3.ONE * presentation.scale * VISITOR_SCALE_MULTIPLIER
	)
	_motion_state = ProceduralCreatureScript.MotionState.new()
	var appear := create_tween()
	scale = Vector3.ONE * 0.15
	appear.tween_property(self, "scale", Vector3.ONE, 0.48).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)


func set_wander_center() -> void:
	_home_position = position
	_pick_wander_target()


func _process(delta: float) -> void:
	if _departing or _creature == null:
		return
	_creature.call("advance", delta, _motion_state)
	_wander_elapsed += delta
	if _wander_elapsed >= _wander_duration:
		_pick_wander_target()
	var offset := _wander_target - position
	offset.y = 0.0
	if offset.length() > 0.018:
		var step := minf(offset.length(), delta * 0.14)
		position += offset.normalized() * step
		rotation.y = lerp_angle(rotation.y, atan2(offset.x, offset.z), delta * 4.0)
	else:
		rotation.y += sin(Time.get_ticks_msec() * 0.0013 + event_id) * delta * 0.035


func begin_departure() -> bool:
	if _departing:
		return false
	_departing = true
	var vase_position := global_position
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position:y", position.y + 0.26, 0.42).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.42).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_IN)
	for child in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		tween.tween_property(mesh_instance, "transparency", 1.0, 0.38)
	tween.chain().tween_callback(func():
		departure_finished.emit(event_id, vase_position)
	)
	return true


func _pick_wander_target() -> void:
	var angle := fmod(float(abs(hash("visitor-wander|%d|%d" % [
		event_id, int(Time.get_ticks_msec() / 1000)
	]))) * 0.0137, TAU)
	var distance := 0.12 + fmod(angle * 0.37 + event_id * 0.11, _wander_radius - 0.12)
	_wander_target = _home_position + Vector3(cos(angle), 0.0, sin(angle)) * distance
	_wander_elapsed = 0.0
	_wander_duration = 1.8 + fmod(angle + event_id * 0.31, 2.4)
