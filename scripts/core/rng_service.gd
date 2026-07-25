class_name RngService
extends RefCounted
## Deterministic named RNG streams. Each stream is an independent seeded
## RandomNumberGenerator so (for example) loot rolls never perturb parcel rolls.
## Stream states are serialized into the save, so a reloaded game continues the
## exact sequence it would have produced — no save-scumming rare rolls.

var world_seed: int
var _streams: Dictionary = {}


func _init(seed_value: int = 0) -> void:
	world_seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system() * 1000.0) % 2147483647


func stream(stream_name: String) -> RandomNumberGenerator:
	if not _streams.has(stream_name):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s|%d" % [stream_name, world_seed])
		_streams[stream_name] = rng
	return _streams[stream_name]


func randf_range(stream_name: String, from: float, to: float) -> float:
	return stream(stream_name).randf_range(from, to)


func randi_range(stream_name: String, from: int, to: int) -> int:
	return stream(stream_name).randi_range(from, to)


func chance(stream_name: String, probability: float) -> bool:
	return stream(stream_name).randf() < probability


## Weighted pick over [{..., "weight": float}]; returns empty Dictionary when empty.
func weighted(stream_name: String, entries: Array) -> Dictionary:
	var total := 0.0
	for entry in entries:
		total += float(entry.get("weight", 1.0))
	if total <= 0.0:
		return {}
	var roll := stream(stream_name).randf() * total
	for entry in entries:
		roll -= float(entry.get("weight", 1.0))
		if roll <= 0.0:
			return entry
	return entries.back()


func to_save_dict() -> Dictionary:
	var states := {}
	for key: String in _streams:
		states[key] = {"seed": _streams[key].seed, "state": _streams[key].state}
	return {"world_seed": world_seed, "streams": states}


func from_save_dict(data: Dictionary) -> void:
	world_seed = int(data.get("world_seed", world_seed))
	_streams.clear()
	var states: Dictionary = data.get("streams", {})
	for key: String in states:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(states[key].get("seed", 0))
		rng.state = int(states[key].get("state", 0))
		_streams[key] = rng
