@tool
class_name TileDependencyScanner
extends RefCounted
## Finds references that would become dangling if a stable tile id vanished.
## Archive is always safe because the runtime definition remains. Hard delete
## is refused while authored content or any development save still names it.

var data_root := "res://data"
var save_root := "user://"


func dependencies_for(
	tile_id: String,
	manifests: Array[TileLibraryManifest]
) -> PackedStringArray:
	var result := PackedStringArray()
	for manifest in manifests:
		if manifest == null or manifest.tile_id == tile_id:
			continue
		if manifest.dependencies.has(tile_id):
			result.append("manifest:%s dependencies" % manifest.tile_id)
		_find_in_variant(
			manifest.runtime_definition,
			tile_id,
			"manifest:%s runtime_definition" % manifest.tile_id,
			result
		)
	_scan_json_tree(data_root, tile_id, result, true)
	_scan_json_tree(save_root, tile_id, result, false)
	var unique: Dictionary = {}
	for entry in result:
		unique[String(entry)] = true
	result = PackedStringArray(unique.keys())
	result.sort()
	return result


func _scan_json_tree(
	root: String,
	tile_id: String,
	result: PackedStringArray,
	is_content: bool
) -> void:
	var absolute := ProjectSettings.globalize_path(root)
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	_scan_directory(directory, absolute, tile_id, result, is_content)


func _scan_directory(
	directory: DirAccess,
	absolute: String,
	tile_id: String,
	result: PackedStringArray,
	is_content: bool
) -> void:
	for file in directory.get_files():
		if not file.ends_with(".json"):
			continue
		# Catalog ownership and visibility are rewritten atomically by the
		# compiler, so they are not external dependencies.
		if is_content and file in ["tiles.json", "tuning.json"]:
			continue
		var path := absolute.path_join(file)
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) == OK:
			_find_in_variant(parser.data, tile_id, path, result)
	for child in directory.get_directories():
		if child.begins_with("."):
			continue
		var child_absolute := absolute.path_join(child)
		var nested := DirAccess.open(child_absolute)
		if nested != null:
			_scan_directory(nested, child_absolute, tile_id, result, is_content)


func _find_in_variant(
	value: Variant,
	tile_id: String,
	location: String,
	result: PackedStringArray
) -> void:
	if value is String:
		if String(value) == tile_id:
			result.append(location)
		return
	if value is Dictionary:
		for key in value:
			_find_in_variant(
				(value as Dictionary)[key], tile_id,
				"%s.%s" % [location, String(key)], result
			)
		return
	if value is Array:
		for index in (value as Array).size():
			_find_in_variant(
				(value as Array)[index], tile_id,
				"%s[%d]" % [location, index], result
			)
