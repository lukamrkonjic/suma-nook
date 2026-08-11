class_name ContributionService
extends RefCounted
## Narrow adapter between world activities and Project state. Sources ask for
## a target before starting, then commit one idempotent receipt on completion.

signal contribution_accepted(result: Dictionary)
signal contribution_rejected(result: Dictionary)

var projects: ProjectService


func _init(project_service: ProjectService) -> void:
	projects = project_service


func target_for(tags: Array[String]) -> Dictionary:
	return projects.target_for_tags(_normalize(tags))


func accepts_any(tags: Array[String]) -> bool:
	return not target_for(tags).is_empty()


func contribute(
	tags: Array[String],
	receipt_id: String,
	metadata: Dictionary = {},
	target: Dictionary = {}
) -> Dictionary:
	var resolved := target.duplicate(true)
	if resolved.is_empty():
		resolved = target_for(tags)
	if resolved.is_empty():
		var rejected := {"accepted": false, "reason": "not_needed"}
		contribution_rejected.emit(rejected.duplicate(true))
		return rejected
	var result := projects.contribute(
		String(resolved.get("project_id", "")),
		int(resolved.get("slot_index", -1)),
		receipt_id,
		1,
		metadata
	)
	if bool(result.get("accepted", false)):
		contribution_accepted.emit(result.duplicate(true))
	else:
		contribution_rejected.emit(result.duplicate(true))
	return result


func _normalize(tags: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for raw_tag: String in tags:
		var tag := raw_tag.to_lower()
		if not tag.is_empty() and not result.has(tag):
			result.append(tag)
	return result
