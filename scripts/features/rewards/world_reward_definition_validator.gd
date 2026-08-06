class_name WorldRewardDefinitionValidator
extends RefCounted
## Shared CRUD contract for world-piece rewards, harvest sources, and visitors.

const ValidationIssueScript := preload(
	"res://scripts/core/content/validation_issue.gd"
)
const REWARD_KINDS := ["tile", "structure"]
const REWARD_RARITIES := ["common", "uncommon", "rare"]
const HARVEST_PRESENTATIONS := [
	"clay_tree", "clay_rock", "berry_cluster", "soft_source"
]
const REVEAL_PRESENTERS := ["world_bud"]
const WORLD_BUD_SHAPES := ["acorn", "berry", "box"]


static func validate(snapshot, issues: Array) -> void:
	_validate_reward_pools(snapshot, issues)
	_validate_reward_roll_policies(snapshot, issues)
	_validate_reward_reveal_profiles(snapshot, issues)
	_validate_token_boxes(snapshot, issues)
	_validate_harvest_profiles(snapshot, issues)
	_validate_harvest_sources(snapshot, issues)
	_validate_visitor_presentations(snapshot, issues)
	_validate_visitor_programs(snapshot, issues)


static func _validate_reward_pools(snapshot, issues: Array) -> void:
	for pool: Defs.RewardPoolDefinition in snapshot.reward_pools.values():
		var source = snapshot.source("reward_pools", pool.id)
		_require(
			issues, not pool.entries.is_empty(), "reward.pool.empty", source,
			"entries", "reward pool '%s' needs at least one entry" % pool.id
		)
		for index in pool.entries.size():
			var entry: Dictionary = pool.entries[index]
			var kind := String(entry.get("kind", ""))
			var content_id := String(entry.get("id", ""))
			var field := "entries[%d]" % index
			_require(
				issues, kind in REWARD_KINDS, "reward.entry.kind", source,
				field + ".kind", "unknown world reward kind '%s'" % kind
			)
			var known: bool = (
				snapshot.tiles.has(content_id)
				if kind == "tile"
				else snapshot.structures.has(content_id) if kind == "structure" else false
			)
			_require(
				issues, known, "reward.entry.reference", source, field + ".id",
				"reward entry references missing %s '%s'" % [kind, content_id]
			)
			_require(
				issues, float(entry.get("weight", 0.0)) > 0.0,
				"reward.entry.weight", source, field + ".weight",
				"reward weight must be positive"
			)
			_require(
				issues,
				int(entry.get("min", 0)) >= 1
				and int(entry.get("max", 0)) >= int(entry.get("min", 0)),
				"reward.entry.quantity", source, field + ".min",
				"reward quantity range must start at one and remain ordered"
			)
			_require(
				issues, kind != "structure" or int(entry.get("max", 1)) == 1,
				"reward.entry.structure_quantity", source, field + ".max",
				"structure rewards grant one stable piece per roll"
			)
			_require(
				issues, String(entry.get("rarity", "common")) in REWARD_RARITIES,
				"reward.entry.rarity", source, field + ".rarity",
				"reward rarity must be common, uncommon, or rare"
			)


static func _validate_reward_roll_policies(snapshot, issues: Array) -> void:
	for policy: Defs.RewardRollPolicyDefinition in snapshot.reward_roll_policies.values():
		var source = snapshot.source("reward_roll_policies", policy.id)
		_require(
			issues, policy.recent_memory >= 0,
			"reward.policy.memory", source, "recent_memory",
			"reward policy recent memory cannot be negative"
		)
		_require(
			issues,
			policy.recent_weight_multiplier >= 0.0
			and policy.recent_weight_multiplier <= 1.0,
			"reward.policy.recent_multiplier", source,
			"recent_weight_multiplier",
			"recent reward multiplier must remain between zero and one"
		)
		_require(
			issues, policy.undiscovered_weight_multiplier >= 1.0,
			"reward.policy.discovery_multiplier", source,
			"undiscovered_weight_multiplier",
			"undiscovered rewards may not be penalized"
		)
		_require(
			issues, policy.rare_pity_max_multiplier >= 1.0,
			"reward.policy.pity", source, "rare_pity_max_multiplier",
			"rare pity multiplier must be at least one"
		)


static func _validate_reward_reveal_profiles(snapshot, issues: Array) -> void:
	var palette := PaletteDefinition.shared()
	for profile: Defs.RewardRevealProfileDefinition in snapshot.reward_reveal_profiles.values():
		var source = snapshot.source("reward_reveal_profiles", profile.id)
		_require(
			issues, profile.presenter_type in REVEAL_PRESENTERS,
			"reward.reveal.presenter", source, "presenter_type",
			"unknown reward reveal presenter '%s'" % profile.presenter_type
		)
		_require(
			issues, profile.shell_shape in WORLD_BUD_SHAPES,
			"reward.reveal.shape", source, "shell_shape",
			"unknown World Bud shell shape '%s'" % profile.shell_shape
		)
		for field in ["shell_material", "accent_material", "glow_material"]:
			var material_key := String(profile.get(field))
			_require(
				issues, palette.has_color(material_key),
				"reward.reveal.material", source, field,
				"reward reveal material '%s' is not a semantic palette token"
				% material_key
			)


static func _validate_harvest_profiles(snapshot, issues: Array) -> void:
	for profile: Defs.HarvestProfileDefinition in snapshot.harvest_profiles.values():
		var source = snapshot.source("harvest_profiles", profile.id)
		var pays_tokens := profile.token_id != ""
		var pays_direct_reward := profile.reward_pool_id != ""
		_require(
			issues, pays_tokens != pays_direct_reward,
			"harvest.profile.reward_mode", source, "token",
			"harvest profile '%s' must define exactly one of token or reward_pool"
			% profile.id
		)
		_require(
			issues,
			not pays_direct_reward
			or snapshot.reward_pools.has(profile.reward_pool_id),
			"harvest.profile.reward_pool", source, "reward_pool",
			"harvest profile '%s' references missing reward pool '%s'"
			% [profile.id, profile.reward_pool_id]
		)
		_require(
			issues,
			profile.first_reward_pool_id == ""
			or snapshot.reward_pools.has(profile.first_reward_pool_id),
			"harvest.profile.first_reward_pool", source, "first_reward_pool",
			"harvest profile '%s' references missing first reward pool '%s'"
			% [profile.id, profile.first_reward_pool_id]
		)
		_require(
			issues,
			not pays_direct_reward
			or snapshot.reward_roll_policies.has(profile.roll_policy_id),
			"harvest.profile.roll_policy", source, "roll_policy",
			"harvest profile '%s' references missing roll policy '%s'"
			% [profile.id, profile.roll_policy_id]
		)
		_require(
			issues,
			not pays_direct_reward
			or snapshot.reward_reveal_profiles.has(profile.reveal_profile_id),
			"harvest.profile.reveal_profile", source, "reveal_profile",
			"harvest profile '%s' references missing reveal profile '%s'"
			% [profile.id, profile.reveal_profile_id]
		)
		if pays_tokens:
			var token := snapshot.items.get(profile.token_id) as Defs.ItemDefinition
			_require(
				issues, token != null and token.category == "token",
				"harvest.profile.token", source, "token",
				"harvest profile '%s' references missing pouch token '%s'"
				% [profile.id, profile.token_id]
			)
			_require(
				issues, profile.token_min >= 1 and profile.token_max >= profile.token_min,
				"harvest.profile.token_quantity", source, "token_min",
				"harvest token quantities must start at one and remain ordered"
			)
		_require(
			issues, profile.hits_required >= 1, "harvest.profile.hits", source,
			"hits", "harvest sources require at least one hit"
		)
		_require(
			issues, profile.home_collection != "", "harvest.profile.collection",
			source, "home_collection", "harvest profile needs a home collection"
		)
		_require(
			issues, profile.presentation_profile in HARVEST_PRESENTATIONS,
			"harvest.profile.presentation", source, "presentation",
			"harvest profile '%s' uses unknown presentation '%s'"
			% [profile.id, profile.presentation_profile]
		)
		if profile.presentation_profile == "berry_cluster":
			_validate_berry_presentation(profile, source, issues)


static func _validate_token_boxes(snapshot, issues: Array) -> void:
	for box: Defs.TokenBoxDefinition in snapshot.token_boxes.values():
		var source = snapshot.source("token_boxes", box.id)
		var token := snapshot.items.get(box.token_id) as Defs.ItemDefinition
		_require(
			issues, token != null and token.category == "token",
			"token_box.token", source, "token",
			"token box '%s' references missing pouch token '%s'"
			% [box.id, box.token_id]
		)
		_require(
			issues, box.cost >= 1,
			"token_box.cost", source, "cost",
			"token box cost must be at least one"
		)
		_require(
			issues, snapshot.reward_pools.has(box.reward_pool_id),
			"token_box.reward_pool", source, "reward_pool",
			"token box '%s' references missing reward pool '%s'"
			% [box.id, box.reward_pool_id]
		)
		_require(
			issues, snapshot.reward_roll_policies.has(box.roll_policy_id),
			"token_box.roll_policy", source, "roll_policy",
			"token box '%s' references missing roll policy '%s'"
			% [box.id, box.roll_policy_id]
		)
		_require(
			issues, snapshot.reward_reveal_profiles.has(box.reveal_profile_id),
			"token_box.reveal_profile", source, "reveal_profile",
			"token box '%s' references missing reveal profile '%s'"
			% [box.id, box.reveal_profile_id]
		)


static func _validate_berry_presentation(
	profile: Defs.HarvestProfileDefinition,
	source,
	issues: Array
) -> void:
	var settings := profile.presentation_settings
	_require(
		issues, int(settings.get("count", 0)) >= 1,
		"harvest.berry.count", source, "presentation_settings.count",
		"berry presentation needs at least one fruit"
	)
	_require(
		issues,
		float(settings.get("radius_min", 0.0)) > 0.0
		and float(settings.get("radius_max", 0.0))
			>= float(settings.get("radius_min", 0.0)),
		"harvest.berry.radius", source, "presentation_settings.radius_min",
		"berry radii must be positive and ordered"
	)
	_require(
		issues,
		float(settings.get("height_min", -1.0)) >= 0.0
		and float(settings.get("height_max", 2.0)) <= 1.0
		and float(settings.get("height_max", 0.0))
			>= float(settings.get("height_min", 0.0)),
		"harvest.berry.height", source, "presentation_settings.height_min",
		"berry height fractions must be ordered within zero and one"
	)
	_require(
		issues, String(settings.get("material", "")) != "",
		"harvest.berry.material", source, "presentation_settings.material",
		"berry presentation needs a semantic palette material"
	)
	_require(
		issues,
		float(settings.get("ready_pulse_scale", 0.0)) >= 1.0
		and float(settings.get("ready_pulse_scale", 0.0)) <= 1.15,
		"harvest.berry.ready_pulse", source,
		"presentation_settings.ready_pulse_scale",
		"ripe berry pulse scale must remain subtle"
	)
	_require(
		issues,
		float(settings.get("ready_nudge_radians", -1.0)) >= 0.0
		and float(settings.get("ready_nudge_radians", 1.0)) <= 0.08
		and float(settings.get("ready_nudge_interval", 0.0)) >= 0.4,
		"harvest.berry.ready_nudge", source,
		"presentation_settings.ready_nudge_radians",
		"ripe berry nudge must remain bounded and readable"
	)


static func _validate_harvest_sources(snapshot, issues: Array) -> void:
	for definition: Defs.StructureDefinition in snapshot.structures.values():
		if not definition.has_capability("harvest_source"):
			continue
		var source = snapshot.source("structures", definition.id)
		var payload := definition.capability("harvest_source")
		var profile_id := String(payload.get("profile_id", ""))
		_require(
			issues, snapshot.harvest_profiles.has(profile_id),
			"harvest.source.profile", source,
			"capabilities.harvest_source.profile_id",
			"harvest source '%s' references missing profile '%s'"
			% [definition.id, profile_id]
		)
		_require(
			issues, definition.preserve_instance_state,
			"harvest.source.stateful", source, "preserve_instance_state",
			"harvest sources must preserve instance state when stored"
		)


static func _validate_visitor_presentations(snapshot, issues: Array) -> void:
	for presentation: Defs.VisitorPresentationDefinition in snapshot.visitor_presentations.values():
		var source = snapshot.source("visitor_presentations", presentation.id)
		_require(
			issues, presentation.presenter_type != "",
			"visitor.presentation.type", source, "presenter_type",
			"visitor presentation needs a registered presenter type"
		)
		_require(
			issues, presentation.presentation_resource != ""
			and FileAccess.file_exists(presentation.presentation_resource),
			"visitor.presentation.resource", source, "resource_path",
			"visitor presentation resource '%s' does not exist"
			% presentation.presentation_resource
		)
		_require(
			issues, presentation.weight > 0.0,
			"visitor.presentation.weight", source, "weight",
			"visitor presentation weight must be positive"
		)


static func _validate_visitor_programs(snapshot, issues: Array) -> void:
	for program: Defs.VisitorProgramDefinition in snapshot.visitor_programs.values():
		var source = snapshot.source("visitor_programs", program.id)
		_require(
			issues, not program.presentation_ids.is_empty(),
			"visitor.program.presentations", source, "presentations",
			"visitor program needs at least one presentation"
		)
		for presentation_id: String in program.presentation_ids:
			_require(
				issues, snapshot.visitor_presentations.has(presentation_id),
				"visitor.program.presentation_ref", source, "presentations",
				"visitor program references missing presentation '%s'"
				% presentation_id
			)
		for field in ["first_reward_pool", "reward_pool"]:
			var pool_id := (
				program.first_reward_pool_id
				if field == "first_reward_pool" else program.reward_pool_id
			)
			_require(
				issues, snapshot.reward_pools.has(pool_id),
				"visitor.program.reward_pool", source, field,
				"visitor program references missing reward pool '%s'" % pool_id
			)
	var active_id := String(snapshot.tuning.get("visitor_program_id", ""))
	_require(
		issues, snapshot.visitor_programs.has(active_id),
		"visitor.program.active", null, "tuning.visitor_program_id",
		"visitor_program_id must reference an existing visitor program"
	)


static func _require(
	issues: Array,
	condition: bool,
	code: String,
	source,
	field: String,
	message: String
) -> void:
	if condition:
		return
	issues.append(ValidationIssueScript.new(
		ValidationIssueScript.Severity.ERROR, code, source, field, message
	))
