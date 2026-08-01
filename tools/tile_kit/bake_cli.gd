extends SceneTree
## Headless bake of the Reference Clean Grass preset into the layer scenes the
## game loads for tile_kit_grass. The F8 studio's Bake To Game button runs the
## same collection logic; this exists so a fresh checkout — or an agent — can
## produce the baked assets without opening an editor.
##
##   godot --headless --path . --script tools/tile_kit/bake_cli.gd

const OUTPUT_DIRECTORY := "res://tools/tile_kit/baked"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
		OUTPUT_DIRECTORY + "/materials"))
	for key: String in TileKitPalette.COLORS:
		var material := TileKitPalette.material(key)
		var material_path := "%s/materials/%s.tres" % [OUTPUT_DIRECTORY, key]
		if ResourceSaver.save(material, material_path) == OK:
			material.take_over_path(material_path)
		else:
			push_error("material save failed: %s" % key)

	var failed := false
	var stats: Dictionary = {}
	for mask in 16:
		var generator := TileKitGenerator.new()
		generator.preset = TileKitPreset.reference_clean_grass()
		generator.neighbour_mask = mask
		get_root().add_child(generator)
		await process_frame
		var scenes := generator.bake_role_scenes()
		if mask == 0:
			stats = generator.statistics()
		for role: String in scenes:
			if mask > 0 and role == "detail":
				continue
			var asset_id := "tile_kit_grass_%s" % role
			if mask > 0:
				asset_id += "_n%02d" % mask
			var path := "%s/%s.tscn" % [OUTPUT_DIRECTORY, asset_id]
			var error := ResourceSaver.save(scenes[role], path)
			print("%s -> %s (%s)" % [asset_id, path, error_string(error)])
			failed = failed or error != OK
		generator.free()
	print("BAKE %s · %s" % [
		"FAILED" if failed else "COMPLETE",
		JSON.stringify(stats),
	])
	quit(1 if failed else 0)
