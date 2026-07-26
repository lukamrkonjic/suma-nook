class_name VisualStyleProfile
extends Resource
## Data-driven lighting/atmosphere preset. The LightingRig applies one of these;
## gameplay scenes and the Match Lab share the same rig so every capture is
## calibrated identically. Shipped profiles: garden_galaxy_day (cream),
## garden_galaxy_mist (blue-gray gradient), garden_rain.

@export var profile_id := "garden_galaxy_day"
@export var background_color := Color(0.9137, 0.8863, 0.8118)
@export var ambient_color := Color(0.8471, 0.8157, 0.749)
@export var ambient_energy := 0.64

@export_group("Background gradient")
## When enabled the rig shows a screen-space vertical gradient (mist preset)
## behind the diorama instead of the flat background color.
@export var background_gradient := false
@export var gradient_top := Color(0.7059, 0.7765, 0.7725)
@export var gradient_mid := Color(0.7255, 0.8, 0.7765)
@export var gradient_bottom := Color(0.7333, 0.8157, 0.7922)
@export var stars_enabled := false

@export_group("Key light")
@export var sun_color := Color(1.0, 0.9451, 0.8235)
@export var sun_energy := 1.25
@export var sun_specular := 0.75
## Degrees. Pitch below horizon; yaw chosen so shadows fall to screen lower-right
## when the camera sits at its default 45° yaw.
@export var sun_pitch_deg := -58.0
@export var sun_yaw_deg := -85.0
@export var shadow_opacity := 0.58
@export var shadow_blur := 1.0
@export var sun_angular_distance := 2.5
@export var shadow_bias := 0.03
@export var shadow_normal_bias := 1.1

@export_group("Post")
@export var ssao_enabled := true
@export var ssao_intensity := 1.35
@export var ssao_radius := 0.5
@export var ssao_power := 1.25
@export var ssao_detail := 0.6
@export var ssao_horizon := 0.06
@export var ssao_sharpness := 0.9
@export var glow_enabled := false
@export var glow_intensity := 0.35
@export var glow_hdr_threshold := 1.6
@export var glow_bloom := 0.04
@export var exposure := 1.0
@export var contrast := 1.04
@export var saturation := 0.93
@export var fog_enabled := false
@export var fog_color := Color(0.9137, 0.8863, 0.8118)
@export var fog_density := 0.01

@export_group("Weather")
@export var rain_enabled := false
@export var local_light_multiplier := 1.0
