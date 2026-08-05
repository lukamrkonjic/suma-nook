@tool
class_name TileKitBaker
extends RefCounted
## Deterministic bridge from an editable recipe to runtime PackedScenes.
## Every filename begins with the manifest's stable tile id; no second tile can
## overwrite another tile's bake, and changing a display name changes nothing.

const DEFAULT_OUTPUT_DIRECTORY := "res://tools/tile_kit/baked"

## Palette materials are identical for every tile in a run. Saving them once
## per bake() (35+ times per library rebuild) made Windows file locking reject
## rewrites of files written milliseconds earlier — save them once per session.
static var _materials_written := false

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
	# Canonical same-surface topology plus a second compact transition family.
	# The latter has identical rim removal but flattens relief at boundaries so
	# unlike natural materials can meet cleanly. This remains 31 states per tile
	# rather than multiplying every same/mixed edge combination.
	var bake_state_count := 16 if preset.separate_tiles else 31
	for bake_state in bake_state_count:
		var transition := bake_state >= 16
		var mask := bake_state - 15 if transition else bake_state
		var generator := TileKitGenerator.new()
		generator.preset = preset
		generator.neighbour_mask = mask
		generator.flatten_connected_relief = transition
		generator.rebuild()
		var scenes := generator.bake_role_scenes()
		if not transition and mask == 0:
			stats = generator.statistics()
			for role in scenes:
				baked_roles.append(String(role))
		for role: String in scenes:
			if (mask > 0 or transition) and role == "detail":
				continue
			var asset_id := "%s_%s" % [tile_id, role]
			if transition:
				asset_id += "_x%02d" % mask
			elif mask > 0:
				asset_id += "_n%02d" % mask
			var path := "%s/%s.tscn" % [output_directory, asset_id]
			# Retried save: rewriting ~1900 bake files back-to-back trips
			# transient Windows locks (indexer/AV scanning the previous
			# write). The same failure mode the material saves already
			# handle — see _save_materials.
			var error := ResourceSaver.save(scenes[role], path)
			var attempts := 0
			while error != OK and attempts < 4:
				attempts += 1
				OS.delay_msec(150 * attempts)
				error = ResourceSaver.save(scenes[role], path)
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
	if _materials_written:
		return
	for key: String in TileKitPalette.COLORS:
		var material := TileKitPalette.material(key)
		var path := "%s/materials/%s.tres" % [output_directory, key]
		var error := ResourceSaver.save(material, path)
		if error != OK:
			# One quiet retry: the failure mode on Windows is a transient
			# lock (indexer/AV) on a file written moments ago.
			OS.delay_msec(120)
			error = ResourceSaver.save(material, path)
		if error == OK:
			material.take_over_path(path)
			written.append(path)
		else:
			errors.append("%s: %s" % [path, error_string(error)])
	_materials_written = true
