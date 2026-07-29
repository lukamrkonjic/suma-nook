class_name CozyRainSurface
extends Node3D
## Fixed-budget rain-on-ground presentation. One world-space plane supplies a
## wet film, pooled patches, deterministic raindrop rings, and four footstep
## rings. One tiny particle emitter adds droplets at moving feet. Work depends
## on visible pixels, never on the number of world tiles or models.

const RAIN_SURFACE_SHADER: Shader = preload(
	"res://assets/materials/cozy_rain_surface.gdshader"
)
const FOOTSTEP_COUNT := 4
const FOOTSTEP_INTERVAL := 0.27
const WALK_SPEED_REFERENCE := 2.2

var _surface: MeshInstance3D
var _material: ShaderMaterial
var _foot_splashes: GPUParticles3D
var _falling_rain: GPUParticles3D
var _actor: Node3D
var _camera_focus: Node3D
var _active := false
var _surface_enabled := false
var _wetness := 0.0
var _puddle_amount := 0.0
var _ripple_amount := 0.0
var _walk_splash_amount := 0.0
var _coverage_radius := 38.0
var _ground_height := 0.0
var _effect_time := 0.0
var _last_actor_position := Vector3.ZERO
var _actor_history_valid := false
var _footstep_elapsed := 0.0
var _footstep_cursor := 0
var _foot_side := 1.0
var _footsteps := PackedVector4Array()
var _quality_multiplier := 1.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_surface()
	_build_foot_splashes()
	for _index in FOOTSTEP_COUNT:
		_footsteps.append(Vector4.ZERO)
	_material.set_shader_parameter("footstep_ripples", _footsteps)
	_resize_surface()
	_set_active(false)


func _build_surface() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 4217
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.024
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.52
	noise.fractal_lacunarity = 2.0
	var noise_texture := NoiseTexture2D.new()
	noise_texture.width = 192
	noise_texture.height = 192
	noise_texture.seamless = true
	noise_texture.seamless_blend_skirt = 0.12
	noise_texture.normalize = true
	noise_texture.generate_mipmaps = true
	noise_texture.noise = noise

	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	_material = ShaderMaterial.new()
	_material.shader = RAIN_SURFACE_SHADER
	_material.set_shader_parameter("noise_texture", noise_texture)
	_surface = MeshInstance3D.new()
	_surface.name = "RainWetSurface"
	_surface.mesh = plane
	_surface.material_override = _material
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface.position.y = 0.035
	_surface.extra_cull_margin = 4.0
	add_child(_surface)


func _build_foot_splashes() -> void:
	_foot_splashes = GPUParticles3D.new()
	_foot_splashes.name = "RainFootSplashes"
	_foot_splashes.amount = 28
	_foot_splashes.lifetime = 0.48
	_foot_splashes.randomness = 0.65
	_foot_splashes.local_coords = false
	_foot_splashes.fixed_fps = 30
	_foot_splashes.interpolate = true
	_foot_splashes.fract_delta = true
	_foot_splashes.visibility_aabb = AABB(
		Vector3(-3.0, -2.0, -3.0),
		Vector3(6.0, 5.0, 6.0)
	)
	_foot_splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.18
	process.direction = Vector3.UP
	process.spread = 58.0
	process.initial_velocity_min = 0.55
	process.initial_velocity_max = 1.15
	process.gravity = Vector3(0.0, -3.8, 0.0)
	process.scale_min = 0.65
	process.scale_max = 1.15
	_foot_splashes.process_material = process
	var droplet := SphereMesh.new()
	droplet.radius = 0.022
	droplet.height = 0.068
	droplet.radial_segments = 6
	droplet.rings = 3
	var droplet_material := StandardMaterial3D.new()
	droplet_material.albedo_color = Color(0.72, 0.88, 0.92, 0.72)
	droplet_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	droplet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	droplet.material = droplet_material
	_foot_splashes.draw_pass_1 = droplet
	_foot_splashes.emitting = false
	add_child(_foot_splashes)


func attach_falling_rain(particles: GPUParticles3D) -> void:
	_falling_rain = particles
	_update_anchor()


func bind_interactors(actor: Node3D, camera_focus: Node3D) -> void:
	_actor = actor
	_camera_focus = camera_focus
	if is_instance_valid(_actor):
		_ground_height = _actor.global_position.y
		_last_actor_position = _actor.global_position
		_actor_history_valid = true
	_update_anchor()


func configure(profile: VisualStyleProfile) -> void:
	if profile == null:
		_set_active(false)
		return
	_wetness = maxf(0.0, profile.rain_surface_wetness)
	_puddle_amount = maxf(0.0, profile.rain_puddle_amount)
	_ripple_amount = maxf(0.0, profile.rain_ripple_amount)
	_walk_splash_amount = maxf(0.0, profile.rain_walk_splash_amount)
	_surface_enabled = (
		_wetness > 0.001
		or _ripple_amount > 0.001
		or _walk_splash_amount > 0.001
	)
	_material.set_shader_parameter("wetness", _wetness)
	_material.set_shader_parameter("puddle_amount", _puddle_amount)
	_material.set_shader_parameter("ripple_amount", _ripple_amount)
	_set_active(profile.rain_enabled)
	if _active:
		_update_anchor()


func set_camera_distance(camera_distance: float) -> void:
	_coverage_radius = clampf(camera_distance * 0.95 + 8.0, 24.0, 76.0)
	_resize_surface()
	_material.set_shader_parameter("coverage_radius", _coverage_radius)


func set_quality(quality_id: String) -> void:
	_quality_multiplier = float({
		"low": 0.45,
		"medium": 0.72,
		"high": 1.0,
	}.get(quality_id, 1.0))


func _resize_surface() -> void:
	if _surface == null:
		return
	var plane := _surface.mesh as PlaneMesh
	if plane != null:
		plane.size = Vector2.ONE * _coverage_radius * 2.35


func _set_active(enabled: bool) -> void:
	_active = enabled
	visible = enabled
	set_process(enabled)
	if _surface != null:
		_surface.visible = enabled and _surface_enabled
	if _foot_splashes != null and not enabled:
		_foot_splashes.emitting = false


func _process(delta: float) -> void:
	if not _active:
		return
	_effect_time += delta
	_material.set_shader_parameter("effect_time", _effect_time)
	_update_ground_height()
	_update_anchor()
	_update_walking_interaction(delta)


func _update_ground_height() -> void:
	if not is_instance_valid(_actor):
		return
	var body := _actor as CharacterBody3D
	if body != null:
		if body.is_on_floor() and absf(body.velocity.y) <= 0.05:
			_ground_height = body.global_position.y
		elif (
			absf(body.global_position.y - _ground_height) <= 0.14
			and absf(body.velocity.y) <= 0.65
		):
			# Floor contact can flicker for one physics tick on seams between
			# chunk colliders. A tiny settled height tolerance keeps walking
			# splashes continuous without accepting an actual jump.
			_ground_height = body.global_position.y
		return
	if absf(_actor.global_position.y - _ground_height) <= 0.35:
		_ground_height = _actor.global_position.y


func _update_anchor() -> void:
	var anchor := _camera_focus if is_instance_valid(_camera_focus) else _actor
	if not is_instance_valid(anchor):
		return
	global_position = Vector3(
		anchor.global_position.x,
		_ground_height,
		anchor.global_position.z
	)
	_material.set_shader_parameter("coverage_center", anchor.global_position)
	if is_instance_valid(_falling_rain):
		_falling_rain.global_position = Vector3(
			anchor.global_position.x,
			_ground_height + 15.5,
			anchor.global_position.z
		)


func _update_walking_interaction(delta: float) -> void:
	if not is_instance_valid(_actor):
		return
	var actor_position := _actor.global_position
	if not _actor_history_valid:
		_last_actor_position = actor_position
		_actor_history_valid = true
	var movement := actor_position - _last_actor_position
	movement.y = 0.0
	var speed := movement.length() / maxf(delta, 0.0001)
	var interaction_direction := movement
	var body := _actor as CharacterBody3D
	if body != null:
		var body_motion := Vector3(body.velocity.x, 0.0, body.velocity.z)
		# Rendering may run more often than physics. On the in-between render
		# frames the transform has not advanced, but the character is still
		# walking; authoritative horizontal velocity keeps rainfall interaction
		# continuous instead of pulsing at the physics cadence.
		speed = maxf(speed, body_motion.length())
		if interaction_direction.length_squared() < 0.00001:
			interaction_direction = body_motion * delta
	var grounded := _actor_is_grounded()
	var movement_strength := (
		clampf((speed - 0.15) / WALK_SPEED_REFERENCE, 0.0, 1.0)
		* _walk_splash_amount
	)
	_material.set_shader_parameter("wake_from_to", Vector4(
		_last_actor_position.x,
		_last_actor_position.z,
		actor_position.x,
		actor_position.z
	))
	_material.set_shader_parameter(
		"wake_meta",
		Vector2(0.34, movement_strength * 0.42 if grounded else 0.0)
	)
	_foot_splashes.global_position = Vector3(
		actor_position.x,
		_ground_height + 0.075,
		actor_position.z
	)
	_foot_splashes.amount_ratio = clampf(
		movement_strength * _quality_multiplier,
		0.0,
		1.0
	)
	_foot_splashes.emitting = grounded and movement_strength > 0.08

	if grounded and movement_strength > 0.08:
		_footstep_elapsed += delta * clampf(speed / WALK_SPEED_REFERENCE, 0.55, 1.6)
		if _footstep_elapsed >= FOOTSTEP_INTERVAL:
			_footstep_elapsed = fmod(_footstep_elapsed, FOOTSTEP_INTERVAL)
			_add_footstep(
				actor_position,
				interaction_direction,
				movement_strength
			)
	else:
		_footstep_elapsed = minf(_footstep_elapsed, FOOTSTEP_INTERVAL * 0.45)
	_last_actor_position = actor_position


func _actor_is_grounded() -> bool:
	var body := _actor as CharacterBody3D
	if body == null:
		return absf(_actor.global_position.y - _ground_height) <= 0.12
	return (
		(body.is_on_floor() and absf(body.velocity.y) <= 0.65)
		or (
			absf(body.global_position.y - _ground_height) <= 0.14
			and absf(body.velocity.y) <= 0.65
		)
	)


func _add_footstep(
	actor_position: Vector3,
	movement: Vector3,
	strength: float
) -> void:
	var direction := Vector2(movement.x, movement.z).normalized()
	if direction.length_squared() < 0.001:
		return
	var side := Vector2(-direction.y, direction.x) * 0.17 * _foot_side
	var behind := direction * -0.11
	var foot_position := Vector2(actor_position.x, actor_position.z) + side + behind
	_footsteps[_footstep_cursor] = Vector4(
		foot_position.x,
		foot_position.y,
		_effect_time,
		clampf(strength, 0.0, 1.0)
	)
	_footstep_cursor = (_footstep_cursor + 1) % FOOTSTEP_COUNT
	_foot_side *= -1.0
	_material.set_shader_parameter("footstep_ripples", _footsteps)


func active_footstep_count() -> int:
	var count := 0
	for footstep in _footsteps:
		var age := _effect_time - footstep.z
		if footstep.w > 0.001 and age >= 0.0 and age <= 1.05:
			count += 1
	return count


func runtime_manifest() -> Dictionary:
	return {
		"active": _active,
		"surface_enabled": _surface_enabled,
		"renderer": "single_world_space_surface",
		"surface_draw_call_budget": 1,
		"foot_splash_draw_call_budget": 1,
		"procedural_impact_fields": 2,
		"footstep_ripple_budget": FOOTSTEP_COUNT,
		"active_footstep_ripples": active_footstep_count(),
		"wetness": _wetness,
		"puddle_amount": _puddle_amount,
		"ripple_amount": _ripple_amount,
		"walk_splash_amount": _walk_splash_amount,
		"coverage_radius": _coverage_radius,
		"ground_height": _ground_height,
		"screen_texture_sampled": false,
		"opaque_depth_sampled": true,
		"temporal_reprojection": false,
		"per_tile_nodes": 0,
		"world_size_dependent": false,
	}
