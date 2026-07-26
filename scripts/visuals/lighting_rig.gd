class_name LightingRig
extends Node3D
## The one shared lighting/atmosphere setup (scenes/visual/GardenStyleLightingRig.tscn).
## Gameplay and the Match Lab both instance this scene; apply_profile() drives every
## environment knob from a VisualStyleProfile resource. No other scene may add its
## own DirectionalLight3D or WorldEnvironment.

signal profile_applied(profile: VisualStyleProfile)

const MIST_BG_SHADER: Shader = preload("res://assets/materials/mist_background.gdshader")

@export var day_profile: VisualStyleProfile
@export var rain_profile: VisualStyleProfile

var current_profile: VisualStyleProfile
var _sun: DirectionalLight3D
var _environment: WorldEnvironment
var _rain: GPUParticles3D
var _bg_layer: CanvasLayer
var _bg_rect: ColorRect
var _bg_material: ShaderMaterial


func _ready() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 60.0
	add_child(_sun)

	_environment = WorldEnvironment.new()
	_environment.name = "Atmosphere"
	_environment.environment = Environment.new()
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

	if day_profile == null:
		day_profile = load("res://assets/visual_profiles/garden_galaxy_day.tres")
	if rain_profile == null:
		rain_profile = load("res://assets/visual_profiles/garden_rain.tres")
	apply_profile(day_profile)


func apply_profile(profile: VisualStyleProfile) -> void:
	current_profile = profile
	var env := _environment.environment
	env.background_mode = Environment.BG_CANVAS if profile.background_gradient else Environment.BG_COLOR
	env.background_color = profile.background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = profile.ambient_color
	env.ambient_light_energy = profile.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = profile.exposure
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = profile.contrast
	env.adjustment_saturation = profile.saturation
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
	profile_applied.emit(profile)


func toggle_profile() -> void:
	apply_profile(rain_profile if current_profile == day_profile else day_profile)


## Scales warm local lights (campfires, lanterns) so they whisper by day and
## carry the scene by rain/dusk.
func local_light_energy(base_energy: float) -> float:
	return base_energy * (current_profile.local_light_multiplier if current_profile else 1.0)


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
