@tool
class_name KitForestFloorBuilder
extends RefCounted
## Lush forest understory: a low clover carpet beneath a few large, readable
## fern crowns. Everything is smooth clay geometry on one shared wind surface.
## Ferns reserve only their small root crowns; clover is allowed beneath the
## fronds so the result reads as one continuous floor rather than isolated props.


static func build(layer: TileKitLayer, rng: RandomNumberGenerator,
		context: Dictionary) -> Dictionary:
	var batch := TileKitMeshUtils.MeshBatch.new()
	var half: float = context.get("surface_half", KitBaseBuilder.HALF)
	var cap_height: Callable = context.get("cap_height", Callable())
	var clover_count := _resolve_count(_int_pair(
		layer.value("clover_count", [20, 28]), Vector2i(20, 28)), rng)
	var fern_count := _resolve_count(_int_pair(
		layer.value("fern_count", [2, 4]), Vector2i(2, 4)), rng)
	var clover_size := _float_pair(
		layer.value("clover_size", [0.040, 0.085]), Vector2(0.040, 0.085))
	var clover_height := _float_pair(
		layer.value("clover_height", [0.018, 0.032]), Vector2(0.018, 0.032))
	var fern_scale := _float_pair(
		layer.value("fern_scale", [0.72, 1.30]), Vector2(0.72, 1.30))
	var fern_height := _float_pair(
		layer.value("fern_height", [0.17, 0.25]), Vector2(0.17, 0.25))
	var fern_reach := _float_pair(
		layer.value("fern_reach", [0.25, 0.34]), Vector2(0.25, 0.34))
	var frond_count := _int_pair(
		layer.value("fronds_per_fern", [5, 7]), Vector2i(5, 7))
	var leaflet_pairs := _int_pair(
		layer.value("leaflet_pairs", [4, 5]), Vector2i(4, 5))
	var four_leaf_chance := float(layer.value("four_leaf_chance", 0.22))
	var edge_margin := float(layer.value("edge_margin", 0.06))
	var clover_spacing := float(layer.value("clover_spacing", 0.095))
	var fern_spacing := float(layer.value("fern_spacing", 0.30))
	var root_sink := float(layer.value("root_sink", 0.010))
	# Resolve these counts only after the living foliage is built. That keeps
	# adding/removing litter from reshuffling the approved fern/clover seed.
	var leaf_litter_count_range := _int_pair(
		layer.value("leaf_litter_count", [5, 8]), Vector2i(5, 8))
	var twig_count_range := _int_pair(
		layer.value("twig_count", [2, 3]), Vector2i(2, 3))
	var leaf_litter_size := _float_pair(
		layer.value("leaf_litter_size", [0.080, 0.140]),
		Vector2(0.080, 0.140))
	var twig_length := _float_pair(
		layer.value("twig_length", [0.17, 0.28]), Vector2(0.17, 0.28))
	var branch_forks := _int_pair(
		layer.value("branch_forks", [1, 2]), Vector2i(1, 2))
	var raised_offshoot_chance := float(
		layer.value("raised_offshoot_chance", 0.48))
	var litter_spacing := float(layer.value("litter_spacing", 0.075))

	var fern_regions: Array[Dictionary] = []
	for index in fern_count:
		# The first crown is a deliberate hero; companions pull toward the
		# smaller end. This prevents equal-sized plants forming a tidy triangle.
		var scale_mix := rng.randf_range(0.90, 1.0) \
			if index == 0 else pow(rng.randf(), 1.55) * 0.78
		var scale := lerpf(fern_scale.x, fern_scale.y, scale_mix)
		var reach := rng.randf_range(fern_reach.x, fern_reach.y) * scale
		var height := rng.randf_range(fern_height.x, fern_height.y) * scale
		var fronds := rng.randi_range(frond_count.x, frond_count.y)
		var pairs := rng.randi_range(leaflet_pairs.x, leaflet_pairs.y)
		# Reserve the complete fern silhouette inside the tile. The extra side
		# allowance covers the broadest leaflet pair, so nothing peeks over.
		var centre_limit := maxf(0.06,
			half - edge_margin - reach - 0.075 * scale)
		var point := _pick_fern_spot(
			rng, fern_regions, centre_limit, fern_spacing)
		fern_regions.append({"point": point, "radius": reach})
		_add_fern_crown(batch, rng,
			_ground(point, cap_height, root_sink), scale,
			fronds, pairs, height, reach)

	var clover_pockets: Array[Vector2] = []
	for _pocket in 4:
		clover_pockets.append(Vector2(
			rng.randf_range(-half * 0.58, half * 0.58),
			rng.randf_range(-half * 0.58, half * 0.58)))
	var clover_points: Array[Vector2] = []
	for index in clover_count:
		var leaf_radius := rng.randf_range(clover_size.x, clover_size.y)
		# Each leaf centre sits 0.58 radii from the crown, then carries its
		# own radius. The 1.62 allowance contains even editor-max clovers.
		var safe_limit := half - edge_margin - leaf_radius * 1.62
		# Four guaranteed low crowns cover every corner, so deterministic detail
		# rotations cannot expose a bald shared intersection. Additional edge
		# crowns loosen the old interior ring while the leaf-aware limit keeps
		# every crown contained.
		var corner_index := index if index < 4 else -1
		var corner_band := corner_index >= 0
		var edge_band := not corner_band and rng.randf() < 0.30
		var clustered := not corner_band and not edge_band \
			and rng.randf() < 0.54
		var point := _pick_clover_spot(rng, clover_points, fern_regions,
			clover_pockets, safe_limit, corner_band, edge_band, clustered,
			clover_spacing, corner_index)
		clover_points.append(point)
		_add_clover(batch, rng,
			_ground(point, cap_height, root_sink), leaf_radius,
			rng.randf_range(clover_height.x, clover_height.y),
			four_leaf_chance)

	# Forest litter gathers in loose pockets instead of being sprayed evenly.
	# Leaves and twigs use separate warm, static clay materials; only the living
	# foliage above remains on the shared wind surface.
	var leaf_litter_count := _resolve_count(leaf_litter_count_range, rng)
	var twig_count := _resolve_count(twig_count_range, rng)
	var litter_pockets: Array[Vector2] = []
	for _pocket in 3:
		litter_pockets.append(Vector2(
			rng.randf_range(-half * 0.52, half * 0.52),
			rng.randf_range(-half * 0.52, half * 0.52)))
	var litter_points: Array[Vector2] = []
	for leaf_index in leaf_litter_count:
		var leaf_size := rng.randf_range(
			leaf_litter_size.x, leaf_litter_size.y)
		var leaf_limit := half - edge_margin - leaf_size * 0.62
		var leaf_point := _pick_litter_spot(rng, litter_points,
			clover_points, litter_pockets, leaf_limit, litter_spacing, 0.68,
			"edge" if leaf_index < 2 else "free")
		litter_points.append(leaf_point)
		_add_fallen_leaf(batch, rng,
			_ground(leaf_point, cap_height, -0.004), leaf_size)
	for twig_index in twig_count:
		var length := rng.randf_range(twig_length.x, twig_length.y)
		var twig_limit := half - edge_margin - length * 0.90
		var twig_point := _pick_litter_spot(rng, litter_points,
			clover_points, litter_pockets, twig_limit,
			maxf(litter_spacing, 0.12), 0.54,
			"edge" if twig_index == 0 else "free")
		litter_points.append(twig_point)
		_add_fallen_branch(batch, rng,
			_ground(twig_point, cap_height, -0.006), length,
			rng.randi_range(branch_forks.x, branch_forks.y),
			raised_offshoot_chance, twig_index == 0)

	return {
		"meshes": [{
			"role": "detail",
			"name": "lush_clover_fern_forest_floor",
			"mesh": batch.commit(),
			"cast_shadow": true,
		}],
	}


static func _int_pair(raw: Variant, fallback: Vector2i) -> Vector2i:
	if raw is Array and raw.size() >= 2:
		return Vector2i(mini(int(raw[0]), int(raw[1])),
			maxi(int(raw[0]), int(raw[1])))
	return fallback


static func _float_pair(raw: Variant, fallback: Vector2) -> Vector2:
	if raw is Array and raw.size() >= 2:
		return Vector2(minf(float(raw[0]), float(raw[1])),
			maxf(float(raw[0]), float(raw[1])))
	return fallback


static func _resolve_count(value_range: Vector2i,
		rng: RandomNumberGenerator) -> int:
	if value_range.x == value_range.y:
		return value_range.x
	return rng.randi_range(value_range.x, value_range.y)


static func _ground(point: Vector2, cap_height: Callable,
		root_sink: float) -> Vector3:
	var height := 0.0
	if cap_height.is_valid():
		height = float(cap_height.call(point))
	return Vector3(point.x, height - root_sink, point.y)


static func _pick_fern_spot(rng: RandomNumberGenerator,
		regions: Array[Dictionary], limit: float, spacing: float) -> Vector2:
	var fallback := Vector2.ZERO
	var fallback_score := -INF
	for _attempt in 64:
		var candidate := Vector2(rng.randf_range(-limit, limit),
			rng.randf_range(-limit, limit))
		var nearest := limit * 2.0 + spacing
		for region: Dictionary in regions:
			var existing: Vector2 = region["point"]
			nearest = minf(nearest, candidate.distance_to(existing))
		if nearest > fallback_score:
			fallback_score = nearest
			fallback = candidate
		if nearest >= spacing * rng.randf_range(0.88, 1.10):
			return candidate
	return fallback


static func _pick_clover_spot(rng: RandomNumberGenerator,
		placed: Array[Vector2], fern_regions: Array[Dictionary],
		pockets: Array[Vector2], limit: float, corner_band: bool, edge_band: bool,
		clustered: bool, spacing: float, corner_index := -1) -> Vector2:
	var fallback := Vector2.ZERO
	var fallback_score := -INF
	for _attempt in 56:
		var candidate: Vector2
		if corner_band:
			var corner := posmod(corner_index, 4) \
				if corner_index >= 0 else rng.randi_range(0, 3)
			var inset_x := rng.randf_range(0.0, minf(0.065, limit * 0.14))
			var inset_y := rng.randf_range(0.0, minf(0.105, limit * 0.20))
			candidate = Vector2(
				(-1.0 if corner in [0, 2] else 1.0) * (limit - inset_x),
				(-1.0 if corner in [0, 1] else 1.0) * (limit - inset_y))
		elif edge_band:
			var side := rng.randi_range(0, 3)
			var edge := limit - rng.randf_range(0.0, 0.055)
			var along := rng.randf_range(-limit, limit)
			match side:
				0: candidate = Vector2(-edge, along)
				1: candidate = Vector2(edge, along)
				2: candidate = Vector2(along, -edge)
				_: candidate = Vector2(along, edge)
		elif clustered and not pockets.is_empty():
			var pocket := pockets[rng.randi() % pockets.size()]
			var angle := rng.randf_range(0.0, TAU)
			var radius := sqrt(rng.randf()) * rng.randf_range(0.12, 0.29)
			candidate = pocket + Vector2(cos(angle), sin(angle)) * radius
			candidate.x = clampf(candidate.x, -limit, limit)
			candidate.y = clampf(candidate.y, -limit, limit)
		else:
			candidate = Vector2(rng.randf_range(-limit, limit),
				rng.randf_range(-limit, limit))
		var nearest := limit * 2.0 + spacing
		for existing in placed:
			nearest = minf(nearest, candidate.distance_to(existing))
		var clears_fern_roots := true
		for region: Dictionary in fern_regions:
			var fern_point: Vector2 = region["point"]
			var root_clearance := 0.085 + float(region["radius"]) * 0.16
			if candidate.distance_to(fern_point) < root_clearance:
				clears_fern_roots = false
				break
		var score := nearest if clears_fern_roots else nearest * 0.25
		if score > fallback_score:
			fallback_score = score
			fallback = candidate
		if clears_fern_roots \
				and nearest >= spacing * rng.randf_range(0.80, 1.08):
			return candidate
	return fallback


static func _pick_litter_spot(rng: RandomNumberGenerator,
		placed: Array[Vector2], clovers: Array[Vector2],
		pockets: Array[Vector2], limit: float, spacing: float,
		cluster_chance: float, placement: String) -> Vector2:
	var fallback := Vector2.ZERO
	var fallback_score := -INF
	for _attempt in 64:
		var candidate: Vector2
		if placement == "edge":
			var side := rng.randi_range(0, 3)
			var edge := limit - rng.randf_range(0.0, minf(0.065, limit * 0.14))
			var along := rng.randf_range(-limit, limit)
			match side:
				0: candidate = Vector2(-edge, along)
				1: candidate = Vector2(edge, along)
				2: candidate = Vector2(along, -edge)
				_: candidate = Vector2(along, edge)
		elif rng.randf() < cluster_chance and not pockets.is_empty():
			var pocket := pockets[rng.randi() % pockets.size()]
			var angle := rng.randf_range(0.0, TAU)
			var radius := sqrt(rng.randf()) * rng.randf_range(0.07, 0.25)
			candidate = pocket + Vector2(cos(angle), sin(angle)) * radius
			candidate.x = clampf(candidate.x, -limit, limit)
			candidate.y = clampf(candidate.y, -limit, limit)
		else:
			candidate = Vector2(rng.randf_range(-limit, limit),
				rng.randf_range(-limit, limit))
		var nearest := limit * 2.0 + spacing
		for existing in placed:
			nearest = minf(nearest, candidate.distance_to(existing))
		# Debris can tuck beneath foliage, but not sit directly through a clover
		# crown. This small clearance leaves the overall floor interwoven.
		for clover in clovers:
			nearest = minf(nearest,
				candidate.distance_to(clover) + spacing * 0.45)
		if nearest > fallback_score:
			fallback_score = nearest
			fallback = candidate
		if nearest >= spacing * rng.randf_range(0.78, 1.08):
			return candidate
	return fallback


static func _add_root_collar(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, base: Vector3, radius: float,
		height: float, centre_color: Color) -> void:
	var ground_color := TileKitPalette.color("forest_floor_top")
	TileKitMeshUtils.add_lobed_mound(batch, "forest_rooted_gradient",
		base - Vector3.UP * height * 0.70,
		radius, radius * rng.randf_range(0.86, 1.12), height,
		rng.randf_range(0.0, TAU), rng, 0.09, 2, 8, 0.82,
		[centre_color, ground_color])


static func _add_clover(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, base: Vector3, leaf_radius: float,
		height: float, four_leaf_chance: float) -> void:
	var ground_color := TileKitPalette.color("forest_floor_top")
	var leaf_color := (
		TileKitPalette.color("forest_clover_light")
		if rng.randf() < 0.24
		else TileKitPalette.color("forest_clover")
	)
	var yaw := rng.randf_range(0.0, TAU)
	var crown := base + Vector3.UP * height
	_add_root_collar(batch, rng, base, leaf_radius * 0.55,
		0.010 + leaf_radius * 0.08, leaf_color.lerp(ground_color, 0.55))
	TileKitMeshUtils.add_blade(batch, "forest_rooted_gradient",
		base - Vector3.UP * 0.018,
		base + Vector3.UP * height * 0.30,
		base + Vector3.UP * height * 0.72,
		crown, leaf_radius * 0.20, 0.76,
		2, 5, 1, 0.94, PackedColorArray([ground_color, leaf_color]))
	var leaf_count := 4 if rng.randf() < four_leaf_chance else 3
	for leaf in leaf_count:
		var angle := yaw + TAU * float(leaf) / float(leaf_count) \
			+ rng.randf_range(-0.08, 0.08)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var radius := leaf_radius * rng.randf_range(0.90, 1.08)
		TileKitMeshUtils.add_egg(batch, "forest_rooted_gradient",
			crown + outward * radius * 0.58,
			Vector3.UP, maxf(0.011, height * 0.60), radius,
			3, 6, 0.82, outward, leaf_color)


static func _add_fallen_leaf(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, centre: Vector3, length: float) -> void:
	var yaw := rng.randf_range(0.0, TAU)
	var forward := Vector3(cos(yaw), 0.0, sin(yaw))
	var side := Vector3(-forward.z, 0.0, forward.x)
	var key := "forest_litter_leaf_light" \
		if rng.randf() < 0.16 else "forest_litter_leaf"
	var curl := rng.randf_range(-1.0, 1.0)
	var p0 := centre - forward * length * 0.50
	var leaf_axis := (forward + side * curl * 0.10 \
		+ Vector3.UP * rng.randf_range(0.015, 0.050)).normalized()
	TileKitMeshUtils.add_egg(batch, key, p0, leaf_axis, length,
		length * rng.randf_range(0.22, 0.28), 4, 9, 0.20, side)
	# A low midrib gives the soft oval a readable leaf construction at game
	# scale without drawing a graphic line across it.
	var vein_start := p0 + leaf_axis * length * 0.12 \
		+ Vector3.UP * length * 0.025
	var vein_end := p0 + leaf_axis * length * 0.88 \
		+ Vector3.UP * length * 0.025
	TileKitMeshUtils.add_blade(batch, "forest_litter_twig",
		vein_start, vein_start.lerp(vein_end, 0.33),
		vein_start.lerp(vein_end, 0.72), vein_end,
		maxf(0.004, length * 0.035), 0.55, 3, 6, 1, 0.76)
	# A tiny attached petiole makes the form read as a fallen leaf rather than
	# another oval ground mark.
	var stem_end := p0 - leaf_axis * length * rng.randf_range(0.14, 0.22)
	TileKitMeshUtils.add_blade(batch, "forest_litter_twig",
		stem_end, stem_end.lerp(p0, 0.34) + Vector3.UP * 0.002,
		stem_end.lerp(p0, 0.74) + Vector3.UP * 0.002, p0,
		maxf(0.005, length * 0.050), 0.82, 3, 6, 1, 0.92)


static func _add_fallen_branch(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, centre: Vector3, length: float,
		fork_count: int, raised_offshoot_chance: float,
		force_raised_offshoot: bool) -> void:
	var yaw := rng.randf_range(0.0, TAU)
	var forward := Vector3(cos(yaw), 0.0, sin(yaw))
	var side := Vector3(-forward.z, 0.0, forward.x)
	var bend := rng.randf_range(-1.0, 1.0)
	# The load-bearing stem is fallen wood: both ends remain supported by the
	# floor and only its natural crook rises by a few millimetres.
	var p0 := centre - forward * length * 0.52 \
		+ Vector3.UP * length * rng.randf_range(0.010, 0.025)
	var p3 := centre + forward * length * 0.48 \
		+ side * bend * length * 0.10 \
		+ Vector3.UP * length * rng.randf_range(0.010, 0.025)
	var p1 := p0.lerp(p3, 0.34) \
		+ side * bend * length * 0.14 \
		+ Vector3.UP * length * rng.randf_range(0.025, 0.060)
	var p2 := p0.lerp(p3, 0.72) \
		- side * bend * length * rng.randf_range(0.01, 0.07) \
		+ Vector3.UP * length * rng.randf_range(0.020, 0.055)
	var width := rng.randf_range(0.016, 0.024)
	TileKitMeshUtils.add_blade(batch, "forest_litter_twig",
		p0, p1, p2, p3, width, 0.88, 5, 7, 1, 1.08)
	# Every piece branches at least once. Some split twice on opposing sides,
	# producing crooked Y, hooked, and antler-like silhouettes rather than a
	# repeated bent noodle.
	for fork_index in maxi(fork_count, 1):
		var fork_t := rng.randf_range(0.28, 0.72)
		var fork_root := _bezier(p0, p1, p2, p3, fork_t)
		var fork_sign := -1.0 if (
			(fork_index % 2 == 0) == (rng.randf() < 0.5)) else 1.0
		var raised_fork := (force_raised_offshoot and fork_index == 0) \
			or rng.randf() < raised_offshoot_chance
		# Even lifted twigs travel farther sideways than upward. They branch off
		# fallen wood; none becomes an implausible vertical stem.
		var upward_component := rng.randf_range(0.14, 0.34) \
			if raised_fork else rng.randf_range(0.015, 0.075)
		var fork_direction := (forward * rng.randf_range(0.45, 0.72) \
			+ side * fork_sign * rng.randf_range(0.55, 0.92) \
			+ Vector3.UP * upward_component).normalized()
		var fork_length := length * rng.randf_range(0.26, 0.48)
		var fork_tip := fork_root + fork_direction * fork_length
		TileKitMeshUtils.add_blade(batch, "forest_litter_twig",
			fork_root - fork_direction * 0.006,
			fork_root.lerp(fork_tip, 0.30) \
				+ side * fork_sign * fork_length * 0.04,
			fork_root.lerp(fork_tip, 0.72) \
				- side * fork_sign * fork_length * 0.025,
			fork_tip, width * 0.68, 0.86, 4, 7, 1, 1.02)


static func _add_fern_crown(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, base: Vector3, scale: float,
		frond_count: int, leaflet_pairs: int, height: float,
		reach: float) -> void:
	var ground_color := TileKitPalette.color("forest_floor_top")
	var fern_dark := TileKitPalette.color("forest_fern")
	var fern_light := TileKitPalette.color("forest_fern_light")
	var crown_yaw := rng.randf_range(0.0, TAU)
	var crown_span := rng.randf_range(PI * 1.15, PI * 1.72)
	var profile_offset := rng.randi_range(0, 6)
	var reach_profile := [1.0, 0.66, 0.88, 0.54, 0.79, 0.94, 0.61]
	_add_root_collar(batch, rng, base, 0.080 * scale,
		0.024 * scale, fern_dark)
	for frond in frond_count:
		var spread_t := float(frond) / float(maxi(frond_count - 1, 1))
		var angle := crown_yaw + (spread_t - 0.5) * crown_span \
			+ rng.randf_range(-0.20, 0.20)
		var forward := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-forward.z, 0.0, forward.x)
		var profile: float = reach_profile[(frond + profile_offset) % 7]
		var frond_reach := reach * profile * rng.randf_range(0.90, 1.05)
		var frond_height := height * rng.randf_range(0.68, 1.08) \
			* lerpf(0.88, 1.08, 1.0 - absf(spread_t - 0.5) * 2.0)
		var root := base - Vector3.UP * 0.026
		var p1 := base + forward * frond_reach * 0.08 \
			+ Vector3.UP * frond_height * 0.42
		var p2 := base + forward * frond_reach * 0.52 \
			+ Vector3.UP * frond_height * 0.96
		var tip := base + forward * frond_reach \
			+ Vector3.UP * frond_height * 0.70
		TileKitMeshUtils.add_blade(batch, "forest_rooted_gradient",
			root, p1, p2, tip, 0.018 * scale, 0.55,
			4, 5, 1, 0.92, PackedColorArray([ground_color, fern_dark]))
		for pair in leaflet_pairs:
			var t := 0.23 + float(pair) * 0.59 \
				/ float(maxi(leaflet_pairs - 1, 1))
			t += rng.randf_range(-0.015, 0.015)
			var centre := _bezier(root, p1, p2, tip, t)
			var envelope := sin(t * PI)
			var leaflet_length := frond_reach \
				* lerpf(0.30, 0.15, t) * lerpf(0.80, 1.0, envelope)
			var leaflet_width := (0.036 - t * 0.010) * scale
			for sign_value in [-1.0, 1.0]:
				var direction: Vector3 = (
					side * float(sign_value) * 0.96 + forward * 0.22
				).normalized()
				var side_length := leaflet_length * rng.randf_range(0.82, 1.12)
				var end := centre + direction * side_length \
					+ Vector3.UP * side_length * 0.20
				var colour_mix := clampf(t * 0.72 \
					+ rng.randf_range(-0.08, 0.08), 0.0, 1.0)
				var leaf_colour := fern_dark.lerp(fern_light, colour_mix)
				TileKitMeshUtils.add_blade(batch, "forest_rooted_gradient",
					centre - Vector3.UP * 0.003,
					centre.lerp(end, 0.32) + Vector3.UP * side_length * 0.04,
					centre.lerp(end, 0.76) + Vector3.UP * side_length * 0.04,
					end, leaflet_width, 0.48,
					3, 5, 1, 0.88,
					PackedColorArray([fern_dark, leaf_colour]))
		var terminal := tip + forward * 0.050 * scale \
			+ Vector3.UP * 0.012 * scale
		TileKitMeshUtils.add_blade(batch, "forest_rooted_gradient",
			tip - forward * 0.010 * scale,
			tip.lerp(terminal, 0.34), tip.lerp(terminal, 0.74), terminal,
			0.026 * scale, 0.48, 3, 5, 1, 0.88,
			PackedColorArray([fern_dark, fern_light]))


static func _bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		t: float) -> Vector3:
	var u := 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) \
		+ p2 * (3.0 * u * t * t) + p3 * (t * t * t)
