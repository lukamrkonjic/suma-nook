extends Node
## Runtime contract test for the single-file color design system.

var _failures := 0


func _ready() -> void:
	var palette := PaletteDefinition.shared()
	_expect(palette != null, "canonical palette loads as PaletteDefinition")
	if palette == null:
		get_tree().quit(1)
		return
	_expect(palette.validate().is_empty(), "palette metadata validates")
	_expect(palette.swatches.size() == 128, "palette uses exactly 128 reference tokens")
	_expect(palette.swatches.size() <= 128, "reference palette stays within its hard cap")
	_expect(palette.colors.size() == 435, "palette has all 435 canonical semantic colors")
	_expect(palette.all_color_keys().size() == 440, "five aliases complete the named palette")
	_expect(
		palette.render_targets.size() == palette.colors.size(),
		"every canonical semantic color has a screen target"
	)
	_expect(palette.has_color("ui_text"), "aliases resolve to canonical tokens")
	_expect(
		palette.raw_color("warm_white").is_equal_approx(
			Color(0.886, 0.854, 0.744, 1.0)
		),
		"game-ready semantic source values load exactly"
	)
	_expect(
		palette.render_target("warm_white").is_equal_approx(
			Color(0.9686, 0.9412, 0.8471, 1.0)
		),
		"screen-space target values load exactly"
	)
	_expect(
		palette.active_scheme == "earthwood_cozy"
		and palette.schemes["earthwood_cozy"]["overrides"].size()
		== palette.colors.size(),
		"active production scheme explicitly covers every semantic role"
	)
	_expect(
		palette.color("background_day").is_equal_approx(
			Color(0.658824, 0.647059, 0.552941, 1.0)
		)
		and palette.color("grass_primary").is_equal_approx(
			Color(0.435294, 0.470588, 0.27451, 1.0)
		)
		and palette.color("pine_deep").is_equal_approx(
			Color(0.129412, 0.239216, 0.196078, 1.0)
		)
		and palette.color("earth_primary").is_equal_approx(
			Color(0.435294, 0.301961, 0.27451, 1.0)
		),
		"earthwood anchors preserve atmosphere, grass, forest, and clay separation"
	)
	_expect(
		palette.character_swatches("skin").size()
		== palette.character_swatch_groups.get("skin", []).size(),
		"character swatches resolve through scheme adjustments"
	)

	palette.clear_runtime_alterations()
	palette.set_active_scheme("default")
	var calibrated := palette.color("grass_primary")
	palette.set_active_scheme("warm")
	_expect(
		not palette.color("grass_primary").is_equal_approx(calibrated),
		"whole-game schemes transform semantic colors"
	)
	palette.set_active_scheme("deuteranopia_safe")
	_expect(
		palette.color("ui_good").is_equal_approx(palette.color("ui_info"))
		and palette.color("ui_bad").is_equal_approx(
			palette.color("terracotta_orange")
		),
		"scheme token overrides resolve"
	)
	palette.set_active_scheme("default")
	palette.set_runtime_override("grass_primary", palette.color("ui_info"))
	_expect(
		palette.color("grass_primary").is_equal_approx(palette.color("ui_info")),
		"runtime token override applies"
	)
	palette.clear_runtime_alterations()

	var profile: VisualStyleProfile = load(
		"res://assets/visual_profiles/garden_galaxy_exact.tres"
	)
	profile.apply_color_design_system(palette)
	_expect(
		profile.background_color.is_equal_approx(
			palette.environment_color(profile.profile_id, "background_color")
		),
		"visual profiles resolve environment colors from the canonical file"
	)

	if _failures == 0:
		print("COLOR DESIGN SYSTEM TEST PASS")
	else:
		push_error("COLOR DESIGN SYSTEM TEST FAIL: %d issue(s)" % _failures)
	get_tree().quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
		return
	_failures += 1
	push_error("FAIL: " + message)
