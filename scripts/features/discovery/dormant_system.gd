class_name DormantSystem
extends RefCounted
## One dormant mystery per Nook, woken by accumulated nearby life — never a
## prompt, never a bar. The score ticks invisibly; when it crosses the
## threshold the wake is deferred to the start of the player's next session
## in view: you arrive, and it has changed.

signal dormant_wake_played(payload: Dictionary)

var registries: Registries
var world: NookWorld
var events: WorldEvents
var commands: WorldCommandService
var build_rewards: RefCounted
var journal: DiscoveryJournal
var enabled := true

var _now_provider: Callable
var _presence_accum: Dictionary = {}   # chunk -> seconds this minute


func _init(
	regs: Registries,
	nook_world: NookWorld,
	world_events: WorldEvents,
	command_service: WorldCommandService,
	reward_service: RefCounted,
	discovery_journal: DiscoveryJournal,
	now_provider: Callable = Callable()
) -> void:
	registries = regs
	world = nook_world
	events = world_events
	commands = command_service
	build_rewards = reward_service
	journal = discovery_journal
	enabled = regs.feature("nook_dormants_enabled", true)
	_now_provider = now_provider
	var system_ref: WeakRef = weakref(self)
	events.world_signal.connect(func(name: String, payload: Dictionary):
		var system: DormantSystem = system_ref.get_ref() as DormantSystem
		if system != null:
			system._on_world_signal(name, payload)
	)


func _score_weight(signal_name: String) -> float:
	var weights: Dictionary = registries.nook_config.get(
		"dormant_score_weights", {}
	)
	return float(weights.get(signal_name, 0.0))


func _on_world_signal(name: String, payload: Dictionary) -> void:
	if not enabled:
		return
	var weight := _score_weight(name)
	if weight <= 0.0:
		return
	if String(payload.get("source", "")) == "generation":
		return
	var chunk: Vector2i = payload.get("nook", Vector2i.ZERO)
	if not payload.has("nook") and payload.has("coord"):
		chunk = world.chunk_of_cell(payload.get("coord", Vector2i.ZERO))
	_add_score(chunk, weight)


## Main reports where the player lingers; presence is life too.
func note_presence(chunk: Vector2i, seconds: float) -> void:
	if not enabled:
		return
	var accumulated := float(_presence_accum.get(chunk, 0.0)) + seconds
	if accumulated >= 60.0:
		_add_score(chunk, _score_weight("presence_minute"))
		accumulated -= 60.0
	_presence_accum[chunk] = accumulated


func _add_score(chunk: Vector2i, amount: float) -> void:
	var record := world.nook(chunk)
	if record == null or record.dormant.is_empty():
		return
	if bool(record.dormant.get("woken", false)) \
		or bool(record.dormant.get("pending_wake", false)):
		return
	var score := float(record.dormant.get("score", 0.0)) + amount
	record.dormant["score"] = score
	var definition := registries.dormant(String(record.dormant.get("id", "")))
	var threshold := definition.wake_score if definition != null else 12.0
	if score >= threshold:
		# Crossed while playing: defer, so the change is found, not watched.
		record.dormant["pending_wake"] = true
	world.touch(chunk)


## Called once per session (after load, before play). Any pending wake in a
## revealed Nook plays now — the player arrives to find it changed.
func apply_pending_wakes() -> Array[Dictionary]:
	var woken: Array[Dictionary] = []
	if not enabled:
		return woken
	for record: NookWorld.NookRecord in world.nooks.values():
		if record.dormant.is_empty():
			continue
		if not bool(record.dormant.get("pending_wake", false)):
			continue
		if bool(record.dormant.get("woken", false)):
			continue
		var payload := _wake(record)
		if not payload.is_empty():
			woken.append(payload)
	return woken


func _wake(record: NookWorld.NookRecord) -> Dictionary:
	var definition := registries.dormant(String(record.dormant.get("id", "")))
	if definition == null:
		return {}
	record.dormant["pending_wake"] = false
	record.dormant["woken"] = true
	world.touch(record.coord)
	var result := commands.apply("wake_dormant", {
		"instance_id": int(record.dormant.get("instance_id", 0)),
		"woken_structure_id": definition.woken_structure_id,
		"dormant_id": definition.id,
		"nook": record.coord,
	})
	record.dormant["instance_id"] = int(
		result.get("instance_id", record.dormant.get("instance_id", 0))
	)
	var reward := {}
	if definition.reward_pool_id != "":
		reward = build_rewards.call(
			"roll_and_grant",
			definition.reward_pool_id,
			"dormant:%s:%d:%d" % [definition.id, record.coord.x, record.coord.y],
			"",
			{"recent": [], "rare_misses": 0}
		)
	if definition.journal_text != "":
		journal.add_entry(
			"dormant", definition.id, definition.journal_text,
			record.coord, _now()
		)
	var payload := {
		"nook": record.coord,
		"dormant_id": definition.id,
		"name": definition.display_name,
		"instance_id": int(record.dormant.get("instance_id", 0)),
		"reward": reward,
	}
	dormant_wake_played.emit(payload)
	return payload


func _now() -> float:
	if _now_provider.is_valid():
		return float(_now_provider.call())
	return Time.get_unix_time_from_system()
