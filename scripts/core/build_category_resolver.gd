class_name BuildCategoryResolver
extends RefCounted
## Shared classification for the Build Bag and the void exchange.

const ICON_DIRECTORY := "res://assets/ui/icons/"
const CATEGORIES := [
	{
		"id": "ground",
		"label": "Ground",
		"icon": "category_ground.svg",
		"wish_description": "Ground, water and island surfaces.",
		"wish_weight": 1.25,
	},
	{
		"id": "woodland",
		"label": "Woodland",
		"icon": "category_woodland.svg",
		"wish_description": "Groves and quiet woodland pieces.",
		"wish_weight": 1.0,
	},
	{
		"id": "stone",
		"label": "Stone",
		"icon": "category_stone.svg",
		"wish_description": "Stone ground and weathered masonry.",
		"wish_weight": 0.9,
	},
	{
		"id": "winter",
		"label": "Snow",
		"icon": "category_winter.svg",
		"wish_description": "Snowy ground and winter details.",
		"wish_weight": 0.85,
	},
	{
		"id": "nature",
		"label": "Nature",
		"icon": "category_nature.svg",
		"wish_description": "Trees, plants and garden life.",
		"wish_weight": 1.05,
	},
	{
		"id": "furniture",
		"label": "Furniture",
		"icon": "category_furniture.svg",
		"wish_description": "Tables, seats and homely comforts.",
		"wish_weight": 1.0,
	},
	{
		"id": "boundaries",
		"label": "Borders",
		"icon": "category_boundaries.svg",
		"wish_description": "Fences, walls, gates and signs.",
		"wish_weight": 0.95,
	},
	{
		"id": "utilities",
		"label": "Utilities",
		"icon": "category_utilities.svg",
		"wish_description": "Lights, tools and useful garden pieces.",
		"wish_weight": 0.95,
	},
	{
		"id": "buildings",
		"label": "Buildings",
		"icon": "category_buildings.svg",
		"wish_description": "Shelters, arches and larger structures.",
		"wish_weight": 0.8,
	},
	{
		"id": "storage",
		"label": "Storage",
		"icon": "category_storage.svg",
		"wish_description": "Crates, chests and rustic containers.",
		"wish_weight": 0.85,
	},
	{
		"id": "deeds",
		"label": "Deeds",
		"icon": "category_deeds.svg",
		"wish_description": "Packed landmarks.",
		"wish_weight": 0.0,
	},
]


static func categories() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for category: Dictionary in CATEGORIES:
		result.append(category.duplicate(true))
	return result


static func category(category_id: String) -> Dictionary:
	for entry: Dictionary in CATEGORIES:
		if String(entry.get("id", "")) == category_id:
			return entry.duplicate(true)
	return {}


static func icon_path(category_id: String) -> String:
	var entry := category(category_id)
	return (
		ICON_DIRECTORY + String(entry.get("icon", ""))
		if not entry.is_empty()
		else ""
	)


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
