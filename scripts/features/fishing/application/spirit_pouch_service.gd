class_name SpiritPouchService
extends RefCounted
## Application face of the five-slot Spirit Pouch. Wraps the pure pouch state
## with definition validation and the signals presentation listens to.

signal pouch_changed
signal spirit_added(spirit_id: String)
signal spirit_rejected_full(spirit_id: String)
signal spirit_reserved(spirit_id: String)
signal spirit_consumed(spirit_id: String)
signal spirit_released(spirit_id: String)

var registries: Registries
var state: SpiritPouchState


func _init(regs: Registries, capacity: int) -> void:
	registries = regs
	state = SpiritPouchState.new(capacity)


func capacity() -> int:
	return state.capacity


func slots() -> Array[String]:
	return state.slots.duplicate()


func armed_spirit_id() -> String:
	return state.armed_spirit_id()


func armed_index() -> int:
	return state.armed_index


func is_full() -> bool:
	return state.is_full()


## One completed valid activity may add one Spirit. When the pouch is full the
## charm is not stored anywhere else — the caller shows gentle feedback.
func add_spirit(spirit_id: String) -> bool:
	if registries.spirit(spirit_id) == null:
		return false
	if not state.add(spirit_id):
		spirit_rejected_full.emit(spirit_id)
		return false
	spirit_added.emit(spirit_id)
	pouch_changed.emit()
	return true


func arm_slot(slot_index: int) -> bool:
	if not state.arm(slot_index):
		return false
	pouch_changed.emit()
	return true


## Selecting Wild Cast clears the armed Spirit without destroying anything.
func select_wild_cast() -> void:
	state.clear_armed()
	pouch_changed.emit()


func reserve_armed() -> String:
	var spirit_id := state.reserve_armed()
	if spirit_id != "":
		spirit_reserved.emit(spirit_id)
	return spirit_id


func consume_reserved() -> String:
	var spirit_id := state.consume_reserved()
	if spirit_id != "":
		spirit_consumed.emit(spirit_id)
		pouch_changed.emit()
	return spirit_id


func release_reserved() -> void:
	if not state.has_reservation():
		return
	var spirit_id := state.armed_spirit_id()
	state.release_reserved()
	spirit_released.emit(spirit_id)
	pouch_changed.emit()


func theme_for(spirit_id: String) -> String:
	var definition := registries.spirit(spirit_id)
	return definition.theme_tag if definition != null else ""


func to_save_dict() -> Dictionary:
	return state.to_save_dict()


func from_save_dict(data: Dictionary) -> void:
	state.from_save_dict(
		data,
		func(spirit_id: String) -> bool:
			return registries.spirit(spirit_id) != null
	)
	pouch_changed.emit()
