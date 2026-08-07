class_name FirstsSystem
extends RefCounted
## Transformation triggers. Each First is one manifest entry listening to a
## world signal by name; no code per First, and — enforced design rule — no
## discovery UI may render before a First fires. Firsts appear in the
## journal only afterwards.

signal first_fired(payload: Dictionary)

var registries: Registries
var grid: WorldGrid
var world: NookWorld
var events: WorldEvents
var journal: DiscoveryJournal
var enabled := true

## World-scoped firsts that have fired (chunk-scoped live on the record).
var fired_world: Dictionary = {}

var _now_provider: Callable


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
	enabled = regs.feature("nook_firsts_enabled", true)
	_now_provider = now_provider
	var system_ref: WeakRef = weakref(self)
	events.world_signal.connect(func(name: String, payload: Dictionary):
		var system: FirstsSystem = system_ref.get_ref() as FirstsSystem
		if system != null:
			system._on_world_signal(name, payload)
	)


func _on_world_signal(name: String, payload: Dictionary) -> void:
	if not enabled or name == "first_fired":
		return
	# Generation must never fire transformation triggers: a Nook arriving
	# with water is not the player bringing water to a dry Nook.
	if String(payload.get("source", "")) == "generation":
		return
	for first in registries.firsts.values():
		if first.signal_name != name:
			continue
		_try_fire(first, payload)


func _try_fire(first: NookDefs.FirstDefinition, payload: Dictionary) -> void:
	var chunk: Vector2i = payload.get("nook", Vector2i.ZERO)
	if not payload.has("nook") and payload.has("coord"):
		chunk = world.chunk_of_cell(payload.get("coord", Vector2i.ZERO))
	var record := world.nook(chunk)
	if first.scope == "chunk":
		if record == null:
			return
		if first.once_per_chunk and record.firsts_fired.has(first.id):
			return
	else:
		if fired_world.has(first.id):
			return
	if first.chunk_lacked_tag != "":
		var trigger_cell: Vector2i = payload.get(
			"coord", Vector2i(2147483647, 2147483647)
		)
		if ChunkFacts.chunk_has_tag(
			grid, world, chunk, first.chunk_lacked_tag, trigger_cell
		):
			return
	# Fire.
	if first.scope == "chunk" and record != null:
		record.firsts_fired.append(first.id)
		world.touch(chunk)
	else:
		fired_world[first.id] = true
	for structure_id in first.unlock_structures:
		journal.unlock_structure(structure_id)
	for tile_id in first.unlock_tiles:
		journal.unlock_tile(tile_id)
	if first.journal_text != "":
		journal.add_entry("first", first.id, first.journal_text, chunk, _now())
	var fired := {
		"nook": chunk,
		"first_id": first.id,
		"name": first.display_name,
		"ambient_fx": first.ambient_fx,
	}
	events.publish("first_fired", fired)
	first_fired.emit(fired)


func to_save_dict() -> Dictionary:
	return {"fired_world": fired_world.keys()}


func from_save_dict(data: Dictionary) -> void:
	fired_world.clear()
	for id: Variant in data.get("fired_world", []):
		fired_world[String(id)] = true


func _now() -> float:
	if _now_provider.is_valid():
		return float(_now_provider.call())
	return Time.get_unix_time_from_system()
