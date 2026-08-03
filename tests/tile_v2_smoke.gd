extends SceneTree
## Headless smoke build of every V2 prototype: parse, compose, mesh, stats.
##   godot --headless --path . --script tests/tile_v2_smoke.gd


func _init() -> void:
	var failures := 0
	for tile_id in TileV2Library.prototype_ids():
		var recipe := TileV2Library.recipe(tile_id)
		if recipe == null:
			print("FAIL: no recipe for %s" % tile_id)
			failures += 1
			continue
		var built := TileV2Generator.build_meshes(recipe)
		var stats: Dictionary = built["stats"]
		var surface: ArrayMesh = built["surface"]
		var base: ArrayMesh = built["base"]
		print("%s: tris=%d (surface %d / base %d) pieces=%d h=[%.3f..%.3f] surfaces=%d+%d"
			% [tile_id, stats["triangles"], stats["surface_triangles"],
			stats["base_triangles"], stats["pieces"], stats["min_height"],
			stats["max_height"], surface.get_surface_count(),
			base.get_surface_count()])
		if stats["triangles"] <= 0:
			print("FAIL: %s produced no triangles" % tile_id)
			failures += 1
	if failures == 0:
		print("TILE V2 SMOKE PASSED")
	else:
		print("TILE V2 SMOKE FAILED (%d)" % failures)
	quit(0 if failures == 0 else 1)
