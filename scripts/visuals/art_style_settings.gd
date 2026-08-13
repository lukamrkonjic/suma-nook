class_name ArtStyleSettings
extends RefCounted
## Single reversible switch for the complete world rendering direction.
##
## `data/art_styles.json` owns the checked-in default. A review run can try a
## different preset without editing any source by passing
## `--art-style=baseline` or setting `SUMA_ART_STYLE=baseline`.

const CONFIG_PATH := "res://data/art_styles.json"
const BASELINE_STYLE_ID := "baseline"

static var _config_cache: Dictionary = {}


static func active_style_id() -> String:
	var config := _config()
	var requested := _command_line_override()
	if requested.is_empty():
		requested = OS.get_environment("SUMA_ART_STYLE").strip_edges()
	if requested.is_empty():
		requested = String(config.get("active", BASELINE_STYLE_ID))
	var presets: Dictionary = config.get("presets", {})
	if not presets.has(requested):
		push_warning(
			"Unknown art style '%s'; falling back to '%s'."
			% [requested, BASELINE_STYLE_ID]
		)
		return BASELINE_STYLE_ID
	return requested


static func preset(requested_style_id := "") -> Dictionary:
	var style_id := requested_style_id.strip_edges()
	if style_id.is_empty():
		style_id = active_style_id()
	var presets: Dictionary = _config().get("presets", {})
	var resolved: Dictionary = presets.get(
		style_id,
		presets.get(BASELINE_STYLE_ID, {})
	)
	return resolved.duplicate(true)


static func visual_profile_path(requested_style_id := "") -> String:
	return String(
		preset(requested_style_id).get(
			"visual_profile",
			"res://assets/visual_profiles/garden_galaxy_exact.tres"
		)
	)


static func surface_mode(requested_style_id := "") -> String:
	return String(
		preset(requested_style_id).get("surface_mode", "baseline_pbr")
	)


static func palette_profile(requested_style_id := "") -> String:
	return String(preset(requested_style_id).get("palette_profile", "default"))


static func reset_cache_for_tests() -> void:
	_config_cache.clear()


static func _config() -> Dictionary:
	if not _config_cache.is_empty():
		return _config_cache
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(CONFIG_PATH)
	)
	if parsed is Dictionary:
		_config_cache = (parsed as Dictionary).duplicate(true)
	else:
		push_warning("Could not parse %s; using the baseline art style." % CONFIG_PATH)
		_config_cache = {
			"active": BASELINE_STYLE_ID,
			"presets": {
				BASELINE_STYLE_ID: {
					"surface_mode": "baseline_pbr",
					"visual_profile": (
						"res://assets/visual_profiles/garden_galaxy_exact.tres"
					),
				},
			},
		}
	return _config_cache


static func _command_line_override() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--art-style="):
			return argument.trim_prefix("--art-style=").strip_edges()
	return ""
