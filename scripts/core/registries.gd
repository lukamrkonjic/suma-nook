class_name Registries
extends RefCounted
## Loads every data/*.json file into typed definition dictionaries and validates
## cross-references at startup. Adding content = adding JSON entries; adding a
## whole new definition type = one loader + one dictionary here.

var tuning: Dictionary = {}
var features: Dictionary = {}
var arrival_config: Dictionary = {}
var skills: Dictionary = {}
var items: Dictionary = {}
var tiles: Dictionary = {}
var structures: Dictionary = {}
var recipes: Dictionary = {}
var loot_tables: Dictionary = {}
var parcels: Dictionary = {}
var anchors: Dictionary = {}
var enemies: Dictionary = {}
var landmarks: Dictionary = {}
var load_errors: PackedStringArray = []


func load_all(base_path := "res://data") -> bool:
	load_errors.clear()
	tuning = _read(base_path + "/tuning.json")
	features = _read(base_path + "/features.json")
	arrival_config = _read(base_path + "/arrival_config.json")
	_load_list(base_path + "/skills.json", "skills", skills, Defs.SkillDefinition.from_dict)
	_load_list(base_path + "/items.json", "items", items, Defs.ItemDefinition.from_dict)
	_load_list(base_path + "/tiles.json", "tiles", tiles, Defs.TileDefinition.from_dict)
	_load_list(base_path + "/structures.json", "structures", structures, Defs.StructureDefinition.from_dict)
	_load_list(base_path + "/recipes.json", "recipes", recipes, Defs.RecipeDefinition.from_dict)
	_load_list(base_path + "/loot_tables.json", "tables", loot_tables, Defs.LootTableDefinition.from_dict)
	_load_list(base_path + "/parcels.json", "parcels", parcels, Defs.ParcelDefinition.from_dict)
	_load_list(base_path + "/anchors.json", "anchors", anchors, Defs.AnchorDefinition.from_dict)
	_load_list(base_path + "/enemies.json", "enemies", enemies, Defs.EnemyDefinition.from_dict)
	_load_list(base_path + "/landmarks.json", "landmarks", landmarks, Defs.LandmarkDefinition.from_dict)
	_validate()
	for error in load_errors:
		push_error("Registries: " + error)
	return load_errors.is_empty()


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
func parcel(id: String) -> Defs.ParcelDefinition: return parcels.get(id)
func anchor(id: String) -> Defs.AnchorDefinition: return anchors.get(id)
func enemy(id: String) -> Defs.EnemyDefinition: return enemies.get(id)
func landmark(id: String) -> Defs.LandmarkDefinition: return landmarks.get(id)


func has_definition(kind: String, id: String) -> bool:
	match kind:
		"tiles": return tiles.has(id)
		"structures": return structures.has(id)
		"items": return items.has(id)
		"parcels": return parcels.has(id)
		"landmarks": return landmarks.has(id)
		"enemies": return enemies.has(id)
		"skills": return skills.has(id)
	return false


func ensure_compatibility_definition(kind: String, id: String) -> Resource:
	if id == "":
		return null
	match kind:
		"tiles":
			if not tiles.has(id):
				tiles[id] = Defs.TileDefinition.from_dict({
					"id": id,
					"name": "Recovered Tile (%s)" % id,
					"family": "retired",
					"asset_id": "tile_stone_clearing",
					"weight": 0.0,
					"obtainable": false,
					"stackable": true,
					"supports_tiles": true,
					"supports_decor": true,
					"surface_kind": "flat",
					"render_profile": "standard",
					"collision_profile": "flat",
					"special_trait": "Compatibility placeholder for retired content.",
				})
			return tiles[id]
		"structures":
			if not structures.has(id):
				structures[id] = Defs.StructureDefinition.from_dict({
					"id": id,
					"name": "Recovered Decoration (%s)" % id,
					"asset_id": "prop_sign",
					"kind": "decoration",
					"socket_type": "decor",
					"allow_elevated": true,
				})
			return structures[id]
		"items":
			if not items.has(id):
				items[id] = Defs.ItemDefinition.from_dict({
					"id": id,
					"name": "Recovered Item (%s)" % id,
					"category": "retired",
					"stack": true,
				})
			return items[id]
		"parcels":
			if not parcels.has(id):
				parcels[id] = Defs.ParcelDefinition.from_dict({
					"id": id,
					"name": "Recovered Parcel (%s)" % id,
					"families": {"home_meadow": 1.0},
					"option_count": 3,
				})
			if not items.has(id):
				items[id] = Defs.ItemDefinition.from_dict({
					"id": id,
					"name": "Recovered Parcel (%s)" % id,
					"category": "parcel",
					"stack": true,
				})
			return parcels[id]
		"landmarks":
			if not landmarks.has(id):
				landmarks[id] = Defs.LandmarkDefinition.from_dict({
					"id": id,
					"name": "Recovered Landmark (%s)" % id,
					"asset_id": "prop_sign",
					"footprint": [[0, 0]],
					"min_progress_tiles": 999999,
				})
			return landmarks[id]
		"enemies":
			if not enemies.has(id):
				enemies[id] = Defs.EnemyDefinition.from_dict({
					"id": id,
					"name": "Recovered Creature (%s)" % id,
					"asset_id": "enemy_thornling_stalker",
					"health": 1,
					"damage": 0,
					"speed": 0.0,
				})
			return enemies[id]
		"skills":
			if not skills.has(id):
				skills[id] = Defs.SkillDefinition.from_dict({
					"id": id,
					"name": "Retired Skill (%s)" % id,
					"future": true,
					"max_level": 1,
				})
			return skills[id]
	return null


func tiles_in_family(family: String) -> Array:
	var result: Array = []
	for def: Defs.TileDefinition in tiles.values():
		if def.family == family and def.obtainable:
			result.append(def)
	return result


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		load_errors.append("missing file " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		load_errors.append("invalid JSON in " + path)
		return {}
	return parsed


func _load_list(path: String, key: String, target: Dictionary, factory: Callable) -> void:
	target.clear()
	for entry in _read(path).get(key, []):
		var def: Resource = factory.call(entry)
		var id: String = def.get("id")
		if id == "":
			load_errors.append("entry without id in " + path)
		elif target.has(id):
			load_errors.append("duplicate id '%s' in %s" % [id, path])
		else:
			target[id] = def


func _validate() -> void:
	var known_families := {}
	for def: Defs.TileDefinition in tiles.values():
		known_families[def.family] = true
		if def.anchor_id != "" and not anchors.has(def.anchor_id):
			load_errors.append("tile %s references missing anchor %s" % [def.id, def.anchor_id])
		if def.asset_id == "":
			load_errors.append("tile %s has no asset id" % def.id)
		if def.weight < 0.0:
			load_errors.append("tile %s has negative parcel weight" % def.id)
		if def.decor_sockets < 0 or def.structure_sockets < 0:
			load_errors.append("tile %s has negative socket counts" % def.id)
		if def.structure_sockets > 1:
			load_errors.append("tile %s declares unsupported multiple major sockets" % def.id)
		if def.surface_kind not in ["flat", "stairs", "uneven", "water"]:
			load_errors.append("tile %s has invalid surface kind %s" % [def.id, def.surface_kind])
		if def.render_profile not in ["standard", "continuous_water"]:
			load_errors.append("tile %s has invalid render profile %s" % [def.id, def.render_profile])
		if def.collision_profile not in ["flat", "pond_basin", "none"]:
			load_errors.append("tile %s has invalid collision profile %s" % [def.id, def.collision_profile])
		if def.supports_tiles and def.surface_kind != "flat":
			load_errors.append("tile %s supports stacking but does not have a flat surface" % def.id)
		if def.render_profile == "continuous_water" and not def.water_cells.has("open_water"):
			load_errors.append("tile %s uses continuous water rendering without the open_water tag" % def.id)
		if def.collision_profile == "pond_basin" and not def.water_cells.has("pond"):
			load_errors.append("tile %s uses pond collision without the pond tag" % def.id)
		if def.structure_sockets > 0 and not def.supports_decor:
			load_errors.append("tile %s exposes a major socket while decor support is disabled" % def.id)
		for skill_id: String in def.unlock_level:
			if not skills.has(skill_id):
				load_errors.append("tile %s unlock references missing skill %s" % [def.id, skill_id])
	for def: Defs.StructureDefinition in structures.values():
		if def.asset_id == "":
			load_errors.append("structure %s has no asset id" % def.id)
		if def.socket_type not in ["decor", "structure"]:
			load_errors.append("structure %s has invalid socket type %s" % [def.id, def.socket_type])
	for def: Defs.AnchorDefinition in anchors.values():
		if not skills.has(def.skill_id):
			load_errors.append("anchor %s references missing skill %s" % [def.id, def.skill_id])
		if def.loot_table != "" and not loot_tables.has(def.loot_table):
			load_errors.append("anchor %s references missing loot table %s" % [def.id, def.loot_table])
	for def: Defs.SkillDefinition in skills.values():
		if def.loot_table != "" and not loot_tables.has(def.loot_table):
			load_errors.append("skill %s references missing loot table %s" % [def.id, def.loot_table])
		if def.rare_table != "" and not loot_tables.has(def.rare_table):
			load_errors.append("skill %s references missing rare table %s" % [def.id, def.rare_table])
		for tile_id: String in def.direct_tile_reward_pool:
			if not tiles.has(tile_id):
				load_errors.append("skill %s reward pool references missing tile %s" % [def.id, tile_id])
		for unlock: Dictionary in def.unlocks:
			var kind := String(unlock.get("kind", ""))
			var unlock_id := String(unlock.get("id", ""))
			if kind in ["tile", "tile_reward"] and not tiles.has(unlock_id):
				load_errors.append("skill %s unlock references missing tile %s" % [def.id, unlock_id])
			elif kind == "structure_reward" and not structures.has(unlock_id):
				load_errors.append("skill %s unlock references missing structure %s" % [def.id, unlock_id])
			elif kind == "recipe" and not recipes.has(unlock_id):
				load_errors.append("skill %s unlock references missing recipe %s" % [def.id, unlock_id])
			elif kind == "anchor_upgrade" and not anchors.has(unlock_id):
				load_errors.append("skill %s unlock references missing anchor %s" % [def.id, unlock_id])
	for def: Defs.LootTableDefinition in loot_tables.values():
		for entry in def.entries:
			if not items.has(entry["item"]):
				load_errors.append("loot table %s references missing item %s" % [def.id, entry["item"]])
	for def: Defs.RecipeDefinition in recipes.values():
		for input_id: String in def.inputs:
			if not items.has(input_id):
				load_errors.append("recipe %s input references missing item %s" % [def.id, input_id])
		var out_known: bool = items.has(def.output_id) or structures.has(def.output_id) or def.output_id == "reroll_charge"
		if not out_known:
			load_errors.append("recipe %s output references missing id %s" % [def.id, def.output_id])
	for def: Defs.ParcelDefinition in parcels.values():
		if not items.has(def.id):
			load_errors.append("parcel %s has no matching inventory item" % def.id)
		for family: String in def.families:
			if not known_families.has(family):
				load_errors.append("parcel %s references empty tile family %s" % [def.id, family])
	for def: Defs.LandmarkDefinition in landmarks.values():
		for spawn in def.enemies:
			if not enemies.has(spawn.get("enemy", "")):
				load_errors.append("landmark %s references missing enemy" % def.id)
		if def.guardian_id != "" and not enemies.has(def.guardian_id):
			load_errors.append("landmark %s references missing guardian" % def.id)
		if def.guardian_reward != "" and not items.has(def.guardian_reward):
			load_errors.append("landmark %s guardian reward missing item" % def.id)
	for id in tuning.get("guaranteed_first_parcel_options", []):
		if not tiles.has(id):
			load_errors.append("tuning guaranteed option references missing tile %s" % id)
