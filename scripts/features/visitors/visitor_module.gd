class_name VisitorModule
extends RefCounted
## Presentation-neutral global heartbeat. The pending event contains its
## pre-rolled reward and replaceable presentation id, so neither can be
## rerolled by reloading or by changing scene adapters.

signal visitor_available(event: Dictionary)
signal visitor_collected(event: Dictionary, reward: Dictionary)
signal timer_changed(seconds_remaining: float)

var registries: Registries
var rng: RngService
var grid: WorldGrid
var rewards: RefCounted
var enabled := true
var arrival_allowed := true
var program: Defs.VisitorProgramDefinition
var time_until_next := 0.0
var visitors_created := 0
var current_event: Dictionary = {}


func _init(
	regs: Registries,
	rng_service: RngService,
	world_grid: WorldGrid,
	reward_service: RefCounted
) -> void:
	registries = regs
	rng = rng_service
	grid = world_grid
	rewards = reward_service
	enabled = registries.feature("visitor_events_enabled", true)
	program = registries.visitor_program(
		String(registries.tune("visitor_program_id", ""))
	)
	_schedule_next(true)


func tick(delta: float) -> void:
	if not enabled or program == null or not current_event.is_empty():
		return
	time_until_next = maxf(0.0, time_until_next - maxf(0.0, delta))
	timer_changed.emit(time_until_next)
	if time_until_next <= 0.0 and arrival_allowed:
		trigger_now()


func trigger_now() -> Dictionary:
	if (
		not enabled
		or not arrival_allowed
		or program == null
		or not current_event.is_empty()
	):
		return {}
	var cell := _choose_arrival_cell()
	if cell == Vector2i(999999, 999999):
		# The world may be temporarily detached while moving a tile stack. Retry
		# soon without consuming an event id or RNG reward roll.
		time_until_next = 2.0
		return {}
	var presentation := _choose_presentation()
	if presentation == null:
		return {}
	var first := visitors_created == 0
	var pool_id := (
		program.first_reward_pool_id if first else program.reward_pool_id
	)
	var pre_rolled: Dictionary = rewards.call(
		"roll", pool_id, "visitors:reward:%d" % (visitors_created + 1)
	)
	if pre_rolled.is_empty():
		return {}
	current_event = {
		"event_id": visitors_created + 1,
		"program_id": program.id,
		"presentation_id": presentation.id,
		"cell": [cell.x, cell.y],
		"reward": pre_rolled,
		"first": first,
	}
	visitor_available.emit(current_event.duplicate(true))
	return current_event.duplicate(true)


func collect(event_id: int) -> Dictionary:
	if current_event.is_empty() or int(current_event.get("event_id", 0)) != event_id:
		return {}
	var event := current_event.duplicate(true)
	var granted: Dictionary = rewards.call(
		"grant", (current_event.get("reward", {}) as Dictionary).duplicate(true)
	)
	if granted.is_empty():
		return {}
	current_event.clear()
	visitors_created += 1
	_schedule_next(false)
	visitor_collected.emit(event, granted.duplicate(true))
	return granted


func has_waiting_visitor() -> bool:
	return not current_event.is_empty()


func waiting_event() -> Dictionary:
	return current_event.duplicate(true)


func event_cell() -> Vector2i:
	var raw: Array = current_event.get("cell", [])
	return (
		Vector2i(int(raw[0]), int(raw[1]))
		if raw.size() >= 2
		else Vector2i(999999, 999999)
	)


func announce_waiting_visitor() -> void:
	if not current_event.is_empty():
		visitor_available.emit(current_event.duplicate(true))


func to_save_dict() -> Dictionary:
	return {
		"program_id": program.id if program != null else "",
		"time_until_next": time_until_next,
		"visitors_created": visitors_created,
		"current_event": current_event.duplicate(true),
	}


func from_save_dict(data: Dictionary) -> void:
	var saved_program := String(data.get("program_id", ""))
	if saved_program != "" and registries.visitor_program(saved_program) != null:
		program = registries.visitor_program(saved_program)
	time_until_next = maxf(0.0, float(data.get("time_until_next", time_until_next)))
	visitors_created = maxi(0, int(data.get("visitors_created", 0)))
	current_event = _normalize_event(
		(data.get("current_event", {}) as Dictionary).duplicate(true)
	)
	if not _event_is_valid(current_event):
		current_event.clear()
		if time_until_next <= 0.0:
			_schedule_next(visitors_created == 0)


func _schedule_next(first: bool) -> void:
	if program == null:
		time_until_next = 0.0
		return
	var minimum := program.first_min_seconds if first else program.later_min_seconds
	var maximum := program.first_max_seconds if first else program.later_max_seconds
	time_until_next = rng.randf_range(
		"visitors:schedule", minimum, maxf(minimum, maximum)
	)


func _choose_presentation() -> Defs.VisitorPresentationDefinition:
	var entries: Array = []
	for presentation_id: String in program.presentation_ids:
		var presentation := registries.visitor_presentation(presentation_id)
		if presentation != null:
			entries.append({"id": presentation.id, "weight": presentation.weight})
	var chosen := rng.weighted("visitors:presentation", entries)
	return (
		registries.visitor_presentation(String(chosen.get("id", "")))
		if not chosen.is_empty() else null
	)


func _choose_arrival_cell() -> Vector2i:
	var candidates: Array[Vector2i] = []
	for slot: Dictionary in grid.all_cell_slots():
		var coord: Vector2i = slot["coord"]
		var elevation := int(slot["elevation"])
		if elevation != grid.top_elevation(coord):
			continue
		var state: WorldGrid.CellState = slot["state"]
		var definition := grid.tile_def_at(coord, elevation)
		if (
			definition != null
			and definition.walkable
			and state.structures.is_empty()
			and state.landmark_id == ""
		):
			candidates.append(coord)
	if candidates.is_empty():
		return Vector2i(999999, 999999)
	return candidates[rng.randi_range(
		"visitors:cell", 0, candidates.size() - 1
	)]


func _event_is_valid(event: Dictionary) -> bool:
	if event.is_empty():
		return false
	var presentation_id := String(event.get("presentation_id", ""))
	var reward: Dictionary = event.get("reward", {})
	var kind := String(reward.get("kind", ""))
	var content_id := String(reward.get("id", ""))
	return (
		registries.visitor_presentation(presentation_id) != null
		and (
			(kind == "tile" and registries.tile(content_id) != null)
			or (kind == "structure" and registries.structure(content_id) != null)
		)
		and int(reward.get("amount", 0)) > 0
	)


func _normalize_event(event: Dictionary) -> Dictionary:
	if event.is_empty():
		return {}
	var raw_cell: Array = event.get("cell", [])
	var reward: Dictionary = (
		event.get("reward", {}) as Dictionary
	).duplicate(true)
	if raw_cell.size() >= 2:
		event["cell"] = [int(raw_cell[0]), int(raw_cell[1])]
	event["event_id"] = int(event.get("event_id", 0))
	event["first"] = bool(event.get("first", false))
	reward["amount"] = int(reward.get("amount", 0))
	event["reward"] = reward
	return event
