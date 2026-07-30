class_name OnboardingState
extends RefCounted
## Saved first-session state machine. It introduces one world-making verb at
## a time and guarantees that the water, well, tree, first Vision, and fishing
## routes can never be skipped or lost.

signal stage_changed(stage: String)

const LAND_CHOICE := "land_choice"
const PLACE_WATER := "place_water"
const PLACE_SECOND_LAND := "place_second_land"
const PLACE_WELL := "place_well"
const PLACE_TREE := "place_tree"
const TEND_TREE := "tend_tree"
const CLAIM_VISION := "claim_vision"
const PLACE_VISION := "place_vision"
const TRY_FISHING := "try_fishing"
const COMPLETE := "complete"

const STAGES := [
	LAND_CHOICE,
	PLACE_WATER,
	PLACE_SECOND_LAND,
	PLACE_WELL,
	PLACE_TREE,
	TEND_TREE,
	CLAIM_VISION,
	PLACE_VISION,
	TRY_FISHING,
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
	return stage in [
		PLACE_WATER,
		PLACE_SECOND_LAND,
		PLACE_WELL,
		PLACE_TREE,
		PLACE_VISION,
	]


func to_save_dict() -> Dictionary:
	return {
		"stage": stage,
		"guided_kind": guided_kind,
		"guided_id": guided_id,
	}


func from_save_dict(data: Dictionary) -> void:
	# Saves created before the authored onboarding are established worlds and
	# must never be pulled backward into the opening sequence.
	var restored := String(data.get("stage", COMPLETE))
	stage = restored if restored in STAGES else COMPLETE
	guided_kind = String(data.get("guided_kind", ""))
	guided_id = String(data.get("guided_id", ""))
	if not requires_guided_placement():
		guided_kind = ""
		guided_id = ""
	stage_changed.emit(stage)
