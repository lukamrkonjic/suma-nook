@tool
class_name BasinGenerator
extends TileLayerGenerator
## Wells, pools, water basins, recessed planters, shallow pits, framed insets:
## a cavity carved into the shared top so the surface mesh itself IS the basin
## floor and its walls.
##
## The cavity is not a sum of shape primitives and deliberately ignores
## `layer.shapes`. A basin outline is a constructed boundary — a designer asks
## for "a round well 14 cm deep with a two-centimetre lip", not for three
## overlapping mounds — so the carve is written straight into the field and
## `apply_layer` is skipped. Everything organic about the tile still comes from
## primitives, on the layers underneath.
##
## The carve REPLACES the top it lands on. Order the basin last among the
## heightfield layers and read `rim_height` as an absolute elevation, not as an
## offset from whatever was already there.
##
## The rim runs out to the tile boundary and ends exactly on the connected edge
## height. That is the whole no-hole guarantee: a basin tile placed beside a
## plain grass tile meets it flush, because the carve is confined inside
## `inner` and the boundary ring is snapped, always.
##
## Water is a separate part on purpose. The floor is opaque terrain, the water
## is a transparent plane; merging them would put terrain triangles behind a
## transparent surface in one draw call and lose both the sorting and the
## ability to hide, tint, or animate the water on its own.
##
## ## Params:
##   shape            String  "rect" | "rounded" | "circle" (default "rounded")
##   corner           float   corner radius as a fraction of the cavity half
##                            size; only read for shape "rounded" (default 0.35)
##   inner            float   cavity outline as a fraction of the half extent
##                            (default 0.62)
##   depth            float   metres; the floor sits at -depth (default 0.14)
##   rim_height       float   metres; absolute elevation of the rim (default 0.0)
##   wall_softness    float   width of the rim-to-floor transition in normalized
##                            tile units, 0..1 (default 0.12)
##   step_count       int     intermediate ledges between rim and floor;
##                            1 gives one ledge (default 0)
##   step_inset       float   radial width of each ledge, normalized (default 0.08)
##   step_drop        float   metres each successive ledge drops (default 0.05)
##   water            bool    emit the water plane (default true)
##   water_level      float   metres; elevation of the water surface (default -0.06)
##   water_inset      float   metres the waterline pulls back from the cavity
##                            wall (default 0.02)
##   corner_segments  int     arc segments per rounded corner (default 2)
##   circle_segments  int     ring segments for shape "circle" (default 14)
##
## Slots: the rim takes `layer.material_slot`, the cavity floor and walls take
## SLOT_INSET, and step treads take `layer.secondary_slot` when one is set so a
## stepped basin reads as two broad regions rather than one. Water is always
## SLOT_WATER.

const SHAPE_RECT := "rect"
const SHAPE_ROUNDED := "rounded"
const SHAPE_CIRCLE := "circle"
const DEFAULT_SHAPE := SHAPE_ROUNDED

## Below this the wall has no vertex ring of its own: the lip quantises onto the
## field grid and the cavity outline goes soft, which is the melted look the art
## direction bans.
const MIN_RESOLUTION := 9
## Smallest cavity floor worth carving, as a fraction of the half extent. Below
## it the basin is all wall and reads as a dimple.
const MIN_FLOOR_FRACTION := 0.08
## A transition wider than this stops reading as a wall and starts reading as a
## pillow.
const SOFT_WALL_LIMIT := 0.35


func generator_id() -> String:
	return "basin"


func kinds() -> Array:
	return [TileForgeConstants.Kind.HEIGHTFIELD, TileForgeConstants.Kind.MESH]


func description() -> String:
	return "Carves a well, pool, or framed inset into the shared top and emits its water plane separately."


func validate(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> PackedStringArray:
	var problems := PackedStringArray()

	var shape := layer.get_string("shape", DEFAULT_SHAPE)
	if shape != SHAPE_RECT and shape != SHAPE_ROUNDED and shape != SHAPE_CIRCLE:
		problems.append(
			"shape '%s' is not one of %s / %s / %s"
			% [shape, SHAPE_RECT, SHAPE_ROUNDED, SHAPE_CIRCLE]
		)

	if layer.resolution < MIN_RESOLUTION:
		problems.append(
			"resolution %d cannot resolve a basin wall; use at least %d"
			% [layer.resolution, MIN_RESOLUTION]
		)

	var corner := layer.get_float("corner", 0.35)
	if corner < 0.0 or corner > 1.0:
		problems.append("corner %.2f is outside 0..1" % corner)

	var inner := layer.get_float("inner", 0.62)
	if inner <= 0.1 or inner > 0.94:
		problems.append(
			"inner %.2f leaves no usable rim; keep the cavity between 0.10 and 0.94 of the half extent"
			% inner
		)

	var depth := layer.get_float("depth", 0.14)
	if depth <= 0.0:
		problems.append("depth %.3f m must be positive — a basin with no depth is a flat tile" % depth)
	elif -depth < TileForgeConstants.MIN_RECESSED_TOP - 0.001:
		problems.append(
			"depth %.3f m puts the floor at %.3f, below the recessed floor %.3f"
			% [depth, -depth, TileForgeConstants.MIN_RECESSED_TOP]
		)

	var rim_height := layer.get_float("rim_height", 0.0)
	if rim_height > TileForgeConstants.MAX_RAISED_TOP:
		problems.append(
			"rim_height %.3f m is above the raised-top ceiling %.3f"
			% [rim_height, TileForgeConstants.MAX_RAISED_TOP]
		)

	var band := layer.get_float("wall_softness", 0.12)
	if band <= 0.0 or band > 1.0:
		problems.append("wall_softness %.2f is outside 0..1" % band)

	var steps := layer.get_int("step_count", 0)
	var step_inset := layer.get_float("step_inset", 0.08)
	var step_drop := layer.get_float("step_drop", 0.05)
	if steps < 0:
		problems.append("step_count %d cannot be negative" % steps)
	if steps > 0 and step_inset <= 0.0:
		problems.append(
			"step_count %d with step_inset %.3f produces zero-width ledges"
			% [steps, step_inset]
		)
	if step_drop < 0.0:
		problems.append("step_drop %.3f must not be negative — ledges descend into the basin" % step_drop)

	var floor_radius := inner - float(maxi(0, steps)) * maxf(0.0, step_inset) - maxf(0.0, band)
	if floor_radius < MIN_FLOOR_FRACTION:
		problems.append(
			"ledges and wall consume the cavity: floor radius %.2f, need at least %.2f — reduce step_count, step_inset, or wall_softness"
			% [floor_radius, MIN_FLOOR_FRACTION]
		)

	# The central lock would drag any part of the wall that reaches into the
	# edge band back up to the boundary height, silently costing the basin its
	# depth. Better to reject the numbers than to bake a shallow puddle.
	if layer.border_policy == TileForgeConstants.BorderPolicy.EDGE_LOCK:
		var limit := 1.0 - layer.edge_lock_width
		if inner > limit:
			problems.append(
				"cavity lip at %.2f reaches into the %.2f-wide edge lock band; keep inner below %.2f or narrow edge_lock_width"
				% [inner, layer.edge_lock_width, limit]
			)

	if layer.get_bool("water", true):
		var level := layer.get_float("water_level", -0.06)
		var water_inset := layer.get_float("water_inset", 0.02)
		if water_inset < 0.0:
			problems.append("water_inset %.3f m cannot be negative" % water_inset)
		if level > rim_height + 0.0001:
			problems.append(
				"water_level %.3f is above the rim %.3f and will spill across the tile"
				% [level, rim_height]
			)
		if level < -depth - 0.0001:
			problems.append(
				"water_level %.3f is below the basin floor %.3f" % [level, -depth]
			)
		var cavity_radius := inner * ctx.half_extent
		if cavity_radius - water_inset <= 0.001:
			problems.append(
				"water_inset %.3f m leaves no water surface inside a %.3f m cavity"
				% [water_inset, cavity_radius]
			)

	_advise(layer, ctx, inner, band)
	return problems


## HEIGHTFIELD pass. Writes the cavity straight into the field: the top surface
## and the basin interior are one continuous mesh, so there is no seam between
## the rim and the floor to crack open.
func generate_height(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> void:
	var field := ctx.field
	if field == null:
		return

	var corner := _corner_fraction(layer)
	var inner: float = clampf(layer.get_float("inner", 0.62), 0.02, 1.0)
	var depth: float = maxf(0.0, layer.get_float("depth", 0.14))
	var rim_height := layer.get_float("rim_height", 0.0)
	var band: float = clampf(layer.get_float("wall_softness", 0.12), 0.005, 1.0)
	var steps: int = maxi(0, layer.get_int("step_count", 0))
	var step_inset: float = maxf(0.0, layer.get_float("step_inset", 0.08))
	var step_drop: float = maxf(0.0, layer.get_float("step_drop", 0.05))

	# Rings from the lip inwards: [rim, ledge 1 .. ledge n, floor]. Modelling
	# the descent as a list of rings rather than as one smoothstep is what lets
	# a stepped rim stay flat on its treads instead of turning into a ramp.
	var radii := PackedFloat32Array()
	var levels := PackedFloat32Array()
	radii.append(inner)
	levels.append(rim_height)
	var cursor := inner
	for step in steps:
		cursor = maxf(0.0, cursor - step_inset)
		radii.append(cursor)
		levels.append(maxf(-depth, rim_height - step_drop * float(step + 1)))
	radii.append(maxf(0.0, cursor - band))
	levels.append(-depth)

	var rim_slot := (
		layer.material_slot
		if layer.material_slot != ""
		else TileForgeConstants.SLOT_TOP_PRIMARY
	)
	var inset_slot := TileForgeConstants.SLOT_INSET
	var ledge_slot := layer.secondary_slot if layer.secondary_slot != "" else inset_slot
	var ledge_edge: float = radii[radii.size() - 2] if steps > 0 else inner

	# Taken as a local and written back once: PackedFloat32Array is copy-on-write,
	# so touching it through the field's property per vertex would pay for a copy
	# on every element.
	var heights := field.heights
	for j in field.resolution:
		for i in field.resolution:
			var distance := _gauge(field.axis(i), field.axis(j), corner)
			heights[field.index_of(i, j)] = _profile(
				distance, radii, levels, band, rim_height
			)
			if distance >= inner:
				field.set_slot(i, j, rim_slot)
			elif steps > 0 and distance >= ledge_edge:
				field.set_slot(i, j, ledge_slot)
			else:
				field.set_slot(i, j, inset_slot)
	field.heights = heights

	# Non-negotiable, because the carve replaced the whole top: if the rim did
	# not end exactly on the connected height a basin tile would open a hole
	# against a flat neighbour. EDGE_LOCK grades the rim down over its own band;
	# every other policy gets the boundary ring snapped and nothing more, which
	# is precisely the hard structural lip a framed inset wants.
	var lock_width: float = (
		layer.edge_lock_width
		if layer.border_policy == TileForgeConstants.BorderPolicy.EDGE_LOCK
		else 0.001
	)
	field.lock_edges(layer.edge_lock_height, lock_width)


## MESH pass. Only the water plane: the cavity itself is already part of the
## triangulated top.
func generate_mesh(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> Array[TileMeshPart]:
	var parts: Array[TileMeshPart] = []
	if not layer.get_bool("water", true):
		return parts

	var outline := _water_outline(layer, ctx)
	if outline.size() < 3:
		return parts

	var level := layer.get_float("water_level", -0.06)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Fan from the tile centre, wound to match `extrude_prism`'s top caps so a
	# water plane faces the same way as every other generated cap.
	for index in outline.size():
		var next := (index + 1) % outline.size()
		_water_vertex(tool, Vector2.ZERO, level)
		_water_vertex(tool, outline[index], level)
		_water_vertex(tool, outline[next], level)

	var mesh := ArrayMesh.new()
	tool.commit(mesh)
	mesh.surface_set_name(0, TileForgeConstants.SLOT_WATER)

	var part := TileMeshPart.make(
		mesh, PackedStringArray([TileForgeConstants.SLOT_WATER]), "water"
	)
	# Hard requirement: water keeps its own render node so it can be sorted,
	# tinted, and hidden without touching the terrain it sits in.
	part.never_merge = true
	part.smooth_shading = false
	parts.append(part)
	return parts


## The recipe declares CollisionMode.RIM_BOX and TileForgeBuilder produces the
## four walls plus the basin floor from it. A second set of shapes here would
## double the collision cost for no gameplay difference.
func generate_collision(_layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> Array:
	return []


func get_bounds(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> AABB:
	var extent := ctx.half_extent
	var depth: float = maxf(0.0, layer.get_float("depth", 0.14))
	var rim_height := layer.get_float("rim_height", 0.0)
	var low: float = minf(-depth, minf(rim_height, layer.get_float("water_level", -0.06)))
	var high: float = maxf(rim_height, layer.edge_lock_height)
	return AABB(
		Vector3(-extent, low, -extent),
		Vector3(extent * 2.0, maxf(0.001, high - low), extent * 2.0)
	)


func get_debug_info(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> Dictionary:
	var inner: float = clampf(layer.get_float("inner", 0.62), 0.02, 1.0)
	var steps: int = maxi(0, layer.get_int("step_count", 0))
	var band: float = clampf(layer.get_float("wall_softness", 0.12), 0.005, 1.0)
	var step_inset: float = maxf(0.0, layer.get_float("step_inset", 0.08))
	return {
		"generator": generator_id(),
		"shape": layer.get_string("shape", DEFAULT_SHAPE),
		"cavity_radius_m": inner * ctx.half_extent,
		"rim_width_m": (1.0 - inner) * ctx.half_extent,
		"floor_y": -maxf(0.0, layer.get_float("depth", 0.14)),
		"rim_y": layer.get_float("rim_height", 0.0),
		"steps": steps,
		"floor_radius": inner - float(steps) * step_inset - band,
		"water": layer.get_bool("water", true),
		"water_y": layer.get_float("water_level", -0.06),
		"top_triangles": (layer.resolution - 1) * (layer.resolution - 1) * 2,
	}


# --- carve ------------------------------------------------------------------

## Normalized radial coordinate of (u, v): 0 at the tile centre, 1 exactly on
## the outline of the chosen shape at full size. Level sets are scaled copies of
## that outline, so testing `gauge <= inner` gives a cavity that is the same
## shape at any size — which is what keeps a rounded basin rounded instead of
## letting its corners square up as it shrinks.
##
## `corner` is the corner radius as a fraction of the half size, so 0 is an
## exact square, 1 an exact circle, and everything between a rounded rect.
static func _gauge(u: float, v: float, corner: float) -> float:
	var a := absf(u)
	var b := absf(v)
	var radius: float = clampf(corner, 0.0, 1.0)
	var flat := 1.0 - radius
	var hi: float = maxf(a, b)
	var lo: float = minf(a, b)
	# Against a flat side the answer is just the dominant axis.
	if lo <= flat * hi:
		return hi
	# In a corner, solve for the scale at which (a, b) lands on the corner arc.
	var sum := a + b
	var square := a * a + b * b
	var discriminant: float = maxf(
		0.0, flat * flat * sum * sum - square * (2.0 * flat * flat - radius * radius)
	)
	var denominator := flat * sum + sqrt(discriminant)
	if denominator <= 0.00001:
		return hi
	return square / denominator


## Height at a normalized radial coordinate, walking the ring list outwards-in.
## Each riser is clamped to the gap it spans so two adjacent rings can never
## overlap and leave a crease where a flat tread should be.
static func _profile(
	distance: float,
	radii: PackedFloat32Array,
	levels: PackedFloat32Array,
	band: float,
	rim_height: float
) -> float:
	if distance >= radii[0]:
		return rim_height
	for index in range(1, radii.size()):
		if distance >= radii[index]:
			var outer := radii[index - 1]
			var riser: float = minf(band, maxf(0.0001, outer - radii[index]))
			var t := smoothstep(outer - riser, outer, distance)
			return lerpf(levels[index], levels[index - 1], t)
	return levels[levels.size() - 1]


static func _corner_fraction(layer: TileSurfaceLayer) -> float:
	var shape := layer.get_string("shape", DEFAULT_SHAPE)
	if shape == SHAPE_RECT:
		return 0.0
	if shape == SHAPE_CIRCLE:
		return 1.0
	return clampf(layer.get_float("corner", 0.35), 0.0, 1.0)


# --- water ------------------------------------------------------------------

## Outline of the water surface in LIVE world XZ: the cavity outline, scaled in
## so the waterline stays parallel to the wall instead of touching it.
func _water_outline(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> PackedVector2Array:
	var inner: float = clampf(layer.get_float("inner", 0.62), 0.02, 1.0)
	var radius: float = (
		inner * ctx.half_extent - maxf(0.0, layer.get_float("water_inset", 0.02))
	)
	if radius <= 0.001:
		return PackedVector2Array()

	var shape := layer.get_string("shape", DEFAULT_SHAPE)
	if shape == SHAPE_CIRCLE:
		# `rounded_rect` clamps its corner radius to 0.9 of the half size, so it
		# cannot express a true circle; a ring is the honest answer.
		var segments: int = maxi(3, layer.get_int("circle_segments", 14))
		var ring := PackedVector2Array()
		for step in segments:
			var angle := TAU * float(step) / float(segments)
			ring.append(Vector2(cos(angle), sin(angle)) * radius)
		return ring

	var size := Vector2(radius * 2.0, radius * 2.0)
	if shape == SHAPE_RECT:
		return rounded_rect(size, 0.0, 0)
	return rounded_rect(
		size,
		clampf(layer.get_float("corner", 0.35), 0.0, 1.0) * radius,
		maxi(0, layer.get_int("corner_segments", 2))
	)


static func _water_vertex(tool: SurfaceTool, point: Vector2, level: float) -> void:
	tool.set_normal(Vector3.UP)
	tool.add_vertex(Vector3(point.x, level, point.y))


# --- advice ------------------------------------------------------------------

## Non-fatal notes. `validate` may only return blockers — the builder turns every
## returned string into a hard failure — so guidance goes through the context's
## message channel instead.
func _advise(
	layer: TileSurfaceLayer,
	ctx: TileGenerationContext,
	inner: float,
	band: float
) -> void:
	if band > SOFT_WALL_LIMIT:
		ctx.report(
			"[%s] wall_softness %.2f will read as a pillow rather than a basin wall"
			% [layer.layer_name, band]
		)
	var cell := 2.0 / float(maxi(2, layer.resolution) - 1)
	if 1.0 - inner < cell * 1.5:
		ctx.report(
			"[%s] the rim is %.2f wide against a %.2f grid cell; raise resolution or lower inner if it reads as a knife edge"
			% [layer.layer_name, 1.0 - inner, cell]
		)
	if layer.resolution > 13:
		ctx.report(
			"[%s] resolution %d puts the top at %d triangles; a basin wall resolves at 9–13"
			% [
				layer.layer_name,
				layer.resolution,
				(layer.resolution - 1) * (layer.resolution - 1) * 2,
			]
		)
