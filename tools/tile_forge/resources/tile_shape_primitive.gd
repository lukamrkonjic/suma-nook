@tool
class_name TileShapePrimitive
extends Resource
## One analytic macro form. These are the ONLY source of organic tile shape.
##
## The Forge deliberately has no fractal-noise displacement path: broad
## overlapping primitives produce forms a person can reason about and revise,
## and they never degrade into the high-frequency fuzz the art direction bans.
## If a surface looks noisy, the fix is fewer, larger primitives — not a
## smoother noise octave.
##
## Coordinate space is normalized tile space: u and v run -1..1, where ±1 is
## exactly the tile boundary. That keeps a primitive independent of tile size
## and of the heightfield resolution it is sampled at.

@export var shape: TileForgeConstants.Shape = TileForgeConstants.Shape.BROAD_MOUND

@export_group("Placement")
## Centre in normalized tile space (-1..1 on both axes).
@export var center := Vector2.ZERO
## Half-size of the form in normalized tile space. X is the local long axis
## for directional shapes (RIDGE, WAVE, DRIFT, TRENCH, STEP).
@export var extents := Vector2(0.7, 0.7)
## Rotation of the local frame, degrees, around +Y.
@export_range(-180.0, 180.0, 0.5) var rotation_deg := 0.0

@export_group("Amplitude")
## Peak height contribution in METRES. Positive raises, negative lowers.
## Keep organic terrain inside roughly ±0.05 m: the reference silhouette is a
## crisp block with a gently modulated top, not a lumpy pillow.
@export var height := 0.03

@export_group("Profile")
@export var falloff: TileForgeConstants.Falloff = TileForgeConstants.Falloff.SMOOTHSTEP
## 0 = crisp shoulder, 1 = very soft, wide shoulder.
@export_range(0.0, 1.0, 0.01) var softness := 0.5
## Widens one side of a directional form and steepens the other. This is what
## makes a DRIFT read as a wind-formed dune rather than a symmetric bump.
@export_range(-1.0, 1.0, 0.01) var asymmetry := 0.0
## For WAVE: number of full waves across the form's X extent.
@export_range(0.25, 6.0, 0.05) var frequency := 1.5
## For WAVE: phase offset in turns.
@export_range(0.0, 1.0, 0.01) var phase := 0.0
## Scales this primitive's influence where a layer mask is active.
@export_range(0.0, 1.0, 0.01) var mask_influence := 1.0


## Height contribution in metres at normalized tile coordinate (u, v).
func evaluate(u: float, v: float) -> float:
	return height * weight(u, v)


## Normalized influence in 0..1 (or -1..1 for WAVE). Detail placement and
## masking use this without caring about the amplitude.
func weight(u: float, v: float) -> float:
	var local := _to_local(u, v)
	match shape:
		TileForgeConstants.Shape.MOUND:
			return _radial(local, 1.0)
		TileForgeConstants.Shape.BROAD_MOUND:
			# Flatter crown, wider shoulder: the workhorse for "gently uneven".
			return _radial(local, 0.55)
		TileForgeConstants.Shape.PLATEAU:
			return _radial(local, 0.22)
		TileForgeConstants.Shape.BOWL:
			return -_radial(local, 1.0)
		TileForgeConstants.Shape.DEPRESSION:
			return -_radial(local, 0.55)
		TileForgeConstants.Shape.RIDGE:
			return _directional(local)
		TileForgeConstants.Shape.TRENCH:
			return -_directional(local)
		TileForgeConstants.Shape.DRIFT:
			return _drift(local)
		TileForgeConstants.Shape.WAVE:
			return _wave(local)
		TileForgeConstants.Shape.STEP:
			return _step(local)
		TileForgeConstants.Shape.CORNER_RISE:
			return _corner(local)
		TileForgeConstants.Shape.EDGE_RISE:
			return _edge(local)
		TileForgeConstants.Shape.FLATTEN_REGION:
			return _radial(local, 0.3)
	return 0.0


func _to_local(u: float, v: float) -> Vector2:
	var offset := Vector2(u, v) - center
	if not is_zero_approx(rotation_deg):
		offset = offset.rotated(-deg_to_rad(rotation_deg))
	var sx: float = maxf(0.0001, extents.x)
	var sy: float = maxf(0.0001, extents.y)
	return Vector2(offset.x / sx, offset.y / sy)


## `crown` shrinks the flat top: 1.0 is a pure dome, 0.2 is a mesa.
func _radial(local: Vector2, crown: float) -> float:
	var distance := local.length()
	if distance >= 1.0:
		return 0.0
	var inner: float = clampf(1.0 - crown, 0.0, 0.94)
	if distance <= inner:
		return 1.0
	var t := (distance - inner) / maxf(0.0001, 1.0 - inner)
	return _shoulder(1.0 - t)


func _directional(local: Vector2) -> float:
	var along: float = absf(local.x)
	if along >= 1.0:
		return 0.0
	var across := local.y
	# Asymmetry biases the crest off-centre across the ridge.
	var skew: float = clampf(asymmetry, -0.85, 0.85)
	var shifted := (across - skew) / maxf(0.15, 1.0 - absf(skew))
	if absf(shifted) >= 1.0:
		return 0.0
	var cross_profile := _shoulder(1.0 - absf(shifted))
	# Ends taper so a ridge does not stop abruptly mid-tile.
	var end_profile := _shoulder(1.0 - along * along)
	return cross_profile * end_profile


## A dune: short windward rise, long leeward tail, crest pushed off-centre.
func _drift(local: Vector2) -> float:
	var across := local.y
	if absf(across) >= 1.0:
		return 0.0
	var crest: float = clampf(asymmetry * 0.55, -0.6, 0.6)
	var t := across - crest
	var span: float = (1.0 - crest) if t >= 0.0 else (1.0 + crest)
	var normalized: float = clampf(absf(t) / maxf(0.15, span), 0.0, 1.0)
	# Windward side falls off with a squarer profile than the leeward tail.
	var profile: float = (
		_shoulder(1.0 - normalized)
		if t >= 0.0
		else _shoulder(1.0 - normalized * normalized)
	)
	var along: float = absf(local.x)
	var end_profile: float = _shoulder(1.0 - clampf(along * along, 0.0, 1.0))
	return profile * end_profile


func _wave(local: Vector2) -> float:
	var along: float = absf(local.x)
	var across: float = absf(local.y)
	if along >= 1.0 or across >= 1.0:
		return 0.0
	var envelope := _shoulder(1.0 - along) * _shoulder(1.0 - across)
	var angle := TAU * (local.x * 0.5 * frequency + phase)
	return sin(angle) * envelope


func _step(local: Vector2) -> float:
	var width: float = maxf(0.05, softness)
	var t: float = clampf((local.x + width) / (2.0 * width), 0.0, 1.0)
	var across: float = absf(local.y)
	if across >= 1.0:
		return 0.0
	return smoothstep(0.0, 1.0, t) * _shoulder(1.0 - across)


func _corner(local: Vector2) -> float:
	var d: float = clampf(local.length(), 0.0, 1.0)
	return _shoulder(1.0 - d)


func _edge(local: Vector2) -> float:
	var across: float = clampf(absf(local.y), 0.0, 1.0)
	var along: float = absf(local.x)
	if along >= 1.0:
		return 0.0
	return _shoulder(1.0 - across) * _shoulder(1.0 - along * along)


## Shared shoulder curve. `t` is 1 at the centre of the form and 0 at its rim.
func _shoulder(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	match falloff:
		TileForgeConstants.Falloff.LINEAR:
			return x
		TileForgeConstants.Falloff.GAUSSIAN:
			var sharpness: float = lerpf(6.0, 1.6, softness)
			return exp(-sharpness * (1.0 - x) * (1.0 - x))
		TileForgeConstants.Falloff.COSINE:
			return 0.5 - 0.5 * cos(PI * x)
		TileForgeConstants.Falloff.PLATEAU_EDGE:
			var knee: float = lerpf(0.15, 0.6, softness)
			return smoothstep(0.0, knee, x)
		_:
			# SMOOTHSTEP, softened towards a wider shoulder.
			var eased := smoothstep(0.0, 1.0, x)
			return lerpf(eased, smoothstep(0.0, 1.0, eased), softness)


static func make(
	shape_type: TileForgeConstants.Shape,
	center_uv: Vector2,
	extents_uv: Vector2,
	height_m: float
) -> TileShapePrimitive:
	var primitive := TileShapePrimitive.new()
	primitive.shape = shape_type
	primitive.center = center_uv
	primitive.extents = extents_uv
	primitive.height = height_m
	return primitive
