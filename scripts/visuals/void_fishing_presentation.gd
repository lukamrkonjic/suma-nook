class_name VoidFishingPresentation
extends Node3D
## Live seated fishing presentation at the keeper's current edge position.
## The luminous line and its shard are true 3D world geometry: the line runs
## from the real rod tip straight down to the rift point in the abyss, is
## occluded correctly by terrain, and can never drape across the scene the
## way a screen-space overlay could. Existing world geometry is never
## replaced or supplemented by a temporary stage.

const StructureVisualFactoryScript := preload(
	"res://scripts/world/structure_visual_factory.gd"
)

const RIFT_DEPTH := 3.5
const REWARD_MAX_SPAN := 0.52
const REWARD_MAX_HEIGHT := 0.62
const TOP_COLOR := Color("#FFF4D8")
const MID_COLOR := Color("#F8E7AE")
const BOTTOM_COLOR := Color("#D5FFF1")
const SHARD_COLOR := Color("#8FFFD7")
const LINE_SAMPLES := 22

var core: GameCore
var assets: AssetLibrary
var player: PlayerController
var player_visual: PlayerVisual
var _tile_factory: TileVisualFactory
var _structure_factory: RefCounted

var _reward: Node3D
var _reward_scale := Vector3.ONE
var _saved_player_transform := Transform3D.IDENTITY
var _surface_point := Vector3.ZERO
var _cast_point := Vector3.ZERO
var _cast_progress := 0.0
var _phase := 0.0
var _sequence_id := 0
var _active := false
var _staged := false
var _pulling_reward := false
var _carrying_reward := false
var _carried_ready := false
var _carried_kind := ""
var _carried_id := ""
var _line_tween: Tween

var _rig: Node3D
var _core_line: MeshInstance3D
var _halo_line: MeshInstance3D
var _core_mesh: ImmediateMesh
var _halo_mesh: ImmediateMesh
var _tip_glow: MeshInstance3D
var _endpoint: Node3D
var _shard_body: Node3D
var _endpoint_bloom: MeshInstance3D
var _endpoint_inner_bloom: MeshInstance3D
var _endpoint_light: OmniLight3D
var _traveller: MeshInstance3D
var _sparkles: Array[Dictionary] = []
var _crackle_arcs: Array[Dictionary] = []
var _bite_pulse := 1.0


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
	_structure_factory = StructureVisualFactoryScript.new(
		assets,
		core.grid
	)
	_build_line_rig()
	if not player.state_changed.is_connected(_on_player_state_changed):
		player.state_changed.connect(_on_player_state_changed)


## Seats the keeper exactly where they initiated the cast while preserving
## their current facing. Fishing never owns or changes the gameplay camera.
func prepare_cast(point: Vector3) -> bool:
	_sequence_id += 1
	_stop_transient_tweens()
	_clear_transient()
	_discard_carried_reward()
	_surface_point = point
	_cast_point = _rift_point(point)
	_saved_player_transform = player.global_transform
	_staged = true
	player.begin_presentation_lock()
	player_visual.play("fish_wait")
	player_visual.set_seated_fishing(true)
	# The hands and lower body have settled before the rod is mounted.
	player_visual.apply_equipment(core.equipment, "rod")
	player_visual.play("fish_wait")
	return true


func begin_cast(point: Vector3) -> void:
	_stop_transient_tweens()
	_surface_point = point
	# The rift opens directly under the LIVE rod tip so the line hangs
	# perfectly vertical, clamped to stay past the ledge marker along the
	# cast direction even when the keeper stands at the back of the cell.
	var direction := -player.global_basis.z
	direction.y = 0.0
	direction = (
		direction.normalized()
		if direction.length_squared() > 0.001
		else Vector3.FORWARD
	)
	var tip := player_visual.fishing_line_origin(point)
	var offset := tip - point
	offset.y = 0.0
	var forward_reach := maxf(offset.dot(direction), 0.0)
	var side := offset - direction * offset.dot(direction)
	var rift_surface := point + direction * forward_reach + side
	_cast_point = _rift_point(
		Vector3(rift_surface.x, point.y, rift_surface.z)
	)
	_cast_progress = 0.0
	_phase = 0.0
	_bite_pulse = 1.0
	_active = true
	_pulling_reward = false
	_set_effect_visible(true)
	# The line leaves the tip on the rod's forward whip, then drops fast.
	player_visual.cast_fishing_rod()
	_line_tween = create_tween()
	_line_tween.tween_interval(0.12)
	_line_tween.tween_property(
		self,
		"_cast_progress",
		1.0,
		0.24
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func bite() -> void:
	if not _active:
		return
	player_visual.bite_fishing_rod()
	if _line_tween != null and _line_tween.is_valid():
		_line_tween.kill()
	_line_tween = create_tween()
	_line_tween.tween_property(
		self,
		"_cast_progress",
		0.94,
		0.09
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_line_tween.tween_property(
		self,
		"_cast_progress",
		1.0,
		0.16
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var pulse := create_tween()
	pulse.tween_property(
		self,
		"_bite_pulse",
		1.18,
		0.1
	)
	pulse.tween_property(
		self,
		"_bite_pulse",
		1.0,
		0.2
	)


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
	# The piece rises straight up the line and reveals above the rift.
	var reveal_point := Vector3(
		_cast_point.x,
		_surface_point.y + 0.72,
		_cast_point.z
	)
	var pull := _reward.create_tween()
	pull.set_parallel()
	pull.tween_property(
		_reward,
		"position",
		reveal_point,
		0.46
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pull.tween_property(
		_reward,
		"scale",
		_reward_scale,
		0.4
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	_set_effect_visible(false)
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
	flight.tween_method(
		fly_along,
		0.0,
		1.0,
		0.52
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	flight.tween_property(
		_reward,
		"rotation",
		_reward.rotation + Vector3(0.4, TAU * 1.25, -0.3),
		0.52
	).set_trans(Tween.TRANS_QUAD)
	flight.tween_property(
		_reward,
		"scale",
		_reward_scale * 0.86,
		0.52
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	await flight.finished
	if sequence != _sequence_id or not is_instance_valid(_reward):
		return
	_active = false
	_carrying_reward = true
	_carried_ready = false
	_carried_kind = String(entry.get("kind", ""))
	_carried_id = String(entry.get("id", ""))
	_clear_transient()
	await _finish_staging(true)
	_carried_ready = true


func consume_carried_reward() -> void:
	if not _carrying_reward or not is_instance_valid(_reward):
		_discard_carried_reward()
		return
	var reward := _reward
	_reward = null
	_carrying_reward = false
	_carried_ready = false
	_carried_kind = ""
	_carried_id = ""
	var tuck := reward.create_tween()
	tuck.set_parallel()
	tuck.tween_property(
		reward,
		"position",
		player_visual.reward_hold_world_position()
		+ Vector3(0.0, -0.12, 0.0),
		0.12
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tuck.tween_property(
		reward,
		"scale",
		Vector3.ZERO,
		0.12
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tuck.chain().tween_callback(reward.queue_free)


func cancel(keep_carried := false) -> void:
	_sequence_id += 1
	_active = false
	_pulling_reward = false
	_stop_transient_tweens()
	_clear_transient()
	if not keep_carried:
		_discard_carried_reward()
	if _staged:
		_finish_staging(true)


func has_active_cast() -> bool:
	return _active


func has_visible_line() -> bool:
	return (
		_core_line != null
		and _core_line.visible
		and _cast_progress > 0.9
	)


func has_visible_shard() -> bool:
	return (
		_endpoint != null
		and _endpoint.visible
		and _cast_progress > 0.9
	)


## Compatibility diagnostic: the old rescue-style black rift is gone.
func has_visible_rift() -> bool:
	return false


func has_carried_reward() -> bool:
	return (
		_carrying_reward
		and _carried_ready
		and is_instance_valid(_reward)
	)


func carried_reward_id() -> String:
	return _carried_id


func rift_world_position() -> Vector3:
	return _cast_point


## The rift always hangs in the abyss below the world's ground plane — from a
## raised ledge the line simply travels further down. A depth relative to the
## ledge top would park the shard beside lower neighbouring terrain.
func _rift_point(point: Vector3) -> Vector3:
	return Vector3(
		point.x,
		minf(point.y, 0.0) - RIFT_DEPTH,
		point.z
	)


func dock_is_visible() -> bool:
	return false


func has_shard_crackle_layer() -> bool:
	return _crackle_arcs.size() >= 3


func shard_crackle_visible() -> bool:
	for data in _crackle_arcs:
		var arc := data["node"] as MeshInstance3D
		if arc.visible and float(data.get("alpha", 0.0)) > 0.35:
			return true
	return false


func _process(delta: float) -> void:
	_phase += delta
	if _staged and is_instance_valid(player):
		# The rod's world heading stays pinned to the keeper's cast cardinal
		# through every frame of hand animation.
		player_visual.align_fishing_rod(player.global_rotation.y)
	if _active:
		_update_line()
	if _carrying_reward and is_instance_valid(_reward):
		_reward.position = (
			player_visual.reward_hold_world_position()
			+ Vector3.UP * (
				0.018 + sin(_phase * 3.4) * 0.014
			)
		)
		_reward.rotation.y += delta * 0.42


func _update_line() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var tip_world := player_visual.fishing_line_origin(
		_cast_point
	)
	# The shard hangs in the rift straight below the cast point, drifting
	# gently in world space.
	var endpoint_full := _cast_point + Vector3(
		sin(_phase * 0.47) * 0.045
		+ sin(_phase * 0.83 + 1.9) * 0.02,
		sin(_phase * 0.61 + 0.4) * 0.03,
		cos(_phase * 0.53 + 1.1) * 0.035
	)
	var progress := ease(
		clampf(_cast_progress, 0.0, 1.0),
		-1.7
	)
	var endpoint_visible := tip_world.lerp(endpoint_full, progress)
	if _pulling_reward and is_instance_valid(_reward):
		# The line reels the retrieved piece up out of the rift.
		endpoint_visible = _reward.position + Vector3.UP * 0.04
	# A gentle mid-line drift keeps the near-vertical line alive without
	# ever bending it away from the drop.
	var control := (
		(tip_world + endpoint_visible) * 0.5
		+ Vector3(
			sin(_phase * 0.47) * 0.02,
			0.0,
			cos(_phase * 0.59 + 0.8) * 0.018
		)
	)
	var points := PackedVector3Array()
	for index in LINE_SAMPLES:
		var t := float(index) / float(LINE_SAMPLES - 1)
		var a := tip_world.lerp(control, t)
		var b := control.lerp(endpoint_visible, t)
		points.append(a.lerp(b, t))
	var camera_position := camera.global_position
	var line_flimmer := (
		0.94
		+ sin(_phase * 1.1) * 0.06
		+ sin(_phase * 2.3 + 1.7) * 0.03
	)
	_rebuild_ribbon(
		_core_mesh,
		points,
		camera_position,
		0.0065,
		clampf(line_flimmer, 0.86, 1.0)
	)
	_rebuild_ribbon(
		_halo_mesh,
		points,
		camera_position,
		0.028,
		clampf(
			0.30
			+ sin(_phase * 0.91 + 0.6) * 0.03
			+ sin(_phase * 1.73) * 0.015,
			0.24,
			0.36
		)
	)
	_tip_glow.global_position = tip_world
	_tip_glow.transparency = clampf(
		1.0 - (0.62 + sin(_phase * 1.37 + 0.8) * 0.1),
		0.0,
		1.0
	)
	_endpoint.global_position = endpoint_visible
	# The stardrop ignites only after it has sunk well below the ledge:
	# during the drop it stays dark, then grows and lights up through the
	# lower half of its descent — its glow can never flash the cliff face
	# or the terrain beside the keeper.
	var descent := clampf(
		(_surface_point.y - endpoint_visible.y - 1.4) / 1.8,
		0.0,
		1.0
	)
	var shard_breathe := (
		1.0
		+ sin(_phase * 1.41) * 0.018
		+ sin(_phase * 2.73 + 0.4) * 0.009
	)
	_endpoint.scale = (
		Vector3.ONE
		* shard_breathe
		* _bite_pulse
		* (0.55 + 0.45 * descent)
	)
	_shard_body.rotation.y += get_process_delta_time() * 0.55
	_shard_body.rotation.z = (
		sin(_phase * 0.78) * 0.05
		+ sin(_phase * 1.64 + 0.7) * 0.02
	)
	var endpoint_flimmer := (
		0.92
		+ sin(_phase * 1.23 + 0.5) * 0.045
		+ sin(_phase * 2.07 + 2.2) * 0.025
	)
	_endpoint_bloom.transparency = clampf(
		1.0 - endpoint_flimmer * 0.5 * descent,
		0.0,
		1.0
	)
	_endpoint_inner_bloom.transparency = clampf(
		1.0 - endpoint_flimmer * 0.85 * descent,
		0.0,
		1.0
	)
	_endpoint_light.light_energy = (
		0.9 + sin(_phase * 1.31 + 0.4) * 0.18
	) * _bite_pulse * descent
	_endpoint.visible = (
		descent > 0.001 and not _pulling_reward
	)
	_animate_sparkles()
	_animate_crackle()
	var travel_phase := fmod(_phase, 7.6)
	if travel_phase > 6.75 and not _pulling_reward:
		var local_phase := (travel_phase - 6.75) / 0.85
		var eased := sin(local_phase * PI)
		_traveller.visible = true
		_traveller.global_position = endpoint_visible.lerp(
			tip_world,
			local_phase * 0.38
		)
		_traveller.scale = Vector3.ONE * (0.55 + eased * 0.5)
		_traveller.transparency = 1.0 - eased * 0.68
	else:
		_traveller.visible = false


## Camera-facing ribbon strip between world points, colored down the line
## with the warm-to-mint gradient. Rebuilt per frame; the sample count is
## tiny and the mesh lives on the GPU only for the current frame.
func _rebuild_ribbon(
	mesh: ImmediateMesh,
	points: PackedVector3Array,
	camera_position: Vector3,
	half_width: float,
	alpha: float
) -> void:
	mesh.clear_surfaces()
	if points.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var count := points.size()
	for index in count:
		var t := float(index) / float(count - 1)
		var tangent: Vector3
		if index == 0:
			tangent = points[1] - points[0]
		elif index == count - 1:
			tangent = points[index] - points[index - 1]
		else:
			tangent = points[index + 1] - points[index - 1]
		if tangent.length_squared() <= 0.000001:
			tangent = Vector3.DOWN
		var side := tangent.normalized().cross(
			camera_position - points[index]
		)
		if side.length_squared() <= 0.000001:
			side = Vector3.RIGHT
		side = side.normalized()
		var color := _line_color_at(t)
		color.a *= alpha
		var width := half_width * lerpf(0.8, 1.3, t)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(points[index] + side * width)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(points[index] - side * width)
	mesh.surface_end()


func _line_color_at(t: float) -> Color:
	if t < 0.45:
		return TOP_COLOR.lerp(MID_COLOR, t / 0.45)
	if t < 0.76:
		return MID_COLOR.lerp(BOTTOM_COLOR, (t - 0.45) / 0.31)
	return BOTTOM_COLOR.lerp(Color("#F2FFFA"), (t - 0.76) / 0.24)


func _build_line_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "FishingPresentationRig"
	_rig.top_level = true
	add_child(_rig)
	_rig.global_position = Vector3.ZERO

	_core_mesh = ImmediateMesh.new()
	_core_line = MeshInstance3D.new()
	_core_line.name = "FishingLineCore"
	_core_line.mesh = _core_mesh
	_core_line.material_override = _line_material(false)
	_core_line.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	_rig.add_child(_core_line)

	_halo_mesh = ImmediateMesh.new()
	_halo_line = MeshInstance3D.new()
	_halo_line.name = "FishingLineHalo"
	_halo_line.mesh = _halo_mesh
	_halo_line.material_override = _line_material(true)
	_halo_line.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	_rig.add_child(_halo_line)

	_tip_glow = _glow_quad(0.11, Color("#FFF0C8"), 3)
	_tip_glow.name = "RodTipShine"
	_rig.add_child(_tip_glow)

	_endpoint = Node3D.new()
	_endpoint.name = "MagicalShardEndpoint"
	_rig.add_child(_endpoint)
	_endpoint_bloom = _glow_quad(0.52, Color(SHARD_COLOR, 0.55), 2)
	_endpoint.add_child(_endpoint_bloom)
	_endpoint_inner_bloom = _glow_quad(0.24, Color("#D8FFF1", 0.85), 3)
	_endpoint.add_child(_endpoint_inner_bloom)
	_shard_body = _build_shard()
	_endpoint.add_child(_shard_body)
	_endpoint_light = OmniLight3D.new()
	_endpoint_light.name = "ShardLight"
	_endpoint_light.light_color = SHARD_COLOR
	_endpoint_light.light_energy = 1.0
	_endpoint_light.omni_range = 2.0
	_endpoint_light.omni_attenuation = 1.6
	_endpoint_light.shadow_enabled = false
	_endpoint.add_child(_endpoint_light)
	for index in 4:
		var arc := MeshInstance3D.new()
		arc.name = "ShardCrackle%02d" % index
		var arc_mesh := QuadMesh.new()
		arc_mesh.size = Vector2(0.011, 0.16)
		arc.mesh = arc_mesh
		arc.material_override = _additive_material(
			Color("#9BFFDB")
		)
		arc.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		arc.visible = false
		_endpoint.add_child(arc)
		_crackle_arcs.append({
			"node": arc,
			"phase": float(index) * 0.37,
			"period": 0.74 + float(index) * 0.19,
			"window": 0.12 + float(index % 2) * 0.025,
			"alpha": 0.0,
		})
	for index in 10:
		var sparkle := _glow_quad(
			0.028 + float(index % 4) * 0.008,
			Color("#D5FFF1", 0.68),
			2
		)
		sparkle.name = "ShardSparkle%02d" % index
		_endpoint.add_child(sparkle)
		_sparkles.append({
			"node": sparkle,
			"phase": float(index) * 0.91,
			"radius": 0.085 + float((index * 7) % 15) * 0.011,
			"speed": 0.22 + float(index % 5) * 0.035,
			"rise": 0.055 + float(index % 4) * 0.028,
		})
	_traveller = _glow_quad(0.05, Color("#F4FFF9", 0.8), 3)
	_traveller.name = "LineTraveller"
	_traveller.visible = false
	_rig.add_child(_traveller)
	_set_effect_visible(false)


## A compact faceted crystal: two six-sided cones joined base to base, with
## a bright emissive heart so it reads as the light source of the rift.
func _build_shard() -> Node3D:
	var body := Node3D.new()
	body.name = "ShardBody"
	var shard_material := StandardMaterial3D.new()
	shard_material.albedo_color = Color("#E8FFF6")
	shard_material.roughness = 0.25
	shard_material.metallic = 0.0
	shard_material.emission_enabled = true
	shard_material.emission = SHARD_COLOR
	shard_material.emission_energy_multiplier = 1.5
	var upper := MeshInstance3D.new()
	upper.name = "ShardUpper"
	var upper_mesh := CylinderMesh.new()
	upper_mesh.top_radius = 0.0
	upper_mesh.bottom_radius = 0.048
	upper_mesh.height = 0.115
	upper_mesh.radial_segments = 6
	upper_mesh.rings = 1
	upper.mesh = upper_mesh
	upper.position.y = 0.0575
	upper.material_override = shard_material
	upper.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	body.add_child(upper)
	var lower := MeshInstance3D.new()
	lower.name = "ShardLower"
	var lower_mesh := CylinderMesh.new()
	lower_mesh.top_radius = 0.0
	lower_mesh.bottom_radius = 0.048
	lower_mesh.height = 0.085
	lower_mesh.radial_segments = 6
	lower_mesh.rings = 1
	lower.mesh = lower_mesh
	lower.position.y = -0.0425
	lower.rotation.x = PI
	lower.material_override = shard_material
	lower.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	body.add_child(lower)
	return body


func _animate_sparkles() -> void:
	for data in _sparkles:
		var sparkle := data["node"] as MeshInstance3D
		var sparkle_phase := float(data["phase"])
		var speed := float(data["speed"])
		var radius := float(data["radius"])
		var rise := float(data["rise"])
		var angle := sparkle_phase + _phase * speed
		var breathe := (
			0.78
			+ sin(_phase * 0.63 + sparkle_phase) * 0.18
		)
		sparkle.position = Vector3(
			cos(angle) * radius * breathe,
			-fmod(
				_phase * rise + sparkle_phase * 0.09,
				0.24
			) + 0.1,
			sin(angle * 0.72) * radius * 0.6
		)
		sparkle.transparency = 1.0 - clampf(
			0.42
			+ sin(_phase * 1.08 + sparkle_phase) * 0.18
			+ sin(_phase * 2.17 + sparkle_phase) * 0.08,
			0.16,
			0.68
		)


func _animate_crackle() -> void:
	for index in _crackle_arcs.size():
		var data := _crackle_arcs[index]
		var arc := data["node"] as MeshInstance3D
		var phase := float(data["phase"])
		var period := float(data["period"])
		var flash_window := float(data["window"])
		var cycle_time := fmod(_phase + phase, period)
		if cycle_time > flash_window:
			arc.visible = false
			data["alpha"] = 0.0
			continue
		var pulse_phase := cycle_time / flash_window
		var pulse := sin(pulse_phase * PI)
		var tick := floori((_phase + phase) * 17.0)
		var angle := (
			phase * TAU
			+ float(tick) * 2.39996
			+ sin(float(tick) * 1.73 + phase) * 0.34
		)
		var reach := (
			0.1
			+ float((tick + index * 5) % 7) * 0.012
			+ pulse * 0.03
		)
		arc.position = Vector3(
			cos(angle) * reach,
			sin(float(tick) * 2.17 + phase) * 0.05,
			sin(angle) * reach
		)
		arc.rotation = Vector3(
			0.0,
			-angle,
			0.5 + sin(float(tick) * 1.31) * 0.9
		)
		var alpha := clampf(
			0.16 + pow(pulse, 0.7) * 0.62,
			0.0,
			0.78
		)
		data["alpha"] = alpha
		arc.transparency = 1.0 - alpha
		arc.visible = true


func _line_material(additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
	)
	material.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
	)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.render_priority = 2 if not additive else 1
	return material


func _additive_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
	)
	material.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
	)
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## A soft radial glow billboard used for the tip shine, shard blooms,
## sparkles, and the traveller pulse.
func _glow_quad(
	size: float,
	color: Color,
	render_priority: int
) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * size
	quad.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
	)
	material.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
	)
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = (
		BaseMaterial3D.BILLBOARD_ENABLED
	)
	material.albedo_color = color
	material.albedo_texture = _soft_disc_texture()
	material.render_priority = render_priority
	quad.material_override = material
	quad.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	return quad


func _soft_disc_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.45),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	return texture


func _set_effect_visible(visible_now: bool) -> void:
	if _core_line != null:
		_core_line.visible = visible_now
	if _halo_line != null:
		_halo_line.visible = visible_now
	if _tip_glow != null:
		_tip_glow.visible = visible_now
	if _endpoint != null:
		# Never pre-shown: the stardrop (and its light) only ignites via the
		# descent gate in _update_line, so a fresh cast can never flash the
		# shard at its stale previous position for a frame.
		_endpoint.visible = false
	if _traveller != null:
		_traveller.visible = false
	if not visible_now:
		if _core_mesh != null:
			_core_mesh.clear_surfaces()
		if _halo_mesh != null:
			_halo_mesh.clear_surfaces()


func _finish_staging(restore_position: bool) -> void:
	if not _staged and not player.presentation_locked():
		return
	_staged = false
	player_visual.set_seated_fishing(false)
	player_visual.apply_equipment(core.equipment)
	if is_instance_valid(player):
		if restore_position:
			player.global_transform = _saved_player_transform
		player.end_presentation_lock()
	if is_instance_valid(player_visual):
		player_visual.play("idle")


func _on_player_state_changed(
	new_state: PlayerController.State
) -> void:
	if new_state == PlayerController.State.FREE and _staged:
		cancel(_carrying_reward)


func _stop_transient_tweens() -> void:
	if _line_tween != null and _line_tween.is_valid():
		_line_tween.kill()
	_line_tween = null


func _clear_transient() -> void:
	_set_effect_visible(false)
	_cast_progress = 0.0
	_bite_pulse = 1.0


func _discard_carried_reward() -> void:
	if is_instance_valid(_reward):
		_reward.queue_free()
	_reward = null
	_carrying_reward = false
	_carried_ready = false
	_carried_kind = ""
	_carried_id = ""


func _build_reward(entry: Dictionary) -> Node3D:
	var kind := String(entry.get("kind", ""))
	var content_id := String(entry.get("id", ""))
	var visual: Node3D
	match kind:
		DiscoverySystem.KIND_TILE:
			var tile_definition := core.registries.tile(
				content_id
			)
			if tile_definition != null:
				visual = _tile_factory.instantiate_visual(
					tile_definition,
					true
				)
		DiscoverySystem.KIND_STRUCTURE:
			var structure_definition := core.registries.structure(
				content_id
			)
			if structure_definition != null:
				visual = _structure_factory.instantiate_visual(
					structure_definition,
					false
				)
	if visual == null:
		return null
	var carrier := Node3D.new()
	carrier.name = "Retrieved_%s" % content_id
	var bounds_data := StructureVisualFactory.local_mesh_bounds(
		visual
	)
	var uniform_scale := 1.0
	if bool(bounds_data.get("found", false)):
		var bounds: AABB = bounds_data["bounds"]
		var horizontal_span := maxf(
			bounds.size.x,
			bounds.size.z
		)
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
		uniform_scale = clampf(
			minf(by_span, by_height),
			0.08,
			1.4
		)
		visual.position = -(
			bounds.position + bounds.size * 0.5
		)
	carrier.add_child(visual)
	_reward_scale = Vector3.ONE * uniform_scale
	return carrier
