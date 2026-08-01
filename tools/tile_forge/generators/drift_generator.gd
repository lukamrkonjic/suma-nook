@tool
class_name DriftGenerator
extends TileLayerGenerator
## Wind-formed accumulation: sand dunes, snow drifts, ash, swept debris.
##
## Unlike heightfield_surface this generator SYNTHESISES its own primitives. A
## drift field is a rule, not a set of placements — crests lying across the
## wind, uneven spacing, a short windward face and a long leeward tail — and
## hand-placing five primitives to express that rule is both tedious and easy to
## get wrong in the one way that matters. Evenly spaced dunes read as corrugated
## iron, and a symmetric crest reads as a row of pillows. Both are failures the
## designer should not have to remember to avoid, so the spacing carries a floor
## under its jitter and the crest carries a default lean.
##
## Everything is still built from TileShapePrimitive DRIFT and TRENCH forms, so
## a drift top is the same kind of geometry as a hand-authored one and obeys the
## same seam, blend, and budget rules.
##
## ## Params:
##   ridge_count          (int,   3)     Number of crests across the tile.
##   flow_angle_deg       (float, 28.0)  Angle the crest LINES run at, degrees.
##                                       Crests advance and lean along this
##                                       angle's normal — that normal is the
##                                       wind, which is why the dune asymmetry
##                                       acts across the crest and not along it.
##   ridge_height         (float, 0.035) Peak of one crest, metres, before the
##                                       layer's `height_scale`.
##   ridge_spacing_jitter (float, 0.35)  0..1 unevenness of the crest spacing.
##   crest_asymmetry      (float, 0.55)  Lean of the crest, -1..1. 0 would give a
##                                       symmetric bump, which is not a dune.
##   ridge_length         (float, 1.5)   Half-length of a crest in normalized
##                                       tile units. Above 1.0 a crest runs off
##                                       both sides instead of tapering to a
##                                       visible point inside the tile.
##   valley_depth_ratio   (float, 0.45)  Depth of the hollow between two crests,
##                                       as a fraction of `ridge_height`.

const DEFAULT_RIDGE_COUNT := 3
const DEFAULT_FLOW_ANGLE_DEG := 28.0
const DEFAULT_RIDGE_HEIGHT := 0.035
const DEFAULT_SPACING_JITTER := 0.35
const DEFAULT_CREST_ASYMMETRY := 0.55
const DEFAULT_RIDGE_LENGTH := 1.5
const DEFAULT_VALLEY_RATIO := 0.45

## More crests than this on a 1.35 m tile stop being drift and become texture.
const MAX_RIDGE_COUNT := 8
## Above this a crest is a landform, not accumulated material, and the tile
## silhouette starts fighting the block it sits on.
const MAX_RIDGE_HEIGHT := 0.09
## Crest centres stay inside this normalized radius. A crest landing on the
## boundary would be sheared flat by the central edge lock and leave a hard
## straight line exactly where two tiles meet.
const CREST_INSET := 0.72
## Floor under `ridge_spacing_jitter`. Evenly spaced dunes are the single
## failure this generator exists to prevent, so even a jitter of 0 gets an
## uneven field.
const MIN_SPACING_JITTER := 0.18
## Fraction of the crest-to-crest gap one dune's cross-section covers. Slightly
## over half so neighbouring dunes merge into a continuous field instead of
## standing apart as separate bumps.
const CROSS_SHARE := 0.62
## Hollows stay narrower than the dunes that flank them: a drift field is mostly
## material, with a shadow line between crests, not a series of channels.
const VALLEY_CROSS_SHARE := 0.42
## Per-crest variation. Macro, applied once per primitive — this is not
## per-vertex jitter, and identical crests read as a stamp.
const HEIGHT_VARIATION := 0.22
const SLIDE_VARIATION := 0.25


func generator_id() -> String:
	return "drift"


func kinds() -> Array:
	return [TileForgeConstants.Kind.HEIGHTFIELD]


func description() -> String:
	return "Synthesised dune field: unevenly spaced asymmetric crests with hollows between."


func validate(layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> PackedStringArray:
	var problems := PackedStringArray()

	var count := layer.get_int("ridge_count", DEFAULT_RIDGE_COUNT)
	if count < 1:
		problems.append("ridge_count %d builds nothing" % count)
	elif count > MAX_RIDGE_COUNT:
		problems.append(
			"ridge_count %d — past %d crests a 1.35 m tile reads as corduroy, not as drift"
			% [count, MAX_RIDGE_COUNT]
		)

	var height := layer.get_float("ridge_height", DEFAULT_RIDGE_HEIGHT)
	if absf(height) > MAX_RIDGE_HEIGHT:
		problems.append(
			"ridge_height %.3f m is a landform, not accumulated material; keep it under %.2f"
			% [height, MAX_RIDGE_HEIGHT]
		)

	if layer.get_float("ridge_length", DEFAULT_RIDGE_LENGTH) <= 0.0:
		problems.append("ridge_length must be positive")

	var ratio := layer.get_float("valley_depth_ratio", DEFAULT_VALLEY_RATIO)
	if ratio < 0.0 or ratio > 1.0:
		problems.append("valley_depth_ratio %.2f is outside 0..1" % ratio)

	var needed := _min_resolution(count)
	if count >= 1 and layer.resolution < needed:
		problems.append(
			"resolution %d cannot resolve %d crests and their hollows; use at least %d"
			% [layer.resolution, count, needed]
		)

	return problems


func generate_height(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> void:
	var ridges := _build_ridges(layer, ctx)
	if ridges.is_empty():
		ctx.field.apply_layer(layer)
		return
	var valleys := _build_valleys(ridges, layer)

	# `apply_layer` adds `extra` AFTER the layer's own `height_scale`, so the
	# synthesised forms re-apply it: they are this layer's shape primitives in
	# every sense except that a designer did not have to place them, and the
	# layer's intensity control has to reach them.
	var scale := layer.height_scale
	var drift := func(u: float, v: float) -> float:
		var total := 0.0
		for ridge in ridges:
			total += ridge.evaluate(u, v)
		for valley in valleys:
			total += valley.evaluate(u, v)
		return total * scale

	ctx.field.apply_layer(layer, drift)
	_paint_crests(layer, ctx, ridges)


func get_bounds(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> AABB:
	var peak := layer.get_float("ridge_height", DEFAULT_RIDGE_HEIGHT) * (1.0 + HEIGHT_VARIATION)
	var hollow := -absf(peak) * clampf(
		layer.get_float("valley_depth_ratio", DEFAULT_VALLEY_RATIO), 0.0, 1.0
	)
	var a := (layer.height_bias + peak) * layer.height_scale
	var b := (layer.height_bias + hollow) * layer.height_scale
	# The boundary is locked to the connected height, so 0 is always occupied.
	var high: float = maxf(maxf(a, b), 0.0)
	var low: float = minf(minf(a, b), 0.0)
	var extent := ctx.half_extent
	return AABB(
		Vector3(-extent, low, -extent),
		Vector3(extent * 2.0, high - low, extent * 2.0)
	)


func get_debug_info(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> Dictionary:
	# Reported along the advance normal, because "are the crests evenly spaced"
	# is the one question worth asking of a drift field.
	var angle := deg_to_rad(layer.get_float("flow_angle_deg", DEFAULT_FLOW_ANGLE_DEG))
	var advance := Vector2(-sin(angle), cos(angle))
	var offsets := PackedFloat32Array()
	for ridge in _build_ridges(layer, ctx):
		offsets.append(ridge.center.dot(advance))
	return {
		"generator": generator_id(),
		"ridges": offsets.size(),
		"crest_offsets": Array(offsets),
		"flow_angle_deg": layer.get_float("flow_angle_deg", DEFAULT_FLOW_ANGLE_DEG),
		"ridge_height": layer.get_float("ridge_height", DEFAULT_RIDGE_HEIGHT),
		"valley_depth_ratio": layer.get_float("valley_depth_ratio", DEFAULT_VALLEY_RATIO),
		"peak": ctx.field.max_height() if ctx.field != null else 0.0,
	}


## One vertex per crest and one per hollow, plus the two locked boundary rings.
func _min_resolution(count: int) -> int:
	return count * 2 + 1


func _ridge_count(layer: TileSurfaceLayer) -> int:
	return clampi(layer.get_int("ridge_count", DEFAULT_RIDGE_COUNT), 0, MAX_RIDGE_COUNT)


## The dune field itself. Deterministic from the recipe seed, so the height pass
## and the debug report can each build it and always agree.
func _build_ridges(
	layer: TileSurfaceLayer,
	ctx: TileGenerationContext
) -> Array[TileShapePrimitive]:
	var result: Array[TileShapePrimitive] = []
	var count := _ridge_count(layer)
	if count <= 0:
		return result

	var angle_deg := layer.get_float("flow_angle_deg", DEFAULT_FLOW_ANGLE_DEG)
	var angle := deg_to_rad(angle_deg)
	# Crests run along `flow_angle_deg`; they advance along its normal. That
	# normal is also the axis the DRIFT asymmetry leans on, which is what makes
	# every crest in the field lean the same way, as one wind would leave them.
	var along := Vector2(cos(angle), sin(angle))
	var advance := Vector2(-sin(angle), cos(angle))

	var height := layer.get_float("ridge_height", DEFAULT_RIDGE_HEIGHT)
	var length: float = maxf(0.05, layer.get_float("ridge_length", DEFAULT_RIDGE_LENGTH))
	var asymmetry: float = clampf(
		layer.get_float("crest_asymmetry", DEFAULT_CREST_ASYMMETRY), -1.0, 1.0
	)
	var jitter: float = maxf(
		MIN_SPACING_JITTER,
		clampf(layer.get_float("ridge_spacing_jitter", DEFAULT_SPACING_JITTER), 0.0, 1.0)
	)

	var rng := ctx.rng("drift")
	var step := 1.0 / float(count)
	var cross := step * 2.0 * CREST_INSET * CROSS_SHARE

	for index in count:
		var even := -1.0 + step * (2.0 * float(index) + 1.0)
		# The shift is capped at the half-gap, so crests never swap order or
		# collapse onto each other however hard the jitter is pushed.
		var offset: float = clampf(
			even + rng.randf_range(-1.0, 1.0) * step * jitter, -1.0, 1.0
		) * CREST_INSET
		# Slide each crest along its own line so the tapered ends do not queue up
		# into a comb across the tile.
		var slide := rng.randf_range(-SLIDE_VARIATION, SLIDE_VARIATION)

		var ridge := TileShapePrimitive.new()
		ridge.shape = TileForgeConstants.Shape.DRIFT
		ridge.center = advance * offset + along * slide
		ridge.extents = Vector2(length, cross)
		ridge.rotation_deg = angle_deg
		ridge.height = height * (1.0 + rng.randf_range(-HEIGHT_VARIATION, HEIGHT_VARIATION))
		ridge.asymmetry = asymmetry
		ridge.falloff = TileForgeConstants.Falloff.SMOOTHSTEP
		ridge.softness = 0.55
		result.append(ridge)

	return result


## Shallow hollows on the midline between neighbouring crests. Derived from the
## crests rather than drawn separately, so an uneven crest field automatically
## gets unevenly sized hollows instead of a regular corrugation.
func _build_valleys(
	ridges: Array[TileShapePrimitive],
	layer: TileSurfaceLayer
) -> Array[TileShapePrimitive]:
	var result: Array[TileShapePrimitive] = []
	var ratio: float = clampf(
		layer.get_float("valley_depth_ratio", DEFAULT_VALLEY_RATIO), 0.0, 1.0
	)
	if ratio <= 0.0:
		return result
	var depth := layer.get_float("ridge_height", DEFAULT_RIDGE_HEIGHT) * ratio

	for index in ridges.size() - 1:
		var near: TileShapePrimitive = ridges[index]
		var far: TileShapePrimitive = ridges[index + 1]
		var gap := near.center.distance_to(far.center)
		if gap <= 0.0001:
			continue
		var valley := TileShapePrimitive.new()
		valley.shape = TileForgeConstants.Shape.TRENCH
		valley.center = (near.center + far.center) * 0.5
		valley.extents = Vector2(minf(near.extents.x, far.extents.x), gap * VALLEY_CROSS_SHARE)
		valley.rotation_deg = near.rotation_deg
		# TRENCH weight is already negative, so a positive height digs down.
		valley.height = depth
		valley.falloff = TileForgeConstants.Falloff.SMOOTHSTEP
		valley.softness = 0.75
		result.append(valley)

	return result


func _paint_crests(
	layer: TileSurfaceLayer,
	ctx: TileGenerationContext,
	ridges: Array[TileShapePrimitive]
) -> void:
	if layer.secondary_slot == "":
		return
	# `paint_secondary_slot` reads `shapes` and takes the ABSOLUTE weight, so the
	# hollows are deliberately withheld — handing them over would paint the
	# shadow line the same colour as the sunlit crest above it.
	var crest_view := layer.duplicate() as TileSurfaceLayer
	crest_view.shapes = ridges
	ctx.field.paint_secondary_slot(crest_view, layer.secondary_slot, layer.secondary_share)
