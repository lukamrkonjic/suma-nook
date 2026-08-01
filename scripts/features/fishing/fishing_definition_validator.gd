class_name FishingDefinitionValidator
extends RefCounted
## Content contract for the void-fishing reward system. Loot references
## existing building content by stable id; malformed content fails loudly at
## startup instead of surfacing as a broken catch.

const ValidationIssueScript := preload(
	"res://scripts/core/content/validation_issue.gd"
)
const REWARD_KINDS := ["tile_bundle", "model", "keepsake"]
const POOL_TAGS := ["local", "global", "wildcard"]
const RARITIES := ["common", "uncommon", "rare"]
const REQUIRED_BALANCE_KEYS := [
	"timing", "source_pools", "haul_sizes", "single_form_weights",
	"bundle_ranges", "keepsake", "rare_luck", "habitat",
	"pouch_capacity", "basket_capacity", "unlock_groups",
	"first_catch_loot_id", "fallback_loot_id",
]


static func validate(snapshot, issues: Array) -> void:
	_validate_loot(snapshot, issues)
	_validate_spirits(snapshot, issues)
	_validate_keepsakes(snapshot, issues)
	_validate_balance(snapshot, issues)


static func _validate_loot(snapshot, issues: Array) -> void:
	var global_tile_bundles := 0
	var wildcard_entries := 0
	for loot: Defs.FishingLootDefinition in snapshot.fishing_loot.values():
		var source = snapshot.source("fishing_loot", loot.id)
		if not REWARD_KINDS.has(loot.reward_kind):
			_error(
				issues, "fishing.loot.kind", source, "reward_kind",
				"loot '%s' has unknown reward kind '%s'" % [loot.id, loot.reward_kind]
			)
			continue
		# The only grantable content is building content: a tile, a placeable
		# model, or a keepsake charm. Creatures cannot be expressed here.
		var known := false
		match loot.reward_kind:
			"tile_bundle":
				known = snapshot.tiles.has(loot.building_definition_id)
			"model":
				known = snapshot.structures.has(loot.building_definition_id)
			"keepsake":
				known = snapshot.keepsakes.has(loot.building_definition_id)
		if not known:
			_error(
				issues, "fishing.loot.reference", source, "building_definition_id",
				"loot '%s' references missing %s '%s'"
				% [loot.id, loot.reward_kind, loot.building_definition_id]
			)
		if loot.theme_tags.is_empty():
			_error(
				issues, "fishing.loot.themes", source, "theme_tags",
				"loot '%s' needs at least one broad theme tag" % loot.id
			)
		if loot.pool_tags.is_empty():
			_error(
				issues, "fishing.loot.pools", source, "pool_tags",
				"loot '%s' needs at least one pool tag" % loot.id
			)
		for tag: String in loot.pool_tags:
			if not POOL_TAGS.has(tag):
				_error(
					issues, "fishing.loot.pool_tag", source, "pool_tags",
					"loot '%s' has unknown pool tag '%s'" % [loot.id, tag]
				)
		if not RARITIES.has(loot.rarity):
			_error(
				issues, "fishing.loot.rarity", source, "rarity",
				"loot '%s' has unknown rarity '%s'" % [loot.id, loot.rarity]
			)
		if loot.base_weight <= 0.0:
			_error(
				issues, "fishing.loot.weight", source, "base_weight",
				"loot '%s' must have a positive base weight" % loot.id
			)
		if loot.bundle_min < 0 or loot.bundle_max < loot.bundle_min:
			_error(
				issues, "fishing.loot.bundle", source, "bundle_min",
				"loot '%s' has an invalid bundle range" % loot.id
			)
		if loot.reward_kind == "keepsake" and not loot.unique:
			_error(
				issues, "fishing.loot.keepsake_unique", source, "unique",
				"keepsake loot '%s' must be unique" % loot.id
			)
		if loot.unlock_group == "":
			_error(
				issues, "fishing.loot.unlock_group", source, "unlock_group",
				"loot '%s' needs an unlock group (default is 'core')" % loot.id
			)
		if loot.reward_kind == "tile_bundle" and loot.in_pool("global"):
			global_tile_bundles += 1
		if loot.in_pool("wildcard"):
			wildcard_entries += 1
	if global_tile_bundles == 0:
		_error(
			issues, "fishing.loot.no_safe_tile", null, "fishing_loot",
			"at least one global-pool tile bundle is required as a safe fallback"
		)
	if wildcard_entries == 0:
		_error(
			issues, "fishing.loot.no_wildcard", null, "fishing_loot",
			"the wildcard pool needs at least one entry"
		)


static func _validate_spirits(snapshot, issues: Array) -> void:
	for spirit: Defs.SpiritDefinition in snapshot.spirits.values():
		var source = snapshot.source("spirits", spirit.id)
		if spirit.theme_tag == "":
			_error(
				issues, "fishing.spirit.theme", source, "theme_tag",
				"spirit '%s' needs a theme tag" % spirit.id
			)
		if not snapshot.skills.has(spirit.source_skill):
			_error(
				issues, "fishing.spirit.skill", source, "source_skill",
				"spirit '%s' references missing skill '%s'"
				% [spirit.id, spirit.source_skill]
			)


static func _validate_keepsakes(snapshot, issues: Array) -> void:
	for keepsake: Defs.KeepsakeDefinition in snapshot.keepsakes.values():
		if keepsake.effect_id == "":
			_error(
				issues, "fishing.keepsake.effect",
				snapshot.source("keepsakes", keepsake.id), "effect",
				"keepsake '%s' needs an effect id" % keepsake.id
			)


static func _validate_balance(snapshot, issues: Array) -> void:
	var balance: Dictionary = snapshot.fishing_balance
	for key: String in REQUIRED_BALANCE_KEYS:
		if not balance.has(key):
			_error(
				issues, "fishing.balance.missing", null, key,
				"fishing_balance.json is missing required key '%s'" % key
			)
	for loot_key in ["first_catch_loot_id", "fallback_loot_id"]:
		var loot_id := String(balance.get(loot_key, ""))
		var loot: Defs.FishingLootDefinition = snapshot.fishing_loot.get(loot_id)
		if loot == null or loot.reward_kind != "tile_bundle":
			_error(
				issues, "fishing.balance.loot_ref", null, loot_key,
				"'%s' must name an existing tile-bundle loot definition" % loot_key
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
