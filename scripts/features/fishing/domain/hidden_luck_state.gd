class_name HiddenLuckState
extends RefCounted
## Invisible bad-luck protection counters. No UI ever reads these; they only
## nudge weights inside the reward generator and reset when the matching
## reward is successfully committed.

var catches_since_rare := 0
var catches_since_keepsake := 0


func to_save_dict() -> Dictionary:
	return {
		"catches_since_rare": catches_since_rare,
		"catches_since_keepsake": catches_since_keepsake,
	}


func from_save_dict(data: Dictionary) -> void:
	catches_since_rare = maxi(0, int(data.get("catches_since_rare", 0)))
	catches_since_keepsake = maxi(0, int(data.get("catches_since_keepsake", 0)))
