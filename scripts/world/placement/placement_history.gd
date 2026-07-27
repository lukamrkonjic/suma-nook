class_name PlacementHistory
extends RefCounted
## Bounded reversible command log. It owns history bookkeeping only; the
## controller supplies the domain operation that applies a command.

const MAX_ENTRIES := 40

var undo_entries: Array[Dictionary] = []
var redo_entries: Array[Dictionary] = []


func record(entry: Dictionary) -> void:
	undo_entries.append(entry)
	if undo_entries.size() > MAX_ENTRIES:
		undo_entries.pop_front()
	redo_entries.clear()


func undo(apply_command: Callable) -> bool:
	if undo_entries.is_empty():
		return false
	var entry: Dictionary = undo_entries.pop_back()
	if apply_command.call(entry, true):
		redo_entries.append(entry)
		return true
	undo_entries.append(entry)
	return false


func redo(apply_command: Callable) -> bool:
	if redo_entries.is_empty():
		return false
	var entry: Dictionary = redo_entries.pop_back()
	if apply_command.call(entry, false):
		undo_entries.append(entry)
		return true
	redo_entries.append(entry)
	return false


func clear() -> void:
	undo_entries.clear()
	redo_entries.clear()
