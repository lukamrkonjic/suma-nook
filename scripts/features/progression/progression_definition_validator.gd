class_name ProgressionDefinitionValidator
extends RefCounted
## Content contract for discovery progression.

const ValidationIssueScript := preload(
	"res://scripts/core/content/validation_issue.gd"
)
const REWARD_KINDS := ["tile", "structure", "gear", "note"]
const MILESTONE_KINDS := ["practice", "journal_page"]


static func validate(snapshot, issues: Array) -> void:
	_validate_discovery_pools(snapshot, issues)
	_validate_milestones(snapshot, issues)
	_validate_recipes(snapshot, issues)
	_validate_tuning(snapshot, issues)


## Since the fishing rework, discovery pools exist only for the ferry's
## periodic gift: exactly one broad "void"-sourced pool, no local skill pools.
static func _validate_discovery_pools(snapshot, issues: Array) -> void:
	var delivery_count := 0
	for pool: Defs.DiscoveryPoolDefinition in snapshot.discovery_pools.values():
		var source = snapshot.source("discovery_pools", pool.id)
		if pool.source != "void":
			_error(
				issues, "discovery.source.invalid", source, "source",
				"pool '%s' has retired source '%s' — local skill pools no longer exist"
				% [pool.id, pool.source]
			)
			continue
		delivery_count += 1
		if pool.skill_id != "" or not pool.context_tags.is_empty():
			_error(
				issues, "discovery.void.context", source, "skill",
				"delivery pool '%s' cannot declare local context" % pool.id
			)
		if pool.rewards.is_empty():
			_error(
				issues, "discovery.rewards.empty", source, "rewards",
				"pool '%s' has no rewards" % pool.id
			)
		for index in pool.rewards.size():
			var reward: Dictionary = pool.rewards[index]
			var kind := String(reward.get("kind", ""))
			var reward_id := String(reward.get("id", ""))
			var known: bool = (
				kind == "tile" and snapshot.tiles.has(reward_id)
			) or (
				kind == "structure" and snapshot.structures.has(reward_id)
			)
			if not known:
				_error(
					issues, "discovery.reward.missing", source,
					"rewards[%d]" % index,
					"unknown %s reward '%s'" % [kind, reward_id]
				)
			if float(reward.get("weight", 0.0)) <= 0.0:
				_error(
					issues, "discovery.reward.weight", source,
					"rewards[%d].weight" % index,
					"reward weight must be positive"
				)
	if delivery_count != 1:
		_error(
			issues, "discovery.void.count", null, "discovery_pools",
			"exactly one broad delivery pool is required (found %d)" % delivery_count
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
		if (
			milestone.kind == "journal_page"
			and (milestone.category == "" or milestone.entries.is_empty())
		):
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
					"rewards[%d].kind" % index,
					"unknown reward kind '%s'" % kind
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


static func _validate_recipes(snapshot, issues: Array) -> void:
	for recipe in snapshot.recipes.values():
		if (
			recipe.unlock_milestone != ""
			and not snapshot.milestones.has(recipe.unlock_milestone)
		):
			_error(
				issues, "recipe.milestone.missing",
				snapshot.source("recipes", recipe.id), "unlock_milestone",
				"referenced milestone '%s' does not exist" % recipe.unlock_milestone
			)


static func _validate_tuning(snapshot, issues: Array) -> void:
	var starter_pool: Variant = snapshot.tuning.get("starter_land_options", [])
	if not starter_pool is Array or starter_pool.is_empty():
		_error(
			issues, "tuning.starter.missing", null, "starter_land_options",
			"progression requires starter land options"
		)


static func _error(
	issues: Array,
	code: String,
	source,
	field: String,
	message: String
) -> void:
	issues.append(ValidationIssueScript.new(
		ValidationIssueScript.Severity.ERROR,
		code,
		source,
		field,
		message
	))
