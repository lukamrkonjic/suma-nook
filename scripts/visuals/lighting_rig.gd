class_name LightingRig
extends Node3D
## The one shared lighting/atmosphere setup
## (scenes/visual/SumaSoftDaylight.tscn). Gameplay and the visual labs instance
## this scene; apply_profile() drives every environment knob from a
## VisualStyleProfile. No other scene may add its own global directional light
## or WorldEnvironment.

signal profile_applied(profile: VisualStyleProfile)

const MIST_BG_SHADER: Shader = preload("res://assets/materials/mist_background.gdshader")
const GG_BG_SHADER: Shader = preload("res://assets/materials/gg_screen_skybox.gdshader")
const GG_GRADE_SHADER: Shader = preload("res://assets/materials/gg_color_grade.gdshader")

# Night is intentionally authored as darkness with small pools of warm light,
# rather than a blue-tinted version of daytime. These multipliers retain just
# enough cool fill to read silhouettes while letting lanterns and fires carry
# the scene.
const NIGHT_AMBIENT_ENERGY_MULTIPLIER := 0.09
const NIGHT_SUN_ENERGY_MULTIPLIER := 0.08
const NIGHT_LOCAL_LIGHT_MULTIPLIER := 3.6
const NIGHT_GLOW_INTENSITY := 0.34
const NIGHT_AMBIENT_TINT := Color(0.34, 0.46, 0.72)
const NIGHT_BACKGROUND_TINT := Color(0.24, 0.34, 0.55)

@export var day_profile: VisualStyleProfile
@export var mist_profile: VisualStyleProfile
@export var rain_profile: VisualStyleProfile
@export var leaves_profile: VisualStyleProfile
@export var snow_profile: VisualStyleProfile
@export var blossom_profile: VisualStyleProfile
@export var neutral_profile: VisualStyleProfile
@export var warm_profile: VisualStyleProfile
@export var overcast_profile: VisualStyleProfile
@export var fallback_profile: VisualStyleProfile

var current_profile: VisualStyleProfile
var _sun: DirectionalLight3D
var _environment: WorldEnvironment
var _ambient_sky: Sky
var _ambient_material: ProceduralSkyMaterial
var _reflection_probe: ReflectionProbe
var _rain: GPUParticles3D
var _motes: GPUParticles3D
var _leaves: GPUParticles3D
var _snow: GPUParticles3D
var _blossoms: GPUParticles3D
var _spores: GPUParticles3D
var _bg_layer: CanvasLayer
var _bg_rect: ColorRect
var _bg_material: ShaderMaterial
var _gg_bg_material: ShaderMaterial
var _gg_bg_quad: MeshInstance3D
var _grade_layer: CanvasLayer
var _grade_rect: ColorRect
var _grade_material: ShaderMaterial
var time_of_day_id := "noon"
var background_preset_id := "profile"
var particle_quality_id := "high"
var _theme_tween: Tween
var _camera_shadow_distance := 40.0
var _user_ssao_enabled := true
var _user_bloom_enabled := true


func _ready() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	# The active profile selects the cascade layout. The map is fitted again
	# whenever gameplay zoom changes so close-ups do not waste texels on the
	# complete camera envelope.
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 80.0
	_sun.directional_shadow_blend_splits = true
	_sun.directional_shadow_fade_start = 0.96
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

	# Confirmed reference probe envelope: realtime, 128 px, one bounce,
	# approximately 50 × 15 × 50 units with box projection disabled.
	_reflection_probe = ReflectionProbe.new()
	_reflection_probe.name = "GardenReflectionProbe"
	_reflection_probe.size = Vector3(50.0, 15.0, 50.0)
	_reflection_probe.position.y = 4.0
	_reflection_probe.intensity = 1.0
	_reflection_probe.max_distance = 50.0
	_reflection_probe.box_projection = false
	_reflection_probe.enable_shadows = false
	_reflection_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(_reflection_probe)

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
	# GG backdrop drawn like Unity's camera skybox: a far-plane fullscreen
	# quad inside the 3D pass, so its colors enter the grade pass as exact
	# linear radiance with no canvas color-space ambiguity.
	_gg_bg_material = ShaderMaterial.new()
	_gg_bg_material.shader = GG_BG_SHADER
	_gg_bg_quad = MeshInstance3D.new()
	_gg_bg_quad.name = "GGBackdrop"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_gg_bg_quad.mesh = quad
	_gg_bg_quad.material_override = _gg_bg_material
	_gg_bg_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex shader pins it to the far plane regardless of transform, so
	# only culling has to be defeated.
	_gg_bg_quad.custom_aabb = AABB(Vector3(-50000, -50000, -50000), Vector3(100000, 100000, 100000))
	_gg_bg_quad.visible = false
	add_child(_gg_bg_quad)

	# GG-exact grade pass (Unity PPv2 PP_MainCamera chain). Layer 0 sits above
	# the 3D image and every negative background layer while staying below the
	# HUD (layer 1) and menus, so only the camera image is graded — matching
	# where PPv2 runs in the reference.
	_grade_layer = CanvasLayer.new()
	_grade_layer.name = "GGColorGrade"
	_grade_layer.layer = 0
	_grade_layer.visible = false
	add_child(_grade_layer)
	_grade_material = ShaderMaterial.new()
	_grade_material.shader = GG_GRADE_SHADER
	_grade_rect = ColorRect.new()
	_grade_rect.name = "GradeRect"
	_grade_rect.material = _grade_material
	_grade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grade_layer.add_child(_grade_rect)

	_rain = _build_rain()
	add_child(_rain)
	_motes = _build_motes()
	add_child(_motes)
	_leaves = _build_leaves()
	add_child(_leaves)
	_snow = _build_snow()
	add_child(_snow)
	_blossoms = _build_blossoms()
	add_child(_blossoms)
	_spores = _build_spores()
	add_child(_spores)

	if day_profile == null:
		day_profile = load("res://assets/visual_profiles/garden_galaxy_exact.tres")
	if mist_profile == null:
		mist_profile = load("res://assets/visual_profiles/garden_galaxy_mist.tres")
	if rain_profile == null:
		rain_profile = load("res://assets/visual_profiles/garden_rain.tres")
	if leaves_profile == null:
		leaves_profile = load("res://assets/visual_profiles/windy_leaves.tres")
	if snow_profile == null:
		snow_profile = load("res://assets/visual_profiles/soft_snow.tres")
	if blossom_profile == null:
		blossom_profile = load("res://assets/visual_profiles/petal_breeze.tres")
	if neutral_profile == null:
		neutral_profile = load("res://assets/visual_profiles/suma_soft_daylight_neutral.tres")
	if warm_profile == null:
		warm_profile = day_profile
	if overcast_profile == null:
		overcast_profile = load("res://assets/visual_profiles/suma_soft_overcast.tres")
	if fallback_profile == null:
		fallback_profile = load("res://assets/visual_profiles/suma_soft_daylight_fallback.tres")
	apply_profile(day_profile)
	get_tree().node_added.connect(_on_tree_node_added)


func apply_profile(profile: VisualStyleProfile) -> void:
	current_profile = profile
	var env := _environment.environment
	var uses_canvas_bg := profile.background_gradient or profile.background_gg_gradient
	env.background_mode = Environment.BG_CANVAS if uses_canvas_bg else Environment.BG_COLOR
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
	if profile.gg_pipeline_enabled:
		# The reference camera image is produced entirely by the grade pass:
		# Godot's own tonemapper stays LINEAR and adjustments stay off so the
		# screen buffer reaching the grade shader is raw linear HDR light.
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = 1.0
		env.adjustment_enabled = false
	else:
		match profile.tonemap:
			"agx":
				env.tonemap_mode = Environment.TONE_MAPPER_AGX
			"aces":
				env.tonemap_mode = Environment.TONE_MAPPER_ACES
			"filmic":
				env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			_:
				env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = profile.exposure
		env.tonemap_agx_white = profile.agx_white
		env.tonemap_agx_contrast = profile.agx_contrast
		env.adjustment_enabled = true
		env.adjustment_brightness = profile.brightness
		env.adjustment_contrast = profile.contrast
		env.adjustment_saturation = profile.saturation
	_configure_grade_pass(profile)
	env.ssao_enabled = profile.ssao_enabled and _user_ssao_enabled
	env.ssao_intensity = profile.ssao_intensity
	env.ssao_radius = profile.ssao_radius
	env.ssao_power = profile.ssao_power
	env.ssao_detail = profile.ssao_detail
	env.ssao_horizon = profile.ssao_horizon
	env.ssao_sharpness = profile.ssao_sharpness
	env.ssao_light_affect = profile.ssao_light_affect
	env.ssao_ao_channel_affect = 0.0
	env.ssil_enabled = profile.ssil_enabled
	env.ssil_intensity = profile.ssil_intensity
	env.ssil_radius = profile.ssil_radius
	env.ssil_sharpness = profile.ssil_sharpness
	env.ssil_normal_rejection = 1.0
	env.ssr_enabled = profile.ssr_enabled
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2
	env.glow_enabled = profile.glow_enabled and _user_bloom_enabled
	env.glow_intensity = profile.glow_intensity
	env.glow_hdr_threshold = profile.glow_hdr_threshold
	env.glow_bloom = profile.glow_bloom
	# PPv2 bloom is a plain additive composite before grading; the legacy
	# profiles were tuned against Godot's normalized soft-light glow.
	env.glow_normalized = not profile.gg_pipeline_enabled
	env.glow_blend_mode = (
		Environment.GLOW_BLEND_MODE_ADDITIVE
		if profile.gg_pipeline_enabled
		else Environment.GLOW_BLEND_MODE_SOFTLIGHT
	)
	env.fog_enabled = profile.fog_enabled
	env.fog_light_color = profile.fog_color
	env.fog_density = profile.fog_density
	env.fog_sky_affect = 0.0

	_bg_layer.visible = uses_canvas_bg
	if profile.background_gg_gradient:
		_set_gg_background(profile.bg_color0, profile.bg_color1, profile.bg_sparkles_enabled)
	elif profile.background_gradient:
		_bg_rect.material = _bg_material
		_bg_material.set_shader_parameter("top_color", profile.gradient_top)
		_bg_material.set_shader_parameter("mid_color", profile.gradient_mid)
		_bg_material.set_shader_parameter("bottom_color", profile.gradient_bottom)
		_bg_material.set_shader_parameter("stars_amount", 1.0 if profile.stars_enabled else 0.0)

	_sun.light_color = profile.sun_color
	_sun.light_energy = profile.sun_energy
	_sun.light_specular = profile.sun_specular
	_sun.rotation_degrees = Vector3(profile.sun_pitch_deg, profile.sun_yaw_deg, 0.0)
	match profile.shadow_cascade_mode:
		"pssm_4":
			_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		"pssm_2":
			_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_:
			_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_split_1 = profile.shadow_split_1
	_sun.directional_shadow_split_2 = profile.shadow_split_2
	_sun.directional_shadow_split_3 = profile.shadow_split_3
	_sun.directional_shadow_blend_splits = profile.shadow_blend_splits
	_refresh_camera_shadow_fit()
	_sun.shadow_opacity = profile.shadow_opacity
	_sun.shadow_blur = profile.shadow_blur
	_sun.light_angular_distance = profile.sun_angular_distance
	_sun.shadow_bias = profile.shadow_bias
	_sun.shadow_normal_bias = profile.shadow_normal_bias
	_reflection_probe.visible = profile.reflection_probe_enabled
	_reflection_probe.enable_shadows = profile.reflection_probe_shadows
	_reflection_probe.update_mode = (
		ReflectionProbe.UPDATE_ALWAYS
		if profile.reflection_probe_update_always
		else ReflectionProbe.UPDATE_ONCE
	)

	_rain.emitting = profile.rain_enabled
	_motes.emitting = profile.motes_enabled
	_leaves.emitting = profile.leaves_enabled
	_snow.emitting = profile.snow_enabled
	_blossoms.emitting = profile.blossoms_enabled
	_spores.emitting = profile.spores_enabled
	_apply_particle_quality()
	_apply_time_of_day()
	_apply_background_preset()
	profile_applied.emit(profile)


## Keep every visible caster inside the shadow frustum while spending the
## available texels on the currently visible camera envelope. The 20-unit
## padding covers the complete starter island around the camera focus.
func set_camera_shadow_distance(camera_distance: float) -> void:
	_camera_shadow_distance = camera_distance
	_refresh_camera_shadow_fit()


func _refresh_camera_shadow_fit() -> void:
	if _sun == null or current_profile == null:
		return
	_sun.directional_shadow_max_distance = clampf(
		_camera_shadow_distance + 20.0,
		30.0,
		current_profile.shadow_max_distance
	)


func toggle_profile() -> void:
	if current_profile == day_profile:
		apply_profile(mist_profile)
	elif current_profile == mist_profile:
		apply_profile(rain_profile)
	else:
		apply_profile(day_profile)


## Art-review variants use identical geometry, camera, and palette; only the
## lighting profile changes. "fallback" removes PCSS and realtime reflections.
func apply_daylight_variant(variant_id: String) -> void:
	match variant_id:
		"neutral":
			apply_profile(neutral_profile)
		"warm":
			apply_profile(warm_profile)
		"overcast":
			apply_profile(overcast_profile)
		"fallback":
			apply_profile(fallback_profile)


func set_weather(weather_id: String) -> void:
	var profile := _profile_for_weather(weather_id)
	if profile != null:
		_transition_to_profile(profile)


func apply_runtime_state(state: Dictionary) -> void:
	var weather := String(state.get("weather", "day"))
	var time_id := String(state.get("time_of_day", "noon"))
	var background_id := String(state.get("background", "profile"))
	var quality_id := String(state.get("particle_quality", "high"))
	time_of_day_id = time_id if time_id in ["morning", "noon", "sunset", "night"] else "noon"
	background_preset_id = background_id if background_id in ["profile", "cream", "mist", "dusk", "night"] else "profile"
	particle_quality_id = quality_id if quality_id in ["low", "medium", "high"] else "high"
	var profile := _profile_for_weather(weather)
	apply_profile(profile if profile != null else day_profile)


func set_time_of_day(preset_id: String) -> void:
	if preset_id not in ["morning", "noon", "sunset", "night"]:
		return
	var from := _capture_visual_state()
	time_of_day_id = preset_id
	_apply_time_of_day()
	var target := _capture_visual_state()
	_apply_visual_state(from)
	_start_visual_transition(from, target)
	profile_applied.emit(current_profile)


func set_background_preset(preset_id: String) -> void:
	if preset_id not in ["profile", "cream", "mist", "dusk", "night"]:
		return
	var from := _capture_visual_state()
	background_preset_id = preset_id
	_apply_background_preset()
	var target := _capture_visual_state()
	_apply_visual_state(from)
	_start_visual_transition(from, target)
	profile_applied.emit(current_profile)


func set_particle_quality(quality_id: String) -> void:
	if quality_id not in ["low", "medium", "high"]:
		return
	particle_quality_id = quality_id
	_apply_particle_quality()


func set_user_post_effects(ssao_enabled: bool, bloom_enabled: bool) -> void:
	_user_ssao_enabled = ssao_enabled
	_user_bloom_enabled = bloom_enabled
	if _environment == null or current_profile == null:
		return
	var env := _environment.environment
	env.ssao_enabled = current_profile.ssao_enabled and _user_ssao_enabled
	env.glow_enabled = (
		(current_profile.glow_enabled or time_of_day_id in ["sunset", "night"])
		and _user_bloom_enabled
	)


func weather_id() -> String:
	if current_profile == mist_profile:
		return "mist"
	if current_profile == rain_profile:
		return "rain"
	if current_profile == leaves_profile:
		return "leaves"
	if current_profile == snow_profile:
		return "snow"
	if current_profile == blossom_profile:
		return "blossom"
	return "day"


func _profile_for_weather(weather_id: String) -> VisualStyleProfile:
	match weather_id:
		"day":
			return day_profile
		"mist":
			return mist_profile
		"rain":
			return rain_profile
		"leaves":
			return leaves_profile
		"snow":
			return snow_profile
		"blossom":
			return blossom_profile
	return null


func is_dark_background() -> bool:
	return time_of_day_id == "night" or background_preset_id == "night" or (
		background_preset_id == "profile"
		and current_profile != null
		and current_profile.rain_enabled
	)


## Scales warm local lights (campfires, lanterns) so they whisper by day and
## become the primary readable light sources at night.
func local_light_energy(base_energy: float) -> float:
	var profile_multiplier := current_profile.local_light_multiplier if current_profile else 1.0
	var time_multiplier := 1.0
	match time_of_day_id:
		"morning":
			time_multiplier = 1.15
		"sunset":
			time_multiplier = 1.5
		"night":
			time_multiplier = NIGHT_LOCAL_LIGHT_MULTIPLIER
	return base_energy * profile_multiplier * time_multiplier


func refresh_local_light(light: OmniLight3D) -> void:
	if light == null:
		return
	var base_energy := float(light.get_meta("base_energy", light.light_energy))
	var scaled_energy := local_light_energy(base_energy)
	# Flickering lights read this multiplier every pulse, so changing the
	# time of day cannot be overwritten by their animation tween.
	light.set_meta(
		"time_energy_scale",
		scaled_energy / base_energy if base_energy > 0.0 else 1.0
	)
	light.light_energy = scaled_energy


func _on_tree_node_added(node: Node) -> void:
	var light := node as OmniLight3D
	if light != null and light.is_in_group("warm_lights"):
		refresh_local_light(light)


## Complete live environment record for automated clean-room diagnostics.
func runtime_manifest() -> Dictionary:
	var env := _environment.environment
	var particles := {}
	for node: GPUParticles3D in [_rain, _motes, _leaves, _snow, _blossoms, _spores]:
		particles[node.name] = _particle_manifest(node)
	return {
		"runtime_state": {
			"weather": weather_id(),
			"time_of_day": time_of_day_id,
			"background": background_preset_id,
			"particle_quality": particle_quality_id,
			"profile": current_profile.profile_id,
			"transition_duration_seconds": 0.35 if current_profile.gg_pipeline_enabled else 1.0,
		},
		"gg_grade_pass": {
			"enabled": _grade_layer.visible,
			"post_exposure": _grade_material.get_shader_parameter("post_exposure"),
			"color_balance": _grade_material.get_shader_parameter("color_balance"),
			"contrast": _grade_material.get_shader_parameter("grade_contrast"),
			"saturation": _grade_material.get_shader_parameter("grade_saturation"),
			"tonemapper": _grade_material.get_shader_parameter("tonemapper"),
		},
		"directional_light": {
			"color": _sun.light_color,
			"energy": _sun.light_energy,
			"specular": _sun.light_specular,
			"rotation_degrees": _sun.rotation_degrees,
			"shadow_enabled": _sun.shadow_enabled,
			"shadow_mode": _sun.directional_shadow_mode,
			"shadow_max_distance": _sun.directional_shadow_max_distance,
			"shadow_blended_splits": _sun.directional_shadow_blend_splits,
			"shadow_split_1": _sun.directional_shadow_split_1,
			"shadow_split_2": _sun.directional_shadow_split_2,
			"shadow_split_3": _sun.directional_shadow_split_3,
			"shadow_fade_start": _sun.directional_shadow_fade_start,
			"shadow_opacity": _sun.shadow_opacity,
			"shadow_blur": _sun.shadow_blur,
			"angular_distance": _sun.light_angular_distance,
			"shadow_bias": _sun.shadow_bias,
			"shadow_normal_bias": _sun.shadow_normal_bias,
		},
		"ambient_and_sky": {
			"background_mode": env.background_mode,
			"background_color": env.background_color,
			"ambient_source": env.ambient_light_source,
			"ambient_color": env.ambient_light_color,
			"ambient_energy": env.ambient_light_energy,
			"sky_contribution": env.ambient_light_sky_contribution,
			"sky_color": _ambient_material.sky_top_color,
			"equator_color": _ambient_material.sky_horizon_color,
			"ground_color": _ambient_material.ground_bottom_color,
			"reflected_light_source": env.reflected_light_source,
		},
		"fog": {
			"enabled": env.fog_enabled,
			"color": env.fog_light_color,
			"density": env.fog_density,
			"sky_affect": env.fog_sky_affect,
		},
		"reflection_probe": {
			"enabled": _reflection_probe.visible,
			"size": _reflection_probe.size,
			"position": _reflection_probe.position,
			"intensity": _reflection_probe.intensity,
			"max_distance": _reflection_probe.max_distance,
			"box_projection": _reflection_probe.box_projection,
			"shadows": _reflection_probe.enable_shadows,
			"update_mode": _reflection_probe.update_mode,
			"resolution": 128,
			"bounces": 1,
		},
		"post_processing": {
			"tonemap_mode": env.tonemap_mode,
			"exposure": env.tonemap_exposure,
			"agx_white": env.tonemap_agx_white,
			"agx_contrast": env.tonemap_agx_contrast,
			"color_adjustment_enabled": env.adjustment_enabled,
			"brightness": env.adjustment_brightness,
			"contrast": env.adjustment_contrast,
			"saturation": env.adjustment_saturation,
			"ssao_enabled": env.ssao_enabled,
			"ssao_intensity": env.ssao_intensity,
			"ssao_radius": env.ssao_radius,
			"ssao_power": env.ssao_power,
			"ssao_detail": env.ssao_detail,
			"ssao_horizon": env.ssao_horizon,
			"ssao_sharpness": env.ssao_sharpness,
			"ssil_enabled": env.ssil_enabled,
			"ssil_intensity": env.ssil_intensity,
			"ssil_radius": env.ssil_radius,
			"ssil_sharpness": env.ssil_sharpness,
			"ssr_enabled": env.ssr_enabled,
			"ssr_max_steps": env.ssr_max_steps,
			"ssr_fade_in": env.ssr_fade_in,
			"ssr_fade_out": env.ssr_fade_out,
			"ssr_depth_tolerance": env.ssr_depth_tolerance,
			"bloom_enabled": env.glow_enabled,
			"bloom_intensity": env.glow_intensity,
			"bloom_hdr_threshold": env.glow_hdr_threshold,
			"bloom_mix": env.glow_bloom,
			"bloom_normalized": env.glow_normalized,
			"anti_aliasing": {
				"msaa_3d": ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d"),
				"screen_space_aa": ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa"),
				"taa": ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa"),
				"debanding": ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_debanding"),
			},
		},
		"particles": particles,
	}


func _particle_manifest(particles: GPUParticles3D) -> Dictionary:
	var result := {
		"emitting": particles.emitting,
		"amount": particles.amount,
		"amount_ratio": particles.amount_ratio,
		"lifetime": particles.lifetime,
		"preprocess": particles.preprocess,
		"randomness": particles.randomness,
		"position": particles.position,
		"visibility_aabb": particles.visibility_aabb,
		"draw_pass": particles.draw_pass_1.get_class() if particles.draw_pass_1 != null else "",
		"curves": particles.get_meta("curve_manifest", {}).duplicate(true),
	}
	var process := particles.process_material as ParticleProcessMaterial
	if process != null:
		result["process_material"] = {
			"emission_shape": process.emission_shape,
			"emission_box_extents": process.emission_box_extents,
			"direction": process.direction,
			"spread_degrees": process.spread,
			"initial_velocity_min": process.initial_velocity_min,
			"initial_velocity_max": process.initial_velocity_max,
			"gravity": process.gravity,
			"angular_velocity_min": process.angular_velocity_min,
			"angular_velocity_max": process.angular_velocity_max,
			"scale_min": process.scale_min,
			"scale_max": process.scale_max,
		}
	return result


func _transition_to_profile(profile: VisualStyleProfile) -> void:
	if profile == null or profile == current_profile:
		return
	var from := _capture_visual_state()
	apply_profile(profile)
	var target := _capture_visual_state()
	_apply_visual_state(from)
	_start_visual_transition(from, target)


func _capture_visual_state() -> Dictionary:
	var env := _environment.environment
	var fallback := env.background_color
	# The GG screen-skybox backdrop blends as a flat color; only the mist
	# gradient material carries tweenable top/mid/bottom parameters.
	var mist_visible := _bg_layer.visible and _bg_rect.material == _bg_material
	return {
		"sun_color": _sun.light_color,
		"sun_energy": _sun.light_energy,
		"sun_rotation": _sun.rotation_degrees,
		"ambient_energy": env.ambient_light_energy,
		"exposure": env.tonemap_exposure,
		"brightness": env.adjustment_brightness,
		"contrast": env.adjustment_contrast,
		"saturation": env.adjustment_saturation,
		"ssao_intensity": env.ssao_intensity,
		"glow_intensity": env.glow_intensity,
		"fog_density": env.fog_density,
		"fog_color": env.fog_light_color,
		"sky": _ambient_material.sky_top_color,
		"equator": _ambient_material.sky_horizon_color,
		"ground": _ambient_material.ground_bottom_color,
		"background": env.background_color,
		"gradient_visible": mist_visible,
		"gradient_top": _bg_material.get_shader_parameter("top_color") if mist_visible else fallback,
		"gradient_mid": _bg_material.get_shader_parameter("mid_color") if mist_visible else fallback,
		"gradient_bottom": _bg_material.get_shader_parameter("bottom_color") if mist_visible else fallback,
		"stars": float(_bg_material.get_shader_parameter("stars_amount")) if mist_visible else 0.0,
		"gg_bg_visible": _gg_bg_quad.visible,
		"gg_bg0": _gg_bg_material.get_shader_parameter("color0") if _gg_bg_quad.visible else fallback,
		"gg_bg1": _gg_bg_material.get_shader_parameter("color1") if _gg_bg_quad.visible else fallback,
	}


func _apply_visual_state(state: Dictionary) -> void:
	var env := _environment.environment
	_sun.light_color = state["sun_color"]
	_sun.light_energy = state["sun_energy"]
	_sun.rotation_degrees = state["sun_rotation"]
	env.ambient_light_energy = state["ambient_energy"]
	env.tonemap_exposure = state["exposure"]
	env.adjustment_brightness = state["brightness"]
	env.adjustment_contrast = state["contrast"]
	env.adjustment_saturation = state["saturation"]
	env.ssao_intensity = state["ssao_intensity"]
	env.glow_intensity = state["glow_intensity"]
	env.fog_density = state["fog_density"]
	env.fog_light_color = state["fog_color"]
	_ambient_material.sky_top_color = state["sky"]
	_ambient_material.sky_horizon_color = state["equator"]
	_ambient_material.ground_horizon_color = state["equator"]
	_ambient_material.ground_bottom_color = state["ground"]
	env.background_color = state["background"]
	if bool(state["gradient_visible"]):
		_set_gradient_background(
			state["gradient_top"],
			state["gradient_mid"],
			state["gradient_bottom"],
			state["stars"]
		)
	else:
		_set_flat_background(state["background"])


func _start_visual_transition(from: Dictionary, target: Dictionary) -> void:
	if _theme_tween != null and _theme_tween.is_valid():
		_theme_tween.kill()
	_theme_tween = create_tween()
	# GG's WorldThemeController blends linearly over 0.35 s; the legacy
	# profiles keep their original one-second eased fade.
	var gg := current_profile != null and current_profile.gg_pipeline_enabled
	if gg:
		_theme_tween.set_trans(Tween.TRANS_LINEAR)
	else:
		_theme_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_theme_tween.tween_method(
		func(weight: float): _blend_visual_state(from, target, weight),
		0.0,
		1.0,
		0.35 if gg else 1.0
	)
	_theme_tween.tween_callback(func():
		_apply_time_of_day()
		_apply_background_preset()
	)


func _blend_visual_state(from: Dictionary, target: Dictionary, weight: float) -> void:
	var env := _environment.environment
	_sun.light_color = (from["sun_color"] as Color).lerp(target["sun_color"], weight)
	_sun.light_energy = lerpf(from["sun_energy"], target["sun_energy"], weight)
	_sun.rotation_degrees = (from["sun_rotation"] as Vector3).lerp(target["sun_rotation"], weight)
	env.ambient_light_energy = lerpf(from["ambient_energy"], target["ambient_energy"], weight)
	env.tonemap_exposure = lerpf(from["exposure"], target["exposure"], weight)
	env.adjustment_brightness = lerpf(from["brightness"], target["brightness"], weight)
	env.adjustment_contrast = lerpf(from["contrast"], target["contrast"], weight)
	env.adjustment_saturation = lerpf(from["saturation"], target["saturation"], weight)
	env.ssao_intensity = lerpf(from["ssao_intensity"], target["ssao_intensity"], weight)
	env.glow_intensity = lerpf(from["glow_intensity"], target["glow_intensity"], weight)
	env.fog_density = lerpf(from["fog_density"], target["fog_density"], weight)
	env.fog_light_color = (from["fog_color"] as Color).lerp(target["fog_color"], weight)
	_ambient_material.sky_top_color = (from["sky"] as Color).lerp(target["sky"], weight)
	_ambient_material.sky_horizon_color = (from["equator"] as Color).lerp(target["equator"], weight)
	_ambient_material.ground_horizon_color = _ambient_material.sky_horizon_color
	_ambient_material.ground_bottom_color = (from["ground"] as Color).lerp(target["ground"], weight)
	var quad_involved: bool = bool(from.get("gg_bg_visible", false)) or bool(target.get("gg_bg_visible", false))
	if quad_involved:
		var from0 := from.get("gg_bg0", from["background"]) as Color
		var from1 := from.get("gg_bg1", from["background"]) as Color
		var target0 := target.get("gg_bg0", target["background"]) as Color
		var target1 := target.get("gg_bg1", target["background"]) as Color
		var sparkles := 0.0
		if _gg_bg_material.get_shader_parameter("sparkle_amount") != null:
			sparkles = float(_gg_bg_material.get_shader_parameter("sparkle_amount"))
		_set_gg_background(from0.lerp(target0, weight), from1.lerp(target1, weight), sparkles > 0.5)
		return
	var from_top := from["gradient_top"] as Color
	var from_mid := from["gradient_mid"] as Color
	var from_bottom := from["gradient_bottom"] as Color
	var target_top := target["gradient_top"] as Color
	var target_mid := target["gradient_mid"] as Color
	var target_bottom := target["gradient_bottom"] as Color
	_set_gradient_background(
		from_top.lerp(target_top, weight),
		from_mid.lerp(target_mid, weight),
		from_bottom.lerp(target_bottom, weight),
		lerpf(from["stars"], target["stars"], weight)
	)


func _apply_particle_quality() -> void:
	var quality_multiplier: float = float({"low": 0.3, "medium": 0.6, "high": 1.0}.get(particle_quality_id, 1.0))
	for particles in [_rain, _motes, _leaves, _snow, _blossoms, _spores]:
		if particles == null:
			continue
		particles.amount_ratio = float(particles.get_meta("base_amount_ratio", 1.0)) * quality_multiplier


## The six serialized WorldTheme assets from the GG reference build
## (sharedassets1 202-207). "sky"/"equator" are HDR pickers and therefore
## LINEAR radiance; every other color is sRGB-authored. "night_*" values are
## the dark-mode multipliers/targets used by WorldTheme.Calculate.
const GG_THEMES := {
	"default": {
		"bg0": Color(0.906, 0.87623, 0.78265), "bg1": Color(0.90588, 0.87059, 0.81569),
		"night_bg": Color(0.913, 0.80487, 0.70666),
		"sky": Color(0.8, 0.74118, 0.76863), "equator": Color(0.65098, 0.41961, 0.37255),
		"night_tint": Color(1.0, 0.90825, 0.78931),
		"light": Color(1.0, 1.0, 0.99216), "night_light": Color(1.0, 0.87073, 0.67451),
		"min_intensity": 0.8,
	},
	"blue": {
		"bg0": Color(0.62125, 0.69434, 0.71), "bg1": Color(0.80029, 0.955, 0.84412),
		"night_bg": Color(0.26171, 0.27566, 0.318),
		"sky": Color(0.75294, 0.82745, 0.87843), "equator": Color(0.70196, 0.61569, 0.62745),
		"night_tint": Color(0.5451, 0.60691, 0.67059),
		"light": Color(1.0, 0.96078, 0.89804), "night_light": Color(0.43137, 0.60784, 0.77255),
		"min_intensity": 0.8,
	},
	"green": {
		"bg0": Color(0.78824, 0.81176, 0.57255), "bg1": Color(0.93217, 0.96, 0.6771),
		"night_bg": Color(0.28948, 0.30371, 0.396),
		"sky": Color(0.8, 0.74118, 0.76863), "equator": Color(0.50196, 0.43529, 0.33725),
		"night_tint": Color(0.54385, 0.65407, 0.67059),
		"light": Color(1.0, 0.96471, 0.91373), "night_light": Color(0.59069, 0.743, 0.71471),
		"min_intensity": 0.8,
	},
	"brown": {
		"bg0": Color(0.241, 0.216, 0.21184), "bg1": Color(0.276, 0.24892, 0.23902),
		"night_bg": Color(0.76821, 0.78708, 0.80189),
		"sky": Color(0.61569, 0.48235, 0.35294), "equator": Color(0.65098, 0.50588, 0.46667),
		"night_tint": Color(0.721, 0.62799, 0.47298),
		"light": Color(1.0, 1.0, 0.99216), "night_light": Color(0.83137, 0.88235, 0.90196),
		"min_intensity": 0.6,
	},
	"orange": {
		"bg0": Color(0.95294, 0.78039, 0.53725), "bg1": Color(0.96078, 0.61252, 0.45882),
		"night_bg": Color(0.55189, 0.61503, 0.67059),
		"sky": Color(0.8, 0.74118, 0.76863), "equator": Color(0.65098, 0.41961, 0.37255),
		"night_tint": Color(0.72642, 0.68393, 0.51854),
		"light": Color(0.95283, 0.84909, 0.68915), "night_light": Color(0.8331, 0.92453, 0.80824),
		"min_intensity": 0.85,
	},
	"pink": {
		"bg0": Color(0.90588, 0.67524, 0.67216), "bg1": Color(0.95686, 0.83735, 0.8),
		"night_bg": Color(0.31765, 0.26275, 0.29295),
		"sky": Color(0.87843, 0.75294, 0.76966), "equator": Color(0.70196, 0.61569, 0.62745),
		"night_tint": Color(0.5451, 0.60691, 0.67059),
		"light": Color(1.0, 0.89804, 0.89928), "night_light": Color(0.55434, 0.43137, 0.77255),
		"min_intensity": 0.95,
	},
}

## Each Suma time slot is an exact steady GG state (theme id, lightLevel).
## Verified against the official screenshot set: cream days are Default
## light, the rosy garden is Pink light, warm evenings are Orange light, and
## GG's iconic starry night is the Brown theme's dark backdrop.
const GG_TIME_STATES := {
	"morning": ["pink", 1.0],
	"noon": ["default", 1.0],
	"sunset": ["orange", 1.0],
	"night": ["brown", 0.0],
}


func _gg_time_state() -> Array:
	return GG_TIME_STATES.get(time_of_day_id, ["default", 1.0])


func _gg_light_level() -> float:
	return float(_gg_time_state()[1])


## The serialized theme remains the hue source, but Suma's night art direction
## deliberately goes far darker than the extracted reference values. Cool,
## low-energy moon fill preserves silhouettes while warm local lights provide
## the readable focal areas.
func _apply_gg_time_of_day() -> void:
	var profile := current_profile
	var env := _environment.environment
	var state := _gg_time_state()
	var theme: Dictionary = GG_THEMES[state[0]]
	var level := float(state[1])
	var ambient_tint := NIGHT_AMBIENT_TINT.lerp(Color.WHITE, level)
	_sun.light_color = (theme.night_light as Color).lerp(theme.light, level)
	_sun.light_energy = (
		lerpf(NIGHT_SUN_ENERGY_MULTIPLIER, 1.0, level)
		* profile.sun_energy
	)
	_sun.rotation_degrees = Vector3(
		lerpf(profile.sun_pitch_night_deg, profile.sun_pitch_deg, level),
		profile.sun_yaw_deg,
		0.0
	)
	# The GG trilight colors are serialized from Unity HDR pickers, i.e. they
	# are already LINEAR radiance. Godot color properties get an sRGB->linear
	# conversion at render time, so pre-encode to make that conversion land
	# back on the reference linear values. The night tint multiplies the
	# linear values (matching WorldTheme.Calculate's raw multiply).
	_ambient_material.sky_top_color = ((theme.sky as Color) * ambient_tint).linear_to_srgb()
	_ambient_material.sky_horizon_color = ((theme.equator as Color) * ambient_tint).linear_to_srgb()
	_ambient_material.ground_horizon_color = _ambient_material.sky_horizon_color
	_ambient_material.ground_bottom_color = (profile.ambient_ground_color * ambient_tint).linear_to_srgb()
	env.ambient_light_energy = (
		profile.ambient_energy
		* lerpf(NIGHT_AMBIENT_ENERGY_MULTIPLIER, 1.0, level)
	)
	env.glow_enabled = profile.glow_enabled and _user_bloom_enabled
	env.glow_intensity = lerpf(
		NIGHT_GLOW_INTENSITY,
		profile.glow_intensity,
		level
	)
	var bg_tint := (
		(theme.night_bg as Color).lerp(Color.WHITE, level)
		* NIGHT_BACKGROUND_TINT.lerp(Color.WHITE, level)
	)
	env.background_color = (theme.bg1 as Color) * bg_tint
	if profile.background_gg_gradient and background_preset_id == "profile":
		_set_gg_background(
			(theme.bg0 as Color) * bg_tint,
			(theme.bg1 as Color) * bg_tint,
			profile.bg_sparkles_enabled
		)


func _apply_time_of_day() -> void:
	if current_profile == null:
		return
	if current_profile.gg_pipeline_enabled:
		_apply_gg_time_of_day()
		return
	var env := _environment.environment
	_sun.light_color = current_profile.sun_color
	_sun.light_energy = current_profile.sun_energy
	_sun.rotation_degrees = Vector3(current_profile.sun_pitch_deg, current_profile.sun_yaw_deg, 0.0)
	env.ambient_light_energy = current_profile.ambient_energy
	env.glow_enabled = current_profile.glow_enabled and _user_bloom_enabled
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
			env.glow_enabled = _user_bloom_enabled
			env.glow_intensity = maxf(current_profile.glow_intensity, 0.28)
		"night":
			_sun.light_color = Color(0.42, 0.56, 0.9)
			_sun.light_energy = (
				current_profile.sun_energy
				* NIGHT_SUN_ENERGY_MULTIPLIER
			)
			_sun.rotation_degrees.x = -38.0
			env.ambient_light_energy = (
				current_profile.ambient_energy
				* NIGHT_AMBIENT_ENERGY_MULTIPLIER
			)
			env.glow_enabled = _user_bloom_enabled
			env.glow_intensity = maxf(
				current_profile.glow_intensity,
				NIGHT_GLOW_INTENSITY
			)


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
			if current_profile.background_gg_gradient:
				var state := _gg_time_state()
				var theme: Dictionary = GG_THEMES[state[0]]
				var bg_tint := (theme.night_bg as Color).lerp(Color.WHITE, float(state[1]))
				_set_gg_background(
					(theme.bg0 as Color) * bg_tint,
					(theme.bg1 as Color) * bg_tint,
					current_profile.bg_sparkles_enabled
				)
			elif current_profile.background_gradient:
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
	_gg_bg_quad.visible = false


func _set_gradient_background(top: Color, middle: Color, bottom: Color, stars: float) -> void:
	_environment.environment.background_mode = Environment.BG_CANVAS
	_bg_layer.visible = true
	_gg_bg_quad.visible = false
	_bg_rect.material = _bg_material
	_bg_material.set_shader_parameter("top_color", top)
	_bg_material.set_shader_parameter("mid_color", middle)
	_bg_material.set_shader_parameter("bottom_color", bottom)
	_bg_material.set_shader_parameter("stars_amount", stars)


## GG "Custom/Screen Skybox" backdrop: bgColor0/bgColor1 wash plus sparkles,
## rendered by the far-plane quad inside the 3D pass.
func _set_gg_background(color0: Color, color1: Color, sparkles: bool) -> void:
	_environment.environment.background_mode = Environment.BG_COLOR
	_bg_layer.visible = false
	_gg_bg_quad.visible = true
	_gg_bg_material.set_shader_parameter("color0", color0)
	_gg_bg_material.set_shader_parameter("color1", color1)
	_gg_bg_material.set_shader_parameter("sparkle_amount", 1.0 if sparkles else 0.0)


func _configure_grade_pass(profile: VisualStyleProfile) -> void:
	_grade_layer.visible = profile.gg_pipeline_enabled
	if not profile.gg_pipeline_enabled:
		return
	_grade_material.set_shader_parameter("post_exposure", pow(2.0, profile.grade_post_exposure_ev))
	_grade_material.set_shader_parameter(
		"color_balance",
		_compute_color_balance(profile.grade_temperature, profile.grade_tint)
	)
	_grade_material.set_shader_parameter("grade_contrast", 1.0 + profile.grade_contrast / 100.0)
	_grade_material.set_shader_parameter("grade_saturation", 1.0 + profile.grade_saturation / 100.0)
	_grade_material.set_shader_parameter("tonemapper", 1 if profile.grade_tonemapper == "neutral" else 0)
	_grade_material.set_shader_parameter("effect_weight", 1.0)


## Unity PPv2 ColorUtilities.ComputeColorBalance: temperature/tint to an LMS
## white-balance multiplier, transcribed with the reference constants.
static func _compute_color_balance(temperature: float, tint: float) -> Vector3:
	var t1 := temperature / 60.0
	var t2 := tint / 60.0
	var x := 0.31271 - t1 * (0.1 if t1 < 0.0 else 0.05)
	var y := 2.87 * x - 3.0 * x * x - 0.27509507 + t2 * 0.05
	var big_x := x / y
	var big_z := (1.0 - x - y) / y
	var l := 0.7328 * big_x + 0.4296 - 0.1624 * big_z
	var m := -0.7036 * big_x + 1.6975 + 0.0061 * big_z
	var s := 0.0030 * big_x + 0.0136 + 0.9834 * big_z
	return Vector3(0.949237 / l, 1.03542 / m, 1.08728 / s)


func _build_rain() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Rain"
	particles.amount = 900
	particles.lifetime = 1.1
	particles.emitting = false
	particles.set_meta("base_amount_ratio", 1.0)
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
	_apply_particle_curves(
		particles,
		mat,
		[[0.0, 0.75], [0.08, 1.0], [0.9, 1.0], [1.0, 0.45]],
		[[0.0, 0.0], [0.04, 1.0], [0.9, 0.85], [1.0, 0.0]]
	)
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
	particles.set_meta("base_amount_ratio", 1.0)
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
	_apply_particle_curves(
		particles,
		process,
		[[0.0, 0.15], [0.12, 0.85], [0.72, 1.0], [1.0, 0.0]],
		[[0.0, 0.0], [0.12, 0.55], [0.72, 0.45], [1.0, 0.0]]
	)
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


func _build_leaves() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "FallingLeaves"
	particles.amount = 100
	particles.lifetime = 10.0
	particles.preprocess = 10.0
	particles.randomness = 0.8
	particles.emitting = false
	# Confirmed ambient metadata: max 100, 5–10 s lifetime and about 5/s.
	particles.set_meta("base_amount_ratio", 0.5)
	particles.visibility_aabb = AABB(Vector3(-30, -8, -30), Vector3(60, 26, 60))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(24, 4, 24)
	process.direction = Vector3(0.75, -0.25, 0.22)
	process.spread = 25.0
	process.initial_velocity_min = 0.45
	process.initial_velocity_max = 1.15
	process.gravity = Vector3(0, -0.08, 0)
	process.angular_velocity_min = -120.0
	process.angular_velocity_max = 120.0
	process.scale_min = 0.65
	process.scale_max = 1.25
	particles.process_material = process
	_apply_particle_curves(
		particles,
		process,
		[[0.0, 0.35], [0.08, 1.0], [0.82, 0.88], [1.0, 0.0]],
		[[0.0, 0.0], [0.08, 1.0], [0.82, 0.9], [1.0, 0.0]]
	)
	particles.position.y = 8.0
	var leaf := QuadMesh.new()
	leaf.size = Vector2(0.11, 0.18)
	leaf.material = _particle_material(Color(0.63, 0.48, 0.18, 0.82), true)
	particles.draw_pass_1 = leaf
	return particles


func _build_snow() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "SoftSnow"
	particles.amount = 320
	particles.lifetime = 8.0
	particles.preprocess = 8.0
	particles.randomness = 0.9
	particles.emitting = false
	particles.set_meta("base_amount_ratio", 1.0)
	particles.visibility_aabb = AABB(Vector3(-30, -8, -30), Vector3(60, 26, 60))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(24, 2, 24)
	process.direction = Vector3(0.08, -1, 0.04)
	process.spread = 12.0
	process.initial_velocity_min = 0.45
	process.initial_velocity_max = 1.0
	process.gravity = Vector3(0, -0.06, 0)
	process.scale_min = 0.55
	process.scale_max = 1.4
	particles.process_material = process
	_apply_particle_curves(
		particles,
		process,
		[[0.0, 0.25], [0.1, 1.0], [0.78, 0.85], [1.0, 0.0]],
		[[0.0, 0.0], [0.08, 0.9], [0.78, 0.8], [1.0, 0.0]]
	)
	particles.position.y = 12.0
	var flake := SphereMesh.new()
	flake.radius = 0.025
	flake.height = 0.05
	flake.material = _particle_material(Color(0.96, 0.98, 1.0, 0.78))
	particles.draw_pass_1 = flake
	return particles


func _build_blossoms() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "BlossomPetals"
	particles.amount = 100
	particles.lifetime = 10.0
	particles.preprocess = 10.0
	particles.randomness = 0.85
	particles.emitting = false
	particles.set_meta("base_amount_ratio", 0.5)
	particles.visibility_aabb = AABB(Vector3(-30, -8, -30), Vector3(60, 24, 60))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(24, 3, 24)
	process.direction = Vector3(0.52, -0.18, 0.2)
	process.spread = 25.0
	process.initial_velocity_min = 0.25
	process.initial_velocity_max = 0.75
	process.gravity = Vector3(0, -0.04, 0)
	process.angular_velocity_min = -150.0
	process.angular_velocity_max = 150.0
	process.scale_min = 0.7
	process.scale_max = 1.2
	particles.process_material = process
	_apply_particle_curves(
		particles,
		process,
		[[0.0, 0.25], [0.08, 1.0], [0.84, 0.9], [1.0, 0.0]],
		[[0.0, 0.0], [0.08, 1.0], [0.84, 0.9], [1.0, 0.0]]
	)
	particles.position.y = 7.0
	var petal := QuadMesh.new()
	petal.size = Vector2(0.09, 0.13)
	petal.material = _particle_material(Color(1.0, 0.69, 0.77, 0.84), true)
	particles.draw_pass_1 = petal
	return particles


func _build_spores() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "WarmSpores"
	particles.amount = 100
	particles.lifetime = 10.0
	particles.preprocess = 10.0
	particles.randomness = 0.95
	particles.emitting = false
	particles.set_meta("base_amount_ratio", 0.5)
	particles.visibility_aabb = AABB(Vector3(-30, -6, -30), Vector3(60, 18, 60))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(24, 2.5, 24)
	process.direction = Vector3(0.1, 1.0, 0.08)
	process.spread = 25.0
	process.initial_velocity_min = 0.04
	process.initial_velocity_max = 0.18
	process.gravity = Vector3.ZERO
	process.scale_min = 0.5
	process.scale_max = 1.2
	particles.process_material = process
	_apply_particle_curves(
		particles,
		process,
		[[0.0, 0.1], [0.16, 0.85], [0.7, 1.0], [1.0, 0.0]],
		[[0.0, 0.0], [0.16, 0.5], [0.7, 0.42], [1.0, 0.0]]
	)
	particles.position.y = 2.0
	var spore := SphereMesh.new()
	spore.radius = 0.014
	spore.height = 0.028
	spore.material = _particle_material(Color(1.0, 0.85, 0.47, 0.5))
	particles.draw_pass_1 = spore
	return particles


func _particle_material(color: Color, billboard := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if billboard:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return material


## Original lifecycle curves shared by the GPU particle modules. Values are
## normalized over particle lifetime and are also retained as metadata so the
## diagnostics exporter can preserve the exact authored points.
func _apply_particle_curves(
		particles: GPUParticles3D,
	process: ParticleProcessMaterial,
	scale_points: Array,
	alpha_points: Array
) -> void:
	var scale_curve := Curve.new()
	scale_curve.min_value = 0.0
	scale_curve.max_value = 1.0
	for point in scale_points:
		scale_curve.add_point(Vector2(float(point[0]), float(point[1])))
	var scale_texture := CurveTexture.new()
	scale_texture.curve = scale_curve
	process.scale_curve = scale_texture

	var alpha_gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for point in alpha_points:
		offsets.append(float(point[0]))
		colors.append(Color(1.0, 1.0, 1.0, float(point[1])))
	alpha_gradient.offsets = offsets
	alpha_gradient.colors = colors
	var alpha_texture := GradientTexture1D.new()
	alpha_texture.gradient = alpha_gradient
	process.color_ramp = alpha_texture
	particles.set_meta("curve_manifest", {
		"scale_over_lifetime": scale_points.duplicate(true),
		"alpha_over_lifetime": alpha_points.duplicate(true),
		"interpolation": "linear",
	})
