class_name PlayerVisual
extends Node3D
## Builds the rounded life-sim keeper from character_proxy.glb, applies the
## profile's customization (skin, hair, eyes, outfit), attaches equipment
## visuals, and drives all procedural animation (walk bob, chop, cast, dodge,
## hit flash, celebrate). A future Tier C rigged character replaces this by
## exposing the same play() state names.

const WALK_BOB_HZ := 7.5

signal animation_started(animation_name: String)
signal animation_event(animation_name: String, event_name: String)
signal animation_finished(animation_name: String)

const ANIMATION_MANIFEST := {
	"idle": {
		"looping": true,
		"duration": 2.4,
		"events": [],
		"procedural_tracks": {
			"body.position.y": "sin(time * TAU / 2.4) * 0.006",
			"head.rotation.z": "sin(time * TAU / 4.8) * 0.008",
		},
	},
	"walk": {
		"looping": true,
		"duration": 0.84,
		"events": [{"name": "left_step", "time": 0.0}, {"name": "right_step", "time": 0.42}],
		"procedural_tracks": {
			"body.position.y": "abs(sin(phase)) * 0.05",
			"body.rotation.x": 0.06,
			"arms.rotation.x": "opposed sin(phase) * 0.55",
		},
	},
	"fish_cast": {
		"looping": false,
		"duration": 0.38,
		"events": [{"name": "release", "time": 0.22}],
		"tracks": {
			"right_arm.rotation.x": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.22, "value": -2.2, "curve": "back_out"},
				{"time": 0.38, "value": -0.9, "curve": "cubic_in"},
			],
		},
	},
	"fish_wait": {
		"looping": true,
		"duration": 1.3,
		"events": [],
		"tracks": {
			"right_arm.rotation.x": [
				{"time": 0.0, "value": -0.9},
				{"time": 0.4, "value": -0.95, "curve": "linear"},
				{"time": 1.3, "value": -0.85, "curve": "sine_in_out"},
			],
		},
	},
	"fish_catch": {
		"looping": false,
		"duration": 0.69,
		"events": [{"name": "impact", "time": 0.14}],
		"tracks": {
			"right_arm.rotation.x": [
				{"time": 0.0, "value": -0.9},
				{"time": 0.14, "value": -2.5, "curve": "back_out"},
			],
			"body.rotation.x": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.14, "value": -0.12, "curve": "linear"},
				{"time": 0.49, "value": -0.12},
				{"time": 0.69, "value": 0.0, "curve": "linear"},
			],
		},
	},
	"chop": {
		"looping": false,
		"duration": 0.52,
		"events": [{"name": "impact", "time": 0.38}],
		"tracks": {
			"right_arm.rotation.x": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.28, "value": -2.4, "curve": "quad_out"},
				{"time": 0.38, "value": -0.3, "curve": "quart_in"},
			],
			"body.rotation.y": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.28, "value": 0.16, "curve": "linear"},
				{"time": 0.38, "value": -0.08, "curve": "linear"},
				{"time": 0.52, "value": 0.0, "curve": "linear"},
			],
		},
	},
	"attack": {
		"looping": false,
		"duration": 0.38,
		"events": [{"name": "impact", "time": 0.22}],
		"tracks": {
			"right_arm.rotation.x": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.12, "value": -2.1, "curve": "quad_out"},
				{"time": 0.22, "value": 0.5, "curve": "quart_in"},
				{"time": 0.38, "value": 0.0, "curve": "linear"},
			],
		},
	},
	"dodge": {
		"looping": false,
		"duration": 0.3,
		"events": [],
		"tracks": {
			"body.rotation.x": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.1, "value": 0.5, "curve": "linear"},
				{"time": 0.3, "value": 0.0, "curve": "linear"},
			],
		},
	},
	"hit": {
		"looping": false,
		"duration": 0.18,
		"events": [{"name": "flash", "time": 0.0}],
		"tracks": {
			"body.position.x": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.05, "value": 0.07, "curve": "linear"},
				{"time": 0.1, "value": -0.05, "curve": "linear"},
				{"time": 0.18, "value": 0.0, "curve": "linear"},
			],
		},
	},
	"celebrate": {
		"looping": false,
		"duration": 0.7,
		"events": [{"name": "apex", "time": 0.2}],
		"tracks": {
			"arms.rotation.x": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.2, "value": -2.9, "curve": "back_out"},
				{"time": 0.4, "value": -2.9},
				{"time": 0.7, "value": 0.0, "curve": "linear"},
			],
			"body.position.y": [
				{"time": 0.0, "value": 0.0},
				{"time": 0.18, "value": 0.16, "curve": "quad_out"},
				{"time": 0.4, "value": 0.0, "curve": "bounce_out"},
			],
		},
	},
}
const ANIMATION_TRANSITIONS := {
	"idle": ["walk", "fish_cast", "fish_wait", "fish_catch", "chop", "attack", "dodge", "hit", "celebrate"],
	"walk": ["idle", "fish_cast", "chop", "attack", "dodge", "hit", "celebrate"],
	"fish_cast": ["fish_wait", "fish_catch", "idle", "walk"],
	"fish_wait": ["fish_catch", "idle", "walk"],
	"fish_catch": ["fish_cast", "fish_wait", "idle", "walk"],
	"chop": ["chop", "idle", "walk"],
	"attack": ["attack", "dodge", "hit", "idle", "walk"],
	"dodge": ["attack", "hit", "idle", "walk"],
	"hit": ["attack", "dodge", "idle", "walk"],
	"celebrate": ["idle", "walk"],
}

var materials: MaterialLibrary
var assets: AssetLibrary
var palette: CozyPalette

var _body: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _head_group: Node3D
var _tool_mount: Node3D
var _back_mount: Node3D
var _head_mount: Node3D
var _hair_nodes: Array[Node3D] = []
var _eye_nodes: Array[MeshInstance3D] = []

var _walk_amount := 0.0
var _walk_phase := 0.0
var _idle_phase := 0.0
var _action_tween: Tween
var _current_anim := "idle"


func build(asset_library: AssetLibrary, pal: CozyPalette) -> void:
	assets = asset_library
	materials = asset_library.materials
	palette = pal
	_body = assets.instantiate("character_proxy")
	add_child(_body)
	_collect_parts()


func _collect_parts() -> void:
	_hair_nodes.clear()
	_eye_nodes.clear()
	for i in 4:
		var hair := _find("Hair%02d" % i)
		if hair != null:
			_hair_nodes.append(hair)
	# The bun/fall sub-meshes follow their parent style visibility.
	for extra_name in [
		"Hair00_bangL", "Hair00_bangR", "Hair01_tuft",
		"Hair02_bun", "Hair03_fall",
	]:
		var extra := _find(extra_name)
		if extra != null:
			_hair_nodes.append(extra)
	for eye_name in ["EyeL", "EyeR", "EyeHighlightL", "EyeHighlightR"]:
		var eye := _find(eye_name) as MeshInstance3D
		if eye != null:
			_eye_nodes.append(eye)

	# Shoulder pivots so arms swing naturally; hands ride along.
	_arm_r = _wrap_pivot("ArmRPivot", Vector3(0.22, 0.66, 0.0), ["ArmR", "HandR"])
	_arm_l = _wrap_pivot("ArmLPivot", Vector3(-0.22, 0.66, 0.0), ["ArmL", "HandL"])
	_head_group = _wrap_pivot("HeadPivot", Vector3(0, 0.69, 0), [
		"Head", "EarL", "EarR", "EyeL", "EyeR", "EyeHighlightL",
		"EyeHighlightR", "Nose", "CheekL", "CheekR", "MouthL", "MouthR",
		"Hair00", "Hair00_bangL", "Hair00_bangR", "Hair01", "Hair01_tuft",
		"Hair02", "Hair02_bun", "Hair03", "Hair03_fall",
	])

	_tool_mount = Node3D.new()
	_tool_mount.name = "ToolMount"
	_tool_mount.position = Vector3(0.05, -0.36, -0.06)  # at the hand, relative to shoulder pivot
	_arm_r.add_child(_tool_mount)
	_back_mount = Node3D.new()
	_back_mount.name = "BackMount"
	_back_mount.position = Vector3(0, 0.72, 0.24)
	add_child(_back_mount)
	_head_mount = Node3D.new()
	_head_mount.name = "HeadMount"
	_head_mount.position = Vector3(0, 0.42, 0)
	_head_group.add_child(_head_mount)


func _find(node_name: String) -> Node3D:
	return _body.find_child(node_name, true, false) as Node3D


func _wrap_pivot(pivot_name: String, pivot_pos: Vector3, part_names: Array) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	_body.add_child(pivot)
	pivot.position = pivot_pos
	for part_name in part_names:
		var part := _find(part_name)
		if part == null or part == pivot or part.get_parent() == pivot:
			continue
		var global := part.global_transform
		part.get_parent().remove_child(part)
		pivot.add_child(part)
		part.global_transform = global
	return pivot


# ------------------------------------------------------------------ customization

func apply_profile(profile: PlayerProfile) -> void:
	var skin := palette.skin_tones[clampi(profile.skin_index, 0, palette.skin_tones.size() - 1)]
	var hair := palette.hair_colors[clampi(profile.hair_color_index, 0, palette.hair_colors.size() - 1)]
	var outfit := palette.outfit_colors[clampi(profile.outfit_index, 0, palette.outfit_colors.size() - 1)]
	_tint_parts(["Head", "EarL", "EarR", "HandL", "HandR"], materials.tinted("skin", skin))
	_tint_parts(["Nose"], materials.tinted("skin", skin.darkened(0.08)))
	_tint_parts(["CheekL", "CheekR"], materials.tinted("petal_pink", skin.lerp(palette.color("petal_pink"), 0.34)))
	_tint_parts([
		"Hair00", "Hair00_bangL", "Hair00_bangR", "Hair01", "Hair01_tuft",
		"Hair02", "Hair02_bun", "Hair03", "Hair03_fall",
	], materials.tinted("hair", hair))
	_tint_parts(["Torso", "ArmL", "ArmR"], materials.tinted("fabric", outfit))
	_tint_parts(["Belt", "Collar"], materials.material("fabric_accent"))
	for i in _hair_nodes.size():
		var node := _hair_nodes[i]
		var style_index := profile.hair_style
		node.visible = node.name.begins_with("Hair%02d" % style_index)
	match profile.eye_index:
		1:  # sleepy
			for eye in _eye_nodes:
				eye.scale = Vector3(1.0, 0.55, 1.0)
		2:  # bright
			for eye in _eye_nodes:
				eye.scale = Vector3(1.3, 1.3, 1.3)
		_:
			for eye in _eye_nodes:
				eye.scale = Vector3.ONE


func _tint_parts(part_names: Array, mat: Material) -> void:
	for part_name in part_names:
		var part := _find(part_name) as MeshInstance3D
		if part == null:
			continue
		for surface in part.mesh.get_surface_count():
			part.set_surface_override_material(surface, mat)


## Equipment: tool/weapon in hand, hood on head, cape on back, body recolor.
func apply_equipment(equipment: EquipmentManager, held_tool_type := "") -> void:
	for mount in [_tool_mount, _back_mount, _head_mount]:
		for child in mount.get_children():
			child.queue_free()
	var held: Defs.ItemDefinition = null
	if held_tool_type != "":
		held = equipment.best_tool(held_tool_type)
	if held == null:
		held = equipment.equipped_in("weapon") if held_tool_type == "weapon" else equipment.equipped_in("tool")
	if held != null and held.asset_id != "":
		var tool_visual := assets.instantiate(held.asset_id)
		tool_visual.rotation_degrees = Vector3(-52, 0, 0)
		_tool_mount.add_child(tool_visual)
	var head_item := equipment.equipped_in("head")
	if head_item != null and head_item.asset_id != "":
		var head_visual := assets.instantiate(head_item.asset_id)
		head_visual.scale = Vector3.ONE * 1.35
		_head_mount.add_child(head_visual)
	var back_item := equipment.equipped_in("back")
	if back_item != null and back_item.asset_id != "":
		_back_mount.add_child(assets.instantiate(back_item.asset_id))
	var body_item := equipment.equipped_in("body")
	if body_item != null:
		_tint_parts(["Torso", "ArmL", "ArmR"], materials.tinted("fabric", palette.color("moss").lightened(0.1)))


# ------------------------------------------------------------------ animation

func set_walk(amount: float, delta: float) -> void:
	_walk_amount = lerpf(_walk_amount, clampf(amount, 0.0, 1.0), 12.0 * delta)
	_walk_phase += delta * WALK_BOB_HZ * (0.4 + 0.6 * _walk_amount)
	_idle_phase += delta * TAU / 2.4
	if _current_anim != "idle":
		return
	var bob := absf(sin(_walk_phase)) * 0.05 * _walk_amount
	if _walk_amount < 0.05:
		bob += sin(_idle_phase) * 0.006
		_head_group.rotation.z = sin(_idle_phase * 0.5) * 0.008
	else:
		_head_group.rotation.z = lerpf(_head_group.rotation.z, 0.0, minf(1.0, delta * 8.0))
	_body.position.y = bob
	_body.rotation.x = _walk_amount * 0.06
	var swing := sin(_walk_phase) * 0.55 * _walk_amount
	_arm_r.rotation.x = swing
	_arm_l.rotation.x = -swing


func play(anim: String) -> void:
	if not ANIMATION_MANIFEST.has(anim):
		return
	if _action_tween != null and _action_tween.is_valid():
		_action_tween.kill()
		if _current_anim != "idle":
			animation_finished.emit(_current_anim)
	_current_anim = anim
	animation_started.emit(anim)
	_action_tween = create_tween()
	match anim:
		"idle":
			_action_tween.tween_property(_arm_r, "rotation", Vector3.ZERO, 0.18)
			_action_tween.parallel().tween_property(_arm_l, "rotation", Vector3.ZERO, 0.18)
			_action_tween.parallel().tween_property(_body, "rotation", Vector3.ZERO, 0.18)
			_action_tween.tween_callback(func():
				_current_anim = "idle"
				animation_finished.emit("idle")
			)
			_current_anim = "idle"
		"fish_cast":
			_action_tween.tween_property(_arm_r, "rotation:x", -2.2, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_action_tween.tween_callback(func(): animation_event.emit(anim, "release"))
			_action_tween.tween_property(_arm_r, "rotation:x", -0.9, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		"fish_wait":
			_action_tween.tween_property(_arm_r, "rotation:x", -0.95, 0.4)
			_action_tween.tween_property(_arm_r, "rotation:x", -0.85, 0.9).set_trans(Tween.TRANS_SINE)
			_action_tween.set_loops()
		"fish_catch":
			_action_tween.tween_property(_arm_r, "rotation:x", -2.5, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_action_tween.parallel().tween_property(_body, "rotation:x", -0.12, 0.14)
			_action_tween.tween_callback(func(): animation_event.emit(anim, "impact"))
			_action_tween.tween_interval(0.35)
			_action_tween.tween_property(_body, "rotation:x", 0.0, 0.2)
		"chop":
			_action_tween.tween_property(_arm_r, "rotation:x", -2.4, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_action_tween.parallel().tween_property(_body, "rotation:y", 0.16, 0.28)
			_action_tween.tween_property(_arm_r, "rotation:x", -0.3, 0.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
			_action_tween.parallel().tween_property(_body, "rotation:y", -0.08, 0.1)
			_action_tween.tween_callback(func(): animation_event.emit(anim, "impact"))
			_action_tween.tween_property(_body, "rotation:y", 0.0, 0.14)
		"attack":
			_action_tween.tween_property(_arm_r, "rotation:x", -2.1, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_action_tween.tween_property(_arm_r, "rotation:x", 0.5, 0.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
			_action_tween.tween_callback(func(): animation_event.emit(anim, "impact"))
			_action_tween.tween_property(_arm_r, "rotation:x", 0.0, 0.16)
		"dodge":
			_action_tween.tween_property(_body, "rotation:x", 0.5, 0.1)
			_action_tween.tween_property(_body, "rotation:x", 0.0, 0.2)
		"hit":
			animation_event.emit(anim, "flash")
			_flash(Color(1.0, 0.5, 0.45))
			_action_tween.tween_property(_body, "position:x", 0.07, 0.05)
			_action_tween.tween_property(_body, "position:x", -0.05, 0.05)
			_action_tween.tween_property(_body, "position:x", 0.0, 0.08)
		"celebrate":
			_action_tween.tween_property(_arm_r, "rotation:x", -2.9, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_action_tween.parallel().tween_property(_arm_l, "rotation:x", -2.9, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_action_tween.parallel().tween_property(_body, "position:y", 0.16, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_action_tween.tween_callback(func(): animation_event.emit(anim, "apex"))
			_action_tween.tween_property(_body, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			_action_tween.parallel().tween_property(_arm_r, "rotation:x", 0.0, 0.3)
			_action_tween.parallel().tween_property(_arm_l, "rotation:x", 0.0, 0.3)
	if anim != "idle" and anim != "fish_wait":
		_action_tween.tween_callback(func():
			_current_anim = "idle"
			animation_finished.emit(anim)
		)


func animation_manifest() -> Dictionary:
	return {
		"states": ANIMATION_MANIFEST.duplicate(true),
		"transitions": ANIMATION_TRANSITIONS.duplicate(true),
		"default_state": "idle",
		"transition_policy": {
			"interruptible": true,
			"interruption_reset": "previous tween is killed before the next state",
			"action_to_idle": "automatic on non-looping completion",
		},
	}


func _flash(color: Color) -> void:
	var head := _find("Head") as MeshInstance3D
	if head == null:
		return
	var overlay := materials.tinted("skin", color)
	var restore: Material = head.get_surface_override_material(0)
	head.set_surface_override_material(0, overlay)
	get_tree().create_timer(0.12).timeout.connect(func():
		if is_instance_valid(head):
			head.set_surface_override_material(0, restore))
