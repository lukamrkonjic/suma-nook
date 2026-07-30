class_name BuildCategoryResolver
extends RefCounted
## Shared classification for the Build Bag and the void exchange.


static func category_for(kind: String, definition: Variant) -> String:
	if kind == "tile" and definition is Defs.TileDefinition:
		return category_for_tile(definition)
	if kind == "structure" and definition is Defs.StructureDefinition:
		return category_for_structure(definition)
	return ""


static func category_for_tile(definition: Defs.TileDefinition) -> String:
	match definition.family:
		"living_grove":
			return "woodland"
		"stonebound":
			return "stone"
		"winter":
			return "winter"
		_:
			return "ground"


static func category_for_structure(definition: Defs.StructureDefinition) -> String:
	var tags := definition.placement_tags
	if tags.has("tree") or tags.has("plant") or tags.has("nature"):
		return "nature"
	if tags.has("furniture"):
		return "furniture"
	if tags.has("barrier") or tags.has("sign"):
		return "boundaries"
	if tags.has("storage") or tags.has("container"):
		return "storage"
	if definition.kind == "building" or tags.has("building"):
		return "buildings"
	return "utilities"
