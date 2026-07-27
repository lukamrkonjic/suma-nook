class_name PlayerArmorRegions
extends RefCounted
## Stable semantic coverage contract shared by player meshes and worn armor.
##
## The production player stores one region id per triangle in UV2.x. Armor
## definitions list the regions they replace; PlayerVisual converts that list
## into a per-instance shader bitmask. This mirrors Imota Idle's Armor Studio
## approach while using finer shoulder, arm, knee, shin, and foot regions.

const REGION_IDS := {
	"head": 0,
	"neck": 1,
	"chest": 2,
	"abdomen": 3,
	"hips": 4,
	"shoulder_l": 5,
	"upper_arm_l": 6,
	"forearm_l": 7,
	"hand_l": 8,
	"shoulder_r": 9,
	"upper_arm_r": 10,
	"forearm_r": 11,
	"hand_r": 12,
	"thigh_l": 13,
	"knee_l": 14,
	"shin_l": 15,
	"foot_l": 16,
	"thigh_r": 17,
	"knee_r": 18,
	"shin_r": 19,
	"foot_r": 20,
	"clavicle_l": 21,
	"shoulder_cap_l": 22,
	"armpit_l": 23,
	"upper_chest_l": 24,
	"upper_arm_inner_l": 25,
	"clavicle_r": 26,
	"shoulder_cap_r": 27,
	"armpit_r": 28,
	"upper_chest_r": 29,
	"upper_arm_inner_r": 30,
}


static func mask_for(regions: Array[String]) -> int:
	var mask := 0
	for region in regions:
		assert(
			REGION_IDS.has(region),
			"Unknown player armor region '%s'" % region
		)
		mask |= 1 << int(REGION_IDS[region])
	return mask


static func names() -> Array[String]:
	var result: Array[String] = []
	result.assign(REGION_IDS.keys())
	result.sort_custom(func(a: String, b: String) -> bool:
		return int(REGION_IDS[a]) < int(REGION_IDS[b])
	)
	return result


static func unknown_regions(regions: Array[String]) -> PackedStringArray:
	var unknown := PackedStringArray()
	for region in regions:
		if not REGION_IDS.has(region):
			unknown.append(region)
	return unknown
