class_name VoidFishingPresentation
extends Node3D
## Owns the physical mystery of fishing beyond the world: a live line from the
## rod, the same dark rift used by the keeper's rescue, and the actual rolled
## build piece rising from the deep before settling into the keeper's hands.

const RIFT_SHADER: Shader = preload(
	"res://assets/materials/reworked/rescue_black_hole.gdshader"
)
const StructureVisualFactoryScript := preload(
	"res://scripts/world/structure_visual_factory.gd"
)

const LINE_RADIUS := 0.009
const RIFT_SIZE := 0.81
const RIFT_DEPTH := 1.15
const REWARD_MAX_SPAN := 0.52
const REWARD_MAX_HEIGHT := 0.62

var core: GameCore
var assets: AssetLibrary
var player: PlayerController
var player_visual: PlayerVisual
var _tile_factory: TileVisualFactory
var _structure_factory: RefCounted

var _rift: MeshInstance3D
var _surface_line: MeshInstance3D
var _reward: Node3D
var _reward_scale := Vector3.ONE

var _surface_point := Vector3.ZERO
var _cast_point := Vector3.ZERO
var _cast_progress := 0.0
var _phase := 0.0
var _sequence_id := 0
var _active := false
var _pulling_reward := false
var _carrying_reward := false
var _carried_kind := ""
var _carried_id := ""
var _line_tween: Tween
var _rift_tween: Tween


func setup(
	game_core: GameCore,
	asset_library: AssetLibrary,
	player_controller: PlayerController,
	visual: PlayerVisual
) -> void:
	core = game_core
	assets = asset_library
	player = player_controller
	player_visual = visual
	_tile_factory = TileVisualFactory.new(assets, core.grid)
	_structure_factory = StructureVisualFactoryScript.new(assets, core.grid)


func begin_cast(point: Vector3) -> void:
	_sequence_id += 1
	_stop_transient_tweens()
	_clear_transient()
	_discard_carried_reward()
	_surface_point = point
	# The rescue presentation places its swallow portal exactly 1.15 m below
	# the falling keeper. Fishing uses that same lower plane so the line truly
	# descends into the unknown instead of ending on the buildable surface.
	_cast_point = point + Vector3.DOWN * RIFT_DEPTH
	_cast_progress = 0.0
	_phase = 0.0
	_active = true
	_pulling_reward = false
	_build_rift()
	_surface_line = _line_mesh(
		"FishingLineToUnknown",
		Color(0.92, 0.86, 0.68, 0.96),
		LINE_RADIUS
	)
	add_child(_surface_line)
	_line_tween = create_tween()
	_line_tween.tween_property(self, "_cast_progress", 1.0, 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Match PlayerController._grow_hole directly on the mesh. The previous
	# variable-to-_process bridge introduced a one-frame delay, while creating
	# the mesh at full scale could expose a flash before that first update.
	_rift_tween = create_tween()
	_rift_tween.tween_interval(0.28)
	_rift_tween.tween_property(
		_rift,
		"scale",
		Vector3.ONE * 0.38,
		0.1
	) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_rift_tween.tween_property(_rift, "scale", Vector3.ONE, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func bite() -> void:
	if not _active:
		return
	# The mystery stays visually plain; only the taut line gives a small bite
	# tug while the rescue-style black disc remains unchanged.
	if _line_tween != null and _line_tween.is_valid():
		_line_tween.kill()
	_line_tween = create_tween()
	_line_tween.tween_property(self, "_cast_progress", 0.92, 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_line_tween.tween_property(self, "_cast_progress", 1.0, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func retrieve_reward(entry: Dictionary) -> void:
	if not _active:
		return
	var sequence := _sequence_id
	_reward = _build_reward(entry)
	if _reward == null:
		return
	add_child(_reward)
	_reward.position = _cast_point + Vector3.DOWN * 0.55
	_reward.scale = _reward_scale * 0.08
	_reward.rotation = Vector3(0.18, -0.45, -0.12)
	_pulling_reward = true
	var reveal_point := _surface_point + Vector3.UP * 0.72
	var pull := _reward.create_tween()
	pull.set_parallel()
	pull.tween_property(_reward, "position", reveal_point, 0.46) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pull.tween_property(_reward, "scale", _reward_scale, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pull.tween_property(
		_reward,
		"rotation",
		Vector3(-0.08, PI * 0.65, 0.08),
		0.46
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await pull.finished
	if sequence != _sequence_id or not is_instance_valid(_reward):
		return
	_pulling_reward = false
	if is_instance_valid(_surface_line):
		_surface_line.visible = false
	_close_rift()
	var start := _reward.position
	var destination := player_visual.reward_hold_world_position()
	var midpoint := (
		(start + destination) * 0.5
		+ Vector3.UP * 0.72
	)
	var fly_along := func(t: float) -> void:
		if not is_instance_valid(_reward):
			return
		var a := start.lerp(midpoint, t)
		var b := midpoint.lerp(destination, t)
		_reward.position = a.lerp(b, t)
	var flight := _reward.create_tween()
	flight.set_parallel()
	flight.tween_method(fly_along, 0.0, 1.0, 0.52) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	flight.tween_property(
		_reward,
		"rotation",
		_reward.rotation + Vector3(0.4, TAU * 1.25, -0.3),
		0.52
	).set_trans(Tween.TRANS_QUAD)
	flight.tween_property(_reward, "scale", _reward_scale * 0.86, 0.52) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	await flight.finished
	if sequence != _sequence_id or not is_instance_valid(_reward):
		return
	_active = false
	_carrying_reward = true
	_carried_kind = String(entry.get("kind", ""))
	_carried_id = String(entry.get("id", ""))
	_clear_transient()


func consume_carried_reward() -> void:
	if not _carrying_reward or not is_instance_valid(_reward):
		_discard_carried_reward()
		return
	var reward := _reward
	_reward = null
	_carrying_reward = false
	_carried_kind = ""
	_carried_id = ""
	var tuck := reward.create_tween()
	tuck.set_parallel()
	tuck.tween_property(
		reward,
		"position",
		player_visual.reward_hold_world_position() + Vector3(0.0, -0.12, 0.0),
		0.12
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tuck.tween_property(reward, "scale", Vector3.ZERO, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tuck.chain().tween_callback(reward.queue_free)


func cancel(keep_carried := false) -> void:
	_sequence_id += 1
	_active = false
	_pulling_reward = false
	_stop_transient_tweens()
	_clear_transient()
	if not keep_carried:
		_discard_carried_reward()


func has_active_cast() -> bool:
	return _active


func has_visible_rift() -> bool:
	# Treat the rift as ready only after its pupil-to-portal opening motion has
	# become readable. Tests and capture tools use this presentation contract
	# instead of guessing at the authored cast duration.
	return is_instance_valid(_rift) and _rift.scale.x > 0.84


func has_visible_line() -> bool:
	return (
		is_instance_valid(_surface_line)
		and _surface_line.visible
		and _cast_progress > 0.9
	)


func has_carried_reward() -> bool:
	return _carrying_reward and is_instance_valid(_reward)


func carried_reward_id() -> String:
	return _carried_id


func rift_world_position() -> Vector3:
	return _cast_point


func _process(delta: float) -> void:
	_phase += delta
	if _active:
		_update_line()
	if _carrying_reward and is_instance_valid(_reward):
		_reward.position = (
			player_visual.reward_hold_world_position()
			+ Vector3.UP * (0.018 + sin(_phase * 3.4) * 0.014)
		)
		_reward.rotation.y += delta * 0.42


func _build_rift() -> void:
	_rift = MeshInstance3D.new()
	_rift.name = "UnknownFishingRift"
	var disc := QuadMesh.new()
	disc.size = Vector2(RIFT_SIZE, RIFT_SIZE)
	_rift.mesh = disc
	var material := ShaderMaterial.new()
	material.shader = RIFT_SHADER
	_rift.material_override = material
	_rift.rotation_degrees.x = -90.0
	_rift.position = _cast_point
	# Start at the same pupil scale as the rescue hole before it can render.
	_rift.scale = Vector3.ONE * 0.01
	_rift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rift)


func _update_line() -> void:
	if not is_instance_valid(_surface_line):
		return
	var origin := player_visual.fishing_line_origin(_cast_point)
	var target := (
		_reward.position
		if _pulling_reward and is_instance_valid(_reward)
		else origin.lerp(_cast_point, _cast_progress)
	)
	_place_segment(_surface_line, origin, target)


func _close_rift() -> void:
	if not is_instance_valid(_rift):
		return
	if _rift_tween != null and _rift_tween.is_valid():
		_rift_tween.kill()
	_rift_tween = create_tween()
	_rift_tween.tween_property(_rift, "scale", Vector3.ONE * 0.01, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


func _stop_transient_tweens() -> void:
	for tween in [_line_tween, _rift_tween]:
		if tween != null and tween.is_valid():
			tween.kill()
	_line_tween = null
	_rift_tween = null


func _build_reward(entry: Dictionary) -> Node3D:
	var kind := String(entry.get("kind", ""))
	var content_id := String(entry.get("id", ""))
	var visual: Node3D
	match kind:
		DiscoverySystem.KIND_TILE:
			var tile_definition := core.registries.tile(content_id)
			if tile_definition != null:
				visual = _tile_factory.instantiate_visual(tile_definition, true)
		DiscoverySystem.KIND_STRUCTURE:
			var structure_definition := core.registries.structure(content_id)
			if structure_definition != null:
				visual = _structure_factory.instantiate_visual(
					structure_definition,
					false
				)
	if visual == null:
		return null
	var carrier := Node3D.new()
	carrier.name = "Retrieved_%s" % content_id
	var bounds_data := StructureVisualFactory.local_mesh_bounds(visual)
	var uniform_scale := 1.0
	if bool(bounds_data.get("found", false)):
		var bounds: AABB = bounds_data["bounds"]
		var horizontal_span := maxf(bounds.size.x, bounds.size.z)
		var by_span := (
			REWARD_MAX_SPAN / horizontal_span
			if horizontal_span > 0.001
			else 1.0
		)
		var by_height := (
			REWARD_MAX_HEIGHT / bounds.size.y
			if bounds.size.y > 0.001
			else 1.0
		)
		uniform_scale = clampf(minf(by_span, by_height), 0.08, 1.4)
		visual.position = -(bounds.position + bounds.size * 0.5)
	carrier.add_child(visual)
	_reward_scale = Vector3.ONE * uniform_scale
	return carrier


func _line_mesh(
	node_name: String,
	color: Color,
	radius: float
) -> MeshInstance3D:
	var line := MeshInstance3D.new()
	line.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 1.0
	cylinder.radial_segments = 6
	cylinder.rings = 1
	line.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.18
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line.material_override = material
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return line


func _place_segment(
	line: MeshInstance3D,
	from: Vector3,
	to: Vector3
) -> void:
	var offset := to - from
	var length := offset.length()
	if length <= 0.002:
		line.visible = false
		return
	line.visible = true
	line.position = (from + to) * 0.5
	line.quaternion = Quaternion(Vector3.UP, offset / length)
	line.scale = Vector3(1.0, length, 1.0)


func _clear_transient() -> void:
	for node in [_rift, _surface_line]:
		if is_instance_valid(node):
			node.queue_free()
	_rift = null
	_surface_line = null


func _discard_carried_reward() -> void:
	if is_instance_valid(_reward):
		_reward.queue_free()
	_reward = null
	_carrying_reward = false
	_carried_kind = ""
	_carried_id = ""
