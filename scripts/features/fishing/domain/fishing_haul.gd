class_name FishingHaul
extends RefCounted
## One completed catch: one to three normal reward entries plus an optional
## keepsake bonus. A whole haul — even a Bountiful triple — occupies exactly
## one Catch Basket slot.

const SIZE_SINGLE := "single"
const SIZE_RICH := "rich"
const SIZE_BOUNTIFUL := "bountiful"

var haul_id := 0                     # stable unique id, assigned at commit
var catch_size := SIZE_SINGLE
var entries: Array[FishingReward] = []
var keepsake: FishingReward = null
var spirit_id := ""                  # spirit consumed for this catch, if any
var dominant_theme := ""             # presentation hint from the habitat


func entry_count() -> int:
	return entries.size()


func has_keepsake() -> bool:
	return keepsake != null


func has_rare_entry() -> bool:
	for entry: FishingReward in entries:
		if entry.is_rare():
			return true
	return false


func tile_bundle_count() -> int:
	var count := 0
	for entry: FishingReward in entries:
		if entry.form == FishingReward.FORM_TILE_BUNDLE:
			count += 1
	return count


func model_count() -> int:
	var count := 0
	for entry: FishingReward in entries:
		if entry.form == FishingReward.FORM_MODEL:
			count += 1
	return count


func primary_entry() -> FishingReward:
	return entries[0] if not entries.is_empty() else keepsake


func to_dict() -> Dictionary:
	var serialized_entries: Array = []
	for entry: FishingReward in entries:
		serialized_entries.append(entry.to_dict())
	var data := {
		"haul_id": haul_id,
		"catch_size": catch_size,
		"entries": serialized_entries,
		"spirit_id": spirit_id,
		"dominant_theme": dominant_theme,
	}
	if keepsake != null:
		data["keepsake"] = keepsake.to_dict()
	return data


static func from_dict(data: Dictionary) -> FishingHaul:
	var haul := FishingHaul.new()
	haul.haul_id = int(data.get("haul_id", 0))
	haul.catch_size = String(data.get("catch_size", SIZE_SINGLE))
	for raw_entry in data.get("entries", []):
		if raw_entry is Dictionary:
			haul.entries.append(FishingReward.from_dict(raw_entry))
	if data.get("keepsake", null) is Dictionary:
		haul.keepsake = FishingReward.from_dict(data["keepsake"])
	haul.spirit_id = String(data.get("spirit_id", ""))
	haul.dominant_theme = String(data.get("dominant_theme", ""))
	return haul
