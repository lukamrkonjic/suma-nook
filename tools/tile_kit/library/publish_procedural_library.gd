extends SceneTree
## One-time/repeatable development importer for the file-backed procedural
## library. Project draft recipes become real preview tiles with stable IDs,
## unique bakes, manifests, and compiled runtime definitions.


func _init() -> void:
	var service := TileLibraryService.new()
	if not service.can_mutate_official():
		push_error("Procedural publication is disabled in release builds.")
		quit(1)
		return
	service.reload()
	var pending: Array[TileLibraryManifest] = []
	for manifest in service.official_manifests():
		if (
			manifest.source_kind == TileLibraryManifest.SOURCE_PROCEDURAL
			and manifest.lifecycle == TileLibraryManifest.LIFECYCLE_DRAFT
		):
			pending.append(manifest)
	pending.sort_custom(func(a: TileLibraryManifest, b: TileLibraryManifest) -> bool:
		return a.tile_id < b.tile_id
	)
	var published := 0
	for draft in pending:
		var recipe := service.load_recipe(draft)
		if recipe == null:
			push_error("Missing recipe for %s" % draft.tile_id)
			quit(1)
			return
		var result := service.publish_new(draft, recipe)
		if not bool(result.get("ok", false)):
			for error in result.get("errors", PackedStringArray()):
				push_error("%s: %s" % [draft.tile_id, String(error)])
			quit(1)
			return
		published += 1
		print("PUBLISHED %s" % draft.tile_id)
	print("PROCEDURAL TILE IMPORT COMPLETE — %d new real tiles" % published)
	quit(0)
