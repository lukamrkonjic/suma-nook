class_name ShrineSystem
extends RefCounted
## The player's visible targeting tool. Setting a discovered item on the
## shrine biases Vision draws toward that item and its family — for farming
## deliberate duplicates (ten pines for a forest) or closing in on a set's
## last pieces. One focus is active at a time; multiple shrines sharing a
## focus is a later design decision.

signal focus_changed(kind: String, id: String)

var registries: Registries
var collection: CollectionManager

var focus_kind := ""   # "tile" | "structure" | ""
var focus_id := ""


func _init(regs: Registries, collection_manager: CollectionManager) -> void:
	registries = regs
	collection = collection_manager


func has_focus() -> bool:
	return focus_kind != "" and focus_id != ""


func focus() -> Dictionary:
	if not has_focus():
		return {}
	return {"kind": focus_kind, "id": focus_id}


## Discovery is the ownership proxy: anything the journal has recorded has
## been genuinely held (stocked or placed) at least once.
func can_focus(kind: String, content_id: String) -> bool:
	match kind:
		VisionSystem.KIND_TILE:
			return (
				registries.tile(content_id) != null
				and collection.is_discovered("tiles", content_id)
			)
		VisionSystem.KIND_STRUCTURE:
			return (
				registries.structure(content_id) != null
				and collection.is_discovered("structures", content_id)
			)
	return false


func set_focus(kind: String, content_id: String) -> bool:
	if not can_focus(kind, content_id):
		return false
	focus_kind = kind
	focus_id = content_id
	focus_changed.emit(focus_kind, focus_id)
	return true


func clear_focus() -> void:
	if not has_focus():
		return
	focus_kind = ""
	focus_id = ""
	focus_changed.emit("", "")


func to_save_dict() -> Dictionary:
	return {"kind": focus_kind, "id": focus_id}


func from_save_dict(data: Dictionary) -> void:
	focus_kind = String(data.get("kind", ""))
	focus_id = String(data.get("id", ""))
	var known := (
		(focus_kind == VisionSystem.KIND_TILE and registries.tile(focus_id) != null)
		or (
			focus_kind == VisionSystem.KIND_STRUCTURE
			and registries.structure(focus_id) != null
		)
	)
	if not known:
		focus_kind = ""
		focus_id = ""
