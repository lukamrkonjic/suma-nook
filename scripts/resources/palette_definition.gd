class_name PaletteDefinition
extends CozyPalette
## The one color design system for Suma Nook.
##
## All authored colors live in `assets/palettes/gg_material_palette.tres`:
##
## - `swatches` contains the deliberately small primitive palette, using
##   role-neutral `<hue-family>_<tone>` references from 050 light to 950 dark;
## - `colors` maps semantic material, UI, character, and VFX tokens to swatches;
## - `render_targets` contains calibrated screen-space targets;
## - `environment_profiles` contains every lighting/profile color;
## - `world_themes` contains time-of-day theme colors;
## - `schemes` contains reversible whole-game alterations.
##
## Callers request semantic tokens. They must not copy RGB values into scenes,
## scripts, shaders, or generated assets. This resource deliberately keeps
## source albedos separate from rendered targets: tune the source, measure the
## result, and never compensate by stacking unrelated color grading.

signal palette_changed(scheme_id: String)

const CANONICAL_PATH := "res://assets/palettes/gg_material_palette.tres"
const REFERENCE_FAMILIES := [
	"blue", "brown", "green", "neutral", "olive", "orange",
	"pink", "red", "sand", "teal", "violet", "yellow",
]
const REFERENCE_TONES := [
	50, 100, 150, 200, 250, 300, 350, 400, 450, 500,
	550, 600, 650, 700, 750, 800, 850, 900, 950,
]
const IDENTITY_ADJUSTMENTS := {
	"hue_shift_degrees": 0.0,
	"saturation_multiplier": 1.0,
	"value_multiplier": 1.0,
	"contrast": 1.0,
	"temperature": 0.0,
	"tint": 0.0,
	"alpha_multiplier": 1.0,
}

@export var render_targets: Dictionary = {}
@export var swatches: Dictionary = {}
@export var aliases: Dictionary = {}
@export var environment_profiles: Dictionary = {}
@export var world_themes: Dictionary = {}
@export var background_presets: Dictionary = {}
@export var schemes: Dictionary = {}
@export var token_domains: Dictionary = {}
@export var design_rules: Dictionary = {}
@export var character_swatch_groups: Dictionary = {}
@export var active_scheme := "default"

var _runtime_adjustments: Dictionary = {}
var _runtime_overrides: Dictionary = {}


static func shared() -> PaletteDefinition:
	return load(CANONICAL_PATH) as PaletteDefinition


func color(key: String, fallback := Color.MAGENTA) -> Color:
	var resolved := _resolve_alias(key)
	var source: Variant = _override_for(resolved)
	if not source is Color:
		source = _color_from_spec(colors.get(resolved), fallback)
	if not source is Color:
		return fallback
	return _apply_adjustments(source, domain_for(resolved))


func raw_color(key: String, fallback := Color.MAGENTA) -> Color:
	return _color_from_spec(colors.get(_resolve_alias(key)), fallback)


func has_color(key: String) -> bool:
	return colors.has(_resolve_alias(key))


func all_color_keys() -> PackedStringArray:
	var result := PackedStringArray()
	for key: String in colors:
		result.append(key)
	for key: String in aliases:
		if key not in result:
			result.append(key)
	return result


func character_swatches(group_id: String) -> PackedColorArray:
	var result := PackedColorArray()
	for swatch_id: String in character_swatch_groups.get(group_id, []):
		var source := _color_from_spec(swatch_id, Color.MAGENTA)
		result.append(_apply_adjustments(source, "character"))
	return result


func render_target(key: String) -> Color:
	return render_targets.get(_resolve_alias(key), Color.MAGENTA)


func environment_color(
	profile_id: String,
	role: String,
	fallback := Color.MAGENTA
) -> Color:
	var profile: Dictionary = environment_profiles.get("_defaults", {}).duplicate(true)
	profile.merge(environment_profiles.get(profile_id, {}), true)
	var value := _color_from_spec(profile.get(role), fallback)
	if value == fallback and not _is_color_spec(profile.get(role)):
		return fallback
	return _apply_adjustments(value, "environment")


func environment_profile(profile_id: String) -> Dictionary:
	var result: Dictionary = environment_profiles.get("_defaults", {}).duplicate(true)
	result.merge(environment_profiles.get(profile_id, {}), true)
	for role: String in result:
		if _is_color_spec(result[role]):
			result[role] = _apply_adjustments(
				_color_from_spec(result[role], Color.MAGENTA),
				"environment"
			)
	return result


func set_environment_color(profile_id: String, role: String, value: Color) -> void:
	if not environment_profiles.has(profile_id):
		environment_profiles[profile_id] = {}
	(environment_profiles[profile_id] as Dictionary)[role] = _store_authored_color(
		"environment_%s_%s" % [profile_id, role],
		value
	)
	palette_changed.emit(active_scheme)


func world_theme(theme_id: String) -> Dictionary:
	var result: Dictionary = world_themes.get(theme_id, {}).duplicate(true)
	for role: String in result:
		if _is_color_spec(result[role]):
			result[role] = _apply_adjustments(
				_color_from_spec(result[role], Color.MAGENTA),
				"environment"
			)
	return result


func background_preset(preset_id: String) -> Dictionary:
	var result: Dictionary = background_presets.get(preset_id, {}).duplicate(true)
	for role: String in result:
		if _is_color_spec(result[role]):
			result[role] = _apply_adjustments(
				_color_from_spec(result[role], Color.MAGENTA),
				"environment"
			)
	return result


func set_active_scheme(scheme_id: String) -> void:
	assert(schemes.has(scheme_id), "Unknown color scheme: %s" % scheme_id)
	if active_scheme == scheme_id:
		return
	active_scheme = scheme_id
	palette_changed.emit(active_scheme)


func set_runtime_adjustments(adjustments: Dictionary) -> void:
	_runtime_adjustments = adjustments.duplicate(true)
	palette_changed.emit(active_scheme)


func set_runtime_override(key: String, value: Color) -> void:
	_runtime_overrides[_resolve_alias(key)] = value
	palette_changed.emit(active_scheme)


func clear_runtime_alterations() -> void:
	_runtime_adjustments.clear()
	_runtime_overrides.clear()
	palette_changed.emit(active_scheme)


func domain_for(key: String) -> String:
	for prefix: String in token_domains:
		if key.begins_with(prefix):
			return String(token_domains[prefix])
	return "world"


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if swatches.size() > 128:
		errors.append("primitive swatch limit exceeded: %d/128" % swatches.size())
	for swatch_id: String in swatches:
		if not _is_reference_token_id(swatch_id):
			errors.append(
				"reference token '%s' must use <hue-family>_<tone>" % swatch_id
			)
		if not swatches[swatch_id] is Color:
			errors.append("swatch '%s' is not a Color" % swatch_id)
	for token: String in colors:
		_validate_color_spec(colors[token], "token '%s'" % token, errors)
	if not schemes.has("default"):
		errors.append("schemes.default is required")
	if not schemes.has(active_scheme):
		errors.append("active_scheme '%s' does not exist" % active_scheme)
	for alias: String in aliases:
		var target := String(aliases[alias])
		if not colors.has(target):
			errors.append("alias '%s' targets missing color '%s'" % [alias, target])
	for profile_id: String in environment_profiles:
		for role: String in environment_profiles[profile_id]:
			_validate_color_spec(
				environment_profiles[profile_id][role],
				"environment '%s.%s'" % [profile_id, role],
				errors
			)
	for theme_id: String in world_themes:
		for role: String in world_themes[theme_id]:
			var spec: Variant = world_themes[theme_id][role]
			if _is_color_spec(spec):
				_validate_color_spec(
					spec,
					"world theme '%s.%s'" % [theme_id, role],
					errors
				)
	for preset_id: String in background_presets:
		for role: String in background_presets[preset_id]:
			_validate_color_spec(
				background_presets[preset_id][role],
				"background '%s.%s'" % [preset_id, role],
				errors
			)
	for group_id: String in character_swatch_groups:
		for swatch_id: String in character_swatch_groups[group_id]:
			if not swatches.has(swatch_id):
				errors.append(
					"character group '%s' references missing swatch '%s'"
					% [group_id, swatch_id]
				)
	for scheme_id: String in schemes:
		var scheme: Dictionary = schemes[scheme_id]
		for token: String in scheme.get("overrides", {}):
			var target: Variant = scheme["overrides"][token]
			if target is String and not has_color(target):
				errors.append(
					"scheme '%s' override '%s' targets missing color '%s'"
					% [scheme_id, token, target]
				)
	return errors


func _resolve_alias(key: String) -> String:
	var resolved := key
	var visited := {}
	while aliases.has(resolved) and not visited.has(resolved):
		visited[resolved] = true
		resolved = String(aliases[resolved])
	return resolved


func _is_reference_token_id(reference_id: String) -> bool:
	var parts := reference_id.split("_")
	return (
		parts.size() == 2
		and parts[0] in REFERENCE_FAMILIES
		and parts[1].is_valid_int()
		and int(parts[1]) in REFERENCE_TONES
	)


func _override_for(key: String) -> Variant:
	if _runtime_overrides.has(key):
		return _runtime_overrides[key]
	var scheme: Dictionary = schemes.get(active_scheme, {})
	var value: Variant = scheme.get("overrides", {}).get(key)
	if value is String:
		var target := _resolve_alias(value)
		if colors.has(target):
			return _color_from_spec(colors[target], Color.MAGENTA)
		return _color_from_spec(value, Color.MAGENTA)
	return value


func _color_from_spec(spec: Variant, fallback: Color) -> Color:
	if spec is Color:
		return spec
	if spec is String:
		var swatch: Variant = swatches.get(String(spec))
		return swatch if swatch is Color else fallback
	if spec is Dictionary:
		var swatch: Variant = swatches.get(String(spec.get("swatch", "")))
		if not swatch is Color:
			return fallback
		var result: Color = swatch
		result.a = clampf(float(spec.get("alpha", result.a)), 0.0, 1.0)
		return result
	return fallback


func _is_color_spec(spec: Variant) -> bool:
	return (
		spec is Color
		or (spec is String and swatches.has(String(spec)))
		or (
			spec is Dictionary
			and swatches.has(String(spec.get("swatch", "")))
		)
	)


func _validate_color_spec(
	spec: Variant,
	context: String,
	errors: PackedStringArray
) -> void:
	if not _is_color_spec(spec):
		errors.append("%s has an invalid swatch reference" % context)


func _store_authored_color(suggested_id: String, value: Color) -> Variant:
	var nearest_id := ""
	var nearest_distance := INF
	for swatch_id: String in swatches:
		var candidate: Color = swatches[swatch_id]
		var distance := Vector3(
			candidate.r - value.r,
			candidate.g - value.g,
			candidate.b - value.b
		).length_squared()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = swatch_id
	if nearest_distance > 0.0000001 and swatches.size() < 128:
		nearest_id = suggested_id.validate_node_name().to_snake_case()
		var suffix := 2
		while swatches.has(nearest_id):
			nearest_id = "%s_%d" % [suggested_id, suffix]
			suffix += 1
		var opaque := value
		opaque.a = 1.0
		swatches[nearest_id] = opaque
	elif nearest_distance > 0.0000001:
		push_warning(
			"Color swatch limit reached; '%s' was mapped to nearest swatch '%s'."
			% [suggested_id, nearest_id]
		)
	if is_equal_approx(value.a, 1.0):
		return nearest_id
	return {"swatch": nearest_id, "alpha": value.a}


func _adjustments_for(domain: String) -> Dictionary:
	var result := IDENTITY_ADJUSTMENTS.duplicate()
	var scheme: Dictionary = schemes.get(active_scheme, {})
	result.merge(scheme.get("global", {}), true)
	result.merge(scheme.get("domains", {}).get(domain, {}), true)
	result.merge(_runtime_adjustments.get("global", {}), true)
	result.merge(_runtime_adjustments.get("domains", {}).get(domain, {}), true)
	return result


func _apply_adjustments(source: Color, domain: String) -> Color:
	var adjustment := _adjustments_for(domain)
	var hue := wrapf(
		source.h + float(adjustment["hue_shift_degrees"]) / 360.0,
		0.0,
		1.0
	)
	var saturation := maxf(
		0.0,
		source.s * float(adjustment["saturation_multiplier"])
	)
	var value := maxf(
		0.0,
		source.v * float(adjustment["value_multiplier"])
	)
	var result := Color.from_hsv(hue, saturation, value, source.a)
	var contrast := float(adjustment["contrast"])
	result.r = maxf(0.0, (result.r - 0.5) * contrast + 0.5)
	result.g = maxf(0.0, (result.g - 0.5) * contrast + 0.5)
	result.b = maxf(0.0, (result.b - 0.5) * contrast + 0.5)
	var temperature := float(adjustment["temperature"])
	var tint := float(adjustment["tint"])
	result.r = maxf(0.0, result.r + temperature * 0.08 + tint * 0.03)
	result.g = maxf(0.0, result.g - tint * 0.06)
	result.b = maxf(0.0, result.b - temperature * 0.08 + tint * 0.03)
	result.a = clampf(
		source.a * float(adjustment["alpha_multiplier"]),
		0.0,
		1.0
	)
	return result
