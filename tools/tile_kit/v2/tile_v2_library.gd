class_name TileV2Library
extends RefCounted
## The authored V2 prototypes — assembly construction, the GG method.
##
## A tile is a block BED (a low quiet sculpt field: colour ramp + a few
## broad centimetres of life) plus an ASSEMBLY of chunky solid pieces —
## stones, bark chunks, snow caps, sand strokes, moss cushions — packed by
## curated templates. The pieces carry the material identity: their
## silhouettes, per-piece tone variation, and baked contact shading are
## what read as the handcrafted miniature.
##
## Determinism: one RNG seeded with (family, seed, layout); a seed selects
## a layout and bounded jitter, never a new composition.

const F := preload("res://tools/tile_kit/v2/tile_v2_field.gd")
const P := preload("res://tools/tile_kit/v2/tile_v2_palette.gd")
const GG := preload("res://tools/tile_kit/v2/tile_v2_gg_library.gd")

const FAMILIES: Array[String] = [
	"forest_floor", "sand_dune", "snow_cap", "rock_slabs", "moss_cushion",
]

const PROTOTYPES := [
	["tile_v2_forest_floor", "Forest Floor", "forest_floor"],
	["tile_v2_sculpted_sand", "Sculpted Sand", "sand_dune"],
	["tile_v2_pillowy_snow", "Pillowy Snow", "snow_cap"],
	["tile_v2_rock_ground", "Rounded Rock Ground", "rock_slabs"],
	["tile_v2_moss_cushion", "Moss Cushion", "moss_cushion"],
]


static func prototype_ids() -> Array[String]:
	var result: Array[String] = []
	for entry: Array in PROTOTYPES:
		result.append(String(entry[0]))
	return result


static func recipe(tile_id: String) -> TileV2Recipe:
	for entry: Array in PROTOTYPES:
		if String(entry[0]) == tile_id:
			var result := TileV2Recipe.new()
			result.tile_id = tile_id
			result.display_name = String(entry[1])
			result.family = String(entry[2])
			result.seed = 20260803
			result.walk_surface_height = _walk_height(String(entry[2]))
			return result
	return null


static func _walk_height(family: String) -> float:
	match family:
		"snow_cap":
			return 0.10
		"moss_cushion":
			return 0.07
		"rock_slabs":
			return 0.06
		"sand_dune":
			return 0.06
	return 0.03


static func compose(recipe: TileV2Recipe) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("tilev2|%s|%d|%d" % [recipe.family, recipe.seed, recipe.layout])
	# The GG construction reboot owns all five compositions
	# (docs/TILE_ART_V2_DIRECTION.md); the composers below are retired.
	var composed: Dictionary = GG.compose_gg(recipe.family, recipe, rng)
	var field: TileV2Field = composed["field"]
	if bool(composed.get("allow_mirror", true)) and rng.randf() < 0.5:
		_mirror(field, composed["pieces"])
	field.prepare()
	return composed


# --- shared helpers ----------------------------------------------------------


static func _jit(rng: RandomNumberGenerator, at: Vector2, radius: float) -> Vector2:
	return at + Vector2(
		rng.randf_range(-radius, radius), rng.randf_range(-radius, radius))


static func _mirror(field: TileV2Field, pieces: Array) -> void:
	for op in field.ops:
		var at: Vector2 = op["at"]
		op["at"] = Vector2(-at.x, at.y)
		op["yaw"] = PI - float(op.get("yaw", 0.0))
		if op.has("curve"):
			op["curve"] = -float(op["curve"])
	for piece: Dictionary in pieces:
		if piece.has("at"):
			var at: Vector2 = piece["at"]
			piece["at"] = Vector2(-at.x, at.y)
			piece["yaw"] = PI - float(piece.get("yaw", 0.0))
		if piece.has("start"):
			var start: Vector2 = piece["start"]
			var end: Vector2 = piece["end"]
			piece["start"] = Vector2(-start.x, start.y)
			piece["end"] = Vector2(-end.x, end.y)
			piece["bow"] = -float(piece["bow"])


static func _breakup(height: float, frequency: float, phase: float) -> Dictionary:
	return {"kind": F.KIND_BREAKUP, "merge": F.MERGE_ADD, "at": Vector2.ZERO,
		"yaw": 0.0, "height": height, "frequency": frequency, "phase": phase}


static func _stops(pairs: Array) -> Array:
	var result: Array = []
	for pair: Array in pairs:
		result.append([float(pair[0]), P.color(String(pair[1]))])
	return result


## A quiet bed field: gentle undulation and a colour ramp, nothing else.
static func _bed(corner: float, rim: float, stops: Array,
		undulation: float, frequency: float,
		rng: RandomNumberGenerator) -> TileV2Field:
	var field := TileV2Field.new()
	field.corner_radius = corner
	field.rim_level = rim
	field.edge_band = 0.12
	field.floor_min = -0.02
	field.color_stops = _stops(stops)
	field.ops.append({"kind": F.KIND_SWELL, "merge": F.MERGE_ADD,
		"at": _jit(rng, Vector2(-0.15, 0.10), 0.08), "yaw": 0.0,
		"rx": 0.85, "rz": 0.78, "height": undulation})
	field.ops.append(_breakup(undulation * 0.16, frequency,
		rng.randf_range(0.0, TAU)))
	return field


# --- A. FOREST FLOOR (mulch litter) ------------------------------------------
## Dense chunky bark litter over dark soil — the GG mulch read: the litter
## IS the surface, chunky pieces packed edge to edge with soil showing in
## the gaps and one calmer pocket.


static func _compose_forest(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	# A perfectly smooth crowned soil block: one broad off-centre crown, one
	# whisper dish, the warm ramp — a polished toy piece of earth.
	var field := _bed(0.10, 0.020, [
		[-0.010, "forest_soil_shadow"],
		[0.026, "forest_soil"],
		[0.070, "forest_soil_light"],
	], 0.034, 1.6, rng)
	# Broad gentle undulations only — cosine swells have no rolled edge, so
	# nothing can ever read as a stamped disc.
	field.ops.append({"kind": F.KIND_SWELL, "merge": F.MERGE_ADD,
		"at": _jit(rng, Vector2(-0.24, 0.18), 0.05), "yaw": 0.0,
		"rx": 0.72, "rz": 0.62, "height": 0.045})
	field.ops.append({"kind": F.KIND_SWELL, "merge": F.MERGE_ADD,
		"at": _jit(rng, Vector2(0.38, -0.32), 0.05), "yaw": 0.0,
		"rx": 0.5, "rz": 0.44, "height": -0.016})
	return {"field": field, "body": _body("forest_deep", "forest_side",
		"forest_soil"), "pieces": [], "allow_mirror": true}


# --- B. SCULPTED SAND --------------------------------------------------------
## A warm sand block with a low broad rise and two or three crisp raised
## wind strokes sweeping the diagonal — the GG sand swoosh language: bold
## solid strokes with clean contact lines, not surface wrinkles.


static func _compose_sand(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var field := _bed(0.14, 0.026, [
		[0.002, "sand_shadow"],
		[0.050, "sand_top"],
		[0.110, "sand_high"],
	], 0.030, 1.4, rng)
	# The broad dune mass: low, wide, carried through the rim.
	var flow_yaw := deg_to_rad(-138.0) + rng.randf_range(-0.10, 0.10)
	field.ops.append({"kind": F.KIND_RAMP, "merge": F.MERGE_ADD,
		"at": Vector2.ZERO, "yaw": flow_yaw, "run": 1.9, "height": 0.045})
	field.ops.append({"kind": F.KIND_RIDGE, "merge": F.MERGE_MAX,
		"ride_surface": true, "at": _jit(rng, Vector2(0.04, 0.0), 0.05),
		"yaw": flow_yaw + PI * 0.5 + rng.randf_range(-0.08, 0.08),
		"length": 1.40, "width_windward": 0.52, "width_lee": 0.30,
		"height": 0.085, "curve": 0.26, "softness": 0.82, "blend": 0.06,
		"edge_carry": 0.95})

	# Nothing else: the tile is one perfect smooth wave of sand.
	return {"field": field, "body": _body("sand_deep", "sand_side",
		"sand_top"), "pieces": [], "allow_mirror": true}


# --- C. PILLOWY SNOW ---------------------------------------------------------
## A snow block carrying one hero cap solid with a REAL overhang, one
## secondary mound and one small shoulder — thick settled volumes, fused
## where they overlap, over a soft white bed.


static func _compose_snow(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var field := _bed(0.13, 0.030, [
		[0.012, "snow_shadow"],
		[0.055, "snow_top"],
	], 0.026, 1.2, rng)
	# Three broad flat-topped lobes overlapping into ONE fused pillowy mass
	# spanning the block — thick settled snow, never an egg in a tray.
	var pieces: Array[Dictionary] = []
	var lobes := [
		[Vector2(-0.24, -0.18), 0.66, 0.56, 0.130],
		[Vector2(0.34, 0.20), 0.55, 0.48, 0.110],
		[Vector2(-0.16, 0.42), 0.44, 0.38, 0.088],
	]
	for lobe: Array in lobes:
		pieces.append({
			"type": "solid",
			"at": _jit(rng, lobe[0], 0.03),
			"yaw": rng.randf_range(0.0, TAU),
			"spec": {
				"style": "cushion",
				"rx": float(lobe[1]) * rng.randf_range(0.97, 1.03),
				"rz": float(lobe[2]) * rng.randf_range(0.97, 1.03),
				"height": float(lobe[3]) * rng.randf_range(0.97, 1.03),
				"belly": 1.05,
				"scallop": 0.06,
				"points": 24,
				"top_scale": 0.74,
				"color": P.color("snow_top"),
				"color_top": P.color("snow_high"),
				"sink": 0.10,
			},
		})
	return {"field": field, "body": _body("snow_body_deep", "snow_body",
		"snow_top"), "pieces": pieces, "allow_mirror": true}


# --- D. ROUNDED ROCK GROUND --------------------------------------------------
## Six fitted stone SOLIDS set into a mortar bed: firm slightly-crowned
## faces, real gaps, edge stones cut flush at the tile boundary — fitted
## masonry, not scattered boulders.


static func _compose_rock(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var field := _bed(0.075, 0.022, [
		[0.0, "rock_groove"],
	], 0.018, 2.1, rng)
	# Terrace: one half a small step higher.
	field.ops.append({"kind": F.KIND_RAMP, "merge": F.MERGE_ADD,
		"at": Vector2.ZERO, "yaw": deg_to_rad(32.0) + rng.randf_range(-0.1, 0.1),
		"run": 1.5, "height": 0.026})

	var tones := ["rock_slab", "rock_slab_light", "rock_slab_warm"]
	var layouts := [
		[
			[Vector2(-0.47, -0.45), 0.40, 0.32, 0.02, 0],
			[Vector2(0.36, -0.50), 0.38, 0.29, -0.04, 1],
			[Vector2(-0.50, 0.32), 0.32, 0.36, -0.02, 2],
			[Vector2(0.14, 0.08), 0.36, 0.31, 0.05, 0],
			[Vector2(0.58, 0.50), 0.33, 0.34, -0.03, 1],
			[Vector2(-0.12, 0.62), 0.30, 0.26, 0.04, 2],
		],
		[
			[Vector2(-0.50, -0.18), 0.34, 0.38, -0.03, 1],
			[Vector2(0.22, -0.48), 0.40, 0.30, 0.04, 0],
			[Vector2(0.60, 0.18), 0.30, 0.35, 0.02, 2],
			[Vector2(-0.06, 0.22), 0.34, 0.32, -0.05, 0],
			[Vector2(-0.56, 0.56), 0.30, 0.28, 0.03, 1],
			[Vector2(0.38, 0.62), 0.28, 0.24, -0.02, 2],
		],
	]
	var layout: Array = layouts[absi(recipe.layout) % layouts.size()]
	var pieces: Array[Dictionary] = []
	for stone: Array in layout:
		pieces.append({
			"type": "solid",
			"at": _jit(rng, stone[0], 0.018),
			"yaw": float(stone[3]) + rng.randf_range(-0.04, 0.04),
			"spec": {
				"style": "stone",
				"rx": float(stone[1]) * rng.randf_range(0.98, 1.02),
				"rz": float(stone[2]) * rng.randf_range(0.98, 1.02),
				"height": rng.randf_range(0.060, 0.070),
				"corner": rng.randf_range(0.44, 0.54),
				"points": 8,
				"top_scale": 0.82,
				"color": P.color(tones[int(stone[4])]),
				"sink": 0.10,
				"clip": true,
			},
		})
	return {"field": field, "body": _body("rock_deep", "rock_side",
		"rock_groove"), "pieces": pieces, "allow_mirror": true}


# --- E. MOSS CUSHION ---------------------------------------------------------
## Seven cushion SOLIDS pressed into two fused masses over dark substrate:
## broad low domes with soft overhanging lips, per-piece olive variation,
## one calm channel of exposed soil.


static func _compose_moss(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var field := _bed(0.11, 0.016, [
		[-0.008, "moss_deep"],
		[0.020, "moss_substrate"],
	], 0.026, 2.0, rng)
	var pieces: Array[Dictionary] = []
	# Three broad flat cushions: two overlap into the dominant fused mass,
	# one holds the far corner; calm dark earth stays visible between.
	var cushions := [
		[Vector2(-0.30, -0.20), 0.550, 0.460, 0.105, "moss_top"],
		[Vector2(0.10, -0.42), 0.400, 0.340, 0.088, "moss_light"],
		[Vector2(0.42, 0.40), 0.360, 0.310, 0.080, "moss_top"],
	]
	for cushion: Array in cushions:
		pieces.append({
			"type": "solid",
			"at": _jit(rng, cushion[0], 0.03),
			"yaw": rng.randf_range(0.0, TAU),
			"spec": {
				"style": "cushion",
				"rx": float(cushion[1]) * rng.randf_range(0.97, 1.03),
				"rz": float(cushion[2]) * rng.randf_range(0.97, 1.03),
				"height": float(cushion[3]) * rng.randf_range(0.97, 1.03),
				"belly": 1.05,
				"scallop": 0.09,
				"points": 24,
				"top_scale": 0.72,
				"color": P.color(String(cushion[4])),
				"color_top": P.color(String(cushion[4])).lightened(0.08),
				"sink": 0.12,
			},
		})
	return {"field": field, "body": _body("forest_deep", "moss_side",
		"moss_substrate"), "pieces": pieces, "allow_mirror": true}


static func _body(lower: String, side: String, rim: String) -> Dictionary:
	return {
		"chamfer": 0.016,
		"lower_key": lower,
		"side_key": side,
		"upper_rings": [
			{"t": 0.55, "out": -0.004, "key": side},
			{"t": 0.90, "out": 0.004, "key": side},
			{"t": 0.97, "out": 0.006, "key": rim},
		],
	}
