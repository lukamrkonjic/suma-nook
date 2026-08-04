class_name KitClusterBuilder
extends RefCounted
## Asymmetrical clusters of thick, soft, curved grass blades.
##
## Two ideas carry this layer. First, the blade itself: a broad elliptical
## ribbon swept along a curve that stays upright through its lower third and
## does its bending in the upper half — thick enough to be a sculpted form,
## never a card or a spike. Second, the composition: clusters are placed from
## a mutated layout template and then REJECTED if they come out balanced.
## Symmetry is the tell of a machine; the reference reads handmade precisely
## because its weight sits off-centre and its open ground is genuinely open.
##
## One species, one palette: ~80% primary green, ~20% secondary, at most a
## couple of deep root accents buried inside large clusters. Variation lives
## in pose and size, never in per-blade tinting.

## Loose layout templates, in normalised tile space (−1..1). Each entry is a
## list of [x, z, size_class] anchors; mutation jitters them, so the templates
## guarantee good bones without ever stamping a recognisable pattern.
const TEMPLATES := [
	[[-0.55, -0.15, 0], [0.35, -0.45, 1], [0.45, 0.30, 1], [0.05, 0.55, 2],
		[-0.30, 0.45, 1], [0.65, -0.05, 2]],
	[[-0.40, -0.40, 1], [0.15, 0.05, 0], [0.55, 0.45, 1], [-0.55, 0.35, 2],
		[0.40, -0.55, 2], [-0.10, -0.60, 1]],
	[[0.50, -0.35, 0], [-0.45, -0.50, 1], [-0.55, 0.10, 1], [0.20, 0.50, 1],
		[0.60, 0.25, 2], [-0.15, -0.20, 2]],
	[[-0.60, 0.45, 0], [-0.20, -0.50, 1], [0.45, -0.20, 1], [0.55, 0.55, 2],
		[0.10, 0.20, 1], [-0.50, -0.10, 2]],
	[[0.30, 0.35, 0], [-0.50, -0.30, 1], [-0.35, 0.55, 2], [0.55, -0.50, 1],
		[-0.05, -0.15, 1], [0.65, 0.05, 2]],
]
const MAX_COMPOSITION_ATTEMPTS := 24


static func build(layer: TileKitLayer, rng: RandomNumberGenerator,
		context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.775)
	var top: float = context.get("surface_top", 0.0)
	var batch := TileKitMeshUtils.MeshBatch.new()

	# Two composition modes, chosen by the preset:
	#
	# "carpet" — a jittered grid of small uniform sprout rosettes covering the
	# whole top. This is how the reference game reads: a grass tile is a
	# TEXTURE made of repeated sprouts, so a hundred of them side by side
	# become one continuous land mass instead of a hundred decorated squares.
	#
	# "clusters" — a few asymmetric feature clusters with open ground, for
	# accent tiles where the grass is a subject rather than a surface.
	var composition: Array
	var mode := String(layer.value("coverage_mode", "carpet"))
	if mode == "gold_grass":
		return _build_gold_grass(layer, rng, context)
	if mode == "tufts":
		return _build_tuft_composition(layer, rng, context)
	if mode == "moss_pads":
		return _build_moss_pads(layer, rng, context)
	if mode == "turf":
		return _build_turf(layer, rng, context)
	if mode == "carpet":
		composition = _compose_carpet(layer, rng, half)
	else:
		composition = _compose(layer, rng, half)
	# Stones laid by an earlier pavers layer are ground the grass must not
	# grow through — the garden-path composition.
	var stones: Array = context.get("paver_stones", [])
	if not stones.is_empty():
		var kept: Array = []
		for cluster: Dictionary in composition:
			var blocked := false
			for stone: Dictionary in stones:
				var delta: Vector2 = (cluster["centre"] as Vector2) 					- (stone["centre"] as Vector2)
				if absf(delta.x) < float(stone["half_x"]) + 0.05 						and absf(delta.y) < float(stone["half_z"]) + 0.05:
					blocked = true
					break
			if not blocked:
				kept.append(cluster)
		composition = kept
	var cap_height: Callable = context.get("cap_height", Callable())
	for cluster: Dictionary in composition:
		_build_rosette(batch, layer, rng, cluster, top, cap_height)

	context["grass_clusters"] = composition
	return {
		"meshes": [{"role": "detail", "name": "tile_grass",
			"mesh": batch.commit()}],
	}


## Jittered grid over the usable top. Even spacing carries the repetition-
## friendly rhythm; the jitter, scale wobble, and a few hash-skipped cells
## keep it from reading as a mechanical lattice.
static func _compose_carpet(layer: TileKitLayer, rng: RandomNumberGenerator,
		half: float) -> Array:
	var spacing: float = layer.value("carpet_spacing", 0.22)
	var jitter: float = layer.value("carpet_jitter", 0.35)
	var skip: float = layer.value("carpet_skip_fraction", 0.10)
	# Default margin is now a whisker: sprout crowns go almost to the
	# footprint boundary, and their leaves overhang the bevel like moss over
	# a wall. Anything larger leaves a bald strip that a 3x3 reads as grid
	# lines — the exact failure repetition is judged on.
	var margin: float = layer.value("edge_margin", 0.02)
	var footprint_band: Array = layer.value("rosette_footprint", [0.10, 0.145])

	var usable := half - margin
	var columns := maxi(1, int(floor((usable * 2.0) / spacing)))
	var start := -(float(columns) - 1.0) * 0.5 * spacing
	var result: Array = []
	for row in columns:
		for column in columns:
			if rng.randf() < skip:
				continue
			var centre := Vector2(
				start + column * spacing + rng.randf_range(-jitter, jitter) * spacing,
				start + row * spacing + rng.randf_range(-jitter, jitter) * spacing
			)
			var footprint := rng.randf_range(float(footprint_band[0]),
				float(footprint_band[1]))
			# Crowns may sit close enough to the boundary that leaves lap
			# over the bevel; only the crown itself stays on the tile.
			var limit := usable - footprint * 0.10
			centre.x = clampf(centre.x, -limit, limit)
			centre.y = clampf(centre.y, -limit, limit)
			# One relaxation pass: two sprouts fusing into a lumpy mass is the
			# single fastest way for a clean carpet to read as clutter.
			for existing: Dictionary in result:
				var other: Vector2 = existing["centre"]
				var minimum := (footprint + float(existing["footprint"])) * 0.55
				var delta := centre - other
				if delta.length() < minimum and delta.length() > 0.001:
					centre = other + delta.normalized() * minimum
			centre.x = clampf(centre.x, -limit, limit)
			centre.y = clampf(centre.y, -limit, limit)
			result.append({
				"centre": centre,
				"footprint": footprint,
				"size_class": 2,
				"lean_yaw": rng.randf() * TAU,
				"aspect": rng.randf_range(0.85, 1.0),
				"yaw": rng.randf() * TAU,
			})
	return result


# --- gold master grass -------------------------------------------------------

## The hand-directed Standard Grass composition. Anchor positions, archetype
## choices, and fringe spans are AUTHORED — the seed only breathes life into
## them with small jitter, yaw variation, and blade-level randomness, so every
## seed reads as the same deliberate design executed slightly differently.
##
## Layout (normalised tile space): a medium three-direction tuft rear-left, a
## wide fan against the right edge, a small curved group front-left, two
## asymmetric supports, one optional taller accent, and fringe on parts of
## the rear and right edges only. The centre-front stays calm for props.
const GOLD_ANCHORS := [
	{"at": Vector2(-0.36, -0.44), "archetype": 1},
	{"at": Vector2(0.62, 0.05), "archetype": 2},
	{"at": Vector2(-0.47, 0.35), "archetype": 3},
	{"at": Vector2(-0.28, 0.50), "archetype": 3},
	{"at": Vector2(0.20, -0.22), "archetype": 3},
	{"at": Vector2(0.33, 0.58), "archetype": 3},
]
const GOLD_ACCENT := Vector2(0.47, -0.52)
const GOLD_FRINGE := [
	# [edge outward, along-edge fractions 0..1] — parts of two edges only.
	[Vector2(0.0, -1.0), [0.30, 0.52, 0.74]],
	[Vector2(1.0, 0.0), [0.38, 0.60]],
]


static func _build_gold_grass(layer: TileKitLayer,
		rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var batch := TileKitMeshUtils.MeshBatch.new()
	var scale: float = layer.value("tuft_scale", 1.0)

	var surface_at := func(point: Vector2) -> float:
		if cap_height.is_valid():
			return top + float(cap_height.call(Vector2(
				clampf(point.x, -half, half), clampf(point.y, -half, half))))
		return top

	for anchor: Dictionary in GOLD_ANCHORS:
		var position: Vector2 = (anchor["at"] as Vector2) * half + Vector2(
			rng.randf_range(-0.05, 0.05), rng.randf_range(-0.05, 0.05))
		_gold_cluster(batch, rng, position, surface_at.call(position),
			int(anchor["archetype"]), scale)
	if rng.randf() < 0.55:
		var position := GOLD_ACCENT * half + Vector2(
			rng.randf_range(-0.05, 0.05), rng.randf_range(-0.05, 0.05))
		_gold_cluster(batch, rng, position, surface_at.call(position), 4, scale)

	# Fringe: short grouped blades integrated into the turf edge, on parts
	# of two edges only, leaning gently outward. Connected edges take no
	# fringe — inside a land mass the seam must stay invisible.
	var mask := int(context.get("neighbour_mask", 0))
	var edge_bits := {Vector2(0.0, -1.0): 1, Vector2(1.0, 0.0): 2,
		Vector2(0.0, 1.0): 4, Vector2(-1.0, 0.0): 8}
	for span: Array in GOLD_FRINGE:
		var outward: Vector2 = span[0]
		if (mask & int(edge_bits.get(outward, 0))) != 0:
			continue
		var along := Vector2(-outward.y, outward.x)
		for fraction: float in span[1]:
			var position := outward * (half - 0.055) \
				+ along * ((fraction * 2.0 - 1.0) * (half - 0.06)) \
				+ along * rng.randf_range(-0.04, 0.04)
			var outward_yaw := atan2(outward.y, outward.x)
			_gold_fringe_tuft(batch, rng, position,
				surface_at.call(position), outward_yaw, scale)

	context["grass_clusters"] = []
	return {
		"meshes": [{"role": "detail", "name": "tile_grass",
			"mesh": batch.commit()}],
	}


## One sculpted cluster: blades share a crown over a small recessed base pad,
## and every archetype forms a single coherent silhouette.
static func _gold_cluster(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, centre: Vector2, surface_y: float,
		archetype: int, scale: float) -> void:
	var facing := rng.randf() * TAU
	var pad_radius := 0.075 * scale
	var blades: Array[Dictionary] = []
	match archetype:
		1:
			# Low three-direction tuft: three small groups sharing a base.
			pad_radius = 0.10 * scale
			for group in 3:
				var group_yaw := facing + group * 2.09 \
					+ rng.randf_range(-0.25, 0.25)
				for blade in 3:
					blades.append({"yaw": group_yaw + (blade - 1.0) * 0.42,
						"height": rng.randf_range(0.15, 0.21),
						"lean": rng.randf_range(0.45, 0.62)})
		2:
			# Wide fan: one direction, tall centre falling to short flanks.
			pad_radius = 0.11 * scale
			var fan_count := 8
			for blade in fan_count:
				var spread := (float(blade) / float(fan_count - 1) - 0.5) * 2.1
				var falloff := 1.0 - absf(spread) * 0.34
				blades.append({"yaw": facing + spread
						+ rng.randf_range(-0.12, 0.12),
					"height": rng.randf_range(0.17, 0.23) * falloff,
					"lean": rng.randf_range(0.55, 0.75)})
		3:
			# Small curved tuft: few blades, one flow, moderate bend.
			pad_radius = 0.065 * scale
			var count := 4 + (rng.randi() % 2)
			for blade in count:
				blades.append({"yaw": facing
						+ (float(blade) / float(count - 1) - 0.5) * 1.1
						+ rng.randf_range(-0.15, 0.15),
					"height": rng.randf_range(0.13, 0.18),
					"lean": rng.randf_range(0.55, 0.75)})
		4:
			# Taller asymmetric accent: the one dramatic silhouette. Blades
			# take evenly separated directions so the cluster stays a fan of
			# distinct curls — never a merged trunk.
			pad_radius = 0.11 * scale
			var tallest := rng.randi_range(0, 6)
			for blade in 7:
				var is_tall: bool = blade == tallest \
					or blade == (tallest + 3) % 7
				blades.append({"yaw": facing + float(blade) * (TAU / 7.0)
						+ rng.randf_range(-0.25, 0.25),
					"height": rng.randf_range(0.30, 0.38) if is_tall
						else rng.randf_range(0.17, 0.24),
					"lean": rng.randf_range(0.45, 0.62)})

	for blade: Dictionary in blades:
		_gold_blade(batch, rng, centre, surface_y, float(blade["yaw"]),
			float(blade["height"]) * scale, float(blade["lean"]),
			pad_radius * 0.5)


static func _gold_fringe_tuft(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, centre: Vector2, surface_y: float,
		outward_yaw: float, scale: float) -> void:
	for blade in 3 + (rng.randi() % 2):
		_gold_blade(batch, rng, centre, surface_y,
			outward_yaw + rng.randf_range(-0.6, 0.6),
			rng.randf_range(0.07, 0.105) * scale,
			rng.randf_range(0.6, 0.85), 0.03)


## One broad curved blade: thick at the base, a long soft taper, a gently
## curled tip. Chunky enough to read at gameplay distance; never a spike.
static func _gold_blade(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, centre: Vector2, surface_y: float,
		yaw: float, blade_height: float, lean: float,
		root_spread: float) -> void:
	var direction := Vector2(cos(yaw), sin(yaw))
	var root := centre + direction * rng.randf_range(0.2, 1.0) * root_spread
	var lean3 := Vector3(direction.x, 0.0, direction.y)
	var reach := blade_height * lean
	var width := clampf(blade_height * rng.randf_range(0.34, 0.42),
		0.040, 0.115)
	# The arc: upright through the lower half, bending hard through the top
	# third, the tip dropping slightly past its peak — a curled leaf, never
	# a leaning cone.
	var p0 := Vector3(root.x, surface_y - 0.012, root.y)
	var p1 := p0 + Vector3.UP * (blade_height * 0.48) + lean3 * (reach * 0.06)
	var p2 := p0 + Vector3.UP * (blade_height * 0.92) + lean3 * (reach * 0.52)
	var p3 := p0 + Vector3.UP * (blade_height * 0.94) + lean3 * reach
	var roll := rng.randf()
	var key := "grass_primary"
	if roll < 0.26:
		key = "grass_root"
	elif roll < 0.38:
		key = "grass_secondary"
	TileKitMeshUtils.add_blade(batch, key, p0, p1, p2, p3, width,
		rng.randf_range(0.42, 0.52), 6, 6, 2)


# --- tufts: art-directed sparse grass ----------------------------------------

## Handcrafted composition templates, in normalised tile space (−1..1).
## Each entry: broad low turf masses (the MACRO form) plus tuft anchors with
## size classes 0/1/2 (the MEDIUM forms). Placement mutates a template —
## jitter, whole-template rotation, scale wobble — so randomness varies a
## strong composition instead of inventing a weak one. Negative space is part
## of every template by construction.
const TUFT_TEMPLATES := [
	{ # Open centre, growth gathered on two opposing edges.
		"masses": [[-0.05, -0.74, 0.55, 0.24], [0.18, 0.76, 0.48, 0.20]],
		"tufts": [[-0.52, -0.70, 2], [0.30, -0.78, 1], [-0.05, -0.55, 0],
			[0.58, 0.68, 2], [-0.15, 0.72, 1], [0.72, 0.30, 0]],
	},
	{ # One large diagonal turf mass; the far corner stays open.
		"masses": [[-0.22, -0.22, 0.78, 0.34]],
		"tufts": [[-0.55, -0.48, 2], [-0.10, -0.15, 1], [0.28, 0.10, 1],
			[-0.72, 0.05, 0], [0.62, 0.66, 0]],
	},
	{ # Quiet front, taller cluster at the rear.
		"masses": [[0.02, -0.58, 0.62, 0.30]],
		"tufts": [[-0.35, -0.62, 2], [0.25, -0.50, 2], [0.60, -0.70, 1],
			[-0.68, -0.30, 1], [0.05, 0.25, 0]],
	},
	{ # Two unequal side clusters with a clear central channel.
		"masses": [[-0.62, -0.10, 0.34, 0.44], [0.68, 0.35, 0.26, 0.30]],
		"tufts": [[-0.60, -0.42, 2], [-0.55, 0.28, 1], [0.66, 0.10, 1],
			[0.60, 0.62, 0], [-0.20, 0.75, 0]],
	},
	{ # Large corner mass balanced by one far small accent.
		"masses": [[-0.48, -0.48, 0.52, 0.42]],
		"tufts": [[-0.62, -0.62, 2], [-0.15, -0.42, 1], [-0.50, -0.05, 1],
			[0.55, 0.55, 1], [0.20, 0.15, 0]],
	},
]


## The premium grass construction: a calm top, one or two broad low turf
## masses, and a handful of chunky directional blade tufts — each tuft one
## designed silhouette. Never a carpet, never bubbles.
static func _build_tuft_composition(layer: TileKitLayer,
		rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var stones: Array = context.get("paver_stones", [])
	var batch := TileKitMeshUtils.MeshBatch.new()

	var template: Dictionary = TUFT_TEMPLATES[rng.randi() % TUFT_TEMPLATES.size()]
	# Whole-template rotation in quarter turns keeps compositions fresh
	# across neighbouring tiles without ever mirroring one against another.
	var quarter := rng.randi() % 4
	var scale_wobble := rng.randf_range(0.9, 1.06)
	var primary := String(layer.value("primary_key", "tile_top"))
	var blade_dark := String(layer.value("blade_key", "grass_primary"))
	var blade_light := String(layer.value("blade_light_key", "grass_secondary"))
	var mass_height_band: Array = layer.value("mass_height", [0.026, 0.042])
	var mass_scale: float = layer.value("mass_scale", 1.0)
	var tuft_scale: float = layer.value("tuft_scale", 1.0)
	var lean_strength: float = layer.value("tuft_lean", 0.55)
	var extra_tufts := KitDressingBuilder._int_range(
		rng, layer.value("extra_tufts", [0, 1]))
	var prevailing := rng.randf() * TAU

	# MACRO: broad low turf masses in the top's own colour — raised ground,
	# not decoration. Their smooth lobed silhouette carries the tile edge.
	for raw_mass: Array in template.get("masses", []):
		var position := _template_point(
			Vector2(raw_mass[0], raw_mass[1]), quarter, rng, half, scale_wobble)
		var radius_x: float = raw_mass[2] * half * scale_wobble * mass_scale
		var radius_z: float = raw_mass[3] * half * scale_wobble * mass_scale
		if _blocked_by_stone(position, stones, 0.02):
			continue
		var surface_y := top
		if cap_height.is_valid():
			surface_y = top + float(cap_height.call(Vector2(
				clampf(position.x, -half, half),
				clampf(position.y, -half, half))))
		var mass_height := rng.randf_range(float(mass_height_band[0]),
			float(mass_height_band[1]))
		TileKitMeshUtils.add_lobed_mound(batch, primary,
			Vector3(position.x, surface_y - mass_height * 0.12, position.y),
			radius_x, radius_z, mass_height,
			rng.randf() * TAU, rng, 0.17, 4, 14, 0.7)
		# A few blades rise from the mass itself so it reads as grass depth,
		# not a plinth.
		for sprout in rng.randi_range(2, 3):
			var sprout_at := position + Vector2(
				rng.randf_range(-radius_x, radius_x) * 0.55,
				rng.randf_range(-radius_z, radius_z) * 0.55)
			_build_tuft(batch, layer, rng, sprout_at,
				surface_y + mass_height * 0.55, 0, tuft_scale,
				prevailing, lean_strength, blade_dark, blade_light)

	# MEDIUM: the tuft anchors — each one readable silhouette.
	var placed: Array[Vector2] = []
	for raw_tuft: Array in template.get("tufts", []):
		var position := _template_point(
			Vector2(raw_tuft[0], raw_tuft[1]), quarter, rng, half, scale_wobble)
		if _blocked_by_stone(position, stones, 0.06):
			continue
		var surface_y := top
		if cap_height.is_valid():
			surface_y = top + float(cap_height.call(Vector2(
				clampf(position.x, -half, half),
				clampf(position.y, -half, half))))
		_build_tuft(batch, layer, rng, position, surface_y,
			int(raw_tuft[2]), tuft_scale, prevailing, lean_strength,
			blade_dark, blade_light)
		placed.append(position)
	# Optional stray tufts, kept clear of existing ones.
	for extra in extra_tufts:
		var position := Vector2(rng.randf_range(-half * 0.7, half * 0.7),
			rng.randf_range(-half * 0.7, half * 0.7))
		var clear := true
		for existing in placed:
			if existing.distance_to(position) < 0.34:
				clear = false
				break
		if not clear or _blocked_by_stone(position, stones, 0.06):
			continue
		var surface_y := top
		if cap_height.is_valid():
			surface_y = top + float(cap_height.call(position))
		_build_tuft(batch, layer, rng, position, surface_y, 0, tuft_scale,
			prevailing, lean_strength, blade_dark, blade_light)
		placed.append(position)

	context["grass_clusters"] = placed
	return {
		"meshes": [{"role": "detail", "name": "tile_grass",
			"mesh": batch.commit()}],
	}


static func _template_point(normalised: Vector2, quarter: int,
		rng: RandomNumberGenerator, half: float, scale: float) -> Vector2:
	var rotated := normalised
	for turn in quarter:
		rotated = Vector2(-rotated.y, rotated.x)
	var jittered := rotated * scale + Vector2(
		rng.randf_range(-0.07, 0.07), rng.randf_range(-0.07, 0.07))
	return jittered * half


## One designed grass tuft: three to seven broad tapered blades emerging from
## a shared crown, fanned around a shared lean direction with one or two
## counter-leaning balances — a single readable silhouette, chunky enough to
## survive the gameplay camera. Size class 0/1/2 scales count and height.
static func _build_tuft(batch: TileKitMeshUtils.MeshBatch,
		layer: TileKitLayer, rng: RandomNumberGenerator, centre: Vector2,
		crown_y: float, size_class: int, scale: float, prevailing: float,
		lean_strength: float, dark_key: String, light_key: String) -> void:
	var blade_counts := [3, 4, 6]
	var height_bands := [[0.085, 0.125], [0.115, 0.165], [0.150, 0.230]]
	var blade_count: int = int(blade_counts[size_class]) + (rng.randi() % 2)
	var height_band: Array = height_bands[size_class]
	var tuft_yaw := prevailing + rng.randf_range(-0.9, 0.9)
	var crown_radius := 0.022 * scale * (1.0 + 0.35 * size_class)
	for blade in blade_count:
		# Fan around the tuft direction; roughly one blade in four leans
		# against the flow, which keeps the silhouette balanced.
		var against: bool = (blade % 4) == 3
		var yaw: float = tuft_yaw + (PI if against else 0.0)
		yaw += rng.randf_range(-1.0, 1.0)
		var direction := Vector2(cos(yaw), sin(yaw))
		var blade_height := rng.randf_range(float(height_band[0]),
			float(height_band[1])) * scale \
			* float(layer.value("height_multiplier", 1.0))
		var blade_width := clampf(blade_height * rng.randf_range(0.26, 0.34),
			0.030, 0.085)
		var reach := blade_height * lean_strength \
			* rng.randf_range(0.5, 1.05) * (0.55 if against else 1.0)
		var root := centre + direction * crown_radius \
			* rng.randf_range(0.3, 1.0)
		var lean := Vector3(direction.x, 0.0, direction.y)
		var p0 := Vector3(root.x, crown_y - 0.014, root.y)
		var p1 := p0 + Vector3.UP * (blade_height * 0.45) \
			+ lean * (reach * 0.08)
		var p2 := p0 + Vector3.UP * (blade_height * 0.82) \
			+ lean * (reach * 0.45)
		var p3 := p0 + Vector3.UP * blade_height + lean * reach
		var key := dark_key
		if rng.randf() < 0.22:
			key = light_key
		# Low ring counts keep the blade CHUNKY — a sculpted wedge with a
		# soft diamond section, not a smooth capsule.
		TileKitMeshUtils.add_blade(batch, key, p0, p1, p2, p3, blade_width,
			rng.randf_range(0.42, 0.58), 5, 5, 2)


# --- GG moss compositions ---------------------------------------------------


## Moss is a MATERIAL RELATIONSHIP, not a family of green blobs. Each style
## owns a different substrate/coverage contract; the recipe supplies the
## matching palette keys while this builder owns the authored composition.
static func _build_moss_pads(layer: TileKitLayer,
		rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var style := String(layer.value("moss_patch_style", "gg_sheet_moss"))
	match style:
		"gg_rosette_moss":
			return _build_gg_rosette_moss(layer, rng, context)
		"gg_cloud_bank_moss":
			return _build_gg_cloud_bank_moss(layer, rng, context)
		"gg_mossy_garden_ground":
			return _build_gg_mossy_garden_ground(layer, rng, context)
		"gg_chenille_moss":
			return _build_gg_chenille_moss(layer, rng, context)
		"gg_cushion_moss":
			return _build_gg_cushion_moss(layer, rng, context)
		"gg_rolling_moss", "gg_brushed_moss":
			return _build_gg_rolling_moss(layer, rng, context)
		_:
			return _build_gg_sheet_moss(layer, rng, context)


## Direction A — botanical pincushion moss. Each low clay bun carries a chunky
## radial crown, the stylised equivalent of an acrocarp moss rosette. The
## authored scale hierarchy and empty pockets keep it from becoming a flower
## grid, while the moss foundation guarantees the whole tile remains ground.
static func _build_gg_rosette_moss(layer: TileKitLayer,
		rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var batch := TileKitMeshUtils.MeshBatch.new()
	var body := String(layer.value("primary_key", "moss_plush_body"))
	var light := String(layer.value("blade_key", "moss_plush_light"))
	var deep := String(layer.value("secondary_key", "moss_plush_deep"))
	var scale: float = layer.value("moss_detail_scale", 1.0)
	var height_scale: float = layer.value("moss_detail_height", 1.0)
	var rosettes := [
		[Vector2(-0.36, -0.18), 1.90, 7],
		[Vector2(0.26, 0.24), 1.62, 6],
		[Vector2(0.46, -0.39), 1.38, 6],
		[Vector2(-0.48, 0.43), 1.30, 5],
		[Vector2(0.00, -0.56), 1.18, 6],
		[Vector2(0.53, 0.55), 1.05, 5],
		[Vector2(-0.04, 0.59), 0.96, 5],
		[Vector2(-0.62, -0.55), 0.86, 5],
		[Vector2(0.62, 0.03), 0.82, 4],
		[Vector2(-0.62, 0.05), 0.74, 4],
	]
	var density: float = layer.value("moss_detail_density", 1.0)
	var count := clampi(roundi(float(rosettes.size()) * density), 7,
		rosettes.size())
	var placed: Array[Vector2] = []
	for index in count:
		var spec: Array = rosettes[index]
		var centre: Vector2 = spec[0]
		var size: float = float(spec[1]) * scale
		centre += Vector2(rng.randf_range(-0.022, 0.022),
			rng.randf_range(-0.022, 0.022))
		var surface_y := _surface_y(centre, top, cap_height)
		var bun_radius := 0.115 * size
		var bun_height := 0.052 * size * height_scale
		TileKitMeshUtils.add_lobed_mound(batch, deep,
			Vector3(centre.x, surface_y - 0.004, centre.y),
			bun_radius * 1.18, bun_radius, bun_height, rng.randf() * TAU,
			rng, 0.08, 6, 24, 0.94)
		_add_gg_moss_fan(batch, rng, centre,
			surface_y + bun_height * 0.62, size, height_scale,
			body, light, int(spec[2]))
		placed.append(centre)
	context["grass_clusters"] = placed
	return {
		"meshes": [{"role": "detail", "name": "tile_moss",
			"mesh": batch.commit()}],
	}


## Direction B — asymmetric cloud-bank moss. Each bank has one soft hero mass
## and a few rounded shoulder puffs, like a clay toy cloud settled into the
## blanket. Six strongly different scales make a family without a repeated
## stamp, while deliberate open moss keeps the composition calm.
static func _build_gg_cloud_bank_moss(layer: TileKitLayer,
		rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var batch := TileKitMeshUtils.MeshBatch.new()
	var body := String(layer.value("primary_key", "moss_plush_body"))
	var light := String(layer.value("blade_key", "moss_plush_light"))
	var deep := String(layer.value("secondary_key", "moss_plush_deep"))
	var scale: float = layer.value("moss_detail_scale", 1.0)
	var height_scale: float = layer.value("moss_detail_height", 1.0)
	var banks := [
		[Vector2(-0.26, -0.10), 1.28, 0, 6],
		[Vector2(0.33, 0.31), 0.96, 1, 5],
		[Vector2(0.39, -0.43), 0.70, 2, 4],
		[Vector2(-0.49, 0.45), 0.72, 0, 4],
		[Vector2(-0.08, 0.56), 0.55, 0, 3],
		[Vector2(0.59, 0.04), 0.48, 2, 3],
	]
	var density: float = layer.value("moss_detail_density", 1.0)
	var bank_count := clampi(roundi(float(banks.size()) * density), 3,
		banks.size())
	var placed: Array[Vector2] = []
	for bank_index in bank_count:
		var spec: Array = banks[bank_index]
		var centre: Vector2 = spec[0]
		centre += Vector2(rng.randf_range(-0.016, 0.016),
			rng.randf_range(-0.016, 0.016))
		var size: float = float(spec[1]) * scale
		var surface_y := _surface_y(centre, top, cap_height)
		var hero_height := 0.080 * size * height_scale
		var tone := int(spec[2])
		var key := light if tone == 1 else deep if tone == 2 else body
		TileKitMeshUtils.add_lobed_mound(batch, key,
			Vector3(centre.x, surface_y - hero_height * 0.12, centre.y),
			0.27 * size, 0.23 * size, hero_height, rng.randf() * TAU,
			rng, 0.08, 8, 34, 0.98)
		var shoulder_count := int(spec[3])
		for shoulder in shoulder_count:
			var angle := TAU * float(shoulder) / float(shoulder_count) \
				+ float(bank_index) * 0.79 + 0.24
			var reach := 0.205 * size * rng.randf_range(0.78, 1.08)
			var point := centre + Vector2(cos(angle), sin(angle)) * reach
			var point_y := _surface_y(point, top, cap_height)
			var puff_size := size * rng.randf_range(0.68, 1.02)
			var puff_key := deep if (shoulder + bank_index) % 5 == 0 else body
			TileKitMeshUtils.add_dome(batch, puff_key,
				Vector3(point.x, point_y - 0.009, point.y),
				0.090 * puff_size, 0.080 * puff_size,
				0.046 * puff_size * height_scale,
				rng.randf() * TAU, 7, 22)
		placed.append(centre)
	context["grass_clusters"] = placed
	return {"meshes": [{"role": "detail", "name": "tile_moss",
		"mesh": batch.commit()}]}


## Mossy garden ground — one continuous moss skin hugs the tile shell while a
## few pressed soil windows reveal the earth underneath. Broad rises sink into
## that skin instead of sitting on it as separate green props. Two stones and
## three short tufts give the miniature habitat character without turning each
## tile into a repeated centrepiece. All detail stays inside the top silhouette.
static func _build_gg_mossy_garden_ground(layer: TileKitLayer,
		rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var batch := TileKitMeshUtils.MeshBatch.new()
	var body := String(layer.value("primary_key", "moss_plush_body"))
	var light := String(layer.value("blade_key", "moss_plush_light"))
	var deep := String(layer.value("secondary_key", "moss_plush_deep"))
	var stone := String(layer.value("moss_stone_key", "stone_medium"))
	var stone_light := String(layer.value("moss_stone_light_key", "stone_light"))
	var soil := String(layer.value("moss_soil_key", "moss_ground_soil_top"))
	var soil_gradient := String(layer.value("moss_soil_gradient_key",
		"moss_ground_soil_gradient"))
	var soil_gradient_colors := [TileKitPalette.color(soil),
		TileKitPalette.color(body)]
	var scale: float = layer.value("moss_detail_scale", 1.0)
	var height_scale: float = layer.value("moss_detail_height", 1.0)
	var density: float = layer.value("moss_detail_density", 1.0)

	# One calm, irregular earth reveal gives the eye a focal area instead of a
	# chain of unrelated brown decals. Its rolled edge is mostly submerged.
	var reveal_point := Vector2(-0.14, 0.035)
	var reveal_height := 0.030 * height_scale
	var reveal_y := _surface_y(reveal_point, top, cap_height)
	TileKitMeshUtils.add_lobed_mound(batch, soil_gradient,
		Vector3(reveal_point.x, reveal_y - reveal_height * 0.74,
			reveal_point.y),
		0.31 * scale, 0.175 * scale, reveal_height, -0.18, rng,
		0.16, 8, 38, 0.98, soil_gradient_colors)
	# A smaller overlapping shoulder turns the opening into one asymmetric bean
	# shape rather than the procedural oval this primitive produces alone.
	var reveal_shoulder := Vector2(0.075, 0.095)
	var shoulder_y := _surface_y(reveal_shoulder, top, cap_height)
	TileKitMeshUtils.add_lobed_mound(batch, soil_gradient,
		Vector3(reveal_shoulder.x, shoulder_y - reveal_height * 0.76,
			reveal_shoulder.y),
		0.16 * scale, 0.105 * scale, reveal_height * 0.88, 0.28, rng,
		0.12, 8, 34, 0.98, soil_gradient_colors)
	# Secondary wear marks use a clear large-to-small hierarchy. They are
	# authored as quiet supporting beats, not an even scatter, and remain at
	# least 0.25 units inside the tile boundary at the largest editor scale.
	var soil_spots := [
		[Vector2(0.35, -0.22), 0.125, 0.078, 0.024, -0.18, 0.12],
		[Vector2(-0.42, 0.29), 0.078, 0.050, 0.019, 0.26, 0.10],
		[Vector2(0.25, 0.43), 0.048, 0.031, 0.015, -0.34, 0.08],
	]
	for spec: Array in soil_spots:
		var point: Vector2 = spec[0]
		var spot_height := float(spec[3]) * height_scale
		var point_y := _surface_y(point, top, cap_height)
		TileKitMeshUtils.add_lobed_mound(batch, soil_gradient,
			Vector3(point.x, point_y - spot_height * 0.78, point.y),
			float(spec[1]) * scale, float(spec[2]) * scale, spot_height,
			float(spec[4]), rng, float(spec[5]), 8, 30, 0.98,
			soil_gradient_colors)

	# Two cohesive cushion banks frame the reveal. Every crown is held inside a
	# conservative 0.60-unit safe zone—far inside the 0.85-unit tile boundary—
	# so rotation and lobe wobble cannot create an overhang.
	var crown_specs := [
		[Vector2(-0.34, -0.27), 0.23, 0.17, 0.066, 0, -0.12, 0.065],
		[Vector2(-0.20, -0.39), 0.13, 0.095, 0.044, 0, 0.18, 0.045],
		[Vector2(-0.47, -0.17), 0.10, 0.078, 0.037, 0, -0.24, 0.040],
		[Vector2(0.29, 0.25), 0.25, 0.18, 0.070, 0, 0.14, 0.060],
		[Vector2(0.43, 0.15), 0.12, 0.09, 0.041, 0, -0.16, 0.040],
		[Vector2(0.24, 0.40), 0.105, 0.080, 0.038, 0, 0.20, 0.040],
		[Vector2(0.36, -0.34), 0.11, 0.082, 0.040, 0, -0.10, 0.040],
	]
	var crown_count := clampi(roundi(float(crown_specs.size()) * density), 5,
		crown_specs.size())
	var placed: Array[Vector2] = []
	for index in crown_count:
		var spec: Array = crown_specs[index]
		var point: Vector2 = spec[0]
		var radius_x := float(spec[1]) * scale
		var radius_z := float(spec[2]) * scale
		# The authored values already fit, but this second guard also contains
		# editor scaling and future parameter changes.
		var safe_half := minf(0.60, half - 0.20)
		point.x = clampf(point.x, -safe_half + radius_x,
			safe_half - radius_x)
		point.y = clampf(point.y, -safe_half + radius_z,
			safe_half - radius_z)
		var crown_height := float(spec[3]) * height_scale
		var tone := int(spec[4])
		var key := light if tone == 1 else deep if tone == 2 else body
		var point_y := _surface_y(point, top, cap_height)
		TileKitMeshUtils.add_lobed_mound(batch, key,
			Vector3(point.x, point_y - crown_height * 0.55, point.y),
			radius_x, radius_z, crown_height, float(spec[5]), rng,
			float(spec[6]), 8, 34, 0.98)
		placed.append(point)

	# A deliberately small stone pair sits in the main soil opening. Keeping it
	# off-centre avoids the repeated emblem visible in a connected grid.
	var stones := [
		[Vector2(-0.105, 0.020), 0.082, 0.058, 0.033, -0.22, stone_light],
		[Vector2(0.015, 0.082), 0.043, 0.032, 0.023, 0.31, stone],
	]
	for spec: Array in stones:
		var point: Vector2 = spec[0]
		var point_y := _surface_y(point, top, cap_height)
		var half_x := float(spec[1]) * scale
		var half_z := float(spec[2]) * scale
		TileKitMeshUtils.add_slab(batch, String(spec[5]),
			Vector3(point.x, point_y + 0.002, point.y), half_x, half_z,
			minf(half_x, half_z) * 0.58, float(spec[3]) * height_scale,
			float(spec[4]), 0.012, 6)

	# Sparse grass rises from the moss skin. The roots are well inset and the
	# blades are short enough that their lean cannot cross the tile silhouette.
	var tuft_specs := [
		[Vector2(-0.35, -0.29), 1, 0.96],
		[Vector2(0.30, 0.27), 1, 0.90],
		[Vector2(0.36, -0.34), 0, 0.78],
	]
	var prevailing := -0.55
	var tuft_points: Array[Vector2] = []
	for spec: Array in tuft_specs:
		var point: Vector2 = spec[0]
		var point_y := _surface_y(point, top, cap_height) + 0.024 * height_scale
		_build_tuft(batch, layer, rng, point, point_y, int(spec[1]),
			float(spec[2]) * scale, prevailing, 0.48, body, light)
		tuft_points.append(point)
	context["grass_clusters"] = tuft_points
	return {"meshes": [{"role": "detail", "name": "tile_mossy_ground",
		"mesh": batch.commit()}]}


## Direction C — chenille moss. A heavily jittered full-footprint weave of low
## rounded fibres creates a plush rug silhouette. A broad size field disrupts
## the lattice, and the fibres are wider than tall so they read soft, never as
## eggs, spikes, gravel, or a sparse group of props.
static func _build_gg_chenille_moss(layer: TileKitLayer,
		rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var batch := TileKitMeshUtils.MeshBatch.new()
	var body := String(layer.value("primary_key", "moss_plush_body"))
	var light := String(layer.value("blade_key", "moss_plush_light"))
	var deep := String(layer.value("secondary_key", "moss_plush_deep"))
	var scale: float = layer.value("moss_detail_scale", 1.0)
	var height_scale: float = layer.value("moss_detail_height", 1.0)
	var density: float = layer.value("moss_detail_density", 1.0)
	var placed: Array[Vector2] = []
	var columns := clampi(roundi(8.0 * density), 7, 9)
	var spacing := 1.46 / float(columns - 1)
	for row in columns:
		for column in columns:
			if rng.randf() < 0.055:
				continue
			var point := Vector2(-0.73 + column * spacing,
				-0.73 + row * spacing)
			point += Vector2(rng.randf_range(-spacing * 0.34, spacing * 0.34),
				rng.randf_range(-spacing * 0.34, spacing * 0.34))
			point.x = clampf(point.x, -0.76, 0.76)
			point.y = clampf(point.y, -0.76, 0.76)
			var surface_y := _surface_y(point, top, cap_height)
			var broad_scale := 1.0 + sin(point.x * 3.7 + point.y * 2.1) * 0.18 \
				+ cos(point.y * 4.3 - 0.6) * 0.12
			var fibre_scale := rng.randf_range(0.82, 1.18) * scale * broad_scale
			var chance := rng.randf()
			var key := light if chance < 0.08 else deep if chance < 0.18 else body
			TileKitMeshUtils.add_dome(batch, key,
				Vector3(point.x, surface_y - 0.008, point.y),
				0.083 * fibre_scale, 0.073 * fibre_scale,
				0.052 * fibre_scale * height_scale,
				rng.randf() * TAU, 6, 16)
			placed.append(point)
	context["grass_clusters"] = placed
	return {"meshes": [{"role": "detail", "name": "tile_moss",
		"mesh": batch.commit()}]}


## A — sheet moss. The whole foundation is moss, then a few very broad, barely
## raised moss sheets change the nap and value. Their low overlapping edges
## read as one thick living carpet rather than coloured decals on bare ground.
static func _build_gg_sheet_moss(layer: TileKitLayer,
		rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var cap_height: Callable = context.get("cap_height", Callable())
	var batch := TileKitMeshUtils.MeshBatch.new()
	var primary := String(layer.value("primary_key", "moss_sheet_top"))
	var secondary := String(layer.value("secondary_key", "moss_sheet_bevel"))
	var scale: float = layer.value("moss_detail_scale", 1.0)
	var height_scale: float = layer.value("moss_detail_height", 1.0)
	var density: float = layer.value("moss_detail_density", 1.0)
	var count := clampi(roundi(5.0 * density), 4, 7)
	var placed: Array[Vector2] = []
	for index in count:
		# The first sheets are deliberately dominant; later sheets fill the
		# negative spaces at another scale so no repeated polka-dot rhythm forms.
		var major := rng.randf_range(0.47, 0.72) * scale
		if index >= 3:
			major *= rng.randf_range(0.66, 0.86)
		var minor := major * rng.randf_range(0.58, 0.86)
		var reach := maxf(0.12, half - major * 0.54)
		var centre := Vector2(rng.randf_range(-reach, reach),
			rng.randf_range(-reach, reach))
		# Bias alternate sheets toward different quadrants without pinning them
		# to a grid. Runtime quarter-turn variants break the repeated orientation.
		if index < 3:
			var angle := rng.randf() * TAU + float(index) * TAU / 3.0
			centre += Vector2(cos(angle), sin(angle)) * rng.randf_range(0.12, 0.30)
			centre.x = clampf(centre.x, -half * 0.82, half * 0.82)
			centre.y = clampf(centre.y, -half * 0.82, half * 0.82)
		var outline := TileKitMeshUtils.soft_blob_outline(rng, 26, 0.22, 4)
		TileKitMeshUtils.add_cushion_blob(batch,
			secondary if index == count - 1 else primary,
			centre, 0.002, major, minor, rng.randf() * TAU, outline,
			cap_height, rng.randf_range(0.014, 0.026) * height_scale, 0.92)
		placed.append(centre)
	context["grass_clusters"] = placed
	return {
		"meshes": [{"role": "detail", "name": "tile_moss",
			"mesh": batch.commit()}],
	}


## B — cushion moss. Uneven families of broad rounded hummocks grow directly
## out of a moss foundation. There is deliberately no row/column lattice: size,
## spacing, overlap and tone all vary, while the high segment count keeps the
## forms soft and clay-like instead of jagged or bean-shaped.
static func _build_gg_cushion_moss(layer: TileKitLayer,
		rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var batch := TileKitMeshUtils.MeshBatch.new()
	var primary := String(layer.value("primary_key", "moss_cushion_body"))
	var light := String(layer.value("blade_key", "moss_cushion_light"))
	var scale: float = layer.value("moss_detail_scale", 1.0)
	var height_scale: float = layer.value("moss_detail_height", 1.0)
	var density: float = layer.value("moss_detail_density", 1.0)
	var placed: Array[Vector2] = []
	var count := clampi(roundi(16.0 * density), 13, 20)
	for index in count:
		var large := index < 5
		var radius_x := rng.randf_range(0.50, 0.69) if large \
			else rng.randf_range(0.21, 0.41)
		radius_x *= scale
		var radius_z := radius_x * rng.randf_range(0.78, 1.08)
		var reach_x := maxf(0.08, half - radius_x * 0.48)
		var reach_z := maxf(0.08, half - radius_z * 0.48)
		var position := Vector2(rng.randf_range(-reach_x, reach_x),
			rng.randf_range(-reach_z, reach_z))
		var surface_y := _surface_y(position, top, cap_height)
		var height := (rng.randf_range(0.034, 0.058) if large \
			else rng.randf_range(0.025, 0.050)) * height_scale
		var key := light if rng.randf() < 0.10 else primary
		TileKitMeshUtils.add_lobed_mound(batch, key,
			Vector3(position.x, surface_y - height * 0.16, position.y),
			radius_x, radius_z, height, rng.randf() * TAU, rng,
			rng.randf_range(0.12, 0.18), 7, 28, 0.92)
		placed.append(position)
	context["grass_clusters"] = placed
	return {
		"meshes": [{"role": "detail", "name": "tile_moss",
			"mesh": batch.commit()}],
	}


## C — rolling moss. A few huge, shallow swells share the foundation colour,
## so the change is sculpted into the moss itself. This is the quietest option:
## broad terrain-like variation without elongated strips, separate objects, or
## a repeated cushion-cell pattern.
static func _build_gg_rolling_moss(layer: TileKitLayer,
		rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var batch := TileKitMeshUtils.MeshBatch.new()
	var primary := String(layer.value("primary_key", "moss_shag_body"))
	var light := String(layer.value("blade_key", "moss_shag_light"))
	var scale: float = layer.value("moss_detail_scale", 1.0)
	var height_scale: float = layer.value("moss_detail_height", 1.0)
	var density: float = layer.value("moss_detail_density", 1.0)
	var count := clampi(roundi(7.0 * density), 6, 9)
	var placed: Array[Vector2] = []
	for index in count:
		var dominant := index < 3
		var radius_x := (rng.randf_range(0.62, 0.82) if dominant \
			else rng.randf_range(0.36, 0.56)) * scale
		var radius_z := radius_x * rng.randf_range(0.76, 1.08)
		var position := Vector2(rng.randf_range(-half * 0.62, half * 0.62),
			rng.randf_range(-half * 0.62, half * 0.62))
		var surface_y := _surface_y(position, top, cap_height)
		var height := (rng.randf_range(0.025, 0.043) if dominant \
			else rng.randf_range(0.018, 0.034)) * height_scale
		TileKitMeshUtils.add_lobed_mound(batch,
			light if index == count - 1 else primary,
			Vector3(position.x, surface_y - height * 0.18, position.y),
			radius_x, radius_z, height, rng.randf() * TAU, rng,
			rng.randf_range(0.10, 0.16), 7, 30, 0.94)
		placed.append(position)
	context["grass_clusters"] = placed
	return {
		"meshes": [{"role": "detail", "name": "tile_moss",
			"mesh": batch.commit()}],
	}


## C — shag moss. The base is still moss; chunky rounded stems create the
## plush nap. Stems gather in broad regularised clusters so the result reads
## as one material rather than granular scatter or leaf litter.
static func _build_gg_shag_moss(layer: TileKitLayer,
		rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var batch := TileKitMeshUtils.MeshBatch.new()
	var primary := String(layer.value("primary_key", "moss_shag_body"))
	var light := String(layer.value("blade_key", "moss_shag_light"))
	var scale: float = layer.value("moss_detail_scale", 1.0)
	var height_scale: float = layer.value("moss_detail_height", 1.0)
	var density: float = layer.value("moss_detail_density", 1.0)
	var columns := clampi(int(round(5.0 * density)), 4, 6)
	var spacing := (half * 1.72) / float(columns - 1)
	var start := -spacing * float(columns - 1) * 0.5
	var placed: Array[Vector2] = []
	for row in columns:
		for column in columns:
			var centre := Vector2(start + column * spacing,
				start + row * spacing) + Vector2(
				rng.randf_range(-0.045, 0.045),
				rng.randf_range(-0.045, 0.045))
			for stem in 3:
				var angle := rng.randf() * TAU
				var position := centre + Vector2(cos(angle), sin(angle)) \
					* rng.randf_range(0.018, 0.055) * scale
				var surface_y := _surface_y(position, top, cap_height)
				var radius := rng.randf_range(0.042, 0.058) * scale
				TileKitMeshUtils.add_dome(batch,
					light if stem == 0 and rng.randf() < 0.22 else primary,
					Vector3(position.x, surface_y - 0.006, position.y),
					radius, radius * rng.randf_range(0.86, 1.08),
					rng.randf_range(0.060, 0.088) * height_scale,
					rng.randf() * TAU, 4, 10)
			placed.append(centre)
	context["grass_clusters"] = placed
	return {
		"meshes": [{"role": "detail", "name": "tile_moss",
			"mesh": batch.commit()}],
	}


## A — warm stone with one moss sheet growing in from a corner. The boundary
## is a smooth cubic sweep with a narrow darker lip; a single stone chip on the
## open face gives the tile one restrained piece of personality.
static func _build_gg_stone_creep(layer: TileKitLayer,
		rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var batch := TileKitMeshUtils.MeshBatch.new()
	var growth := String(layer.value("primary_key", "moss_gg_stone_growth"))
	var lip := String(layer.value("blade_key", "moss_gg_stone_edge"))
	var chip := String(layer.value("secondary_key", "moss_gg_stone_chip"))
	var scale: float = layer.value("moss_detail_scale", 1.0)
	var height: float = layer.value("moss_detail_height", 1.0)
	var quarter := rng.randi() % 4
	_add_gg_corner_sheet(batch, growth, lip, half, top, quarter, rng,
		cap_height, scale, height)
	var chip_local := _rotate_quarter(Vector2(0.42, 0.36) * half, quarter)
	var chip_y := _surface_y(chip_local, top, cap_height)
	TileKitMeshUtils.add_faceted_chunk(batch, chip,
		Vector3(chip_local.x, chip_y + 0.002, chip_local.y),
		0.085, 0.055, 0.018, rng.randf() * TAU, rng, 6, 0.10, 0.82)
	context["grass_clusters"] = [chip_local]
	return {
		"meshes": [{"role": "detail", "name": "tile_moss",
			"mesh": batch.commit()}],
	}


## B — the moss is a single dense bank of short, broad GG-style leaf wedges
## growing over warm soil. Open ground remains deliberate; two dark clods sit
## opposite the bank rather than distributing noise over the whole surface.
static func _build_gg_earth_bank(layer: TileKitLayer,
		rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var batch := TileKitMeshUtils.MeshBatch.new()
	var primary := String(layer.value("primary_key", "moss_gg_earth_growth"))
	var highlight := String(layer.value("blade_key", "moss_gg_earth_highlight"))
	var clod := String(layer.value("secondary_key", "dirt_clay_chip_dark"))
	var scale: float = layer.value("moss_detail_scale", 1.0)
	var height: float = layer.value("moss_detail_height", 1.0)
	var density: float = layer.value("moss_detail_density", 1.0)
	var quarter := rng.randi() % 4
	var template := [Vector2(-0.58, -0.48), Vector2(-0.25, -0.61),
		Vector2(0.10, -0.56), Vector2(-0.53, -0.17),
		Vector2(-0.22, -0.31), Vector2(0.10, -0.29),
		Vector2(-0.39, 0.05), Vector2(0.29, -0.48)]
	var sizes := [1.18, 0.82, 0.62, 0.96, 0.72, 0.52, 0.58, 0.48]
	var count := clampi(int(round(template.size() * density)), 3, template.size())
	var placed: Array[Vector2] = []
	for index in count:
		var position := _template_point(template[index], quarter, rng, half, 1.0)
		var surface_y := _surface_y(position, top, cap_height)
		_add_gg_moss_fan(batch, rng, position, surface_y,
			float(sizes[index]) * scale, height, primary, highlight,
			3 + (rng.randi() % 2))
		placed.append(position)
	for clod_point in [Vector2(0.43, 0.34), Vector2(0.58, 0.08)]:
		var position := _rotate_quarter(clod_point * half, quarter)
		var surface_y := _surface_y(position, top, cap_height)
		TileKitMeshUtils.add_faceted_chunk(batch, clod,
			Vector3(position.x, surface_y + 0.001, position.y),
			rng.randf_range(0.045, 0.070), rng.randf_range(0.032, 0.050),
			rng.randf_range(0.010, 0.018), rng.randf() * TAU, rng, 5, 0.12, 0.78)
	context["grass_clusters"] = placed
	return {
		"meshes": [{"role": "detail", "name": "tile_moss",
			"mesh": batch.commit()}],
	}


## C — the entire top is moss; detail is only a handful of low cross-sprouts
## in a deeper tone. There is no second moss layer and therefore no blob read.
static func _build_gg_living_carpet(layer: TileKitLayer,
		rng: RandomNumberGenerator, context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var batch := TileKitMeshUtils.MeshBatch.new()
	var primary := String(layer.value("primary_key", "moss_gg_carpet_detail"))
	var highlight := String(layer.value("blade_key", "moss_gg_carpet_highlight"))
	var scale: float = layer.value("moss_detail_scale", 1.0)
	var height: float = layer.value("moss_detail_height", 1.0)
	var density: float = layer.value("moss_detail_density", 1.0)
	var quarter := rng.randi() % 4
	var template := [Vector2(-0.56, -0.27), Vector2(0.28, -0.52),
		Vector2(0.50, 0.18), Vector2(-0.17, 0.45),
		Vector2(-0.06, -0.02), Vector2(0.55, 0.52)]
	var sizes := [0.72, 0.48, 0.62, 0.42, 0.55, 0.38]
	var count := clampi(int(round(template.size() * density)), 2, template.size())
	var placed: Array[Vector2] = []
	for index in count:
		var position := _template_point(template[index], quarter, rng, half, 1.0)
		var surface_y := _surface_y(position, top, cap_height)
		_add_gg_moss_fan(batch, rng, position, surface_y,
			float(sizes[index]) * scale, height * 0.72,
			primary, highlight, 3)
		placed.append(position)
	context["grass_clusters"] = placed
	return {
		"meshes": [{"role": "detail", "name": "tile_moss",
			"mesh": batch.commit()}],
	}


static func _surface_y(position: Vector2, top: float,
		cap_height: Callable) -> float:
	return top + (float(cap_height.call(position)) if cap_height.is_valid() else 0.0)


static func _rotate_quarter(point: Vector2, quarter: int) -> Vector2:
	var result := point
	for turn in quarter:
		result = Vector2(-result.y, result.x)
	return result


## Smooth corner sheet: two tile edges and one cubic inner boundary. The top
## uses sky-facing normals; only the exposed inner curve receives a darker lip.
static func _add_gg_corner_sheet(batch: TileKitMeshUtils.MeshBatch,
		top_key: String, lip_key: String, half: float, top: float, quarter: int,
		rng: RandomNumberGenerator, cap_height: Callable,
		scale: float, height_scale: float) -> void:
	var reach_x := half * rng.randf_range(0.42, 0.56) * scale
	var reach_z := half * rng.randf_range(0.12, 0.28) * scale
	var p0 := Vector2(reach_x, -half + 0.010)
	var p1 := Vector2(half * rng.randf_range(0.26, 0.40),
		-half * rng.randf_range(0.38, 0.50))
	var p2 := Vector2(-half * rng.randf_range(0.30, 0.44),
		half * rng.randf_range(0.06, 0.20))
	var p3 := Vector2(-half + 0.010, reach_z)
	var outline: Array[Vector2] = [_rotate_quarter(
		Vector2(-half + 0.010, -half + 0.010), quarter),
		_rotate_quarter(p0, quarter)]
	for step in 16:
		var t := float(step + 1) / 16.0
		var inverse := 1.0 - t
		var point := p0 * pow(inverse, 3.0) \
			+ p1 * (3.0 * pow(inverse, 2.0) * t) \
			+ p2 * (3.0 * inverse * t * t) + p3 * pow(t, 3.0)
		outline.append(_rotate_quarter(point, quarter))
	var thickness := 0.024 * height_scale
	var centre := Vector2.ZERO
	for point in outline:
		centre += point
	centre /= float(outline.size())
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.append(Vector3(centre.x,
		_surface_y(centre, top, cap_height) + thickness, centre.y))
	normals.append(Vector3.UP)
	for point in outline:
		vertices.append(Vector3(point.x,
			_surface_y(point, top, cap_height) + thickness, point.y))
		normals.append(Vector3.UP)
	for index in outline.size():
		indices.append_array([0, 1 + index, 1 + (index + 1) % outline.size()])
	batch.add(top_key, vertices, normals, indices)
	# Outline index 1 is p0; every following edge through the last point is
	# the exposed cubic boundary. The two tile-boundary legs stay open/flush.
	for index in range(1, outline.size() - 1):
		var a := outline[index]
		var b := outline[index + 1]
		var bottom_a := Vector3(a.x, _surface_y(a, top, cap_height) + 0.002, a.y)
		var bottom_b := Vector3(b.x, _surface_y(b, top, cap_height) + 0.002, b.y)
		var top_a := bottom_a + Vector3.UP * (thickness - 0.002)
		var top_b := bottom_b + Vector3.UP * (thickness - 0.002)
		TileKitMeshUtils.add_flat_triangle(batch, lip_key,
			bottom_a, top_b, top_a)
		TileKitMeshUtils.add_flat_triangle(batch, lip_key,
			bottom_a, bottom_b, top_b)


## Short, broad, nearly horizontal leaves: chunky enough for GG's toy-clay
## read, but low enough to read as moss rather than meadow grass.
static func _add_gg_moss_fan(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, centre: Vector2, surface_y: float,
		scale: float, height_scale: float, primary: String, highlight: String,
		leaf_count: int) -> void:
	var base_yaw := rng.randf() * TAU
	for leaf in leaf_count:
		var yaw := base_yaw + TAU * float(leaf) / float(leaf_count) \
			+ rng.randf_range(-0.24, 0.24)
		var direction := Vector2(cos(yaw), sin(yaw))
		var height := rng.randf_range(0.052, 0.072) * scale * height_scale
		var reach := height * rng.randf_range(0.82, 1.05)
		var root := centre + direction * rng.randf_range(0.004, 0.014) * scale
		var lean := Vector3(direction.x, 0.0, direction.y)
		var p0 := Vector3(root.x, surface_y - 0.006, root.y)
		var p1 := p0 + Vector3.UP * (height * 0.34) + lean * (reach * 0.10)
		var p2 := p0 + Vector3.UP * (height * 0.72) + lean * (reach * 0.58)
		var p3 := p0 + Vector3.UP * (height * 0.56) + lean * reach
		TileKitMeshUtils.add_blade(batch,
			highlight if leaf == 0 and rng.randf() < 0.34 else primary,
			p0, p1, p2, p3, rng.randf_range(0.044, 0.060) * scale,
			0.62, 5, 6, 2, 0.58)


# --- turf: sculpted carpet mode ----------------------------------------------


## The premium grass read: the top of the tile IS the vegetation. A dense bed
## of low interlocking lobed mounds forms one continuous sculpted turf whose
## silhouette is lumpy and alive; a fraction of mounds sprout a few short broad
## blades rooted INSIDE the mound (tips breaking the surface, never hair plugs
## on a board); one to three taller accent clumps give the tile a focal point.
## Rim mounds push slightly outward so the carpet laps over the bevel the way
## moss creeps over a wall — repetition then reads as one land mass.
static func _build_turf(layer: TileKitLayer, rng: RandomNumberGenerator,
		context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var batch := TileKitMeshUtils.MeshBatch.new()

	var spacing: float = layer.value("turf_spacing", 0.26)
	var jitter: float = layer.value("carpet_jitter", 0.30)
	var skip: float = layer.value("turf_skip_fraction", 0.10)
	var footprint_band: Array = layer.value("turf_footprint", [0.22, 0.34])
	var height_band: Array = layer.value("turf_height", [0.030, 0.055])
	var lobe_depth: float = layer.value("turf_lobe_depth", 0.20)
	var overhang: float = layer.value("turf_overhang", 0.035)
	var blade_fraction: float = layer.value("blade_fraction", 0.42)
	var blades_band: Array = layer.value("blades_per_tuft", [2, 4])
	var accent_band: Array = layer.value("accent_clumps", [1, 2])
	# Turf mounds live in the TOP's own colour family — the carpet must read
	# as one thick material, never as patches shingled over a different green.
	# Blades take a deliberately deeper tone so the sculpted tips punctuate.
	var primary := String(layer.value("primary_key", "tile_top"))
	var secondary := String(layer.value("secondary_key", "dressing_medium"))
	var blade_key := String(layer.value("blade_key", "grass_primary"))
	var secondary_fraction: float = layer.value("secondary_fraction", 0.24)
	var height_multiplier: float = layer.value("height_multiplier", 1.0)

	var stones: Array = context.get("paver_stones", [])
	var mounds: Array = []
	var columns := maxi(2, int(floor((half * 2.0) / spacing)))
	var start := -(float(columns) - 1.0) * 0.5 * spacing
	for row in columns:
		for column in columns:
			if rng.randf() < skip:
				continue
			var centre := Vector2(
				start + column * spacing
					+ rng.randf_range(-jitter, jitter) * spacing,
				start + row * spacing
					+ rng.randf_range(-jitter, jitter) * spacing
			)
			# Rim mounds migrate OUTWARD: the carpet overhangs the bevel a
			# touch instead of stopping short of it with a bald strip.
			var rim_distance := half - maxf(absf(centre.x), absf(centre.y))
			if rim_distance < spacing * 0.8:
				var push := (1.0 - rim_distance / (spacing * 0.8)) * overhang
				centre += centre.normalized() * push if centre.length() > 0.01 \
					else Vector2.ZERO
			var limit := half + overhang
			centre.x = clampf(centre.x, -limit, limit)
			centre.y = clampf(centre.y, -limit, limit)
			if _blocked_by_stone(centre, stones, 0.04):
				continue
			var footprint := rng.randf_range(float(footprint_band[0]),
				float(footprint_band[1]))
			mounds.append({
				"centre": centre,
				"footprint": footprint,
				"height": rng.randf_range(float(height_band[0]),
					float(height_band[1])) * height_multiplier,
				"yaw": rng.randf() * TAU,
				"aspect": rng.randf_range(0.78, 1.0),
			})

	for mound: Dictionary in mounds:
		var centre: Vector2 = mound["centre"]
		var surface_y := top
		if cap_height.is_valid():
			var clamped := Vector2(clampf(centre.x, -half, half),
				clampf(centre.y, -half, half))
			surface_y = top + float(cap_height.call(clamped))
		var footprint: float = mound["footprint"]
		var mound_height: float = mound["height"]
		var key := secondary if rng.randf() < secondary_fraction else primary
		# Sunk a whisker so every mound meets the ground in a soft contact
		# line — turf grows FROM the tile, it is not shingled onto it.
		TileKitMeshUtils.add_lobed_mound(batch, key,
			Vector3(centre.x, surface_y - mound_height * 0.10, centre.y),
			footprint * 0.5, footprint * 0.5 * float(mound["aspect"]),
			mound_height, float(mound["yaw"]), rng, lobe_depth)
		# A fraction of mounds sprout short broad blades from within the
		# mound body — sculpted tips that break the carpet silhouette.
		if rng.randf() < blade_fraction:
			var blade_count := rng.randi_range(int(blades_band[0]),
				int(blades_band[1]))
			_add_tuft_blades(batch, layer, rng, centre, footprint,
				surface_y + mound_height * 0.55, blade_count, 1.0,
				blade_key, secondary)

	# Accent clumps: the tile's few deliberate taller features, kept off the
	# rim so their silhouette belongs to this tile alone.
	var accents := rng.randi_range(int(accent_band[0]), int(accent_band[1]))
	var accent_positions: Array[Vector2] = []
	for accent in accents:
		var position := Vector2(rng.randf_range(-half * 0.62, half * 0.62),
			rng.randf_range(-half * 0.62, half * 0.62))
		var clear := true
		for existing in accent_positions:
			if existing.distance_to(position) < half * 0.6:
				clear = false
				break
		if not clear or _blocked_by_stone(position, stones, 0.08):
			continue
		accent_positions.append(position)
		var surface_y := top
		if cap_height.is_valid():
			surface_y = top + float(cap_height.call(position))
		var footprint := rng.randf_range(0.16, 0.24)
		var mound_height := rng.randf_range(float(height_band[1]),
			float(height_band[1]) * 1.5) * height_multiplier
		TileKitMeshUtils.add_lobed_mound(batch, primary,
			Vector3(position.x, surface_y - mound_height * 0.1, position.y),
			footprint * 0.62, footprint * 0.55, mound_height,
			rng.randf() * TAU, rng, lobe_depth * 1.2)
		_add_tuft_blades(batch, layer, rng, position, footprint,
			surface_y + mound_height * 0.6, rng.randi_range(4, 6), 1.35,
			blade_key, secondary)

	context["grass_clusters"] = mounds
	return {
		"meshes": [{"role": "detail", "name": "tile_grass",
			"mesh": batch.commit()}],
	}


## Short broad curved blades rooted inside a turf mound. Roots start well
## below the mound crown so every blade emerges from the mass — the exact
## opposite of the retired hair-plug read.
static func _add_tuft_blades(batch: TileKitMeshUtils.MeshBatch,
		layer: TileKitLayer, rng: RandomNumberGenerator, centre: Vector2,
		footprint: float, crown_y: float, blade_count: int,
		scale: float, primary: String, secondary: String) -> void:
	var height_band: Array = layer.value("leaf_height", [0.075, 0.130])
	var width_band: Array = layer.value("leaf_width", [0.050, 0.080])
	var thickness_band: Array = layer.value("thickness_ratio", [0.50, 0.68])
	var base_yaw := rng.randf() * TAU
	for blade in blade_count:
		var yaw := base_yaw + TAU * float(blade) / float(blade_count) \
			+ rng.randf_range(-0.5, 0.5)
		var direction := Vector2(cos(yaw), sin(yaw))
		var root := centre + direction * footprint * rng.randf_range(0.06, 0.22)
		var blade_height := rng.randf_range(float(height_band[0]),
			float(height_band[1])) * scale * rng.randf_range(0.8, 1.2)
		var blade_width := minf(
			rng.randf_range(float(width_band[0]), float(width_band[1])) * scale,
			blade_height * 0.45)
		var reach := blade_height * rng.randf_range(0.35, 0.75)
		var lean := Vector3(direction.x, 0.0, direction.y)
		var p0 := Vector3(root.x, crown_y - footprint * 0.28, root.y)
		var p1 := p0 + Vector3.UP * (blade_height * 0.42) + lean * (reach * 0.10)
		var p2 := p0 + Vector3.UP * (blade_height * 0.78) + lean * (reach * 0.52)
		var p3 := p0 + Vector3.UP * blade_height + lean * reach
		var key := secondary if rng.randf() < 0.3 else primary
		TileKitMeshUtils.add_blade(batch, key, p0, p1, p2, p3, blade_width,
			rng.randf_range(float(thickness_band[0]),
				float(thickness_band[1])), 8, 10, 3)


static func _blocked_by_stone(centre: Vector2, stones: Array,
		clearance: float) -> bool:
	for stone: Dictionary in stones:
		var delta: Vector2 = centre - (stone["centre"] as Vector2)
		if absf(delta.x) < float(stone["half_x"]) + clearance \
				and absf(delta.y) < float(stone["half_z"]) + clearance:
			return true
	return false


# --- composition -------------------------------------------------------------


## Draws candidate layouts until one is honestly asymmetrical and keeps the
## open-space promise, keeping the best-scoring fallback so a hostile seed
## still terminates with the least-bad layout instead of hanging.
static func _compose(layer: TileKitLayer, rng: RandomNumberGenerator,
		half: float) -> Array:
	var counts := [
		int(layer.value("large_clusters", 1)),
		int(layer.value("medium_clusters", 3)),
		int(layer.value("small_clusters", 2)),
	]
	var footprints := [
		layer.value("large_footprint", [0.24, 0.36]),
		layer.value("medium_footprint", [0.15, 0.26]),
		layer.value("small_footprint", [0.085, 0.15]),
	]
	var margin: float = layer.value("preferred_edge_margin", 0.12)
	var spread: float = layer.value("cluster_spread", 0.85)
	var open_target: float = layer.value("open_space_target", 0.52)

	var best: Array = []
	var best_score := INF
	for attempt in MAX_COMPOSITION_ATTEMPTS:
		var template: Array = TEMPLATES[rng.randi() % TEMPLATES.size()]
		var anchors := template.duplicate()
		anchors.shuffle()
		var candidate: Array = []
		var anchor_index := 0
		var valid := true
		for size_class in 3:
			for instance in counts[size_class]:
				var band: Array = footprints[size_class]
				var footprint: float = rng.randf_range(band[0], band[1])
				var anchor: Array = anchors[anchor_index % anchors.size()]
				anchor_index += 1
				# Prefer anchors of the matching size class when available.
				for probe: Array in anchors:
					if int(probe[2]) == size_class and not _anchor_used(candidate, probe, half, spread):
						anchor = probe
						break
				var limit := half - margin - footprint * 0.5
				if limit <= 0.0:
					valid = false
					break
				var centre := Vector2(
					clampf(float(anchor[0]) * half * spread
						+ rng.randf_range(-0.08, 0.08), -limit, limit),
					clampf(float(anchor[1]) * half * spread
						+ rng.randf_range(-0.08, 0.08), -limit, limit)
				)
				# Footprint overlap: nudge apart once, then reject.
				for existing: Dictionary in candidate:
					var minimum: float = (footprint + float(existing["footprint"])) * 0.42
					var delta: Vector2 = centre - (existing["centre"] as Vector2)
					if delta.length() < minimum:
						centre += delta.normalized() * (minimum - delta.length() + 0.02) \
							if delta.length() > 0.001 else Vector2(minimum, 0.0)
				centre.x = clampf(centre.x, -limit, limit)
				centre.y = clampf(centre.y, -limit, limit)
				for existing: Dictionary in candidate:
					var minimum: float = (footprint + float(existing["footprint"])) * 0.40
					if centre.distance_to(existing["centre"]) < minimum:
						valid = false
						break
				if not valid:
					break
				candidate.append({
					"centre": centre,
					"footprint": footprint,
					"size_class": size_class,
					"lean_yaw": rng.randf() * TAU,
					"aspect": rng.randf_range(0.72, 1.0),
					"yaw": rng.randf() * TAU,
				})
			if not valid:
				break
		if not valid or candidate.is_empty():
			continue
		var score := _composition_penalty(candidate, half, open_target)
		if score < best_score:
			best_score = score
			best = candidate
		if score < 0.08:
			break
	return best


static func _anchor_used(candidate: Array, anchor: Array, half: float,
		spread: float) -> bool:
	var position := Vector2(float(anchor[0]), float(anchor[1])) * half * spread
	for existing: Dictionary in candidate:
		if position.distance_to(existing["centre"]) < 0.12:
			return true
	return false


## Penalty for the compositions the brief forbids: balanced quadrants,
## occupied corners everywhere, mirrored halves, and open space off target.
static func _composition_penalty(candidate: Array, half: float,
		open_target: float) -> float:
	var quadrant_weight := [0.0, 0.0, 0.0, 0.0]
	var corners := [false, false, false, false]
	var covered := 0.0
	for cluster: Dictionary in candidate:
		var centre: Vector2 = cluster["centre"]
		var footprint: float = cluster["footprint"]
		var area := PI * pow(footprint * 0.5, 2.0)
		covered += area
		var quadrant := (0 if centre.x < 0.0 else 1) + (0 if centre.y < 0.0 else 2)
		quadrant_weight[quadrant] += area
		if absf(centre.x) > half * 0.5 and absf(centre.y) > half * 0.5:
			corners[quadrant] = true

	var penalty := 0.0
	var total_weight: float = quadrant_weight[0] + quadrant_weight[1] \
		+ quadrant_weight[2] + quadrant_weight[3]
	if total_weight > 0.0:
		var mean := total_weight / 4.0
		var deviation := 0.0
		for weight: float in quadrant_weight:
			deviation += absf(weight - mean)
		# LOW deviation means evenly balanced quadrants — the machine look.
		penalty += maxf(0.0, 0.9 - deviation / total_weight) * 0.5
	if corners[0] and corners[1] and corners[2] and corners[3]:
		penalty += 1.0
	# Mirror check: a cluster whose reflection also holds a cluster.
	for cluster: Dictionary in candidate:
		var centre: Vector2 = cluster["centre"]
		for other: Dictionary in candidate:
			if other == cluster:
				continue
			if centre.distance_to(Vector2(-(other["centre"] as Vector2).x,
					(other["centre"] as Vector2).y)) < 0.10 \
				or centre.distance_to(Vector2((other["centre"] as Vector2).x,
					-(other["centre"] as Vector2).y)) < 0.10:
				penalty += 0.25
	var tile_area := pow(half * 2.0, 2.0)
	var open_fraction := 1.0 - covered / tile_area
	penalty += absf(open_fraction - open_target) * 1.5
	return penalty


# --- cluster geometry --------------------------------------------------------


## One sprout rosette: leaves splaying outward from a shared crown, evenly
## spaced around the circle with jitter, plus a near-vertical centre leaf.
##
## Even spacing is what makes every rosette read as the SAME plant — the
## coherence that lets a tile repeat across a land mass — while the yaw
## jitter, size wobble, and random rotation keep any two from being copies.
static func _build_rosette(batch: TileKitMeshUtils.MeshBatch,
		layer: TileKitLayer, rng: RandomNumberGenerator,
		cluster: Dictionary, top: float, cap_height: Callable) -> void:
	var centre: Vector2 = cluster["centre"]
	var footprint: float = cluster["footprint"]
	var rosette_yaw: float = cluster["yaw"]

	var leaf_band: Array = layer.value("rosette_leaves", [4, 6])
	var leaf_count := rng.randi_range(int(leaf_band[0]), int(leaf_band[1]))
	var height_band: Array = layer.value("leaf_height", [0.075, 0.115])
	var width_band: Array = layer.value("leaf_width", [0.042, 0.062])
	var splay_band: Array = layer.value("splay_degrees", [26.0, 50.0])
	var thickness_band: Array = layer.value("thickness_ratio", [0.42, 0.55])
	var height_multiplier: float = layer.value("height_multiplier", 1.0)
	var width_multiplier: float = layer.value("width_multiplier", 1.0)
	var bend_multiplier: float = layer.value("bend_multiplier", 0.75)
	var sink_band: Array = layer.value("root_sink", [0.008, 0.015])
	var secondary_fraction: float = layer.value("secondary_fraction", 0.2)
	var scale := footprint / 0.12

	# Ring leaves, evenly spaced with jitter.
	for leaf in leaf_count:
		var yaw := rosette_yaw + TAU * float(leaf) / float(leaf_count) \
			+ rng.randf_range(-0.4, 0.4)
		_add_leaf(batch, layer, rng, centre, top, yaw,
			rng.randf_range(float(splay_band[0]), float(splay_band[1])),
			rng.randf_range(float(height_band[0]), float(height_band[1]))
				* height_multiplier * scale,
			rng.randf_range(float(width_band[0]), float(width_band[1]))
				* width_multiplier * scale,
			thickness_band, bend_multiplier, sink_band, secondary_fraction,
			cap_height)

	# Centre leaf: taller, nearly upright — the sprout's growing tip.
	if rng.randf() < 0.85:
		_add_leaf(batch, layer, rng, centre, top, rng.randf() * TAU,
			rng.randf_range(3.0, 10.0),
			rng.randf_range(float(height_band[1]) * 0.95,
				float(height_band[1]) * 1.2) * height_multiplier * scale,
			rng.randf_range(float(width_band[0]), float(width_band[1]))
				* width_multiplier * scale * 0.9,
			thickness_band, bend_multiplier, sink_band, secondary_fraction,
			cap_height)


static func _add_leaf(batch: TileKitMeshUtils.MeshBatch, layer: TileKitLayer,
		rng: RandomNumberGenerator, centre: Vector2, top: float, yaw: float,
		splay_degrees: float, leaf_height: float, leaf_width: float,
		thickness_band: Array, bend_multiplier: float, sink_band: Array,
		secondary_fraction: float, cap_height: Callable) -> void:
	# Per-leaf length variety: sibling leaves in one clump differ visibly in
	# height, which is what keeps a rosette from reading as one stamped flower.
	leaf_height *= rng.randf_range(0.78, 1.22)
	# Proportion discipline, enforced here rather than trusted to presets: a
	# leaf is at most ~45% as wide as it is tall. This is the single change
	# that retires the fat-petal tulip read across every stored recipe.
	leaf_width = minf(leaf_width, leaf_height * 0.45)
	var direction := Vector2(cos(yaw), sin(yaw))
	var lean3 := Vector3(direction.x, 0.0, direction.y)
	# The root sits slightly toward the leaf's own side, so bases spread just
	# enough to read as a crown instead of a single stem.
	var crown_offset: float = layer.value("crown_radius", 0.016)
	var root := centre + direction * crown_offset
	var reach := tan(deg_to_rad(splay_degrees)) * leaf_height
	var bend := rng.randf_range(0.8, 1.15) * bend_multiplier
	var sink := rng.randf_range(float(sink_band[0]), float(sink_band[1]))

	# Roots follow the cap's real surface: on the flat top this is y = 0, but
	# near the rim it tracks the bevel downward, so edge sprouts hug the curve
	# instead of hovering over it.
	var surface_y := top
	if cap_height.is_valid():
		surface_y = top + float(cap_height.call(root))
	var p0 := Vector3(root.x, surface_y - sink, root.y)
	# Upright through the lower third, bending through the upper half: the
	# blade grows skyward from its crown and arcs outward as it rises, so the
	# silhouette curves through multiple segments instead of splaying straight
	# from the base like a tulip petal.
	var p1 := p0 + Vector3.UP * (leaf_height * 0.38) + lean3 * (reach * 0.12)
	var p2 := p0 + Vector3.UP * (leaf_height * 0.74) + lean3 * (reach * 0.52 * bend)
	var p3 := p0 + Vector3.UP * leaf_height + lean3 * (reach * bend)

	var key := String(layer.value("primary_key", "grass_primary"))
	if rng.randf() < secondary_fraction:
		key = String(layer.value("secondary_key", "grass_secondary"))
	TileKitMeshUtils.add_blade(batch, key, p0, p1, p2, p3,
		leaf_width, rng.randf_range(float(thickness_band[0]),
			float(thickness_band[1])),
		10, 14, 4, float(layer.value("root_width_factor", 0.86)))
