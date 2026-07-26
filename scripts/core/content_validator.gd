class_name ContentValidator
extends RefCounted
## Production content integrity checks that require the imported asset catalog.


static func validate(registries: Registries) -> PackedStringArray:
	var errors := PackedStringArray()
	for def: Defs.TileDefinition in registries.tiles.values():
		var asset_id := "tile_water_floor" if def.render_profile == "continuous_water" else def.asset_id
		_require_asset(errors, "tile", def.id, asset_id)
	for def: Defs.StructureDefinition in registries.structures.values():
		_require_asset(errors, "structure", def.id, def.asset_id)
	for def: Defs.ItemDefinition in registries.items.values():
		if def.asset_id != "":
			_require_asset(errors, "item", def.id, def.asset_id)
	for def: Defs.EnemyDefinition in registries.enemies.values():
		_require_asset(errors, "enemy", def.id, def.asset_id)
	for def: Defs.LandmarkDefinition in registries.landmarks.values():
		_require_asset(errors, "landmark", def.id, def.asset_id)
		if def.reclaimed_dressing_asset != "":
			_require_asset(
				errors,
				"landmark dressing",
				def.id,
				def.reclaimed_dressing_asset
			)
	return errors


static func _require_asset(
	errors: PackedStringArray,
	kind: String,
	content_id: String,
	asset_id: String
) -> void:
	if asset_id == "":
		errors.append("%s %s has no asset id" % [kind, content_id])
	elif AssetLibrary.resolve_path(asset_id) == "":
		errors.append(
			"%s %s references missing asset %s" % [kind, content_id, asset_id]
		)
