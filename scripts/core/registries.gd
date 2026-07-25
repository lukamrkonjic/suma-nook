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


func tiles_in_family(family: String) -> Array:
	var result: Array = []
	for def: Defs.TileDefinition in tiles.values():
		if def.family == family:
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
	for def: Defs.TileDefinition in tiles.values():
		if def.anchor_id != "" and not anchors.has(def.anchor_id):
			load_errors.append("tile %s references missing anchor %s" % [def.id, def.anchor_id])
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
