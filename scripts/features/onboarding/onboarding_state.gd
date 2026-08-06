class_name OnboardingState
extends RefCounted
## Saved build-first opening. Guided pieces are ordinary stock; this state only
## remembers which real piece and source instance advances the lesson.

signal stage_changed(stage: String)

const PLACE_TREE := "place_tree"
const WAIT_TREE := "wait_tree"
const HARVEST_TREE := "harvest_tree"
const PLACE_FOREST_REWARD := "place_forest_reward"
const WAIT_VISITOR := "wait_visitor"
const PLACE_VISITOR_REWARD := "place_visitor_reward"
const COMPLETE := "complete"

const STAGES := [
	PLACE_TREE,
	WAIT_TREE,
	HARVEST_TREE,
	PLACE_FOREST_REWARD,
	WAIT_VISITOR,
	PLACE_VISITOR_REWARD,
	COMPLETE,
]

var stage := COMPLETE
var guided_kind := ""
var guided_id := ""
var starter_tree_instance_id := 0


func begin(starter_tree_id := "struct_pine_young") -> void:
	starter_tree_instance_id = 0
	guide_piece(PLACE_TREE, "structure", starter_tree_id)


func set_stage(next_stage: String) -> bool:
	if next_stage not in STAGES or next_stage == stage:
		return false
	stage = next_stage
	guided_kind = ""
	guided_id = ""
	_clear_finished_tree_reference()
	stage_changed.emit(stage)
	return true


func guide_piece(next_stage: String, kind: String, content_id: String) -> bool:
	if next_stage not in STAGES or kind not in ["tile", "structure"]:
		return false
	stage = next_stage
	guided_kind = kind
	guided_id = content_id
	_clear_finished_tree_reference()
	stage_changed.emit(stage)
	return true


func tree_placed(instance_id: int) -> bool:
	if stage != PLACE_TREE or instance_id <= 0:
		return false
	starter_tree_instance_id = instance_id
	return set_stage(WAIT_TREE)


func tree_ready(instance_id: int) -> bool:
	return (
		instance_id == starter_tree_instance_id
		and stage == WAIT_TREE
		and set_stage(HARVEST_TREE)
	)


func is_active() -> bool:
	return stage != COMPLETE


func requires_guided_placement() -> bool:
	return stage in [PLACE_TREE, PLACE_FOREST_REWARD, PLACE_VISITOR_REWARD]


func to_save_dict() -> Dictionary:
	return {
		"stage": stage,
		"guided_kind": guided_kind,
		"guided_id": guided_id,
		"starter_tree_instance_id": starter_tree_instance_id,
	}


func from_save_dict(data: Dictionary) -> void:
	var restored := String(data.get("stage", COMPLETE))
	stage = restored if restored in STAGES else COMPLETE
	guided_kind = String(data.get("guided_kind", ""))
	guided_id = String(data.get("guided_id", ""))
	starter_tree_instance_id = maxi(
		0, int(data.get("starter_tree_instance_id", 0))
	)
	if not requires_guided_placement():
		guided_kind = ""
		guided_id = ""
	_clear_finished_tree_reference()
	stage_changed.emit(stage)


func _clear_finished_tree_reference() -> void:
	if stage not in [PLACE_TREE, WAIT_TREE, HARVEST_TREE]:
		starter_tree_instance_id = 0
