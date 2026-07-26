class_name LightingRig
extends Node3D
## The one shared lighting/atmosphere setup (scenes/visual/GGDayLightingRig.tscn).
## Gameplay and the Match Lab both instance this scene; apply_profile() drives every
## environment knob from a VisualStyleProfile resource. No other scene may add its
## own DirectionalLight3D or WorldEnvironment.

signal profile_applied(profile: VisualStyleProfile)

const MIST_BG_SHADER: Shader = preload("res://assets/materials/mist_background.gdshader")

@export var day_profile: VisualStyleProfile
@export var mist_profile: VisualStyleProfile
@export var rain_profile: VisualStyleProfile

var current_profile: VisualStyleProfile
var _sun: DirectionalLight3D
var _environment: WorldEnvironment
var _ambient_sky: Sky
var _ambient_material: ProceduralSkyMaterial
var _rain: GPUParticles3D
var _motes: GPUParticles3D
var _bg_layer: CanvasLayer
var _bg_rect: ColorRect
var _bg_material: ShaderMaterial
var time_of_day_id := "noon"
var background_preset_id := "profile"


func _ready() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	# Four blended cascades fitted tightly around the compact world: a large
	# shadow distance wastes cascade resolution and is what makes stylized
	# shadows stair-step. See docs/visual_rework/SMOOTHNESS_AUDIT.md.
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 28.0
	_sun.directional_shadow_blend_splits = true
	_sun.directional_shadow_fade_start = 0.9
	add_child(_sun)

	_environment = WorldEnvironment.new()
	_environment.name = "Atmosphere"
	_environment.environment = Environment.new()
	_ambient_sky = Sky.new()
	_ambient_material = ProceduralSkyMaterial.new()
	_ambient_material.sun_angle_max = 0.0
	_ambient_sky.sky_material = _ambient_material
	_environment.environment.sky = _ambient_sky
	add_child(_environment)

	# Screen-space gradient backdrop (mist preset). Sits behind the 3D scene
	# via BG_CANVAS; hidden entirely for flat-color presets.
	_bg_layer = CanvasLayer.new()
	_bg_layer.name = "Backdrop"
	_bg_layer.layer = -10
	add_child(_bg_layer)
	_bg_rect = ColorRect.new()
	_bg_rect.name = "GradientRect"
	_bg_material = ShaderMaterial.new()
	_bg_material.shader = MIST_BG_SHADER
	_bg_rect.material = _bg_material
	_bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_layer.add_child(_bg_rect)

	_rain = _build_rain()
	add_child(_rain)
	_motes = _build_motes()
	add_child(_motes)

	if day_profile == null:
		day_profile = load("res://assets/visual_profiles/gg_day_profile.tres")
	if mist_profile == null:
		mist_profile = load("res://assets/visual_profiles/garden_galaxy_mist.tres")
	if rain_profile == null:
		rain_profile = load("res://assets/visual_profiles/garden_rain.tres")
	apply_profile(day_profile)


func apply_profile(profile: VisualStyleProfile) -> void:
	current_profile = profile
	var env := _environment.environment
	env.background_mode = Environment.BG_CANVAS if profile.background_gradient else Environment.BG_COLOR
	env.background_color = profile.background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if profile.ambient_gradient_enabled else Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = profile.ambient_color
	env.ambient_light_energy = profile.ambient_energy
	env.ambient_light_sky_contribution = 1.0 if profile.ambient_gradient_enabled else 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_ambient_material.sky_top_color = profile.ambient_sky_color
	_ambient_material.sky_horizon_color = profile.ambient_equator_color
	_ambient_material.ground_horizon_color = profile.ambient_equator_color
	_ambient_material.ground_bottom_color = profile.ambient_ground_color
	match profile.tonemap:
		"aces":
			env.tonemap_mode = Environment.TONE_MAPPER_ACES
		"filmic":
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		_:
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = profile.exposure
	env.adjustment_enabled = false
	env.ssao_enabled = profile.ssao_enabled
	env.ssao_intensity = profile.ssao_intensity
	env.ssao_radius = profile.ssao_radius
	env.ssao_power = profile.ssao_power
	env.ssao_detail = profile.ssao_detail
	env.ssao_horizon = profile.ssao_horizon
	env.ssao_sharpness = profile.ssao_sharpness
	env.glow_enabled = profile.glow_enabled
	env.glow_intensity = profile.glow_intensity
	env.glow_hdr_threshold = profile.glow_hdr_threshold
	env.glow_bloom = profile.glow_bloom
	env.fog_enabled = profile.fog_enabled
	env.fog_light_color = profile.fog_color
	env.fog_density = profile.fog_density
	env.fog_sky_affect = 0.0

	_bg_layer.visible = profile.background_gradient
	if profile.background_gradient:
		_bg_material.set_shader_parameter("top_color", profile.gradient_top)
		_bg_material.set_shader_parameter("mid_color", profile.gradient_mid)
		_bg_material.set_shader_parameter("bottom_color", profile.gradient_bottom)
		_bg_material.set_shader_parameter("stars_amount", 1.0 if profile.stars_enabled else 0.0)

	_sun.light_color = profile.sun_color
	_sun.light_energy = profile.sun_energy
	_sun.light_specular = profile.sun_specular
	_sun.rotation_degrees = Vector3(profile.sun_pitch_deg, profile.sun_yaw_deg, 0.0)
	_sun.shadow_opacity = profile.shadow_opacity
	_sun.shadow_blur = profile.shadow_blur
	_sun.light_angular_distance = profile.sun_angular_distance
	_sun.shadow_bias = profile.shadow_bias
	_sun.shadow_normal_bias = profile.shadow_normal_bias

	_rain.emitting = profile.rain_enabled
	_motes.emitting = profile.motes_enabled
	_apply_time_of_day()
	_apply_background_preset()
	profile_applied.emit(profile)


func toggle_profile() -> void:
	if current_profile == day_profile:
		apply_profile(mist_profile)
	elif current_profile == mist_profile:
		apply_profile(rain_profile)
	else:
		apply_profile(day_profile)


func set_weather(weather_id: String) -> void:
	match weather_id:
		"day":
			apply_profile(day_profile)
		"mist":
			apply_profile(mist_profile)
		"rain":
			apply_profile(rain_profile)


func set_time_of_day(preset_id: String) -> void:
	if preset_id not in ["morning", "noon", "sunset", "night"]:
		return
	time_of_day_id = preset_id
	_apply_time_of_day()
	profile_applied.emit(current_profile)


func set_background_preset(preset_id: String) -> void:
	if preset_id not in ["profile", "cream", "mist", "dusk", "night"]:
		return
	background_preset_id = preset_id
	_apply_background_preset()
	profile_applied.emit(current_profile)


func reset_admin_overrides() -> void:
	time_of_day_id = "noon"
	background_preset_id = "profile"
	apply_profile(day_profile)


func weather_id() -> String:
	if current_profile == mist_profile:
		return "mist"
	if current_profile == rain_profile:
		return "rain"
	return "day"


func is_dark_background() -> bool:
	return background_preset_id == "night" or (
		background_preset_id == "profile"
		and current_profile != null
		and current_profile.rain_enabled
	)


## Scales warm local lights (campfires, lanterns) so they whisper by day and
## carry the scene by rain/dusk.
func local_light_energy(base_energy: float) -> float:
	var profile_multiplier := current_profile.local_light_multiplier if current_profile else 1.0
	var time_multiplier := 1.0
	match time_of_day_id:
		"morning":
			time_multiplier = 1.15
		"sunset":
			time_multiplier = 1.5
		"night":
			time_multiplier = 2.2
	return base_energy * profile_multiplier * time_multiplier


func _apply_time_of_day() -> void:
	if current_profile == null:
		return
	var env := _environment.environment
	_sun.light_color = current_profile.sun_color
	_sun.light_energy = current_profile.sun_energy
	_sun.rotation_degrees = Vector3(current_profile.sun_pitch_deg, current_profile.sun_yaw_deg, 0.0)
	env.ambient_light_energy = current_profile.ambient_energy
	env.glow_enabled = current_profile.glow_enabled
	env.glow_intensity = current_profile.glow_intensity
	match time_of_day_id:
		"morning":
			_sun.light_color = current_profile.sun_color.lerp(Color(1.0, 0.78, 0.58), 0.38)
			_sun.light_energy = current_profile.sun_energy * 0.78
			_sun.rotation_degrees.x = -28.0
			env.ambient_light_energy = current_profile.ambient_energy * 0.82
		"sunset":
			_sun.light_color = current_profile.sun_color.lerp(Color(1.0, 0.48, 0.25), 0.62)
			_sun.light_energy = current_profile.sun_energy * 0.62
			_sun.rotation_degrees.x = -15.0
			env.ambient_light_energy = current_profile.ambient_energy * 0.55
			env.glow_enabled = true
			env.glow_intensity = maxf(current_profile.glow_intensity, 0.28)
		"night":
			_sun.light_color = Color(0.42, 0.56, 0.9)
			_sun.light_energy = current_profile.sun_energy * 0.2
			_sun.rotation_degrees.x = -38.0
			env.ambient_light_energy = maxf(0.12, current_profile.ambient_energy * 0.28)
			env.glow_enabled = true
			env.glow_intensity = maxf(current_profile.glow_intensity, 0.42)


func _apply_background_preset() -> void:
	if current_profile == null:
		return
	match background_preset_id:
		"cream":
			_set_flat_background(day_profile.background_color)
		"mist":
			_set_gradient_background(
				mist_profile.gradient_top,
				mist_profile.gradient_mid,
				mist_profile.gradient_bottom,
				0.0
			)
		"dusk":
			_set_gradient_background(
				Color(0.39, 0.34, 0.5),
				Color(0.72, 0.47, 0.43),
				Color(0.9, 0.67, 0.48),
				0.0
			)
		"night":
			_set_gradient_background(
				Color(0.055, 0.075, 0.14),
				Color(0.09, 0.15, 0.22),
				Color(0.12, 0.2, 0.24),
				1.0
			)
		_:
			if current_profile.background_gradient:
				_set_gradient_background(
					current_profile.gradient_top,
					current_profile.gradient_mid,
					current_profile.gradient_bottom,
					1.0 if current_profile.stars_enabled else 0.0
				)
			else:
				_set_flat_background(current_profile.background_color)


func _set_flat_background(color: Color) -> void:
	_environment.environment.background_mode = Environment.BG_COLOR
	_environment.environment.background_color = color
	_bg_layer.visible = false


func _set_gradient_background(top: Color, middle: Color, bottom: Color, stars: float) -> void:
	_environment.environment.background_mode = Environment.BG_CANVAS
	_bg_layer.visible = true
	_bg_material.set_shader_parameter("top_color", top)
	_bg_material.set_shader_parameter("mid_color", middle)
	_bg_material.set_shader_parameter("bottom_color", bottom)
	_bg_material.set_shader_parameter("stars_amount", stars)


func _build_rain() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Rain"
	particles.amount = 900
	particles.lifetime = 1.1
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 30, 60))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(24, 0.1, 24)
	mat.direction = Vector3(0.06, -1, 0.02)
	mat.spread = 0.0
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 19.0
	mat.gravity = Vector3.ZERO
	particles.process_material = mat
	particles.position.y = 16.0
	var streak := BoxMesh.new()
	streak.size = Vector3(0.015, 0.5, 0.015)
	var streak_mat := StandardMaterial3D.new()
	streak_mat.albedo_color = Color(0.85, 0.9, 0.88, 0.4)
	streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = streak_mat
	particles.draw_pass_1 = streak
	return particles


func _build_motes() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "DriftingMotes"
	particles.amount = 180
	particles.lifetime = 6.0
	particles.randomness = 0.9
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-30, -6, -30), Vector3(60, 22, 60))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(24, 6, 24)
	process.direction = Vector3(0.18, 0.35, 0.08)
	process.spread = 110.0
	process.initial_velocity_min = 0.04
	process.initial_velocity_max = 0.18
	process.gravity = Vector3.ZERO
	process.scale_min = 0.55
	process.scale_max = 1.35
	particles.process_material = process
	particles.position.y = 3.0
	var mote := SphereMesh.new()
	mote.radius = 0.018
	mote.height = 0.036
	var mote_material := StandardMaterial3D.new()
	mote_material.albedo_color = Color(1.0, 0.93, 0.72, 0.48)
	mote_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote.material = mote_material
	particles.draw_pass_1 = mote
	return particles
