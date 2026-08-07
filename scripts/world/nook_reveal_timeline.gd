class_name NookRevealTimeline
extends RefCounted
## Pure timing math for the falling-tile reveal wave. All numbers come from
## data/reveal.json, so the signature moment is tunable without code. The
## presenter consumes entries; headless tests exercise this class directly.
##
## The wave is radial from an origin (the connecting seam by default, the
## chunk centre when the Nook has no revealed neighbour), with deterministic
## per-tile stagger noise so it ripples instead of marching.


## entries: [{"local": Vector2i, "delay": float}] sorted by delay.
static func tile_wave(
	locals: Array[Vector2i],
	origin: Vector2,
	config: Dictionary
) -> Array[Dictionary]:
	var tiles_per_second := maxf(
		1.0, float(config.get("wavefront_tiles_per_second", 11.0))
	)
	var stagger := maxf(0.0, float(config.get("stagger_ms", 80.0))) / 1000.0
	var entries: Array[Dictionary] = []
	for local: Vector2i in locals:
		var distance := Vector2(local).distance_to(origin)
		var noise := _stagger_noise(local)
		entries.append({
			"local": local,
			"delay": maxf(0.0, distance / tiles_per_second + noise * stagger),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["delay"]) < float(b["delay"])
	)
	return entries


## Wave origin in local-cell space. seam_side is the offset toward the
## revealed neighbour the Nook connects from (Vector2i.ZERO = none).
static func wave_origin(
	size: int, seam_side: Vector2i, config: Dictionary
) -> Vector2:
	var centre := Vector2(size - 1, size - 1) * 0.5
	if String(config.get("origin", "seam")) != "seam" \
		or seam_side == Vector2i.ZERO:
		return centre
	# The seam midpoint on the edge facing the neighbour.
	return centre + Vector2(seam_side) * (float(size) * 0.5)


## Deterministic -1..1 ripple noise per cell — the same Nook always falls
## the same way, which keeps replays and captures honest.
static func _stagger_noise(local: Vector2i) -> float:
	var h := hash("reveal:%d:%d" % [local.x, local.y])
	return float(h % 2000) / 1000.0 - 1.0


## Total duration of the terrain wave, so callers can schedule the feature
## pops and mood settle that follow it.
static func wave_duration(entries: Array[Dictionary], config: Dictionary) -> float:
	if entries.is_empty():
		return 0.0
	return float(entries[entries.size() - 1]["delay"]) \
		+ maxf(0.05, float(config.get("tile_drop_seconds", 0.34)))
