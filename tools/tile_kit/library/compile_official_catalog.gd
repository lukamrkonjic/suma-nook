extends SceneTree
## Validates and compiles official manifests into the runtime JSON catalog.
## This is the repeatable CI/editor equivalent of the publish pipeline's final
## step; release builds remain read-only.
##
## godot --headless --path . --script \
##   tools/tile_kit/library/compile_official_catalog.gd


func _init() -> void:
	var service := TileLibraryService.new()
	if not service.can_mutate_official():
		push_error("Official catalog compilation is disabled in release builds.")
		quit(1)
		return
	service.reload()
	var official := service.official_manifests()
	var result := service.compiler.compile(official)
	if not bool(result.get("ok", false)):
		for error in result.get("errors", PackedStringArray()):
			push_error(String(error))
		quit(1)
		return
	print("OFFICIAL TILE CATALOG COMPILED — %d manifests" % official.size())
	quit(0)
