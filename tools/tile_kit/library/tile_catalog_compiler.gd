@tool
class_name TileCatalogCompiler
extends RefCounted
## Compiles official manifests into the runtime's existing JSON catalog.
##
## data/tiles.json remains the fast, read-only runtime format. Designers never
## hand-edit its managed entries; the manifests are authoritative and this
## compiler preserves every unmanaged/legacy entry verbatim.

const DEFAULT_CATALOG_PATH := "res://data/tiles.json"
const DEFAULT_TUNING_PATH := "res://data/tuning.json"
const CatalogTaxonomy := preload("res://tools/tile_kit/library/tile_catalog_taxonomy.gd")

class CandidateSnapshot:
	extends RefCounted
	var tiles: Dictionary = {}

	func source(_kind: String, _id: String) -> Variant:
		return null


var catalog_path := DEFAULT_CATALOG_PATH
var tuning_path := DEFAULT_TUNING_PATH


func build_candidate(
	manifests: Array[TileLibraryManifest],
	retired_ids: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var errors := PackedStringArray()
	var catalog := _read_json_object(catalog_path, errors)
	var tuning := _read_json_object(tuning_path, errors)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var raw_tiles: Variant = catalog.get("tiles", [])
	if not (raw_tiles is Array):
		errors.append("%s must contain a tiles array." % catalog_path)
		return {"ok": false, "errors": errors}
	var managed_ids: Dictionary = {}
	for retired_id in retired_ids:
		managed_ids[String(retired_id)] = true
	var official_by_id: Dictionary = {}
	for manifest in manifests:
		if manifest == null:
			errors.append("Tile Library contains a null manifest.")
			continue
		for error in manifest.validation_errors():
			errors.append("%s: %s" % [manifest.tile_id, error])
		if managed_ids.has(manifest.tile_id):
			errors.append("Duplicate official manifest id '%s'." % manifest.tile_id)
		managed_ids[manifest.tile_id] = true
		if manifest.is_official():
			official_by_id[manifest.tile_id] = manifest
	var compiled_tiles: Array = []
	var seen_ids: Dictionary = {}
	for raw: Variant in raw_tiles:
		if not (raw is Dictionary):
			errors.append("Runtime tile entries must be objects.")
			continue
		var raw_id := String((raw as Dictionary).get("id", ""))
		if managed_ids.has(raw_id):
			continue
		if seen_ids.has(raw_id):
			errors.append("Duplicate unmanaged runtime tile id '%s'." % raw_id)
		seen_ids[raw_id] = true
		compiled_tiles.append((raw as Dictionary).duplicate(true))
	var official_ids: Array[String] = []
	for raw_id in official_by_id:
		official_ids.append(String(raw_id))
	official_ids.sort_custom(func(a: String, b: String) -> bool:
		var manifest_a := official_by_id[a] as TileLibraryManifest
		var manifest_b := official_by_id[b] as TileLibraryManifest
		var category_a := CatalogTaxonomy.category_rank(manifest_a.catalog_category)
		var category_b := CatalogTaxonomy.category_rank(manifest_b.catalog_category)
		if category_a != category_b:
			return category_a < category_b
		if manifest_a.catalog_order != manifest_b.catalog_order:
			return manifest_a.catalog_order < manifest_b.catalog_order
		return manifest_a.display_name.naturalnocasecmp_to(manifest_b.display_name) < 0
	)
	for tile_id in official_ids:
		if seen_ids.has(tile_id):
			errors.append("Manifest id '%s' collides with unmanaged runtime content." % tile_id)
			continue
		seen_ids[tile_id] = true
		compiled_tiles.append(
			(official_by_id[tile_id] as TileLibraryManifest).to_tile_dictionary()
		)
	var compiled_tuning := tuning.duplicate(true)
	compiled_tuning["active_tile_ids"] = _compiled_visibility_ids(
		tuning.get("active_tile_ids", []), manifests,
		TileLibraryManifest.VISIBILITY_ACTIVE, retired_ids
	)
	compiled_tuning["preview_tile_ids"] = _compiled_visibility_ids(
		tuning.get("preview_tile_ids", []), manifests,
		TileLibraryManifest.VISIBILITY_PREVIEW, retired_ids
	)
	var payload := catalog.duplicate(true)
	payload["tiles"] = compiled_tiles
	_validate_definitions(compiled_tiles, compiled_tuning, errors)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"catalog": payload,
		"tuning": compiled_tuning,
	}


func compile(
	manifests: Array[TileLibraryManifest],
	retired_ids: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var candidate := build_candidate(manifests, retired_ids)
	if not bool(candidate.get("ok", false)):
		return candidate
	var catalog_snapshot: Variant = _snapshot_file(catalog_path)
	var tuning_snapshot: Variant = _snapshot_file(tuning_path)
	var catalog_error := _write_json_object(catalog_path, candidate["catalog"])
	if catalog_error != OK:
		candidate["ok"] = false
		candidate["errors"] = PackedStringArray([
			"Catalog write failed: %s" % error_string(catalog_error)
		])
		return candidate
	var tuning_error := _write_json_object(tuning_path, candidate["tuning"])
	if tuning_error != OK:
		_restore_file(catalog_path, catalog_snapshot)
		_restore_file(tuning_path, tuning_snapshot)
		candidate["ok"] = false
		candidate["errors"] = PackedStringArray([
			"Tuning write failed: %s" % error_string(tuning_error)
		])
		return candidate
	return candidate


func _snapshot_file(path: String) -> Variant:
	var absolute := ProjectSettings.globalize_path(path)
	return (
		FileAccess.get_file_as_bytes(absolute)
		if FileAccess.file_exists(absolute)
		else null
	)


func _restore_file(path: String, snapshot: Variant) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if snapshot == null:
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)
		return
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file != null:
		file.store_buffer(snapshot as PackedByteArray)


func _compiled_visibility_ids(
	current: Variant,
	manifests: Array[TileLibraryManifest],
	visibility: String,
	retired_ids: PackedStringArray = PackedStringArray()
) -> Array[String]:
	var managed: Dictionary = {}
	var by_id: Dictionary = {}
	for retired_id in retired_ids:
		managed[String(retired_id)] = true
	for manifest in manifests:
		if manifest != null:
			managed[manifest.tile_id] = true
			by_id[manifest.tile_id] = manifest
	var result: Array[String] = []
	if current is Array:
		for raw_id in current:
			var tile_id := String(raw_id)
			var keep_managed := false
			if by_id.has(tile_id):
				var manifest := by_id[tile_id] as TileLibraryManifest
				keep_managed = (
					manifest.lifecycle == TileLibraryManifest.LIFECYCLE_PUBLISHED
					and manifest.visibility == visibility
				)
			if (
				(not managed.has(tile_id) or keep_managed)
				and not result.has(tile_id)
			):
				result.append(tile_id)
	var additions: Array[String] = []
	for manifest in manifests:
		if (
			manifest != null
			and manifest.lifecycle == TileLibraryManifest.LIFECYCLE_PUBLISHED
			and manifest.visibility == visibility
		):
			additions.append(manifest.tile_id)
	additions.sort()
	for tile_id in additions:
		if not result.has(tile_id):
			result.append(tile_id)
	return result


func _validate_definitions(
	raw_tiles: Array,
	tuning: Dictionary,
	errors: PackedStringArray
) -> void:
	var snapshot := CandidateSnapshot.new()
	for raw: Variant in raw_tiles:
		if not (raw is Dictionary):
			continue
		var definition := Defs.TileDefinition.from_dict(raw)
		if definition.id.is_empty():
			errors.append("Compiled tile has an empty id.")
			continue
		if snapshot.tiles.has(definition.id):
			errors.append("Compiled catalog repeats '%s'." % definition.id)
			continue
		snapshot.tiles[definition.id] = definition
	var issues: Array = []
	TileDefinitionValidator.validate(snapshot, issues)
	for issue in issues:
		if issue.severity == ValidationIssue.Severity.ERROR:
			errors.append(issue.format())
	for list_name in ["active_tile_ids", "preview_tile_ids"]:
		var configured: Variant = tuning.get(list_name, [])
		if not (configured is Array):
			errors.append("%s must be an array." % list_name)
			continue
		var seen: Dictionary = {}
		for raw_id in configured:
			var tile_id := String(raw_id)
			if not snapshot.tiles.has(tile_id):
				errors.append("%s references missing tile '%s'." % [list_name, tile_id])
			if seen.has(tile_id):
				errors.append("%s repeats tile '%s'." % [list_name, tile_id])
			seen[tile_id] = true


func _read_json_object(path: String, errors: PackedStringArray) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(absolute):
		errors.append("Missing JSON source: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and path != absolute:
		text = FileAccess.get_file_as_string(absolute)
	var parser := JSON.new()
	if parser.parse(text) != OK or not (parser.data is Dictionary):
		errors.append("Invalid JSON source: %s" % path)
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _write_json_object(path: String, value: Dictionary) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	var parent := absolute.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(parent)
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "  ", false) + "\n")
	return OK
