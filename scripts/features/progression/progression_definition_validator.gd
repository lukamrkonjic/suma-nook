class_name ProgressionDefinitionValidator
extends RefCounted
## Feature-owned content contract for progression v2. Registered by
## GameContentCatalog like every feature validator; a violated contract
## blocks atomic publication, so a bad edit can never half-ship.

const ValidationIssueScript := preload(
	"res://scripts/core/content/validation_issue.gd"
)

const REWARD_KINDS := ["tile", "structure", "gear", "note"]
const MILESTONE_KINDS := ["practice", "journal_page"]


static func validate(snapshot, issues: Array) -> void:
	_validate_domains(snapshot, issues)
	_validate_activities(snapshot, issues)
	_validate_milestones(snapshot, issues)
	_validate_recipes(snapshot, issues)
	_validate_tuning_pools(snapshot, issues)


static func _validate_domains(snapshot, issues: Array) -> void:
	var known_families := {}
	for tile in snapshot.tiles.values():
		known_families[tile.family] = true
	var wildcard_count := 0
	var claimed_families := {}
	for domain in snapshot.inspiration_domains.values():
		var source = snapshot.source("inspiration_domains", domain.id)
		if domain.wildcard:
			wildcard_count += 1
			if not domain.tile_families.is_empty():
				_error(
					issues, "domain.wildcard.families", source, "tile_families",
					"wildcard domain '%s' must not claim tile families" % domain.id
				)
		elif domain.tile_families.is_empty():
			_error(
				issues, "domain.families.empty", source, "tile_families",
				"domain '%s' claims no tile families and is not a wildcard" % domain.id
			)
		for family in domain.tile_families:
			if not known_families.has(family):
				_error(
					issues, "domain.family.missing", source,
					"tile_families", "referenced tile family '%s' has no definitions" % family
				)
			if claimed_families.has(family):
				_error(
					issues, "domain.family.duplicate", source, "tile_families",
					"tile family '%s' is claimed by two domains" % family
				)
			claimed_families[family] = true
		for activity_id in domain.activities:
			if not snapshot.skills.has(activity_id):
				_error(
					issues, "domain.activity.missing", source, "activities",
					"referenced activity '%s' does not exist" % activity_id
				)
	if wildcard_count != 1 and not snapshot.inspiration_domains.is_empty():
		_error(
			issues, "domain.wildcard.count", null, "inspiration_domains",
			"exactly one wildcard domain is required (found %d)" % wildcard_count
		)


static func _validate_activities(snapshot, issues: Array) -> void:
	for skill in snapshot.skills.values():
		var source = snapshot.source("skills", skill.id)
		if skill.domain_id == "":
			_error(
				issues, "activity.domain.required", source, "domain",
				"activity '%s' declares no inspiration domain" % skill.id
			)
		elif not snapshot.inspiration_domains.has(skill.domain_id):
			_error(
				issues, "activity.domain.missing", source, "domain",
				"referenced domain '%s' does not exist" % skill.domain_id
			)
		else:
			var domain = snapshot.inspiration_domains[skill.domain_id]
			if not domain.activities.has(skill.id):
				_error(
					issues, "activity.domain.unlisted", source, "domain",
					"domain '%s' does not list activity '%s' back" % [skill.domain_id, skill.id]
				)


static func _validate_milestones(snapshot, issues: Array) -> void:
	for milestone in snapshot.milestones.values():
		var source = snapshot.source("milestones", milestone.id)
		if not MILESTONE_KINDS.has(milestone.kind):
			_error(
				issues, "milestone.kind.unknown", source, "kind",
				"unknown milestone kind '%s'" % milestone.kind
			)
			continue
		if milestone.kind == "practice":
			if not snapshot.skills.has(milestone.activity_id):
				_error(
					issues, "milestone.activity.missing", source, "activity",
					"referenced activity '%s' does not exist" % milestone.activity_id
				)
			if milestone.action_count <= 0:
				_error(
					issues, "milestone.actions.invalid", source, "action_count",
					"practice milestone '%s' needs a positive action_count" % milestone.id
				)
		if milestone.kind == "journal_page":
			if milestone.category == "" or milestone.entries.is_empty():
				_error(
					issues, "milestone.page.incomplete", source, "entries",
					"journal milestone '%s' needs a category and entries" % milestone.id
				)
		for index in milestone.rewards.size():
			var reward: Dictionary = milestone.rewards[index]
			var kind := String(reward.get("kind", "note"))
			var reward_id := String(reward.get("id", ""))
			if not REWARD_KINDS.has(kind):
				_error(
					issues, "milestone.reward.kind", source,
					"rewards[%d].kind" % index, "unknown reward kind '%s'" % kind
				)
				continue
			var known := true
			match kind:
				"tile": known = snapshot.tiles.has(reward_id)
				"structure": known = snapshot.structures.has(reward_id)
				"gear": known = snapshot.items.has(reward_id)
			if not known:
				_error(
					issues, "milestone.reward.missing", source,
					"rewards[%d].id" % index,
					"referenced %s '%s' does not exist" % [kind, reward_id]
				)
			var active_tile_ids: Variant = snapshot.tuning.get("active_tile_ids", [])
			if (
				kind == "tile"
				and snapshot.tiles.has(reward_id)
				and active_tile_ids is Array
				and not active_tile_ids.is_empty()
				and not active_tile_ids.has(reward_id)
			):
				_error(
					issues, "milestone.reward.inactive", source,
					"rewards[%d].id" % index,
					"milestone reward tile '%s' is not in active_tile_ids" % reward_id
				)


static func _validate_recipes(snapshot, issues: Array) -> void:
	for recipe in snapshot.recipes.values():
		if recipe.unlock_milestone == "":
			continue
		if not snapshot.milestones.has(recipe.unlock_milestone):
			_error(
				issues, "recipe.milestone.missing",
				snapshot.source("recipes", recipe.id), "unlock_milestone",
				"referenced milestone '%s' does not exist" % recipe.unlock_milestone
			)


static func _validate_tuning_pools(snapshot, issues: Array) -> void:
	for tuning_key in ["first_vision_options", "land_insurance_pool", "starter_land_options"]:
		var pool: Variant = snapshot.tuning.get(tuning_key, [])
		if not pool is Array or pool.is_empty():
			_error(
				issues, "tuning.pool.missing", null,
				"%s/tuning.json %s" % [snapshot.base_path, tuning_key],
				"progression requires a non-empty '%s' tile list" % tuning_key
			)
			continue
		var active_tile_ids: Variant = snapshot.tuning.get("active_tile_ids", [])
		for index in pool.size():
			var tile_id := String(pool[index])
			if not snapshot.tiles.has(tile_id):
				_error(
					issues, "tuning.pool.tile.missing", null,
					"%s/tuning.json %s[%d]" % [snapshot.base_path, tuning_key, index],
					"referenced tile '%s' does not exist" % tile_id
				)
			elif active_tile_ids is Array and not active_tile_ids.has(tile_id):
				_error(
					issues, "tuning.pool.tile.inactive", null,
					"%s/tuning.json %s[%d]" % [snapshot.base_path, tuning_key, index],
					"tile '%s' is not in active_tile_ids" % tile_id
				)


static func _error(issues: Array, code: String, source, field: String, message: String) -> void:
	issues.append(ValidationIssueScript.new(
		ValidationIssueScript.Severity.ERROR, code, source, field, message
	))
