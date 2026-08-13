extends Node
## Standalone contract for the reversible art-direction seam. Run this before
## visual captures so a future preset cannot silently delete the baseline.

var _failures := 0


func _ready() -> void:
	var active_id := ArtStyleSettings.active_style_id()
	_check(
		active_id == "garden_galaxy_reference",
		"checked-in default selects the evidence-driven GG reconstruction"
	)
	_check(
		ArtStyleSettings.surface_mode() == "garden_galaxy_reference_pbr",
		"reference preset selects the Standard/PBR surface path"
	)
	_check(
		ArtStyleSettings.palette_profile() == "garden_galaxy_reference",
		"reference preset selects its measured source-albedo palette"
	)
	var active_profile_path := ArtStyleSettings.visual_profile_path()
	var active_profile := load(active_profile_path) as VisualStyleProfile
	_check(
		active_profile != null
			and active_profile.profile_id == "garden_galaxy_reference",
		"reference preset resolves its audited lighting profile"
	)
	_check(
		active_profile.shadow_opacity == 1.0
			and active_profile.shadow_blur == 0.6
			and active_profile.sun_angular_distance == 0.0
			and active_profile.shadow_bias == 0.02
			and active_profile.shadow_normal_bias == 1.0,
		"reference profile restores the crisp-studio point-sun shadow contract"
	)
	_check(
		active_profile.ssao_enabled
			and active_profile.ssao_intensity == 2.0
			and active_profile.ssao_sharpness == 0.98,
		"reference profile restores the old high-definition contact AO"
	)
	_check(
		active_profile.gg_pipeline_enabled
			and active_profile.grade_contrast == 35.0
			and active_profile.glow_hdr_threshold == 1.24,
		"reference profile keeps the PPv2 camera grade and bounded bloom"
	)
	_check(
		not active_profile.reflection_probe_enabled,
		"crisp-studio profile avoids the later reflection haze"
	)
	_check(
		int(ProjectSettings.get_setting(
			"rendering/lights_and_shadows/directional_shadow/size"
		)) == 8192
			and int(ProjectSettings.get_setting(
				"rendering/anti_aliasing/quality/msaa_3d"
			)) == 3,
		"graphics-lab startup settings retain the 8192 atlas and 8x MSAA"
	)

	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var cream := palette.color("warm_white")
	var expected_grass := Color("#586c49").lerp(cream, 0.14)
	var expected_wood := Color("#704e28").lerp(cream, 0.1)
	var expected_stone := Color("#aba9a2").lerp(cream, 0.06)
	var restored := MaterialLibrary.new(palette, "garden_galaxy_reference")
	var grass := restored.material("grass") as ShaderMaterial
	var field_grass := restored.material(
		"grass_field_surface_primary"
	) as ShaderMaterial
	var wood := restored.material("wood") as ShaderMaterial
	var stone := restored.material("stone_highlight") as ShaderMaterial
	var tinted_skin := restored.tinted("skin", Color("#b96f4d"))
	for material_instance: Material in [
		grass,
		field_grass,
		wood,
		stone,
		tinted_skin,
	]:
		_check(
			material_instance is ShaderMaterial
				and (material_instance as ShaderMaterial).shader.resource_path.ends_with(
					"gg_prop_surface.gdshader"
				),
			"ordinary and tinted materials recreate GG texture variation before PBR lighting"
		)
	_check(
		(grass.get_shader_parameter("albedo") as Color).is_equal_approx(
			expected_grass
		)
			and is_equal_approx(
				float(grass.get_shader_parameter("roughness_val")),
				0.74
			),
		"grass uses the crisp-studio foliage response and restrained sage source"
	)
	_check(
		(field_grass.get_shader_parameter("albedo") as Color).is_equal_approx(
			expected_grass
		),
		"the current v3 grass field cannot bypass the reference palette"
	)
	_check(
		(wood.get_shader_parameter("albedo") as Color).is_equal_approx(
			expected_wood
		)
			and is_equal_approx(
				float(wood.get_shader_parameter("roughness_val")),
				0.72
			),
		"wood uses the early Suma source albedo that resolves to the GG screen target"
	)
	_check(
		(stone.get_shader_parameter("albedo") as Color).is_equal_approx(
			expected_stone
		),
		"stone uses the original reconstruction's warm neutral family"
	)
	var water := restored.material("water") as ShaderMaterial
	_check(
		is_equal_approx(float(water.get_shader_parameter("foam_width")), 0.13)
			and is_equal_approx(
				float(water.get_shader_parameter("water_roughness")),
				0.42
			),
		"water keeps the reference-derived jello-block tuning"
	)
	var snow := restored.material("snow_top") as ShaderMaterial
	_check(
			snow.shader.resource_path.ends_with("gg_soft_terrain.gdshader")
			and (snow.get_shader_parameter("albedo") as Color).is_equal_approx(
				Color("#bbc4c4")
			),
		"responsive snow keeps footprints with a bounded GG blue-white albedo"
	)

	var baseline := MaterialLibrary.new(palette, "baseline")
	_check(
		baseline.material("grass") is StandardMaterial3D,
		"baseline still resolves the original StandardMaterial3D path"
	)
	_check(
		ArtStyleSettings.visual_profile_path("baseline").ends_with(
			"garden_galaxy_exact.tres"
		),
		"baseline still resolves the prior daylight profile"
	)

	if _failures == 0:
		print("ART STYLE PRESET CONTRACT: 22 checks passed")
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  [ok] %s" % message)
		return
	_failures += 1
	push_error("[art style contract] %s" % message)
