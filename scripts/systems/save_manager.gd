class_name SaveManager
extends RefCounted
## Versioned atomic persistence: serialize → temp file → validate → rename,
## with one rotating backup. Loading tolerates missing definitions (they are
## dropped with warnings, never crashes) and refuses files from future schema
## versions rather than corrupting them.

signal saved(path: String)
signal load_failed(reason: String)

var registries: Registries
var save_path: String
var backup_path: String


func _init(regs: Registries) -> void:
	registries = regs
	save_path = String(regs.tune("save_path", "user://suma_nook_world.json"))
	backup_path = save_path + ".backup"


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func write(payload: Dictionary) -> bool:
	payload["save_version"] = registries.tunei("save_version", 1)
	payload["content_revision"] = registries.tunei("content_revision", 0)
	payload["timestamp"] = Time.get_datetime_string_from_system()
	var text := JSON.stringify(payload, "  ")
	var temp_path := save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot open %s for writing" % temp_path)
		return false
	file.store_string(text)
	file.close()
	# Validate the temp file parses before it replaces anything.
	var verify: Variant = JSON.parse_string(FileAccess.get_file_as_string(temp_path))
	if not verify is Dictionary:
		push_error("SaveManager: temp save failed validation; keeping previous save")
		DirAccess.remove_absolute(temp_path)
		return false
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(save_path, backup_path)
	var err := DirAccess.rename_absolute(temp_path, save_path)
	if err != OK:
		push_error("SaveManager: rename failed (%s)" % err)
		return false
	saved.emit(save_path)
	return true


func read() -> Dictionary:
	for path in [save_path, backup_path]:
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			var version := int(parsed.get("save_version", 0))
			if version > registries.tunei("save_version", 1):
				load_failed.emit("save is from a newer version")
				return {}
			if path == backup_path:
				push_warning("SaveManager: primary save unreadable, recovered from backup")
			return parsed
	load_failed.emit("no readable save file")
	return {}


func delete_save() -> void:
	for path in [save_path, backup_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
