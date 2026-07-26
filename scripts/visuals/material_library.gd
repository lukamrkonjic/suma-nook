class_name MaterialLibrary
extends RefCounted
## One shared material per palette key, all built on the garden master shader
## (matte, low specular, mild orientation tint). GLB assets ship with semantic
## material names ("grass", "wood", ...); rebind_materials() swaps every surface
## to the shared library instance, so a palette edit re-skins the whole game
## without touching a single GLB.

const MASTER_SHADER: Shader = preload("res://assets/materials/garden_master.gdshader")
const WATER_SHADER: Shader = preload("res://assets/materials/garden_water.gdshader")

const EMISSIVE := {"fire_core": 5.0, "fire_outer": 2.5, "magic": 2.0}
## Restrained metals: warm, mostly matte — no glossy plastic, no mirror black.
const METALS := {
	"gold": {"metallic": 0.30, "roughness": 0.65},
	"metal": {"metallic": 0.25, "roughness": 0.72},
	"warm_charcoal": {"metallic": 0.05, "roughness": 0.78},
}

var palette: CozyPalette
var _materials: Dictionary = {}


func _init(pal: CozyPalette) -> void:
	palette = pal


func material(key: String) -> Material:
	if _materials.has(key):
		return _materials[key]
	if not palette.colors.has(key):
		return _fallback()
	var m: Material
	match key:
		"water":
			m = _water_material()
		"crystal":
			m = _crystal_material()
		_:
			m = _master_material(key)
	m.resource_name = key
	_materials[key] = m
	return m


func _master_material(key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = MASTER_SHADER
	m.set_shader_parameter("albedo", palette.color(key))
	m.set_shader_parameter("roughness", METALS[key]["roughness"] if METALS.has(key) else 0.9)
	m.set_shader_parameter("metallic", METALS[key]["metallic"] if METALS.has(key) else 0.0)
	m.set_shader_parameter("specular", 0.3 if METALS.has(key) else 0.18)
	if EMISSIVE.has(key):
		m.set_shader_parameter("emission_color", palette.color(key))
		m.set_shader_parameter("emission_energy", EMISSIVE[key])
	return m


func _water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("base_color", palette.color("water"))
	m.set_shader_parameter("deep_color", palette.color("water_deep"))
	m.set_shader_parameter("lit_color", palette.color("water_light"))
	return m


func _crystal_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = palette.color("crystal")
	m.albedo_color.a = 0.9
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.35
	m.metallic_specular = 0.3
	m.emission_enabled = true
	m.emission = palette.color("crystal")
	m.emission_energy_multiplier = 1.0
	return m


## Variant material tinted at runtime (skin tones, hair colors, outfit palettes).
## Cached per (base_key, color) so recolors still share materials.
func tinted(base_key: String, tint: Color) -> Material:
	var cache_key := "%s|%s" % [base_key, tint.to_html()]
	if _materials.has(cache_key):
		return _materials[cache_key]
	var m := material(base_key).duplicate() as Material
	m.resource_name = cache_key
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		if sm.shader == MASTER_SHADER:
			sm.set_shader_parameter("albedo", tint)
			if EMISSIVE.has(base_key):
				sm.set_shader_parameter("emission_color", tint)
		else:
			sm.set_shader_parameter("base_color", tint)
	elif m is StandardMaterial3D:
		var std := m as StandardMaterial3D
		std.albedo_color = Color(tint, std.albedo_color.a)
		if std.emission_enabled:
			std.emission = tint
	_materials[cache_key] = m
	return m


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
