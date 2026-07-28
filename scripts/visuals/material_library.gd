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
## GG-style baked-shading emulation shared by every opaque surface material.
const SURFACE_RAMP := {
	"ramp_height": 1.35,
	"ramp_top_lift": 0.10,
	"ramp_bottom_drop": 0.16,
}
const STYLE_DATA_PATH := "res://data/material_styles.json"
const WATER_PARAMETERS := {
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


func _init(pal: CozyPalette) -> void:
	palette = pal
	_style_data = JSON.parse_string(FileAccess.get_file_as_string(STYLE_DATA_PATH))


func material(key: String) -> Material:
	if _materials.has(key):
		return _materials[key]
	if key == "water":
		return _cache(key, _water_material())
	if key.begins_with("uw_flora"):
		return _cache(key, _flora_material(key))
	if key.begins_with("uw_"):
		return _cache(key, _underwater_material(key))
	if not palette.colors.has(key):
		return _fallback()
	var style := material_parameters(key)
	var emission_energy := float(style.get("emission_energy", EMISSIVE.get(key, 0.0)))
	var alpha := float(style.get("alpha", 1.0))
	# Opaque, non-emissive surfaces use the GG diorama shader (baked-ramp
	# emulation). Emissive and translucent keys keep StandardMaterial3D.
	if emission_energy <= 0.0 and alpha >= 1.0:
		var surface := ShaderMaterial.new()
		surface.resource_name = key
		surface.shader = SURFACE_SHADER
		surface.set_shader_parameter("albedo", _styled_albedo(key, palette.color(key), style))
		surface.set_shader_parameter("roughness_val", float(style["roughness"]))
		surface.set_shader_parameter("metallic_val", float(style["metallic"]))
		surface.set_shader_parameter("specular_val", float(style["specular"]))
		for parameter in SURFACE_RAMP:
			surface.set_shader_parameter(parameter, SURFACE_RAMP[parameter])
		_materials[key] = surface
		return surface
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = _styled_albedo(key, palette.color(key), style)
	m.roughness = float(style["roughness"])
	m.metallic = float(style["metallic"])
	m.metallic_specular = float(style["specular"])
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = palette.color(key)
		m.emission_energy_multiplier = emission_energy
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = alpha
	_materials[key] = m
	return m


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
	for key: String in palette.colors:
		var live := material(key)
		if live is ShaderMaterial:
			manifest[key] = _shader_material_manifest(key, live as ShaderMaterial)
		else:
			var style := material_parameters(key)
			var standard := live as StandardMaterial3D
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
			"family": "gg_diorama_surface",
			"material_class": "ShaderMaterial",
			"shader_path": shader_material.shader.resource_path,
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
	for parameter in WATER_PARAMETERS:
		m.set_shader_parameter(parameter, WATER_PARAMETERS[parameter])
	return m


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
	var m := material(base_key).duplicate() as StandardMaterial3D
	m.resource_name = cache_key
	m.albedo_color = Color(_styled_albedo(base_key, tint), m.albedo_color.a)
	if m.emission_enabled:
		m.emission = tint
	_materials[cache_key] = m
	return m


func _styled_albedo(key: String, source: Color, supplied_style := {}) -> Color:
	var style: Dictionary = supplied_style if not supplied_style.is_empty() else material_parameters(key)
	var cream := palette.color("warm_white")
	var result := source.lerp(cream, float(style.get("calm_cream_mix", 0.0)))
	var lift := float(style.get("calm_value_lift", 0.0))
	result.r = minf(1.0, result.r + lift)
	result.g = minf(1.0, result.g + lift)
	result.b = minf(1.0, result.b + lift)
	result.a = source.a
	return result


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
	return key if palette.colors.has(key) else ""


func _fallback() -> Material:
	if not _materials.has("__fallback"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.MAGENTA
		_materials["__fallback"] = m
	return _materials["__fallback"]
