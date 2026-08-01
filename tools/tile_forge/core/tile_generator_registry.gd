@tool
class_name TileGeneratorRegistry
extends RefCounted
## Maps generator ids to implementations.
##
## Registration is by DISCOVERY, not by editing a list: every .gd file under
## tools/tile_forge/generators/ that extends TileLayerGenerator is loaded and
## asked for its own id. Adding a geometry family is therefore literally one
## new file — no recipe, no baker, and no existing generator changes, which is
## success criterion 6.
##
## `register()` remains available for a generator that lives outside the folder
## (a game-specific family in scripts/, for example).

const GENERATOR_DIR := "res://tools/tile_forge/generators"

static var _shared: TileGeneratorRegistry

var _generators: Dictionary = {}
var _load_errors: PackedStringArray = []


static func shared() -> TileGeneratorRegistry:
	if _shared == null:
		_shared = TileGeneratorRegistry.new()
		_shared.discover()
	return _shared


## Forces a rescan. The lab calls this after a script edit so a new generator
## appears without restarting the editor.
static func refresh() -> TileGeneratorRegistry:
	_shared = TileGeneratorRegistry.new()
	_shared.discover()
	return _shared


func discover() -> void:
	_generators.clear()
	_load_errors.clear()
	var dir := DirAccess.open(GENERATOR_DIR)
	if dir == null:
		_load_errors.append("generator directory not found: %s" % GENERATOR_DIR)
		return
	var names := dir.get_files()
	names.sort()  # stable registration order
	for file_name in names:
		# `.uid` sidecars end in ".gd.uid"; stripping the suffix would produce a
		# second, identical path and register every generator twice.
		if file_name.ends_with(".uid"):
			continue
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".gd"):
			continue
		_load_one(GENERATOR_DIR.path_join(clean))


func _load_one(path: String) -> void:
	var script: Variant = ResourceLoader.load(path)
	if script == null or not (script is GDScript):
		_load_errors.append("not a script: %s" % path)
		return
	var instance: Variant = (script as GDScript).new()
	if not (instance is TileLayerGenerator):
		_load_errors.append("does not extend TileLayerGenerator: %s" % path)
		return
	var generator := instance as TileLayerGenerator
	var id := generator.generator_id()
	if id == "" or id == "abstract":
		_load_errors.append("generator has no id: %s" % path)
		return
	if _generators.has(id):
		_load_errors.append(
			"duplicate generator id '%s' (%s already registered)" % [id, path]
		)
		return
	_generators[id] = generator


func register(generator: TileLayerGenerator) -> void:
	if generator == null:
		return
	_generators[generator.generator_id()] = generator


func has(id: String) -> bool:
	return _generators.has(id)


func get_generator(id: String) -> TileLayerGenerator:
	return _generators.get(id, null)


func ids() -> PackedStringArray:
	var result := PackedStringArray(_generators.keys())
	result.sort()
	return result


func load_errors() -> PackedStringArray:
	return _load_errors


## One line per generator, for the lab panel and the README's generator table.
func report() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in ids():
		var generator: TileLayerGenerator = _generators[id]
		var kind_names: PackedStringArray = []
		for kind in generator.kinds():
			kind_names.append(TileForgeConstants.Kind.keys()[kind])
		result.append({
			"id": id,
			"kinds": Array(kind_names),
			"description": generator.description(),
		})
	return result
