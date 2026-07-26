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
@export var leaves_profile: VisualStyleProfile
@export var snow_profile: VisualStyleProfile
@export var blossom_profile: VisualStyleProfile

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
var time_of_day_id := "noon"
var background_preset_id := "profile"
var particle_quality_id := "high"
var _theme_tween: Tween


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

	# Confirmed reference probe envelope: realtime, 128 px, one bounce,
	# approximately 50 × 15 × 50 units with box projection disabled.
	_reflection_probe = ReflectionProbe.new()
	_reflection_probe.name = "GardenReflectionProbe"
	_reflection_probe.size = Vector3(50.0, 15.0, 50.0)
	_reflection_probe.position.y = 4.0
	_reflection_probe.intensity = 1.0
	_reflection_probe.max_distance = 50.0
	_reflection_probe.box_projection = false
	_reflection_probe.enable_shadows = true
	_reflection_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
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
		day_profile = load("res://assets/visual_profiles/gg_day_profile.tres")
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
	env.adjustment_enabled = true
	env.adjustment_brightness = profile.brightness
	env.adjustment_contrast = profile.contrast
	env.adjustment_saturation = profile.saturation
	env.ssao_enabled = profile.ssao_enabled
	env.ssao_intensity = profile.ssao_intensity
	env.ssao_radius = profile.ssao_radius
	env.ssao_power = profile.ssao_power
	env.ssao_detail = profile.ssao_detail
	env.ssao_horizon = profile.ssao_horizon
	env.ssao_sharpness = profile.ssao_sharpness
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.2
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
	_leaves.emitting = profile.leaves_enabled
	_snow.emitting = profile.snow_enabled
	_blossoms.emitting = profile.blossoms_enabled
	_spores.emitting = profile.spores_enabled
	_apply_particle_quality()
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


func reset_admin_overrides() -> void:
	time_of_day_id = "noon"
	background_preset_id = "profile"
	particle_quality_id = "high"
	apply_profile(day_profile)


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
			"transition_duration_seconds": 1.0,
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
			"ssr_enabled": env.ssr_enabled,
			"ssr_max_steps": env.ssr_max_steps,
			"ssr_fade_in": env.ssr_fade_in,
			"ssr_fade_out": env.ssr_fade_out,
			"ssr_depth_tolerance": env.ssr_depth_tolerance,
			"bloom_enabled": env.glow_enabled,
			"bloom_intensity": env.glow_intensity,
			"bloom_hdr_threshold": env.glow_hdr_threshold,
			"bloom_mix": env.glow_bloom,
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
		"gradient_visible": _bg_layer.visible,
		"gradient_top": _bg_material.get_shader_parameter("top_color") if _bg_layer.visible else fallback,
		"gradient_mid": _bg_material.get_shader_parameter("mid_color") if _bg_layer.visible else fallback,
		"gradient_bottom": _bg_material.get_shader_parameter("bottom_color") if _bg_layer.visible else fallback,
		"stars": float(_bg_material.get_shader_parameter("stars_amount")) if _bg_layer.visible else 0.0,
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
	_theme_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_theme_tween.tween_method(
		func(weight: float): _blend_visual_state(from, target, weight),
		0.0,
		1.0,
		1.0
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
