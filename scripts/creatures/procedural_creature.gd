class_name ProceduralCreature
extends Node3D
## One JSON definition in, one seamless animated critter out.
##
## Builds a single SDF blend-shell draw call from a compact creature
## definition and animates it procedurally for any body plan: legged
## creatures with 1, 2, 4, or 6 legs and 0..3 arms, hoppers, and flyers
## with wings. The node is driver-agnostic — whoever owns it (player
## controller adapter, mascot AI adapter, review harness) feeds a
## MotionState each physics tick and fires impulse notifications; this
## node owns everything visible.

const SdfBlendShellScript := preload("res://scripts/player/sdf_blend_shell.gd")
const CreatureOutfitScript := preload(
	"res://scripts/creatures/creature_outfit.gd"
)
const CreatureCoatScript := preload(
	"res://scripts/creatures/creature_coat.gd"
)
const MAX_SHAPES := 16

## Fired after every advance() once the shell and anchors are current;
## outfits and other attachments re-seat themselves on this.
signal pose_advanced

## Fired by the action engine at authored phase events ("impact", "release",
## "collect", ...) and once with "finished" when a non-looping action ends.
signal action_event(action_name: String, event_name: String)

const ACTION_LIBRARY_PATH := "res://data/creature_actions.json"
const ACTION_NEUTRAL_REACH := Vector3(0.72, -0.68, 0.0)

static var _action_library: Dictionary = {}

## Per-tick motion inputs, expressed in the creature root's local space.
class MotionState:
	var local_velocity := Vector3.ZERO
	var grounded := true
	var flying := false
	var yaw_rate := 0.0
	## Local-space point the head should watch, or null for none.
	var look_target: Variant = null


var _definition: Dictionary
var _palette: Dictionary
var _plan := "legged"
var _torso: Dictionary
var _head: Dictionary
var _legs: Dictionary
var _arms: Dictionary
var _wings: Dictionary
var _tail: Dictionary
var _ears: Dictionary
var _gait: Dictionary
var _juice: Dictionary

var _shell: MeshInstance3D
var _face_root: Node3D
var _belly_root: Node3D
var _eye_nodes: Array[MeshInstance3D] = []
var _eye_base_scales: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()

var _leg_count := 2
var _leg_rests: Array[Vector3] = []
var _leg_phases: Array[float] = []
var _feet: Array[Vector3] = []
var _feet_velocities: Array[Vector3] = []
var _ear_tips: Array[Vector3] = []
var _ear_velocities: Array[Vector3] = []
var _tail_points: Array[Vector3] = []
var _tail_previous: Array[Vector3] = []

var _body_position := Vector3.ZERO
var _body_spring_velocity := Vector3.ZERO
var _body_rotation := Vector3.ZERO
var _head_position := Vector3.ZERO
var _head_spring_velocity := Vector3.ZERO
var _head_look := Vector3.ZERO
var _head_tilt := 0.0
var _head_tilt_target := 0.0
var _head_tilt_timer := 0.0

var _gait_phase := 0.0
var _flap_phase := 0.0
var _hop_phase := 0.0
var _idle_time := 0.0
var _fold := 1.0
var _tuck := 0.0
var _flap_amplitude := 0.0
var _pitch := 0.0
var _bank := 0.0
var _landing_squash := 0.0
var _stretch := 0.0
var _surprise := 0.0
var _blink_timer := 1.5
var _blink_phase := 0.0
var _flap_rate := 0.0

var _outfit: Node3D
var _anchor_arms: Array[Dictionary] = []
var _anchor_legs: Array[Dictionary] = []

var _action_name := ""
var _action_phases: Array = []
var _action_seconds := 1.0
var _action_loop := false
var _action_time := 0.0
var _action_weight := 0.0
var _action_active := false
var _action_next_phase := 0
var _action_reach := ACTION_NEUTRAL_REACH
var _action_spread := 0.0
var _action_body_pitch := 0.0
var _action_head_pitch := 0.0

var _radius_b_buffer: Array[float] = []
var _breath_phase := 0.0
var _weight_phase := 0.0
var _idle_factor := 1.0
var _body_yaw := 0.0
var _fidget_timer := 2.0
var _tail_swish := 0.0
var _wander_timer := 0.0
var _wander_look := Vector3.ZERO


func build_from_path(definition_path: String) -> void:
	var source := FileAccess.get_file_as_string(definition_path)
	var parsed: Variant = JSON.parse_string(source)
	assert(parsed is Dictionary, "Invalid creature definition: %s" % definition_path)
	build(parsed as Dictionary)


func build(definition: Dictionary) -> void:
	if is_instance_valid(_shell):
		return
	_rng.randomize()
	_definition = definition
	_palette = definition.get("palette", {}) as Dictionary
	_plan = String(definition.get("body_plan", "legged"))
	_torso = definition.get("torso", {}) as Dictionary
	_head = definition.get("head", {}) as Dictionary
	_legs = definition.get("legs", {}) as Dictionary
	_arms = definition.get("arms", {}) as Dictionary
	_wings = definition.get("wings", {}) as Dictionary
	_tail = definition.get("tail", {}) as Dictionary
	_ears = definition.get("ears", {}) as Dictionary
	_gait = definition.get("gait", {}) as Dictionary
	_juice = definition.get("juice", {}) as Dictionary
	_leg_count = clampi(int(_legs.get("count", 2)), 0, 6)

	var budget := shape_budget()
	assert(
		budget <= MAX_SHAPES,
		"Creature '%s' needs %d SDF shapes; the mobile budget is %d"
		% [definition_id(), budget, MAX_SHAPES]
	)

	_shell = SdfBlendShellScript.new() as MeshInstance3D
	_shell.name = "CreatureSdfShell"
	add_child(_shell)
	_shell.call("build", budget)
	_shell.call("set_neighbors", _build_neighbors())
	_shell.call("set_outline_width", float(_juice.get("outline", 0.006)))
	var coat := definition.get("coat", {}) as Dictionary
	if not coat.is_empty():
		_shell.call("set_coat", coat)
		var accents := CreatureCoatScript.new() as Node3D
		accents.name = "CoatAccents"
		add_child(accents)
		accents.call("build", coat, self)
	_build_overlays()
	_reset_pose()
	if definition.has("outfit"):
		set_outfit(String(definition.get("outfit")))
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	reset_physics_interpolation()


## Dress the creature from an outfit JSON path; replaces any current outfit.
func set_outfit(outfit_path: String) -> void:
	clear_outfit()
	var source := FileAccess.get_file_as_string(outfit_path)
	var parsed: Variant = JSON.parse_string(source)
	assert(parsed is Dictionary, "Invalid outfit definition: %s" % outfit_path)
	_outfit = CreatureOutfitScript.new() as Node3D
	_outfit.name = "Outfit"
	add_child(_outfit)
	_outfit.call("build", parsed as Dictionary, self)
	# A hat replaces any coat head plumage — feathers through a cap read
	# as clipping, not style.
	var coat_accents := get_node_or_null("CoatAccents/HeadAccents") as Node3D
	if coat_accents != null:
		coat_accents.visible = not (parsed as Dictionary).has("hat")


func clear_outfit() -> void:
	if is_instance_valid(_outfit):
		_outfit.queue_free()
	_outfit = null
	var coat_accents := get_node_or_null("CoatAccents/HeadAccents") as Node3D
	if coat_accents != null:
		coat_accents.visible = true


func outfit() -> Node3D:
	return _outfit


## Live world-space attachment frames for clothing and equipables, refreshed
## by every advance()/_update_shell.
func pose_anchors() -> Dictionary:
	return {
		"head": Transform3D(_head_basis(), _head_position),
		"head_radius": float(_head.get("radius", 0.1)),
		"body": Transform3D(Basis.from_euler(_body_rotation), _body_position),
		"torso_radius": _torso_radius(),
		"torso_half": float(_torso.get("length", 0.09)) * 0.5,
		"upright": _is_upright(),
		"foot_radius": _foot_radius(),
		"leg_radius": float(_legs.get("radius", 0.028)),
		"arm_radius": float(_arms.get("radius", 0.032)),
		"breath": 1.0 + sin(_breath_phase) * 0.016 * (0.4 + 0.6 * _idle_factor),
		"arms": _anchor_arms,
		"legs": _anchor_legs,
	}


func definition_id() -> String:
	return String(_definition.get("id", ""))


func shape_budget() -> int:
	var total := 2  # torso + head
	if _head.has("snout"):
		total += 1
	var segments := clampi(int(_legs.get("segments", _default_leg_segments())), 1, 2)
	total += _leg_count * segments
	if _has_foot_balls():
		total += _leg_count
	var arm_count := clampi(int(_arms.get("count", 0)), 0, 3)
	total += arm_count
	if bool(_arms.get("hand_balls", false)):
		total += arm_count
	if _has_wings():
		total += 4
	total += clampi(int(_tail.get("segments", 0)), 0, 3)
	total += clampi(int(_ears.get("count", 0)), 0, 2)
	return total


func foot_world_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for foot in _feet:
		result.append(to_global(foot + Vector3.DOWN * _foot_radius() * 0.9))
	return result


func notify_landed(strength := 0.6) -> void:
	_landing_squash = maxf(_landing_squash, clampf(strength, 0.0, 1.0))


func notify_takeoff() -> void:
	_landing_squash = maxf(_landing_squash, 0.35)


func notify_surprise() -> void:
	_surprise = 1.0


# ------------------------------------------------------------------ actions

## Play a named action from data/creature_actions.json, layered on top of
## locomotion. `seconds` rescales the authored cycle (SkillActions passes the
## equipment-adjusted cycle time). Looping actions run until stop_action()
## or the next play_action() replaces them.
func play_action(action_name: String, seconds := -1.0) -> void:
	var definition := _action_definition(action_name)
	if definition.is_empty():
		stop_action()
		return
	_action_name = action_name
	_action_phases = definition.get("phases", []) as Array
	_action_seconds = (
		seconds if seconds > 0.05
		else float(definition.get("seconds", 0.8))
	)
	_action_loop = bool(definition.get("loop", false))
	_action_time = 0.0
	_action_next_phase = 0
	_action_active = true


func stop_action() -> void:
	_action_active = false


func is_action_active() -> bool:
	return _action_active


## Where inside the cycle the visible hit lands, so gameplay can await it.
func action_impact_ratio(action_name: String, fallback: float) -> float:
	var definition := _action_definition(action_name)
	return clampf(float(definition.get("impact_ratio", fallback)), 0.01, 0.99)


func _action_definition(action_name: String) -> Dictionary:
	if _action_library.is_empty():
		var source := FileAccess.get_file_as_string(ACTION_LIBRARY_PATH)
		var parsed: Variant = JSON.parse_string(source)
		if parsed is Dictionary:
			_action_library = parsed as Dictionary
	return _action_library.get(action_name, {}) as Dictionary


func _advance_action(delta: float) -> void:
	var ramp := 1.0 - exp(-11.0 * delta)
	_action_weight = lerpf(
		_action_weight, 1.0 if _action_active else 0.0, ramp
	)
	if not _action_active:
		if _action_weight < 0.001:
			_action_name = ""
		return
	_action_time += delta
	var cycle := _action_time / maxf(_action_seconds, 0.05)
	if cycle >= 1.0:
		if _action_loop:
			_action_time = fmod(_action_time, _action_seconds)
			cycle = _action_time / _action_seconds
			_action_next_phase = 0
		else:
			_sample_action_pose(1.0)
			_fire_action_events(1.01)
			action_event.emit(_action_name, "finished")
			_action_active = false
			return
	_fire_action_events(cycle)
	_sample_action_pose(cycle)


func _fire_action_events(cycle: float) -> void:
	while _action_next_phase < _action_phases.size():
		var phase := _action_phases[_action_next_phase] as Dictionary
		if cycle < float(phase.get("t", 1.0)):
			break
		if phase.has("event"):
			action_event.emit(_action_name, String(phase.get("event")))
		if phase.has("squash"):
			_landing_squash = maxf(
				_landing_squash, float(phase.get("squash"))
			)
		_action_next_phase += 1


func _sample_action_pose(cycle: float) -> void:
	var previous_t := 0.0
	var previous_pose := {
		"reach": ACTION_NEUTRAL_REACH, "spread": 0.0,
		"body_pitch": 0.0, "head_pitch": 0.0,
	}
	for phase_value in _action_phases:
		var phase := phase_value as Dictionary
		var phase_t := float(phase.get("t", 1.0))
		var pose := {
			"reach": _phase_reach(phase, previous_pose),
			"spread": float(phase.get("spread", 0.0)),
			"body_pitch": float(phase.get("body_pitch", 0.0)),
			"head_pitch": float(phase.get("head_pitch", 0.0)),
		}
		if cycle <= phase_t or phase_t >= 1.0:
			var span := maxf(phase_t - previous_t, 0.0001)
			var alpha := _action_ease(
				clampf((cycle - previous_t) / span, 0.0, 1.0),
				String(phase.get("ease", "inout"))
			)
			_action_reach = (previous_pose["reach"] as Vector3).lerp(
				pose["reach"] as Vector3, alpha
			)
			_action_spread = lerpf(
				float(previous_pose["spread"]), float(pose["spread"]), alpha
			)
			_action_body_pitch = lerpf(
				float(previous_pose["body_pitch"]),
				float(pose["body_pitch"]),
				alpha
			)
			_action_head_pitch = lerpf(
				float(previous_pose["head_pitch"]),
				float(pose["head_pitch"]),
				alpha
			)
			return
		previous_t = phase_t
		previous_pose = pose


func _phase_reach(phase: Dictionary, previous_pose: Dictionary) -> Vector3:
	var reach: Variant = phase.get("reach")
	if reach is Array and (reach as Array).size() >= 3:
		return Vector3(
			float((reach as Array)[0]),
			float((reach as Array)[1]),
			float((reach as Array)[2])
		)
	return previous_pose.get("reach", ACTION_NEUTRAL_REACH) as Vector3


func _action_ease(alpha: float, kind: String) -> float:
	match kind:
		"linear":
			return alpha
		"in":
			return alpha * alpha
		"out":
			return 1.0 - (1.0 - alpha) * (1.0 - alpha)
	return alpha * alpha * (3.0 - 2.0 * alpha)


## Creatures without arms translate arm reach into a head lunge, so a
## quadruped "chops" with an adorable headbutt-peck instead of doing nothing.
func _action_head_push() -> Vector3:
	if _action_weight < 0.001:
		return Vector3.ZERO
	if clampi(int(_arms.get("count", 0)), 0, 3) > 0:
		return Vector3.ZERO
	var head_radius := float(_head.get("radius", 0.1))
	return Vector3(
		0.0,
		(_action_reach.y - ACTION_NEUTRAL_REACH.y) * 0.16,
		_action_reach.z * 0.4
	) * head_radius * _action_weight


## The owner calls this once per physics tick; nothing animates without it.
func advance(delta: float, state: MotionState) -> void:
	if not visible or not is_instance_valid(_shell):
		return
	delta = minf(delta, 1.0 / 30.0)
	var horizontal := Vector3(state.local_velocity.x, 0.0, state.local_velocity.z)
	var speed := horizontal.length()
	var reference_speed := float(_gait.get("reference_speed", 2.4))
	var movement_amount := clampf(speed / maxf(reference_speed, 0.05), 0.0, 1.35)

	_idle_time += delta
	_landing_squash = move_toward(_landing_squash, 0.0, delta * 4.2)
	_surprise = move_toward(_surprise, 0.0, delta * 1.2)
	_advance_action(delta)

	# Idle life: breathing, slow weight shifting, and occasional fidgets
	# keep the whole body organic even when standing still.
	_breath_phase += delta * TAU * float(_juice.get("breath_rate", 0.55))
	_weight_phase += delta * TAU * float(_juice.get("weight_rate", 0.16))
	_tail_swish = move_toward(_tail_swish, 0.0, delta * 1.1)
	_idle_factor = (
		(1.0 - clampf(movement_amount, 0.0, 1.0))
		* (0.0 if state.flying else 1.0)
	)
	_fidget_timer -= delta
	if _fidget_timer <= 0.0:
		_fidget(movement_amount)
	_gait_phase = fposmod(
		_gait_phase + speed * delta * float(_gait.get("cadence", 6.4)), TAU
	)
	_hop_phase = fposmod(
		_hop_phase
		+ delta * float(_gait.get("hop_rate", 2.6)) * TAU
		* clampf(movement_amount * 1.4, 0.0, 1.0),
		TAU
	)

	var blend_rate := 1.0 - exp(-9.0 * delta)
	_fold = lerpf(_fold, 0.0 if state.flying else 1.0, blend_rate)
	_tuck = lerpf(_tuck, 1.0 if state.flying else 0.0, blend_rate)
	if state.flying:
		_flap_rate = lerpf(_flap_rate, float(_wings.get("flap_hz", 3.2)), blend_rate)
		_flap_amplitude = lerpf(
			_flap_amplitude, float(_wings.get("flap", 0.6)), blend_rate
		)
	else:
		_flap_rate = lerpf(_flap_rate, 0.0, blend_rate)
		_flap_amplitude = lerpf(_flap_amplitude, 0.0, blend_rate)
	_flap_phase = fposmod(_flap_phase + delta * TAU * _flap_rate, TAU)

	_update_body(delta, state, movement_amount)
	_update_head(delta, state, movement_amount)
	_update_feet(delta, state, horizontal, movement_amount)
	_update_ears(delta, state, movement_amount)
	_update_tail(delta, state)
	_update_blink(delta)
	_update_shell(movement_amount, state)
	_update_overlays()
	pose_advanced.emit()


# ------------------------------------------------------------------ motion

## Small involuntary moves on a loose timer — an ear flick, a tail swish,
## a tiny weight bounce, a curious head tilt. Never during real motion.
func _fidget(movement_amount: float) -> void:
	_fidget_timer = _rng.randf_range(3.2, 7.5)
	if movement_amount > 0.3:
		return
	match _rng.randi_range(0, 3):
		0:
			for ear_index in _ear_velocities.size():
				_ear_velocities[ear_index] += Vector3(
					_rng.randf_range(-0.5, 0.5),
					_rng.randf_range(0.2, 0.6),
					_rng.randf_range(-0.3, 0.3)
				) * float(_ears.get("length", 0.1)) * 6.0
		1:
			_tail_swish = 1.0
		2:
			_landing_squash = maxf(_landing_squash, 0.15)
		3:
			_head_tilt_target = _rng.randf_range(-0.24, 0.24)
			_head_tilt_timer = _rng.randf_range(1.6, 2.6)


func _update_body(delta: float, state: MotionState, movement_amount: float) -> void:
	var base_y := _body_rest_height()
	var bob := 0.0
	if state.flying:
		bob = sin(_flap_phase - 0.9) * float(_wings.get("hover_bob", 0.02))
	elif _is_hop_plan():
		bob = _hop_height() * movement_amount
		_stretch = maxf(sin(_hop_phase), 0.0) * 0.35 * movement_amount
	elif state.grounded:
		bob = (
			(1.0 - cos(_gait_phase * 2.0)) * 0.5
			* float(_gait.get("body_bob", 0.018))
			* clampf(movement_amount, 0.0, 1.0)
		) + sin(_idle_time * 1.9) * base_y * 0.012
	# Breathing lifts the chest; slow weight shifting rocks the stance.
	var scale_reference := _torso_radius()
	bob += sin(_breath_phase) * scale_reference * 0.022 * (0.35 + 0.65 * _idle_factor)
	var sway_x := sin(_weight_phase) * scale_reference * 0.07 * _idle_factor
	var target := Vector3(
		sway_x, base_y + bob - _landing_squash * base_y * 0.16, 0.0
	)
	_body_spring_velocity += (target - _body_position) * 120.0 * delta
	_body_spring_velocity *= exp(-12.0 * delta)
	_body_position += _body_spring_velocity * delta

	var lean := float(_gait.get("lean", 0.06))
	var pitch_target := 0.0
	var roll_target := 0.0
	if state.flying:
		pitch_target = float(_wings.get("pitch", 0.12))
		roll_target = clampf(
			-state.yaw_rate * float(_wings.get("bank", 0.5)) * 0.45, -0.38, 0.38
		)
	else:
		pitch_target = clampf(-state.local_velocity.z * lean * 0.22, -0.17, 0.17)
		if _is_hop_plan():
			pitch_target += _stretch * 0.35
		roll_target = (
			clampf(-state.local_velocity.x * lean * 0.28, -0.15, 0.15)
			+ sin(_gait_phase) * float(_gait.get("waddle", 0.03)) * movement_amount
		)
	if not state.flying:
		# The stance rocks with the weight shift; the torso twists with the
		# stride. Both are what make a body read as alive instead of rigid.
		roll_target += sin(_weight_phase) * 0.038 * _idle_factor
		pitch_target += cos(_weight_phase * 0.63) * 0.02 * _idle_factor
	var yaw_target := (
		sin(_weight_phase * 0.71) * 0.05 * _idle_factor
		+ sin(_gait_phase) * float(_gait.get("gait_twist", 0.07)) * movement_amount
	)
	_pitch = lerpf(_pitch, pitch_target, 1.0 - exp(-7.0 * delta))
	_bank = lerpf(_bank, roll_target, 1.0 - exp(-6.0 * delta))
	_body_yaw = lerpf(_body_yaw, yaw_target, 1.0 - exp(-6.0 * delta))
	_body_rotation = Vector3(
		_pitch + _torso_rest_pitch() + _action_body_pitch * _action_weight,
		_body_yaw,
		_bank
	)


func _update_head(delta: float, state: MotionState, movement_amount: float) -> void:
	var body_basis := Basis.from_euler(_body_rotation)
	var squash := _landing_squash * float(_juice.get("squash", 0.2))
	var offset := _head_offset() * (1.0 - squash * 0.4)
	var target := _body_position + body_basis * offset
	var stabilize := clampf(float(_head.get("stabilize", 0.35)), 0.0, 1.0)
	if state.grounded and not state.flying:
		target.y = lerpf(target.y, _body_rest_height() + offset.y, stabilize)
	target += (
		Vector3(state.local_velocity.x, 0.0, state.local_velocity.z)
		* -float(_juice.get("head_lag", 0.045)) * 0.02
	)
	target += body_basis * _action_head_push()
	_head_spring_velocity += (target - _head_position) * 140.0 * delta
	_head_spring_velocity *= exp(-13.0 * delta)
	_head_position += _head_spring_velocity * delta

	var look_target := Vector3.ZERO
	if state.look_target is Vector3 and not state.flying:
		var to_target := (state.look_target as Vector3) - _head_position
		var planar := Vector2(to_target.x, to_target.z).length()
		look_target.y = clampf(atan2(-to_target.x, -to_target.z), -1.1, 1.1)
		look_target.x = clampf(atan2(to_target.y, maxf(planar, 0.15)), -0.35, 0.4)
	elif state.flying:
		look_target.x = -_pitch * 0.7
	else:
		# Nothing to watch: the head wanders curiously on its own.
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_wander_timer = _rng.randf_range(1.8, 4.5)
			_wander_look = Vector3(
				_rng.randf_range(-0.14, 0.1),
				_rng.randf_range(-0.55, 0.55),
				0.0
			)
		look_target = _wander_look * _idle_factor
	look_target.x += sin(_breath_phase - 0.5) * 0.02
	look_target.y -= _body_yaw * 0.7

	_head_tilt_timer -= delta
	if _head_tilt_timer <= 0.0:
		_head_tilt_timer = _rng.randf_range(2.6, 6.0)
		_head_tilt_target = (
			0.0 if absf(_head_tilt_target) > 0.01 or _rng.randf() < 0.5
			else _rng.randf_range(-0.2, 0.2)
		)
	if state.flying or movement_amount > 0.4:
		_head_tilt_target = 0.0
	_head_tilt = lerpf(_head_tilt, _head_tilt_target, 1.0 - exp(-5.0 * delta))
	var snap := 1.0 - exp(-float(_juice.get("head_snap", 9.0)) * delta)
	_head_look = _head_look.lerp(look_target, snap)


func _update_feet(
	delta: float,
	state: MotionState,
	horizontal: Vector3,
	movement_amount: float
) -> void:
	if _leg_count == 0:
		return
	var direction := (
		horizontal.normalized()
		if horizontal.length_squared() > 0.0016
		else Vector3(0.0, 0.0, -1.0)
	)
	var stride := (
		float(_gait.get("stride", 0.1)) * clampf(movement_amount * 1.25, 0.0, 1.0)
	)
	var lift := (
		float(_gait.get("step_lift", 0.06)) * clampf(movement_amount * 1.5, 0.0, 1.0)
	)
	var rest_y := _foot_radius() * 0.85
	for leg_index in _leg_count:
		var rest := _leg_rests[leg_index]
		var target: Vector3
		if state.flying or not state.grounded:
			var body_basis := Basis.from_euler(_body_rotation)
			target = _body_position + body_basis * Vector3(
				rest.x, -_torso_radius() * 1.1, rest.z * 0.5 + _torso_radius() * 0.3
			)
		elif _is_hop_plan():
			var hop_lift := _hop_height() * movement_amount
			target = Vector3(rest.x, rest_y + hop_lift * 0.8, rest.z)
			target += direction * sin(_hop_phase) * stride * 0.5
		else:
			var phase := _gait_phase + _leg_phases[leg_index]
			target = Vector3(rest.x, rest_y, rest.z)
			target += (
				direction * sin(phase) * stride
				+ Vector3.UP * maxf(sin(phase), 0.0) * lift
			)
		_feet_velocities[leg_index] += (target - _feet[leg_index]) * 190.0 * delta
		_feet_velocities[leg_index] *= exp(-18.0 * delta)
		_feet[leg_index] += _feet_velocities[leg_index] * delta


func _update_ears(delta: float, state: MotionState, movement_amount: float) -> void:
	var ear_count := clampi(int(_ears.get("count", 0)), 0, 2)
	if ear_count == 0:
		return
	var head_basis := _head_basis()
	var sway := (
		sin(_idle_time * 2.0) * 0.02
		+ sin(_gait_phase) * 0.014 * movement_amount
	)
	var stiffness := float(_juice.get("ear_spring", 40.0))
	var acceleration_drop := -0.5 if state.flying else 0.0
	for ear_index in ear_count:
		var side := _ear_side(ear_index)
		var base := _ear_base(ear_index, head_basis)
		var direction := _ear_direction(side)
		var target := base + head_basis * (
			direction * float(_ears.get("length", 0.1))
			+ Vector3(sway * side, acceleration_drop * 0.02, 0.0)
		)
		_ear_velocities[ear_index] += (target - _ear_tips[ear_index]) * stiffness * delta
		_ear_velocities[ear_index] *= exp(-7.0 * delta)
		_ear_tips[ear_index] += _ear_velocities[ear_index] * delta


func _update_tail(delta: float, state: MotionState) -> void:
	var segment_count := clampi(int(_tail.get("segments", 0)), 0, 3)
	if segment_count == 0:
		return
	var body_basis := Basis.from_euler(_body_rotation)
	var anchor := _body_position + body_basis * _tail_base_offset()
	var droop := clampf(float(_tail.get("droop", 0.45)), 0.0, 1.0)
	if _is_hop_plan():
		# A hopper's tail is a counterweight: it dips as the body rises.
		droop = clampf(droop + _stretch * 0.5, 0.0, 1.0)
	if state.flying:
		droop = clampf(droop - 0.3, 0.0, 1.0)
	var segment_length := float(_tail.get("length", 0.12)) / float(segment_count)
	# A fidget swish triples the wag briefly — pure happiness.
	var swish := 1.0 + _tail_swish * 2.2
	var wag := sin(_idle_time * float(_tail.get("wag_rate", 1.6)) * swish)
	var wag_amount := float(_tail.get("wag", 0.25)) * swish
	var drag := float(_juice.get("tail_drag", 0.85))
	for segment_index in segment_count:
		var progress := float(segment_index + 1) / float(segment_count)
		var desired := body_basis * Vector3(
			wag * wag_amount * progress,
			lerpf(0.55, -0.9, droop) * progress,
			1.0
		).normalized()
		var current := _tail_points[segment_index]
		var inertial := (current - _tail_previous[segment_index]) * drag
		var target := anchor + desired * segment_length
		var next_position := (
			current + inertial + (target - current) * 18.0 * delta * delta
			+ Vector3.DOWN * 0.2 * delta * delta
		)
		_tail_previous[segment_index] = current
		var to_next := next_position - anchor
		if to_next.length_squared() < 0.000001:
			to_next = desired
		var resolved := anchor + to_next.normalized() * segment_length
		# A dragging tail rests ON the ground instead of clipping through it.
		resolved.y = maxf(resolved.y, float(_tail.get("radius", 0.026)) * 0.8)
		_tail_points[segment_index] = resolved
		anchor = _tail_points[segment_index]


func _update_blink(delta: float) -> void:
	if _eye_nodes.is_empty():
		return
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = _rng.randf_range(2.2, 5.2)
		_blink_phase = 0.14
	_blink_phase = maxf(_blink_phase - delta, 0.0)
	var closed := sin(PI * clampf(_blink_phase / 0.14, 0.0, 1.0))
	var openness := (1.0 - 0.92 * closed) * (1.0 + _surprise * 0.3)
	for eye_index in _eye_nodes.size():
		var base_scale := _eye_base_scales[eye_index]
		_eye_nodes[eye_index].scale = Vector3(
			base_scale.x * (1.0 + _surprise * 0.18),
			base_scale.y * openness,
			base_scale.z
		)


# ------------------------------------------------------------------ shell

func _update_shell(movement_amount: float, state: MotionState) -> void:
	var shape_a: Array[Vector4] = []
	var shape_b: Array[Vector4] = []
	var colors: Array[Vector4] = []
	_radius_b_buffer = []
	var body_basis := Basis.from_euler(_body_rotation)
	var head_basis := _head_basis()
	var squash := _landing_squash * float(_juice.get("squash", 0.2))
	var breath := 1.0 + sin(_breath_phase) * 0.016 * (0.4 + 0.6 * _idle_factor)
	var torso_radius := (
		_torso_radius() * (1.0 + squash * 0.35 - _stretch * 0.10) * breath
	)
	var torso_half := (
		float(_torso.get("length", 0.09)) * 0.5
		* (1.0 - squash * 0.45 + _stretch * 0.25)
	)
	var torso_axis := (
		Vector3(0.0, 1.0, 0.0) if _is_upright() else Vector3(0.0, 0.0, 1.0)
	)

	# Torso taper sculpts the silhouette: <1 narrows the top/rear (pear
	# chests), >1 swells it (round rumps). 1 is a plain capsule.
	_append_shape(
		shape_a, shape_b, colors,
		_body_position + body_basis * (torso_axis * -torso_half),
		_body_position + body_basis * (torso_axis * torso_half),
		torso_radius, float(_torso.get("blend", 0.03)), _color_for("torso"),
		torso_radius * clampf(float(_torso.get("taper", 1.0)), 0.5, 1.5)
	)
	var head_radius := float(_head.get("radius", 0.1)) * (1.0 + squash * 0.08)
	_append_shape(
		shape_a, shape_b, colors,
		_head_position + head_basis * Vector3(0.0, -0.008, -0.003),
		_head_position + head_basis * Vector3(0.0, 0.008, 0.003),
		head_radius, float(_head.get("blend", 0.03)), _color_for("head")
	)
	if _head.has("snout"):
		# A real sculpted muzzle/snout/trunk instead of a flat decal. All
		# dimensions are in head-radius units so it scales with the creature.
		var snout := _head.get("snout") as Dictionary
		var snout_length := float(snout.get("length", 0.55)) * head_radius
		var snout_radius := float(snout.get("radius", 0.42)) * head_radius
		var snout_drop := float(snout.get("drop", -0.12)) * head_radius
		var snout_dip := float(snout.get("dip", 0.2)) * snout_length
		_append_shape(
			shape_a, shape_b, colors,
			_head_position + head_basis * Vector3(0.0, snout_drop, -head_radius * 0.5),
			_head_position + head_basis * Vector3(
				0.0, snout_drop - snout_dip, -head_radius * 0.5 - snout_length
			),
			snout_radius, 0.02,
			(
				Color(String(_palette.get("snout")))
				if _palette.has("snout") else _color_for("head")
			),
			snout_radius * clampf(float(snout.get("taper", 0.7)), 0.3, 1.2)
		)

	_append_leg_shapes(shape_a, shape_b, colors, body_basis)
	_append_arm_shapes(shape_a, shape_b, colors, body_basis, movement_amount, state)
	if _has_wings():
		_append_wing_shapes(shape_a, shape_b, colors, body_basis)
	_append_tail_shapes(shape_a, shape_b, colors)
	_append_ear_shapes(shape_a, shape_b, colors, head_basis)

	_shell.call(
		"update_shapes",
		PackedVector4Array(shape_a),
		PackedVector4Array(shape_b),
		PackedVector4Array(colors),
		PackedFloat32Array(_radius_b_buffer)
	)


func _append_leg_shapes(
	shape_a: Array[Vector4],
	shape_b: Array[Vector4],
	colors: Array[Vector4],
	body_basis: Basis
) -> void:
	var segments := clampi(int(_legs.get("segments", _default_leg_segments())), 1, 2)
	var leg_radius := float(_legs.get("radius", 0.028))
	var limb_color := _color_for("limb")
	_anchor_legs = []
	for leg_index in _leg_count:
		var rest := _leg_rests[leg_index]
		var hip := _body_position + body_basis * Vector3(
			rest.x, _hip_drop(), rest.z
		)
		var foot := _feet[leg_index]
		var anchor_knee := hip.lerp(foot, 0.5)
		if segments == 2:
			# Knees bend forward by default; "back" gives digitigrade animal
			# hocks (fox, cat) that read natural on beast-legged bipeds.
			var knee_direction := (
				1.0 if String(_legs.get("knee", "forward")) == "back" else -1.0
			)
			var bend_hint := body_basis * Vector3(
				rest.x * 1.5, 0.0, knee_direction
			)
			var half := float(_legs.get("length", 0.2)) * 0.5 + 0.01
			var knee := _two_bone_joint(hip, foot, half, half, bend_hint)
			anchor_knee = knee
			_append_shape(
				shape_a, shape_b, colors, hip, knee,
				leg_radius, 0.014, limb_color, leg_radius * 0.82
			)
			_append_shape(
				shape_a, shape_b, colors, knee, foot + Vector3.UP * 0.01,
				leg_radius * 0.85, 0.012, limb_color, leg_radius * 0.62
			)
		else:
			_append_shape(
				shape_a, shape_b, colors, hip, foot + Vector3.UP * 0.01,
				leg_radius, 0.012, limb_color, leg_radius * 0.66
			)
		if _has_foot_balls():
			_append_shape(
				shape_a, shape_b, colors, foot, foot,
				_foot_radius(), 0.006, _color_for("foot")
			)
		_anchor_legs.append({"hip": hip, "knee": anchor_knee, "foot": foot})


func _append_arm_shapes(
	shape_a: Array[Vector4],
	shape_b: Array[Vector4],
	colors: Array[Vector4],
	body_basis: Basis,
	movement_amount: float,
	state: MotionState
) -> void:
	var arm_count := clampi(int(_arms.get("count", 0)), 0, 3)
	_anchor_arms = []
	if arm_count == 0:
		return
	var arm_length := float(_arms.get("length", 0.15))
	var arm_radius := float(_arms.get("radius", 0.032))
	var shoulder_height := float(_arms.get("height", _torso_radius() * 0.45))
	var swing := sin(_gait_phase) * 0.5 * clampf(movement_amount, 0.0, 1.0)
	if not state.grounded and not _is_hop_plan():
		swing = -0.45
	if _is_hop_plan():
		# Hoppers hold little paws tucked in front — no swing.
		swing = 0.0
	for arm_index in arm_count:
		# 2 arms → left/right; a third arm grows from the back.
		var angle := PI * 0.5 if arm_index == 0 else -PI * 0.5
		if arm_index == 2:
			angle = PI
		var lateral := Vector3(sin(angle), 0.0, cos(angle))
		var shoulder := _body_position + body_basis * (
			lateral * _torso_radius() * 0.82
			+ Vector3(0.0, shoulder_height, 0.0)
		)
		var swing_sign := 1.0 if arm_index == 0 else -1.0
		if arm_index == 2:
			swing_sign = 0.0
		var hand_offset: Vector3
		if _is_hop_plan():
			hand_offset = Vector3(
				lateral.x * arm_length * 0.35,
				-arm_length * 0.4,
				-arm_length * 0.7
			)
		else:
			hand_offset = Vector3(
				lateral.x * arm_length * 0.75,
				-arm_length * 0.72,
				lateral.z * arm_length * 0.75 + swing * swing_sign * arm_length
			)
		# Idle drift: hands float on small slow circles instead of hanging
		# frozen at the sides.
		hand_offset += Vector3(
			sin(_breath_phase * 0.8 + float(arm_index) * 2.1) * 0.05,
			sin(_breath_phase + float(arm_index)) * 0.07,
			cos(_weight_phase * 1.3 + float(arm_index) * 1.7) * 0.05
		) * arm_length * _idle_factor
		if _action_weight > 0.001:
			# Actions steer hands toward an authored reach point (in arm-length
			# units); side arms mirror, a back arm follows straight behind.
			var reach_offset: Vector3
			if arm_index == 2:
				reach_offset = Vector3(
					0.0,
					_action_reach.y * arm_length,
					maxf(-_action_reach.z, 0.25) * arm_length
				)
			else:
				reach_offset = Vector3(
					lateral.x * (_action_reach.x + _action_spread) * arm_length,
					_action_reach.y * arm_length,
					_action_reach.z * arm_length
				)
			hand_offset = hand_offset.lerp(reach_offset, _action_weight)
		var hand := shoulder + body_basis * hand_offset
		_append_shape(
			shape_a, shape_b, colors, shoulder, hand,
			arm_radius, 0.018, _color_for("arm"), arm_radius * 0.72
		)
		if bool(_arms.get("hand_balls", false)):
			_append_shape(
				shape_a, shape_b, colors, hand, hand,
				arm_radius * 1.18, 0.008, _color_for("arm")
			)
		_anchor_arms.append({"shoulder": shoulder, "hand": hand})


func _append_wing_shapes(
	shape_a: Array[Vector4],
	shape_b: Array[Vector4],
	colors: Array[Vector4],
	body_basis: Basis
) -> void:
	var wing_length := float(_wings.get("length", 0.11))
	var spread := smoothstep(0.0, 1.0, 1.0 - _fold)
	var flap := sin(_flap_phase) * _flap_amplitude + 0.18
	var tip_flap := sin(_flap_phase - 0.65) * _flap_amplitude * 1.25 - 0.1
	var upper_radius := lerpf(0.02, 0.034, spread) * _wing_scale()
	var tip_radius := lerpf(0.015, 0.023, spread) * _wing_scale()
	var wing_color := _color_for("wing")
	var torso_radius := _torso_radius()
	for side in [-1.0, 1.0]:
		var shoulder := _body_position + body_basis * Vector3(
			side * torso_radius * 0.86, torso_radius * 0.5, 0.0
		)
		var folded_wrist := _body_position + body_basis * Vector3(
			side * torso_radius * 0.83, -torso_radius * 0.15, torso_radius * 0.21
		)
		var folded_tip := _body_position + body_basis * Vector3(
			side * torso_radius * 0.62, -torso_radius * 0.74, torso_radius * 0.4
		)
		var upper_direction := Vector3(
			side * cos(flap), sin(flap), -0.06
		).normalized()
		var spread_wrist := shoulder + body_basis * upper_direction * wing_length
		var tip_direction := Vector3(
			side * cos(tip_flap), sin(tip_flap), 0.12
		).normalized()
		var spread_tip := spread_wrist + body_basis * tip_direction * wing_length
		_append_shape(
			shape_a, shape_b, colors,
			shoulder, folded_wrist.lerp(spread_wrist, spread),
			upper_radius, 0.016, wing_color, upper_radius * 0.85
		)
		_append_shape(
			shape_a, shape_b, colors,
			folded_wrist.lerp(spread_wrist, spread),
			folded_tip.lerp(spread_tip, spread),
			tip_radius, 0.013, wing_color.darkened(0.08), tip_radius * 0.55
		)


func _append_tail_shapes(
	shape_a: Array[Vector4],
	shape_b: Array[Vector4],
	colors: Array[Vector4]
) -> void:
	var segment_count := clampi(int(_tail.get("segments", 0)), 0, 3)
	if segment_count == 0:
		return
	var body_basis := Basis.from_euler(_body_rotation)
	var anchor := _body_position + body_basis * _tail_base_offset()
	var tail_radius := float(_tail.get("radius", 0.026))
	var tail_color := _color_for("tail")
	var tip_taper := clampf(float(_tail.get("taper", 0.55)), 0.2, 1.6)
	for segment_index in segment_count:
		var start_taper := lerpf(
			1.0, tip_taper, float(segment_index) / maxf(float(segment_count), 1.0)
		)
		var end_taper := lerpf(
			1.0, tip_taper,
			float(segment_index + 1) / maxf(float(segment_count), 1.0)
		)
		_append_shape(
			shape_a, shape_b, colors,
			anchor, _tail_points[segment_index],
			tail_radius * start_taper, 0.014,
			tail_color if segment_index < segment_count - 1 else tail_color.darkened(0.08),
			tail_radius * end_taper
		)
		anchor = _tail_points[segment_index]


func _append_ear_shapes(
	shape_a: Array[Vector4],
	shape_b: Array[Vector4],
	colors: Array[Vector4],
	head_basis: Basis
) -> void:
	var ear_count := clampi(int(_ears.get("count", 0)), 0, 2)
	var ear_radius := float(_ears.get("radius", 0.02))
	var ear_color := _color_for("ear")
	for ear_index in ear_count:
		_append_shape(
			shape_a, shape_b, colors,
			_ear_base(ear_index, head_basis), _ear_tips[ear_index],
			ear_radius, float(_ears.get("blend", 0.01)), ear_color,
			ear_radius * clampf(float(_ears.get("taper", 0.55)), 0.2, 1.4)
		)


# ------------------------------------------------------------------ overlays

func _build_overlays() -> void:
	_face_root = Node3D.new()
	_face_root.name = "CreatureFace"
	add_child(_face_root)
	var style := String(_head.get("face", "critter"))
	var head_radius := float(_head.get("radius", 0.1))
	match style:
		"owl":
			_build_owl_face(head_radius)
		"pup":
			_build_pup_face(head_radius)
		"human":
			_build_human_face(head_radius)
		_:
			_build_critter_face(head_radius)

	_belly_root = Node3D.new()
	_belly_root.name = "CreatureBelly"
	add_child(_belly_root)
	if bool(_torso.get("belly", true)):
		var torso_radius := _torso_radius()
		_add_sphere(
			_belly_root, "BellyPatch",
			Vector3(0.0, -torso_radius * 0.14, -torso_radius + 0.016),
			Vector3(torso_radius * 0.67, torso_radius * 0.79, 0.018),
			_color_for("belly")
		)


func _build_critter_face(head_radius: float) -> void:
	_add_sphere(_face_root, "Muzzle", Vector3(0.0, -head_radius * 0.09, -head_radius + 0.011), Vector3(head_radius * 0.62, head_radius * 0.51, 0.014), _color_for("face_patch"))
	var eye_scale := Vector3(head_radius * 0.1, head_radius * 0.165, 0.007)
	var eye_left := _add_sphere(_face_root, "EyeLeft", Vector3(-head_radius * 0.26, head_radius * 0.04, -head_radius - 0.005), eye_scale, _color("ink"), Vector3.ZERO, true)
	var eye_right := _add_sphere(_face_root, "EyeRight", Vector3(head_radius * 0.26, head_radius * 0.04, -head_radius - 0.005), eye_scale, _color("ink"), Vector3.ZERO, true)
	_register_eyes(eye_left, eye_right)
	_add_sphere(_face_root, "GlintLeft", Vector3(-head_radius * 0.30, head_radius * 0.10, -head_radius - 0.012), Vector3(0.004, 0.006, 0.003), Color("#FFF8E4"), Vector3.ZERO, true)
	_add_sphere(_face_root, "GlintRight", Vector3(head_radius * 0.22, head_radius * 0.10, -head_radius - 0.012), Vector3(0.004, 0.006, 0.003), Color("#FFF8E4"), Vector3.ZERO, true)
	_add_sphere(_face_root, "CheekLeft", Vector3(-head_radius * 0.43, -head_radius * 0.23, -head_radius + 0.006), Vector3(head_radius * 0.13, head_radius * 0.07, 0.005), _color("accent"), Vector3(0.0, 0.45, 0.0), true)
	_add_sphere(_face_root, "CheekRight", Vector3(head_radius * 0.43, -head_radius * 0.23, -head_radius + 0.006), Vector3(head_radius * 0.13, head_radius * 0.07, 0.005), _color("accent"), Vector3(0.0, -0.45, 0.0), true)
	_add_sphere(_face_root, "Nose", Vector3(0.0, -head_radius * 0.19, -head_radius - 0.011), Vector3(head_radius * 0.062, head_radius * 0.055, 0.004), _color("ink"), Vector3.ZERO, true)
	_add_sphere(_face_root, "Mouth", Vector3(0.0, -head_radius * 0.36, -head_radius - 0.008), Vector3(head_radius * 0.07, head_radius * 0.04, 0.003), _color("ink"), Vector3.ZERO, true)


func _build_owl_face(head_radius: float) -> void:
	_add_sphere(_face_root, "FaceDiscLeft", Vector3(-head_radius * 0.27, head_radius * 0.1, -head_radius + 0.026), Vector3(head_radius * 0.47, head_radius * 0.51, 0.024), _color_for("face_patch"), Vector3(0.0, 0.34, 0.0))
	_add_sphere(_face_root, "FaceDiscRight", Vector3(head_radius * 0.27, head_radius * 0.1, -head_radius + 0.026), Vector3(head_radius * 0.47, head_radius * 0.51, 0.024), _color_for("face_patch"), Vector3(0.0, -0.34, 0.0))
	var eye_scale := Vector3(head_radius * 0.2, head_radius * 0.27, 0.008)
	var eye_left := _add_sphere(_face_root, "EyeLeft", Vector3(-head_radius * 0.38, head_radius * 0.1, -head_radius - 0.005), eye_scale, _color("ink"), Vector3.ZERO, true)
	var eye_right := _add_sphere(_face_root, "EyeRight", Vector3(head_radius * 0.38, head_radius * 0.1, -head_radius - 0.005), eye_scale, _color("ink"), Vector3.ZERO, true)
	_register_eyes(eye_left, eye_right)
	_add_sphere(_face_root, "GlintLeft", Vector3(-head_radius * 0.44, head_radius * 0.19, -head_radius - 0.015), Vector3(0.0062, 0.0082, 0.004), Color("#FFF8E4"), Vector3.ZERO, true)
	_add_sphere(_face_root, "GlintRight", Vector3(head_radius * 0.32, head_radius * 0.19, -head_radius - 0.015), Vector3(0.0062, 0.0082, 0.004), Color("#FFF8E4"), Vector3.ZERO, true)
	_add_sphere(_face_root, "Beak", Vector3(0.0, -head_radius * 0.13, -head_radius - 0.007), Vector3(head_radius * 0.13, head_radius * 0.19, 0.012), _color("accent").lightened(0.12), Vector3.ZERO, true)
	_add_sphere(_face_root, "CheekLeft", Vector3(-head_radius * 0.59, -head_radius * 0.16, -head_radius + 0.008), Vector3(head_radius * 0.12, head_radius * 0.08, 0.005), _color("accent").lightened(0.22), Vector3(0.0, 0.5, 0.0), true)
	_add_sphere(_face_root, "CheekRight", Vector3(head_radius * 0.59, -head_radius * 0.16, -head_radius + 0.008), Vector3(head_radius * 0.12, head_radius * 0.08, 0.005), _color("accent").lightened(0.22), Vector3(0.0, -0.5, 0.0), true)


## A human-ish villager face: hair volume, brows, simple warm features and
## no animal muzzle. Hair color comes from the "hair" palette key.
func _build_human_face(head_radius: float) -> void:
	var hair := (
		Color(String(_palette.get("hair")))
		if _palette.has("hair") else _color("ink")
	)
	_add_sphere(_face_root, "HairCap", Vector3(0.0, head_radius * 0.3, head_radius * 0.12), Vector3(head_radius * 1.04, head_radius * 0.82, head_radius * 1.02), hair)
	_add_sphere(_face_root, "HairFringe", Vector3(0.0, head_radius * 0.56, -head_radius * 0.62), Vector3(head_radius * 0.78, head_radius * 0.34, head_radius * 0.5), hair)
	var eye_scale := Vector3(head_radius * 0.095, head_radius * 0.14, 0.007)
	var eye_left := _add_sphere(_face_root, "EyeLeft", Vector3(-head_radius * 0.24, head_radius * 0.02, -head_radius - 0.004), eye_scale, _color("ink"), Vector3.ZERO, true)
	var eye_right := _add_sphere(_face_root, "EyeRight", Vector3(head_radius * 0.24, head_radius * 0.02, -head_radius - 0.004), eye_scale, _color("ink"), Vector3.ZERO, true)
	_register_eyes(eye_left, eye_right)
	_add_sphere(_face_root, "GlintLeft", Vector3(-head_radius * 0.28, head_radius * 0.07, -head_radius - 0.01), Vector3(0.004, 0.005, 0.003), Color("#FFF8E4"), Vector3.ZERO, true)
	_add_sphere(_face_root, "GlintRight", Vector3(head_radius * 0.2, head_radius * 0.07, -head_radius - 0.01), Vector3(0.004, 0.005, 0.003), Color("#FFF8E4"), Vector3.ZERO, true)
	_add_sphere(_face_root, "BrowLeft", Vector3(-head_radius * 0.24, head_radius * 0.22, -head_radius - 0.002), Vector3(head_radius * 0.1, head_radius * 0.035, 0.004), hair.darkened(0.1), Vector3.ZERO, true)
	_add_sphere(_face_root, "BrowRight", Vector3(head_radius * 0.24, head_radius * 0.22, -head_radius - 0.002), Vector3(head_radius * 0.1, head_radius * 0.035, 0.004), hair.darkened(0.1), Vector3.ZERO, true)
	_add_sphere(_face_root, "Nose", Vector3(0.0, -head_radius * 0.1, -head_radius - 0.008), Vector3(head_radius * 0.055, head_radius * 0.05, 0.01), _color_for("head").darkened(0.12), Vector3.ZERO, true)
	_add_sphere(_face_root, "Mouth", Vector3(0.0, -head_radius * 0.3, -head_radius - 0.005), Vector3(head_radius * 0.08, head_radius * 0.035, 0.003), _color("ink"), Vector3.ZERO, true)
	_add_sphere(_face_root, "CheekLeft", Vector3(-head_radius * 0.42, -head_radius * 0.18, -head_radius + 0.004), Vector3(head_radius * 0.11, head_radius * 0.06, 0.005), _color("accent"), Vector3(0.0, 0.45, 0.0), true)
	_add_sphere(_face_root, "CheekRight", Vector3(head_radius * 0.42, -head_radius * 0.18, -head_radius + 0.004), Vector3(head_radius * 0.11, head_radius * 0.06, 0.005), _color("accent"), Vector3(0.0, -0.45, 0.0), true)


func _build_pup_face(head_radius: float) -> void:
	if _head.has("snout"):
		# The sculpted SDF snout replaces the muzzle decal; the nose and
		# mouth ride out to its tip.
		var snout := _head.get("snout") as Dictionary
		var tip_z := (
			-head_radius * 0.5
			- float(snout.get("length", 0.55)) * head_radius
		)
		var tip_y := (
			float(snout.get("drop", -0.12)) * head_radius
			- float(snout.get("dip", 0.2))
			* float(snout.get("length", 0.55)) * head_radius
		)
		var snout_radius := float(snout.get("radius", 0.42)) * head_radius
		var tip_radius := (
			snout_radius * clampf(float(snout.get("taper", 0.7)), 0.3, 1.2)
		)
		var eye_scale_snouted := Vector3(head_radius * 0.11, head_radius * 0.15, 0.007)
		var eye_left_snouted := _add_sphere(_face_root, "EyeLeft", Vector3(-head_radius * 0.3, head_radius * 0.12, -head_radius - 0.004), eye_scale_snouted, _color("ink"), Vector3.ZERO, true)
		var eye_right_snouted := _add_sphere(_face_root, "EyeRight", Vector3(head_radius * 0.3, head_radius * 0.12, -head_radius - 0.004), eye_scale_snouted, _color("ink"), Vector3.ZERO, true)
		_register_eyes(eye_left_snouted, eye_right_snouted)
		_add_sphere(_face_root, "GlintLeft", Vector3(-head_radius * 0.34, head_radius * 0.18, -head_radius - 0.011), Vector3(0.005, 0.006, 0.003), Color("#FFF8E4"), Vector3.ZERO, true)
		_add_sphere(_face_root, "GlintRight", Vector3(head_radius * 0.26, head_radius * 0.18, -head_radius - 0.011), Vector3(0.005, 0.006, 0.003), Color("#FFF8E4"), Vector3.ZERO, true)
		_add_sphere(_face_root, "Nose", Vector3(0.0, tip_y + tip_radius * 0.35, tip_z - tip_radius * 0.72), Vector3(tip_radius * 0.5, tip_radius * 0.38, 0.008), _color("ink"), Vector3.ZERO, true)
		_add_sphere(_face_root, "BrowLeft", Vector3(-head_radius * 0.3, head_radius * 0.34, -head_radius + 0.002), Vector3(head_radius * 0.11, head_radius * 0.045, 0.005), _color("accent"), Vector3.ZERO, true)
		_add_sphere(_face_root, "BrowRight", Vector3(head_radius * 0.3, head_radius * 0.34, -head_radius + 0.002), Vector3(head_radius * 0.11, head_radius * 0.045, 0.005), _color("accent"), Vector3.ZERO, true)
		return
	_add_sphere(_face_root, "Muzzle", Vector3(0.0, -head_radius * 0.22, -head_radius - 0.006), Vector3(head_radius * 0.42, head_radius * 0.33, head_radius * 0.28), _color_for("face_patch"))
	var eye_scale := Vector3(head_radius * 0.11, head_radius * 0.15, 0.007)
	var eye_left := _add_sphere(_face_root, "EyeLeft", Vector3(-head_radius * 0.30, head_radius * 0.12, -head_radius - 0.004), eye_scale, _color("ink"), Vector3.ZERO, true)
	var eye_right := _add_sphere(_face_root, "EyeRight", Vector3(head_radius * 0.30, head_radius * 0.12, -head_radius - 0.004), eye_scale, _color("ink"), Vector3.ZERO, true)
	_register_eyes(eye_left, eye_right)
	_add_sphere(_face_root, "GlintLeft", Vector3(-head_radius * 0.34, head_radius * 0.18, -head_radius - 0.011), Vector3(0.005, 0.006, 0.003), Color("#FFF8E4"), Vector3.ZERO, true)
	_add_sphere(_face_root, "GlintRight", Vector3(head_radius * 0.26, head_radius * 0.18, -head_radius - 0.011), Vector3(0.005, 0.006, 0.003), Color("#FFF8E4"), Vector3.ZERO, true)
	_add_sphere(_face_root, "Nose", Vector3(0.0, -head_radius * 0.13, -head_radius - head_radius * 0.28), Vector3(head_radius * 0.1, head_radius * 0.08, 0.006), _color("ink"), Vector3.ZERO, true)
	_add_sphere(_face_root, "BrowLeft", Vector3(-head_radius * 0.30, head_radius * 0.34, -head_radius + 0.002), Vector3(head_radius * 0.11, head_radius * 0.045, 0.005), _color("accent"), Vector3.ZERO, true)
	_add_sphere(_face_root, "BrowRight", Vector3(head_radius * 0.30, head_radius * 0.34, -head_radius + 0.002), Vector3(head_radius * 0.11, head_radius * 0.045, 0.005), _color("accent"), Vector3.ZERO, true)


func _update_overlays() -> void:
	_face_root.transform = Transform3D(_head_basis(), _head_position)
	var breath := 1.0 + sin(_breath_phase) * 0.016 * (0.4 + 0.6 * _idle_factor)
	_belly_root.transform = Transform3D(
		Basis.from_euler(_body_rotation).scaled(Vector3.ONE * breath),
		_body_position
	)
	_belly_root.visible = _is_upright()


# ------------------------------------------------------------------ pose math

func _reset_pose() -> void:
	_body_position = Vector3(0.0, _body_rest_height(), 0.0)
	_head_position = _body_position + _head_offset()
	_leg_rests = _compute_leg_rests()
	_leg_phases = _compute_leg_phases()
	_feet = []
	_feet_velocities = []
	for rest in _leg_rests:
		_feet.append(Vector3(rest.x, _foot_radius() * 0.85, rest.z))
		_feet_velocities.append(Vector3.ZERO)
	var ear_count := clampi(int(_ears.get("count", 0)), 0, 2)
	_ear_tips = []
	_ear_velocities = []
	var head_basis := Basis.IDENTITY
	for ear_index in ear_count:
		_ear_tips.append(
			_ear_base(ear_index, head_basis)
			+ _ear_direction(_ear_side(ear_index)) * float(_ears.get("length", 0.1))
		)
		_ear_velocities.append(Vector3.ZERO)
	var segment_count := clampi(int(_tail.get("segments", 0)), 0, 3)
	_tail_points = []
	_tail_previous = []
	var anchor := _body_position + _tail_base_offset()
	var segment_length := float(_tail.get("length", 0.12)) / maxf(float(segment_count), 1.0)
	for segment_index in segment_count:
		anchor += Vector3(0.0, -0.2, 0.98).normalized() * segment_length
		_tail_points.append(anchor)
		_tail_previous.append(anchor)
	_update_shell(0.0, MotionState.new())
	_update_overlays()


func _compute_leg_rests() -> Array[Vector3]:
	var rests: Array[Vector3] = []
	var stance := float(_legs.get("stance", 0.1)) * 0.5
	match _leg_count:
		0:
			pass
		1:
			rests.append(Vector3(0.0, 0.0, 0.0))
		2:
			rests.append(Vector3(-stance, 0.0, 0.0))
			rests.append(Vector3(stance, 0.0, 0.0))
		_:
			var pairs := _leg_count / 2
			var torso_span := float(_torso.get("length", 0.16)) * 0.5
			for pair_index in pairs:
				var along := (
					lerpf(-1.0, 1.0, float(pair_index) / maxf(float(pairs - 1), 1.0))
					* (torso_span - float(_legs.get("inset", 0.02)))
				)
				rests.append(Vector3(-stance, 0.0, along))
				rests.append(Vector3(stance, 0.0, along))
	return rests


func _compute_leg_phases() -> Array[float]:
	var phases: Array[float] = []
	match _leg_count:
		1:
			phases = [0.0]
		2:
			phases = [0.0, PI]
		4:
			# Diagonal trot with a touch of rear lag so it reads organic.
			phases = [0.0, PI, PI + 0.25, 0.25]
		6:
			# Alternating tripod.
			phases = [0.0, PI, PI, 0.0, 0.0, PI]
		_:
			for leg_index in _leg_count:
				phases.append(PI * float(leg_index % 2))
	return phases


func _two_bone_joint(
	start: Vector3,
	end: Vector3,
	upper_length: float,
	lower_length: float,
	bend_hint: Vector3
) -> Vector3:
	var to_end := end - start
	var distance := clampf(
		to_end.length(), 0.001, upper_length + lower_length - 0.001
	)
	var direction := (
		to_end.normalized() if to_end.length_squared() > 0.000001 else Vector3.DOWN
	)
	var along := (
		(upper_length * upper_length - lower_length * lower_length
		+ distance * distance) / (2.0 * distance)
	)
	var height := sqrt(maxf(upper_length * upper_length - along * along, 0.0))
	var bend := bend_hint - direction * bend_hint.dot(direction)
	if bend.length_squared() < 0.0001:
		bend = direction.cross(Vector3.RIGHT)
	return start + direction * along + bend.normalized() * height


func _head_basis() -> Basis:
	return Basis.from_euler(
		Vector3(
			_body_rotation.x * 0.25 + _head_look.x
			+ _action_head_pitch * _action_weight,
			_head_look.y,
			_body_rotation.z * 0.25 + _head_tilt
		)
	)


## A lone ear (antenna) sits centered; a pair sits mirrored.
func _ear_side(ear_index: int) -> float:
	if clampi(int(_ears.get("count", 0)), 0, 2) == 1:
		return 0.0
	return -1.0 if ear_index == 0 else 1.0


func _ear_base(ear_index: int, head_basis: Basis) -> Vector3:
	var side := _ear_side(ear_index)
	var head_radius := float(_head.get("radius", 0.1))
	var style := String(_ears.get("style", "up"))
	var local := Vector3(side * head_radius * 0.4, head_radius * 0.68, 0.012)
	if style == "side":
		local = Vector3(side * head_radius * 0.82, head_radius * 0.3, 0.008)
	return _head_position + head_basis * local


func _ear_direction(side: float) -> Vector3:
	match String(_ears.get("style", "up")):
		"side":
			return Vector3(side * 0.72, -0.62, 0.1).normalized()
		"tuft":
			return Vector3(side * 0.34, 0.93, -0.05).normalized()
		_:
			return Vector3(side * 0.2, 0.97, 0.06).normalized()


func _tail_base_offset() -> Vector3:
	if _is_upright():
		return Vector3(0.0, -_torso_radius() * 0.35, _torso_radius() * 0.62)
	return Vector3(
		0.0, _torso_radius() * 0.1, float(_torso.get("length", 0.16)) * 0.5 + 0.01
	)


func _head_offset() -> Vector3:
	var offset: Variant = _head.get("offset")
	if offset is Array and (offset as Array).size() >= 3:
		return Vector3(
			float((offset as Array)[0]),
			float((offset as Array)[1]),
			float((offset as Array)[2])
		)
	if _is_upright():
		return Vector3(0.0, _torso_radius() + float(_head.get("radius", 0.1)) * 0.8, -0.006)
	return Vector3(
		0.0,
		_torso_radius() * 0.7 + float(_head.get("radius", 0.1)) * 0.45,
		-float(_torso.get("length", 0.16)) * 0.5 - float(_head.get("radius", 0.1)) * 0.35
	)


func _body_rest_height() -> float:
	var explicit: Variant = _torso.get("height")
	if explicit != null:
		return float(explicit)
	var leg_length := float(_legs.get("length", 0.2))
	if _leg_count == 0:
		return _torso_radius() * 1.05
	if _is_hop_plan():
		# Hoppers rest on deeply bent legs, coiled to launch.
		return leg_length * 0.78 + _foot_radius() * 0.6
	return leg_length * 0.92 + _foot_radius() * 0.6


func _hip_drop() -> float:
	if _is_hop_plan():
		# A hopper's hips ride high on the torso so the deeply bent knees
		# read as haunches instead of poking out at ground level.
		return -_torso_radius() * 0.55
	if _is_upright():
		return -_torso_radius() * 0.9 - float(_torso.get("length", 0.09)) * 0.3
	return -_torso_radius() * 0.55


func _hop_height() -> float:
	return maxf(sin(_hop_phase), 0.0) * float(_gait.get("hop_lift", 0.07))


func _torso_rest_pitch() -> float:
	return deg_to_rad(float(_torso.get("pitch", 0.0)))


func _torso_radius() -> float:
	return float(_torso.get("radius", 0.1))


func _foot_radius() -> float:
	return float(_legs.get("foot_radius", 0.026))


func _is_upright() -> bool:
	var stance := String(_torso.get("stance", ""))
	if stance == "horizontal":
		return false
	return _leg_count <= 2 or stance == "upright"


func _is_hop_plan() -> bool:
	return _plan == "hopper"


func _has_wings() -> bool:
	return _plan == "flyer" or not _wings.is_empty()


func _has_foot_balls() -> bool:
	return _leg_count <= 4 and bool(_legs.get("foot_balls", true))


func _default_leg_segments() -> int:
	return 2 if _leg_count <= 2 else 1


func _wing_scale() -> float:
	return float(_wings.get("thickness", 1.0))


func _build_neighbors() -> Array:
	var neighbors: Array = []
	for shape_index in shape_budget():
		neighbors.append([0])
	neighbors[0] = [1]
	return neighbors


# ------------------------------------------------------------------ helpers

func _append_shape(
	shape_a: Array[Vector4],
	shape_b: Array[Vector4],
	colors: Array[Vector4],
	endpoint_a: Vector3,
	endpoint_b: Vector3,
	radius: float,
	blend_radius: float,
	color: Color,
	radius_b := -1.0
) -> void:
	shape_a.append(Vector4(endpoint_a.x, endpoint_a.y, endpoint_a.z, radius))
	shape_b.append(Vector4(endpoint_b.x, endpoint_b.y, endpoint_b.z, blend_radius))
	colors.append(Vector4(color.r, color.g, color.b, color.a))
	_radius_b_buffer.append(radius_b if radius_b > 0.0 else radius)


func _register_eyes(eye_left: MeshInstance3D, eye_right: MeshInstance3D) -> void:
	_eye_nodes = [eye_left, eye_right]
	_eye_base_scales = [eye_left.scale, eye_right.scale]


func _add_sphere(
	parent: Node3D,
	node_name: String,
	position: Vector3,
	scale_value: Vector3,
	color: Color,
	rotation_value := Vector3.ZERO,
	_unshaded := false
) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 18
	sphere.rings = 9
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = sphere
	instance.position = position
	instance.rotation = rotation_value
	instance.scale = scale_value
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	material.metallic = 0.0
	# Every decal is an unshaded sticker: solid fills that match the shell's
	# flat cel look and never go muddy when the key light is behind the body.
	material.disable_receive_shadows = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _color(key: String) -> Color:
	return Color(String(_palette.get(key, "#FFFFFF")))


## Part colors resolve through the palette with sensible fallbacks, so a
## minimal palette of body/face/accent/ink still dresses a full creature.
func _color_for(part: String) -> Color:
	match part:
		"torso":
			return _color("body")
		"head":
			return (
				_color("body_light") if _palette.has("body_light")
				else _color("body").lightened(0.12)
			)
		"limb":
			return (
				_color("limb") if _palette.has("limb")
				else _color("body").darkened(0.08)
			)
		"arm":
			return _color_for("head")
		"foot":
			return (
				_color("foot") if _palette.has("foot")
				else _color("accent").darkened(0.1)
			)
		"wing":
			return (
				_color("wing") if _palette.has("wing")
				else _color("body").darkened(0.14)
			)
		"tail":
			return _color("body").darkened(0.1)
		"ear":
			return (
				_color("ear") if _palette.has("ear")
				else _color("accent")
			)
		"belly":
			return (
				_color("belly") if _palette.has("belly")
				else _color("face").darkened(0.06)
			)
		"face_patch":
			return _color("face")
	return _color("body")
