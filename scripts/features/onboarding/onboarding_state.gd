class_name OnboardingState
extends RefCounted
## Saved first-session state machine for the fishing loop: choose a biome,
## fish the void from an exposed edge, then place what the first haul brought
## back. Free play begins with the placement lesson complete; Spirits and the
## basket introduce themselves through ordinary play.

signal stage_changed(stage: String)

const LAND_CHOICE := "land_choice"
const TRY_VOID_FISHING := "try_void_fishing"
const PLACE_DISCOVERY := "place_discovery"
const COMPLETE := "complete"

const STAGES := [
	LAND_CHOICE,
	TRY_VOID_FISHING,
	PLACE_DISCOVERY,
	COMPLETE,
]

var stage := COMPLETE
var guided_kind := ""
var guided_id := ""


func begin() -> void:
	guided_kind = ""
	guided_id = ""
	set_stage(LAND_CHOICE)


func set_stage(next_stage: String) -> bool:
	if next_stage not in STAGES or next_stage == stage:
		return false
	stage = next_stage
	guided_kind = ""
	guided_id = ""
	stage_changed.emit(stage)
	return true


func guide_piece(next_stage: String, kind: String, content_id: String) -> bool:
	if next_stage not in STAGES or kind not in ["tile", "structure"]:
		return false
	stage = next_stage
	guided_kind = kind
	guided_id = content_id
	stage_changed.emit(stage)
	return true


func is_active() -> bool:
	return stage != COMPLETE


func requires_guided_placement() -> bool:
	return stage == PLACE_DISCOVERY


func to_save_dict() -> Dictionary:
	return {
		"stage": stage,
		"guided_kind": guided_kind,
		"guided_id": guided_id,
	}


func from_save_dict(data: Dictionary) -> void:
	var restored := String(data.get("stage", COMPLETE))
	stage = restored if restored in STAGES else COMPLETE
	guided_kind = String(data.get("guided_kind", ""))
	guided_id = String(data.get("guided_id", ""))
	if not requires_guided_placement():
		guided_kind = ""
		guided_id = ""
	stage_changed.emit(stage)
