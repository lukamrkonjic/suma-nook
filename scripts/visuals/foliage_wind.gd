extends Node
## Deterministic canopy wind for tree structures only.
##
## Terrain tiles never receive this controller. Flexible tree tiers use two
## overlapping frequencies and a height/name-weighted amplitude, while trunks
## and collision nodes remain completely rigid.

const SLOW_FREQUENCY := 0.82
const GUST_FREQUENCY := 1.91
const BASE_SWAY_DEGREES := 1.35
const TIP_SWAY_DEGREES := 2.8

var _elapsed := 0.0
var _phase := 0.0
var _parts: Array[Dictionary] = []


func setup(tree_root: Node3D, seed_value: int) -> void:
	name = "FoliageWind"
	_phase = fposmod(float(seed_value) * 0.61803398875, TAU)
	var candidates: Array[Node3D] = []
	for child in tree_root.find_children("*", "Node3D", true, false):
		var part := child as Node3D
		if part == null or part == self:
			continue
		var lower := part.name.to_lower()
		if (
			lower.contains("leaf")
			or lower.contains("tier")
			or lower.contains("canopy")
			or lower.contains("foliage")
			or lower.contains("needle")
		):
			candidates.append(part)
	if candidates.is_empty():
		set_process(false)
		return

	var maximum_height := 0.001
	for part in candidates:
		maximum_height = maxf(maximum_height, part.position.y)
	for index in candidates.size():
		var part := candidates[index]
		var lower := part.name.to_lower()
		var height_weight := clampf(part.position.y / maximum_height, 0.0, 1.0)
		var layer_weight := float(index + 1) / float(candidates.size())
		var flexibility := maxf(height_weight, layer_weight * 0.72)
		if lower.contains("leaf"):
			flexibility = minf(1.0, flexibility + 0.18)
		_parts.append({
			"node": part,
			"base_rotation": part.rotation,
			"phase": _phase + float(index) * 0.77,
			"amplitude": deg_to_rad(lerpf(
				BASE_SWAY_DEGREES,
				TIP_SWAY_DEGREES,
				flexibility
			)),
		})


func _process(delta: float) -> void:
	_elapsed += delta
	for entry in _parts:
		var part := entry["node"] as Node3D
		if part == null or not is_instance_valid(part):
			continue
		var base: Vector3 = entry["base_rotation"]
		var phase := float(entry["phase"])
		var amplitude := float(entry["amplitude"])
		var broad := sin(_elapsed * SLOW_FREQUENCY + phase)
		var gust := sin(_elapsed * GUST_FREQUENCY + phase * 1.37) * 0.34
		var crosswind := cos(
			_elapsed * SLOW_FREQUENCY * 0.73 + phase * 0.81
		) * 0.46
		part.rotation = base + Vector3(
			amplitude * (broad + gust) * 0.34,
			0.0,
			amplitude * (broad + gust + crosswind)
		)
