extends Node
class_name TilegardenSaveManager

signal saved(path: String)
signal loaded(path: String, missing_definition_ids: Array[String])
signal save_failed(message: String)

const SAVE_PATH := "user://tilegarden-save.json"

var save_version := 1
var save_path := SAVE_PATH


func setup(version: int, path := SAVE_PATH) -> void:
	save_version = maxi(1, version)
	save_path = path


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func write_save(payload: Dictionary) -> bool:
	var body := payload.duplicate(true)
	body["save_version"] = save_version
	body["timestamp"] = Time.get_unix_time_from_system()
	var json := JSON.stringify(body, "\t", false)
	var verify: Variant = JSON.parse_string(json)
	if not verify is Dictionary:
		save_failed.emit("Save validation failed before writing.")
		return false
	var temp_path := save_path + ".tmp"
	var backup_path := save_path + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		save_failed.emit("Could not open the temporary save file.")
		return false
	file.store_string(json)
	file.flush()
	file = null
	var recheck := FileAccess.open(temp_path, FileAccess.READ)
	if recheck == null or not JSON.parse_string(recheck.get_as_text()) is Dictionary:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		save_failed.emit("Temporary save validation failed.")
		return false
	recheck = null
	var absolute_save := ProjectSettings.globalize_path(save_path)
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	if FileAccess.file_exists(save_path):
		var backup_error := DirAccess.rename_absolute(absolute_save, absolute_backup)
		if backup_error != OK:
			save_failed.emit("Could not rotate the previous save.")
			return false
	var replace_error := DirAccess.rename_absolute(absolute_temp, absolute_save)
	if replace_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(absolute_backup, absolute_save)
		save_failed.emit("Could not atomically replace the save.")
		return false
	saved.emit(save_path)
	return true


func read_save() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		save_failed.emit("Could not open the save.")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		save_failed.emit("The save is not valid JSON.")
		return {}
	var version := int(parsed.get("save_version", 0))
	if version != save_version:
		save_failed.emit("Unsupported save version %d." % version)
		return {}
	return parsed


static func delete_paths(path: String) -> void:
	for candidate: String in [path, path + ".tmp", path + ".bak"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
