class_name WaterInteractionSystem
extends Node3D
## Constant-budget player/water interaction.
##
## Six world-space impulses deform every joined/chunked water mesh through its
## already-shared material. Two pooled GPU emitters provide entry droplets and
## small movement spray. No nodes, textures, or simulations are allocated per
## water tile and movement never spawns short-lived scene objects.

const IMPULSE_COUNT := 6
const MOVE_IMPULSE_INTERVAL := 0.34
const MOVE_IMPULSE_DISTANCE := 0.42
const SWIM_SPEED_REFERENCE := 1.35
const WATER_Y_OFFSET := 0.025

var _material: ShaderMaterial
var _core: GameCore
var _player: PlayerController
var _entry_splash: GPUParticles3D
var _movement_splash: GPUParticles3D
var _impulses := PackedVector4Array()
var _impulse_cursor := 0
var _effect_time := 0.0
var _move_elapsed := 0.0
var _move_distance := 0.0
var _wake_strength := 0.0
var _wake_direction := Vector2(0.0, -1.0)
var _last_position := Vector3.ZERO
var _last_surface_position := Vector3.ZERO
var _history_valid := false
var _entry_count := 0
var _exit_count := 0
var _movement_impulse_count := 0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 50
	for _index in IMPULSE_COUNT:
		_impulses.append(Vector4(0.0, 0.0, -100.0, 0.0))
	_build_entry_splash()
	_build_movement_splash()
	set_process(false)


func setup(
	water_material: ShaderMaterial,
	game_core: GameCore,
	player_controller: PlayerController
) -> void:
	_material = water_material
	_core = game_core
	_player = player_controller
	_last_position = _player.global_position
	_history_valid = true
	_last_surface_position = _surface_position()
	_material.set_shader_parameter("interaction_time", _effect_time)
	_material.set_shader_parameter("interaction_impulses", _impulses)
	_clear_wake()
	if not _player.entered_open_water.is_connected(_on_entered_open_water):
		_player.entered_open_water.connect(_on_entered_open_water)
	if not _player.exited_open_water.is_connected(_on_exited_open_water):
		_player.exited_open_water.connect(_on_exited_open_water)
	set_process(true)


func _process(delta: float) -> void:
	if _material == null or not is_instance_valid(_player):
		return
	_effect_time += delta
	_material.set_shader_parameter("interaction_time", _effect_time)

	var actor_position := _player.global_position
	var horizontal_velocity := Vector3(
		_player.velocity.x,
		0.0,
		_player.velocity.z
	)
	var swimming := (
		_player.state == PlayerController.State.SWIMMING
		and _is_over_open_water()
	)
	var surface_position := _surface_position()
	var movement := actor_position - _last_position
	movement.y = 0.0
	if not _history_valid:
		movement = Vector3.ZERO
		_history_valid = true
	var traveled := movement.length()
	var speed := maxf(
		horizontal_velocity.length(),
		traveled / maxf(delta, 0.0001)
	)

	if swimming:
		_last_surface_position = surface_position
		var direction_3d := horizontal_velocity
		if direction_3d.length_squared() < 0.002:
			direction_3d = movement
		if direction_3d.length_squared() > 0.002:
			var desired := Vector2(direction_3d.x, direction_3d.z).normalized()
			_wake_direction = _wake_direction.lerp(
				desired,
				1.0 - exp(-delta * 12.0)
			).normalized()
		var target_strength := clampf(
			(speed - 0.08) / SWIM_SPEED_REFERENCE,
			0.0,
			1.2
		)
		_wake_strength = move_toward(
			_wake_strength,
			target_strength,
			delta * (5.5 if target_strength > _wake_strength else 3.2)
		)
		_move_elapsed += delta
		_move_distance += traveled
		if (
			_wake_strength > 0.12
			and (
				_move_elapsed >= MOVE_IMPULSE_INTERVAL
				or _move_distance >= MOVE_IMPULSE_DISTANCE
			)
		):
			_emit_movement_impulse(surface_position)
			_move_elapsed = 0.0
			_move_distance = 0.0
		_update_wake(surface_position)
		_update_movement_spray(surface_position)
	else:
		_wake_strength = move_toward(_wake_strength, 0.0, delta * 4.5)
		_move_elapsed = 0.0
		_move_distance = 0.0
		if _wake_strength > 0.001:
			_update_wake(_last_surface_position)
		else:
			_clear_wake()
		_movement_splash.emitting = false
		_movement_splash.amount_ratio = 0.0

	_last_position = actor_position


func _on_entered_open_water(
	surface_position: Vector3,
	impact_speed: float
) -> void:
	if _material == null:
		return
	var strength := clampf(0.68 + impact_speed / 6.0, 0.68, 1.55)
	var fixed_surface := Vector3(
		surface_position.x,
		_water_level(),
		surface_position.z
	)
	_write_impulse(fixed_surface, strength)
	_entry_count += 1
	_last_surface_position = fixed_surface
	_entry_splash.global_position = fixed_surface + Vector3.UP * WATER_Y_OFFSET
	_entry_splash.amount_ratio = clampf(strength / 1.35, 0.55, 1.0)
	_entry_splash.emitting = true
	_entry_splash.restart()


func _on_exited_open_water(
	surface_position: Vector3,
	kick_speed: float
) -> void:
	if _material == null:
		return
	var fixed_surface := Vector3(
		surface_position.x,
		_water_level(),
		surface_position.z
	)
	# The hop should read as feet pushing off, not a second landing splash.
	var strength := clampf(0.52 + kick_speed * 0.018, 0.56, 0.62)
	_write_impulse(fixed_surface, strength)
	_exit_count += 1
	_last_surface_position = fixed_surface


func _emit_movement_impulse(surface_position: Vector3) -> void:
	var perpendicular := Vector2(-_wake_direction.y, _wake_direction.x)
	var side := -1.0 if _movement_impulse_count % 2 == 0 else 1.0
	var offset := perpendicular * side * 0.16 - _wake_direction * 0.10
	var point := surface_position + Vector3(offset.x, 0.0, offset.y)
	_write_impulse(point, clampf(_wake_strength * 0.34, 0.12, 0.42))
	_movement_impulse_count += 1


func _write_impulse(surface_position: Vector3, strength: float) -> void:
	_impulses[_impulse_cursor] = Vector4(
		surface_position.x,
		surface_position.z,
		_effect_time,
		strength
	)
	_impulse_cursor = (_impulse_cursor + 1) % IMPULSE_COUNT
	_material.set_shader_parameter("interaction_impulses", _impulses)


func _update_wake(surface_position: Vector3) -> void:
	_material.set_shader_parameter(
		"interaction_wake",
		Vector4(
			surface_position.x,
			surface_position.z,
			_wake_direction.x,
			_wake_direction.y
		)
	)
	_material.set_shader_parameter(
		"interaction_wake_meta",
		Vector4(_wake_strength, 1.65, 0.16, 0.0)
	)


func _clear_wake() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("interaction_wake", Vector4.ZERO)
	_material.set_shader_parameter("interaction_wake_meta", Vector4.ZERO)


func _update_movement_spray(surface_position: Vector3) -> void:
	_movement_splash.global_position = (
		surface_position + Vector3.UP * WATER_Y_OFFSET
	)
	_movement_splash.amount_ratio = clampf(_wake_strength * 0.72, 0.0, 0.82)
	_movement_splash.emitting = _wake_strength > 0.12


func _surface_position() -> Vector3:
	if not is_instance_valid(_player):
		return Vector3(0.0, _water_level(), 0.0)
	return Vector3(
		_player.global_position.x,
		_water_level(),
		_player.global_position.z
	)


func _water_level() -> float:
	if _core == null:
		return -0.14
	return _core.registries.tunef("water_level_y", -0.14)


func _is_over_open_water() -> bool:
	if _core == null or not is_instance_valid(_player):
		return false
	return _core.water_field.is_open_water(_player.current_cell())


func _build_entry_splash() -> void:
	_entry_splash = GPUParticles3D.new()
	_entry_splash.name = "WaterEntrySplash"
	_entry_splash.amount = 18
	_entry_splash.lifetime = 0.40
	_entry_splash.one_shot = true
	_entry_splash.explosiveness = 0.94
	_entry_splash.randomness = 0.58
	_entry_splash.local_coords = false
	_entry_splash.fixed_fps = 60
	_entry_splash.interpolate = true
	_entry_splash.fract_delta = true
	_entry_splash.visibility_aabb = AABB(
		Vector3(-2.0, -0.6, -2.0),
		Vector3(4.0, 4.2, 4.0)
	)
	_entry_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.17
	process.direction = Vector3.UP
	process.spread = 46.0
	process.initial_velocity_min = 1.35
	process.initial_velocity_max = 2.75
	process.gravity = Vector3(0.0, -8.0, 0.0)
	process.scale_min = 0.55
	process.scale_max = 1.0
	process.color_ramp = _particle_fade_ramp()
	_entry_splash.process_material = process
	_entry_splash.draw_pass_1 = _droplet_mesh(0.018, 0.046, 12, 6)
	_entry_splash.emitting = false
	add_child(_entry_splash)


func _build_movement_splash() -> void:
	_movement_splash = GPUParticles3D.new()
	_movement_splash.name = "WaterMovementSplash"
	_movement_splash.amount = 8
	_movement_splash.lifetime = 0.24
	_movement_splash.randomness = 0.72
	_movement_splash.local_coords = false
	_movement_splash.fixed_fps = 60
	_movement_splash.interpolate = true
	_movement_splash.fract_delta = true
	_movement_splash.visibility_aabb = AABB(
		Vector3(-1.3, -0.4, -1.3),
		Vector3(2.6, 2.2, 2.6)
	)
	_movement_splash.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.16
	process.direction = Vector3.UP
	process.spread = 58.0
	process.initial_velocity_min = 0.34
	process.initial_velocity_max = 0.74
	process.gravity = Vector3(0.0, -4.8, 0.0)
	process.scale_min = 0.45
	process.scale_max = 0.8
	process.color_ramp = _particle_fade_ramp()
	_movement_splash.process_material = process
	_movement_splash.draw_pass_1 = _droplet_mesh(0.012, 0.032, 10, 5)
	_movement_splash.emitting = false
	add_child(_movement_splash)


func _droplet_mesh(
	radius: float,
	height: float,
	radial_segments: int,
	rings: int
) -> SphereMesh:
	var droplet := SphereMesh.new()
	droplet.radius = radius
	droplet.height = height
	droplet.radial_segments = radial_segments
	droplet.rings = rings
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.78, 0.92, 0.93, 0.62)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	droplet.material = material
	return droplet


func _particle_fade_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.88, 0.98, 0.97, 0.28),
		Color(0.74, 0.92, 0.93, 0.54),
		Color(0.56, 0.80, 0.84, 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func active_impulse_count() -> int:
	var count := 0
	for impulse in _impulses:
		var age := _effect_time - impulse.z
		if impulse.w > 0.001 and age >= 0.0 and age <= 2.2:
			count += 1
	return count


func runtime_manifest() -> Dictionary:
	return {
		"renderer": "shared_water_material_impulses",
		"impulse_budget": IMPULSE_COUNT,
		"active_impulses": active_impulse_count(),
		"entry_splash_draw_call_budget": 1,
		"movement_splash_draw_call_budget": 1,
		"particle_draw_call_budget": 2,
		"entry_particle_budget": _entry_splash.amount,
		"movement_particle_budget": _movement_splash.amount,
		"entry_count": _entry_count,
		"exit_count": _exit_count,
		"movement_impulse_count": _movement_impulse_count,
		"wake_strength": _wake_strength,
		"water_level": _water_level(),
		"last_surface_height": _last_surface_position.y,
		"per_tile_nodes": 0,
		"world_size_dependent": false,
		"uses_cpu_mesh_updates": false,
		"uses_screen_texture": false,
	}
