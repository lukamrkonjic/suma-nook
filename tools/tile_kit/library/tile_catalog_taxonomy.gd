@tool
class_name TileCatalogTaxonomy
extends RefCounted
## Human-facing organization for the official tile catalog.
##
## Stable IDs remain the runtime/save contract. Names, scenery categories,
## and display order are presentation metadata and may evolve freely.

const CATEGORIES := [
	["meadow", "Meadow"],
	["forest", "Forest"],
	["garden", "Garden"],
	["farm", "Farm"],
	["swamp", "Swamp"],
	["beach", "Beach"],
	["tundra", "Tundra"],
	["market", "Market"],
	["urban", "Urban"],
	["ruins", "Ruins"],
]

## Runtime families predate the authoring taxonomy and still drive gameplay
## rules such as Build Bag tabs and winter loot. Keep them independent from
## scenery categories so presentation changes cannot alter progression.
const RUNTIME_FAMILIES := {
	"tile_grove_mature": "living_grove",
	"tile_grove_birch": "living_grove",
	"tile_grove_flowering": "living_grove",
	"tile_grove_autumn": "living_grove",
	"tile_grove_mossy": "living_grove",
	"tile_cobblestone": "stonebound",
	"tile_concrete_brutalist": "stonebound",
	"tile_flagstone": "stonebound",
	"tile_proc_brick_court": "stonebound",
	"tile_proc_checker_slabs": "stonebound",
	"tile_proc_cobblestone_paving": "stonebound",
	"tile_proc_concrete_slabs": "stonebound",
	"tile_stone_clearing": "stonebound",
	"tile_stone_crystal": "stonebound",
	"tile_stone_mossy": "stonebound",
	"tile_stone_road": "stonebound",
	"tile_stone_ruin": "stonebound",
	"tile_frosted_stone": "winter",
	"tile_snowfield": "winter",
	"tile_snow_drift": "winter",
	"tile_snow_path": "winter",
	"tile_proc_snow_field": "winter",
	"tile_proc_snow_drifts_study": "winter",
	"tile_proc_sandy_ground": "beach",
	"tile_proc_sand_dunes_study": "beach",
	"tile_master_grass": "tile_forge",
	"tile_master_pavers": "tile_forge",
	"tile_master_wood": "tile_forge",
	"tile_open_water": "waterside",
	"tile_proc_wood_plank_deck": "woodland",
}

## [display name, stable tile ID, scenery category, order within category]
const RECIPES := [
	["Grass", "tile_grass", "meadow", 10],
	["Dense Grass", "tile_kit_grass", "meadow", 20],
	["Flowering Grass", "tile_grass_flower", "meadow", 30],
	["Flower Meadow", "tile_proc_flower_meadow", "meadow", 40],
	["Wild Grass", "tile_master_grass", "meadow", 50],

	["Forest Floor", "tile_grove_mature", "forest", 10],
	["Birch Forest Floor", "tile_grove_birch", "forest", 20],
	["Flowering Forest Floor", "tile_grove_flowering", "forest", 30],
	["Autumn Forest Floor", "tile_grove_autumn", "forest", 40],
	["Mossy Forest Floor", "tile_grove_mossy", "forest", 50],
	["Mossy Clearing", "tile_proc_mossy_forest_floor", "forest", 60],
	["Fallen Leaves", "tile_proc_autumn_litter", "forest", 70],

	["Garden Soil", "tile_garden", "garden", 10],
	["Mulch Ground", "tile_proc_mulch_dirt_floor", "garden", 20],
	["Garden Path", "tile_path", "garden", 30],
	["Meadow Path", "tile_proc_garden_path", "garden", 40],
	["White Soil", "tile_plain_ground", "garden", 50],

	["Dirt Ground", "tile_dirt", "farm", 10],
	["Clay Ground", "tile_clay", "farm", 20],
	["Tilled Soil", "tile_proc_tilled_field", "farm", 30],
	["Dirt Path", "tile_dirt_road", "farm", 40],
	["Dirt Crossroad", "tile_dirt_crossroad", "farm", 50],

	["Pond Edge", "tile_grass_pond_edge", "swamp", 10],
	["Small Pond", "tile_proc_pond_basin", "swamp", 20],
	["Open Water", "tile_open_water", "swamp", 30],
	["Mud Ground", "tile_proc_mud_bed", "swamp", 40],
	["Mud Puddles", "tile_mud", "swamp", 50],

	["Beach Sand", "tile_sand", "beach", 10],
	["Sandy Ground", "tile_proc_sandy_ground", "beach", 20],
	["Sand Dunes", "tile_proc_sand_dunes_study", "beach", 30],
	["Boardwalk", "tile_wooden_planks", "beach", 40],

	["Fresh Snow", "tile_snowfield", "tundra", 10],
	["Snow Field", "tile_proc_snow_field", "tundra", 20],
	["Deep Snow", "tile_snow_drift", "tundra", 30],
	["Snow Drifts", "tile_proc_snow_drifts_study", "tundra", 40],
	["Snowy Path", "tile_snow_path", "tundra", 50],
	["Frosted Stone", "tile_frosted_stone", "tundra", 60],

	["Terracotta Courtyard", "tile_courtyard", "market", 10],
	["Brick Paving", "tile_proc_brick_court", "market", 20],
	["Checkerboard Tiles", "tile_proc_checker_slabs", "market", 30],
	["Wood Deck", "tile_proc_wood_plank_deck", "market", 40],
	["Wide Wood Planks", "tile_master_wood", "market", 50],

	["Cobblestone", "tile_cobblestone", "urban", 10],
	["Cobblestone Paving", "tile_proc_cobblestone_paving", "urban", 20],
	["Large Stone Pavers", "tile_master_pavers", "urban", 30],
	["Concrete Slabs", "tile_proc_concrete_slabs", "urban", 40],
	["Large Concrete Slabs", "tile_concrete_brutalist", "urban", 50],
	["Stone Path", "tile_flagstone", "urban", 60],
	["Gravel Ground", "tile_proc_gravel_yard", "urban", 70],

	["Boulder Field", "tile_proc_boulder_ground", "ruins", 10],
	["Stone Clearing", "tile_stone_clearing", "ruins", 20],
	["Crystal Ground", "tile_stone_crystal", "ruins", 30],
	["Mossy Stone", "tile_stone_mossy", "ruins", 40],
	["Ruined Stone Road", "tile_stone_road", "ruins", 50],
	["Stone Ruins", "tile_stone_ruin", "ruins", 60],
]


static func has_tile(tile_id: String) -> bool:
	return not metadata(tile_id).is_empty()


static func metadata(tile_id: String) -> Dictionary:
	for entry: Array in RECIPES:
		if String(entry[1]) == tile_id:
			return {
				"name": String(entry[0]),
				"id": String(entry[1]),
				"category": String(entry[2]),
				"order": int(entry[3]),
			}
	return {}


static func display_name(tile_id: String) -> String:
	return String(metadata(tile_id).get("name", tile_id.capitalize()))


static func category(tile_id: String) -> String:
	return String(metadata(tile_id).get("category", "other"))


static func catalog_order(tile_id: String) -> int:
	return int(metadata(tile_id).get("order", 1000))


static func runtime_family(tile_id: String) -> String:
	return String(RUNTIME_FAMILIES.get(tile_id, "home_meadow"))


static func category_rank(category_id: String) -> int:
	for index in CATEGORIES.size():
		if String((CATEGORIES[index] as Array)[0]) == category_id:
			return index
	return CATEGORIES.size()


static func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := {}
	var names := {}
	var positions := {}
	for entry: Array in RECIPES:
		var tile_id := String(entry[1])
		var tile_name := String(entry[0])
		var category_id := String(entry[2])
		var order := int(entry[3])
		var position_key := "%s:%d" % [category_id, order]
		if ids.has(tile_id):
			errors.append("Duplicate taxonomy ID: %s" % tile_id)
		if names.has(tile_name.to_lower()):
			errors.append("Duplicate taxonomy name: %s" % tile_name)
		if category_rank(category_id) >= CATEGORIES.size():
			errors.append("Unknown taxonomy category: %s" % category_id)
		if order < 0:
			errors.append("Negative taxonomy order: %s" % tile_id)
		if positions.has(position_key):
			errors.append("Duplicate taxonomy position: %s" % position_key)
		ids[tile_id] = true
		names[tile_name.to_lower()] = true
		positions[position_key] = true
	return errors
