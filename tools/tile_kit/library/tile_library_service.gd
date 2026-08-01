@tool
class_name TileLibraryService
extends RefCounted
## Professional CRUD boundary for Tile Library content.
##
## Runtime builds only read compiled catalog/assets. Every mutating method is
## guarded here (not merely hidden in UI), so a release build cannot publish,
## overwrite, archive, or delete official content by calling around the panel.

const OFFICIAL_RECIPE_DIRECTORY := "res://tools/tile_kit/library/recipes"
const OFFICIAL_MANIFEST_DIRECTORY := "res://tools/tile_kit/library/manifests"
const DRAFT_RECIPE_DIRECTORY := "user://tile_library/drafts/recipes"
const DRAFT_MANIFEST_DIRECTORY := "user://tile_library/drafts/manifests"
const CatalogTaxonomy := preload("res://tools/tile_kit/library/tile_catalog_taxonomy.gd")

var official_recipe_directory := OFFICIAL_RECIPE_DIRECTORY
var official_manifest_directory := OFFICIAL_MANIFEST_DIRECTORY
var draft_recipe_directory := DRAFT_RECIPE_DIRECTORY
var draft_manifest_directory := DRAFT_MANIFEST_DIRECTORY
var compiler := TileCatalogCompiler.new()
var baker := TileKitBaker.new()
var dependency_scanner := TileDependencyScanner.new()
## -1 follows the build; 0/1 is for isolated tool tests only.
var mutation_override := -1

var manifests: Array[TileLibraryManifest] = []


func reload() -> Array[TileLibraryManifest]:
	manifests.clear()
	_load_manifests_from(official_manifest_directory)
	_load_manifests_from(draft_manifest_directory)
	manifests.sort_custom(func(a: TileLibraryManifest, b: TileLibraryManifest) -> bool:
		var rank_a := _lifecycle_rank(a.lifecycle)
		var rank_b := _lifecycle_rank(b.lifecycle)
		if rank_a != rank_b:
			return rank_a < rank_b
		var category_a := CatalogTaxonomy.category_rank(a.catalog_category)
		var category_b := CatalogTaxonomy.category_rank(b.catalog_category)
		if category_a != category_b:
			return category_a < category_b
		if a.catalog_order != b.catalog_order:
			return a.catalog_order < b.catalog_order
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0
	)
	return manifests


func official_manifests() -> Array[TileLibraryManifest]:
	var result: Array[TileLibraryManifest] = []
	var prefix := ProjectSettings.globalize_path(official_manifest_directory)
	for manifest in manifests:
		if ProjectSettings.globalize_path(manifest.resource_path).begins_with(prefix):
			result.append(manifest)
	return result


func official_manifest(tile_id: String) -> TileLibraryManifest:
	for manifest in official_manifests():
		if manifest.tile_id == tile_id:
			return manifest
	return null


func is_user_draft(manifest: TileLibraryManifest) -> bool:
	return manifest != null and _is_under(
		manifest.resource_path, draft_manifest_directory
	)


func load_recipe(manifest: TileLibraryManifest) -> TileKitPreset:
	if manifest == null or not manifest.is_editable_recipe():
		return null
	return ResourceLoader.load(
		manifest.recipe_path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as TileKitPreset


func new_manifest_from(
	preset: TileKitPreset,
	tile_id := "",
	display_name := "New Procedural Tile"
) -> TileLibraryManifest:
	var manifest := TileLibraryManifest.new()
	manifest.tile_id = tile_id
	manifest.display_name = display_name
	manifest.source_kind = TileLibraryManifest.SOURCE_PROCEDURAL
	manifest.lifecycle = TileLibraryManifest.LIFECYCLE_DRAFT
	manifest.visibility = TileLibraryManifest.VISIBILITY_ACTIVE
	manifest.separate_tiles = preset != null and preset.separate_tiles
	manifest.created_at = _timestamp()
	manifest.updated_at = manifest.created_at
	return manifest


func save_draft(
	working: TileLibraryManifest,
	preset: TileKitPreset
) -> Dictionary:
	var guard := _guard_mutation()
	if not guard.is_empty():
		return _failure(guard)
	var candidate := working.duplicate_manifest()
	candidate.lifecycle = TileLibraryManifest.LIFECYCLE_DRAFT
	candidate.visibility = TileLibraryManifest.VISIBILITY_HIDDEN
	candidate.separate_tiles = preset != null and preset.separate_tiles
	candidate.updated_at = _timestamp()
	if candidate.created_at.is_empty():
		candidate.created_at = candidate.updated_at
	var errors := candidate.validation_errors()
	# A recipe path is assigned by this operation, so validate everything else.
	for index in range(errors.size() - 1, -1, -1):
		if errors[index] == "Procedural tiles require a .tres recipe.":
			errors.remove_at(index)
	if preset == null:
		errors.append("A procedural draft requires an editable recipe.")
	if not errors.is_empty():
		return _failure_array(errors)
	_ensure_directories()
	var recipe_path := "%s/%s.tres" % [draft_recipe_directory, candidate.tile_id]
	var manifest_path := "%s/%s.tres" % [draft_manifest_directory, candidate.tile_id]
	candidate.recipe_path = recipe_path
	var recipe_error := ResourceSaver.save(preset.duplicate_preset(), recipe_path)
	if recipe_error != OK:
		return _failure("Draft recipe save failed: %s" % error_string(recipe_error))
	var manifest_error := ResourceSaver.save(candidate, manifest_path)
	if manifest_error != OK:
		return _failure("Draft manifest save failed: %s" % error_string(manifest_error))
	reload()
	return {"ok": true, "manifest": _load_manifest(manifest_path)}


func publish_new(
	working: TileLibraryManifest,
	preset: TileKitPreset
) -> Dictionary:
	var existing := official_manifest(working.tile_id)
	if existing != null and existing.lifecycle != TileLibraryManifest.LIFECYCLE_DRAFT:
		return _failure("Official tile '%s' already exists; use Overwrite." % working.tile_id)
	return _publish(working, preset, existing, false)


func overwrite(
	working: TileLibraryManifest,
	preset: TileKitPreset
) -> Dictionary:
	var existing := official_manifest(working.tile_id)
	if existing == null:
		return _failure("No official tile '%s' exists to overwrite." % working.tile_id)
	if working.tile_id != existing.tile_id:
		return _failure("Overwrite cannot change a stable tile ID.")
	return _publish(working, preset, existing, true)


func archive(tile_id: String) -> Dictionary:
	var guard := _guard_mutation()
	if not guard.is_empty():
		return _failure(guard)
	var existing := official_manifest(tile_id)
	if existing == null:
		return _failure("Only official tiles can be archived.")
	if existing.lifecycle == TileLibraryManifest.LIFECYCLE_ARCHIVED:
		return _failure("Tile '%s' is already archived." % tile_id)
	var candidate := existing.duplicate_manifest()
	candidate.lifecycle = TileLibraryManifest.LIFECYCLE_ARCHIVED
	candidate.visibility = TileLibraryManifest.VISIBILITY_HIDDEN
	candidate.revision += 1
	candidate.updated_at = _timestamp()
	var project := _project_with_replacement(candidate)
	var validation := compiler.build_candidate(project)
	if not bool(validation.get("ok", false)):
		return validation
	var snapshots := _snapshot_publication(
		existing, existing.resource_path, existing.recipe_path
	)
	var save_error := ResourceSaver.save(candidate, existing.resource_path)
	if save_error != OK:
		return _failure("Archive manifest save failed: %s" % error_string(save_error))
	project = _project_with_replacement(_load_manifest(existing.resource_path))
	var compiled := compiler.compile(project)
	if not bool(compiled.get("ok", false)):
		_rollback(snapshots, PackedStringArray([existing.resource_path]))
		return compiled
	reload()
	return {"ok": true, "manifest": official_manifest(tile_id)}


func hard_delete(tile_id: String) -> Dictionary:
	var guard := _guard_mutation()
	if not guard.is_empty():
		return _failure(guard)
	var existing := official_manifest(tile_id)
	if existing == null:
		return _failure("No official tile '%s' exists." % tile_id)
	var dependencies := dependency_scanner.dependencies_for(tile_id, manifests)
	if not dependencies.is_empty():
		return {
			"ok": false,
			"errors": PackedStringArray([
				"Hard delete blocked; archive instead. Dependencies: %s"
				% "; ".join(dependencies)
			]),
			"dependencies": dependencies,
		}
	var remaining: Array[TileLibraryManifest] = []
	for manifest in official_manifests():
		if manifest.tile_id != tile_id:
			remaining.append(manifest)
	var validation := compiler.build_candidate(
		remaining, PackedStringArray([tile_id])
	)
	if not bool(validation.get("ok", false)):
		return validation
	var snapshots := _snapshot_publication(
		existing, existing.resource_path, existing.recipe_path
	)
	var compiled := compiler.compile(remaining, PackedStringArray([tile_id]))
	if not bool(compiled.get("ok", false)):
		return compiled
	var failures := PackedStringArray()
	_remove_file(existing.resource_path, failures)
	if existing.source_kind == TileLibraryManifest.SOURCE_PROCEDURAL:
		_remove_file(existing.recipe_path, failures)
		failures.append_array(baker.remove_bake(tile_id))
	if not failures.is_empty():
		_rollback(snapshots, PackedStringArray())
		return {"ok": false, "errors": failures}
	reload()
	return {"ok": true}


func delete_draft(manifest: TileLibraryManifest) -> Dictionary:
	var guard := _guard_mutation()
	if not guard.is_empty():
		return _failure(guard)
	if manifest == null or not _is_under(manifest.resource_path, draft_manifest_directory):
		return _failure("Only user drafts can be deleted without publication checks.")
	var snapshot: Dictionary = {}
	for path in [manifest.resource_path, manifest.recipe_path]:
		var absolute := ProjectSettings.globalize_path(path)
		snapshot[path] = (
			FileAccess.get_file_as_bytes(absolute)
			if FileAccess.file_exists(absolute)
			else null
		)
	var failures := PackedStringArray()
	_remove_file(manifest.resource_path, failures)
	_remove_file(manifest.recipe_path, failures)
	if not failures.is_empty():
		_rollback(snapshot, PackedStringArray())
	reload()
	return {"ok": failures.is_empty(), "errors": failures}


func can_mutate_official() -> bool:
	if mutation_override >= 0:
		return mutation_override == 1
	return Engine.is_editor_hint() or OS.is_debug_build() or OS.has_feature("editor")


func _publish(
	working: TileLibraryManifest,
	preset: TileKitPreset,
	existing: TileLibraryManifest,
	is_overwrite: bool
) -> Dictionary:
	var guard := _guard_mutation()
	if not guard.is_empty():
		return _failure(guard)
	var candidate := working.duplicate_manifest()
	if candidate.source_kind == TileLibraryManifest.SOURCE_PROCEDURAL and preset == null:
		return _failure("Procedural publication requires a recipe.")
	candidate.lifecycle = TileLibraryManifest.LIFECYCLE_PUBLISHED
	if candidate.visibility == TileLibraryManifest.VISIBILITY_HIDDEN:
		candidate.visibility = TileLibraryManifest.VISIBILITY_PREVIEW
	candidate.revision = (existing.revision + 1) if existing != null else 1
	candidate.updated_at = _timestamp()
	if candidate.created_at.is_empty():
		candidate.created_at = candidate.updated_at
	if candidate.published_at.is_empty():
		candidate.published_at = candidate.updated_at
	var recipe_path := "%s/%s.tres" % [official_recipe_directory, candidate.tile_id]
	var manifest_path := "%s/%s.tres" % [official_manifest_directory, candidate.tile_id]
	if candidate.source_kind == TileLibraryManifest.SOURCE_PROCEDURAL:
		candidate.recipe_path = recipe_path
		candidate.separate_tiles = preset.separate_tiles
	var errors := candidate.validation_errors()
	if not errors.is_empty():
		return _failure_array(errors)
	# Build in memory first. This catches missing builders and invalid geometry
	# before an official resource or catalog file is touched.
	if candidate.source_kind == TileLibraryManifest.SOURCE_PROCEDURAL:
		var preflight := _preflight_recipe(preset)
		if not bool(preflight.get("ok", false)):
			return preflight
		candidate.baked_roles = preflight["roles"]
	var project := _project_with_replacement(candidate)
	var validation := compiler.build_candidate(project)
	if not bool(validation.get("ok", false)):
		return validation
	_ensure_directories()
	var snapshots := _snapshot_publication(candidate, manifest_path, recipe_path)
	var written := PackedStringArray()
	if candidate.source_kind == TileLibraryManifest.SOURCE_PROCEDURAL:
		var recipe_error := ResourceSaver.save(preset.duplicate_preset(), recipe_path)
		if recipe_error != OK:
			return _failure("Official recipe save failed: %s" % error_string(recipe_error))
		written.append(recipe_path)
		var bake_result := baker.bake(preset, candidate.tile_id)
		if not bool(bake_result.get("ok", false)):
			_rollback(snapshots, written + bake_result.get("written", PackedStringArray()))
			return bake_result
		candidate.baked_roles = bake_result["roles"]
		written.append_array(bake_result["written"])
	var manifest_error := ResourceSaver.save(candidate, manifest_path)
	if manifest_error != OK:
		_rollback(snapshots, written)
		return _failure("Official manifest save failed: %s" % error_string(manifest_error))
	written.append(manifest_path)
	# Reload the just-saved manifest so source_manifest in the compiled catalog
	# is the actual project path rather than a draft resource path.
	var saved_candidate := _load_manifest(manifest_path)
	project = _project_with_replacement(saved_candidate)
	var compiled := compiler.compile(project)
	if not bool(compiled.get("ok", false)):
		_rollback(snapshots, written)
		return compiled
	var cleanup_warnings := _remove_promoted_user_drafts(candidate.tile_id)
	reload()
	return {
		"ok": true,
		"manifest": official_manifest(candidate.tile_id),
		"overwrote": is_overwrite,
		"warnings": cleanup_warnings,
	}


func _preflight_recipe(preset: TileKitPreset) -> Dictionary:
	var generator := TileKitGenerator.new()
	generator.preset = preset
	generator.rebuild()
	var scenes := generator.bake_role_scenes()
	var stats := generator.statistics()
	var roles := PackedStringArray()
	for role in scenes:
		roles.append(String(role))
	roles.sort()
	generator.free()
	var errors := PackedStringArray()
	if int(stats.get("triangles", 0)) <= 0:
		errors.append("Recipe generated no triangles.")
	if not roles.has("base") or not roles.has("surface"):
		errors.append("Recipe must generate base and surface roles.")
	return {"ok": errors.is_empty(), "errors": errors, "roles": roles}


func _project_with_replacement(candidate: TileLibraryManifest) -> Array[TileLibraryManifest]:
	var result: Array[TileLibraryManifest] = []
	var replaced := false
	for manifest in official_manifests():
		if manifest.tile_id == candidate.tile_id:
			if not replaced:
				result.append(candidate)
				replaced = true
		else:
			result.append(manifest)
	if not replaced:
		result.append(candidate)
	return result


func _snapshot_publication(
	candidate: TileLibraryManifest,
	manifest_path: String,
	recipe_path: String
) -> Dictionary:
	var paths := PackedStringArray([
		manifest_path, compiler.catalog_path, compiler.tuning_path,
	])
	if candidate.source_kind == TileLibraryManifest.SOURCE_PROCEDURAL:
		paths.append(recipe_path)
		paths.append_array(baker.baked_paths_for(candidate.tile_id))
	var snapshot: Dictionary = {}
	for path in paths:
		var absolute := ProjectSettings.globalize_path(path)
		snapshot[path] = (
			FileAccess.get_file_as_bytes(absolute)
			if FileAccess.file_exists(absolute)
			else null
		)
	return snapshot


func _rollback(snapshot: Dictionary, written: PackedStringArray) -> void:
	for path in written:
		if not snapshot.has(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for path in snapshot:
		var absolute := ProjectSettings.globalize_path(String(path))
		var bytes: Variant = snapshot[path]
		if bytes == null:
			if FileAccess.file_exists(absolute):
				DirAccess.remove_absolute(absolute)
			continue
		DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		var file := FileAccess.open(absolute, FileAccess.WRITE)
		if file != null:
			file.store_buffer(bytes as PackedByteArray)


func _load_manifests_from(directory_path: String) -> void:
	var absolute := ProjectSettings.globalize_path(directory_path)
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	for file in directory.get_files():
		if not file.ends_with(".tres"):
			continue
		var manifest := _load_manifest("%s/%s" % [directory_path, file])
		if manifest != null:
			manifests.append(manifest)


func _load_manifest(path: String) -> TileLibraryManifest:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) \
		as TileLibraryManifest


func _ensure_directories() -> void:
	for path in [
		official_recipe_directory, official_manifest_directory,
		draft_recipe_directory, draft_manifest_directory,
	]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _remove_file(path: String, failures: PackedStringArray) -> void:
	if path.is_empty():
		return
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return
	var error := DirAccess.remove_absolute(absolute)
	if error != OK:
		failures.append("%s: %s" % [path, error_string(error)])


func _remove_promoted_user_drafts(tile_id: String) -> PackedStringArray:
	var warnings := PackedStringArray()
	for manifest in manifests:
		if manifest.tile_id != tile_id or not is_user_draft(manifest):
			continue
		_remove_file(manifest.resource_path, warnings)
		_remove_file(manifest.recipe_path, warnings)
	return warnings


func _is_under(path: String, root: String) -> bool:
	return ProjectSettings.globalize_path(path).begins_with(
		ProjectSettings.globalize_path(root) + "/"
	)


func _guard_mutation() -> String:
	return "Tile Library is read-only in release builds." \
		if not can_mutate_official() else ""


func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}


func _failure_array(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "errors": errors}


func _timestamp() -> String:
	return Time.get_datetime_string_from_system(true, true)


func _lifecycle_rank(lifecycle: String) -> int:
	match lifecycle:
		TileLibraryManifest.LIFECYCLE_PUBLISHED:
			return 0
		TileLibraryManifest.LIFECYCLE_DRAFT:
			return 1
	return 2
