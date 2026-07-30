class_name Registries
extends RefCounted
## Typed façade over an atomically published content catalog. Existing gameplay
## code uses the same lookup API while loading, provenance, and validation stay
## isolated from runtime behavior.

const ContentCatalogSnapshotScript := preload(
	"res://scripts/core/content/content_catalog_snapshot.gd"
)
const DefinitionSourceScript := preload("res://scripts/core/content/definition_source.gd")
const ValidationIssueScript := preload("res://scripts/core/content/validation_issue.gd")
const CommonDefinitionValidatorScript := preload(
	"res://scripts/core/content/validators/common_definition_validator.gd"
)
const TileDefinitionValidatorScript := preload(
	"res://scripts/core/content/validators/tile_definition_validator.gd"
)
const StructureDefinitionValidatorScript := preload(
	"res://scripts/core/content/validators/structure_definition_validator.gd"
)
const CatalogReferenceValidatorScript := preload(
	"res://scripts/core/content/validators/catalog_reference_validator.gd"
)

var snapshot
var tuning: Dictionary = {}
var features: Dictionary = {}
var arrival_config: Dictionary = {}
var skills: Dictionary = {}
var items: Dictionary = {}
var tiles: Dictionary = {}
var structures: Dictionary = {}
var recipes: Dictionary = {}
var loot_tables: Dictionary = {}
var inspiration_domains: Dictionary = {}
var milestones: Dictionary = {}
var anchors: Dictionary = {}
var capabilities: Dictionary = {}
var enemies: Dictionary = {}
var landmarks: Dictionary = {}
var load_issues: Array = []
var load_errors: PackedStringArray = []
var feature_validators: Array[Callable] = []


func register_validator(validator: Callable) -> void:
	if validator.is_valid() and not feature_validators.has(validator):
		feature_validators.append(validator)


## Loading is atomic: an invalid candidate never mutates the currently
## published dictionaries. This also makes development reloads safe.
func load_all(base_path := "res://data", report_issues := true) -> bool:
	var candidate := ContentCatalogSnapshotScript.new(base_path)
	var issues: Array = []
	candidate.tuning = _read_object(base_path + "/tuning.json", issues)
	candidate.features = _read_object(base_path + "/features.json", issues)
	candidate.arrival_config = _read_object(base_path + "/arrival_config.json", issues)
	_load_list(
		candidate, base_path + "/skills.json", "skills", "skills",
		candidate.skills, Defs.SkillDefinition.from_dict, issues
	)
	_load_list(
		candidate, base_path + "/items.json", "items", "items",
		candidate.items, Defs.ItemDefinition.from_dict, issues
	)
	_load_list(
		candidate, base_path + "/tiles.json", "tiles", "tiles",
		candidate.tiles, Defs.TileDefinition.from_dict, issues
	)
	_load_list(
		candidate, base_path + "/structures.json", "structures", "structures",
		candidate.structures, Defs.StructureDefinition.from_dict, issues
	)
	_load_list(
		candidate, base_path + "/recipes.json", "recipes", "recipes",
		candidate.recipes, Defs.RecipeDefinition.from_dict, issues
	)
	_load_list(
		candidate, base_path + "/loot_tables.json", "tables", "loot_tables",
		candidate.loot_tables, Defs.LootTableDefinition.from_dict, issues
	)
	_load_list(
		candidate, base_path + "/inspiration_domains.json", "inspiration_domains",
		"inspiration_domains", candidate.inspiration_domains,
		Defs.InspirationDomainDefinition.from_dict, issues
	)
	_load_list(
		candidate, base_path + "/milestones.json", "milestones", "milestones",
		candidate.milestones, Defs.MilestoneDefinition.from_dict, issues
	)
	_load_list(
		candidate, base_path + "/anchors.json", "anchors", "anchors",
		candidate.anchors, Defs.AnchorDefinition.from_dict, issues
	)
	_load_list(
		candidate, base_path + "/capabilities.json", "capabilities", "capabilities",
		candidate.capabilities, Defs.CapabilityDefinition.from_dict, issues
	)
	_load_list(
		candidate, base_path + "/enemies.json", "enemies", "enemies",
		candidate.enemies, Defs.EnemyDefinition.from_dict, issues
	)
	_load_list(
		candidate, base_path + "/landmarks.json", "landmarks", "landmarks",
		candidate.landmarks, Defs.LandmarkDefinition.from_dict, issues
	)
	CommonDefinitionValidatorScript.validate(candidate, issues)
	TileDefinitionValidatorScript.validate(candidate, issues)
	StructureDefinitionValidatorScript.validate(candidate, issues)
	CatalogReferenceValidatorScript.validate(candidate, issues)
	for validator: Callable in feature_validators:
		validator.call(candidate, issues)
	ContentValidator.validate_snapshot(candidate, issues)
	_publish_issues(issues, report_issues)
	if _has_errors(issues):
		return false
	_adopt(candidate)
	return true


func reload_all_atomic(base_path := "", report_issues := true) -> bool:
	var reload_path := base_path
	if reload_path == "":
		reload_path = snapshot.base_path if snapshot != null else "res://data"
	return load_all(reload_path, report_issues)


func definition_source(kind: String, content_id: String):
	return snapshot.source(kind, content_id) if snapshot != null else null


func definition_kinds() -> Array[String]:
	return (
		snapshot.DEFINITION_KINDS.duplicate()
		if snapshot != null
		else ContentCatalogSnapshotScript.DEFINITION_KINDS.duplicate()
	)


func definitions(kind: String) -> Dictionary:
	return snapshot.definitions(kind) if snapshot != null else {}


func definition(kind: String, content_id: String):
	return definitions(kind).get(content_id)


func definition_traits(kind: String, content_id: String):
	var found = definition(kind, content_id)
	return found.traits if found != null else null


func definition_has_tag(kind: String, content_id: String, tag: String) -> bool:
	var traits = definition_traits(kind, content_id)
	return traits != null and traits.has_tag(tag)


func definition_has_capability(
	kind: String, content_id: String, capability_id: String
) -> bool:
	var traits = definition_traits(kind, content_id)
	return traits != null and traits.has_capability(capability_id)


func definition_capability(
	kind: String, content_id: String, capability_id: String
) -> Dictionary:
	var traits = definition_traits(kind, content_id)
	return traits.capability(capability_id) if traits != null else {}


func tune(key: String, fallback: Variant = null) -> Variant:
	return tuning.get(key, fallback)


func tunef(key: String, fallback: float = 0.0) -> float:
	return float(tuning.get(key, fallback))


func tunei(key: String, fallback: int = 0) -> int:
	return int(tuning.get(key, fallback))


func feature(key: String, fallback := false) -> bool:
	return bool(features.get(key, fallback))


func skill(id: String) -> Defs.SkillDefinition: return skills.get(id)
func item(id: String) -> Defs.ItemDefinition: return items.get(id)
func tile(id: String) -> Defs.TileDefinition: return tiles.get(id)
func structure(id: String) -> Defs.StructureDefinition: return structures.get(id)
func recipe(id: String) -> Defs.RecipeDefinition: return recipes.get(id)
func loot_table(id: String) -> Defs.LootTableDefinition: return loot_tables.get(id)
func inspiration_domain(id: String) -> Defs.InspirationDomainDefinition: return inspiration_domains.get(id)
func milestone(id: String) -> Defs.MilestoneDefinition: return milestones.get(id)
func anchor(id: String) -> Defs.AnchorDefinition: return anchors.get(id)
func capability(id: String) -> Defs.CapabilityDefinition: return capabilities.get(id)
func enemy(id: String) -> Defs.EnemyDefinition: return enemies.get(id)
func landmark(id: String) -> Defs.LandmarkDefinition: return landmarks.get(id)


func has_definition(kind: String, id: String) -> bool:
	return definitions(kind).has(id)


func active_tile_ids() -> Array[String]:
	var configured: Variant = tuning.get("active_tile_ids", [])
	var result: Array[String] = []
	if configured is Array and not configured.is_empty():
		for tile_id: Variant in configured:
			var normalized := String(tile_id)
			if tiles.has(normalized) and not result.has(normalized):
				result.append(normalized)
		return result
	# Compatibility for custom/older data sets that predate the active roster.
	for definition: Defs.TileDefinition in tiles.values():
		if definition.obtainable:
			result.append(definition.id)
	return result


func is_tile_active(tile_id: String) -> bool:
	return active_tile_ids().has(tile_id)


func active_tiles() -> Array:
	var result: Array = []
	for tile_id: String in active_tile_ids():
		result.append(tiles[tile_id])
	return result


func tiles_in_family(family: String) -> Array:
	var result: Array = []
	for definition: Defs.TileDefinition in tiles.values():
		if (
			definition.family == family
			and definition.obtainable
			and is_tile_active(definition.id)
		):
			result.append(definition)
	return result


## Domain lookup by tile family. Wildcard domains never own a family.
func domain_for_family(family: String) -> Defs.InspirationDomainDefinition:
	for definition: Defs.InspirationDomainDefinition in inspiration_domains.values():
		if definition.tile_families.has(family):
			return definition
	return null


## Domain an activity feeds, resolved from the activity definition.
func domain_for_activity(skill_id: String) -> Defs.InspirationDomainDefinition:
	var definition := skill(skill_id)
	if definition == null:
		return null
	return inspiration_domain(definition.domain_id)


func _read_object(path: String, issues: Array) -> Dictionary:
	if not FileAccess.file_exists(path):
		issues.append(ValidationIssueScript.new(
			ValidationIssueScript.Severity.ERROR, "content.file.missing",
			null, path, "file does not exist"
		))
		return {}
	var parser := JSON.new()
	var error := parser.parse(FileAccess.get_file_as_string(path))
	if error != OK:
		issues.append(ValidationIssueScript.new(
			ValidationIssueScript.Severity.ERROR, "content.json.invalid",
			null, "%s:%d" % [path, parser.get_error_line()],
			parser.get_error_message()
		))
		return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		issues.append(ValidationIssueScript.new(
			ValidationIssueScript.Severity.ERROR, "content.root.invalid",
			null, path, "root value must be an object"
		))
		return {}
	return parsed


func _load_list(
	candidate,
	path: String,
	root_key: String,
	kind: String,
	target: Dictionary,
	factory: Callable,
	issues: Array
) -> void:
	var root := _read_object(path, issues)
	var raw_entries: Variant = root.get(root_key, [])
	if not raw_entries is Array:
		issues.append(ValidationIssueScript.new(
			ValidationIssueScript.Severity.ERROR, "content.list.invalid",
			null, "%s.%s" % [path, root_key],
			"expected an array"
		))
		return
	for index in raw_entries.size():
		var raw_entry: Variant = raw_entries[index]
		if not raw_entry is Dictionary:
			issues.append(ValidationIssueScript.new(
				ValidationIssueScript.Severity.ERROR, "content.entry.invalid",
				null, "%s[%d]" % [path, index],
				"expected an object"
			))
			continue
		var content_id := String(raw_entry.get("id", ""))
		var source := DefinitionSourceScript.new(path, kind, root_key, index, content_id)
		if content_id == "":
			issues.append(ValidationIssueScript.new(
				ValidationIssueScript.Severity.ERROR, "content.id.required",
				source, "id", "id must not be empty"
			))
			continue
		if target.has(content_id):
			issues.append(ValidationIssueScript.new(
				ValidationIssueScript.Severity.ERROR, "content.id.duplicate",
				source, "id",
				"id '%s' is already defined" % content_id
			))
			continue
		var definition: Resource = factory.call(raw_entry)
		target[content_id] = definition
		candidate.set_source(kind, content_id, source)


func _adopt(candidate) -> void:
	snapshot = candidate
	tuning = candidate.tuning
	features = candidate.features
	arrival_config = candidate.arrival_config
	skills = candidate.skills
	items = candidate.items
	tiles = candidate.tiles
	structures = candidate.structures
	recipes = candidate.recipes
	loot_tables = candidate.loot_tables
	inspiration_domains = candidate.inspiration_domains
	milestones = candidate.milestones
	anchors = candidate.anchors
	capabilities = candidate.capabilities
	enemies = candidate.enemies
	landmarks = candidate.landmarks


func _publish_issues(issues: Array, report_issues: bool) -> void:
	load_issues.assign(issues)
	load_errors.clear()
	for issue in issues:
		if issue.severity == ValidationIssueScript.Severity.ERROR:
			load_errors.append(issue.format())
			if report_issues:
				push_error("Registries: " + issue.format())
		elif report_issues:
			push_warning("Registries: " + issue.format())


func _has_errors(issues: Array) -> bool:
	for issue in issues:
		if issue.severity == ValidationIssueScript.Severity.ERROR:
			return true
	return false
