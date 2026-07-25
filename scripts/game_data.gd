extends RefCounted
class_name GameData

const BuildDef := preload("res://scripts/data/build_item_definition.gd")
const TokenDef := preload("res://scripts/data/token_definition.gd")

var items: Dictionary = {}
var tokens: Dictionary = {}
var beginner: Dictionary = {}
var tuning: Dictionary = {}


func load_all() -> bool:
	items.clear()
	tokens.clear()
	for row: Variant in _load_json_array("res://data/items.json"):
		var definition: BuildItemDefinition = BuildDef.from_dict(row)
		if definition.id == &"" or items.has(definition.id):
			push_error("Invalid or duplicate item definition: %s" % definition.id)
			return false
		items[definition.id] = definition
	for row: Variant in _load_json_array("res://data/tokens.json"):
		var token: TokenDefinition = TokenDef.from_dict(row)
		if token.id == &"" or tokens.has(token.id):
			push_error("Invalid or duplicate token definition: %s" % token.id)
			return false
		tokens[token.id] = token
	beginner = _load_json_dict("res://data/beginner_rewards.json")
	tuning = _load_json_dict("res://data/tuning.json")
	return not items.is_empty() and not tokens.is_empty()


func item(id: StringName) -> BuildItemDefinition:
	return items.get(id) as BuildItemDefinition


func token(id: StringName) -> TokenDefinition:
	return tokens.get(id) as TokenDefinition


func item_ids_for_pool(pool: StringName) -> PackedStringArray:
	var result := PackedStringArray()
	for id: StringName in items:
		var definition: BuildItemDefinition = items[id]
		if String(pool) in definition.reward_pools:
			result.append(String(id))
	return result


func ground_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for id: StringName in items:
		if (items[id] as BuildItemDefinition).is_ground():
			result.append(String(id))
	return result


static func _load_json_array(path: String) -> Array:
	var value: Variant = _load_json(path)
	if value is Array:
		return value
	push_error("Expected JSON array at %s" % path)
	return []


static func _load_json_dict(path: String) -> Dictionary:
	var value: Variant = _load_json(path)
	if value is Dictionary:
		return value
	push_error("Expected JSON object at %s" % path)
	return {}


static func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Missing data file: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open data file: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("Invalid JSON: %s" % path)
	return parsed

