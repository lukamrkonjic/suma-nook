class_name CharacterSlots
extends RefCounted
## Canonical equipment slots for the modular character system. Paired features
## (eyes, brows) are single parts so their symmetry can never drift.

const HAIR := "HAIR"
const EYEBROWS := "EYEBROWS"
const EYES := "EYES"
const NOSE := "NOSE"
const MOUTH := "MOUTH"
const MOUSTACHE := "MOUSTACHE"
const BEARD := "BEARD"
const HEADWEAR := "HEADWEAR"
const TOP_INNER := "TOP_INNER"
const TOP_OUTER := "TOP_OUTER"
const BOTTOM := "BOTTOM"
const SHOES := "SHOES"
const GLOVES := "GLOVES"
const BACK := "BACK"
const ACCESSORY := "ACCESSORY"

const ALL: PackedStringArray = [
	HAIR, EYEBROWS, EYES, NOSE, MOUTH, MOUSTACHE, BEARD, HEADWEAR,
	TOP_INNER, TOP_OUTER, BOTTOM, SHOES, GLOVES, BACK, ACCESSORY,
]

## Default socket for each face slot. Rigid accessory sockets follow the
## HandSocket_L / HandSocket_R / BackSocket / ChestSocket / HipSocket_L /
## HipSocket_R naming convention as they are introduced.
const DEFAULT_SOCKETS := {
	HAIR: "HairSocket",
	EYEBROWS: "BrowsSocket",
	EYES: "EyesSocket",
	NOSE: "NoseSocket",
	MOUTH: "MouthSocket",
	MOUSTACHE: "MoustacheSocket",
	BEARD: "BeardSocket",
	HEADWEAR: "HatSocket",
}


static func is_valid(slot: String) -> bool:
	return ALL.has(slot)
