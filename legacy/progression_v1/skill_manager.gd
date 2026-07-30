class_name SkillManager
extends RefCounted
## XP, levels, and data-driven level unlocks for every skill. Unlock side
## effects (granting a parcel, revealing a recipe) are resolved by GameCore
## listening to level_up so this class stays pure and testable.

signal xp_gained(skill_id: String, amount: int, new_total: int)
signal level_up(skill_id: String, new_level: int, unlocks: Array)

var registries: Registries
var xp: Dictionary = {}       # skill_id -> xp toward next level
var levels: Dictionary = {}   # skill_id -> level (starts at 1)
var lifetime_actions: Dictionary = {}   # skill_id -> total actions performed


func _init(regs: Registries) -> void:
	registries = regs
	for skill_id: String in regs.skills:
		xp[skill_id] = 0
		levels[skill_id] = 1
		lifetime_actions[skill_id] = 0


func level(skill_id: String) -> int:
	return int(levels.get(skill_id, 1))


func xp_progress(skill_id: String) -> Dictionary:
	var def := registries.skill(skill_id)
	if def == null:
		return {"current": 0, "needed": 1, "fraction": 0.0}
	var needed := def.xp_to_next(level(skill_id))
	var current := int(xp.get(skill_id, 0))
	return {"current": current, "needed": needed, "fraction": clampf(float(current) / needed, 0.0, 1.0)}


func is_playable(skill_id: String) -> bool:
	var def := registries.skill(skill_id)
	return def != null and not def.future


func add_xp(skill_id: String, amount: int) -> void:
	var def := registries.skill(skill_id)
	if def == null or amount <= 0:
		return
	xp[skill_id] = int(xp.get(skill_id, 0)) + amount
	xp_gained.emit(skill_id, amount, xp[skill_id])
	while levels[skill_id] < def.max_level and xp[skill_id] >= def.xp_to_next(levels[skill_id]):
		xp[skill_id] -= def.xp_to_next(levels[skill_id])
		levels[skill_id] += 1
		level_up.emit(skill_id, levels[skill_id], unlocks_at(skill_id, levels[skill_id]))


func record_action(skill_id: String) -> void:
	lifetime_actions[skill_id] = int(lifetime_actions.get(skill_id, 0)) + 1


func unlocks_at(skill_id: String, at_level: int) -> Array:
	var def := registries.skill(skill_id)
	if def == null:
		return []
	return def.unlocks.filter(func(u): return int(u.get("level", 0)) == at_level)


## Everything already unlocked (level <= current) of a given kind.
func unlocked(skill_id: String, kind: String) -> Array[String]:
	var result: Array[String] = []
	var def := registries.skill(skill_id)
	if def == null:
		return result
	for u in def.unlocks:
		if String(u.get("kind", "")) == kind and int(u.get("level", 0)) <= level(skill_id):
			result.append(String(u.get("id", "")))
	return result


## Next few meaningful goals for the skills panel.
func upcoming_unlocks(skill_id: String, limit := 3) -> Array:
	var def := registries.skill(skill_id)
	if def == null:
		return []
	var future_unlocks: Array = def.unlocks.filter(func(u): return int(u.get("level", 0)) > level(skill_id))
	future_unlocks.sort_custom(func(a, b): return int(a["level"]) < int(b["level"]))
	return future_unlocks.slice(0, limit)


func recipe_available(recipe: Defs.RecipeDefinition) -> bool:
	for skill_id: String in recipe.unlock:
		if level(skill_id) < int(recipe.unlock[skill_id]):
			return false
	return true


func to_save_dict() -> Dictionary:
	return {"xp": xp.duplicate(), "levels": levels.duplicate(), "actions": lifetime_actions.duplicate()}


func from_save_dict(data: Dictionary) -> void:
	var saved_levels: Dictionary = data.get("levels", {})
	var saved_xp: Dictionary = data.get("xp", {})
	var saved_actions: Dictionary = data.get("actions", {})
	for skill_id: String in registries.skills:
		levels[skill_id] = int(saved_levels.get(skill_id, 1))
		xp[skill_id] = int(saved_xp.get(skill_id, 0))
		lifetime_actions[skill_id] = int(saved_actions.get(skill_id, 0))
