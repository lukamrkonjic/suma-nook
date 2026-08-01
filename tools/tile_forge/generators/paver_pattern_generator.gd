@tool
class_name PaverPatternGenerator
extends TileLayerGenerator
## Constructed paving: square slabs, rounded paving stones, cobbles, brick
## courses.
##
## Every layout here is AUTHORED — an explicit table of (centre, size)
## rectangles in normalized tile space, never a scatter. A designer can read the
## numbers, count the joints, and predict the tile before pressing bake, which
## is the whole difference between paving and gravel.
##
## Three rules keep a paved tile meeting its neighbours cleanly:
##
##   * a template's rectangles cover -1..1 EXACTLY, so the outermost paver edges
##     land on ±half_extent and the silhouette is the tile, not a shrunken
##     island with a dark trench around it;
##   * a joint is opened on INTERIOR edges only — a boundary edge is shared with
##     the next tile and stays flush, so the joint pattern reads as paving
##     rather than as the tile grid;
##   * a rectangle the boundary CUT in half is finished square instead of
##     rounded and chamfered, because its other half lives on the neighbour and
##     a rolled, bevelled cut edge would draw a false joint straight down the
##     middle of one brick.
##
## Layout tables pack a rectangle into a Vector4 as (centre_u, centre_v,
## size_u, size_v); built pavers reuse the same packing in LIVE metres as
## (centre_x, centre_z, size_x, size_z).
##
## ## Params:
##   template          String  layout table: "quad" (2x2 slabs), "running"
##                             (brick running bond), "basket" (basketweave
##                             pairs), "grid" (NxN), "mixed" (hero slab plus
##                             authored fill). Default "quad".
##   grid_size         int     cells per side, "grid" only. Default 3.
##   joint             float   gap between neighbouring pavers, LIVE metres.
##                             Default 0.014.
##   paver_thickness   float   slab depth above the structural seam, metres.
##                             Default 0.055 — exactly the standard seam, so a
##                             default paver top lands on the walk plane.
##   bevel             float   top chamfer, metres. Default 0.008. Clamped
##                             against the slab so it stays a catchlight.
##   corner_radius     float   plan-view corner rounding, metres. Default 0.02.
##   corner_segments   int     arc segments per rounded corner. Default 2.
##   height_variation  float   per-slab lift, metres. Default 0.003, applied in
##                             discrete steps so paving reads as settled stone
##                             instead of a wobble.
##   colour_variation  float   fraction of slabs taking `secondary_slot`, 0..1.
##                             Default 0.3. Overrides the layer's
##                             `secondary_share` because a paver's colour is a
##                             whole-slab decision, not an area split.

const TEMPLATE_QUAD := "quad"
const TEMPLATE_RUNNING := "running"
const TEMPLATE_BASKET := "basket"
const TEMPLATE_GRID := "grid"
const TEMPLATE_MIXED := "mixed"

const TEMPLATES: PackedStringArray = [
	TEMPLATE_QUAD,
	TEMPLATE_RUNNING,
	TEMPLATE_BASKET,
	TEMPLATE_GRID,
	TEMPLATE_MIXED,
]

const DEFAULT_GRID_SIZE := 3
const DEFAULT_JOINT := 0.014
## Matches -TileForgeConstants.SEAM_STANDARD so the default slab exactly fills
## the shipped seam recess and its top sits on the walk plane.
const DEFAULT_THICKNESS := 0.055
const DEFAULT_BEVEL := 0.008
const DEFAULT_CORNER_RADIUS := 0.02
const DEFAULT_CORNER_SEGMENTS := 2
const DEFAULT_HEIGHT_VARIATION := 0.003
const DEFAULT_COLOUR_VARIATION := 0.3

## Snap tolerance in normalized units for "this edge is the tile boundary".
## A computed grid edge lands within a float ulp of ±1, not on it.
const EDGE_EPSILON := 0.000001
## Below this a paver is a sliver rather than a stone, so it is dropped instead
## of built. Only reachable with a joint the validator has already rejected.
const MIN_PAVER := 0.004
## Two secondary slabs side by side merge into one blob and the paving loses its
## unit read, so a slab next to an already-secondary neighbour is damped hard.
const NEIGHBOUR_DAMPING := 0.15
## Discrete lift levels: half the slabs stay flush, a quarter sit proud, a
## quarter settle. Steps rather than a continuous range keep the faceted read.
const LIFT_STEPS: PackedFloat32Array = [0.0, 1.0, 0.0, -1.0]
## Soft budget above which the lab is told the tile is getting expensive.
const TRIANGLE_NOTE := 700

const KEY_RECTS := "rects"
const KEY_CUT := "cut"


## 2x2 slabs. The calmest paving: four broad colour regions and one cross joint.
const LAYOUT_QUAD: PackedVector4Array = [
	Vector4(-0.5, -0.5, 1.0, 1.0),
	Vector4(0.5, -0.5, 1.0, 1.0),
	Vector4(-0.5, 0.5, 1.0, 1.0),
	Vector4(0.5, 0.5, 1.0, 1.0),
]

## Running bond: four courses of 2:1 bricks, alternate courses offset by half a
## brick so head joints never stack. The offset courses deliberately run PAST
## the tile edge and are clipped there — a half brick on this tile meets its
## other half on the neighbour, which is what keeps the bond continuous instead
## of framing every tile. Four courses (an even count) so the course above the
## top one, on the neighbour, is still an offset course.
const LAYOUT_RUNNING: PackedVector4Array = [
	# Course 1, flush.
	Vector4(-0.5, -0.75, 1.0, 0.5),
	Vector4(0.5, -0.75, 1.0, 0.5),
	# Course 2, offset half a brick — the outer two are clipped to halves.
	Vector4(-1.0, -0.25, 1.0, 0.5),
	Vector4(0.0, -0.25, 1.0, 0.5),
	Vector4(1.0, -0.25, 1.0, 0.5),
	# Course 3, flush.
	Vector4(-0.5, 0.25, 1.0, 0.5),
	Vector4(0.5, 0.25, 1.0, 0.5),
	# Course 4, offset.
	Vector4(-1.0, 0.75, 1.0, 0.5),
	Vector4(0.0, 0.75, 1.0, 0.5),
	Vector4(1.0, 0.75, 1.0, 0.5),
]

## Basketweave: four unit cells in checker, each holding a pair of 2:1 bricks
## turned across its neighbours. Authored flush to the tile edge on purpose —
## cutting a cell through its pair stops the weave reading — and the checker
## still continues into the neighbour, because the tile is exactly two cells
## wide and parity therefore alternates across every seam.
const LAYOUT_BASKET: PackedVector4Array = [
	# South-west cell: pair lying east-west.
	Vector4(-0.5, -0.75, 1.0, 0.5),
	Vector4(-0.5, -0.25, 1.0, 0.5),
	# South-east cell: pair standing north-south.
	Vector4(0.25, -0.5, 0.5, 1.0),
	Vector4(0.75, -0.5, 0.5, 1.0),
	# North-west cell: pair standing north-south.
	Vector4(-0.75, 0.5, 0.5, 1.0),
	Vector4(-0.25, 0.5, 0.5, 1.0),
	# North-east cell: pair lying east-west.
	Vector4(0.5, 0.25, 1.0, 0.5),
	Vector4(0.5, 0.75, 1.0, 0.5),
]

## One hero slab with an L of fill pieces around it. Sizes step down through a
## deliberate 1.2 / 0.8 / 0.6 series so the eye reads a hierarchy rather than a
## shuffle. This layout is tile-specific by design: use it for a courtyard
## centre, not for a field that repeats.
const LAYOUT_MIXED: PackedVector4Array = [
	Vector4(-0.4, -0.4, 1.2, 1.2),  # hero slab
	Vector4(0.6, -0.7, 0.8, 0.6),  # east fill, south
	Vector4(0.6, -0.1, 0.8, 0.6),  # east fill, north
	Vector4(-0.6, 0.6, 0.8, 0.8),  # north fill, west
	Vector4(0.1, 0.6, 0.6, 0.8),  # north fill, centre
	Vector4(0.7, 0.6, 0.6, 0.8),  # north fill, east
]


func generator_id() -> String:
	return "paver_pattern"


func kinds() -> Array:
	return [TileForgeConstants.Kind.MESH]


func description() -> String:
	return "Authored paving templates — quad slabs, running bond, basketweave, grid, or mixed — extruded as chunky stone with restrained edges."


func validate(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> PackedStringArray:
	var problems := PackedStringArray()
	var template := _template_of(layer)
	if not TEMPLATES.has(template):
		problems.append(
			"unknown template '%s' (expected one of %s)" % [template, ", ".join(TEMPLATES)]
		)
		return problems

	var cells := layer.get_int("grid_size", DEFAULT_GRID_SIZE)
	if template == TEMPLATE_GRID and cells < 1:
		problems.append("grid_size %d must be at least 1" % cells)
		return problems

	var joint := layer.get_float("joint", DEFAULT_JOINT)
	if joint < 0.0:
		problems.append("joint %.4f m is negative — pavers would overlap" % joint)
	var thickness := layer.get_float("paver_thickness", DEFAULT_THICKNESS)
	if thickness <= 0.0:
		problems.append("paver_thickness %.4f m must be greater than zero" % thickness)

	# A joint is cut from both sides of an interior paver, so the smallest piece
	# in the template is what actually limits it.
	var smallest := _smallest_cell(_layout_for(layer), ctx.half_extent)
	if joint >= smallest * 0.5:
		problems.append(
			"joint %.4f m is too large for template '%s': its smallest paver is only %.4f m across"
			% [joint, template, smallest]
		)
		return problems

	var built: float = smallest - maxf(0.0, joint)
	var radius := layer.get_float("corner_radius", DEFAULT_CORNER_RADIUS)
	if radius > built * 0.5:
		problems.append(
			"corner_radius %.4f m exceeds half the smallest paver (%.4f m) — the slab would round away into a lozenge"
			% [radius, built]
		)
	return problems


func generate_mesh(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> Array[TileMeshPart]:
	var parts: Array[TileMeshPart] = []
	var pavers := _build_pavers(layer, ctx.half_extent)
	var rects: PackedVector4Array = pavers[KEY_RECTS]
	var cut_flags: PackedByteArray = pavers[KEY_CUT]
	if rects.is_empty():
		return parts

	var primary := layer.material_slot
	if primary == "":
		primary = TileForgeConstants.SLOT_TOP_PRIMARY
	var slot_of := _assign_slots(
		rects,
		primary,
		layer.secondary_slot,
		clampf(layer.get_float("colour_variation", DEFAULT_COLOUR_VARIATION), 0.0, 1.0),
		maxf(0.0, layer.get_float("joint", DEFAULT_JOINT)),
		ctx
	)

	var bottom_y := ctx.base_profile.canonical_seam()
	var thickness: float = maxf(0.001, layer.get_float("paver_thickness", DEFAULT_THICKNESS))
	# A chamfer deeper than the slab turns a paver into a pyramid.
	var bevel: float = clampf(
		layer.get_float("bevel", DEFAULT_BEVEL), 0.0, thickness * 0.45
	)
	var radius: float = maxf(0.0, layer.get_float("corner_radius", DEFAULT_CORNER_RADIUS))
	var segments: int = maxi(0, layer.get_int("corner_segments", DEFAULT_CORNER_SEGMENTS))
	var variation: float = maxf(0.0, layer.get_float("height_variation", DEFAULT_HEIGHT_VARIATION))
	var lift_rng := ctx.rng("paver_lift")

	var tools: Dictionary = {}
	var slot_order := PackedStringArray()
	for index in rects.size():
		var rect := rects[index]
		var slot := slot_of[index]
		if not tools.has(slot):
			var fresh := SurfaceTool.new()
			fresh.begin(Mesh.PRIMITIVE_TRIANGLES)
			# Constructed stone is faceted: one normal per face keeps the bevel
			# reading as a catchlight instead of a soft roll.
			fresh.set_smooth_group(-1)
			tools[slot] = fresh
			slot_order.append(slot)
		var surface: SurfaceTool = tools[slot]

		var size := Vector2(rect.z, rect.w)
		var was_cut := cut_flags[index] == 1
		# A paver the tile boundary halved is finished square so it fuses with
		# its other half on the neighbour into one brick.
		var outline := rounded_rect(
			size,
			0.0 if was_cut else radius,
			0 if was_cut else segments
		)
		# extrude_prism insets the cap radially, so a bevel near half the short
		# side would collapse the top into a point.
		var paver_bevel: float = 0.0 if was_cut else minf(bevel, minf(size.x, size.y) * 0.25)
		var lift: float = LIFT_STEPS[lift_rng.randi_range(0, LIFT_STEPS.size() - 1)] * variation
		extrude_prism(
			surface,
			outline,
			bottom_y,
			bottom_y + thickness + lift,
			paver_bevel,
			Transform2D(0.0, Vector2(rect.x, rect.y))
		)

	var mesh := ArrayMesh.new()
	for slot in slot_order:
		var surface: SurfaceTool = tools[slot]
		surface.generate_normals()
		surface.commit(mesh)
		mesh.surface_set_name(mesh.get_surface_count() - 1, slot)

	var part := TileMeshPart.make(mesh, slot_order, "surface")
	part.smooth_shading = false
	parts.append(part)

	var triangles := _estimate_triangles(rects, cut_flags, radius, segments, bevel)
	if triangles > TRIANGLE_NOTE:
		ctx.report(
			"paver template '%s' builds %d pavers (~%d triangles) — drop corner_segments to 1 to lighten it"
			% [_template_of(layer), rects.size(), triangles]
		)
	return parts


## Exact footprint: the outer paver edges are the tile edges, and every slab
## shares the structural seam as its underside.
func get_bounds(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> AABB:
	var extent := ctx.half_extent
	var bottom := ctx.base_profile.canonical_seam()
	var top: float = (
		bottom
		+ maxf(0.001, layer.get_float("paver_thickness", DEFAULT_THICKNESS))
		+ maxf(0.0, layer.get_float("height_variation", DEFAULT_HEIGHT_VARIATION))
	)
	return AABB(
		Vector3(-extent, bottom, -extent),
		Vector3(extent * 2.0, top - bottom, extent * 2.0)
	)


func get_debug_info(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> Dictionary:
	var pavers := _build_pavers(layer, ctx.half_extent)
	var rects: PackedVector4Array = pavers[KEY_RECTS]
	var cut_flags: PackedByteArray = pavers[KEY_CUT]
	var cut_count := 0
	for value: int in cut_flags:
		if value == 1:
			cut_count += 1
	var radius: float = maxf(0.0, layer.get_float("corner_radius", DEFAULT_CORNER_RADIUS))
	var segments: int = maxi(0, layer.get_int("corner_segments", DEFAULT_CORNER_SEGMENTS))
	var bevel: float = maxf(0.0, layer.get_float("bevel", DEFAULT_BEVEL))
	return {
		"generator": generator_id(),
		"template": _template_of(layer),
		"pavers": rects.size(),
		"clipped": cut_count,
		"joint": layer.get_float("joint", DEFAULT_JOINT),
		"smallest_paver": _smallest_cell(_layout_for(layer), ctx.half_extent),
		"triangles": _estimate_triangles(rects, cut_flags, radius, segments, bevel),
	}


# --- Layout -------------------------------------------------------------------

static func _template_of(layer: TileSurfaceLayer) -> String:
	return layer.get_string("template", TEMPLATE_QUAD)


## The authored rectangle table for a layer, in normalized tile space.
static func _layout_for(layer: TileSurfaceLayer) -> PackedVector4Array:
	match _template_of(layer):
		TEMPLATE_RUNNING:
			return LAYOUT_RUNNING
		TEMPLATE_BASKET:
			return LAYOUT_BASKET
		TEMPLATE_GRID:
			return _grid_layout(maxi(1, layer.get_int("grid_size", DEFAULT_GRID_SIZE)))
		TEMPLATE_MIXED:
			return LAYOUT_MIXED
	return LAYOUT_QUAD


## The one template that cannot be a literal table, because its cell count is a
## parameter. It still covers -1..1 exactly.
static func _grid_layout(cells: int) -> PackedVector4Array:
	var result := PackedVector4Array()
	var step := 2.0 / float(cells)
	for j in cells:
		for i in cells:
			result.append(Vector4(
				-1.0 + (float(i) + 0.5) * step,
				-1.0 + (float(j) + 0.5) * step,
				step,
				step
			))
	return result


## Turns the authored table into the pavers actually built: clipped to the tile,
## joints opened on interior edges only. Pure — takes no context and consumes no
## randomness — so validation, debug, and the mesh pass all see the same layout.
## Returns { KEY_RECTS: PackedVector4Array, KEY_CUT: PackedByteArray }.
static func _build_pavers(layer: TileSurfaceLayer, extent: float) -> Dictionary:
	var half_joint: float = maxf(0.0, layer.get_float("joint", DEFAULT_JOINT)) * 0.5
	var rects := PackedVector4Array()
	var cut_flags := PackedByteArray()

	for cell: Vector4 in _layout_for(layer):
		var min_u := cell.x - cell.z * 0.5
		var max_u := cell.x + cell.z * 0.5
		var min_v := cell.y - cell.w * 0.5
		var max_v := cell.y + cell.w * 0.5
		var was_cut := (
			min_u < -1.0 - EDGE_EPSILON
			or max_u > 1.0 + EDGE_EPSILON
			or min_v < -1.0 - EDGE_EPSILON
			or max_v > 1.0 + EDGE_EPSILON
		)
		# Snapping rather than clamping: a computed grid edge lands a float ulp
		# off ±1, and the boundary has to be exact, not approximate.
		var at_min_u := min_u <= -1.0 + EDGE_EPSILON
		var at_max_u := max_u >= 1.0 - EDGE_EPSILON
		var at_min_v := min_v <= -1.0 + EDGE_EPSILON
		var at_max_v := max_v >= 1.0 - EDGE_EPSILON
		min_u = -1.0 if at_min_u else min_u
		max_u = 1.0 if at_max_u else max_u
		min_v = -1.0 if at_min_v else min_v
		max_v = 1.0 if at_max_v else max_v
		if max_u - min_u <= EDGE_EPSILON or max_v - min_v <= EDGE_EPSILON:
			continue

		var x0: float = min_u * extent + (0.0 if at_min_u else half_joint)
		var x1: float = max_u * extent - (0.0 if at_max_u else half_joint)
		var z0: float = min_v * extent + (0.0 if at_min_v else half_joint)
		var z1: float = max_v * extent - (0.0 if at_max_v else half_joint)
		if x1 - x0 <= MIN_PAVER or z1 - z0 <= MIN_PAVER:
			continue

		rects.append(Vector4((x0 + x1) * 0.5, (z0 + z1) * 0.5, x1 - x0, z1 - z0))
		cut_flags.append(1 if was_cut else 0)

	return {KEY_RECTS: rects, KEY_CUT: cut_flags}


## Shortest side of any piece the template actually produces, LIVE metres.
## Measured after boundary clipping, because a clipped half brick is the piece
## a joint or a corner radius has to survive.
static func _smallest_cell(layout: PackedVector4Array, extent: float) -> float:
	var smallest := INF
	for cell: Vector4 in layout:
		var width: float = (
			minf(cell.x + cell.z * 0.5, 1.0) - maxf(cell.x - cell.z * 0.5, -1.0)
		) * extent
		var depth: float = (
			minf(cell.y + cell.w * 0.5, 1.0) - maxf(cell.y - cell.w * 0.5, -1.0)
		) * extent
		if width > 0.0:
			smallest = minf(smallest, width)
		if depth > 0.0:
			smallest = minf(smallest, depth)
	return extent * 2.0 if smallest == INF else smallest


# --- Colour -------------------------------------------------------------------

## Colour is a whole-slab decision: half a paver in a second tone reads as a
## texture, not as stone. The secondary slot is damped next to a slab that
## already took it so two of them seldom merge into one blob.
static func _assign_slots(
	rects: PackedVector4Array,
	primary: String,
	secondary: String,
	share: float,
	joint: float,
	ctx: TileGenerationContext
) -> PackedStringArray:
	var result := PackedStringArray()
	if secondary == "" or share <= 0.0:
		for index in rects.size():
			result.append(primary)
		return result

	var rng := ctx.rng("paver")
	var taken := PackedByteArray()
	taken.resize(rects.size())
	taken.fill(0)
	for index in rects.size():
		var chance := share
		for other in index:
			if taken[other] == 1 and _touching(rects[index], rects[other], joint):
				chance *= NEIGHBOUR_DAMPING
		# The draw is consumed whatever the odds, so adding a paver to a template
		# cannot reshuffle the colour of every paver after it.
		if rng.randf() < chance:
			taken[index] = 1
		result.append(secondary if taken[index] == 1 else primary)
	return result


## Two pavers are neighbours when only a joint separates them. Diagonal contact
## counts: a slab touching at a corner still reads as adjacent from the game
## camera.
static func _touching(a: Vector4, b: Vector4, joint: float) -> bool:
	var reach := joint * 1.5 + 0.001
	return (
		absf(a.x - b.x) <= (a.z + b.z) * 0.5 + reach
		and absf(a.y - b.y) <= (a.w + b.w) * 0.5 + reach
	)


# --- Budget -------------------------------------------------------------------

static func _outline_points(radius: float, segments: int) -> int:
	return 4 * (segments + 1) if radius > 0.0001 and segments > 0 else 4


## Mirrors what `extrude_prism` emits: walls plus a cap, and a chamfer ring when
## a bevel is asked for. Cut pavers are always plain prisms.
static func _estimate_triangles(
	rects: PackedVector4Array,
	cut_flags: PackedByteArray,
	radius: float,
	segments: int,
	bevel: float
) -> int:
	var whole_points := _outline_points(radius, segments)
	var whole_cost := (5 if bevel > 0.0001 else 3) * whole_points
	var cut_cost := 3 * 4
	var total := 0
	for index in rects.size():
		total += cut_cost if cut_flags[index] == 1 else whole_cost
	return total
