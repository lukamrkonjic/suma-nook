class_name TileV2GGLibrary
extends RefCounted
## The five GG-reboot compositions (docs/TILE_ART_V2_DIRECTION.md).
## Manually authored piece assemblies: chunky layered geometry, multiple
## height levels, medium-piece density, per-material bodies. No spheres,
## no central mounds, no scatter.

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


## FOREST: two overlapping sheets of angular bark slabs over dark soil —
## the litter is layered INTO the tile; soil shows along one clear band.
static func _forest(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var field := _bed(0.10, 0.018, [
		[-0.010, "forest_soil_shadow"], [0.028, "forest_soil"]], 0.028, rng)
	var tones := ["forest_bark", "forest_bark_light", "forest_bark_deep",
		"forest_bark", "forest_bark_light"]
	var pieces: Array[Dictionary] = []
	# Sheet 1 — big grounded slabs covering an L (soil band stays clear
	# along the (+x,−z) diagonal corner).
	var sheet1 := [
		[Vector2(-0.55, -0.50), 0.20, 0.14, -0.4], [Vector2(-0.14, -0.52), 0.18, 0.13, 0.5],
		[Vector2(-0.56, -0.06), 0.19, 0.14, 0.2], [Vector2(-0.18, -0.12), 0.17, 0.12, -0.6],
		[Vector2(-0.52, 0.36), 0.18, 0.13, 0.7], [Vector2(-0.10, 0.30), 0.19, 0.13, -0.2],
		[Vector2(0.28, 0.48), 0.18, 0.13, 0.4], [Vector2(0.30, 0.10), 0.16, 0.12, -0.5],
		[Vector2(0.62, 0.40), 0.15, 0.11, 0.1],
	]
	for entry: Array in sheet1:
		pieces.append(_slab(
			entry[0] + Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03)),
			float(entry[3]) + rng.randf_range(-0.2, 0.2), {
				"sides": 6, "rx": entry[1], "rz": entry[2],
				"height": rng.randf_range(0.034, 0.046),
				"bevel": 0.011, "tilt": rng.randf_range(-0.07, 0.07),
				"sink": 0.28, "clip": true,
				"tone": P.color(tones[rng.randi() % tones.size()]),
			}))
	# Sheet 2 — smaller slabs stacked ON the first sheet, tilted more.
	var sheet2 := [
		[Vector2(-0.36, -0.32), 0.14, 0.10, 0.8], [Vector2(-0.30, 0.16), 0.13, 0.09, -0.4],
		[Vector2(0.06, -0.34), 0.13, 0.10, 0.3], [Vector2(0.12, 0.34), 0.12, 0.09, -0.7],
		[Vector2(-0.55, 0.55), 0.12, 0.09, 0.5], [Vector2(0.45, 0.28), 0.12, 0.09, 0.1],
	]
	for entry: Array in sheet2:
		pieces.append(_slab(
			entry[0] + Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03)),
			float(entry[3]) + rng.randf_range(-0.3, 0.3), {
				"sides": 5, "rx": entry[1], "rz": entry[2],
				"height": rng.randf_range(0.028, 0.038),
				"bevel": 0.010, "tilt": rng.randf_range(-0.13, 0.13),
				"sink": 0.0, "lift": rng.randf_range(0.024, 0.038),
				"clip": true,
				"tone": P.color(tones[rng.randi() % tones.size()]),
			}))
	return {"field": field, "body": {
		"chamfer": 0.016, "lower_key": "forest_deep", "side_key": "forest_side",
		"upper_rings": [
			{"t": 0.55, "out": -0.004, "key": "forest_side"},
			{"t": 0.90, "out": 0.004, "key": "forest_side"},
			{"t": 0.97, "out": 0.006, "key": "forest_soil"},
		]}, "pieces": pieces, "allow_mirror": true}


## SAND: four broad terraced wedges cut flush at the rim — connected
## sloped planes stepping down across the tile, layered ochre sides.
static func _sand(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var field := _bed(0.13, 0.024, [
		[0.002, "sand_shadow"], [0.06, "sand_top"]], 0.026, rng)
	var sand_top := P.color("sand_top")
	var sand_high := P.color("sand_high")
	var pieces: Array[Dictionary] = []
	var shelves := [
		# [at, rx, rz, height, slope, tone]
		[Vector2(-0.30, -0.26), 0.54, 0.46, 0.042, Vector2(0.050, 0.028), sand_top],
		[Vector2(0.32, 0.08), 0.48, 0.40, 0.070, Vector2(-0.040, 0.055), sand_high],
		[Vector2(-0.12, 0.44), 0.40, 0.32, 0.098, Vector2(0.036, -0.048), sand_top],
		[Vector2(0.50, -0.42), 0.28, 0.22, 0.030, Vector2(-0.030, -0.020), sand_high],
	]
	for shelf: Array in shelves:
		pieces.append(_slab(
			shelf[0] + Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03)),
			rng.randf_range(-0.15, 0.15), {
				"sides": 8, "rx": shelf[1], "rz": shelf[2],
				"height": shelf[3], "bevel": 0.022,
				"slope": shelf[4], "crown": 0.004,
				"sink": 0.10, "clip": true, "tone": shelf[5],
			}))
	return {"field": field, "body": {
		"chamfer": 0.018, "lower_key": "sand_deep", "side_key": "sand_side",
		"upper_rings": [
			{"t": 0.34, "out": -0.004, "key": "sand_deep"},
			{"t": 0.60, "out": 0.000, "key": "sand_side"},
			{"t": 0.90, "out": 0.004, "key": "sand_side"},
			{"t": 0.97, "out": 0.006, "key": "sand_top"},
		]}, "pieces": pieces, "allow_mirror": true}


## SNOW: four chunky joined snow sections cut at the rim — a thick cap
## with uneven inner seams and broad height changes over a dark body.
static func _snow(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var field := _bed(0.12, 0.026, [
		[0.010, "snow_shadow"], [0.05, "snow_top"]], 0.022, rng)
	var snow := P.color("snow_top")
	var pieces: Array[Dictionary] = []
	var sections := [
		[Vector2(-0.28, -0.22), 0.48, 0.42, 0.105, Vector2(0.020, 0.030)],
		[Vector2(0.32, 0.14), 0.42, 0.36, 0.085, Vector2(-0.030, 0.024)],
		[Vector2(-0.14, 0.42), 0.36, 0.30, 0.070, Vector2(0.026, -0.030)],
		[Vector2(0.44, -0.38), 0.27, 0.23, 0.055, Vector2(-0.020, -0.018)],
	]
	for section: Array in sections:
		pieces.append(_slab(
			section[0] + Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.03, 0.03)),
			rng.randf_range(0.0, TAU), {
				"sides": 7, "rx": section[1], "rz": section[2],
				"height": section[3], "bevel": 0.030,
				"slope": section[4], "crown": 0.010,
				"sink": 0.14, "clip": true, "tone": snow,
			}))
	return {"field": field, "body": {
		"chamfer": 0.016, "lower_key": "snow_body_deep", "side_key": "snow_body",
		"upper_rings": [
			{"t": 0.34, "out": -0.004, "key": "snow_body"},
			{"t": 0.62, "out": -0.002, "key": "snow_body"},
			{"t": 0.78, "out": 0.012, "key": "snow_shadow"},
			{"t": 0.95, "out": 0.014, "key": "snow_top"},
		]}, "pieces": pieces, "allow_mirror": true}


## ROCK: six fitted stones, varied heights, deep seams, tight bevels.
static func _rock(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var field := _bed(0.075, 0.020, [[0.0, "rock_groove"]], 0.016, rng)
	field.ops.append({"kind": F.KIND_RAMP, "merge": F.MERGE_ADD,
		"at": Vector2.ZERO, "yaw": deg_to_rad(32.0), "run": 1.5, "height": 0.022})
	var tones := ["rock_slab", "rock_slab_light", "rock_slab_warm"]
	var pieces: Array[Dictionary] = []
	var stones := [
		[Vector2(-0.47, -0.45), 0.40, 0.32, 0.02, 0, 0.070],
		[Vector2(0.36, -0.50), 0.38, 0.29, -0.04, 1, 0.058],
		[Vector2(-0.50, 0.32), 0.32, 0.36, -0.02, 2, 0.064],
		[Vector2(0.14, 0.08), 0.36, 0.31, 0.05, 0, 0.075],
		[Vector2(0.58, 0.50), 0.33, 0.34, -0.03, 1, 0.060],
		[Vector2(-0.12, 0.62), 0.30, 0.26, 0.04, 2, 0.055],
	]
	for stone: Array in stones:
		pieces.append(_slab(
			stone[0] + Vector2(rng.randf_range(-0.015, 0.015), rng.randf_range(-0.015, 0.015)),
			float(stone[3]) + rng.randf_range(-0.03, 0.03), {
				"sides": 7, "rx": stone[1], "rz": stone[2],
				"height": float(stone[5]) * rng.randf_range(0.96, 1.04),
				"bevel": 0.012, "crown": 0.006,
				"radii": [1.0, 0.97, 1.02, 0.99, 1.01, 0.98, 1.0],
				"sink": 0.08, "clip": true,
				"tone": P.color(tones[int(stone[4])]),
			}))
	return {"field": field, "body": {
		"chamfer": 0.020, "lower_key": "rock_deep", "side_key": "rock_side",
		"upper_rings": [
			{"t": 0.35, "out": -0.004, "key": "rock_deep"},
			{"t": 0.86, "out": 0.005, "key": "rock_side"},
			{"t": 0.955, "out": 0.008, "key": "rock_groove"},
		]}, "pieces": pieces, "allow_mirror": true}


## MOSS: five authored tuft clumps — dense connected florets in two
## grouped regions with earth visible between, green overlapping the edge.
static func _moss(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var field := _bed(0.11, 0.015, [
		[-0.008, "moss_deep"], [0.020, "moss_substrate"]], 0.024, rng)
	var pieces: Array[Dictionary] = []
	# [anchor, tone, bump list [offset, r, h]]
	var clumps := [
		[Vector2(-0.36, -0.26), "moss_top", [
			[Vector2(0.0, 0.0), 0.16, 0.085], [Vector2(0.20, -0.08), 0.13, 0.072],
			[Vector2(-0.18, 0.12), 0.14, 0.078], [Vector2(0.04, 0.20), 0.12, 0.066],
			[Vector2(-0.22, -0.14), 0.12, 0.062], [Vector2(0.16, 0.14), 0.10, 0.055],
		]],
		[Vector2(0.06, -0.48), "moss_light", [
			[Vector2(0.0, 0.0), 0.14, 0.070], [Vector2(0.18, 0.05), 0.11, 0.058],
			[Vector2(-0.16, 0.02), 0.11, 0.060], [Vector2(0.02, 0.14), 0.10, 0.050],
		]],
		[Vector2(-0.58, 0.16), "moss_shadow", [
			[Vector2(0.0, 0.0), 0.13, 0.065], [Vector2(0.13, 0.11), 0.11, 0.056],
			[Vector2(-0.06, 0.16), 0.10, 0.050], [Vector2(0.08, -0.12), 0.10, 0.052],
		]],
		[Vector2(0.46, 0.36), "moss_top", [
			[Vector2(0.0, 0.0), 0.15, 0.078], [Vector2(0.17, -0.10), 0.12, 0.064],
			[Vector2(-0.14, 0.11), 0.12, 0.062], [Vector2(0.05, 0.17), 0.11, 0.056],
			[Vector2(-0.12, -0.13), 0.10, 0.052],
		]],
		[Vector2(0.60, -0.10), "moss_light", [
			[Vector2(0.0, 0.0), 0.12, 0.060], [Vector2(0.10, 0.13), 0.10, 0.050],
			[Vector2(-0.04, -0.14), 0.09, 0.046],
		]],
	]
	for clump: Array in clumps:
		var anchor: Vector2 = clump[0] + Vector2(
			rng.randf_range(-0.025, 0.025), rng.randf_range(-0.025, 0.025))
		pieces.append({"type": "gg_tufts", "at": anchor,
			"yaw": rng.randf_range(0.0, TAU), "tone": String(clump[1]),
			"bumps": clump[2]})
	return {"field": field, "body": {
		"chamfer": 0.016, "lower_key": "forest_deep", "side_key": "moss_side",
		"upper_rings": [
			{"t": 0.50, "out": -0.004, "key": "moss_side"},
			{"t": 0.82, "out": 0.003, "key": "moss_substrate"},
			{"t": 0.95, "out": 0.010, "key": "moss_top"},
		]}, "pieces": pieces, "allow_mirror": true}
