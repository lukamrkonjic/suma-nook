class_name KitPaversBuilder
extends RefCounted
## Constructed surface courses: paver stones, cobbles, and planks.
##
## The one brick that covers the research inventory's constructed families —
## cobblestone/flagstone, brick paving, and wooden decking — because they are
## all the same idea at different aspect ratios: rounded slabs laid in courses
## over the cap, with the cap's own colour reading as mortar or shadow in the
## gaps between them.
##
## Slabs run to the true footprint boundary and settle onto the cap surface
## (each stone sits at the LOWEST cap height under its footprint, sinking a
## whisker), so a paved land mass reads continuous across tile seams exactly
## like the grass carpet does — no bald mortar border at every tile edge.
##
## Two patterns:
##   "cobbles"  offset grid of near-square rounded stones, jittered
##   "planks"   long boards in rows with staggered joints
static func build(layer: TileKitLayer, rng: RandomNumberGenerator,
		context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var pattern := String(layer.value("pattern", "cobbles"))
	# One colour for every slab by default — variation comes from height
	# jitter, gaps, and lighting, never from a per-stone patchwork. A preset
	# that genuinely wants mixed stones sets slab_key to "" and provides
	# color_weights instead.
	var slab_key := String(layer.value("slab_key", ""))
	var weights: Dictionary = layer.value("color_weights", {"stone_medium": 1.0})
	var height_band: Array = layer.value("stone_height", [0.020, 0.030])
	var sink: float = layer.value("sink", 0.005)
	var batch := TileKitMeshUtils.MeshBatch.new()

	var stones: Array = []
	if pattern == "planks":
		stones = _plank_courses(layer, rng, half)
	elif pattern == "stepping":
		stones = _stepping_stones(layer, rng, half)
	else:
		stones = _cobble_courses(layer, rng, half)

	for stone: Dictionary in stones:
		var centre: Vector2 = stone["centre"]
		var half_x: float = stone["half_x"]
		var half_z: float = stone["half_z"]
		var yaw: float = stone["yaw"]
		# Settle onto the lowest cap point under the stone so rim stones lean
		# into the bevel instead of hovering over it — but clamp the drop: at
		# the footprint boundary the bevel falls further than a whole stone is
		# tall, and an unclamped settle sank every rim stone out of sight,
		# which on screen read as a paving pattern with a bald border.
		var max_settle: float = layer.value("max_settle", 0.012)
		var base_y := top
		if cap_height.is_valid():
			var lowest := 0.0
			for corner: Vector2 in [
				Vector2(half_x, half_z), Vector2(half_x, -half_z),
				Vector2(-half_x, half_z), Vector2(-half_x, -half_z),
			]:
				lowest = minf(lowest,
					float(cap_height.call(centre + corner.rotated(yaw))))
			base_y = top + maxf(lowest, -max_settle)
		# Checkerboards alternate two fixed colours by course parity; plain
		# courses use the single slab colour; "" falls back to weighted mix.
		var alt_key := String(layer.value("slab_key_alt", ""))
		var stone_key := slab_key
		if not alt_key.is_empty() and int(stone.get("parity", 0)) == 1:
			stone_key = alt_key
		TileKitMeshUtils.add_slab(batch,
			stone_key if not stone_key.is_empty()
				else TileKitPalette.weighted_key(rng, weights),
			Vector3(centre.x, base_y - sink, centre.y),
			half_x, half_z,
			layer.value("stone_corner", 0.028),
			rng.randf_range(float(height_band[0]), float(height_band[1])) + sink,
			yaw)

	context["paver_stones"] = stones
	return {
		"meshes": [{"role": "surface", "name": "tile_pavers",
			"mesh": batch.commit()}],
	}


## Full-fill flagstone courses: each row's span is SEGMENTED from edge to
## edge, so the first and last stone in every course touch the footprint
## boundary exactly — no sliver gaps, no bald margins, the way the reference
## game's stone blocks read as completely paved. Jitter lives in the joint
## positions, never in coverage.
static func _cobble_courses(layer: TileKitLayer, rng: RandomNumberGenerator,
		half: float) -> Array:
	var cell: float = layer.value("stone_cell", 0.55)
	var cell_z: float = layer.value("stone_cell_z", cell)
	var gap: float = layer.value("gap", 0.026)
	var jitter: float = layer.value("stone_jitter", 0.05)
	var edge := 0.004
	var span := (half - edge) * 2.0
	var rows := maxi(1, int(round(span / cell_z)))
	var row_height := span / float(rows)
	var stones: Array = []
	for row in rows:
		var z0 := -half + edge + row * row_height
		var z1 := z0 + row_height
		# Segment the row from edge to edge with jittered joints; alternate
		# rows shift their joint pattern half a stone for the running bond.
		var columns := maxi(1, int(round(span / cell)))
		var joints: Array[float] = [-half + edge]
		for joint in range(1, columns):
			var base := -half + edge + span * float(joint) / float(columns)
			if row % 2 == 1:
				base += cell * 0.5 * (1.0 if joint % 2 == 0 else -1.0) * 0.5
			joints.append(clampf(
				base + rng.randf_range(-jitter, jitter) * cell,
				-half + edge + cell * 0.25, half - edge - cell * 0.25))
		joints.append(half - edge)
		joints.sort()
		for segment in joints.size() - 1:
			var x0: float = joints[segment]
			var x1: float = joints[segment + 1]
			if x1 - x0 < cell * 0.22:
				continue
			stones.append({
				"centre": Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5),
				"half_x": (x1 - x0 - gap) * 0.5,
				"half_z": (row_height - gap) * 0.5,
				"yaw": 0.0,
				"parity": (row + segment) % 2,
			})
	return stones

## Long boards in rows, joints staggered per row like decking.
static func _plank_courses(layer: TileKitLayer, rng: RandomNumberGenerator,
		half: float) -> Array:
	var width: float = layer.value("plank_width", 0.21)
	var gap: float = layer.value("gap", 0.020)
	var length_band: Array = layer.value("plank_length", [0.55, 0.95])
	var rows := maxi(1, int(ceil((half * 2.0) / width)))
	var stones: Array = []
	for row in rows:
		var z := -half + (float(row) + 0.5) * width
		var cursor := -half + rng.randf_range(-0.25, 0.0)
		while cursor < half:
			var length: float = rng.randf_range(float(length_band[0]),
				float(length_band[1]))
			var start := maxf(cursor, -half + 0.006)
			var finish := minf(cursor + length, half - 0.006)
			cursor += length + gap
			if finish - start < width * 0.6:
				continue
			stones.append({
				"centre": Vector2((start + finish) * 0.5, z),
				"half_x": (finish - start) * 0.5,
				"half_z": (width - gap) * 0.5,
				"yaw": 0.0,
			})
	return stones


## A handful of separate large stones scattered with breathing room — the
## garden stepping-path. Grass (or anything after this layer) reads the stone
## list from context and keeps clear.
static func _stepping_stones(layer: TileKitLayer, rng: RandomNumberGenerator,
		half: float) -> Array:
	var count_band: Array = layer.value("stepping_count", [4, 6])
	var size_band: Array = layer.value("stepping_size", [0.24, 0.34])
	var count := rng.randi_range(int(count_band[0]), int(count_band[1]))
	var stones: Array = []
	var attempts := 0
	while stones.size() < count and attempts < count * 16:
		attempts += 1
		var half_x := rng.randf_range(float(size_band[0]), float(size_band[1])) * 0.5
		var half_z := half_x * rng.randf_range(0.82, 1.0)
		var reach := half - 0.06 - maxf(half_x, half_z)
		var centre := Vector2(rng.randf_range(-reach, reach),
			rng.randf_range(-reach, reach))
		var clear := true
		for existing: Dictionary in stones:
			if centre.distance_to(existing["centre"]) 					< (maxf(half_x, half_z) + maxf(existing["half_x"],
						existing["half_z"])) * 1.35:
				clear = false
				break
		if clear:
			stones.append({
				"centre": centre,
				"half_x": half_x,
				"half_z": half_z,
				"yaw": rng.randf_range(-0.12, 0.12),
				"parity": 0,
			})
	return stones

