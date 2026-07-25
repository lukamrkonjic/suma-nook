extends RefCounted
class_name TokenDefinition

var id: StringName
var display_name: String
var icon: StringName
var palette: PackedColorArray
var default_weight: float
var reward_pool: StringName
var progression_requirements: Dictionary


static func from_dict(row: Dictionary) -> TokenDefinition:
	var definition := TokenDefinition.new()
	definition.id = StringName(str(row.get("id", "")))
	definition.display_name = str(row.get("display_name", definition.id))
	definition.icon = StringName(str(row.get("icon", "seed")))
	for value: Variant in row.get("palette", ["#ffffff"]):
		definition.palette.append(Color(str(value)))
	definition.default_weight = maxf(0.0, float(row.get("default_weight", 1.0)))
	definition.reward_pool = StringName(str(row.get("reward_pool", definition.id)))
	definition.progression_requirements = row.get("progression_requirements", {})
	return definition

