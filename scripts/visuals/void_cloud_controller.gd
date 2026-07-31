class_name VoidCloudController
extends Node3D
## Horizon Zero Dawn style volumetric cloud sea (Schneider & Vos, SIGGRAPH
## 2015). One fixed world-space slab below the island is ray-marched by
## assets/materials/void_cloud_sea.gdshader: Perlin-Worley base shape,
## Worley edge erosion distorted by curl noise, a height gradient and a
## drifting weather coverage field, lit with Beer's law, Henyey-Greenstein
## scattering and the powder dark-edge term.
##
## The controller owns everything the shader cannot: it bakes the tiling
## noise fields into 3D textures at startup (procedurally, from
## FastNoiseLite - no image assets), positions the slab from the island
## underside, follows the lighting rig's palette across time of day and
## weather, and accumulates wind time. Because the slab is anchored in
## world space, zooming or orbiting the camera only changes perspective;
## the cloudscape itself can never recompose or rescale with the view.

const CLOUD_SHADER: Shader = preload(
	"res://assets/materials/void_cloud_sea.gdshader"
)

const SLAB_HALF_EXTENT := 84.0
const SLAB_THICKNESS := 11.5
const ISLAND_CLEARANCE := 11.5
const PALETTE_BLEND_TAU := 1.8
const BASE_NOISE_SIZE := 96
const WORLEY_NOISE_SIZE := 80
const DETAIL_NOISE_SIZE := 48
const CURL_NOISE_SIZE := 96

@export var enabled := true
@export var wind_speed := 1.0
@export var volume_opacity := 0.97
@export_enum("low", "medium", "high") var quality_level := "medium"

# One base cotton palette, authored for full daylight. Every time of day
# is produced by grading it with the sky colours the lighting rig pushes
# via set_sky_light(), so the clouds always sit inside the sky's own
# light: dim grey-blue under the night sky, warm at sunset, cream at
# noon. Weather modifiers apply to the base before grading.
@export_group("Cloud palette")
@export var base_crown := Color(1.0, 1.0, 0.985)
@export var base_light := Color(1.0, 0.965, 0.90)
@export var base_shade := Color(0.878, 0.848, 0.832)
@export var base_rim := Color(1.0, 0.80, 0.52)

const FALLBACK_ATMOSPHERE := Color(1.082, 1.036, 0.932)

var _environment: Environment
var _rig: Node
var _focus: Node3D
var _camera: Camera3D
var _slab: MeshInstance3D
var _material: ShaderMaterial
var _underside_y := -1.0
var _camera_distance := 37.0
var _wind_seconds := 0.0
var _raymarch_steps := 44
var _cloud_top_y := -12.5
var _cloud_bottom_y := -24.0

var _current_crown := base_crown
var _current_light := base_light
var _current_shade := base_shade
var _current_rim := base_rim
var _current_atmosphere := FALLBACK_ATMOSPHERE
var _current_opacity := 0.94
var _current_rain_absorption := 0.0
var _target_crown := base_crown
var _target_light := base_light
var _target_shade := base_shade
var _target_rim := base_rim
var _target_atmosphere := FALLBACK_ATMOSPHERE
var _target_opacity := 0.94
var _target_rain_absorption := 0.0

var _sky_color0 := Color(1.108, 1.015, 0.917)
var _sky_color1 := Color(1.082, 1.036, 0.932)
var _sky_zenith := Color(1.062, 0.962, 0.851)
var _sky_known := false


func setup(environment: Environment, lighting_rig: Node) -> void:
	_environment = environment
	_rig = lighting_rig
	_build_cloud_sea()
	configure_environment()
	apply_quality(quality_level)
	if _rig != null and _rig.has_signal("profile_applied"):
		_rig.profile_applied.connect(_on_lighting_changed)
	_refresh_palette_targets()


func set_world_reference(underside_y: float, focus: Node3D) -> void:
	_underside_y = underside_y
	_focus = focus
	_cloud_top_y = _underside_y - ISLAND_CLEARANCE
	_cloud_bottom_y = _cloud_top_y - SLAB_THICKNESS
	_update_slab_bounds()
	_resolve_camera()


func set_camera_distance(distance: float) -> void:
	# World-space clouds do not react to zoom; the distance is only kept
	# for the runtime manifest and debugging.
	_camera_distance = distance


func configure_environment() -> void:
	if _environment == null:
		return
	# Global fog would fade the island and player. The clouds create their
	# own optical depth inside the ray-marched slab only.
	_environment.volumetric_fog_enabled = false
	_environment.volumetric_fog_density = 0.0


func set_clouds_enabled(now_enabled: bool) -> void:
	enabled = now_enabled
	if _slab != null:
		_slab.visible = enabled


func apply_quality(level: String) -> void:
	if level not in ["low", "medium", "high"]:
		return
	quality_level = level
	match level:
		"low":
			_raymarch_steps = 28
		"high":
			_raymarch_steps = 64
		_:
			_raymarch_steps = 44
	if _material != null:
		_material.set_shader_parameter("view_steps", _raymarch_steps)


func _process(delta: float) -> void:
	if not enabled or _material == null:
		return
	_wind_seconds += delta * wind_speed
	var blend := 1.0 - exp(-delta / PALETTE_BLEND_TAU)
	_current_crown = _current_crown.lerp(_target_crown, blend)
	_current_light = _current_light.lerp(_target_light, blend)
	_current_shade = _current_shade.lerp(_target_shade, blend)
	_current_rim = _current_rim.lerp(_target_rim, blend)
	_current_atmosphere = _current_atmosphere.lerp(
		_target_atmosphere,
		blend
	)
	_current_opacity = lerpf(_current_opacity, _target_opacity, blend)
	_current_rain_absorption = lerpf(
		_current_rain_absorption,
		_target_rain_absorption,
		blend
	)
	_material.set_shader_parameter("crown_color", _current_crown)
	_material.set_shader_parameter("light_color", _current_light)
	_material.set_shader_parameter("shade_color", _current_shade)
	_material.set_shader_parameter("rim_color", _current_rim)
	_material.set_shader_parameter(
		"atmosphere_color",
		_current_atmosphere
	)
	_material.set_shader_parameter("mist_opacity", _current_opacity)
	_material.set_shader_parameter(
		"rain_absorption",
		_current_rain_absorption
	)
	_material.set_shader_parameter("wind_time", _wind_seconds)
	_resolve_camera()


func _build_cloud_sea() -> void:
	_material = ShaderMaterial.new()
	_material.shader = CLOUD_SHADER
	_material.render_priority = -12
	_material.set_shader_parameter("view_steps", _raymarch_steps)
	_material.set_shader_parameter("mist_opacity", volume_opacity)
	_material.set_shader_parameter(
		"wind_direction",
		Vector2(0.82, 0.57).normalized()
	)
	_bake_noise_fields()

	var box := BoxMesh.new()
	box.size = Vector3(
		SLAB_HALF_EXTENT * 2.0,
		SLAB_THICKNESS,
		SLAB_HALF_EXTENT * 2.0
	)
	box.material = _material

	_slab = MeshInstance3D.new()
	_slab.name = "HorizonCloudSea"
	_slab.mesh = box
	_slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_slab.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_slab.ignore_occlusion_culling = true
	_slab.custom_aabb = AABB(
		Vector3(-SLAB_HALF_EXTENT, -40.0, -SLAB_HALF_EXTENT),
		Vector3(SLAB_HALF_EXTENT * 2.0, 80.0, SLAB_HALF_EXTENT * 2.0)
	)
	_slab.visible = enabled
	add_child(_slab)
	_update_slab_bounds()


## Bakes the HZD noise set procedurally at startup. Nothing is loaded from
## disk: FastNoiseLite generates every field, so the system stays free of
## image assets while gaining the trilinear softness of texture sampling.
func _bake_noise_fields() -> void:
	var perlin := FastNoiseLite.new()
	perlin.noise_type = FastNoiseLite.TYPE_PERLIN
	perlin.fractal_type = FastNoiseLite.FRACTAL_FBM
	perlin.fractal_octaves = 4
	perlin.fractal_lacunarity = 2.0
	perlin.fractal_gain = 0.5
	perlin.frequency = 2.1 / float(BASE_NOISE_SIZE)
	perlin.seed = 811
	_material.set_shader_parameter(
		"base_perlin_noise",
		_bake_texture_3d(perlin, BASE_NOISE_SIZE)
	)

	var worley := FastNoiseLite.new()
	worley.noise_type = FastNoiseLite.TYPE_CELLULAR
	worley.cellular_distance_function = (
		FastNoiseLite.DISTANCE_EUCLIDEAN
	)
	worley.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	worley.fractal_type = FastNoiseLite.FRACTAL_FBM
	worley.fractal_octaves = 3
	worley.frequency = 4.2 / float(WORLEY_NOISE_SIZE)
	worley.seed = 233
	_material.set_shader_parameter(
		"base_worley_noise",
		_bake_texture_3d(worley, WORLEY_NOISE_SIZE)
	)

	var detail := FastNoiseLite.new()
	detail.noise_type = FastNoiseLite.TYPE_CELLULAR
	detail.cellular_distance_function = (
		FastNoiseLite.DISTANCE_EUCLIDEAN
	)
	detail.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = 2
	detail.frequency = 4.2 / float(DETAIL_NOISE_SIZE)
	detail.seed = 977
	_material.set_shader_parameter(
		"detail_worley_noise",
		_bake_texture_3d(detail, DETAIL_NOISE_SIZE)
	)

	_material.set_shader_parameter("curl_noise", _bake_curl_texture())


func _bake_texture_3d(noise: FastNoiseLite, size: int) -> ImageTexture3D:
	var slices := noise.get_image_3d(size, size, size)
	var converted: Array[Image] = []
	for slice in slices:
		if slice.get_format() != Image.FORMAT_L8:
			slice.convert(Image.FORMAT_L8)
		converted.append(slice)
	var texture := ImageTexture3D.new()
	texture.create(Image.FORMAT_L8, size, size, size, false, converted)
	return texture


## Curl of a smooth 2D field, per the talk: non-divergent flow used to
## fake turbulent distortion of the detail noise.
func _bake_curl_texture() -> ImageTexture:
	var field := FastNoiseLite.new()
	field.noise_type = FastNoiseLite.TYPE_SIMPLEX
	field.fractal_type = FastNoiseLite.FRACTAL_FBM
	field.fractal_octaves = 3
	field.frequency = 3.4 / float(CURL_NOISE_SIZE)
	field.seed = 421
	var image := Image.create(
		CURL_NOISE_SIZE,
		CURL_NOISE_SIZE,
		false,
		Image.FORMAT_RG8
	)
	for y in CURL_NOISE_SIZE:
		for x in CURL_NOISE_SIZE:
			var dx := (
				field.get_noise_2d(float(x + 1), float(y))
				- field.get_noise_2d(float(x - 1), float(y))
			) * 0.5
			var dy := (
				field.get_noise_2d(float(x), float(y + 1))
				- field.get_noise_2d(float(x), float(y - 1))
			) * 0.5
			var curl := Vector2(dy, -dx) * 6.0
			image.set_pixel(x, y, Color(
				clampf(curl.x * 0.5 + 0.5, 0.0, 1.0),
				clampf(curl.y * 0.5 + 0.5, 0.0, 1.0),
				0.0
			))
	return ImageTexture.create_from_image(image)


func _update_slab_bounds() -> void:
	if _slab == null or _material == null:
		return
	var center_y := (_cloud_top_y + _cloud_bottom_y) * 0.5
	_slab.position = Vector3(0.0, center_y, 0.0)
	_material.set_shader_parameter(
		"slab_min",
		Vector3(-SLAB_HALF_EXTENT, _cloud_bottom_y, -SLAB_HALF_EXTENT)
	)
	_material.set_shader_parameter(
		"slab_max",
		Vector3(SLAB_HALF_EXTENT, _cloud_top_y, SLAB_HALF_EXTENT)
	)


func _resolve_camera() -> void:
	if _camera != null and is_instance_valid(_camera):
		return
	_camera = get_viewport().get_camera_3d()
	if _camera != null:
		# The slab's far corners can exceed the old 90-unit clip at maximum
		# gameplay zoom. This only extends visibility; shadow coverage
		# remains independently bounded by LightingRig.
		_camera.far = maxf(_camera.far, 130.0)


func _on_lighting_changed(_profile) -> void:
	_refresh_palette_targets()


## The lighting rig pushes the sky colours actually being shown (anchors
## plus zenith) whenever the backdrop changes, including every frame of a
## time-of-day transition. The cloud palette regrades from them, so the
## sea can never drift out of the sky's light.
func set_sky_light(color0: Color, color1: Color, zenith: Color) -> void:
	_sky_color0 = color0
	_sky_color1 = color1
	_sky_zenith = zenith
	_sky_known = true
	_refresh_palette_targets()


func _refresh_palette_targets() -> void:
	var weather := "day"
	if _rig != null and _rig.has_method("weather_id"):
		weather = String(_rig.weather_id())
	var crown := base_crown
	var light := base_light
	var shade := base_shade
	var rim := base_rim
	var opacity := volume_opacity
	_target_rain_absorption = 0.0
	match weather:
		"rain":
			crown = crown.lerp(Color(0.70, 0.73, 0.78), 0.52)
			light = light.lerp(Color(0.59, 0.63, 0.70), 0.48)
			shade = shade.lerp(Color(0.38, 0.42, 0.52), 0.52)
			opacity = minf(1.0, volume_opacity + 0.04)
			# The talk darkens rain clouds by raising light absorption.
			_target_rain_absorption = 0.55
		"snow":
			crown = crown.lerp(Color(0.97, 0.98, 1.0), 0.42)
			light = light.lerp(Color(0.85, 0.89, 0.96), 0.30)
	# Grade the cotton palette by the sky's own light: keep most of the
	# sky's hue family and follow its luminance, so night clouds are dim
	# grey-blue shapes and sunset clouds catch the amber wash.
	var atmosphere := FALLBACK_ATMOSPHERE
	var grade := Color(1.0, 1.0, 1.0)
	var brightness := 1.0
	if _sky_known:
		var source := _sky_color1.lerp(_sky_zenith, 0.45)
		var luminance := (
			source.r * 0.2126
			+ source.g * 0.7152
			+ source.b * 0.0722
		)
		var safe_luminance := maxf(luminance, 0.02)
		var hue := Color(
			source.r / safe_luminance,
			source.g / safe_luminance,
			source.b / safe_luminance
		)
		# Dim skies keep almost none of their hue in the clouds: night
		# clouds should read as plain quiet grey, not warm smoke.
		hue = Color(1.0, 1.0, 1.0).lerp(
			hue,
			lerpf(0.22, 0.65, clampf(luminance, 0.0, 1.0))
		)
		# Floor keeps night clouds as faint moonlit shapes rather than
		# vanishing entirely into the dark.
		brightness = maxf(
			pow(clampf(luminance, 0.0, 1.25), 0.85),
			0.17
		)
		grade = Color(
			hue.r * brightness,
			hue.g * brightness,
			hue.b * brightness
		)
		atmosphere = _sky_color1
	_target_crown = crown * grade
	_target_light = light * grade
	_target_shade = shade * grade * 0.94
	_target_rim = rim * grade
	_target_atmosphere = atmosphere
	_target_opacity = opacity * lerpf(
		0.72,
		1.0,
		clampf(brightness, 0.0, 1.0)
	)
	if (
		_rig != null
		and _rig.has_method("shadow_ray_direction")
		and _material != null
	):
		_material.set_shader_parameter(
			"sun_direction",
			-_rig.shadow_ray_direction()
		)


func runtime_manifest() -> Dictionary:
	return {
		"implementation": "horizon_zero_dawn_raymarched_cloud_sea",
		"enabled": enabled,
		"world_space": true,
		"zoom_stable": true,
		"camera_composed": false,
		"screen_space_layers": 0,
		"sprites": 0,
		"cloud_image_textures": 0,
		"noise_sources": (
			"runtime-baked Perlin-Worley base, Worley erosion, curl"
			+ " turbulence (FastNoiseLite, no image assets)"
		),
		"runtime_baked_noise_textures": 4,
		"quality_level": quality_level,
		"layer_count": 1,
		"cloud_count": 1,
		"volume_count": 1,
		"raymarch_steps": _raymarch_steps,
		"light_samples": 6,
		"cloud_top_y": _cloud_top_y,
		"cloud_bottom_y": _cloud_bottom_y,
		"underside_y": _underside_y,
		"island_clearance": _underside_y - _cloud_top_y,
		"slab_half_extent": SLAB_HALF_EXTENT,
		"crown_tint": _current_crown,
		"shade_tint": _current_shade,
		"wind_speed": wind_speed,
		"wind_time": _wind_seconds,
		"camera_distance": _camera_distance,
		"volumetric_raymarch": true,
		"volumetric_fog_used": false,
	}
