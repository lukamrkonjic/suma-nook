class_name RewardDeliveryPort
extends RefCounted
## Narrow contract for physically staging finished hauls. The session never
## knows how hauls are displayed or taken — only whether a commit succeeded
## and whether the container has room.

signal slot_freed


func commit(_haul: FishingHaul) -> bool:
	return false


func is_full() -> bool:
	return false
