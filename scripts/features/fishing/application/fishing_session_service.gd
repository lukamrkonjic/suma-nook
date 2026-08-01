class_name FishingSessionService
extends RefCounted
## The explicit fishing state machine. Tick-driven (GameCore.tick advances it)
## so the whole session runs headless and deterministically; presentation only
## listens to its signals. There is no failure path: a cast that reaches its
## bite always delivers the same catch, whether the player reels or not.

signal fishing_started(anchor: Vector2i)
signal cast_started(context: FishingRollContext, duration: float)
signal waiting_started(duration: float)
signal bite_started(window: float)
signal manual_reel_started(duration: float)
signal auto_reel_started(duration: float)
signal haul_generated(haul: FishingHaul)
signal reveal_started(haul: FishingHaul, duration: float)
signal haul_committed(haul: FishingHaul)
signal basket_full_paused
signal fishing_stopped(reason: String)

const States := FishingSessionStates.State

var balance: FishingBalance
var habitat_query: WorldHabitatQuery
var generator: FishingRewardGenerator
var delivery: RewardDeliveryPort
var pouch: SpiritPouchService
var luck: HiddenLuckService
var rng: RngService

var state: States = States.IDLE
var anchor := Vector2i.ZERO
var context: FishingRollContext = null

## Supplied by the composition root: builds the per-cast context extras
## (unlock groups, owned keepsakes, first-catch flag).
var context_builder: Callable = Callable()
## Called with no arguments after a first catch commits, so the module can
## record first_catch_done.
var first_catch_recorder: Callable = Callable()

var _time_left := 0.0
var _pending_haul: FishingHaul = null
var _reserved_spirit_id := ""


func _init(
	balance_config: FishingBalance,
	world_habitat: WorldHabitatQuery,
	reward_generator: FishingRewardGenerator,
	reward_delivery: RewardDeliveryPort,
	pouch_service: SpiritPouchService,
	luck_service: HiddenLuckService,
	rng_service: RngService
) -> void:
	balance = balance_config
	habitat_query = world_habitat
	generator = reward_generator
	delivery = reward_delivery
	pouch = pouch_service
	luck = luck_service
	rng = rng_service
	delivery.slot_freed.connect(_on_slot_freed)


func is_active() -> bool:
	return state != States.IDLE


func state_name() -> String:
	return FishingSessionStates.state_name(state)


func begin_session(fishing_anchor: Vector2i) -> bool:
	if state != States.IDLE:
		return false
	anchor = fishing_anchor
	fishing_started.emit(anchor)
	if delivery.is_full():
		state = States.PAUSED_BASKET_FULL
		basket_full_paused.emit()
		return true
	_start_cast()
	return true


## The fishing input pressed during the bite retrieves the same catch faster.
## Pressing it at any other moment does nothing — there is nothing to fail.
func request_manual_reel() -> bool:
	if state != States.BITE:
		return false
	state = States.MANUAL_REELING
	_time_left = balance.timing("manual_reel_seconds", 1.8)
	manual_reel_started.emit(_time_left)
	return true


func cancel(reason := "cancelled") -> void:
	if state == States.IDLE:
		return
	_release_reservation()
	_pending_haul = null
	state = States.IDLE
	fishing_stopped.emit(reason)


func advance(delta: float) -> void:
	if state == States.IDLE or state == States.PAUSED_BASKET_FULL:
		return
	_time_left -= delta
	if _time_left > 0.0:
		return
	match state:
		States.CASTING:
			_start_waiting()
		States.WAITING:
			_start_bite()
		States.BITE:
			state = States.AUTO_REELING
			_time_left = balance.timing("auto_reel_seconds", 2.6)
			auto_reel_started.emit(_time_left)
		States.MANUAL_REELING, States.AUTO_REELING:
			_start_reveal()
		States.REVEALING:
			_commit_pending_haul()


func _start_cast(extra_delay := 0.0) -> void:
	# The reward context is snapshotted now: the current catch keeps the world
	# as it was when the line went out.
	var sample := habitat_query.sample(anchor)
	context = FishingRollContext.new(sample)
	if context_builder.is_valid():
		context_builder.call(context)
	_reserved_spirit_id = pouch.reserve_armed()
	context.spirit_theme = pouch.theme_for(_reserved_spirit_id)
	state = States.CASTING
	_time_left = balance.timing("cast_seconds", 1.2) + extra_delay
	cast_started.emit(context, _time_left)


func _start_waiting() -> void:
	state = States.WAITING
	var wait := rng.randf_range(
		"fishing_wait",
		balance.timing("wait_min_seconds", 8.0),
		balance.timing("wait_max_seconds", 16.0)
	)
	# Clamp the whole idle path under the intended maximum so timer and
	# animation composition can never exceed it.
	var worst_tail := (
		balance.timing("bite_window_seconds", 6.0)
		+ balance.timing("auto_reel_seconds", 2.6)
		+ balance.timing("reveal_seconds", 1.4)
	)
	var allowed := (
		balance.timing("total_max_seconds", 30.0)
		- balance.timing("cast_seconds", 1.2)
		- worst_tail
	)
	_time_left = clampf(wait, 0.5, maxf(0.5, allowed))
	waiting_started.emit(_time_left)


func _start_bite() -> void:
	# The haul is generated at the bite, before the player chooses how to
	# react: manual and automatic retrieval provably share one reward.
	_pending_haul = generator.generate_haul(context)
	haul_generated.emit(_pending_haul)
	state = States.BITE
	_time_left = balance.timing("bite_window_seconds", 6.0)
	bite_started.emit(_time_left)


func _start_reveal() -> void:
	state = States.REVEALING
	_time_left = balance.timing("reveal_seconds", 1.4)
	reveal_started.emit(_pending_haul, _time_left)


func _commit_pending_haul() -> void:
	if _pending_haul == null:
		cancel("empty_haul")
		return
	if not delivery.commit(_pending_haul):
		# Delivery refused (basket full): keep the haul, keep the Spirit
		# reservation, keep protection untouched, and wait for room.
		state = States.PAUSED_BASKET_FULL
		basket_full_paused.emit()
		return
	var haul := _pending_haul
	_pending_haul = null
	haul.spirit_id = pouch.consume_reserved()
	_reserved_spirit_id = ""
	luck.on_haul_committed(haul)
	if context != null and context.first_catch_pending and first_catch_recorder.is_valid():
		first_catch_recorder.call()
	haul_committed.emit(haul)
	if delivery.is_full():
		state = States.PAUSED_BASKET_FULL
		basket_full_paused.emit()
		return
	_recast()


func _recast() -> void:
	# The between-cast breath folds into the fresh cast timer.
	_start_cast(balance.timing("recast_pause_seconds", 0.8))


func _on_slot_freed() -> void:
	if state != States.PAUSED_BASKET_FULL:
		return
	if _pending_haul != null:
		_commit_pending_haul()
	else:
		_recast()


func _release_reservation() -> void:
	if _reserved_spirit_id != "":
		pouch.release_reserved()
		_reserved_spirit_id = ""
