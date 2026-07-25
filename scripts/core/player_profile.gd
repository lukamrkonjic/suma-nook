class_name PlayerProfile
extends RefCounted
## Character identity + continuous transform. The position is a float Vector3
## and the facing a float angle — saved exactly, never grid-quantized.

signal profile_changed

var display_name := "Keeper"
var skin_index := 1
var hair_style := 0      # 0..3 → Hair00..Hair03 meshes
var hair_color_index := 0
var eye_index := 0       # 0 wide | 1 sleepy | 2 bright (eye scale/spacing variant)
var outfit_index := 0

var position := Vector3.ZERO
var facing := 0.0        # radians around Y


func to_save_dict() -> Dictionary:
	return {
		"name": display_name,
		"skin": skin_index, "hair_style": hair_style, "hair_color": hair_color_index,
		"eyes": eye_index, "outfit": outfit_index,
		"px": position.x, "py": position.y, "pz": position.z, "facing": facing,
	}


func from_save_dict(data: Dictionary) -> void:
	display_name = String(data.get("name", "Keeper"))
	skin_index = int(data.get("skin", 1))
	hair_style = int(data.get("hair_style", 0))
	hair_color_index = int(data.get("hair_color", 0))
	eye_index = int(data.get("eyes", 0))
	outfit_index = int(data.get("outfit", 0))
	position = Vector3(float(data.get("px", 0)), float(data.get("py", 0)), float(data.get("pz", 0)))
	facing = float(data.get("facing", 0.0))
	profile_changed.emit()
