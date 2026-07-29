class_name CozyGroundFog
extends Node3D
## Stable, full-resolution ground mist. Three cheap world-space planes create
## depth while one seamless noise texture supplies continuously drifting
## wisps. Nothing samples screen coordinates or a camera-relative voxel grid,
## so scrolling cannot invalidate or shimmer the mist.

const MIST_SHADER: Shader = preload("res://assets/materials/cozy_ground_fog.gdshader")
const LAYER_COUNT := 3
const SWEEP_COUNT := 6
const TRAIL_COUNT := 3
const ENEMY_COUNT := 2
const LIGHT_COUNT := 4
const INTERACTION_STEP := 1.0 / 30.0
const ENEMY_SCAN_STEP := 0.25
const LIGHT_SCAN_STEP := 0.5
const TRAIL_SAMPLE_STEP := 0.18
const LAYER_HEIGHT_FACTORS := [0.12, 0.34, 0.62]
const LAYER_OPACITIES := [0.28, 0.10, 0.045]
const LAYER_SCALES := [0.72, 1.0, 1.42]
const LAYER_PHASES := [0.0, 11.7, 27.4]

var _layers: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _actor: Node3D
var _camera_focus: Node3D
var _selected_enemies: Array[Node3D] = []
var _enemy_previous_positions: Dictionary = {}
var _trail_segments: Array[Dictionary] = []
var _active := false
var _density := 0.0
var _mist_color := Color(0.88, 0.87, 0.81)
var _layer_height := 1.35
var _noise_scale := 0.095
var _wind := Vector2(0.025, -0.018)
var _disturbance_radius := 0.95
var _close_seconds := 1.8
var _coverage_radius := 38.0
var _mist_floor_y := 0.0
var _last_actor_position := Vector3.ZERO
var _last_trail_position := Vector3.ZERO
var _actor_history_valid := false
var _interaction_elapsed := 0.0
var _enemy_scan_elapsed := ENEMY_SCAN_STEP
var _light_scan_elapsed := LIGHT_SCAN_STEP
var _trail_sample_elapsed := 0.0
var _selected_light_count := 0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_layers()
	_resize_layers()
	_set_active(false)


func _build_layers() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 7319
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.027
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.52
	noise.fractal_lacunarity = 2.05

	var noise_texture := NoiseTexture2D.new()
	noise_texture.width = 256
	noise_texture.height = 256
	noise_texture.seamless = true
	noise_texture.seamless_blend_skirt = 0.12
	noise_texture.normalize = true
	noise_texture.generate_mipmaps = true
	noise_texture.noise = noise

	for layer_index in LAYER_COUNT:
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE
		plane.subdivide_width = 1
		plane.subdivide_depth = 1

		var material := ShaderMaterial.new()
		material.shader = MIST_SHADER
		material.render_priority = layer_index
		material.set_shader_parameter("noise_texture", noise_texture)
		material.set_shader_parameter("layer_phase", LAYER_PHASES[layer_index])
		material.set_shader_parameter("layer_opacity", LAYER_OPACITIES[layer_index])
		material.set_shader_parameter("layer_scale", LAYER_SCALES[layer_index])

		var layer := MeshInstance3D.new()
		layer.name = "WorldMistLayer%d" % (layer_index + 1)
		layer.mesh = plane
		layer.material_override = material
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		layer.extra_cull_margin = 4.0
		add_child(layer)
		_layers.append(layer)
		_materials.append(material)


func bind_interactors(actor: Node3D, camera_focus: Node3D) -> void:
	_actor = actor
	_camera_focus = camera_focus
	if is_instance_valid(_actor):
		_mist_floor_y = _actor.global_position.y
	_seed_actor_history()
	_update_anchor_and_player()
	_refresh_enemy_selection()
	_refresh_lights()


func configure(profile: VisualStyleProfile) -> void:
	if profile == null:
		_set_active(false)
		return
	_density = maxf(0.0, profile.ground_fog_density)
	_mist_color = profile.fog_color
	_layer_height = maxf(0.2, profile.ground_fog_height)
	_noise_scale = maxf(0.001, profile.ground_fog_noise_scale)
	_wind = profile.ground_fog_wind
	_disturbance_radius = maxf(0.15, profile.ground_fog_disturbance_radius)
	_close_seconds = maxf(0.25, profile.ground_fog_close_seconds)
	for layer_index in _layers.size():
		_layers[layer_index].position.y = (
			_layer_height * float(LAYER_HEIGHT_FACTORS[layer_index])
		)
		var material := _materials[layer_index]
		material.set_shader_parameter("mist_color", Vector3(
			_mist_color.r,
			_mist_color.g,
			_mist_color.b
		))
		material.set_shader_parameter("mist_density", _density)
		material.set_shader_parameter("noise_scale", _noise_scale)
		material.set_shader_parameter("wind", _wind)
	_set_active(profile.fog_enabled and _density > 0.001)
	if _active:
		_update_anchor_and_player()
		_refresh_sweeps(INTERACTION_STEP)
		_refresh_lights()


func set_camera_distance(camera_distance: float) -> void:
	# Perspective distance, temporary middle-pan, and the isometric diagonal
	# are all covered before the radial fade begins. The extra world area costs
	# no more fragments than the viewport because the planes are depth-tested.
	_coverage_radius = clampf(camera_distance * 0.95 + 8.0, 24.0, 76.0)
	_resize_layers()
	_broadcast_parameter("coverage_radius", _coverage_radius)


func _resize_layers() -> void:
	var plane_size := Vector2.ONE * _coverage_radius * 2.35
	for layer in _layers:
		var plane := layer.mesh as PlaneMesh
		if plane != null:
			plane.size = plane_size


func _set_active(enabled: bool) -> void:
	_active = enabled
	visible = enabled
	set_process(enabled)
	for layer in _layers:
		layer.visible = enabled


func _process(delta: float) -> void:
	if not _active:
		return
	_update_anchor_and_player()
	_interaction_elapsed += delta
	_enemy_scan_elapsed += delta
	_light_scan_elapsed += delta
	if _enemy_scan_elapsed >= ENEMY_SCAN_STEP:
		_enemy_scan_elapsed = fmod(_enemy_scan_elapsed, ENEMY_SCAN_STEP)
		_refresh_enemy_selection()
	if _light_scan_elapsed >= LIGHT_SCAN_STEP:
		_light_scan_elapsed = fmod(_light_scan_elapsed, LIGHT_SCAN_STEP)
		_refresh_lights()
	while _interaction_elapsed >= INTERACTION_STEP:
		_interaction_elapsed -= INTERACTION_STEP
		_refresh_sweeps(INTERACTION_STEP)


func _update_anchor_and_player() -> void:
	var anchor := _camera_focus if is_instance_valid(_camera_focus) else _actor
	_update_ground_height()
	if is_instance_valid(anchor):
		global_position = Vector3(
			anchor.global_position.x,
			_mist_floor_y,
			anchor.global_position.z
		)
		_broadcast_parameter("coverage_center", anchor.global_position)
	if is_instance_valid(_actor):
		_broadcast_parameter("player_position", _actor.global_position)


func _update_ground_height() -> void:
	if not is_instance_valid(_actor):
		return
	var body := _actor as CharacterBody3D
	if body != null:
		# is_on_floor() alone can remain true during the frame in which a jump
		# begins. Requiring settled vertical velocity prevents that launch frame
		# from lifting every mist layer with the actor.
		if body.is_on_floor() and absf(body.velocity.y) <= 0.05:
			_mist_floor_y = body.global_position.y
		return
	# Generic non-physics preview actors may follow gently stepped terrain, but
	# large vertical animation/teleport offsets must not drag the mist plane.
	if absf(_actor.global_position.y - _mist_floor_y) <= 0.35:
		_mist_floor_y = _actor.global_position.y


func _seed_actor_history() -> void:
	_trail_segments.clear()
	_actor_history_valid = is_instance_valid(_actor)
	if _actor_history_valid:
		_last_actor_position = _actor.global_position
		_last_trail_position = _last_actor_position
	_trail_sample_elapsed = 0.0


func _refresh_sweeps(step: float) -> void:
	var from_to := PackedVector4Array()
	var metadata := PackedVector4Array()
	for _index in SWEEP_COUNT:
		from_to.append(Vector4.ZERO)
		metadata.append(Vector4.ZERO)

	if not is_instance_valid(_actor):
		_broadcast_parameter("sweep_from_to", from_to)
		_broadcast_parameter("sweep_meta", metadata)
		return
	if not _actor_history_valid:
		_seed_actor_history()

	var actor_position := _actor.global_position
	var movement_distance := _last_actor_position.distance_to(actor_position)
	# No idle aura: a stationary actor contributes no clearing at all. Normal
	# walking only nudges a narrow wake; sprinting and dashes push harder.
	var movement_strength := smoothstep(0.012, 0.11, movement_distance) * 0.62
	from_to[0] = _segment_vector(_last_actor_position, actor_position)
	metadata[0] = Vector4(
		_disturbance_radius * 0.62,
		movement_strength,
		0.0,
		0.0
	)
	_trail_sample_elapsed += step
	if (
		_trail_sample_elapsed >= TRAIL_SAMPLE_STEP
		and actor_position.distance_to(_last_trail_position) > 0.08
	):
		_trail_segments.push_front({
			"from": _last_trail_position,
			"to": actor_position,
			"age": 0.0,
		})
		_last_trail_position = actor_position
		_trail_sample_elapsed = 0.0
		if _trail_segments.size() > TRAIL_COUNT:
			_trail_segments.resize(TRAIL_COUNT)

	for trail in _trail_segments:
		trail["age"] = float(trail.get("age", 0.0)) + step
	for trail_index in mini(TRAIL_COUNT, _trail_segments.size()):
		var trail: Dictionary = _trail_segments[trail_index]
		var strength := clampf(
			1.0 - float(trail["age"]) / _close_seconds,
			0.0,
			1.0
		)
		from_to[trail_index + 1] = _segment_vector(trail["from"], trail["to"])
		metadata[trail_index + 1] = Vector4(
			_disturbance_radius * 0.72,
			strength * 0.56,
			0.0,
			0.0
		)

	for enemy_index in mini(ENEMY_COUNT, _selected_enemies.size()):
		var enemy := _selected_enemies[enemy_index]
		if not is_instance_valid(enemy):
			continue
		var instance_id := enemy.get_instance_id()
		var previous: Vector3 = _enemy_previous_positions.get(
			instance_id,
			enemy.global_position
		)
		var slot := 1 + TRAIL_COUNT + enemy_index
		from_to[slot] = _segment_vector(previous, enemy.global_position)
		metadata[slot] = Vector4(
			_disturbance_radius * 0.78,
			0.82,
			0.0,
			0.0
		)
		_enemy_previous_positions[instance_id] = enemy.global_position

	_last_actor_position = actor_position
	_broadcast_parameter("sweep_from_to", from_to)
	_broadcast_parameter("sweep_meta", metadata)


func _refresh_enemy_selection() -> void:
	_selected_enemies.clear()
	if not is_instance_valid(_actor) or get_tree() == null:
		return
	var candidates: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if is_instance_valid(enemy) and enemy.visible:
			candidates.append(enemy)
	candidates.sort_custom(func(left: Node3D, right: Node3D) -> bool:
		return left.global_position.distance_squared_to(_actor.global_position) < (
			right.global_position.distance_squared_to(_actor.global_position)
		)
	)
	for index in mini(ENEMY_COUNT, candidates.size()):
		_selected_enemies.append(candidates[index])


func _refresh_lights() -> void:
	var positions := PackedVector4Array()
	var colors := PackedVector4Array()
	for _index in LIGHT_COUNT:
		positions.append(Vector4.ZERO)
		colors.append(Vector4.ZERO)
	_selected_light_count = 0
	if get_tree() == null:
		return
	var reference_position := (
		_camera_focus.global_position
		if is_instance_valid(_camera_focus)
		else global_position
	)
	var candidates: Array[OmniLight3D] = []
	for node in get_tree().get_nodes_in_group("warm_lights"):
		var light := node as OmniLight3D
		if (
			is_instance_valid(light)
			and light.visible
			and light.light_energy > 0.001
		):
			candidates.append(light)
	candidates.sort_custom(func(left: OmniLight3D, right: OmniLight3D) -> bool:
		return left.global_position.distance_squared_to(reference_position) < (
			right.global_position.distance_squared_to(reference_position)
		)
	)
	for index in mini(LIGHT_COUNT, candidates.size()):
		var light := candidates[index]
		var color := light.light_color
		var radius := maxf(1.0, light.omni_range * 1.35)
		var energy := clampf(light.light_energy * 0.16, 0.08, 1.25)
		positions[index] = Vector4(
			light.global_position.x,
			light.global_position.z,
			light.global_position.y,
			radius
		)
		colors[index] = Vector4(color.r, color.g, color.b, energy)
	_selected_light_count += 1
	_broadcast_parameter("light_position_radius", positions)
	_broadcast_parameter("light_color_energy", colors)


func _segment_vector(from: Vector3, to: Vector3) -> Vector4:
	return Vector4(from.x, from.z, to.x, to.z)


func _broadcast_parameter(parameter_name: StringName, value: Variant) -> void:
	for material in _materials:
		material.set_shader_parameter(parameter_name, value)


func request_light_refresh() -> void:
	_light_scan_elapsed = LIGHT_SCAN_STEP


func runtime_manifest() -> Dictionary:
	return {
		"active": _active,
		"renderer": "full_resolution_world_space_layers",
		"layer_count": LAYER_COUNT,
		"draw_call_budget": LAYER_COUNT,
		"camera_sampled": false,
		"screen_texture_sampled": false,
		"temporal_reprojection": false,
		"dynamic_noise": true,
		"noise_texture_size": 256,
		"coverage_radius": _coverage_radius,
		"ground_height": _mist_floor_y,
		"density": _density,
		"layer_height": _layer_height,
		"wind": _wind,
		"interaction_update_hz": int(round(1.0 / INTERACTION_STEP)),
		"sweep_budget": SWEEP_COUNT,
		"player_trail_budget": TRAIL_COUNT,
		"enemy_budget": ENEMY_COUNT,
		"active_enemies": _selected_enemies.size(),
		"light_budget": LIGHT_COUNT,
		"active_lights": _selected_light_count,
		"volumetric_fog": false,
		"world_size_dependent": false,
	}
