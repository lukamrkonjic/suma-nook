class_name MaterialLibrary
extends RefCounted
## One shared StandardMaterial3D per palette key. GLB assets ship with semantic
## material names ("grass", "wood", ...); rebind_materials() swaps every surface
## to the shared library instance, so a palette edit re-skins the whole game
## without touching a single GLB.
##
## Calibration baseline: ordinary matte materials, no custom shaders, no
## orientation tint, no baked sunlight. The DirectionalLight3D does the shading.

const WATER_SHADER: Shader = preload("res://assets/materials/reworked/gg_water.gdshader")
const UNDERWATER_SHADER: Shader = preload("res://assets/materials/reworked/gg_underwater.gdshader")
const FLORA_SHADER: Shader = preload("res://assets/materials/reworked/gg_uw_flora.gdshader")
const SURFACE_SHADER: Shader = preload("res://assets/materials/reworked/gg_prop_surface.gdshader")
const SOFT_TERRAIN_SHADER: Shader = preload(
	"res://assets/materials/reworked/gg_soft_terrain.gdshader"
)
const ArtStyleSettingsScript := preload(
	"res://scripts/visuals/art_style_settings.gd"
)
const SOFT_TERRAIN_IMPRINT_COUNT := 12
const SOFT_TERRAIN_PARAMETERS := {
	"sand_top": {
		"profile": "sand",
		"terrain_lifetime": 6.5,
		"terrain_depth": 0.045,
		"terrain_radius": 0.22,
		"terrain_rim_height": 0.006,
	},
	"snow_top": {
		"profile": "snow",
		"terrain_lifetime": 13.5,
		"terrain_depth": 0.062,
		"terrain_radius": 0.225,
		"terrain_rim_height": 0.012,
	},
}
## GG-style baked-shading emulation shared by every opaque surface material.
const SURFACE_RAMP := {
	"ramp_height": 1.35,
	"ramp_top_lift": 0.0,
	"ramp_bottom_drop": 0.0,
	"mottle_amount": 0.0,
}
const STYLE_DATA_PATH := "res://data/material_styles.json"
const GARDEN_GALAXY_PALETTE_PATH := (
	"res://data/garden_galaxy_reference_palette.json"
)
const WATER_PARAMETERS := {
	"wave_height": 0.032,
	"wave_speed": 0.72,
	"surface_shimmer": 0.08,
	"depth_falloff": 0.62,
	"shallow_alpha": 0.8,
	"deep_alpha": 0.97,
	"foam_width": 0.022,
	"water_roughness": 0.18,
	"water_specular": 0.56,
	"scene_lighting_response": 1.0,
	"fresnel_strength": 0.52,
	"water_level": -0.14,
	"side_opacity": 1.0,
}
## Frozen July 28 Garden Galaxy reconstruction values from commit 3e271add.
## The active style selects this period response without disturbing the later
## baseline water tuning.
const GARDEN_GALAXY_WATER_PARAMETERS := {
	"wave_height": 0.048,
	"wave_speed": 1.08,
	"surface_shimmer": 0.16,
	"depth_falloff": 0.5,
	"shallow_alpha": 0.8,
	"deep_alpha": 0.97,
	"foam_width": 0.13,
	"water_roughness": 0.42,
	"water_specular": 0.18,
	"scene_lighting_response": 1.0,
	"fresnel_strength": 0.22,
	"water_level": -0.14,
	"side_opacity": 0.88,
}
const UNDERWATER_PARAMETERS := {
	"water_level": -0.14,
	"caustic_strength": 0.58,
	"depth_fade": 1.0,
	"roughness": 0.9,
	"specular": 0.12,
}
const FLORA_PARAMETERS := {
	"water_level": -0.14,
	"sway_strength": 0.06,
	"sway_speed": 1.1,
	"depth_fade": 1.0,
	"roughness": 0.9,
	"specular": 0.12,
}

const EMISSIVE := {"fire_core": 5.0, "fire_yellow": 3.0, "fire_orange": 2.2, "fire_outer": 2.5, "magic": 2.0, "crystal": 1.0}
## Restrained warm metals — never glossy plastic, never mirror black.
const METALS := {
	"gold": {"metallic": 0.3, "roughness": 0.65},
	"gold_primary": {"metallic": 0.3, "roughness": 0.65},
	"gold_deep": {"metallic": 0.25, "roughness": 0.68},
	"metal": {"metallic": 0.25, "roughness": 0.72},
}

var palette: CozyPalette
var _materials: Dictionary = {}
var _style_data: Dictionary = {}
var _garden_galaxy_palette: Dictionary = {}
var _art_style_id := "baseline"
var _art_style: Dictionary = {}


func _init(pal: CozyPalette, requested_art_style := "") -> void:
	palette = pal
	_style_data = JSON.parse_string(FileAccess.get_file_as_string(STYLE_DATA_PATH))
	_garden_galaxy_palette = JSON.parse_string(
		FileAccess.get_file_as_string(GARDEN_GALAXY_PALETTE_PATH)
	)
	_art_style_id = (
		ArtStyleSettingsScript.active_style_id()
		if requested_art_style.is_empty()
		else requested_art_style
	)
	_art_style = ArtStyleSettingsScript.preset(_art_style_id)
	if palette is PaletteDefinition:
		(palette as PaletteDefinition).palette_changed.connect(
			_on_palette_changed
		)


func material(key: String) -> Material:
	if _materials.has(key):
		return _materials[key]
	if key == "water":
		return _cache(key, _water_material())
	if key.begins_with("uw_flora"):
		return _cache(key, _flora_material(key))
	if key.begins_with("uw_"):
		return _cache(key, _underwater_material(key))
	if not _has_palette_color(key):
		return _fallback()
	var style := _active_style_parameters(key, material_parameters(key))
	var emission_energy := (
		float(style.get("emission_energy", EMISSIVE.get(key, 0.0)))
		* float(_art_style.get("emission_scale", 1.0))
	)
	var alpha := float(style.get("alpha", 1.0))
	# Deformable sand/snow retain their fixed-budget imprint shader. The
	# Reference materials stay colour-clean. Broad form shading comes from the
	# light and smoothed normals; imported surface dirt must never be replaced by
	# procedural dirt. Soft terrain keeps its dedicated interaction shader.
	if (
		emission_energy <= 0.0
		and alpha >= 1.0
		and SOFT_TERRAIN_PARAMETERS.has(key)
	):
		var surface := ShaderMaterial.new()
		surface.resource_name = key
		surface.shader = (
			SOFT_TERRAIN_SHADER
			if SOFT_TERRAIN_PARAMETERS.has(key)
			else SURFACE_SHADER
		)
		surface.set_shader_parameter("albedo", _styled_albedo(key, palette.color(key), style))
		surface.set_shader_parameter("roughness_val", float(style["roughness"]))
		surface.set_shader_parameter("metallic_val", float(style["metallic"]))
		surface.set_shader_parameter("specular_val", float(style["specular"]))
		var ramp_parameters := _surface_ramp_parameters()
		for parameter in ramp_parameters:
			surface.set_shader_parameter(parameter, ramp_parameters[parameter])
		if SOFT_TERRAIN_PARAMETERS.has(key):
			_configure_soft_terrain_material(
				surface,
				key,
				SOFT_TERRAIN_PARAMETERS[key]
			)
		_materials[key] = surface
		return surface
	if (
		emission_energy <= 0.0
		and alpha >= 1.0
		and String(_art_style.get("surface_mode", "baseline_pbr")) in [
			"garden_galaxy_diorama",
			"garden_galaxy_reference_pbr",
		]
	):
		return _cache(key, _garden_galaxy_surface_material(key, style))
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = _styled_albedo(key, palette.color(key), style)
	m.roughness = float(style["roughness"])
	m.metallic = float(style["metallic"])
	m.metallic_specular = float(style["specular"])
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = palette.color(key)
		m.emission_energy_multiplier = emission_energy
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = alpha
	_materials[key] = m
	return m


func art_style_id() -> String:
	return _art_style_id


func _surface_ramp_parameters() -> Dictionary:
	var parameters := SURFACE_RAMP.duplicate(true)
	var surface_mode := String(_art_style.get("surface_mode", "baseline_pbr"))
	if surface_mode == "garden_galaxy_diorama":
		parameters["ramp_top_lift"] = 0.10
		parameters["ramp_bottom_drop"] = 0.16
		parameters["mottle_amount"] = 0.035
	elif surface_mode == "garden_galaxy_reference_pbr":
		# The reference screenshots use large deliberate colour regions and clean
		# surfaces. Lighting supplies the gradient; procedural grain made imported
		# Meshy assets look dirty beside the native props.
		parameters["ramp_top_lift"] = 0.035
		parameters["ramp_bottom_drop"] = 0.055
		parameters["mottle_amount"] = 0.0
	return parameters


func _garden_galaxy_surface_material(
	key: String,
	style: Dictionary
) -> ShaderMaterial:
	var material_instance := ShaderMaterial.new()
	material_instance.resource_name = key
	material_instance.shader = SURFACE_SHADER
	material_instance.set_shader_parameter(
		"albedo",
		_styled_albedo(key, palette.color(key), style)
	)
	material_instance.set_shader_parameter(
		"roughness_val",
		float(style.get("roughness", 0.72))
	)
	material_instance.set_shader_parameter(
		"metallic_val",
		float(style.get("metallic", 0.0))
	)
	material_instance.set_shader_parameter(
		"specular_val",
		float(style.get("specular", 0.5))
	)
	for parameter_name in _surface_ramp_parameters():
		material_instance.set_shader_parameter(
			parameter_name,
			_surface_ramp_parameters()[parameter_name]
		)
	return material_instance


func _active_style_parameters(key: String, source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	if not _uses_garden_galaxy_reference():
		return result
	result["family"] = "garden_galaxy_reference_pbr"
	# Exact response selected by the old crisp-studio graphics test. Material
	# classes keep distinct gloss and pastelization instead of collapsing into
	# one uniformly matte toy surface.
	result["calm_cream_mix"] = 0.08
	result["calm_value_lift"] = 0.0
	result["metallic"] = 0.0
	result["specular"] = 0.5
	result["roughness"] = 0.72
	var lower_key := key.to_lower()
	if _contains_any(
		lower_key,
		["grass", "moss", "leaf", "foliage", "pine", "olive", "flora", "reed"]
	):
		result["roughness"] = 0.74
		result["calm_cream_mix"] = 0.14
	elif _contains_any(lower_key, ["earth", "soil", "sand"]):
		result["roughness"] = 0.8
		result["specular"] = 0.45
		result["calm_cream_mix"] = 0.08
	elif _contains_any(lower_key, ["stone", "rock", "concrete"]):
		result["roughness"] = 0.7
		result["calm_cream_mix"] = 0.06
	elif _contains_any(lower_key, ["wood", "cardboard"]):
		result["roughness"] = 0.72
		result["calm_cream_mix"] = 0.1
	elif _contains_any(lower_key, ["terracotta", "ceramic", "coral", "burnt_red"]):
		result["roughness"] = 0.66
		result["specular"] = 0.55
		result["calm_cream_mix"] = 0.1
	elif _contains_any(
		lower_key,
		["fabric", "skin", "hair", "petal", "flower", "mushroom", "cream_fabric"]
	):
		result["roughness"] = 0.8
		result["specular"] = 0.45
		result["calm_cream_mix"] = 0.08
	elif lower_key.contains("snow"):
		result["roughness"] = 0.82
		result["specular"] = 0.35
		result["calm_cream_mix"] = 0.0
	elif _contains_any(lower_key, ["gold", "metal"]):
		result["roughness"] = float(source.get("roughness", 0.72))
		result["metallic"] = float(source.get("metallic", 0.28))
		result["specular"] = float(source.get("specular", 0.22))
		result["calm_cream_mix"] = 0.0
	return result


func _contains_any(source: String, needles: Array) -> bool:
	for needle: String in needles:
		if source.contains(needle):
			return true
	return false


## Returns a complete semantic parameter record for every palette material.
## These are original cross-engine mappings; the audit explicitly records that
## GG live material property blocks were not observed.
func material_parameters(key: String) -> Dictionary:
	var result: Dictionary = _style_data.get("defaults", {
		"family": "painted_matte",
		"roughness": 0.88,
		"metallic": 0.0,
		"specular": 0.18,
	}).duplicate(true)
	for family in _style_data.get("families", []):
		for token in family.get("contains", []):
			if key.contains(String(token)):
				for parameter in family:
					if parameter not in ["id", "contains"]:
						result[parameter] = family[parameter]
				result["family"] = family.get("id", result["family"])
				break
	if _style_data.get("overrides", {}).has(key):
		result.merge(_style_data["overrides"][key], true)
	return result


func material_parameter_manifest() -> Dictionary:
	var manifest := {}
	for key: String in _palette_keys():
		var live := material(key)
		if live is ShaderMaterial:
			manifest[key] = _shader_material_manifest(key, live as ShaderMaterial)
		else:
			var style := material_parameters(key)
			var standard := live as StandardMaterial3D
			if not standard.emission_enabled and standard.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				style["family"] = (
					"garden_galaxy_reference_pbr"
					if _uses_garden_galaxy_reference()
					else "realistic_pbr_surface"
				)
			style["material_class"] = "StandardMaterial3D"
			style["albedo_color"] = standard.albedo_color
			style["roughness"] = standard.roughness
			style["metallic"] = standard.metallic
			style["specular"] = standard.metallic_specular
			style["emission_enabled"] = standard.emission_enabled
			style["emission_color"] = standard.emission
			style["emission_energy"] = standard.emission_energy_multiplier if standard.emission_enabled else 0.0
			style["transparency_mode"] = standard.transparency
			manifest[key] = style
	if not manifest.has("water"):
		manifest["water"] = _shader_material_manifest("water", material("water") as ShaderMaterial)
	return manifest


func _shader_material_manifest(key: String, shader_material: ShaderMaterial) -> Dictionary:
	var parameters := {}
	if shader_material.shader == SOFT_TERRAIN_SHADER:
		for parameter_name in [
			"albedo", "roughness_val", "metallic_val", "specular_val",
			"ramp_height", "ramp_top_lift", "ramp_bottom_drop",
			"terrain_lifetime", "terrain_depth", "terrain_radius",
			"terrain_rim_height", "terrain_floor_height",
			"terrain_compressed_tint",
			"terrain_rim_tint",
		]:
			parameters[parameter_name] = shader_material.get_shader_parameter(
				parameter_name
			)
		parameters["roughness"] = parameters["roughness_val"]
		parameters["metallic"] = parameters["metallic_val"]
		parameters["specular"] = parameters["specular_val"]
		return {
			"family": "responsive_soft_terrain",
			"material_class": "ShaderMaterial",
			"shader_path": shader_material.shader.resource_path,
			"soft_surface_profile": SOFT_TERRAIN_PARAMETERS[key]["profile"],
			"imprint_capacity": SOFT_TERRAIN_IMPRINT_COUNT,
			"parameters": parameters,
		}
	if shader_material.shader == SURFACE_SHADER:
		for parameter_name in [
			"albedo", "roughness_val", "metallic_val", "specular_val",
			"ramp_height", "ramp_top_lift", "ramp_bottom_drop",
		]:
			parameters[parameter_name] = shader_material.get_shader_parameter(parameter_name)
		parameters["roughness"] = parameters["roughness_val"]
		parameters["metallic"] = parameters["metallic_val"]
		parameters["specular"] = parameters["specular_val"]
		return {
			"family": (
				"garden_galaxy_reference_pbr"
				if _uses_garden_galaxy_reference()
				else "gg_diorama_surface"
			),
			"material_class": "ShaderMaterial",
			"shader_path": shader_material.shader.resource_path,
			"art_style_id": _art_style_id,
			"parameters": parameters,
		}
	var family := "original_underwater_shader"
	var names: Array = ["albedo", "caustic_color"]
	if key == "water":
		family = "original_water_shader"
		names = [
			"shallow_color", "mid_color", "deep_color", "foam_color", "sky_color",
			"side_top_color", "side_bottom_color", "caustic_color",
		]
		names.append_array(WATER_PARAMETERS.keys())
	elif key.begins_with("uw_flora"):
		family = "original_underwater_flora_shader"
		names.append_array(FLORA_PARAMETERS.keys())
	else:
		names.append_array(UNDERWATER_PARAMETERS.keys())
	for parameter_name in names:
		var shader_name := String(parameter_name)
		if shader_name == "roughness":
			shader_name = "roughness_val"
		if shader_name == "specular":
			# The two underwater shaders use a fixed 0.12 in shader code.
			parameters[String(parameter_name)] = 0.12
			continue
		parameters[String(parameter_name)] = shader_material.get_shader_parameter(shader_name)
	return {
		"family": family,
		"material_class": "ShaderMaterial",
		"shader_path": shader_material.shader.resource_path,
		"parameters": parameters,
	}


func _configure_soft_terrain_material(
	surface: ShaderMaterial,
	key: String,
	profile: Dictionary
) -> void:
	for parameter_name in [
		"terrain_lifetime",
		"terrain_depth",
		"terrain_radius",
		"terrain_rim_height",
	]:
		surface.set_shader_parameter(parameter_name, profile[parameter_name])
	var base_color := _styled_albedo(
		key,
		palette.color(key),
		material_parameters(key)
	)
	if String(profile["profile"]) == "snow":
		surface.set_shader_parameter(
			"terrain_compressed_tint",
			palette.color("snow_side").darkened(0.04)
		)
		surface.set_shader_parameter(
			"terrain_rim_tint",
			base_color.lightened(0.07)
		)
	else:
		surface.set_shader_parameter(
			"terrain_compressed_tint",
			base_color.darkened(0.16)
		)
		surface.set_shader_parameter(
			"terrain_rim_tint",
			base_color.lightened(0.08)
		)


func _cache(key: String, m: Material) -> Material:
	m.resource_name = key
	_materials[key] = m
	return m


## Shared depth-aware water surface material (see gg_water.gdshader).
func _water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("shallow_color", _styled_albedo("water_shallow", palette.color("water_shallow")))
	m.set_shader_parameter("mid_color", _styled_albedo("water_turquoise", palette.color("water_turquoise")))
	m.set_shader_parameter("deep_color", _styled_albedo("water_deep", palette.color("water_deep")))
	m.set_shader_parameter("foam_color", _styled_albedo("water_foam", palette.color("water_foam")))
	m.set_shader_parameter("sky_color", palette.color("background_day"))
	m.set_shader_parameter("side_top_color", palette.color("water_shallow_highlight"))
	m.set_shader_parameter("side_bottom_color", palette.color("water_turquoise"))
	m.set_shader_parameter("caustic_color", palette.color("water_caustic"))
	m.set_shader_parameter("placement_invalid_tint", palette.color("ui_invalid"))
	var water_parameters := _active_water_parameters()
	for parameter in water_parameters:
		m.set_shader_parameter(parameter, water_parameters[parameter])
	return m


func _active_water_parameters() -> Dictionary:
	if (
		String(_art_style.get("surface_mode", "baseline_pbr"))
		in ["garden_galaxy_diorama", "garden_galaxy_reference_pbr"]
	):
		return GARDEN_GALAXY_WATER_PARAMETERS
	return WATER_PARAMETERS


func _underwater_material(key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = UNDERWATER_SHADER
	m.set_shader_parameter("albedo", _styled_albedo(key, palette.color(key)))
	m.set_shader_parameter("caustic_color", palette.color("water_caustic"))
	m.set_shader_parameter("water_level", UNDERWATER_PARAMETERS["water_level"])
	m.set_shader_parameter("caustic_strength", UNDERWATER_PARAMETERS["caustic_strength"])
	m.set_shader_parameter("depth_fade", UNDERWATER_PARAMETERS["depth_fade"])
	m.set_shader_parameter("roughness_val", UNDERWATER_PARAMETERS["roughness"])
	return m


func _flora_material(key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FLORA_SHADER
	m.set_shader_parameter("albedo", _styled_albedo(key, palette.color(key)))
	m.set_shader_parameter("caustic_color", palette.color("water_caustic"))
	m.set_shader_parameter("water_level", FLORA_PARAMETERS["water_level"])
	m.set_shader_parameter("sway_strength", FLORA_PARAMETERS["sway_strength"])
	m.set_shader_parameter("sway_speed", FLORA_PARAMETERS["sway_speed"])
	m.set_shader_parameter("depth_fade", FLORA_PARAMETERS["depth_fade"])
	return m


## Variant material tinted at runtime (skin tones, hair colors, outfit palettes).
## Cached per (base_key, color) so recolors still share materials.
func tinted(base_key: String, tint: Color) -> Material:
	var cache_key := "%s|%s" % [base_key, tint.to_html()]
	if _materials.has(cache_key):
		return _materials[cache_key]
	var instance := material(base_key).duplicate() as Material
	instance.resource_name = cache_key
	if instance is ShaderMaterial:
		(instance as ShaderMaterial).set_shader_parameter(
			"albedo",
			_styled_albedo(
				base_key,
				tint,
				_active_style_parameters(
					base_key,
					material_parameters(base_key)
				)
			)
		)
	elif instance is StandardMaterial3D:
		var standard := instance as StandardMaterial3D
		standard.albedo_color = Color(
			_styled_albedo(
				base_key,
				tint,
				_active_style_parameters(
					base_key,
					material_parameters(base_key)
				)
			),
			standard.albedo_color.a
		)
		if standard.emission_enabled:
			standard.emission = tint
	_materials[cache_key] = instance
	return instance


func _styled_albedo(key: String, source: Color, supplied_style := {}) -> Color:
	var style: Dictionary = supplied_style if not supplied_style.is_empty() else material_parameters(key)
	if _uses_garden_galaxy_reference():
		if supplied_style.is_empty():
			style = _active_style_parameters(key, style)
		source = _garden_galaxy_reference_color(key, source)
	var cream := palette.color("warm_white")
	var result := source.lerp(cream, float(style.get("calm_cream_mix", 0.0)))
	var lift := float(style.get("calm_value_lift", 0.0))
	result.r = minf(1.0, result.r + lift)
	result.g = minf(1.0, result.g + lift)
	result.b = minf(1.0, result.b + lift)
	result.a = source.a
	return result


func _garden_galaxy_reference_color(key: String, fallback: Color) -> Color:
	var exact: Dictionary = _garden_galaxy_palette.get("exact", {})
	if exact.has(key):
		return Color.from_string(String(exact[key]), fallback)
	var lower_key := key.to_lower()
	for family: Dictionary in _garden_galaxy_palette.get("families", []):
		for token: String in family.get("contains", []):
			if lower_key.contains(token):
				return Color.from_string(String(family.get("color", "")), fallback)
	return fallback


func _uses_garden_galaxy_reference() -> bool:
	return (
		String(_art_style.get("surface_mode", "baseline_pbr"))
		== "garden_galaxy_reference_pbr"
	)


## Recursively swap every surface whose imported material name matches a palette
## key for the shared library material.
func rebind_materials(root: Node) -> void:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var current := mesh.surface_get_material(surface)
			if current == null:
				continue
			var key := _semantic_key(current.resource_name)
			if key != "":
				mesh_instance.set_surface_override_material(surface, material(key))


func _semantic_key(raw_name: String) -> String:
	# glTF import can suffix duplicates ("grass.001"); strip that.
	var key := raw_name.get_slice(".", 0)
	return key if _has_palette_color(key) else ""


func _fallback() -> Material:
	if not _materials.has("__fallback"):
		var m := StandardMaterial3D.new()
		m.albedo_color = palette.color("debug_missing")
		_materials["__fallback"] = m
	return _materials["__fallback"]


func _has_palette_color(key: String) -> bool:
	if palette is PaletteDefinition:
		return (palette as PaletteDefinition).has_color(key)
	return palette.colors.has(key)


func _palette_keys() -> PackedStringArray:
	if palette is PaletteDefinition:
		return (palette as PaletteDefinition).all_color_keys()
	return PackedStringArray(palette.colors.keys())


func _on_palette_changed(_scheme_id: String) -> void:
	for key: String in _materials:
		if key == "__fallback" or key.contains("|"):
			continue
		_refresh_material_color(key, _materials[key])


func _refresh_material_color(key: String, material_instance: Material) -> void:
	if material_instance is ShaderMaterial:
		var shader_material := material_instance as ShaderMaterial
		if key == "water":
			shader_material.set_shader_parameter(
				"shallow_color",
				_styled_albedo("water_shallow", palette.color("water_shallow"))
			)
			shader_material.set_shader_parameter(
				"mid_color",
				_styled_albedo("water_turquoise", palette.color("water_turquoise"))
			)
			shader_material.set_shader_parameter(
				"deep_color",
				_styled_albedo("water_deep", palette.color("water_deep"))
			)
			shader_material.set_shader_parameter(
				"foam_color",
				_styled_albedo("water_foam", palette.color("water_foam"))
			)
			shader_material.set_shader_parameter(
				"sky_color",
				palette.color("background_day")
			)
			shader_material.set_shader_parameter(
				"side_top_color",
				palette.color("water_shallow_highlight")
			)
			shader_material.set_shader_parameter(
				"side_bottom_color",
				palette.color("water_turquoise")
			)
			shader_material.set_shader_parameter(
				"caustic_color",
				palette.color("water_caustic")
			)
			return
		if key.begins_with("uw_"):
			shader_material.set_shader_parameter(
				"albedo",
				_styled_albedo(key, palette.color(key))
			)
			shader_material.set_shader_parameter(
				"caustic_color",
				palette.color("water_caustic")
			)
			return
		shader_material.set_shader_parameter(
			"albedo",
			_styled_albedo(key, palette.color(key), material_parameters(key))
		)
		if SOFT_TERRAIN_PARAMETERS.has(key):
			_configure_soft_terrain_material(
				shader_material,
				key,
				SOFT_TERRAIN_PARAMETERS[key]
			)
		return
	if material_instance is StandardMaterial3D:
		var standard := material_instance as StandardMaterial3D
		var alpha := standard.albedo_color.a
		standard.albedo_color = Color(
			_styled_albedo(key, palette.color(key), material_parameters(key)),
			alpha
		)
		if standard.emission_enabled:
			standard.emission = palette.color(key)
