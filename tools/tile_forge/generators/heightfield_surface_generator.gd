@tool
class_name HeightfieldSurfaceGenerator
extends TileLayerGenerator
## The soft organic workhorse: grass, soil, sand, snow, mud, moss.
##
## It is deliberately thin. The shape comes from the layer's own
## TileShapePrimitive set, the blend and the seam come from TileHeightField, and
## this class only decides two things: whether a whisper of softening is added
## on top, and which vertices are crest enough to take the second colour.
##
## Everything the art direction bans lives one shortcut away from here — the
## shortcut of reaching for noise when a surface looks boring. It does not
## exist. If a top reads as flat the answer is a bigger primitive or a second
## one, never a higher frequency.
##
## ## Params:
##   micro_relief (float, 0.0) 0..1 strength of a sub-centimetre softening term.
##                0 disables it entirely, which is the right value for anything
##                constructed. It is NOT a shape source — see below.
##   micro_scale  (float, 1.6) Frequency of that softening in normalized tile
##                units. 1.6 puts roughly three lattice cells across the whole
##                tile, which is broad enough that no vertex disagrees visibly
##                with its neighbour.

## Hard ceiling on the softening contribution, metres. Six millimetres at a
## 15-degree-FOV camera 37 units out is under a pixel of silhouette: it exists
## only to stop a large primitive reading as machined, and it can never become
## the shape. `apply_layer` adds this term AFTER the layer's `height_scale`, so
## turning a layer up cannot smuggle the ceiling up with it.
const MICRO_RELIEF_CEILING := 0.006
## A single primitive taller than this stops being terrain relief and starts
## being a structural form, which belongs in a mesh layer with a real silhouette.
const MAX_SHAPE_HEIGHT := 0.2
## Below three vertices per side there is no interior sample at all, so every
## primitive collapses into the locked boundary band.
const MIN_SHAPED_RESOLUTION := 3
const DEFAULT_MICRO_SCALE := 1.6


func generator_id() -> String:
	return "heightfield_surface"


func kinds() -> Array:
	return [TileForgeConstants.Kind.HEIGHTFIELD]


func description() -> String:
	return "Organic top from broad shape primitives, with optional sub-centimetre softening."


func validate(layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> PackedStringArray:
	var problems := PackedStringArray()

	if layer.shapes.is_empty() and is_zero_approx(layer.height_bias):
		problems.append("no shape primitives and no height_bias — this layer builds nothing")

	if not layer.shapes.is_empty() and layer.resolution < MIN_SHAPED_RESOLUTION:
		problems.append(
			"resolution %d cannot carry a shaped top; use at least %d"
			% [layer.resolution, MIN_SHAPED_RESOLUTION]
		)

	for index in layer.shapes.size():
		var shape: TileShapePrimitive = layer.shapes[index]
		if shape == null:
			continue
		if absf(shape.height) > MAX_SHAPE_HEIGHT:
			problems.append(
				"shape %d is %.3f m tall; organic relief stops reading as a miniature past %.2f m"
				% [index, shape.height, MAX_SHAPE_HEIGHT]
			)

	return problems


func generate_height(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> void:
	var relief: float = clampf(layer.get_float("micro_relief", 0.0), 0.0, 1.0)
	if relief <= 0.0:
		ctx.field.apply_layer(layer)
	else:
		var amplitude := relief * MICRO_RELIEF_CEILING
		var frequency: float = maxf(0.1, layer.get_float("micro_scale", DEFAULT_MICRO_SCALE))
		# Seeded per layer so two layers on one tile soften differently, and so
		# the same recipe softens identically on every machine.
		var noise_seed := ctx.rng("micro_relief|" + layer.layer_name).randi()
		var soften := func(u: float, v: float) -> float:
			return TileSeedUtil.value_noise_2d(noise_seed, u * frequency, v * frequency) * amplitude
		ctx.field.apply_layer(layer, soften)

	_paint_crests(layer, ctx)


func get_bounds(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> AABB:
	var rise := 0.0
	var fall := 0.0
	for shape in layer.shapes:
		if shape == null:
			continue
		if shape.height > 0.0:
			rise += shape.height
		else:
			fall += shape.height
	# A negative height_scale flips which extreme is the top, so both ends are
	# scaled and then re-sorted rather than assumed.
	var a := (layer.height_bias + rise) * layer.height_scale
	var b := (layer.height_bias + fall) * layer.height_scale
	var margin: float = clampf(layer.get_float("micro_relief", 0.0), 0.0, 1.0) * MICRO_RELIEF_CEILING
	# The boundary is locked to the connected height, so 0 is always occupied
	# even when every primitive pushes one way.
	var high: float = maxf(maxf(a, b) + margin, 0.0)
	var low: float = minf(minf(a, b) - margin, 0.0)
	var extent := ctx.half_extent
	return AABB(
		Vector3(-extent, low, -extent),
		Vector3(extent * 2.0, high - low, extent * 2.0)
	)


func get_debug_info(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> Dictionary:
	return {
		"generator": generator_id(),
		"shapes": layer.shapes.size(),
		"resolution": layer.resolution,
		"micro_relief": layer.get_float("micro_relief", 0.0),
		"micro_scale": layer.get_float("micro_scale", DEFAULT_MICRO_SCALE),
		"peak": ctx.field.max_height() if ctx.field != null else 0.0,
		"trough": ctx.field.min_height() if ctx.field != null else 0.0,
	}


## Crests take the second colour. The driver is the layer's own macro form, so
## the region comes out as one broad band following the high ground rather than
## as a scatter of coloured vertices.
func _paint_crests(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> void:
	if layer.secondary_slot == "" or layer.shapes.is_empty():
		return
	ctx.field.paint_secondary_slot(layer, layer.secondary_slot, layer.secondary_share)
