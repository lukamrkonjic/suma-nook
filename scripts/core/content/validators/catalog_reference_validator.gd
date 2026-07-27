class_name CatalogReferenceValidator
extends RefCounted
## Cross-definition checks live outside the registry loader so new feature
## validators can be composed without growing a single central method.

const ValidationIssueScript := preload("res://scripts/core/content/validation_issue.gd")


static func validate(snapshot, issues: Array) -> void:
	var known_families := {}
	for definition: Defs.TileDefinition in snapshot.tiles.values():
		known_families[definition.family] = true
		_reference(
			issues, snapshot, "tiles", definition.id, "anchor", definition.anchor_id,
			"anchors", snapshot.anchors
		)
		for skill_id: String in definition.unlock_level:
			_reference(
				issues, snapshot, "tiles", definition.id,
				"unlock_level.%s" % skill_id, skill_id, "skills", snapshot.skills
			)
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
	for definition: Defs.SkillDefinition in snapshot.skills.values():
		_reference(
			issues, snapshot, "skills", definition.id, "loot_table", definition.loot_table,
			"loot_tables", snapshot.loot_tables
		)
		_reference(
			issues, snapshot, "skills", definition.id, "rare_table", definition.rare_table,
			"loot_tables", snapshot.loot_tables
		)
		for index in definition.direct_tile_reward_pool.size():
			_reference(
				issues, snapshot, "skills", definition.id,
				"direct_tile_reward_pool[%d]" % index,
				definition.direct_tile_reward_pool[index], "tiles", snapshot.tiles, false
			)
		for index in definition.unlocks.size():
			var unlock: Dictionary = definition.unlocks[index]
			var kind := String(unlock.get("kind", ""))
			var content_id := String(unlock.get("id", ""))
			var target: Dictionary = {}
			var target_kind := ""
			match kind:
				"tile", "tile_reward":
					target = snapshot.tiles
					target_kind = "tiles"
				"structure_reward":
					target = snapshot.structures
					target_kind = "structures"
				"recipe":
					target = snapshot.recipes
					target_kind = "recipes"
				"anchor_upgrade":
					target = snapshot.anchors
					target_kind = "anchors"
			if target_kind != "":
				_reference(
					issues, snapshot, "skills", definition.id,
					"unlocks[%d].id" % index, content_id, target_kind, target, false
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
			or definition.output_id == "reroll_charge"
		)
		if not output_known:
			issues.append(ValidationIssueScript.new(
				ValidationIssueScript.Severity.ERROR, "recipe.output.missing",
				snapshot.source("recipes", definition.id), "output",
				"referenced output '%s' does not exist" % definition.output_id
			))
	for definition: Defs.ParcelDefinition in snapshot.parcels.values():
		_reference(
			issues, snapshot, "parcels", definition.id, "id", definition.id,
			"items", snapshot.items, false
		)
		for family: String in definition.families:
			if not known_families.has(family):
				issues.append(ValidationIssueScript.new(
					ValidationIssueScript.Severity.ERROR, "parcel.family.missing",
					snapshot.source("parcels", definition.id),
					"families.%s" % family,
					"referenced tile family '%s' has no definitions" % family
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
	for index in snapshot.tuning.get("guaranteed_first_parcel_options", []).size():
		var tile_id := String(snapshot.tuning["guaranteed_first_parcel_options"][index])
		if not snapshot.tiles.has(tile_id):
			issues.append(ValidationIssueScript.new(
				ValidationIssueScript.Severity.ERROR, "tuning.guaranteed_option.missing", null,
				"%s/tuning.json guaranteed_first_parcel_options[%d]"
				% [snapshot.base_path, index],
				"referenced tile '%s' does not exist" % tile_id
			))


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
