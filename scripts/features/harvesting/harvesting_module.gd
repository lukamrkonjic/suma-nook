class_name HarvestingModule
extends RefCounted
## Authoritative, presentation-free lifecycle for every harvest_source
## capability. Runtime lives on the stable structure instance so placement,
## storage, save, and future automation all share one state.

signal source_state_changed(instance_id: int, state: String, status: Dictionary)
signal hit_landed(instance_id: int, hit: Dictionary)
signal reward_granted(instance_id: int, reward: Dictionary)

const STATE_MATURING := "maturing"
const STATE_READY := "ready"
const STATE_REGROWING := "regrowing"
const RUNTIME_KEY := "harvest"

var registries: Registries
var rng: RngService
var grid: WorldGrid
var rewards: RefCounted
var enabled := true
var first_rewards_claimed: Dictionary = {}
var reward_history: Dictionary = {} # home_collection -> recent tokens + rare misses
var total_cycles := 0

var _now_provider: Callable
var _schedule: Array[Dictionary] = []


func _init(
	regs: Registries,
	rng_service: RngService,
	world_grid: WorldGrid,
	reward_service: RefCounted,
	now_provider: Callable = Callable()
) -> void:
	registries = regs
	rng = rng_service
	grid = world_grid
	rewards = reward_service
	enabled = registries.feature("harvesting_enabled", true)
	_now_provider = now_provider
	var module_ref: WeakRef = weakref(self)
	grid.slot_changed.connect(func(coord, elevation):
		var module: HarvestingModule = module_ref.get_ref() as HarvestingModule
		if module != null:
			module._sync_slot(coord, elevation)
	)
	rebuild_schedule()


func tick(_delta: float) -> void:
	if not enabled:
		return
	var now := _now()
	while not _schedule.is_empty() and float(_schedule[0]["deadline"]) <= now:
		var due: Dictionary = _schedule.pop_front()
		var instance_id := int(due["instance_id"])
		var found := grid.find_structure(instance_id)
		if found.is_empty():
			continue
		var structure: WorldGrid.StructureState = found["structure"]
		var runtime := _runtime(structure, false)
		if runtime.is_empty():
			continue
		if not is_equal_approx(
			float(runtime.get("deadline_unix", 0.0)),
			float(due["deadline"])
		):
			continue
		_normalize_due(structure, now)


func rebuild_schedule() -> void:
	_schedule.clear()
	if not enabled:
		return
	for slot: Dictionary in grid.all_cell_slots():
		_sync_slot(slot["coord"], int(slot["elevation"]))


func can_harvest(instance_id: int) -> bool:
	return profile_for_instance(instance_id) != null


func profile_for_instance(instance_id: int) -> Defs.HarvestProfileDefinition:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return null
	return profile_for_structure(found["structure"])


func profile_for_structure(
	structure: WorldGrid.StructureState
) -> Defs.HarvestProfileDefinition:
	if structure == null:
		return null
	var definition := registries.structure(structure.structure_id)
	if definition == null or not definition.has_capability("harvest_source"):
		return null
	var profile_id := String(
		definition.capability("harvest_source").get("profile_id", "")
	)
	return registries.harvest_profile(profile_id)


func status(instance_id: int) -> Dictionary:
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return {}
	var structure: WorldGrid.StructureState = found["structure"]
	var profile := profile_for_structure(structure)
	if profile == null:
		return {}
	var runtime := _runtime(structure)
	_normalize_due(structure, _now())
	runtime = _runtime(structure, false)
	return _status_dictionary(profile, runtime)


## One call equals one deliberate click/confirm. Automation can use the same
## port with actor="helper"; helpers are prevented from taking the final hit.
func request_hit(instance_id: int, actor := "player") -> Dictionary:
	if not enabled:
		return {"accepted": false, "reason": "disabled"}
	var found := grid.find_structure(instance_id)
	if found.is_empty():
		return {"accepted": false, "reason": "missing"}
	var structure: WorldGrid.StructureState = found["structure"]
	var profile := profile_for_structure(structure)
	if profile == null:
		return {"accepted": false, "reason": "not_harvestable"}
	var runtime := _runtime(structure)
	_normalize_due(structure, _now())
	runtime = _runtime(structure, false)
	if String(runtime.get("state", STATE_MATURING)) != STATE_READY:
		return {
			"accepted": false,
			"reason": String(runtime.get("state", STATE_MATURING)),
			"remaining": maxf(0.0, float(runtime.get("deadline_unix", 0.0)) - _now()),
		}
	var next_hit := int(runtime.get("hits", 0)) + 1
	if actor != "player" and next_hit >= profile.hits_required:
		return {"accepted": false, "reason": "final_hit_reserved"}
	runtime["hits"] = next_hit
	var final := next_hit >= profile.hits_required
	var hit := {
		"accepted": true,
		"instance_id": instance_id,
		"actor": actor,
		"hit": next_hit,
		"hits_required": profile.hits_required,
		"progress": float(next_hit) / float(profile.hits_required),
		"penultimate": next_hit == profile.hits_required - 1,
		"final": final,
		"profile_id": profile.id,
		"verb": profile.verb,
		"presentation": profile.presentation_profile,
		"reveal_profile_id": profile.reveal_profile_id,
	}
	if final:
		runtime["state"] = STATE_REGROWING
		runtime["hits"] = 0
		runtime["cycles"] = int(runtime.get("cycles", 0)) + 1
		runtime["deadline_unix"] = _now() + profile.regrowth_seconds
		total_cycles += 1
		var pool_id := profile.reward_pool_id
		if (
			profile.first_reward_pool_id != ""
			and not bool(first_rewards_claimed.get(profile.id, false))
		):
			pool_id = profile.first_reward_pool_id
			first_rewards_claimed[profile.id] = true
		var history := _reward_history_for(profile.home_collection)
		var reward: Dictionary = rewards.call(
			"roll_and_grant",
			pool_id,
			"harvest:%s:%d" % [profile.id, int(runtime["cycles"])],
			profile.roll_policy_id,
			history
		)
		_update_reward_history(profile, reward)
		hit["reward"] = reward.duplicate(true)
		_schedule_instance(instance_id, float(runtime["deadline_unix"]))
		reward_granted.emit(instance_id, reward.duplicate(true))
		source_state_changed.emit(
			instance_id, STATE_REGROWING, _status_dictionary(profile, runtime)
		)
	hit_landed.emit(instance_id, hit.duplicate(true))
	return hit


func remaining_seconds(instance_id: int) -> float:
	var current := status(instance_id)
	return float(current.get("remaining", 0.0))


func to_save_dict() -> Dictionary:
	return {
		"first_rewards_claimed": first_rewards_claimed.duplicate(true),
		"reward_history": reward_history.duplicate(true),
		"total_cycles": total_cycles,
	}


func from_save_dict(data: Dictionary) -> void:
	first_rewards_claimed = (
		data.get("first_rewards_claimed", {}) as Dictionary
	).duplicate(true)
	reward_history = (
		data.get("reward_history", {}) as Dictionary
	).duplicate(true)
	total_cycles = maxi(0, int(data.get("total_cycles", 0)))
	rebuild_schedule()


func _reward_history_for(home_collection: String) -> Dictionary:
	if not reward_history.has(home_collection):
		reward_history[home_collection] = {
			"recent": [],
			"rare_misses": 0,
		}
	return reward_history[home_collection]


func _update_reward_history(
	profile: Defs.HarvestProfileDefinition,
	reward: Dictionary
) -> void:
	if reward.is_empty():
		return
	var history := _reward_history_for(profile.home_collection)
	var recent: Array = history.get("recent", [])
	recent.append("%s:%s" % [reward.get("kind", ""), reward.get("id", "")])
	var policy := registries.reward_roll_policy(profile.roll_policy_id)
	var memory := policy.recent_memory if policy != null else 0
	while recent.size() > memory:
		recent.pop_front()
	history["recent"] = recent
	history["rare_misses"] = (
		0
		if String(reward.get("rarity", "common")) == "rare"
		else maxi(0, int(history.get("rare_misses", 0))) + 1
	)


func _sync_slot(coord: Vector2i, elevation: int) -> void:
	var state := grid.cell_at(coord, elevation)
	if state == null:
		return
	for structure: WorldGrid.StructureState in state.structures:
		var profile := profile_for_structure(structure)
		if profile == null:
			continue
		var runtime := _runtime(structure)
		_normalize_due(structure, _now())
		runtime = _runtime(structure, false)
		var deadline := float(runtime.get("deadline_unix", 0.0))
		if deadline > _now():
			_schedule_instance(structure.instance_id, deadline)


func _runtime(
	structure: WorldGrid.StructureState,
	initialize := true
) -> Dictionary:
	var runtime: Variant = structure.runtime_state.get(RUNTIME_KEY, {})
	if runtime is Dictionary and not runtime.is_empty():
		return runtime
	if not initialize:
		return {}
	var profile := profile_for_structure(structure)
	if profile == null:
		return {}
	var ready_immediately := profile.maturation_seconds <= 0.0
	runtime = {
		"profile_id": profile.id,
		"state": STATE_READY if ready_immediately else STATE_MATURING,
		"hits": 0,
		"deadline_unix": 0.0 if ready_immediately else _now() + profile.maturation_seconds,
		"cycles": 0,
		"visual_seed": abs(hash("harvest|%d" % structure.instance_id)),
	}
	structure.runtime_state[RUNTIME_KEY] = runtime
	source_state_changed.emit(
		structure.instance_id, String(runtime["state"]),
		_status_dictionary(profile, runtime)
	)
	return runtime


func _normalize_due(
	structure: WorldGrid.StructureState,
	now: float
) -> void:
	var runtime := _runtime(structure, false)
	if runtime.is_empty():
		return
	var state := String(runtime.get("state", STATE_MATURING))
	if state == STATE_READY or float(runtime.get("deadline_unix", 0.0)) > now:
		return
	runtime["state"] = STATE_READY
	runtime["hits"] = 0
	runtime["deadline_unix"] = 0.0
	var profile := profile_for_structure(structure)
	if profile != null:
		source_state_changed.emit(
			structure.instance_id, STATE_READY,
			_status_dictionary(profile, runtime)
		)


func _status_dictionary(
	profile: Defs.HarvestProfileDefinition,
	runtime: Dictionary
) -> Dictionary:
	return {
		"profile_id": profile.id,
		"state": String(runtime.get("state", STATE_MATURING)),
		"hits": int(runtime.get("hits", 0)),
		"hits_required": profile.hits_required,
		"remaining": maxf(0.0, float(runtime.get("deadline_unix", 0.0)) - _now()),
		"cycles": int(runtime.get("cycles", 0)),
		"verb": profile.verb,
		"tool_icon": profile.tool_icon,
		"home_collection": profile.home_collection,
		"presentation": profile.presentation_profile,
	}


func _schedule_instance(instance_id: int, deadline: float) -> void:
	if deadline <= 0.0:
		return
	_schedule.append({"instance_id": instance_id, "deadline": deadline})
	_schedule.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["deadline"]) < float(b["deadline"])
	)


func _now() -> float:
	if _now_provider.is_valid():
		return float(_now_provider.call())
	return Time.get_unix_time_from_system()
