class_name CollectionManager
extends RefCounted
## The field-guide record of everything discovered: tiles, structures, fish,
## materials, gear, landmarks, enemies. Entries store first-discovery time and
## totals so late-game players can see their own history.

signal discovered(category: String, id: String)

var registries: Registries
var entries: Dictionary = {}   # "category/id" -> {count, first_time, placed}


func _init(regs: Registries) -> void:
	registries = regs


func record(category: String, id: String, amount := 1) -> bool:
	var key := "%s/%s" % [category, id]
	var is_new := not entries.has(key)
	if is_new:
		entries[key] = {"count": 0, "first_time": Time.get_datetime_string_from_system(), "placed": 0}
		discovered.emit(category, id)
	entries[key]["count"] += amount
	return is_new


func record_placed(category: String, id: String) -> void:
	record(category, id, 0)
	entries["%s/%s" % [category, id]]["placed"] += 1


func is_discovered(category: String, id: String) -> bool:
	return entries.has("%s/%s" % [category, id])


func discovered_in(category: String) -> Array[String]:
	var result: Array[String] = []
	var prefix := category + "/"
	for key: String in entries:
		if key.begins_with(prefix):
			result.append(key.trim_prefix(prefix))
	result.sort()
	return result


func entry(category: String, id: String) -> Dictionary:
	return entries.get("%s/%s" % [category, id], {})


func total_discovered() -> int:
	return entries.size()


func to_save_dict() -> Dictionary:
	return {"entries": entries.duplicate(true)}


func from_save_dict(data: Dictionary) -> void:
	entries = data.get("entries", {}).duplicate(true)
