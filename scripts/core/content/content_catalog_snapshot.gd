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
	"inspiration_domains",
	"milestones",
	"anchors",
	"capabilities",
	"enemies",
	"landmarks",
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
var inspiration_domains: Dictionary = {}
var milestones: Dictionary = {}
var anchors: Dictionary = {}
var capabilities: Dictionary = {}
var enemies: Dictionary = {}
var landmarks: Dictionary = {}
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
		"inspiration_domains": return inspiration_domains
		"milestones": return milestones
		"anchors": return anchors
		"capabilities": return capabilities
		"enemies": return enemies
		"landmarks": return landmarks
	return {}


func set_source(kind: String, content_id: String, source) -> void:
	if not sources.has(kind):
		sources[kind] = {}
	sources[kind][content_id] = source


func source(kind: String, content_id: String):
	return (sources.get(kind, {}) as Dictionary).get(content_id)
