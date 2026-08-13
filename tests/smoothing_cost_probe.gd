extends SceneTree
## Times AssetLibrary.instantiate across a broad sample with the game-wide
## smoothing default on and off, so the cost of smooth-shading every model is
## a measured number rather than a hope.

const SAMPLE := 60


func _init() -> void:
	var palette := load("res://assets/palettes/gg_material_palette.tres") as CozyPalette
	var directory := DirAccess.open("res://assets/3d/reworked")
	var ids: Array[String] = []
	for name in directory.get_files():
		if name.ends_with(".glb") and not name.begins_with("tile_"):
			ids.append(name.get_basename())
	ids.sort()
	var step := maxi(1, ids.size() / SAMPLE)
	var sample: Array[String] = []
	for index in range(0, ids.size(), step):
		sample.append(ids[index])

	# Warm Godot's resource cache first; otherwise the first pass measured
	# scene loading and made smoothing look free.
	var warm := AssetLibrary.new(MaterialLibrary.new(palette))
	warm.edits.set_default_model_smoothing(0.0)
	for asset_id in sample:
		var warmed := warm.instantiate(asset_id)
		if warmed != null:
			warmed.free()

	for smoothing in [0.0, 0.85]:
		var assets := AssetLibrary.new(MaterialLibrary.new(palette))
		assets.edits.set_default_model_smoothing(smoothing)
		var started := Time.get_ticks_usec()
		var built := 0
		for asset_id in sample:
			var node := assets.instantiate(asset_id)
			if node != null:
				built += 1
				node.free()
		var elapsed := (Time.get_ticks_usec() - started) / 1000.0
		print(
			"smoothing=%.2f  assets=%d  total=%.1fms  per_asset=%.2fms"
			% [smoothing, built, elapsed, elapsed / maxi(built, 1)]
		)
	quit()
