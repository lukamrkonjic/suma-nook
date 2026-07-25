class_name VisualStyleProfile
extends Resource
## Data-driven lighting/atmosphere preset. The LightingRig applies one of these;
## gameplay scenes and the Style Lab share the same rig so every capture is
## calibrated identically. Two shipped profiles: garden_day, garden_rain.

@export var profile_id := "garden_day"
@export var background_color := Color(0.906, 0.882, 0.8)
@export var ambient_color := Color(0.93, 0.89, 0.8)
@export var ambient_energy := 0.7

@export_group("Key light")
@export var sun_color := Color(1.0, 0.96, 0.86)
@export var sun_energy := 1.25
## Degrees. Pitch below horizon; yaw chosen so shadows fall to screen lower-right
## when the camera sits at its default 45° yaw.
@export var sun_pitch_deg := -52.0
@export var sun_yaw_deg := -35.0
@export var shadow_opacity := 0.72
@export var shadow_blur := 1.6

@export_group("Post")
@export var ssao_enabled := true
@export var ssao_intensity := 1.4
@export var ssao_radius := 0.7
@export var glow_enabled := true
@export var glow_intensity := 0.45
@export var glow_hdr_threshold := 1.35
@export var exposure := 1.0
@export var fog_enabled := false
@export var fog_color := Color(0.906, 0.882, 0.8)
@export var fog_density := 0.01

@export_group("Weather")
@export var rain_enabled := false
@export var local_light_multiplier := 1.0
