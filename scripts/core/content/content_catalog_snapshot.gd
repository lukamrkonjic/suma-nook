class_name ContentCatalogSnapshot
extends RefCounted
## Immutable-after-publication collection of parsed content. Registries builds
## a candidate snapshot, validates it completely, then swaps it atomically.

const DEFINITION_KINDS: Array[String] = [
	"skills",
	"items",
	"tiles",
	"structures",
	"recipes",
	"loot_tables",
	"discovery_pools",
	"milestones",
	"anchors",
	"capabilities",
	"enemies",
	"landmarks",
	"fishing_loot",
	"spirits",
	"keepsakes",
	"reward_pools",
	"reward_roll_policies",
	"reward_reveal_profiles",
	"harvest_profiles",
	"visitor_presentations",
	"visitor_programs",
]

var base_path: String
var tuning: Dictionary = {}
var features: Dictionary = {}
var arrival_config: Dictionary = {}
var skills: Dictionary = {}
var items: Dictionary = {}
var tiles: Dictionary = {}
var structures: Dictionary = {}
var recipes: Dictionary = {}
var loot_tables: Dictionary = {}
var discovery_pools: Dictionary = {}
var milestones: Dictionary = {}
var anchors: Dictionary = {}
var capabilities: Dictionary = {}
var enemies: Dictionary = {}
var landmarks: Dictionary = {}
var fishing_loot: Dictionary = {}
var spirits: Dictionary = {}
var keepsakes: Dictionary = {}
var reward_pools: Dictionary = {}
var reward_roll_policies: Dictionary = {}
var reward_reveal_profiles: Dictionary = {}
var harvest_profiles: Dictionary = {}
var visitor_presentations: Dictionary = {}
var visitor_programs: Dictionary = {}
var fishing_balance: Dictionary = {}
var sources: Dictionary = {}


func _init(source_base_path: String = "res://data") -> void:
	base_path = source_base_path


func definitions(kind: String) -> Dictionary:
	match kind:
		"skills": return skills
		"items": return items
		"tiles": return tiles
		"structures": return structures
		"recipes": return recipes
		"loot_tables": return loot_tables
		"discovery_pools": return discovery_pools
		"milestones": return milestones
		"anchors": return anchors
		"capabilities": return capabilities
		"enemies": return enemies
		"landmarks": return landmarks
		"fishing_loot": return fishing_loot
		"spirits": return spirits
		"keepsakes": return keepsakes
		"reward_pools": return reward_pools
		"reward_roll_policies": return reward_roll_policies
		"reward_reveal_profiles": return reward_reveal_profiles
		"harvest_profiles": return harvest_profiles
		"visitor_presentations": return visitor_presentations
		"visitor_programs": return visitor_programs
	return {}


func set_source(kind: String, content_id: String, source) -> void:
	if not sources.has(kind):
		sources[kind] = {}
	sources[kind][content_id] = source


func source(kind: String, content_id: String):
	return (sources.get(kind, {}) as Dictionary).get(content_id)
