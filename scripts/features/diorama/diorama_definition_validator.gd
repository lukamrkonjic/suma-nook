class_name DioramaDefinitionValidator
extends RefCounted

const ValidationIssueScript := preload(
	"res://scripts/core/content/validation_issue.gd"
)


static func validate(snapshot, issues: Array) -> void:
	var membership := {}
	for collection in snapshot.creative_collections.values():
		if not snapshot.tiles.has(collection.starting_tile_id):
			_issue(
				issues,
				"diorama.collection.starting_tile",
				"collection '%s' references missing starting tile '%s'"
				% [collection.id, collection.starting_tile_id]
			)
		for member: Dictionary in collection.members:
			var kind := String(member.get("kind", ""))
			var content_id := String(member.get("id", ""))
			var key := "%s:%s" % [kind, content_id]
			if kind not in ["tile", "structure"]:
				_issue(issues, "diorama.member.kind", "collection '%s' has invalid member kind '%s'" % [collection.id, kind])
				continue
			if (
				(kind == "tile" and not snapshot.tiles.has(content_id))
				or (kind == "structure" and not snapshot.structures.has(content_id))
			):
				_issue(issues, "diorama.member.missing", "collection '%s' references missing %s '%s'" % [collection.id, kind, content_id])
			if membership.has(key):
				_issue(issues, "diorama.member.duplicate", "%s belongs to both '%s' and '%s'" % [key, membership[key], collection.id])
			membership[key] = collection.id
		var milestone_ids := {}
		for milestone: Dictionary in collection.milestones:
			var milestone_id := String(milestone.get("id", ""))
			if milestone_id == "" or milestone_ids.has(milestone_id):
				_issue(issues, "diorama.milestone.id", "collection '%s' has an empty or duplicate milestone id" % collection.id)
			milestone_ids[milestone_id] = true
			var gift_id := String(milestone.get("gift_id", ""))
			if gift_id != "" and not snapshot.world_gifts.has(gift_id):
				_issue(issues, "diorama.milestone.gift", "milestone '%s' references missing gift '%s'" % [milestone_id, gift_id])

	for curiosity in snapshot.world_curiosities.values():
		if not snapshot.creative_collections.has(curiosity.collection_id):
			_issue(issues, "diorama.curiosity.collection", "curiosity '%s' references missing collection '%s'" % [curiosity.id, curiosity.collection_id])
		if not snapshot.reward_reveal_profiles.has(curiosity.reveal_profile_id):
			_issue(issues, "diorama.curiosity.reveal", "curiosity '%s' references missing reveal profile '%s'" % [curiosity.id, curiosity.reveal_profile_id])

	var roles: Variant = snapshot.discovery_tray_config.get("roles", [])
	var starters: Variant = snapshot.discovery_tray_config.get("starter_offers", [])
	if not roles is Array or (roles as Array).size() != 3:
		_issue(issues, "diorama.tray.roles", "discovery tray must define exactly three roles")
	if not starters is Array or (starters as Array).size() != 3:
		_issue(issues, "diorama.tray.starters", "discovery tray must define exactly three starter offers")
	elif starters is Array:
		for starter: Variant in starters:
			if not starter is Dictionary:
				_issue(issues, "diorama.tray.starter", "every starter offer must be an object")
				continue
			var kind := String(starter.get("kind", ""))
			var content_id := String(starter.get("id", ""))
			if not membership.has("%s:%s" % [kind, content_id]):
				_issue(issues, "diorama.tray.starter_member", "starter offer %s:%s is not in a creative collection" % [kind, content_id])

	var worldheart: Dictionary = snapshot.worldheart_config
	var minimum := float(worldheart.get("pulse_interval_min", 0.0))
	var maximum := float(worldheart.get("pulse_interval_max", 0.0))
	if minimum <= 0.0 or maximum < minimum:
		_issue(issues, "diorama.worldheart.cadence", "Worldheart pulse interval must be positive and ordered")
	var visible_cap := int(worldheart.get("visible_reward_cap", 0))
	var reserve_cap := int(worldheart.get("reserve_cap", 0))
	if visible_cap <= 0 or reserve_cap < visible_cap:
		_issue(issues, "diorama.worldheart.capacity", "Worldheart reserve must contain at least its visible rewards")
	if int(worldheart.get("contributions_required", 0)) < 2:
		_issue(
			issues,
			"diorama.worldheart.contributions",
			"Worldheart collection rituals need at least two contributions"
		)
	var worldheart_starters: Variant = worldheart.get("starter_rewards", [])
	if not worldheart_starters is Array or (worldheart_starters as Array).is_empty():
		_issue(issues, "diorama.worldheart.starters", "Worldheart needs at least one starter reward")
	else:
		for starter: Variant in worldheart_starters:
			if not starter is Dictionary:
				_issue(issues, "diorama.worldheart.starter", "every Worldheart starter must be an object")
				continue
			var kind := String(starter.get("kind", ""))
			var content_id := String(starter.get("id", ""))
			if not membership.has("%s:%s" % [kind, content_id]):
				_issue(issues, "diorama.worldheart.starter_member", "Worldheart starter %s:%s is not in a creative collection" % [kind, content_id])


static func _issue(issues: Array, code: String, message: String) -> void:
	issues.append(ValidationIssueScript.new(
		ValidationIssueScript.Severity.ERROR,
		code,
		null,
		"diorama",
		message
	))
