class_name ArrivalScheduler
extends RefCounted
## Saveable, presentation-agnostic periodic delivery state. At most one
## delivery can exist; its timer pauses until the chosen tile is safely stored.

signal arrival_requested(payload: LandParcelPayload)
signal delivery_ready(payload: LandParcelPayload)
signal delivery_resolved
signal timer_changed(seconds_remaining: float)

const IDLE := "idle"
const ARRIVING := "arriving"
const WAITING := "waiting"
const OPENED := "opened"

var registries: Registries
var rng: RngService
var state := IDLE
var time_until_next := 0.0
var paused := false
var deliveries_created := 0
var current_payload: LandParcelPayload


func _init(regs: Registries, rng_service: RngService) -> void:
	registries = regs
	rng = rng_service
	_schedule_next(true)


func tick(delta: float) -> void:
	if (
		not registries.feature("ferry_arrivals_enabled", true)
		or paused
		or state != IDLE
	):
		return
	time_until_next = maxf(0.0, time_until_next - delta)
	timer_changed.emit(time_until_next)
	if time_until_next <= 0.0:
		trigger_arrival()


func trigger_arrival() -> bool:
	if state != IDLE or not registries.feature("ferry_arrivals_enabled", true):
		return false
	current_payload = LandParcelPayload.new()
	current_payload.parcel_id = String(registries.arrival_config.get("parcel_id", "parcel_wild"))
	current_payload.delivery_id = deliveries_created + 1
	if not current_payload.is_valid(registries):
		current_payload = null
		return false
	state = ARRIVING
	arrival_requested.emit(current_payload)
	return true


func mark_delivery_ready(payload: LandParcelPayload) -> void:
	if state != ARRIVING or payload == null:
		return
	current_payload = payload
	state = WAITING
	delivery_ready.emit(current_payload)


func has_waiting_package() -> bool:
	return state == WAITING and current_payload != null


func open_waiting(parcels: ParcelManager) -> Array[String]:
	if not has_waiting_package() or parcels.has_pending():
		return []
	var options := parcels.deliver(current_payload.parcel_id)
	if not options.is_empty():
		state = OPENED
	return options


func resolve_delivery() -> void:
	if state not in [WAITING, OPENED]:
		return
	state = IDLE
	current_payload = null
	deliveries_created += 1
	_schedule_next(false)
	delivery_resolved.emit()


func force_departure_ready() -> void:
	if state == ARRIVING and current_payload != null:
		mark_delivery_ready(current_payload)


func _schedule_next(first: bool) -> void:
	var prefix := "first" if first else "later"
	var minimum := float(registries.arrival_config.get("%s_arrival_min_seconds" % prefix, 60.0))
	var maximum := float(registries.arrival_config.get("%s_arrival_max_seconds" % prefix, minimum))
	time_until_next = rng.randf_range("arrival_schedule", minimum, maxf(minimum, maximum))


func to_save_dict() -> Dictionary:
	return {
		"state": state,
		"time_until_next": time_until_next,
		"paused": paused,
		"deliveries_created": deliveries_created,
		"payload": current_payload.to_dict() if current_payload != null else {},
	}


func from_save_dict(data: Dictionary) -> void:
	state = String(data.get("state", IDLE))
	time_until_next = maxf(0.0, float(data.get("time_until_next", time_until_next)))
	paused = bool(data.get("paused", false))
	deliveries_created = maxi(0, int(data.get("deliveries_created", 0)))
	var payload_data: Dictionary = data.get("payload", {})
	current_payload = LandParcelPayload.from_dict(payload_data) if not payload_data.is_empty() else null
	# A quit during the animation recovers as a safe package at the dock.
	if state == ARRIVING:
		state = WAITING
	if current_payload == null and state != IDLE:
		state = IDLE


func announce_restored_delivery() -> void:
	if has_waiting_package():
		delivery_ready.emit(current_payload)
