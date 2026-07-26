class_name VisualStyleProfile
extends Resource
## Data-driven lighting/atmosphere preset. The LightingRig applies one of these;
## gameplay scenes and the Match Lab share the same rig so every capture is
## calibrated identically. Shipped profiles: garden_galaxy_day (cream),
## garden_galaxy_mist (blue-gray gradient), garden_rain.

@export var profile_id := "garden_galaxy_day"
@export var background_color := Color(0.9176, 0.8941, 0.8157)
@export var ambient_color := Color(0.8667, 0.8471, 0.7961)
@export var ambient_energy := 0.78

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
@export var shadow_opacity := 0.34
@export var shadow_blur := 0.6
@export var sun_angular_distance := 4.0
@export var shadow_bias := 0.015
@export var shadow_normal_bias := 0.6

@export_group("Post")
@export var ssao_enabled := true
@export var ssao_intensity := 0.55
@export var ssao_radius := 0.3
@export var ssao_power := 1.0
@export var ssao_detail := 0.5
@export var ssao_horizon := 0.06
@export var ssao_sharpness := 0.9
@export var glow_enabled := false
@export var glow_intensity := 0.35
@export var glow_hdr_threshold := 1.6
@export var glow_bloom := 0.04
@export var exposure := 1.0
@export var contrast := 1.0
@export var saturation := 1.0
@export var fog_enabled := false
@export var fog_color := Color(0.9137, 0.8863, 0.8118)
@export var fog_density := 0.01

@export_group("Weather")
@export var rain_enabled := false
@export var local_light_multiplier := 1.0
