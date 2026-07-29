class_name ContentValidator
extends RefCounted
## Production content integrity checks that require the imported asset catalog.

const ValidationIssueScript := preload("res://scripts/core/content/validation_issue.gd")


static func validate(registries: Registries) -> PackedStringArray:
	var issues: Array = []
	_validate_definitions(
		registries.tiles,
		registries.structures,
		registries.items,
		registries.enemies,
		registries.landmarks,
		issues,
		func(kind: String, id: String):
			return registries.definition_source(kind, id)
	)
	var errors := PackedStringArray()
	for issue in issues:
		if issue.severity == ValidationIssueScript.Severity.ERROR:
			errors.append(issue.format())
	return errors


static func validate_snapshot(snapshot, issues: Array) -> void:
	_validate_definitions(
		snapshot.tiles,
		snapshot.structures,
		snapshot.items,
		snapshot.enemies,
		snapshot.landmarks,
		issues,
		func(kind: String, id: String):
			return snapshot.source(kind, id)
	)


static func _validate_definitions(
	tiles: Dictionary,
	structures: Dictionary,
	items: Dictionary,
	enemies: Dictionary,
	landmarks: Dictionary,
	issues: Array,
	source_for: Callable
) -> void:
	for def: Defs.TileDefinition in tiles.values():
		if def.render_profile == "continuous_water":
			_require_asset(issues, "tiles", def.id, "tile_water_floor", source_for)
		elif def.uses_layered_visual():
			for index in def.visual_layers.size():
				var layer: Defs.TileVisualLayerDefinition = def.visual_layers[index]
				_require_asset(
					issues, "tiles", def.id, layer.asset_id, source_for,
					"layers[%d].asset_id" % index
				)
		else:
			_require_asset(issues, "tiles", def.id, def.asset_id, source_for)
	for def: Defs.StructureDefinition in structures.values():
		_require_asset(issues, "structures", def.id, def.asset_id, source_for)
	for def: Defs.ItemDefinition in items.values():
		if def.asset_id != "":
			_require_asset(issues, "items", def.id, def.asset_id, source_for)
	for def: Defs.EnemyDefinition in enemies.values():
		_require_asset(issues, "enemies", def.id, def.asset_id, source_for)
	for def: Defs.LandmarkDefinition in landmarks.values():
		_require_asset(issues, "landmarks", def.id, def.asset_id, source_for)
		if def.reclaimed_dressing_asset != "":
			_require_asset(
				issues,
				"landmarks",
				def.id,
				def.reclaimed_dressing_asset,
				source_for,
				"reclaimed_dressing_asset"
			)


static func _require_asset(
	issues: Array,
	kind: String,
	content_id: String,
	asset_id: String,
	source_for: Callable,
	field: String = "asset_id"
) -> void:
	if asset_id == "":
		issues.append(ValidationIssueScript.new(
			ValidationIssueScript.Severity.ERROR, "asset.required",
			source_for.call(kind, content_id), field,
			"asset id must not be empty"
		))
	elif AssetLibrary.resolve_path(asset_id) == "":
		issues.append(ValidationIssueScript.new(
			ValidationIssueScript.Severity.ERROR, "asset.missing",
			source_for.call(kind, content_id), field,
			"referenced asset '%s' does not exist" % asset_id
		))
