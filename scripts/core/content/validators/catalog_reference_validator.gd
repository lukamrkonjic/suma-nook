class_name CatalogReferenceValidator
extends RefCounted
## Cross-definition checks live outside the registry loader so new feature
## validators can be composed without growing a single central method.

const ValidationIssueScript := preload("res://scripts/core/content/validation_issue.gd")


static func validate(snapshot, issues: Array) -> void:
	for definition: Defs.TileDefinition in snapshot.tiles.values():
		_reference(
			issues, snapshot, "tiles", definition.id, "anchor", definition.anchor_id,
			"anchors", snapshot.anchors
		)
	var active_tile_ids: Variant = snapshot.tuning.get("active_tile_ids", [])
	if not active_tile_ids is Array or active_tile_ids.is_empty():
		issues.append(ValidationIssueScript.new(
			ValidationIssueScript.Severity.ERROR, "tuning.active_tiles.required", null,
			"%s/tuning.json active_tile_ids" % snapshot.base_path,
			"active_tile_ids must contain at least one tile"
		))
	else:
		var seen_active := {}
		for index in active_tile_ids.size():
			var active_tile_id := String(active_tile_ids[index])
			if not snapshot.tiles.has(active_tile_id):
				issues.append(ValidationIssueScript.new(
					ValidationIssueScript.Severity.ERROR, "tuning.active_tile.missing", null,
					"%s/tuning.json active_tile_ids[%d]" % [snapshot.base_path, index],
					"referenced tile '%s' does not exist" % active_tile_id
				))
			elif (
				snapshot.tiles[active_tile_id].surface_kind != "water"
				and not snapshot.tiles[active_tile_id].uses_layered_visual()
			):
				issues.append(ValidationIssueScript.new(
					ValidationIssueScript.Severity.ERROR,
					"tuning.active_tile.not_layered", null,
					"%s/tuning.json active_tile_ids[%d]" % [snapshot.base_path, index],
					"active land tile '%s' must use the layered render profile"
					% active_tile_id
				))
			elif seen_active.has(active_tile_id):
				issues.append(ValidationIssueScript.new(
					ValidationIssueScript.Severity.ERROR, "tuning.active_tile.duplicate", null,
					"%s/tuning.json active_tile_ids[%d]" % [snapshot.base_path, index],
					"tile '%s' appears more than once" % active_tile_id
				))
			seen_active[active_tile_id] = true
	for definition: Defs.StructureDefinition in snapshot.structures.values():
		_reference(
			issues, snapshot, "structures", definition.id, "anchor", definition.anchor_id,
			"anchors", snapshot.anchors
		)
	for definition: Defs.AnchorDefinition in snapshot.anchors.values():
		_reference(
			issues, snapshot, "anchors", definition.id, "skill", definition.skill_id,
			"skills", snapshot.skills, false
		)
		_reference(
			issues, snapshot, "anchors", definition.id, "loot_table", definition.loot_table,
			"loot_tables", snapshot.loot_tables
		)
	for definition: Defs.LootTableDefinition in snapshot.loot_tables.values():
		for index in definition.entries.size():
			_reference(
				issues, snapshot, "loot_tables", definition.id,
				"entries[%d].item" % index, String(definition.entries[index]["item"]),
				"items", snapshot.items, false
			)
	for definition: Defs.RecipeDefinition in snapshot.recipes.values():
		for input_id: String in definition.inputs:
			_reference(
				issues, snapshot, "recipes", definition.id,
				"inputs.%s" % input_id, input_id, "items", snapshot.items, false
			)
		var output_known: bool = (
			snapshot.items.has(definition.output_id)
			or snapshot.structures.has(definition.output_id)
		)
		if not output_known:
			issues.append(ValidationIssueScript.new(
				ValidationIssueScript.Severity.ERROR, "recipe.output.missing",
				snapshot.source("recipes", definition.id), "output",
				"referenced output '%s' does not exist" % definition.output_id
			))
	for definition: Defs.LandmarkDefinition in snapshot.landmarks.values():
		for index in definition.enemies.size():
			_reference(
				issues, snapshot, "landmarks", definition.id,
				"enemies[%d].enemy" % index,
				String(definition.enemies[index].get("enemy", "")),
				"enemies", snapshot.enemies, false
			)
		_reference(
			issues, snapshot, "landmarks", definition.id, "guardian", definition.guardian_id,
			"enemies", snapshot.enemies
		)
		_reference(
			issues, snapshot, "landmarks", definition.id,
			"guardian_reward", definition.guardian_reward, "items", snapshot.items
		)


static func _reference(
	issues: Array,
	snapshot,
	source_kind: String,
	source_id: String,
	field: String,
	target_id: String,
	target_kind: String,
	target: Dictionary,
	optional: bool = true
) -> void:
	if optional and target_id == "":
		return
	if target.has(target_id):
		return
	issues.append(ValidationIssueScript.new(
		ValidationIssueScript.Severity.ERROR, "reference.%s.missing" % target_kind,
		snapshot.source(source_kind, source_id),
		field,
		"referenced %s id '%s' does not exist" % [target_kind, target_id]
	))
