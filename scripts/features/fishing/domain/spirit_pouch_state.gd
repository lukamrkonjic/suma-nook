class_name SpiritPouchState
extends RefCounted
## The five physical charm slots. Pure rules: capacity, arming, and the
## reserve → consume/release lifecycle. Not an inventory — spirits are
## individual charms, never numeric stacks.

var capacity := 5
var slots: Array[String] = []        # spirit definition ids, one per charm
var armed_index := -1                # slot armed for the next cast, -1 = Wild
var reserved_index := -1             # slot reserved by an in-flight cast


func _init(slot_capacity := 5) -> void:
	capacity = maxi(1, slot_capacity)


func count() -> int:
	return slots.size()


func is_full() -> bool:
	return slots.size() >= capacity


func armed_spirit_id() -> String:
	if armed_index < 0 or armed_index >= slots.size():
		return ""
	return slots[armed_index]


func add(spirit_id: String) -> bool:
	if spirit_id == "" or is_full():
		return false
	slots.append(spirit_id)
	return true


func arm(slot_index: int) -> bool:
	if reserved_index >= 0:
		return false   # never re-aim a cast that already reserved its charm
	if slot_index < -1 or slot_index >= slots.size():
		return false
	armed_index = slot_index
	return true


func clear_armed() -> void:
	if reserved_index < 0:
		armed_index = -1


## Reserves the armed charm for the cast that is starting. The charm stays
## visible in the pouch until the haul is safely committed.
func reserve_armed() -> String:
	if armed_index < 0 or armed_index >= slots.size() or reserved_index >= 0:
		return ""
	reserved_index = armed_index
	return slots[reserved_index]


func has_reservation() -> bool:
	return reserved_index >= 0


## Consumes the reserved charm after a successful commit.
func consume_reserved() -> String:
	if reserved_index < 0 or reserved_index >= slots.size():
		reserved_index = -1
		return ""
	var spirit_id := slots[reserved_index]
	slots.remove_at(reserved_index)
	reserved_index = -1
	armed_index = -1
	return spirit_id


## Returns the reserved charm to the pouch when a cast is cancelled.
func release_reserved() -> void:
	reserved_index = -1


func to_save_dict() -> Dictionary:
	return {
		"slots": slots.duplicate(),
		"armed_index": armed_index,
	}


func from_save_dict(data: Dictionary, valid_ids: Callable) -> void:
	slots.clear()
	reserved_index = -1
	for raw_id in data.get("slots", []):
		var spirit_id := String(raw_id)
		if slots.size() < capacity and valid_ids.call(spirit_id):
			slots.append(spirit_id)
	armed_index = int(data.get("armed_index", -1))
	if armed_index < -1 or armed_index >= slots.size():
		armed_index = -1
