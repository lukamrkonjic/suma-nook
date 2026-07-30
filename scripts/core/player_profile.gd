class_name PlayerProfile
extends RefCounted
## Character identity + continuous transform. The position is a float Vector3
## and the facing a float angle — saved exactly, never grid-quantized.

signal profile_changed

var display_name := "Keeper"
var body_index := 0      # index into CharacterBodyCatalog
var skin_index := 0
var hair_style := 0      # index into the hair catalog (CharacterPartCatalog)
var hair_color_index := 0
var eye_index := 0       # index into the eye catalog
var mouth_index := 0     # index into the mouth catalog
var nose_index := 0      # index into the nose catalog
var outfit_index := 0
var starter_land_id := "tile_grass"   # the arrival land pick; world begins here

var position := Vector3.ZERO
var facing := 0.0        # radians around Y


func to_save_dict() -> Dictionary:
	return {
		"name": display_name,
		"body": body_index,
		"skin": skin_index, "hair_style": hair_style, "hair_color": hair_color_index,
		"eyes": eye_index, "mouth": mouth_index, "nose": nose_index,
		"outfit": outfit_index,
		"starter_land": starter_land_id,
		"px": position.x, "py": position.y, "pz": position.z, "facing": facing,
	}


func from_save_dict(data: Dictionary) -> void:
	display_name = String(data.get("name", "Keeper"))
	body_index = int(data.get("body", 0))
	skin_index = int(data.get("skin", 1))
	hair_style = int(data.get("hair_style", 0))
	hair_color_index = int(data.get("hair_color", 0))
	eye_index = int(data.get("eyes", 0))
	mouth_index = int(data.get("mouth", 0))
	nose_index = int(data.get("nose", 0))
	outfit_index = int(data.get("outfit", 0))
	starter_land_id = String(data.get("starter_land", "tile_grass"))
	position = Vector3(float(data.get("px", 0)), float(data.get("py", 0)), float(data.get("pz", 0)))
	facing = float(data.get("facing", 0.0))
	profile_changed.emit()
