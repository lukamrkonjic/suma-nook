extends RefCounted
# legacy-disabled class_name BuildItemDefinition

var id: StringName
var display_name: String
var category: StringName
var scene_path: String
var visual_kind: StringName
var reward_pools: PackedStringArray
var reward_weight: float
var footprint: Vector2i
var valid_support_types: PackedStringArray
var stackability: bool
var max_stack_height: int
var rotation_rules: StringName
var recycle_value: int
var rarity: StringName
var tags: PackedStringArray
var visitor_interaction_tags: PackedStringArray
var placement_audio_category: StringName
var particle_category: StringName
var modifier_kind: StringName
var modifier_tag: StringName
var modifier_strength: float


static func from_dict(row: Dictionary) -> BuildItemDefinition:
	var definition := BuildItemDefinition.new()
	definition.id = StringName(str(row.get("id", "")))
	definition.display_name = str(row.get("display_name", definition.id))
	definition.category = StringName(str(row.get("category", "decor")))
	definition.scene_path = str(row.get("scene_path", "res://scenes/build_item.tscn"))
	definition.visual_kind = StringName(str(row.get("visual_kind", definition.id)))
	definition.reward_pools = PackedStringArray(row.get("reward_pools", []))
	definition.reward_weight = maxf(0.0, float(row.get("reward_weight", 1.0)))
	var fp: Array = row.get("footprint", [1, 1])
	definition.footprint = Vector2i(maxi(1, int(fp[0])), maxi(1, int(fp[1])))
	definition.valid_support_types = PackedStringArray(row.get("valid_support_types", ["ground"]))
	definition.stackability = bool(row.get("stackability", false))
	definition.max_stack_height = maxi(1, int(row.get("max_stack_height", 1)))
	definition.rotation_rules = StringName(str(row.get("rotation_rules", "quarter")))
	definition.recycle_value = maxi(0, int(row.get("recycle_value", 1)))
	definition.rarity = StringName(str(row.get("rarity", "common")))
	definition.tags = PackedStringArray(row.get("tags", []))
	definition.visitor_interaction_tags = PackedStringArray(row.get("visitor_interaction_tags", []))
	definition.placement_audio_category = StringName(str(row.get("placement_audio_category", "general")))
	definition.particle_category = StringName(str(row.get("particle_category", "dust")))
	definition.modifier_kind = StringName(str(row.get("modifier_kind", "")))
	definition.modifier_tag = StringName(str(row.get("modifier_tag", "")))
	definition.modifier_strength = maxf(0.0, float(row.get("modifier_strength", 1.0)))
	return definition


func rotated_footprint(rotation_quarters: int) -> Vector2i:
	return Vector2i(footprint.y, footprint.x) if absi(rotation_quarters) % 2 == 1 else footprint


func is_ground() -> bool:
	return category == &"ground"


func supports_interaction(tag: StringName) -> bool:
	return String(tag) in visitor_interaction_tags
