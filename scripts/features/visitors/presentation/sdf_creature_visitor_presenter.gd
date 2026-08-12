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
var _creature_rest_scale := Vector3.ONE
var _creature_rest_position := Vector3.ZERO
var _departing := false
var _greet_tween: Tween
var greet_count := 0
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
	_creature_rest_scale = _creature.scale
	_creature_rest_position = _creature.position
	_motion_state = ProceduralCreatureScript.MotionState.new()
	var appear := create_tween()
	scale = Vector3.ONE * 0.15
	appear.tween_property(self, "scale", Vector3.ONE, 0.48).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)


func set_wander_center() -> void:
	_home_position = position
	_pick_wander_target()


func interaction_world_point() -> Vector3:
	if _creature == null:
		return global_position + Vector3.UP * 0.35
	var local_bounds := AABB()
	var has_bounds := false
	for child in _creature.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var bounds := mesh_instance.get_aabb()
		for endpoint_index in range(8):
			var point := to_local(mesh_instance.to_global(
				bounds.get_endpoint(endpoint_index)
			))
			if not has_bounds:
				local_bounds = AABB(point, Vector3.ZERO)
				has_bounds = true
			else:
				local_bounds = local_bounds.expand(point)
	return (
		to_global(local_bounds.get_center())
		if has_bounds
		else global_position + Vector3.UP * 0.35
	)


func is_departing() -> bool:
	return _departing


## A click is a greeting, never a pickup or an early reward claim. The visitor
## reacts in place and keeps strolling until its authored visit timer ends.
func greet() -> bool:
	if _departing or _creature == null:
		return false
	if _greet_tween != null and _greet_tween.is_valid():
		_greet_tween.kill()
	_creature.scale = _creature_rest_scale
	_creature.position = _creature_rest_position
	_creature.call("notify_surprise")
	_creature.scale = Vector3(
		_creature_rest_scale.x * 1.08,
		_creature_rest_scale.y * 0.82,
		_creature_rest_scale.z * 1.08
	)
	_greet_tween = _creature.create_tween().set_parallel()
	_greet_tween.tween_property(
		_creature, "position:y", _creature_rest_position.y + 0.14, 0.16
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_greet_tween.tween_property(
		_creature,
		"scale",
		Vector3(
			_creature_rest_scale.x * 0.94,
			_creature_rest_scale.y * 1.12,
			_creature_rest_scale.z * 0.94
		),
		0.16
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_greet_tween.chain().set_parallel()
	_greet_tween.tween_property(
		_creature, "position", _creature_rest_position, 0.24
	).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_greet_tween.tween_property(
		_creature, "scale", _creature_rest_scale, 0.2
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	greet_count += 1
	return true


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
	if _greet_tween != null and _greet_tween.is_valid():
		_greet_tween.kill()
	if _creature != null:
		_creature.position = _creature_rest_position
		_creature.scale = _creature_rest_scale
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
