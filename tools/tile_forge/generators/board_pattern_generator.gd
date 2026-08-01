@tool
class_name BoardPatternGenerator
extends TileLayerGenerator
## Constructed plank decking: docks, bridges, boardwalks, wooden floors.
##
## The point of this family is that two neighbouring tiles read as ONE deck.
## That is a layout guarantee rather than a modelling one: board width is
## DERIVED from the tile size so the outermost board edge lands exactly on
## ±half_extent, and every groove is interior. A deck that shrank away from its
## own edge would draw a dark trench around every tile, which is the loudest
## "this is a grid of tiles" tell there is.
##
## Shape is pure layout arithmetic — no heightfield contribution, no noise. The
## only randomness is a sub-centimetre per-board lift and a two-tone colour
## choice, both on their own seeded channels.
##
## Params:
##   layout            String  "horizontal" (boards run along X), "vertical"
##                             (boards run along Z), or "alternating" (two
##                             parquet bands at 90° to each other).
##   board_count       int     Boards across the run axis. Default 5.
##   gap               float   Groove between boards, LIVE metres. Default 0.012.
##   board_thickness   float   Seam-to-top height, metres. Default 0.055 — the
##                             standard seam depth, so a default deck tops out
##                             flush on the walk plane.
##   stagger           float   0..1 fraction of a board length the end joint
##                             walks per row. Ignored when joint_rows <= 1.
##   joint_rows        int     How many boards long the tile is along the run
##                             axis. Default 1; >1 introduces end joints.
##   bevel             float   Top chamfer, metres. Default 0.006.
##   height_variation  float   Peak-to-peak per-board lift, metres. Default
##                             0.004.
##   colour_variation  float   0..1 fraction of WHOLE boards painted with
##                             `secondary_slot`. Default 0.45.

## Hard ceiling on per-board lift. Past a couple of millimetres a proud board
## stops reading as a plank and starts reading as a bug.
const MAX_HEIGHT_VARIATION := 0.02
## A run fragment shorter than this fraction of a board is absorbed by its
## neighbour instead of shipped as a sliver — the call a carpenter would make.
const MIN_PIECE_FRACTION := 0.28
## Breaks the two-tone accumulator out of a strict stripe without moving the
## requested share.
const COLOUR_JITTER := 0.08
## Boards are drawn as rounded rectangles; the corner radius is tied to the
## bevel so one knob controls the whole softness of the constructed read.
const CORNER_RADIUS_SCALE := 1.5


func generator_id() -> String:
	return "board_pattern"


func kinds() -> Array:
	return [TileForgeConstants.Kind.MESH]


func description() -> String:
	return "Plank decking that tiles seamlessly: docks, bridges, boardwalks, wooden floors."


func validate(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> PackedStringArray:
	var problems := PackedStringArray()
	var count := layer.get_int("board_count", 5)
	var gap := layer.get_float("gap", 0.012)
	var thickness := layer.get_float("board_thickness", 0.055)
	if count < 1:
		problems.append("board_count %d must be at least 1" % count)
	if gap < 0.0:
		problems.append("gap %.4f m cannot be negative" % gap)
	if gap * float(count - 1) >= ctx.tile_size:
		problems.append(
			"gap %.4f m across %d boards consumes the whole %.3f m tile"
			% [gap, count, ctx.tile_size]
		)
	if thickness <= 0.0:
		problems.append("board_thickness %.4f m must be positive" % thickness)
	return problems


func generate_mesh(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> Array[TileMeshPart]:
	var boards := _plan_boards(layer, ctx)
	if boards.is_empty():
		return []

	var primary := layer.material_slot
	if primary == "":
		primary = TileForgeConstants.SLOT_TOP_PRIMARY
	var secondary := layer.secondary_slot
	var share: float = clampf(layer.get_float("colour_variation", 0.45), 0.0, 1.0)
	var two_tone := secondary != "" and share > 0.0
	# A fully committed share has no pattern left to break up, and jittering it
	# would drop the odd primary board into an otherwise uniform deck.
	var colour_jitter := COLOUR_JITTER if share < 1.0 else 0.0

	var seam := ctx.base_profile.canonical_seam()
	var thickness: float = maxf(0.001, layer.get_float("board_thickness", 0.055))
	var lift_half := _lift_half(layer, thickness)
	var bevel: float = maxf(0.0, layer.get_float("bevel", 0.006))

	var height_rng := ctx.rng("board")
	# Its own stream: retuning the two-tone share must never shuffle the heights.
	var colour_rng := ctx.rng("board_colour")
	var carry := colour_rng.randf()

	var tools: Dictionary = {}
	var slot_order := PackedStringArray()

	for board in boards:
		var size: Vector2 = board["size"]
		var centre: Vector2 = board["centre"]
		var top_y := seam + thickness + height_rng.randf_range(-lift_half, lift_half)

		var slot := primary
		if two_tone:
			# An accumulator rather than a per-board coin flip: it lands on the
			# requested share exactly, and at any share near a half it almost
			# never hands two neighbours the same colour. The jitter is what
			# stops the result reading as a painted stripe.
			carry += share + colour_rng.randf_range(-colour_jitter, colour_jitter)
			if carry >= 1.0:
				slot = secondary
				carry -= 1.0
			carry = clampf(carry, 0.0, 0.999)

		if not tools.has(slot):
			var fresh := SurfaceTool.new()
			fresh.begin(Mesh.PRIMITIVE_TRIANGLES)
			# Faceted throughout. A plank with averaged normals reads as moulded
			# plastic, not as sawn timber.
			fresh.set_smooth_group(-1)
			tools[slot] = fresh
			slot_order.append(slot)

		# Bevel is bounded by the board itself so a narrow plank or a thin deck
		# cannot invert its own chamfer.
		var piece_bevel: float = minf(bevel, minf(size.x, size.y) * 0.25)
		piece_bevel = minf(piece_bevel, (top_y - seam) * 0.4)
		var tool: SurfaceTool = tools[slot]
		extrude_prism(
			tool,
			rounded_rect(size, piece_bevel * CORNER_RADIUS_SCALE, 1),
			seam,
			top_y,
			piece_bevel,
			Transform2D(0.0, centre)
		)

	var mesh := ArrayMesh.new()
	for slot in slot_order:
		var tool: SurfaceTool = tools[slot]
		tool.generate_normals()
		# Indexed only AFTER the normals exist, so welding can merge nothing but
		# vertices that already agree on a face normal — the faceted read
		# survives, and the surface carries the index array TileMeshPart needs to
		# report an honest triangle count.
		tool.index()
		tool.commit(mesh)
		mesh.surface_set_name(mesh.get_surface_count() - 1, slot)

	var part := TileMeshPart.make(mesh, slot_order, "surface")
	part.smooth_shading = false
	var parts: Array[TileMeshPart] = [part]
	return parts


## The recipe's FLAT_BOX already spans the deck. Per-board shapes would cost
## many times as much for a surface the player only ever walks across.
func generate_collision(_layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> Array:
	return []


func get_bounds(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> AABB:
	var extent := ctx.half_extent
	var seam := ctx.base_profile.canonical_seam()
	var thickness: float = maxf(0.001, layer.get_float("board_thickness", 0.055))
	# Exactly the tile footprint: the layout arithmetic guarantees it, so the
	# declared bounds must not hedge with a margin.
	return AABB(
		Vector3(-extent, seam, -extent),
		Vector3(extent * 2.0, thickness + _lift_half(layer, thickness), extent * 2.0)
	)


func get_debug_info(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> Dictionary:
	var boards := _plan_boards(layer, ctx)
	# 8-point rounded outline costs 5 triangles per point once bevelled; a plain
	# rectangle costs 12 in total. Reported so a heavy joint_rows setting is
	# visible before the geometry budget check flags it.
	var per_board := 40 if layer.get_float("bevel", 0.006) > 0.0001 else 12
	return {
		"generator": generator_id(),
		"layout": layer.get_string("layout", "horizontal"),
		"boards": boards.size(),
		"triangles": boards.size() * per_board,
	}


# --- Layout -------------------------------------------------------------------

## Every board's footprint rect in LIVE space, in a stable order. Deliberately
## free of randomness so the debug report and the emitted mesh always agree.
func _plan_boards(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count: int = maxi(1, layer.get_int("board_count", 5))
	var gap: float = maxf(0.0, layer.get_float("gap", 0.012))
	var joint_rows: int = maxi(1, layer.get_int("joint_rows", 1))
	var stagger: float = clampf(layer.get_float("stagger", 0.0), 0.0, 1.0)
	if joint_rows <= 1:
		# A single-piece run has no end joint for the stagger to walk.
		stagger = 0.0

	var nominal_width: float = maxf(
		0.002, (ctx.tile_size - gap * float(count - 1)) / float(count)
	)
	var nominal_pitch := nominal_width + gap

	for band in _bands(layer, ctx.half_extent, gap, count, nominal_pitch):
		var run_axis: int = band["run_axis"]
		var across_min: float = band["across_min"]
		var across_max: float = band["across_max"]
		var run_min: float = band["run_min"]
		var run_max: float = band["run_max"]
		var rows: int = band["rows"]

		var width := (across_max - across_min - gap * float(rows - 1)) / float(rows)
		var seg_len := (run_max - run_min - gap * float(joint_rows - 1)) / float(joint_rows)
		if width <= 0.0 or seg_len <= 0.0:
			continue
		var pitch := seg_len + gap
		var min_piece := seg_len * MIN_PIECE_FRACTION

		for row in rows:
			var near := across_min + float(row) * (width + gap)
			var far := near + width
			# Snapped rather than trusted to accumulate exactly: the outermost
			# board edge IS the seam contract, and a float ulp of drift there is
			# a visible hairline between two decks.
			if row == 0:
				near = across_min
			if row == rows - 1:
				far = across_max
			var offset := fposmod(stagger * seg_len * float(row), pitch)
			for piece in _row_pieces(run_min, run_max, seg_len, pitch, offset, min_piece):
				var along := Vector2(piece.y - piece.x, (piece.x + piece.y) * 0.5)
				var across := Vector2(far - near, (near + far) * 0.5)
				# Built pre-oriented instead of rotated: a Transform2D rotation
				# would smear the exact boundary coordinates by a float epsilon.
				if run_axis == 0:
					result.append({
						"size": Vector2(along.x, across.x),
						"centre": Vector2(along.y, across.y),
					})
				else:
					result.append({
						"size": Vector2(across.x, along.x),
						"centre": Vector2(across.y, along.y),
					})
	return result


## Band decomposition. "alternating" is a parquet: two halves running at 90° to
## each other, split down the middle with one groove's worth of joint so the two
## grains never touch. Each band re-derives its row count from the nominal board
## width, so a half-depth band still gets planks of the same visual scale
## instead of comically narrow ones.
func _bands(
	layer: TileSurfaceLayer,
	extent: float,
	gap: float,
	count: int,
	nominal_pitch: float
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match layer.get_string("layout", "horizontal").to_lower():
		"vertical":
			result.append({
				"run_axis": 1,
				"run_min": -extent,
				"run_max": extent,
				"across_min": -extent,
				"across_max": extent,
				"rows": count,
			})
		"alternating":
			var split := gap * 0.5
			result.append({
				"run_axis": 0,
				"run_min": -extent,
				"run_max": extent,
				"across_min": -extent,
				"across_max": -split,
				"rows": _rows_for(extent - split, nominal_pitch, gap),
			})
			result.append({
				"run_axis": 1,
				"run_min": split,
				"run_max": extent,
				"across_min": -extent,
				"across_max": extent,
				"rows": count,
			})
		_:
			result.append({
				"run_axis": 0,
				"run_min": -extent,
				"run_max": extent,
				"across_min": -extent,
				"across_max": extent,
				"rows": count,
			})
	return result


## Rows that keep a band's plank width closest to the nominal width derived from
## the whole tile. A full-span band recovers `board_count` exactly. Ties break
## towards FEWER, wider rows: a half band whose planks are narrower than the
## full band's reads as squeezed rather than as parquet.
static func _rows_for(span: float, nominal_pitch: float, gap: float) -> int:
	return maxi(1, int(ceil((span + gap) / maxf(0.0001, nominal_pitch) - 0.5)))


## Cut list for one row along the run axis, as (start, end) pairs. The periodic
## joint pattern is shifted by `offset` and then clipped, and the two end pieces
## are pushed out to the band limits: a tile boundary must land on solid board,
## never inside a groove, or the neighbouring deck opens a double-width gap.
static func _row_pieces(
	run_min: float,
	run_max: float,
	seg_len: float,
	pitch: float,
	offset: float,
	min_piece: float
) -> PackedVector2Array:
	var pieces := PackedVector2Array()
	var last := int(ceil((run_max - run_min) / maxf(0.0001, pitch))) + 1
	for index in range(-1, last + 1):
		var start: float = maxf(run_min + offset + float(index) * pitch, run_min)
		var end: float = minf(run_min + offset + float(index) * pitch + seg_len, run_max)
		if end - start < min_piece:
			continue
		pieces.append(Vector2(start, end))
	if pieces.is_empty():
		pieces.append(Vector2(run_min, run_max))
		return pieces
	pieces[0] = Vector2(run_min, pieces[0].y)
	pieces[pieces.size() - 1] = Vector2(pieces[pieces.size() - 1].x, run_max)
	return pieces


## Half of the per-board lift, capped twice: never more than a couple of
## millimetres, and never enough for a thin deck to swallow its own thickness.
static func _lift_half(layer: TileSurfaceLayer, thickness: float) -> float:
	return minf(
		maxf(0.0, layer.get_float("height_variation", 0.004)) * 0.5,
		minf(MAX_HEIGHT_VARIATION * 0.5, thickness * 0.25)
	)
