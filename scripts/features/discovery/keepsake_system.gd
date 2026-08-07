class_name KeepsakeSystem
extends RefCounted
## Witness catalog. Moments are data-defined observers — lifetime counters
## and chunk co-occurrences — that mint keepsake objects when they happen.
## Keepsakes are pure output: they gate nothing, ever.

signal keepsake_minted(payload: Dictionary)

var registries: Registries
var grid: WorldGrid
var world: NookWorld
var events: WorldEvents
var journal: DiscoveryJournal
var enabled := true

var counters: Dictionary = {}   # signal name -> lifetime count
var minted: Dictionary = {}     # moment id -> true

var _now_provider: Callable
## Chunk-fact conditions -> predicate. New conditions register here; data
## declares which ones a moment needs.
var _condition_checks: Dictionary = {}


func _init(
	regs: Registries,
	world_grid: WorldGrid,
	nook_world: NookWorld,
	world_events: WorldEvents,
	discovery_journal: DiscoveryJournal,
	now_provider: Callable = Callable()
) -> void:
	registries = regs
	grid = world_grid
	world = nook_world
	events = world_events
	journal = discovery_journal
	enabled = regs.feature("nook_keepsakes_enabled", true)
	_now_provider = now_provider
	_condition_checks = {
		"warm_light": func(chunk: Vector2i) -> bool:
			return ChunkFacts.chunk_has_capability(grid, world, chunk, "light"),
		"water": func(chunk: Vector2i) -> bool:
			return ChunkFacts.chunk_has_tag(grid, world, chunk, "water"),
		"tree": func(chunk: Vector2i) -> bool:
			return ChunkFacts.chunk_has_tag(grid, world, chunk, "tree"),
	}
	var system_ref: WeakRef = weakref(self)
	events.world_signal.connect(func(name: String, payload: Dictionary):
		var system: KeepsakeSystem = system_ref.get_ref() as KeepsakeSystem
		if system != null:
			system._on_world_signal(name, payload)
	)


## Ambient facts (time of day, weather) come from presentation state; the
## scene-side owner refreshes them, listeners never poll rendering.
var ambient_facts: Dictionary = {}


func set_ambient_fact(fact: String, value: bool) -> void:
	ambient_facts[fact] = value


func _on_world_signal(name: String, payload: Dictionary) -> void:
	if not enabled or name == "keepsake_minted":
		return
	if String(payload.get("source", "")) == "generation":
		return
	counters[name] = int(counters.get(name, 0)) + 1
	var chunk: Vector2i = payload.get("nook", Vector2i.ZERO)
	if not payload.has("nook") and payload.has("coord"):
		chunk = world.chunk_of_cell(payload.get("coord", Vector2i.ZERO))
	for moment in registries.moments.values():
		if minted.has(moment.id):
			continue
		match moment.kind:
			"counter":
				if moment.signal_name == name \
					and int(counters.get(name, 0)) >= moment.count:
					_mint(moment, chunk)
			"cooccurrence":
				if _conditions_hold(moment, chunk):
					_mint(moment, chunk)


func _conditions_hold(
	moment: NookDefs.MomentDefinition, chunk: Vector2i
) -> bool:
	if not world.has_nook(chunk):
		return false
	for condition in moment.conditions:
		if ambient_facts.has(condition):
			if not bool(ambient_facts[condition]):
				return false
			continue
		var check: Variant = _condition_checks.get(condition)
		if check is Callable:
			if not bool((check as Callable).call(chunk)):
				return false
			continue
		return false
	return true


func _mint(moment: NookDefs.MomentDefinition, chunk: Vector2i) -> void:
	minted[moment.id] = true
	if moment.keepsake_structure_id != "":
		journal.unlock_structure(moment.keepsake_structure_id)
	if moment.journal_text != "":
		journal.add_entry(
			"keepsake", moment.id, moment.journal_text, chunk, _now()
		)
	var payload := {
		"nook": chunk,
		"moment_id": moment.id,
		"name": moment.display_name,
		"keepsake_structure_id": moment.keepsake_structure_id,
	}
	events.publish("keepsake_minted", payload)
	keepsake_minted.emit(payload)


func to_save_dict() -> Dictionary:
	return {
		"counters": counters.duplicate(true),
		"minted": minted.keys(),
	}


func from_save_dict(data: Dictionary) -> void:
	counters.clear()
	for key: Variant in data.get("counters", {}):
		counters[String(key)] = int((data.get("counters", {}) as Dictionary)[key])
	minted.clear()
	for id: Variant in data.get("minted", []):
		minted[String(id)] = true


func _now() -> float:
	if _now_provider.is_valid():
		return float(_now_provider.call())
	return Time.get_unix_time_from_system()
