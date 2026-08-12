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
	"token_boxes",
	"harvest_profiles",
	"project_definitions",
	"special_finds",
	"visitor_presentations",
	"visitor_programs",
	"nook_biomes",
	"nook_stamps",
	"nook_moods",
	"treasure_tables",
	"firsts",
	"dormants",
	"moments",
	"creative_collections",
	"world_gifts",
	"world_curiosities",
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
var token_boxes: Dictionary = {}
var harvest_profiles: Dictionary = {}
var project_definitions: Dictionary = {}
var special_finds: Dictionary = {}
var visitor_presentations: Dictionary = {}
var visitor_programs: Dictionary = {}
var nook_biomes: Dictionary = {}
var nook_stamps: Dictionary = {}
var nook_moods: Dictionary = {}
var treasure_tables: Dictionary = {}
var firsts: Dictionary = {}
var dormants: Dictionary = {}
var moments: Dictionary = {}
var creative_collections: Dictionary = {}
var world_gifts: Dictionary = {}
var world_curiosities: Dictionary = {}
var nook_config: Dictionary = {}
var reveal_config: Dictionary = {}
var fishing_balance: Dictionary = {}
var discovery_tray_config: Dictionary = {}
var build_cadence_config: Dictionary = {}
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
		"token_boxes": return token_boxes
		"harvest_profiles": return harvest_profiles
		"project_definitions": return project_definitions
		"special_finds": return special_finds
		"visitor_presentations": return visitor_presentations
		"visitor_programs": return visitor_programs
		"nook_biomes": return nook_biomes
		"nook_stamps": return nook_stamps
		"nook_moods": return nook_moods
		"treasure_tables": return treasure_tables
		"firsts": return firsts
		"dormants": return dormants
		"moments": return moments
		"creative_collections": return creative_collections
		"world_gifts": return world_gifts
		"world_curiosities": return world_curiosities
	return {}


func set_source(kind: String, content_id: String, source) -> void:
	if not sources.has(kind):
		sources[kind] = {}
	sources[kind][content_id] = source


func source(kind: String, content_id: String):
	return (sources.get(kind, {}) as Dictionary).get(content_id)
