class_name CharacterAppearancePreset
extends Resource
## One complete serializable appearance: a body profile, the selected part for
## each slot, and the color channels. The default player character is entirely
## described by such a preset; no appearance is hard-coded in scene-building
## code.

@export var preset_id := ""
@export var body_profile: CharacterBodyProfile
@export var parts: Array[CharacterPartDefinition] = []

@export_group("Colors")
@export var skin_color := Color("e0b06c")
@export var hair_color := Color("543826")
@export var brow_color := Color("543826")
@export var moustache_color := Color("543826")
@export var eye_color := Color("241a14")
@export var mouth_color := Color("5c372a")


func part_in_slot(slot: String) -> CharacterPartDefinition:
	for part in parts:
		if part != null and part.slot == slot:
			return part
	return null


func color_for_channel(channel: String) -> Color:
	match channel:
		"skin":
			return skin_color
		"hair":
			return hair_color
		"brows":
			return brow_color
		"moustache":
			return moustache_color
		"eyes":
			return eye_color
		"mouth":
			return mouth_color
	return Color.WHITE


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if body_profile == null:
		errors.append("preset has no body_profile")
	else:
		errors.append_array(body_profile.validation_errors())
	var seen_slots: Dictionary = {}
	for part in parts:
		if part == null:
			errors.append("preset contains a null part")
			continue
		errors.append_array(part.validation_errors())
		if seen_slots.has(part.slot):
			errors.append(
				"preset selects more than one part for slot '%s'" % part.slot
			)
		seen_slots[part.slot] = true
		if (
			body_profile != null
			and not part.supports_body(body_profile.profile_id)
		):
			errors.append(
				"part '%s' does not support body '%s'"
				% [part.part_id, body_profile.profile_id]
			)
	return errors
