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
	if String(layer.value("coverage_mode", "carpet")) == "carpet":
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
	leaf_width = minf(leaf_width, leaf_height * 0.85)
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
	# Splayed from the base — a sprout leaf grows outward from its crown, so
	# the lean starts immediately rather than in the upper half.
	var p1 := p0 + Vector3.UP * (leaf_height * 0.35) + lean3 * (reach * 0.30)
	var p2 := p0 + Vector3.UP * (leaf_height * 0.72) + lean3 * (reach * 0.68 * bend)
	var p3 := p0 + Vector3.UP * leaf_height + lean3 * (reach * bend)

	var key := String(layer.value("primary_key", "grass_primary"))
	if rng.randf() < secondary_fraction:
		key = String(layer.value("secondary_key", "grass_secondary"))
	TileKitMeshUtils.add_blade(batch, key, p0, p1, p2, p3,
		leaf_width, rng.randf_range(float(thickness_band[0]),
			float(thickness_band[1])),
		10, 14, 4)
