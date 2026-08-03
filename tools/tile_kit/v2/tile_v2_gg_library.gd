class_name TileV2GGLibrary
extends RefCounted
## The five GG-reboot compositions — ROUND 10 rules (see
## docs/TILE_ART_V2_DIRECTION.md): thick flared pieces (height ≥ 0.35 of
## plan width), ≥85% coverage, two piece layers, differing bodies, pieces
## crossing the rim on several tiles. Dense handcrafted terrain, never
## plates on an empty block.

const F := preload("res://tools/tile_kit/v2/tile_v2_field.gd")
const P := preload("res://tools/tile_kit/v2/tile_v2_palette.gd")


static func compose_gg(family: String, recipe: TileV2Recipe,
		rng: RandomNumberGenerator) -> Dictionary:
	match family:
		"forest_floor":
			return _forest(recipe, rng)
		"sand_dune":
			return _sand(recipe, rng)
		"snow_cap":
			return _snow(recipe, rng)
		"rock_slabs":
			return _rock(recipe, rng)
	return _moss(recipe, rng)


static func _bed(corner: float, rim: float, stops: Array, undulation: float,
		rng: RandomNumberGenerator) -> TileV2Field:
	var field := TileV2Field.new()
	field.corner_radius = corner
	field.rim_level = rim
	field.edge_band = 0.11
	field.floor_min = -0.02
	var resolved: Array = []
	for pair: Array in stops:
		resolved.append([float(pair[0]), P.color(String(pair[1]))])
	field.color_stops = resolved
	field.ops.append({"kind": F.KIND_SWELL, "merge": F.MERGE_ADD,
		"at": Vector2(-0.14, 0.10), "yaw": 0.0, "rx": 0.85, "rz": 0.78,
		"height": undulation})
	field.ops.append({"kind": F.KIND_BREAKUP, "merge": F.MERGE_ADD,
		"at": Vector2.ZERO, "yaw": 0.0, "height": undulation * 0.14,
		"frequency": 1.8, "phase": rng.randf_range(0.0, TAU)})
	return field


static func _slab(at: Vector2, yaw: float, spec: Dictionary) -> Dictionary:
	return {"type": "gg_slab", "at": at, "yaw": yaw, "spec": spec}


static func _tone(rng: RandomNumberGenerator, keys: Array) -> Color:
	var color: Color = P.color(String(keys[rng.randi() % keys.size()]))
	var jitter := rng.randf_range(-0.04, 0.04)
	return color.lightened(jitter) if jitter > 0.0 else color.darkened(-jitter)


## FOREST: full two-layer bark terrain — a packed grid of THICK chunks with
## a second tilted layer on top; two chunks poke past the rim.
static func _forest(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var field := _bed(0.10, 0.016, [
		[-0.010, "forest_soil_shadow"], [0.028, "forest_soil"]], 0.026, rng)
	var tones := ["forest_bark", "forest_bark_light", "forest_bark_deep"]
	var pieces: Array[Dictionary] = []
	# Layer 1: 4×4 packed chunks covering the whole top (touching).
	for row in 4:
		for column in 4:
			var at := Vector2(-0.60 + column * 0.40 + (0.10 if row % 2 == 1 else 0.0),
				-0.60 + row * 0.40) + Vector2(
				rng.randf_range(-0.04, 0.04), rng.randf_range(-0.04, 0.04))
			pieces.append(_slab(at, rng.randf_range(0.0, TAU), {
				"sides": 6,
				"rx": rng.randf_range(0.20, 0.25),
				"rz": rng.randf_range(0.15, 0.19),
				"height": rng.randf_range(0.085, 0.115),
				"bevel": 0.016, "crown": 0.014, "flare": 0.12,
				"tilt": rng.randf_range(-0.06, 0.06),
				"sink": 0.34, "clip": true,
				"tone": _tone(rng, tones),
			}))
	# Layer 2: seven smaller chunks stacked on the field, tilted; the two
	# marked ones sit at the rim and cross it (clip off).
	var layer2 := [
		[Vector2(-0.38, -0.30), false], [Vector2(0.10, -0.42), false],
		[Vector2(-0.16, 0.10), false], [Vector2(0.34, 0.26), false],
		[Vector2(-0.48, 0.44), false], [Vector2(0.82, -0.10), true],
		[Vector2(-0.20, -0.84), true],
	]
	for entry: Array in layer2:
		pieces.append(_slab(
			(entry[0] as Vector2) + Vector2(
				rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03)),
			rng.randf_range(0.0, TAU), {
				"sides": 5,
				"rx": rng.randf_range(0.14, 0.18),
				"rz": rng.randf_range(0.10, 0.13),
				"height": rng.randf_range(0.070, 0.095),
				"bevel": 0.014, "crown": 0.012, "flare": 0.10,
				"tilt": rng.randf_range(-0.12, 0.12),
				"sink": 0.10, "lift": rng.randf_range(0.050, 0.075),
				"clip": not bool(entry[1]),
				"tone": _tone(rng, tones),
			}))
	return {"field": field, "body": {
		"chamfer": 0.016, "lower_key": "forest_deep", "side_key": "forest_side",
		"upper_rings": [
			{"t": 0.55, "out": -0.004, "key": "forest_side"},
			{"t": 0.90, "out": 0.004, "key": "forest_side"},
			{"t": 0.97, "out": 0.006, "key": "forest_soil"},
		]}, "pieces": pieces, "allow_mirror": true}


## SAND: the whole top is four THICK overlapping terraces stepping down the
## diagonal, running over the far rim — layered dune terrain, strata sides.
static func _sand(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var field := _bed(0.13, 0.020, [
		[0.002, "sand_shadow"], [0.06, "sand_top"]], 0.024, rng)
	var pieces: Array[Dictionary] = []
	var shelves := [
		# [at, rx, rz, height, slope, clip, tone]
		[Vector2(0.30, 0.30), 0.72, 0.62, 0.070, Vector2(0.045, 0.030), true, "sand_top"],
		[Vector2(-0.10, -0.06), 0.66, 0.56, 0.125, Vector2(0.040, 0.045), true, "sand_top"],
		[Vector2(-0.42, -0.44), 0.55, 0.48, 0.185, Vector2(0.030, 0.035), false, "sand_high"],
		[Vector2(0.44, -0.34), 0.34, 0.28, 0.095, Vector2(-0.025, 0.030), true, "sand_high"],
	]
	for shelf: Array in shelves:
		pieces.append(_slab(
			(shelf[0] as Vector2) + Vector2(
				rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03)),
			rng.randf_range(-0.12, 0.12), {
				"sides": 8,
				"rx": shelf[1], "rz": shelf[2],
				"height": shelf[3], "bevel": 0.030,
				"slope": shelf[4], "crown": 0.010, "flare": 0.08,
				"sink": 0.08, "clip": bool(shelf[5]),
				"tone": P.color(String(shelf[6])),
			}))
	return {"field": field, "body": {
		"chamfer": 0.018, "lower_key": "sand_deep", "side_key": "sand_side",
		"upper_rings": [
			{"t": 0.30, "out": -0.004, "key": "sand_deep"},
			{"t": 0.55, "out": 0.002, "key": "sand_side"},
			{"t": 0.80, "out": -0.002, "key": "sand_side"},
			{"t": 0.95, "out": 0.006, "key": "sand_top"},
		]}, "pieces": pieces, "allow_mirror": true}


## SNOW: five THICK joined snow masses burying the whole top, two crossing
## the rim — sculpted terrain thickness over a dark body with a white
## fascia band.
static func _snow(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var field := _bed(0.12, 0.022, [
		[0.010, "snow_shadow"], [0.05, "snow_top"]], 0.020, rng)
	var snow := P.color("snow_top")
	var pieces: Array[Dictionary] = []
	var sections := [
		# [at, rx, rz, height, clip]
		[Vector2(-0.30, -0.24), 0.52, 0.46, 0.150, true],
		[Vector2(0.34, 0.10), 0.46, 0.40, 0.120, true],
		[Vector2(-0.10, 0.44), 0.42, 0.35, 0.100, true],
		[Vector2(0.52, -0.52), 0.34, 0.28, 0.085, false],
		[Vector2(-0.78, 0.30), 0.30, 0.26, 0.080, false],
	]
	for section: Array in sections:
		pieces.append(_slab(
			(section[0] as Vector2) + Vector2(
				rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03)),
			rng.randf_range(0.0, TAU), {
				"sides": 7,
				"rx": section[1], "rz": section[2],
				"height": section[3], "bevel": 0.050,
				"crown": 0.022, "flare": 0.12,
				"slope": Vector2(rng.randf_range(-0.03, 0.03),
					rng.randf_range(-0.03, 0.03)),
				"sink": 0.12, "clip": bool(section[4]),
				"tone": snow,
			}))
	return {"field": field, "body": {
		"chamfer": 0.016, "lower_key": "snow_body_deep", "side_key": "snow_body",
		"upper_rings": [
			{"t": 0.30, "out": -0.004, "key": "snow_body"},
			{"t": 0.58, "out": -0.002, "key": "snow_body"},
			{"t": 0.72, "out": 0.014, "key": "snow_shadow"},
			{"t": 0.94, "out": 0.016, "key": "snow_top"},
		]}, "pieces": pieces, "allow_mirror": true}


## ROCK: seven THICK fitted stones, touching, varied heights, deep seams,
## heavy battered foundation.
static func _rock(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var field := _bed(0.075, 0.018, [[0.0, "rock_groove"]], 0.014, rng)
	field.ops.append({"kind": F.KIND_RAMP, "merge": F.MERGE_ADD,
		"at": Vector2.ZERO, "yaw": deg_to_rad(32.0), "run": 1.5, "height": 0.020})
	var tones := ["rock_slab", "rock_slab_light", "rock_slab_warm"]
	var pieces: Array[Dictionary] = []
	var stones := [
		[Vector2(-0.46, -0.44), 0.42, 0.34, 0.115],
		[Vector2(0.36, -0.48), 0.40, 0.31, 0.095],
		[Vector2(-0.50, 0.30), 0.34, 0.38, 0.105],
		[Vector2(0.12, 0.06), 0.38, 0.33, 0.130],
		[Vector2(0.58, 0.46), 0.35, 0.36, 0.100],
		[Vector2(-0.10, 0.62), 0.32, 0.27, 0.090],
		[Vector2(0.64, -0.06), 0.26, 0.30, 0.085],
	]
	for stone: Array in stones:
		pieces.append(_slab(
			(stone[0] as Vector2) + Vector2(
				rng.randf_range(-0.012, 0.012), rng.randf_range(-0.012, 0.012)),
			rng.randf_range(-0.05, 0.05), {
				"sides": 7,
				"rx": stone[1], "rz": stone[2],
				"height": float(stone[3]) * rng.randf_range(0.97, 1.03),
				"bevel": 0.018, "crown": 0.014, "flare": 0.09,
				"radii": [1.0, 0.96, 1.03, 0.98, 1.02, 0.97, 1.0],
				"sink": 0.16, "clip": true,
				"tone": _tone(rng, tones),
			}))
	return {"field": field, "body": {
		"chamfer": 0.020, "lower_key": "rock_deep", "side_key": "rock_side",
		"upper_rings": [
			{"t": 0.08, "out": 0.010, "key": "rock_deep"},
			{"t": 0.40, "out": 0.000, "key": "rock_deep"},
			{"t": 0.86, "out": 0.004, "key": "rock_side"},
			{"t": 0.955, "out": 0.008, "key": "rock_groove"},
		]}, "pieces": pieces, "allow_mirror": true}


## MOSS: six big chunky floret clumps burying ~85% of the top, one crossing
## the rim; earth shows only in the channel between clump groups.
static func _moss(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var field := _bed(0.11, 0.014, [
		[-0.008, "moss_deep"], [0.020, "moss_substrate"]], 0.022, rng)
	var pieces: Array[Dictionary] = []
	var clumps := [
		# [anchor, tone, bump count, spread]
		[Vector2(-0.38, -0.28), "moss_top", 11, 0.30],
		[Vector2(0.10, -0.48), "moss_light", 8, 0.24],
		[Vector2(-0.60, 0.22), "moss_shadow", 8, 0.24],
		[Vector2(0.44, 0.34), "moss_top", 10, 0.28],
		[Vector2(0.66, -0.16), "moss_light", 6, 0.20],
		[Vector2(-0.14, 0.66), "moss_top", 7, 0.22],
	]
	for clump: Array in clumps:
		var bumps: Array = []
		var count: int = clump[2]
		var spread: float = clump[3]
		for index in count:
			var angle := TAU * float(index) / float(count) \
				+ rng.randf_range(-0.4, 0.4)
			var reach := spread * sqrt(rng.randf_range(0.05, 1.0))
			bumps.append([
				Vector2(cos(angle) * reach, sin(angle) * reach * 0.85),
				rng.randf_range(0.105, 0.185),
				rng.randf_range(0.100, 0.155),
			])
		pieces.append({"type": "gg_tufts",
			"at": (clump[0] as Vector2) + Vector2(
				rng.randf_range(-0.025, 0.025), rng.randf_range(-0.025, 0.025)),
			"yaw": rng.randf_range(0.0, TAU), "tone": String(clump[1]),
			"bumps": bumps})
	return {"field": field, "body": {
		"chamfer": 0.016, "lower_key": "forest_deep", "side_key": "moss_side",
		"upper_rings": [
			{"t": 0.50, "out": -0.004, "key": "moss_side"},
			{"t": 0.82, "out": 0.003, "key": "moss_substrate"},
			{"t": 0.95, "out": 0.010, "key": "moss_top"},
		]}, "pieces": pieces, "allow_mirror": true}
