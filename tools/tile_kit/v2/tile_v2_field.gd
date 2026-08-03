class_name TileV2Field
extends RefCounted
## The V2 sculpt field: one deterministic 2.5D height-and-paint function per
## tile, composed from AUTHORED primitives instead of noise.
##
## A field is an ordered op list. Each op contributes a height shape (dome,
## dune ridge, plateau, basin, ramp, swell, breakup) plus an optional paint
## colour over its own footprint. The final surface therefore IS the
## material's macro-form — the mesher samples this field directly; there is
## no flat cap underneath.
##
## Height semantics for MERGE_MAX ops: the candidate surface is
## lerp(current_ground, op_base, weight) + shape — inside its silhouette the
## op builds from its resolved base level, at its skirt it hands back to
## whatever ground is already there, and outside it contributes NOTHING.
## (The first draft let bases leak tile-wide; overlapping lobes cascaded
## into a raised pudding plateau that flattened every composition.)
##
## Paint is a colour compositor, not a key argmax: a height-ramp of colour
## stops shades the substrate continuously, and each painting op blends its
## colour in over a soft threshold of its own footprint weight — colour
## edges land on the op's steep shoulder, never on a triangle staircase.
##
## Seam safety: outside authored edge-carry regions the field eases to the
## recipe's rim shoulder across the edge band. An op with edge_carry > 0 may
## break the rim — that is how a dune exits the tile or a moss lobe rounds
## over an edge, deliberately, one or two per composition.

const TILE := 1.70
const HALF := TILE / 2.0

# Op kinds (encoded for the hot loop).
enum {
	KIND_DOME,
	KIND_RIDGE,
	KIND_PLATEAU,
	KIND_RAMP,
	KIND_SWELL,
	KIND_BREAKUP,
}

# Merge modes.
enum {
	MERGE_MAX,   # smooth-max union from the op's own base level
	MERGE_ADD,   # additive (broad ramps and swells)
	MERGE_CARVE, # smooth-min carve (basins, compressions)
}

## Authored ops (dictionaries; see the library composers for the schema).
## Painting ops carry "paint_color": Color (resolved by the composer).
var ops: Array[Dictionary] = []

## Substrate colour ramp: ascending [[height, Color], ...]. Heights outside
## the ramp clamp to the end stops; between stops the colour interpolates.
var color_stops: Array = []

## Edge behaviour.
var rim_level := 0.02
var edge_band := 0.22
var corner_radius := 0.10
var floor_min := -0.045

## Outputs of sample_into() — read immediately after the call.
var out_height := 0.0
var out_color := Color.WHITE

# --- compiled op data (filled by prepare) ------------------------------------

const STRIDE := 12

var _count := 0
var _kind := PackedInt32Array()
var _merge := PackedInt32Array()
var _atx := PackedFloat64Array()
var _aty := PackedFloat64Array()
var _cosy := PackedFloat64Array()
var _siny := PackedFloat64Array()
var _base := PackedFloat64Array()
var _blend := PackedFloat64Array()
var _carry := PackedFloat64Array()
var _has_paint := PackedInt32Array()
var _paint_r := PackedFloat64Array()
var _paint_g := PackedFloat64Array()
var _paint_b := PackedFloat64Array()
var _paint_lo := PackedFloat64Array()
var _paint_hi := PackedFloat64Array()
var _p := PackedFloat64Array()        # kind-specific params, STRIDE per op

var _stop_h := PackedFloat64Array()
var _stop_r := PackedFloat64Array()
var _stop_g := PackedFloat64Array()
var _stop_b := PackedFloat64Array()
var _skip_edge := false


## Compiles ops and resolves op base levels: an op building on the substrate
## rides whatever the ops before it already sculpted at its centre (a
## cushion on a soil rise sits higher than one in a hollow). Deterministic.
func prepare() -> void:
	_count = ops.size()
	_kind.resize(_count)
	_merge.resize(_count)
	_atx.resize(_count)
	_aty.resize(_count)
	_cosy.resize(_count)
	_siny.resize(_count)
	_base.resize(_count)
	_blend.resize(_count)
	_carry.resize(_count)
	_has_paint.resize(_count)
	_paint_r.resize(_count)
	_paint_g.resize(_count)
	_paint_b.resize(_count)
	_paint_lo.resize(_count)
	_paint_hi.resize(_count)
	_p.resize(_count * STRIDE)
	for index in _count:
		var op := ops[index]
		var kind := int(op["kind"])
		_kind[index] = kind
		_merge[index] = int(op["merge"])
		var at: Vector2 = op["at"]
		_atx[index] = at.x
		_aty[index] = at.y
		var yaw: float = op.get("yaw", 0.0)
		_cosy[index] = cos(yaw)
		_siny[index] = sin(yaw)
		_blend[index] = op.get("blend", 0.03)
		_carry[index] = op.get("edge_carry", 0.0)
		if op.has("paint_color"):
			var paint: Color = op["paint_color"]
			_has_paint[index] = 1
			_paint_r[index] = paint.r
			_paint_g[index] = paint.g
			_paint_b[index] = paint.b
			var paint_min: float = op.get("paint_min", 0.4)
			var feather: float = op.get("paint_feather", 0.11)
			_paint_lo[index] = paint_min - feather
			_paint_hi[index] = paint_min + feather
		else:
			_has_paint[index] = 0
		var s := index * STRIDE
		match kind:
			KIND_DOME:
				var softness: float = op.get("softness", 0.6)
				_p[s + 0] = maxf(float(op.get("rx", 0.2)), 0.0001)
				_p[s + 1] = maxf(float(op.get("rz", op.get("rx", 0.2))), 0.0001)
				_p[s + 2] = op.get("height", 0.1)
				_p[s + 3] = lerpf(3.4, 2.1, softness)   # superellipse a
				_p[s + 4] = lerpf(0.50, 0.80, softness) # superellipse e
				_p[s + 5] = op.get("scallop", 0.0)
				_p[s + 6] = float(op.get("scallop_a", 3))
				_p[s + 7] = float(op.get("scallop_b", 5))
				_p[s + 8] = op.get("scallop_phase", 0.0)
				_p[s + 9] = op.get("scallop_phase_b", 1.7)
			KIND_RIDGE:
				var softness: float = op.get("softness", 0.7)
				_p[s + 0] = maxf(float(op.get("length", 0.8)), 0.0001)
				_p[s + 1] = maxf(float(op.get("width_windward", 0.30)), 0.0001)
				_p[s + 2] = maxf(float(op.get("width_lee", 0.14)), 0.0001)
				_p[s + 3] = op.get("height", 0.12)
				_p[s + 4] = op.get("curve", 0.0)
				_p[s + 5] = lerpf(3.6, 1.9, softness)   # across power
				_p[s + 6] = lerpf(4.0, 2.2, softness)   # along power
			KIND_PLATEAU:
				var hx: float = op.get("hx", 0.3)
				var hz: float = op.get("hz", 0.24)
				_p[s + 0] = hx
				_p[s + 1] = hz
				_p[s + 2] = clampf(float(op.get("corner", minf(hx, hz) * 0.55)),
					0.002, minf(hx, hz) - 0.002)
				_p[s + 3] = maxf(float(op.get("bevel", 0.05)), 0.0001)
				_p[s + 4] = op.get("height", 0.06)
				_p[s + 5] = op.get("dome", 0.0)
				_p[s + 6] = op.get("wobble", 0.0)
				_p[s + 7] = op.get("wobble_phase", 0.0)
				_p[s + 8] = maxf(minf(hx, hz), 0.0001)  # dome reach
			KIND_RAMP:
				_p[s + 0] = maxf(float(op.get("run", TILE)), 0.0001)
				_p[s + 1] = op.get("height", 0.05)
			KIND_SWELL:
				_p[s + 0] = maxf(float(op.get("rx", 0.7)), 0.0001)
				_p[s + 1] = maxf(float(op.get("rz", op.get("rx", 0.7))), 0.0001)
				_p[s + 2] = op.get("height", 0.03)
			KIND_BREAKUP:
				_p[s + 0] = op.get("frequency", 2.6)
				_p[s + 1] = op.get("phase", 0.0)
				_p[s + 2] = op.get("height", 0.008)
		# Base level: MERGE_MAX ops that ride the surface sample the partial
		# stack beneath their centre, minus their sink.
		var sink: float = op.get("sink", 0.0)
		if _merge[index] == MERGE_MAX and bool(op.get("ride_surface", true)):
			_base[index] = _height_up_to(index, at.x, at.y) - sink
		else:
			_base[index] = -sink

	_stop_h.resize(color_stops.size())
	_stop_r.resize(color_stops.size())
	_stop_g.resize(color_stops.size())
	_stop_b.resize(color_stops.size())
	for index in color_stops.size():
		var stop: Array = color_stops[index]
		_stop_h[index] = stop[0]
		var color: Color = stop[1]
		_stop_r[index] = color.r
		_stop_g[index] = color.g
		_stop_b[index] = color.b


## The hot path: computes height AND colour at (px, py) into out_height /
## out_color. No allocations, no Dictionary access.
func sample_into(px: float, py: float) -> void:
	var h := 0.0
	var carry := 0.0
	# Paint accumulators: op paints composite over the substrate ramp.
	var paint_mix := 0.0
	var paint_red := 0.0
	var paint_green := 0.0
	var paint_blue := 0.0
	for index in _count:
		var shape_h := 0.0
		var weight := 0.0
		# --- inline shape evaluation ---
		var dx := px - _atx[index]
		var dy := py - _aty[index]
		var c := _cosy[index]
		var s := _siny[index]
		var lx := dx * c + dy * s
		var ly := -dx * s + dy * c
		var base := index * STRIDE
		match _kind[index]:
			KIND_DOME:
				var rx := _p[base + 0]
				var rz := _p[base + 1]
				var scallop := _p[base + 5]
				var factor := 1.0
				if scallop > 0.0:
					var angle := atan2(ly / rz, lx / rx)
					factor = 1.0 + scallop * (
						0.62 * sin(angle * _p[base + 6] + _p[base + 8])
						+ 0.38 * sin(angle * _p[base + 7] + _p[base + 9]))
					factor = maxf(factor, 0.15)
				var sx := lx / (rx * factor)
				var sz := ly / (rz * factor)
				var dist := sqrt(sx * sx + sz * sz)
				if dist < 1.0:
					weight = pow(maxf(0.0, 1.0 - pow(dist, _p[base + 3])),
						_p[base + 4])
					shape_h = _p[base + 2] * weight
			KIND_RIDGE:
				var length := _p[base + 0]
				var along_t := absf(lx) / length
				if along_t < 1.55:
					var across := ly - _p[base + 4] * lx * lx / length
					# Windward and lee widths blend across the crest — a hard
					# switch creases the ridge line into folded cloth.
					var width := lerpf(_p[base + 1], _p[base + 2],
						smoothstep(-0.06, 0.06, across))
					var across_n := absf(across) / width
					weight = exp(-pow(across_n, _p[base + 5])
						- pow(along_t, _p[base + 6]))
					shape_h = _p[base + 3] * weight
			KIND_PLATEAU:
				var corner := _p[base + 2]
				var qx := absf(lx) - (_p[base + 0] - corner)
				var qy := absf(ly) - (_p[base + 1] - corner)
				var outside := sqrt(
					maxf(qx, 0.0) * maxf(qx, 0.0) + maxf(qy, 0.0) * maxf(qy, 0.0))
				var sd := outside + minf(maxf(qx, qy), 0.0) - corner
				var wobble := _p[base + 6]
				if wobble > 0.0:
					var angle := atan2(ly, lx)
					sd += wobble * 0.5 * (
						sin(angle * 3.0 + _p[base + 7])
						+ sin(angle * 5.0 - _p[base + 7]))
				if sd < 0.0:
					var t := clampf(-sd / _p[base + 3], 0.0, 1.0)
					weight = t * t * (3.0 - 2.0 * t)
					var inner := clampf(-sd / _p[base + 8], 0.0, 1.0)
					var inv := 1.0 - inner
					shape_h = _p[base + 4] * weight \
						+ _p[base + 5] * (1.0 - inv * inv)
			KIND_RAMP:
				var t := clampf(lx / _p[base + 0] + 0.5, 0.0, 1.0)
				shape_h = _p[base + 1] * t * t * (3.0 - 2.0 * t)
			KIND_SWELL:
				var sx := lx / _p[base + 0]
				var sz := ly / _p[base + 1]
				var dist := sqrt(sx * sx + sz * sz)
				if dist < 1.0:
					var lobe := cos(dist * PI * 0.5)
					shape_h = _p[base + 2] * lobe * lobe
			KIND_BREAKUP:
				# Three plane waves ~60° apart: interference reads as gentle
				# hand-pressed unevenness, never as a woven axis-aligned grid.
				var frequency := _p[base + 0] * TAU * 0.27
				var phase := _p[base + 1]
				var v := 0.45 * sin(
						(px * 0.955 + py * 0.296) * frequency + phase) \
					+ 0.33 * sin((px * -0.221 + py * 0.975) * frequency * 1.13
						+ phase * 1.7 + 1.2) \
					+ 0.29 * sin((px * -0.737 - py * 0.676) * frequency * 0.87
						- phase * 0.8 + 2.6)
				shape_h = _p[base + 2] * v * 0.93
		# --- merge ---
		match _merge[index]:
			MERGE_MAX:
				if weight > 0.0005:
					# The candidate hands back to the existing ground at the
					# op's skirt — bases never leak outside the silhouette.
					var b := h + (_base[index] - h) * weight + shape_h
					var k := _blend[index]
					if k <= 0.0001:
						h = maxf(h, b)
					else:
						var t := clampf(0.5 + 0.5 * (b - h) / k, 0.0, 1.0)
						h = lerpf(h, b, t) + k * t * (1.0 - t)
			MERGE_ADD:
				h += shape_h
			MERGE_CARVE:
				if shape_h > 0.0:
					var b := h - shape_h
					var k := _blend[index]
					if k <= 0.0001:
						h = minf(h, b)
					else:
						var t := clampf(0.5 + 0.5 * (h - b) / k, 0.0, 1.0)
						h = lerpf(h, b, t) - k * t * (1.0 - t)
		# --- carry + paint ---
		var op_carry := _carry[index]
		if op_carry > 0.0:
			var carried := weight * op_carry
			if carried > carry:
				carry = carried
		if _has_paint[index] == 1 and weight > _paint_lo[index]:
			var alpha := smoothstep(_paint_lo[index], _paint_hi[index], weight)
			# Standard over-compositing so later ops paint over earlier ones.
			paint_red = lerpf(paint_red, _paint_r[index], alpha)
			paint_green = lerpf(paint_green, _paint_g[index], alpha)
			paint_blue = lerpf(paint_blue, _paint_b[index], alpha)
			paint_mix = paint_mix + (1.0 - paint_mix) * alpha

	# Rim easing toward a rounded shoulder: the rim dips slightly at the very
	# edge and rises inward, so the boundary reads as material rolling over —
	# never as a flat tray moat. Carried ops override the easing.
	if _skip_edge:
		out_height = h
	else:
		var inset := boundary_inset_xy(px, py)
		var ease_t := smoothstep(0.0, edge_band, inset)
		var carried_ease := smoothstep(0.0, 0.55, carry)
		if carried_ease > ease_t:
			ease_t = carried_ease
		var shoulder := rim_level * (0.48 + 0.52 * smoothstep(0.0, 0.15, inset))
		h = lerpf(shoulder, h, ease_t)
		if h < floor_min:
			h = floor_min
		out_height = h

	# Substrate ramp by final height, then op paints over it.
	var red: float
	var green: float
	var blue: float
	var stop_count := _stop_h.size()
	if stop_count == 0:
		red = 0.8
		green = 0.2
		blue = 0.8
	elif out_height <= _stop_h[0] or stop_count == 1:
		red = _stop_r[0]
		green = _stop_g[0]
		blue = _stop_b[0]
	elif out_height >= _stop_h[stop_count - 1]:
		red = _stop_r[stop_count - 1]
		green = _stop_g[stop_count - 1]
		blue = _stop_b[stop_count - 1]
	else:
		red = _stop_r[0]
		green = _stop_g[0]
		blue = _stop_b[0]
		for index in range(1, stop_count):
			if out_height < _stop_h[index]:
				var t := (out_height - _stop_h[index - 1]) \
					/ (_stop_h[index] - _stop_h[index - 1])
				red = lerpf(_stop_r[index - 1], _stop_r[index], t)
				green = lerpf(_stop_g[index - 1], _stop_g[index], t)
				blue = lerpf(_stop_b[index - 1], _stop_b[index], t)
				break
			red = _stop_r[index]
			green = _stop_g[index]
			blue = _stop_b[index]
	if paint_mix > 0.0:
		red = lerpf(red, paint_red, paint_mix)
		green = lerpf(green, paint_green, paint_mix)
		blue = lerpf(blue, paint_blue, paint_mix)
	out_color = Color(red, green, blue)


func height(p: Vector2) -> float:
	sample_into(p.x, p.y)
	return out_height


## Edge-carry weight at a plan point — the skirt reads this to bulge lips
## outward exactly where a carried lobe crosses the rim.
func carry_at(p: Vector2) -> float:
	var carry := 0.0
	for index in _count:
		var op_carry := _carry[index]
		if op_carry <= 0.0:
			continue
		var weight := _weight_of(index, p.x, p.y)
		var carried := weight * op_carry
		if carried > carry:
			carry = carried
	return clampf(carry, 0.0, 1.0)


## Signed inset from the rounded-rect plan outline (>= 0 inside, 0 at rim).
func boundary_inset_xy(px: float, py: float) -> float:
	var qx := absf(px) - (HALF - corner_radius)
	var qy := absf(py) - (HALF - corner_radius)
	var outside := sqrt(maxf(qx, 0.0) * maxf(qx, 0.0)
		+ maxf(qy, 0.0) * maxf(qy, 0.0))
	return -(outside + minf(maxf(qx, qy), 0.0) - corner_radius)


func boundary_inset(p: Vector2) -> float:
	return boundary_inset_xy(p.x, p.y)


## Pulls a point outside the rounded plan back onto the outline (grid corner
## clipping). Interior points return unchanged.
func clip_to_plan(p: Vector2) -> Vector2:
	var inner := HALF - corner_radius
	var q := Vector2(absf(p.x) - inner, absf(p.y) - inner)
	if q.x <= 0.0 or q.y <= 0.0:
		return p
	var excess := q.length() - corner_radius
	if excess <= 0.0:
		return p
	var pull := q.normalized() * excess
	return Vector2(p.x - signf(p.x) * pull.x, p.y - signf(p.y) * pull.y)


func _height_up_to(op_limit: int, px: float, py: float) -> float:
	# Partial-stack evaluation used only during prepare(); reuses the merge
	# logic of sample_into for ops [0, op_limit) with rim easing bypassed.
	var saved := _count
	_count = op_limit
	_skip_edge = true
	sample_into(px, py)
	_skip_edge = false
	_count = saved
	return out_height


func _weight_of(index: int, px: float, py: float) -> float:
	var dx := px - _atx[index]
	var dy := py - _aty[index]
	var c := _cosy[index]
	var s := _siny[index]
	var lx := dx * c + dy * s
	var ly := -dx * s + dy * c
	var base := index * STRIDE
	match _kind[index]:
		KIND_DOME:
			var rx := _p[base + 0]
			var rz := _p[base + 1]
			var scallop := _p[base + 5]
			var factor := 1.0
			if scallop > 0.0:
				var angle := atan2(ly / rz, lx / rx)
				factor = 1.0 + scallop * (
					0.62 * sin(angle * _p[base + 6] + _p[base + 8])
					+ 0.38 * sin(angle * _p[base + 7] + _p[base + 9]))
				factor = maxf(factor, 0.15)
			var sx := lx / (rx * factor)
			var sz := ly / (rz * factor)
			var dist := sqrt(sx * sx + sz * sz)
			if dist >= 1.0:
				return 0.0
			return pow(maxf(0.0, 1.0 - pow(dist, _p[base + 3])), _p[base + 4])
		KIND_RIDGE:
			var length := _p[base + 0]
			var along_t := absf(lx) / length
			if along_t >= 1.55:
				return 0.0
			var across := ly - _p[base + 4] * lx * lx / length
			var width := lerpf(_p[base + 1], _p[base + 2],
				smoothstep(-0.06, 0.06, across))
			return exp(-pow(absf(across) / width, _p[base + 5])
				- pow(along_t, _p[base + 6]))
		KIND_PLATEAU:
			var corner := _p[base + 2]
			var qx := absf(lx) - (_p[base + 0] - corner)
			var qy := absf(ly) - (_p[base + 1] - corner)
			var outside := sqrt(
				maxf(qx, 0.0) * maxf(qx, 0.0) + maxf(qy, 0.0) * maxf(qy, 0.0))
			var sd := outside + minf(maxf(qx, qy), 0.0) - corner
			if sd >= 0.0:
				return 0.0
			var t := clampf(-sd / _p[base + 3], 0.0, 1.0)
			return t * t * (3.0 - 2.0 * t)
	return 0.0
