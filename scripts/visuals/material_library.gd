class_name MaterialLibrary
extends RefCounted
## One shared StandardMaterial3D per palette key. GLB assets ship with semantic
## material names ("grass", "wood", ...); rebind_materials() swaps every surface
## to the shared library instance, so a palette edit re-skins the whole game
## without touching a single GLB.
##
## Calibration baseline: ordinary matte materials, no custom shaders, no
## orientation tint, no baked sunlight. The DirectionalLight3D does the shading.

const EMISSIVE := {"fire_core": 5.0, "fire_outer": 2.5, "magic": 2.0, "crystal": 1.0}
## Restrained warm metals — never glossy plastic, never mirror black.
const METALS := {
	"gold": {"metallic": 0.3, "roughness": 0.65},
	"metal": {"metallic": 0.25, "roughness": 0.72},
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
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = palette.color(key)
	m.roughness = METALS[key]["roughness"] if METALS.has(key) else 0.88
	m.metallic = METALS[key]["metallic"] if METALS.has(key) else 0.0
	m.metallic_specular = 0.3 if METALS.has(key) else 0.18
	if EMISSIVE.has(key):
		m.emission_enabled = true
		m.emission = palette.color(key)
		m.emission_energy_multiplier = EMISSIVE[key]
	if key == "water":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 0.82
		m.roughness = 0.65
		m.metallic_specular = 0.2
	if key == "crystal":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 0.9
		m.roughness = 0.35
	_materials[key] = m
	return m


## Variant material tinted at runtime (skin tones, hair colors, outfit palettes).
## Cached per (base_key, color) so recolors still share materials.
func tinted(base_key: String, tint: Color) -> Material:
	var cache_key := "%s|%s" % [base_key, tint.to_html()]
	if _materials.has(cache_key):
		return _materials[cache_key]
	var m := material(base_key).duplicate() as StandardMaterial3D
	m.resource_name = cache_key
	m.albedo_color = Color(tint, m.albedo_color.a)
	if m.emission_enabled:
		m.emission = tint
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
