class_name TileV2Library
extends RefCounted
## The authored V2 prototype recipes and their composers.
##
## Each FAMILY is a genuinely different generator: it owns its macro
## topology, body profile, edge behaviour, palette roles, and curated
## layouts. compose() resolves a recipe into a concrete sculpt field plus a
## fully-resolved structure piece list — the generator and mesher stay dumb.
##
## Determinism: every random draw comes from one RNG seeded with
## (family, seed, layout); a seed selects a layout variant and bounded
## jitter (position a few cm, yaw a few degrees, scale ±10%, sanctioned
## omissions, mirroring where the layout allows it). Randomness can never
## restructure a composition.

const F := preload("res://tools/tile_kit/v2/tile_v2_field.gd")
const P := preload("res://tools/tile_kit/v2/tile_v2_palette.gd")

const FAMILIES: Array[String] = [
	"forest_floor", "sand_dune", "snow_cap", "rock_slabs", "moss_cushion",
]

## The five vertical-slice prototypes.
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


## recipe → {"field": TileV2Field (prepared), "body": Dictionary,
##           "pieces": Array[Dictionary]}
static func compose(recipe: TileV2Recipe) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("tilev2|%s|%d|%d" % [recipe.family, recipe.seed, recipe.layout])
	var composed: Dictionary
	match recipe.family:
		"forest_floor":
			composed = _compose_forest(recipe, rng)
		"sand_dune":
			composed = _compose_sand(recipe, rng)
		"snow_cap":
			composed = _compose_snow(recipe, rng)
		"rock_slabs":
			composed = _compose_rock(recipe, rng)
		"moss_cushion":
			composed = _compose_moss(recipe, rng)
		_:
			composed = _compose_moss(recipe, rng)
	var field: TileV2Field = composed["field"]
	# Sanctioned mirroring: some layouts read equally well flipped; the draw
	# happens AFTER all layout jitter so it never disturbs other streams.
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
		var at: Vector2 = piece["at"]
		piece["at"] = Vector2(-at.x, at.y)
		piece["yaw"] = PI - float(piece.get("yaw", 0.0))


static func _breakup(height: float, frequency: float, phase: float) -> Dictionary:
	return {"kind": F.KIND_BREAKUP, "merge": F.MERGE_ADD, "at": Vector2.ZERO,
		"yaw": 0.0, "height": height, "frequency": frequency, "phase": phase}


static func _stops(pairs: Array) -> Array:
	var result: Array = []
	for pair: Array in pairs:
		result.append([float(pair[0]), P.color(String(pair[1]))])
	return result


# --- A. FOREST FLOOR ---------------------------------------------------------
## Quiet compact soil with three embedded bark-chip clusters swept along the
## screen diagonal. The material reads from grouped angular litter IN the
## soil — no grass, no flowers, no confetti. A substantial patch of soil
## stays calm.


static func _compose_forest(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var p := recipe.params
	var macro: float = p.get("macro_scale", 1.0)
	var field := TileV2Field.new()
	field.corner_radius = 0.10
	field.rim_level = 0.022
	field.edge_band = 0.10
	field.floor_min = -0.030
	field.color_stops = _stops([
		[-0.015, "forest_soil_shadow"],
		[0.020, "forest_soil"],
		[0.072, "forest_soil_light"],
	])

	# Macro: one broad soil rise across the litter diagonal, one shallow
	# settled dish opposite — never perfectly flat, never noisy.
	field.ops.append({"kind": F.KIND_SWELL, "merge": F.MERGE_ADD,
		"at": _jit(rng, Vector2(-0.30, 0.24), 0.05), "yaw": 0.0,
		"rx": 0.88, "rz": 0.78, "height": 0.056 * macro})
	field.ops.append({"kind": F.KIND_SWELL, "merge": F.MERGE_ADD,
		"at": _jit(rng, Vector2(0.36, -0.30), 0.05), "yaw": 0.0,
		"rx": 0.52, "rz": 0.46, "height": -0.020 * macro})
	field.ops.append(_breakup(0.006 * macro, 1.9, rng.randf_range(0.0, TAU)))

	# Curated litter layouts along the anti-diagonal (screen left→right):
	# [anchor, cluster yaw, chip count, spread]. One dominant cluster, one
	# supporting, one small; the (−x,−z) and (+x,+z) corners stay quiet.
	var layouts := [
		[
			[Vector2(-0.44, 0.28), -0.68, 7, 0.20],
			[Vector2(0.02, -0.04), 0.48, 5, 0.155],
			[Vector2(0.46, -0.36), -0.42, 3, 0.12],
		],
		[
			[Vector2(-0.42, 0.12), 0.55, 7, 0.20],
			[Vector2(0.12, 0.34), -0.35, 3, 0.12],
			[Vector2(0.44, -0.28), 0.62, 5, 0.155],
		],
	]
	var layout: Array = layouts[absi(recipe.layout) % layouts.size()]
	var pieces: Array[Dictionary] = []
	var chip_scale: float = p.get("structure_scale", 1.0)
	var stain := P.color("forest_soil_shadow")
	for cluster: Array in layout:
		var anchor := _jit(rng, cluster[0], 0.04)
		var cluster_yaw: float = cluster[1] + rng.randf_range(-0.15, 0.15)
		var count: int = cluster[2]
		var spread: float = cluster[3]
		# Contact stain under the cluster: the soil is darker where litter
		# gathers, which is what embeds the chips into the material. The
		# scallop keeps it an irregular damp patch, never a stamped oval.
		field.ops.append({"kind": F.KIND_DOME, "merge": F.MERGE_ADD,
			"at": anchor, "yaw": cluster_yaw, "rx": spread * 2.1,
			"rz": spread * 1.35, "height": 0.0, "softness": 0.85,
			"scallop": 0.30, "scallop_a": 3, "scallop_b": 5,
			"scallop_phase": rng.randf_range(0.0, TAU),
			"scallop_phase_b": rng.randf_range(0.0, TAU),
			"paint_color": stain, "paint_min": 0.44, "paint_feather": 0.24})
		# A slight soil press-up beneath the pile.
		field.ops.append({"kind": F.KIND_DOME, "merge": F.MERGE_MAX,
			"at": anchor, "yaw": cluster_yaw, "rx": spread * 1.9,
			"rz": spread * 1.4, "height": 0.016 * macro, "softness": 0.85,
			"blend": 0.05})
		for index in count:
			# Chips overlap and lean along the cluster axis — a raked pile,
			# not a ring. The first chips are the big ones.
			var t := float(index) / maxf(float(count - 1), 1.0)
			var along := (t - 0.5) * spread * 2.0
			var side := rng.randf_range(-spread * 0.55, spread * 0.55)
			var axis := Vector2(cos(cluster_yaw), sin(cluster_yaw))
			var at := anchor + axis * along + Vector2(-axis.y, axis.x) * side
			var size := lerpf(1.05, 0.68, t) * chip_scale
			pieces.append({
				"type": "chip",
				"key": ["forest_bark", "forest_bark", "forest_bark_light",
					"forest_bark", "forest_bark_deep"][rng.randi() % 5],
				"at": at,
				"length": rng.randf_range(0.150, 0.230) * size,
				"width": rng.randf_range(0.080, 0.120) * size,
				"height": rng.randf_range(0.032, 0.048) * size,
				"yaw": cluster_yaw + rng.randf_range(-0.5, 0.5),
				"sink": rng.randf_range(0.32, 0.46),
			})

	# Two lone strays drifting off the piles toward the edges — litter
	# behaviour, not decoration.
	for stray: Array in [[Vector2(0.60, -0.06), 0.3], [Vector2(-0.16, 0.60), -0.5]]:
		pieces.append({
			"type": "chip",
			"key": "forest_bark" if rng.randf() < 0.7 else "forest_bark_deep",
			"at": _jit(rng, stray[0], 0.05),
			"length": rng.randf_range(0.11, 0.15) * chip_scale,
			"width": rng.randf_range(0.06, 0.08) * chip_scale,
			"height": rng.randf_range(0.026, 0.034) * chip_scale,
			"yaw": float(stray[1]) + rng.randf_range(-0.6, 0.6),
			"sink": rng.randf_range(0.38, 0.52),
		})

	# Accent: one lighter dry patch in a quiet corner — and nothing else.
	field.ops.append({"kind": F.KIND_DOME, "merge": F.MERGE_ADD,
		"at": _jit(rng, Vector2(-0.36, -0.44), 0.05), "yaw": 0.0,
		"rx": 0.24, "rz": 0.18, "height": 0.0, "scallop": 0.26,
		"scallop_phase": rng.randf_range(0.0, TAU), "softness": 0.75,
		"paint_color": P.color("forest_soil_light"),
		"paint_min": 0.46, "paint_feather": 0.12})

	var body := {
		"chamfer": 0.016,
		"lower_key": "forest_deep",
		"side_key": "forest_side",
		"upper_rings": [
			{"t": 0.55, "out": -0.004, "key": "forest_side"},
			{"t": 0.88, "out": 0.005, "key": "forest_side"},
			{"t": 0.965, "out": 0.007, "key": "forest_soil"},
		],
	}
	return {"field": field, "body": body, "pieces": pieces, "allow_mirror": true}


# --- B. SCULPTED SAND --------------------------------------------------------
## One broad diagonal dune IS the tile, carried clean through the rim. A
## small echo ridge, one soft spill over an edge, two whisper impressions.
## Everything else is clean flowing material shaded by a height ramp.


static func _compose_sand(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var p := recipe.params
	var macro: float = p.get("macro_scale", 1.0)
	var dune_height: float = p.get("dune_height", 0.170) * macro
	var field := TileV2Field.new()
	field.corner_radius = 0.14
	field.rim_level = 0.030
	field.edge_band = 0.12
	field.floor_min = -0.016
	field.color_stops = _stops([
		[0.004, "sand_shadow"],
		[0.058, "sand_top"],
		[0.150, "sand_high"],
	])

	# The flow: high side to low side across the whole footprint.
	var flow_yaw := deg_to_rad(-138.0) + rng.randf_range(-0.10, 0.10)
	field.ops.append({"kind": F.KIND_RAMP, "merge": F.MERGE_ADD,
		"at": Vector2.ZERO, "yaw": flow_yaw, "run": 1.9,
		"height": 0.055 * macro})

	# Layout variants move the crest line; the grammar stays.
	var layouts := [
		{"main": Vector2(0.05, -0.02), "second": Vector2(-0.42, 0.44),
			"spill": Vector2(0.56, 0.55)},
		{"main": Vector2(-0.05, 0.10), "second": Vector2(0.45, -0.40),
			"spill": Vector2(-0.54, 0.57)},
	]
	var layout: Dictionary = layouts[absi(recipe.layout) % layouts.size()]

	# The dune: one confident curved stroke, carried through the rim so the
	# silhouette itself is the material.
	var dune_yaw := flow_yaw + PI * 0.5 + rng.randf_range(-0.08, 0.08)
	field.ops.append({"kind": F.KIND_RIDGE, "merge": F.MERGE_MAX,
		"ride_surface": true,
		"at": _jit(rng, layout["main"], 0.05), "yaw": dune_yaw,
		"length": 1.42, "width_windward": 0.45, "width_lee": 0.16,
		"height": dune_height,
		"curve": 0.32 * (1.0 if rng.randf() < 0.5 else -1.0),
		"softness": 0.63, "blend": 0.05,
		"edge_carry": 1.0 * float(p.get("edge_carry_scale", 1.0))})

	# The echo: a much smaller sibling stroke.
	field.ops.append({"kind": F.KIND_RIDGE, "merge": F.MERGE_MAX,
		"at": _jit(rng, layout["second"], 0.05),
		"yaw": dune_yaw + rng.randf_range(-0.13, 0.13),
		"length": 0.60, "width_windward": 0.28, "width_lee": 0.13,
		"height": dune_height * 0.32, "curve": 0.2,
		"softness": 0.70, "blend": 0.045, "edge_carry": 0.55})

	# The spill: a rounded lip of sand pouring over one edge.
	field.ops.append({"kind": F.KIND_DOME, "merge": F.MERGE_MAX,
		"at": _jit(rng, layout["spill"], 0.04), "yaw": 0.0,
		"rx": 0.28, "rz": 0.24, "height": 0.046 * macro, "softness": 0.85,
		"blend": 0.05, "edge_carry": 0.95})

	# Two soft impressions on the windward flat — barely there.
	for offset: Vector2 in [Vector2(-0.34, 0.24), Vector2(-0.10, 0.46)]:
		field.ops.append({"kind": F.KIND_DOME, "merge": F.MERGE_CARVE,
			"at": _jit(rng, offset, 0.05), "yaw": 0.0,
			"rx": rng.randf_range(0.085, 0.110), "rz": rng.randf_range(0.075, 0.095),
			"height": 0.011, "softness": 0.75, "blend": 0.035})

	field.ops.append(_breakup(0.0018 * macro, 1.4, rng.randf_range(0.0, TAU)))

	var body := {
		"chamfer": 0.018,
		"lower_key": "sand_deep",
		"side_key": "sand_side",
		"upper_rings": [
			{"t": 0.42, "out": -0.004, "key": "sand_side"},
			{"t": 0.82, "out": 0.010, "out_carry": 0.008, "key": "sand_side"},
			{"t": 0.95, "out": 0.015, "out_carry": 0.010, "key": "sand_top"},
		],
	}
	return {"field": field, "body": body, "pieces": [], "allow_mirror": true}


# --- C. PILLOWY SNOW ---------------------------------------------------------
## A thick white cap of four fused lobes spread to the corners with a soft
## overhung perimeter over a muted earth body — the cap IS the whole top.
## One settled press between the lobes. Weight, not frosting.


static func _compose_snow(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var p := recipe.params
	var macro: float = p.get("macro_scale", 1.0)
	var cap: float = p.get("cap_height", 0.185) * macro
	var field := TileV2Field.new()
	field.corner_radius = 0.13
	field.rim_level = 0.050
	field.edge_band = 0.09
	field.floor_min = 0.018
	field.color_stops = _stops([
		[0.040, "snow_shadow"],
		[0.100, "snow_top"],
		[0.190, "snow_high"],
	])

	# Four broad lobes spread to the corners: the fused cap IS the whole top,
	# carrying over the rim almost everywhere — no flat moat, no tray.
	var layouts := [
		[
			[Vector2(-0.30, -0.26), 0.62, 0.55, 1.00, 0.90],
			[Vector2(0.40, 0.18), 0.56, 0.49, 0.86, 0.95],
			[Vector2(-0.26, 0.44), 0.50, 0.44, 0.72, 0.85],
			[Vector2(0.34, -0.44), 0.42, 0.37, 0.62, 0.88],
		],
		[
			[Vector2(0.30, -0.30), 0.60, 0.54, 1.00, 0.92],
			[Vector2(-0.40, 0.06), 0.55, 0.48, 0.84, 0.92],
			[Vector2(0.28, 0.46), 0.48, 0.42, 0.70, 0.85],
			[Vector2(-0.32, -0.48), 0.42, 0.36, 0.60, 0.88],
		],
	]
	var layout: Array = layouts[absi(recipe.layout) % layouts.size()]
	var softness: float = p.get("lobe_softness", 0.80)
	for lobe: Array in layout:
		field.ops.append({"kind": F.KIND_DOME, "merge": F.MERGE_MAX,
			"ride_surface": false,
			"at": _jit(rng, lobe[0], 0.04),
			"yaw": rng.randf_range(0.0, TAU),
			"rx": float(lobe[1]) * rng.randf_range(0.96, 1.04),
			"rz": float(lobe[2]) * rng.randf_range(0.96, 1.04),
			"height": cap * float(lobe[3]) * rng.randf_range(0.96, 1.04),
			"softness": softness,
			"scallop": 0.10, "scallop_a": 3, "scallop_b": 5,
			"scallop_phase": rng.randf_range(0.0, TAU),
			"scallop_phase_b": rng.randf_range(0.0, TAU),
			"blend": 0.095,
			"edge_carry": float(lobe[4]) * float(p.get("edge_carry_scale", 1.0))})

	# The compression: one settled dip in the saddle BETWEEN lobes, with a
	# soft painted cooler shadow — pressed snow, not a crater.
	var hollow := _jit(rng, Vector2(0.04, 0.06), 0.04)
	field.ops.append({"kind": F.KIND_DOME, "merge": F.MERGE_CARVE,
		"at": hollow, "yaw": 0.0,
		"rx": 0.30, "rz": 0.25, "height": 0.030 * macro, "softness": 0.85,
		"blend": 0.07})
	field.ops.append({"kind": F.KIND_DOME, "merge": F.MERGE_ADD,
		"at": hollow, "yaw": 0.0, "rx": 0.24, "rz": 0.20, "height": 0.0,
		"softness": 0.85, "paint_color": P.color("snow_shadow"),
		"paint_min": 0.55, "paint_feather": 0.22})

	field.ops.append(_breakup(0.0018 * macro, 1.2, rng.randf_range(0.0, TAU)))

	var overhang: float = p.get("overhang", 1.0)
	var body := {
		"chamfer": 0.016,
		"lower_key": "snow_body_deep",
		"side_key": "snow_body",
		"upper_rings": [
			{"t": 0.30, "out": -0.004, "key": "snow_body"},
			{"t": 0.55, "out": -0.002, "key": "snow_body"},
			# The cap: shadowed underside rolling out into the white lobes.
			{"t": 0.66, "out": 0.016 * overhang, "out_carry": 0.014 * overhang,
				"key": "snow_shadow"},
			{"t": 0.80, "out": 0.028 * overhang, "out_carry": 0.014 * overhang,
				"key": "snow_top"},
			{"t": 0.94, "out": 0.018 * overhang, "out_carry": 0.008 * overhang,
				"key": "snow_top"},
		],
	}
	return {"field": field, "body": body, "pieces": [], "allow_mirror": true}


# --- D. ROUNDED ROCK GROUND --------------------------------------------------
## Five fitted slab volumes with soft deep grooves and subtly domed faces,
## running to the rim; one step of height; one gravel pocket where a slab
## was left out. Structure, not scatter — the layout is the identity.


static func _compose_rock(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var p := recipe.params
	var macro: float = p.get("macro_scale", 1.0)
	var slab_height: float = p.get("slab_height", 0.070) * macro
	var field := TileV2Field.new()
	field.corner_radius = 0.075
	field.rim_level = 0.030
	field.edge_band = 0.085
	field.floor_min = -0.008
	field.color_stops = _stops([[0.0, "rock_groove"]])

	# The terrace: one half of the composition sits a step higher.
	var terrace_yaw := deg_to_rad(32.0) + rng.randf_range(-0.12, 0.12)
	field.ops.append({"kind": F.KIND_RAMP, "merge": F.MERGE_ADD,
		"at": Vector2.ZERO, "yaw": terrace_yaw, "run": 1.5,
		"height": 0.042 * macro})

	# Fitted slab layouts: [at, hx, hz, yaw, colour index]. Gaps are the
	# grooves; slabs run to the rim and carry through it. The pocket entry
	# marks where a slab was deliberately left out.
	var layouts := [
		{
			"slabs": [
				[Vector2(-0.46, -0.44), 0.375, 0.300, 0.03, 0],
				[Vector2(0.33, -0.48), 0.350, 0.265, -0.05, 1],
				[Vector2(-0.48, 0.31), 0.300, 0.335, -0.03, 2],
				[Vector2(0.15, 0.065), 0.335, 0.290, 0.06, 0],
				[Vector2(0.57, 0.48), 0.290, 0.315, -0.04, 1],
			],
			"pocket": Vector2(-0.11, 0.60),
		},
		{
			"slabs": [
				[Vector2(-0.48, -0.18), 0.330, 0.360, -0.04, 1],
				[Vector2(0.22, -0.46), 0.370, 0.280, 0.05, 0],
				[Vector2(0.57, 0.18), 0.280, 0.330, 0.03, 2],
				[Vector2(-0.06, 0.22), 0.320, 0.300, -0.06, 0],
				[Vector2(-0.55, 0.55), 0.270, 0.255, 0.04, 1],
			],
			"pocket": Vector2(0.40, 0.62),
		},
	]
	var slab_keys := ["rock_slab", "rock_slab_light", "rock_slab_warm"]
	var layout: Dictionary = layouts[absi(recipe.layout) % layouts.size()]
	for slab: Array in layout["slabs"]:
		field.ops.append({"kind": F.KIND_PLATEAU, "merge": F.MERGE_MAX,
			"ride_surface": true,
			"at": _jit(rng, slab[0], 0.02),
			"yaw": float(slab[3]) + rng.randf_range(-0.05, 0.05),
			"hx": float(slab[1]) * rng.randf_range(0.97, 1.03),
			"hz": float(slab[2]) * rng.randf_range(0.97, 1.03),
			"corner": minf(float(slab[1]), float(slab[2])) * 0.46,
			"bevel": 0.060, "dome": 0.020 * macro,
			"wobble": 0.0045, "wobble_phase": rng.randf_range(0.0, TAU),
			"height": slab_height * rng.randf_range(0.92, 1.08),
			"blend": 0.015,
			"edge_carry": 0.60,
			"paint_color": P.color(slab_keys[int(slab[4])]),
			"paint_min": 0.55, "paint_feather": 0.10})

	# The gravel pocket: a shallow bed with a handful of settled pebbles in
	# the gap the missing slab left. Under 8% of the surface.
	var pocket: Vector2 = _jit(rng, layout["pocket"], 0.03)
	field.ops.append({"kind": F.KIND_DOME, "merge": F.MERGE_CARVE,
		"at": pocket, "yaw": 0.0, "rx": 0.17, "rz": 0.15, "height": 0.018,
		"softness": 0.8, "blend": 0.03})
	field.ops.append({"kind": F.KIND_DOME, "merge": F.MERGE_ADD,
		"at": pocket, "yaw": 0.0, "rx": 0.145, "rz": 0.125, "height": 0.0,
		"scallop": 0.2, "scallop_phase": rng.randf_range(0.0, TAU),
		"softness": 0.75, "paint_color": P.color("rock_gravel"),
		"paint_min": 0.42, "paint_feather": 0.14})
	var pieces: Array[Dictionary] = []
	for index in 6:
		var angle := TAU * float(index) / 6.0 + rng.randf_range(-0.45, 0.45)
		pieces.append({
			"type": "pebble",
			"key": "rock_gravel" if index % 3 != 2 else "rock_slab_light",
			"at": pocket + Vector2(cos(angle), sin(angle)) \
				* rng.randf_range(0.02, 0.08),
			"radius": rng.randf_range(0.022, 0.036),
			"height": rng.randf_range(0.014, 0.022),
			"yaw": rng.randf_range(0.0, TAU),
		})

	field.ops.append(_breakup(0.0035 * macro, 2.3, rng.randf_range(0.0, TAU)))

	var body := {
		"chamfer": 0.020,
		"lower_key": "rock_deep",
		"side_key": "rock_side",
		"upper_rings": [
			{"t": 0.48, "out": -0.004, "key": "rock_side"},
			{"t": 0.86, "out": 0.007, "key": "rock_side"},
			{"t": 0.955, "out": 0.009, "out_carry": 0.008,
				"key": "rock_groove", "key_carry": "rock_slab"},
		],
	}
	return {"field": field, "body": body, "pieces": pieces, "allow_mirror": true}


# --- E. MOSS CUSHION ---------------------------------------------------------
## Two fused cushion masses — one dominant, one counterweight — of broad
## LOW scalloped lobes over a dark substrate that survives as the diagonal
## channel between them. Lobes merge; nothing reads as a separate sphere.


static func _compose_moss(recipe: TileV2Recipe, rng: RandomNumberGenerator) -> Dictionary:
	var p := recipe.params
	var macro: float = p.get("macro_scale", 1.0)
	var cushion: float = p.get("cushion_height", 0.115) * macro
	var field := TileV2Field.new()
	field.corner_radius = 0.11
	field.rim_level = 0.016
	field.edge_band = 0.08
	field.floor_min = -0.022
	field.color_stops = _stops([
		[-0.012, "moss_deep"],
		[0.010, "moss_substrate"],
	])

	# Substrate: gentle settle plus fine tooth.
	field.ops.append({"kind": F.KIND_SWELL, "merge": F.MERGE_ADD,
		"at": Vector2(0.10, 0.06), "yaw": 0.0, "rx": 0.9, "rz": 0.85,
		"height": 0.016 * macro})
	field.ops.append(_breakup(0.004 * macro, 2.2, rng.randf_range(0.0, TAU)))

	# Masses: [at, rx, rz, height factor, paint key, carry]. Broad LOW
	# cushions covering most of the top, heavily blended so adjacent lobes
	# melt into two fused masses; the substrate survives as the diagonal
	# channel between them, never as a border ring.
	var layouts := [
		[
			# Dominant mass sweeps the lower-left half over the rim.
			[Vector2(-0.34, -0.26), 0.420, 0.360, 1.00, "moss_top", 0.75],
			[Vector2(0.06, -0.46), 0.330, 0.285, 0.84, "moss_top", 0.65],
			[Vector2(-0.60, 0.10), 0.310, 0.270, 0.78, "moss_shadow", 0.60],
			[Vector2(-0.58, -0.50), 0.300, 0.265, 0.72, "moss_top", 0.90],
			[Vector2(0.02, -0.06), 0.260, 0.235, 0.68, "moss_light", 0.0],
			# Counterweight mass holds the upper-right corner.
			[Vector2(0.50, 0.40), 0.340, 0.300, 0.80, "moss_top", 0.72],
			[Vector2(0.64, 0.05), 0.250, 0.225, 0.58, "moss_light", 0.55],
			[Vector2(0.16, 0.58), 0.270, 0.240, 0.62, "moss_shadow", 0.50],
		],
		[
			[Vector2(-0.30, 0.30), 0.410, 0.355, 1.00, "moss_top", 0.75],
			[Vector2(-0.58, -0.02), 0.320, 0.280, 0.82, "moss_shadow", 0.60],
			[Vector2(0.04, 0.52), 0.310, 0.270, 0.78, "moss_top", 0.68],
			[Vector2(-0.56, 0.54), 0.290, 0.260, 0.70, "moss_top", 0.88],
			[Vector2(-0.02, 0.12), 0.250, 0.230, 0.66, "moss_light", 0.0],
			[Vector2(0.48, -0.36), 0.330, 0.290, 0.80, "moss_top", 0.72],
			[Vector2(0.64, 0.06), 0.240, 0.220, 0.58, "moss_light", 0.52],
			[Vector2(0.14, -0.56), 0.260, 0.235, 0.62, "moss_shadow", 0.55],
		],
	]
	var layout: Array = layouts[absi(recipe.layout) % layouts.size()]
	var softness: float = p.get("lobe_softness", 0.62)
	for lobe: Array in layout:
		field.ops.append({"kind": F.KIND_DOME, "merge": F.MERGE_MAX,
			"ride_surface": true,
			"at": _jit(rng, lobe[0], 0.03),
			"yaw": rng.randf_range(0.0, TAU),
			"rx": float(lobe[1]) * rng.randf_range(0.95, 1.05),
			"rz": float(lobe[2]) * rng.randf_range(0.95, 1.05),
			"height": cushion * float(lobe[3]) * rng.randf_range(0.95, 1.05),
			"softness": softness,
			"scallop": 0.13, "scallop_a": 3, "scallop_b": 5,
			"scallop_phase": rng.randf_range(0.0, TAU),
			"scallop_phase_b": rng.randf_range(0.0, TAU),
			"blend": 0.095,
			"paint_color": P.color(String(lobe[4])),
			"paint_min": 0.22, "paint_feather": 0.10,
			"edge_carry": float(lobe[5]) * float(p.get("edge_carry_scale", 1.0))})

	# One shallow darker hollow in the substrate channel.
	field.ops.append({"kind": F.KIND_DOME, "merge": F.MERGE_CARVE,
		"at": _jit(rng, Vector2(0.20, 0.18), 0.04), "yaw": 0.0,
		"rx": 0.15, "rz": 0.13, "height": 0.018, "softness": 0.7,
		"blend": 0.04})

	var body := {
		"chamfer": 0.016,
		"lower_key": "moss_side",
		"side_key": "moss_side",
		"upper_rings": [
			{"t": 0.45, "out": -0.004, "key": "moss_side"},
			{"t": 0.78, "out": 0.003, "key": "moss_substrate"},
			{"t": 0.94, "out": 0.009, "out_carry": 0.018,
				"key": "moss_substrate", "key_carry": "moss_top"},
		],
	}
	return {"field": field, "body": body, "pieces": [], "allow_mirror": true}
