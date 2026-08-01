@tool
class_name FlatSurfaceGenerator
extends TileLayerGenerator
## The exact-square, no-nonsense top: one constant plane and nothing else.
##
## Plain grass, packed dirt, poured concrete, or the clean cap a constructed
## pattern is laid onto. It exists because the most common tile in a readable
## collection is not sculpted at all, and because paying 169 vertices for a
## plane is how a tile budget quietly disappears.
##
## The one expressive thing it does is split the top into TWO broad colour
## regions. Two matte halves meeting along a single off-axis line is the
## reference read; a checkerboard, a speckle, or a per-vertex draw is not — so
## the split is always one straight boundary, never a pattern.
##
## ## Params:
##   region_angle_deg  (float, 28.0) Angle of the boundary LINE between the two
##                     colour regions, degrees. Off-axis by default so the split
##                     never reads as a machined edge along the tile.
##   region_offset     (float, 0.0)  Signed position of that line along its own
##                     normal, in normalized tile units. 0 puts the line through
##                     the tile centre; `secondary_share` biases it from there.

## A constant plane is fully described by its four corners. Anything more is
## vertices spent on nothing, and the builder sizes the shared field from the
## largest resolution any layer asks for.
const FLAT_RESOLUTION := 2
## A straight region boundary quantised onto fewer than five vertices per side
## degenerates into a corner wedge; more than nine buys no extra straightness
## because the boundary is a line, not a curve.
const REGION_MIN_RESOLUTION := 5
const REGION_MAX_RESOLUTION := 9
const DEFAULT_REGION_ANGLE_DEG := 28.0


func generator_id() -> String:
	return "flat_surface"


func kinds() -> Array:
	return [TileForgeConstants.Kind.HEIGHTFIELD]


func description() -> String:
	return "Constant-height top with an optional two-region colour split."


func validate(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> PackedStringArray:
	var problems := PackedStringArray()

	if not layer.shapes.is_empty():
		problems.append(
			"flat_surface ignores shape primitives — use heightfield_surface for a sculpted top"
		)

	var plane := layer.height_bias * layer.height_scale
	if plane > TileForgeConstants.MAX_RAISED_TOP:
		problems.append(
			"plane sits at %.3f m, above the raised-top ceiling %.3f"
			% [plane, TileForgeConstants.MAX_RAISED_TOP]
		)
	if plane < TileForgeConstants.MIN_RECESSED_TOP - 0.001:
		problems.append(
			"plane sits at %.3f m, below the recessed floor %.3f"
			% [plane, TileForgeConstants.MIN_RECESSED_TOP]
		)

	# The builder sizes the shared heightfield from `layer.resolution` in the
	# pass immediately after validation, so this is the only hook that can stop a
	# flat top being paid for at a sculpted top's vertex count.
	var wanted := _wanted_resolution(layer)
	if layer.resolution != wanted:
		ctx.report(
			"flat_surface '%s' resolution %d -> %d"
			% [layer.layer_name, layer.resolution, wanted]
		)
		layer.resolution = wanted

	return problems


func generate_height(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> void:
	# Reuse the shared blend and edge-lock path, but hand it a layer with nothing
	# to evaluate: a flat top is `height_bias` and nothing else, and its mask
	# describes a COLOUR region, so letting the mask scale the height would carve
	# the plane this generator exists to keep flat.
	var empty: Array[TileShapePrimitive] = []
	var plane_layer := layer.duplicate() as TileSurfaceLayer
	plane_layer.shapes = empty
	plane_layer.mask_shapes = empty
	ctx.field.apply_layer(plane_layer)
	_paint_regions(layer, ctx)


func get_bounds(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> AABB:
	# Exactly the tile, at exactly one height. Stating that honestly is what lets
	# the validator treat a footprint overrun as a real error rather than slack.
	var plane := layer.height_bias * layer.height_scale
	var extent := ctx.half_extent
	return AABB(
		Vector3(-extent, plane, -extent),
		Vector3(extent * 2.0, 0.0, extent * 2.0)
	)


func get_debug_info(layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> Dictionary:
	return {
		"generator": generator_id(),
		"plane_y": layer.height_bias * layer.height_scale,
		"resolution": layer.resolution,
		"regions": 2 if layer.secondary_slot != "" else 1,
		"region_source": _region_source(layer),
		"region_angle_deg": layer.get_float("region_angle_deg", DEFAULT_REGION_ANGLE_DEG),
	}


## Four corners for a single-colour plane; just enough vertices to carry a
## straight boundary when a second region is asked for.
func _wanted_resolution(layer: TileSurfaceLayer) -> int:
	if layer.secondary_slot == "":
		return FLAT_RESOLUTION
	return clampi(layer.resolution, REGION_MIN_RESOLUTION, REGION_MAX_RESOLUTION)


func _region_source(layer: TileSurfaceLayer) -> String:
	if layer.secondary_slot == "":
		return "none"
	return "mask_shapes" if not layer.mask_shapes.is_empty() else "split_line"


func _paint_regions(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> void:
	if layer.secondary_slot == "":
		return

	var field := ctx.field
	var primary := layer.material_slot
	if primary == "":
		primary = TileForgeConstants.SLOT_TOP_PRIMARY

	# A flat layer that declares a second slot owns BOTH regions, so the primary
	# is stamped rather than inherited — otherwise half the tile silently keeps
	# whatever colour the layer beneath happened to leave behind.
	for j in field.resolution:
		for i in field.resolution:
			field.set_slot(i, j, primary)

	if not layer.mask_shapes.is_empty():
		# The designer drew the region themselves. `paint_secondary_slot` reads
		# `shapes`, so it is handed a view of this layer whose shapes ARE the
		# mask; the original layer is never touched.
		var mask_view := layer.duplicate() as TileSurfaceLayer
		mask_view.shapes = layer.mask_shapes
		field.paint_secondary_slot(mask_view, layer.secondary_slot, layer.secondary_share)
		return

	_paint_split_line(layer, field)


## Two broad halves divided by one straight line. Slot ids are written directly
## because there is no height to shape here — a colour region on a flat top is
## not a form, and routing it through a shape primitive would only invite one.
func _paint_split_line(layer: TileSurfaceLayer, field: TileHeightField) -> void:
	var angle := deg_to_rad(layer.get_float("region_angle_deg", DEFAULT_REGION_ANGLE_DEG))
	var normal := Vector2(-sin(angle), cos(angle))
	# `secondary_share` moves the line so the requested split is honoured without
	# the designer solving for an offset; `region_offset` then nudges it by hand,
	# and a share of 0.5 leaves the line exactly on `region_offset`.
	#
	# The conversion is the tile area swept per unit of offset: the chord across
	# the normalized square perpendicular to `normal`, over the square's area.
	# Deriving it from the angle rather than assuming one keeps a 5-degree split
	# as honest as a 45-degree one.
	var swept_per_unit := (2.0 / maxf(absf(normal.x), absf(normal.y))) / 4.0
	var threshold := (
		layer.get_float("region_offset", 0.0)
		+ (0.5 - layer.secondary_share) / swept_per_unit
	)
	for j in field.resolution:
		for i in field.resolution:
			var u := field.axis(i)
			var v := field.axis(j)
			if u * normal.x + v * normal.y >= threshold:
				field.set_slot(i, j, layer.secondary_slot)
