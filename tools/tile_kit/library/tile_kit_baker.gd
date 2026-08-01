@tool
class_name TileKitBaker
extends RefCounted
## Deterministic bridge from an editable recipe to runtime PackedScenes.
## Every filename begins with the manifest's stable tile id; no second tile can
## overwrite another tile's bake, and changing a display name changes nothing.

const DEFAULT_OUTPUT_DIRECTORY := "res://tools/tile_kit/baked"

var output_directory := DEFAULT_OUTPUT_DIRECTORY


func bake(preset: TileKitPreset, tile_id: String) -> Dictionary:
	var errors := PackedStringArray()
	var written := PackedStringArray()
	var baked_roles := PackedStringArray()
	if preset == null:
		return {"ok": false, "errors": PackedStringArray(["Recipe is missing."])}
	if tile_id.is_empty() or tile_id != tile_id.to_snake_case() \
			or not tile_id.is_valid_identifier():
		return {"ok": false, "errors": PackedStringArray(["Tile ID is not bake-safe."])}
	var absolute_output := ProjectSettings.globalize_path(output_directory)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		absolute_output + "/materials"
	)
	if directory_error != OK:
		return {
			"ok": false,
			"errors": PackedStringArray([
				"Could not create bake directory: %s" % error_string(directory_error)
			]),
		}
	_save_materials(errors, written)
	var stats: Dictionary = {}
	for mask in 16:
		var generator := TileKitGenerator.new()
		generator.preset = preset
		generator.neighbour_mask = mask
		generator.rebuild()
		var scenes := generator.bake_role_scenes()
		if mask == 0:
			stats = generator.statistics()
			for role in scenes:
				baked_roles.append(String(role))
		for role: String in scenes:
			if mask > 0 and role == "detail":
				continue
			var asset_id := "%s_%s" % [tile_id, role]
			if mask > 0:
				asset_id += "_n%02d" % mask
			var path := "%s/%s.tscn" % [output_directory, asset_id]
			var error := ResourceSaver.save(scenes[role], path)
			if error == OK:
				written.append(path)
			else:
				errors.append("%s: %s" % [path, error_string(error)])
		generator.free()
	baked_roles.sort()
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"written": written,
		"roles": baked_roles,
		"statistics": stats,
	}


func baked_paths_for(tile_id: String) -> PackedStringArray:
	var result := PackedStringArray()
	var absolute := ProjectSettings.globalize_path(output_directory)
	var directory := DirAccess.open(absolute)
	if directory == null:
		return result
	for file in directory.get_files():
		if file.begins_with(tile_id + "_") and file.ends_with(".tscn"):
			result.append("%s/%s" % [output_directory, file])
	result.sort()
	return result


func remove_bake(tile_id: String) -> PackedStringArray:
	var failures := PackedStringArray()
	for path in baked_paths_for(tile_id):
		var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if error != OK:
			failures.append("%s: %s" % [path, error_string(error)])
	return failures


func _save_materials(errors: PackedStringArray, written: PackedStringArray) -> void:
	for key: String in TileKitPalette.COLORS:
		var material := TileKitPalette.material(key)
		var path := "%s/materials/%s.tres" % [output_directory, key]
		var error := ResourceSaver.save(material, path)
		if error == OK:
			material.take_over_path(path)
			written.append(path)
		else:
			errors.append("%s: %s" % [path, error_string(error)])
