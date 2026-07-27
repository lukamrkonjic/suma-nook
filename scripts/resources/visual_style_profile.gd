class_name VisualStyleProfile
extends Resource
## Data-driven lighting/atmosphere preset. SumaSoftDaylight applies one of
## these; gameplay scenes and visual labs share the same rig so every capture
## is calibrated identically.

@export var profile_id := "garden_galaxy_day"
@export var background_color := Color(0.9176, 0.8941, 0.8157)
@export var ambient_color := Color(0.8667, 0.8471, 0.7961)
@export var ambient_energy := 0.78

@export_group("Ambient hemisphere")
## Uses a procedural sky as the diffuse/reflection source while keeping the
## camera backdrop independent. Upward faces receive a soft sky tint while
## downward faces receive warm ground bounce, like a miniature studio diorama.
@export var ambient_gradient_enabled := false
@export var ambient_sky_color := Color(0.8, 0.741, 0.769)
@export var ambient_equator_color := Color(0.651, 0.42, 0.373)
@export var ambient_ground_color := Color(0.859, 0.8, 0.722)

@export_group("Background gradient")
## When enabled the rig shows a screen-space vertical gradient (mist preset)
## behind the diorama instead of the flat background color.
@export var background_gradient := false
@export var gradient_top := Color(0.7059, 0.7765, 0.7725)
@export var gradient_mid := Color(0.7255, 0.8, 0.7765)
@export var gradient_bottom := Color(0.7333, 0.8157, 0.7922)
@export var stars_enabled := false

@export_group("Key light")
@export var sun_color := Color(1.0, 0.9608, 0.902)
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
@export var fog_color := Color(0.9137, 0.8863, 0.8118)
@export var fog_density := 0.01

@export_group("Reflection quality")
@export var reflection_probe_enabled := true
@export var reflection_probe_update_always := false
@export var reflection_probe_shadows := false

@export_group("Weather")
@export var rain_enabled := false
@export var motes_enabled := false
@export var leaves_enabled := false
@export var snow_enabled := false
@export var blossoms_enabled := false
@export var spores_enabled := false
@export var local_light_multiplier := 1.0
