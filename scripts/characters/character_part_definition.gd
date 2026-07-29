class_name CharacterPartDefinition
extends Resource
## One selectable visual part (a hairstyle, an eye pair, a moustache, a shirt).
## Adding a new part means authoring its asset, creating one of these
## definitions, and setting fit data — never editing CharacterAssembler.

const ATTACHMENT_RIGID := "rigid"
const ATTACHMENT_SKINNED := "skinned"

@export_group("Identity")
@export var part_id := ""
@export var display_name := ""
@export var slot := ""
@export var compatibility_tags: PackedStringArray = []

@export_group("Asset")
@export var scene: PackedScene
@export_enum("rigid", "skinned") var attachment_type := "rigid"
## Target socket. Empty uses the slot's canonical socket
## (CharacterSlots.DEFAULT_SOCKETS).
@export var socket := ""

@export_group("Compatibility")
## Empty means: fits every body profile.
@export var compatible_body_profiles: PackedStringArray = []
@export var fits: Array[CharacterPartFit] = []

@export_group("Interactions")
## Body regions this part covers (PlayerArmorRegions names), e.g. a shirt
## hides ["chest", "abdomen"].
@export var hidden_regions: PackedStringArray = []
## Slots this part suppresses while equipped, e.g. HEADWEAR hides HAIR.
@export var hides_slots: PackedStringArray = []

@export_group("Color")
## Named tint channel the appearance preset drives ("skin", "hair", "brows",
## "moustache", "eyes", "mouth", ""). Empty keeps authored materials.
@export var color_channel := ""


func resolved_socket() -> String:
	if not socket.is_empty():
		return socket
	return String(CharacterSlots.DEFAULT_SOCKETS.get(slot, ""))


func supports_body(profile_id: String) -> bool:
	return (
		compatible_body_profiles.is_empty()
		or compatible_body_profiles.has(profile_id)
	)


func fit_for(profile_id: String) -> CharacterPartFit:
	for fit in fits:
		if fit != null and fit.body_profile_id == profile_id:
			return fit
	return null


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if part_id.is_empty():
		errors.append("part_id is empty")
	if not CharacterSlots.is_valid(slot):
		errors.append("part '%s' has unknown slot '%s'" % [part_id, slot])
	if scene == null:
		errors.append("part '%s' has no scene" % part_id)
	if attachment_type == ATTACHMENT_RIGID and resolved_socket().is_empty():
		errors.append("part '%s' resolves to no socket" % part_id)
	for fit in fits:
		if fit == null:
			errors.append("part '%s' has a null fit entry" % part_id)
		else:
			errors.append_array(fit.validation_errors())
	return errors
