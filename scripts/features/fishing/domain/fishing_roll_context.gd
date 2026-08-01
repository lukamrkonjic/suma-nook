class_name FishingRollContext
extends RefCounted
## Everything one cast's reward generation may look at, snapshotted when the
## cast begins. Later world edits never change an in-flight catch; the next
## cast samples the changed world.

var habitat: FishingHabitatSample
var spirit_theme := ""               # armed spirit's theme, "" for Wild Cast
var unlock_groups: Array[String] = ["core"]
var owned_keepsake_ids: Array[String] = []   # unique keepsakes never re-roll
var first_catch_pending := false


func _init(habitat_sample: FishingHabitatSample = null) -> void:
	habitat = habitat_sample if habitat_sample != null else FishingHabitatSample.new()


func is_wild_cast() -> bool:
	return spirit_theme == ""
