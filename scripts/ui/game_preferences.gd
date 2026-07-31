class_name GamePreferences
extends RefCounted
## Small, save-backed set of player-facing options. The values live inside the
## normal game save so Save & Exit is sufficient to preserve them.

const AA_OFF := "off"
const AA_BALANCED := "balanced"
const AA_HIGH := "high"

## "Pixel size" dropdown labels, mirroring Imota's setting: the index maps
## onto PixelLook.PIXEL_LEVELS (keep both the same length).
const PIXEL_SIZE_OPTIONS := [
	"Off — crisp render",
	"Fine",
	"Medium",
	"Chunky",
	"Chunkier",
	"Very chunky",
	"Chunkiest",
]

var fullscreen := true
var vsync := true
var anti_aliasing := AA_BALANCED
var ssao := true
var bloom := true
var master_volume := 0.63
var music_volume := 0.4
var tutorial_hints := true
var pixel_size := 0
var pixel_cel := false


func from_dict(data: Dictionary) -> void:
	fullscreen = bool(data.get("fullscreen", fullscreen))
	vsync = bool(data.get("vsync", vsync))
	var requested_aa := String(data.get("anti_aliasing", anti_aliasing))
	anti_aliasing = requested_aa if requested_aa in [AA_OFF, AA_BALANCED, AA_HIGH] else AA_BALANCED
	ssao = bool(data.get("ssao", ssao))
	bloom = bool(data.get("bloom", bloom))
	master_volume = clampf(float(data.get("master_volume", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(data.get("music_volume", music_volume)), 0.0, 1.0)
	tutorial_hints = bool(data.get("tutorial_hints", tutorial_hints))
	pixel_size = clampi(int(data.get("pixel_size", pixel_size)), 0, PIXEL_SIZE_OPTIONS.size() - 1)
	pixel_cel = bool(data.get("pixel_cel", pixel_cel))


func to_dict() -> Dictionary:
	return {
		"fullscreen": fullscreen,
		"vsync": vsync,
		"anti_aliasing": anti_aliasing,
		"ssao": ssao,
		"bloom": bloom,
		"master_volume": master_volume,
		"music_volume": music_volume,
		"tutorial_hints": tutorial_hints,
		"pixel_size": pixel_size,
		"pixel_cel": pixel_cel,
	}


func apply(
	viewport: Viewport,
	lighting: LightingRig,
	hud: Hud,
	pixel_look: PixelLook = null
) -> void:
	if DisplayServer.get_name() != "headless":
		var command_line := OS.get_cmdline_args()
		var user_command_line := OS.get_cmdline_user_args()
		var force_windowed := (
			"--windowed" in command_line
			or "--force-windowed" in user_command_line
		)
		var force_fullscreen := "--fullscreen" in command_line
		var use_fullscreen := fullscreen
		if force_windowed:
			use_fullscreen = false
		elif force_fullscreen:
			use_fullscreen = true
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if use_fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED
		)
		DisplayServer.window_set_flag(
			DisplayServer.WINDOW_FLAG_BORDERLESS,
			use_fullscreen
		)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
		)
	match anti_aliasing:
		AA_OFF:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.use_taa = false
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		AA_BALANCED:
			viewport.msaa_3d = Viewport.MSAA_4X
			viewport.use_taa = false
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		_:
			viewport.msaa_3d = Viewport.MSAA_8X
			# Preserve the crisp hard-edged miniature silhouette. Temporal AA
			# softened face boundaries and introduced visible surface banding.
			viewport.use_taa = false
			# A single non-temporal FXAA pass cleans up residual shadow-map
			# stipple without the motion trails or surface wash of TAA.
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	if lighting != null:
		lighting.set_user_post_effects(ssao, bloom)
	if hud != null:
		hud.set_tutorial_enabled(tutorial_hints)
	if pixel_look != null:
		pixel_look.apply(pixel_size, pixel_cel)


func _set_bus_volume(bus_name: String, value: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(value, 0.001)))
