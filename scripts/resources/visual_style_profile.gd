class_name VisualStyleProfile
extends Resource
## Data-driven lighting/atmosphere preset. SumaSoftDaylight applies one of
## these; gameplay scenes and visual labs share the same rig so every capture
## is calibrated identically. Color values are intentionally not serialized
## here: every profile color resolves from the canonical PaletteDefinition.

const COLOR_PROPERTIES := [
	"background_color",
	"ambient_color",
	"ambient_sky_color",
	"ambient_equator_color",
	"ambient_ground_color",
	"gradient_top",
	"gradient_mid",
	"gradient_bottom",
	"sun_color",
	"fog_color",
	"bg_color0",
	"bg_color1",
	"night_bg_multiply",
	"night_ambient_tint",
	"night_light_color",
]

var _applying_design_system := false
var _color_overrides: Dictionary = {}
var _resolved_profile_id := ""

@export var profile_id := "garden_galaxy_day"
var background_color := Color.MAGENTA:
	set(value):
		background_color = value
		_track_color_override("background_color", value)
var ambient_color := Color.MAGENTA:
	set(value):
		ambient_color = value
		_track_color_override("ambient_color", value)
@export var ambient_energy := 0.78

@export_group("Ambient hemisphere")
## Uses a procedural sky as the diffuse/reflection source while keeping the
## camera backdrop independent. Upward faces receive a soft sky tint while
## downward faces receive warm ground bounce, like a miniature studio diorama.
@export var ambient_gradient_enabled := false
var ambient_sky_color := Color.MAGENTA:
	set(value):
		ambient_sky_color = value
		_track_color_override("ambient_sky_color", value)
var ambient_equator_color := Color.MAGENTA:
	set(value):
		ambient_equator_color = value
		_track_color_override("ambient_equator_color", value)
var ambient_ground_color := Color.MAGENTA:
	set(value):
		ambient_ground_color = value
		_track_color_override("ambient_ground_color", value)

@export_group("Background backdrop")
## Legacy profiles retain three colour anchors for lighting compatibility.
## The rig renders their middle hue as one flat screen-space backdrop.
@export var background_gradient := false
var gradient_top := Color.MAGENTA:
	set(value):
		gradient_top = value
		_track_color_override("gradient_top", value)
var gradient_mid := Color.MAGENTA:
	set(value):
		gradient_mid = value
		_track_color_override("gradient_mid", value)
var gradient_bottom := Color.MAGENTA:
	set(value):
		gradient_bottom = value
		_track_color_override("gradient_bottom", value)
@export var stars_enabled := false

@export_group("Key light")
var sun_color := Color.MAGENTA:
	set(value):
		sun_color = value
		_track_color_override("sun_color", value)
@export var sun_energy := 0.95
@export var sun_specular := 0.55
## Degrees. Pitch below horizon; yaw chosen so shadows fall to screen lower-right
## when the camera sits at its default 45° yaw.
@export var sun_pitch_deg := -58.0
@export var sun_yaw_deg := -65.0
@export var shadow_max_distance := 100.0
@export var shadow_opacity := 0.34
@export var shadow_blur := 1.2
## Keep at or below ~1.0. Godot's PCSS blocker search (driven by this value)
## dithers into a visible cross-hatch on smooth curved surfaces such as
## foliage — measured in docs/visual_rework/SMOOTHNESS_AUDIT.md. Softness
## comes from shadow_blur instead.
@export var sun_angular_distance := 1.0
@export var shadow_bias := 0.015
@export var shadow_normal_bias := 1.2
## "orthogonal", "pssm_2", or "pssm_4". Two blended splits are the default
## miniature-quality balance; the close split keeps character contact shadows
## crisp without spending the entire map on the far camera envelope.
@export var shadow_cascade_mode := "pssm_2"
@export var shadow_split_1 := 0.35
@export var shadow_split_2 := 0.65
@export var shadow_split_3 := 0.85
@export var shadow_blend_splits := true

@export_group("Post")
@export var ssao_enabled := true
@export var ssao_intensity := 0.55
@export var ssao_radius := 0.3
@export var ssao_power := 1.0
@export var ssao_detail := 0.5
@export var ssao_horizon := 0.06
@export var ssao_sharpness := 0.9
@export var ssil_enabled := false
@export var ssil_intensity := 0.25
@export var ssil_radius := 0.4
@export var ssil_sharpness := 0.85
@export var ssr_enabled := false
@export var glow_enabled := false
@export var glow_intensity := 0.35
@export var glow_hdr_threshold := 1.6
@export var glow_bloom := 0.04
@export var exposure := 1.0
## "linear" during raw calibration; "agx" is the soft-daylight shipping path.
@export var tonemap := "agx"
@export var agx_white := 14.0
@export var agx_contrast := 1.08
@export var brightness := 1.0
@export var contrast := 1.0
@export var saturation := 1.0
@export var fog_enabled := false
var fog_color := Color.MAGENTA:
	set(value):
		fog_color = value
		_track_color_override("fog_color", value)
@export var fog_density := 0.01

@export_group("Localized ground fog")
## These drive the full-resolution world-space mist layers. fog_density above
## is retained only for old profile compatibility; traditional full-screen
## fog stays disabled, while volumetric froxel fog is owned entirely by the
## void-cloud system's localized FogVolume (zero global density).
@export var ground_fog_density := 0.0
@export var ground_fog_height := 1.65
@export var ground_fog_noise_scale := 0.11
@export var ground_fog_wind := Vector2(0.025, -0.018)
@export var ground_fog_disturbance_radius := 0.78
@export var ground_fog_close_seconds := 1.8

@export_group("Reflection quality")
@export var reflection_probe_enabled := true
@export var reflection_probe_update_always := false
@export var reflection_probe_shadows := false

@export_group("GG exact pipeline")
## Switches the rig onto the Garden Galaxy reference pipeline: LINEAR env
## tonemap plus a screen-space grade pass that reproduces Unity PPv2's
## PP_MainCamera profile (postExposure -> LogC contrast -> LMS white balance
## -> saturation -> Neutral tonemap). Serialized reference values are the
## defaults below.
@export var gg_pipeline_enabled := false
@export var grade_post_exposure_ev := 0.3
@export var grade_temperature := 10.0
@export var grade_tint := -7.0
@export var grade_saturation := 6.0
@export var grade_contrast := 35.0
## "neutral" or "none".
@export var grade_tonemapper := "neutral"
## Screen-space Garden Galaxy backdrop. The time-of-day theme still provides
## its authored anchors; the rig selects the lightest as one flat colour and
## keeps the sparse sparkle field above it.
@export var background_gg_gradient := false
var bg_color0 := Color.MAGENTA:
	set(value):
		bg_color0 = value
		_track_color_override("bg_color0", value)
var bg_color1 := Color.MAGENTA:
	set(value):
		bg_color1 = value
		_track_color_override("bg_color1", value)
@export var bg_sparkles_enabled := true
## Theme Default dark-mode constants (WorldTheme.Calculate): background is
## multiplied by night_bg_multiply, ambient/sky by night_ambient_tint, the sun
## lerps to night_light_color and min_light_intensity, and the sun pitch
## lerps from day toward sun_pitch_night_deg.
var night_bg_multiply := Color.MAGENTA:
	set(value):
		night_bg_multiply = value
		_track_color_override("night_bg_multiply", value)
var night_ambient_tint := Color.MAGENTA:
	set(value):
		night_ambient_tint = value
		_track_color_override("night_ambient_tint", value)
var night_light_color := Color.MAGENTA:
	set(value):
		night_light_color = value
		_track_color_override("night_light_color", value)
@export var min_light_intensity := 0.8
@export var sun_pitch_night_deg := -50.0
## PPv2 forward-path AO multiplies the whole lit image, not just ambient.
@export var ssao_light_affect := 0.0

@export_group("Weather")
@export var rain_enabled := false
## Fixed-budget world-space rain surface. These affect one shared overlay and
## one player-foot emitter, never individual tiles.
@export var rain_surface_wetness := 0.0
@export var rain_puddle_amount := 0.0
@export var rain_ripple_amount := 0.0
@export var rain_walk_splash_amount := 0.0
@export var motes_enabled := false
@export var leaves_enabled := false
@export var snow_enabled := false
@export var blossoms_enabled := false
@export var spores_enabled := false
@export var local_light_multiplier := 1.0


func apply_color_design_system(
	palette: PaletteDefinition,
	force := false
) -> void:
	if palette == null:
		return
	if _resolved_profile_id == profile_id and not force:
		return
	var resolved := palette.environment_profile(profile_id)
	_applying_design_system = true
	for field: String in COLOR_PROPERTIES:
		if _color_overrides.has(field) and not force:
			continue
		if resolved.has(field):
			set(field, resolved[field])
	_applying_design_system = false
	_resolved_profile_id = profile_id


func commit_color_design_system(palette: PaletteDefinition) -> void:
	if palette == null:
		return
	for field: String in COLOR_PROPERTIES:
		palette.set_environment_color(profile_id, field, get(field))
	_color_overrides.clear()
	_resolved_profile_id = profile_id


func invalidate_color_design_system() -> void:
	_resolved_profile_id = ""


func _track_color_override(field: String, value: Color) -> void:
	if not _applying_design_system:
		_color_overrides[field] = value
