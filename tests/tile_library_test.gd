extends SceneTree
## Isolated contract test for the official Tile Library content lifecycle.

const TEST_ROOT := "user://tile_library_contract"
const TEST_ID := "tile_test_library_dune"

var _failures: Array[String] = []
var _checks := 0


func _init() -> void:
	_run()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _run() -> void:
	_remove_test_root()
	_check_official_sources()
	_check_compiler_candidate()
	_check_mutation_guard()
	_check_crud_lifecycle()
	_remove_test_root()
	if _failures.is_empty():
		print("TILE LIBRARY TEST PASSED — %d checks" % _checks)
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: %s" % failure)
	printerr("TILE LIBRARY TEST FAILED — %d/%d" % [
		_failures.size(), _checks,
	])
	quit(1)


func _check_official_sources() -> void:
	_check(TileKitPreset.OFFICIAL_RECIPES.size() == 21, "21 recipes are registered")
	for entry in TileKitPreset.OFFICIAL_RECIPES:
		var tile_id := String(entry[1])
		var path := "%s/%s.tres" % [
			TileKitPreset.OFFICIAL_RECIPE_DIRECTORY, tile_id,
		]
		_check(ResourceLoader.exists(path), "%s has a file-backed recipe" % tile_id)
		var preset := TileKitPreset.make_built_in(String(entry[0]))
		_check(preset != null, "%s loads through the compatibility API" % tile_id)
	var service := TileLibraryService.new()
	service.reload()
	_check(service.official_manifests().size() >= 56, "official manifest library is populated")
	var catalog := _read_json("res://data/tiles.json")
	var procedural_count := 0
	for raw in catalog.get("tiles", []):
		var tile_id := String((raw as Dictionary).get("id", ""))
		if String((raw as Dictionary).get("source_kind", "")) \
				== TileLibraryManifest.SOURCE_PROCEDURAL:
			procedural_count += 1
		_check(
			service.official_manifest(tile_id) != null,
			"runtime tile %s has an authoritative manifest" % tile_id
		)
	_check(catalog.get("tiles", []).size() == 56, "all 56 official tiles are real runtime tiles")
	_check(procedural_count == 21, "all 21 procedural recipes are real runtime tiles")
	for template in TileTemplateLibrary.TEMPLATES:
		_check(
			not String(template["id"]).begins_with("tile_"),
			"%s is a generic template, not a game tile" % template["name"]
		)
	var asset_studio_source := FileAccess.get_file_as_string(
		"res://scripts/ui/asset_viewer.gd"
	)
	_check(
		"AssetViewerTabTileKit" not in asset_studio_source,
		"Asset Studio has no separate Tile Kit category"
	)
	var palette := load("res://assets/palettes/gg_material_palette.tres") as CozyPalette
	var panel := TileKitPanel.new()
	panel.setup(UiKit.new(palette))
	get_root().add_child(panel)
	var template_select := panel.find_child("TileLibraryTemplate", true, false) \
		as OptionButton
	_check(
		template_select != null
			and template_select.item_count == TileTemplateLibrary.TEMPLATES.size(),
		"new-tile dropdown contains only the generic template library"
	)
	_check(
		panel.find_child("TileLibraryPreset", true, false) == null,
		"tile inspector contains no second real-tile dropdown"
	)
	panel.free()


func _check_compiler_candidate() -> void:
	var service := TileLibraryService.new()
	service.reload()
	var candidate := service.compiler.build_candidate(service.official_manifests())
	_check(
		bool(candidate.get("ok", false)),
		"the complete official manifest set compiles: %s" % _errors(candidate)
	)


func _check_mutation_guard() -> void:
	var service := _isolated_service()
	service.mutation_override = 0
	var preset := TileKitPreset.sand_dune_study()
	var manifest := service.new_manifest_from(preset, TEST_ID, "Guarded Dune")
	var result := service.save_draft(manifest, preset)
	_check(not bool(result.get("ok", false)), "release guard rejects draft writes")


func _check_crud_lifecycle() -> void:
	var service := _isolated_service()
	service.mutation_override = 1
	_prepare_isolated_catalog(service)
	service.reload()
	var original_catalog := FileAccess.get_file_as_bytes(
		ProjectSettings.globalize_path(service.compiler.catalog_path)
	)
	var preset := TileKitPreset.sand_dune_study()
	var manifest := service.new_manifest_from(preset, TEST_ID, "Contract Dune")
	manifest.family = "sand"
	manifest.connection_group = TEST_ID
	manifest.visibility = TileLibraryManifest.VISIBILITY_PREVIEW

	var draft := service.save_draft(manifest, preset)
	_check(bool(draft.get("ok", false)), "Save Draft succeeds: %s" % _errors(draft))
	_check(
		FileAccess.get_file_as_bytes(
			ProjectSettings.globalize_path(service.compiler.catalog_path)
		) == original_catalog,
		"Save Draft has no runtime catalog implication"
	)
	var draft_manifest := draft.get("manifest", null) as TileLibraryManifest
	_check(draft_manifest != null, "saved draft reloads as a resource")

	var published := service.publish_new(draft_manifest, preset)
	_check(bool(published.get("ok", false)), "Publish New succeeds: %s" % _errors(published))
	var official := published.get("manifest", null) as TileLibraryManifest
	_check(official != null and official.revision == 1, "Publish New creates revision 1")
	_check(
		ResourceLoader.exists("%s/%s_surface.tscn" % [
			service.baker.output_directory, TEST_ID,
		]),
		"publication bakes uniquely named runtime scenes"
	)
	_check(
		_catalog_has(service.compiler.catalog_path, TEST_ID),
		"published stable ID is compiled into the runtime catalog"
	)
	service.reload()
	var lingering_drafts := 0
	for item in service.manifests:
		if item.tile_id == TEST_ID and service.is_user_draft(item):
			lingering_drafts += 1
	_check(lingering_drafts == 0, "publishing promotes and removes its user draft")

	official.display_name = "Contract Dune Revised"
	var overwritten := service.overwrite(official, preset)
	_check(bool(overwritten.get("ok", false)), "Overwrite succeeds: %s" % _errors(overwritten))
	official = overwritten.get("manifest", null) as TileLibraryManifest
	_check(
		official != null and official.tile_id == TEST_ID and official.revision == 2,
		"Overwrite preserves the stable ID and increments revision"
	)

	var archived := service.archive(TEST_ID)
	_check(bool(archived.get("ok", false)), "Archive succeeds: %s" % _errors(archived))
	var archived_definition := _catalog_tile(service.compiler.catalog_path, TEST_ID)
	_check(not archived_definition.is_empty(), "Archive retains the runtime definition")
	_check(
		not bool(archived_definition.get("obtainable", true)),
		"Archive makes the retained definition unobtainable"
	)

	var dependency_directory := TEST_ROOT + "/dependencies"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dependency_directory))
	var dependency_path := dependency_directory + "/reference.json"
	_write_json(dependency_path, {"tile": TEST_ID})
	var blocked := service.hard_delete(TEST_ID)
	_check(not bool(blocked.get("ok", false)), "dependencies block Hard Delete")
	_check(
		blocked.get("dependencies", PackedStringArray()).size() > 0,
		"blocked delete reports its dependency locations"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dependency_path))
	var deleted := service.hard_delete(TEST_ID)
	_check(bool(deleted.get("ok", false)), "Hard Delete succeeds when unreferenced: %s" % _errors(deleted))
	_check(
		not _catalog_has(service.compiler.catalog_path, TEST_ID),
		"Hard Delete removes the compiled definition"
	)
	_check(
		not ResourceLoader.exists("%s/%s_surface.tscn" % [
			service.baker.output_directory, TEST_ID,
		]),
		"Hard Delete removes generated scenes"
	)


func _isolated_service() -> TileLibraryService:
	var service := TileLibraryService.new()
	service.official_recipe_directory = TEST_ROOT + "/official/recipes"
	service.official_manifest_directory = TEST_ROOT + "/official/manifests"
	service.draft_recipe_directory = TEST_ROOT + "/drafts/recipes"
	service.draft_manifest_directory = TEST_ROOT + "/drafts/manifests"
	service.compiler.catalog_path = TEST_ROOT + "/catalog.json"
	service.compiler.tuning_path = TEST_ROOT + "/tuning.json"
	service.baker.output_directory = TEST_ROOT + "/baked"
	service.dependency_scanner.data_root = TEST_ROOT + "/dependencies"
	service.dependency_scanner.save_root = TEST_ROOT + "/saves"
	return service


func _prepare_isolated_catalog(service: TileLibraryService) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_ROOT))
	_copy_text("res://data/tiles.json", service.compiler.catalog_path)
	_copy_text("res://data/tuning.json", service.compiler.tuning_path)


func _copy_text(source: String, destination: String) -> void:
	var file := FileAccess.open(
		ProjectSettings.globalize_path(destination), FileAccess.WRITE
	)
	if file != null:
		file.store_string(FileAccess.get_file_as_string(source))


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value))


func _read_json(path: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	return parser.data as Dictionary


func _catalog_has(path: String, tile_id: String) -> bool:
	return not _catalog_tile(path, tile_id).is_empty()


func _catalog_tile(path: String, tile_id: String) -> Dictionary:
	for raw in _read_json(path).get("tiles", []):
		if String((raw as Dictionary).get("id", "")) == tile_id:
			return raw as Dictionary
	return {}


func _errors(result: Dictionary) -> String:
	return "; ".join(result.get("errors", PackedStringArray()))


func _remove_test_root() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_ROOT)
	if not absolute.replace("\\", "/").contains("/tile_library_contract"):
		return
	_remove_tree(absolute)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for child in directory.get_directories():
		_remove_tree(path.path_join(child))
	DirAccess.remove_absolute(path)
