class_name TreasureSystem
extends RefCounted
## Buried-in-the-work discovery. Pure listener on feature_cleared: when the
## cleared cell carries a generation-time treasure assignment, the buried
## thing tumbles out. Deleting this system leaves clearing fully playable —
## you just find less.

signal treasure_revealed(payload: Dictionary)

var registries: Registries
var world: NookWorld
var events: WorldEvents
var build_rewards: RefCounted
var journal: DiscoveryJournal
var enabled := true

var _now_provider: Callable
## Shuffle-bag history per treasure pool, shared with the reward roll
## policy machinery so owned-item rolls converge to variants, never junk.
var _histories: Dictionary = {}


func _init(
	regs: Registries,
	nook_world: NookWorld,
	world_events: WorldEvents,
	reward_service: RefCounted,
	discovery_journal: DiscoveryJournal,
	now_provider: Callable = Callable()
) -> void:
	registries = regs
	world = nook_world
	events = world_events
	build_rewards = reward_service
	journal = discovery_journal
	enabled = regs.feature("nook_treasures_enabled", true)
	_now_provider = now_provider
	var system_ref: WeakRef = weakref(self)
	events.feature_cleared.connect(func(payload: Dictionary):
		var system: TreasureSystem = system_ref.get_ref() as TreasureSystem
		if system != null:
			system._on_feature_cleared(payload)
	)


func _on_feature_cleared(payload: Dictionary) -> void:
	if not enabled:
		return
	var coord: Vector2i = payload.get("nook", Vector2i.ZERO)
	var record := world.nook(coord)
	if record == null:
		return
	var cell: Vector2i = payload.get("coord", Vector2i.ZERO)
	var key := NookWorld.cell_key(world.local_cell(coord, cell))
	var assignment: Variant = record.treasures.get(key)
	if not assignment is Dictionary or bool(assignment.get("found", false)):
		return
	var pool_id := String(assignment.get("pool", ""))
	if pool_id == "":
		return
	assignment["found"] = true
	world.touch(coord)
	var history := _history_for(pool_id)
	var reward: Dictionary = build_rewards.call(
		"roll_and_grant",
		pool_id,
		"treasure:%d:%d:%s" % [coord.x, coord.y, key],
		"",
		history
	)
	if reward.is_empty():
		return
	var text := "Buried beneath the %s: %s." % [
		String(assignment.get("host_tag", "ground")),
		String(build_rewards.call("display_name", reward)),
	]
	journal.add_entry("treasure", pool_id, text, coord, _now())
	var revealed := {
		"nook": coord,
		"coord": cell,
		"reward": reward.duplicate(true),
		"host_tag": String(assignment.get("host_tag", "")),
	}
	events.publish("treasure_found", revealed)
	treasure_revealed.emit(revealed)


func _history_for(pool_id: String) -> Dictionary:
	if not _histories.has(pool_id):
		_histories[pool_id] = {"recent": [], "rare_misses": 0}
	return _histories[pool_id]


func to_save_dict() -> Dictionary:
	return {"histories": _histories.duplicate(true)}


func from_save_dict(data: Dictionary) -> void:
	_histories = (data.get("histories", {}) as Dictionary).duplicate(true)


func _now() -> float:
	if _now_provider.is_valid():
		return float(_now_provider.call())
	return Time.get_unix_time_from_system()
