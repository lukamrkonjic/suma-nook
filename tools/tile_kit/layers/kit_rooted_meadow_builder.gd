@tool
class_name KitRootedMeadowBuilder
extends RefCounted
## Approved rooted clay meadow composition. The default parameter values
## reproduce the selected gallery study exactly; Tile Editor ranges reshape
## that same construction instead of switching to a look-alike builder.

const GRASS_SCALES: Array[float] = [
	0.65, 0.90, 1.05, 1.20, 1.35, 1.55, 1.75, 2.00, 2.30,
]
const FERN_SCALES: Array[float] = [1.12]
const CLOVER_SCALES: Array[float] = [0.68, 0.84, 1.00]
const FLOWER_SCALES: Array[float] = [0.90, 1.05, 1.22]

const DEFAULT_BLADE_COUNTS := Vector2i(3, 5)
const DEFAULT_GRASS_HEIGHT := Vector2(0.1257, 0.2214)
const DEFAULT_BLADE_WIDTH := Vector2(
	0.08241167634421508, 0.10656355301955055)
const DEFAULT_CLOVER_SIZE := Vector2(0.05724, 0.063)


static func build(layer: TileKitLayer, rng: RandomNumberGenerator,
		context: Dictionary) -> Dictionary:
	var batch := TileKitMeshUtils.MeshBatch.new()
	var half: float = context.get("surface_half", KitBaseBuilder.HALF)
	var cap_height: Callable = context.get("cap_height", Callable())
	var edge_margin := float(layer.value("edge_margin", 0.025))
	var min_spacing := float(layer.value("min_spacing", 0.15))
	var root_sink := float(layer.value("root_sink", 0.010))
	var blade_counts := _int_pair(
		layer.value("blades_per_turf", [3, 5]), DEFAULT_BLADE_COUNTS)
	var grass_height := _float_pair(
		layer.value("grass_height", [0.1257, 0.2214]), DEFAULT_GRASS_HEIGHT)
	var blade_width := _float_pair(
		layer.value("blade_width", [0.082411676, 0.106563553]),
		DEFAULT_BLADE_WIDTH)
	var clover_size := _float_pair(
		layer.value("clover_size", [0.05724, 0.063]), DEFAULT_CLOVER_SIZE)
	var four_leaf_chance := float(layer.value("four_leaf_chance", 0.28))
	var accent_flower_chance := float(
		layer.value("accent_flower_chance", 0.0))
	var turf_count := _resolve_count(
		_int_pair(layer.value("turf_count", [9, 9]), Vector2i(9, 9)), rng)
	var fern_count := _resolve_count(
		_int_pair(layer.value("fern_count", [1, 1]), Vector2i(1, 1)), rng)
	var clover_count := _resolve_count(
		_int_pair(layer.value("clover_count", [3, 3]), Vector2i(3, 3)), rng)
	var flower_count := _resolve_count(
		_int_pair(layer.value("flower_count", [0, 0]), Vector2i.ZERO), rng)
	var items: Array[Dictionary] = []
	for index in turf_count:
		var placement := "free"
		if _grass_uses_edge_band(index, turf_count):
			placement = "edge"
		items.append({"kind": "grass",
			"scale": _sample_scale(GRASS_SCALES, index, turf_count),
			"placement": placement})
	for index in fern_count:
		items.append({"kind": "fern",
			"scale": _sample_scale(FERN_SCALES, index, fern_count),
			"placement": "free"})
	for index in clover_count:
		var corner_index := index * 2 if index < 2 else -1
		items.append({"kind": "clover",
			"scale": _sample_scale(CLOVER_SCALES, index, clover_count),
			# Low clovers and flowers cover all four corners. Rotation can then vary
			# the composition without ever uncovering a connected intersection.
			"placement": "corner" if corner_index >= 0 else "free",
			"corner_index": corner_index})
	for index in flower_count:
		var corner_index := index * 2 + 1 if index < 2 else -1
		items.append({"kind": "flower",
			"scale": _sample_scale(FLOWER_SCALES, index, flower_count),
			"placement": "corner" if corner_index >= 0 else "free",
			"corner_index": corner_index})
	_shuffle(items, rng)
	var placed: Array[Vector2] = []
	for item in items:
		var kind := String(item["kind"])
		var spacing := min_spacing
		if kind == "fern":
			spacing = min_spacing * (0.19 / 0.15)
		elif kind == "flower":
			spacing = min_spacing * (0.14 / 0.15)
		elif kind == "clover":
			spacing = min_spacing * (0.105 / 0.15)
		var scale := float(item["scale"])
		var footprint := _item_footprint(kind, scale, clover_size)
		var limit := maxf(0.02, half - edge_margin - footprint)
		var point := _pick_spot(rng, placed, limit,
			String(item["placement"]), spacing,
			int(item.get("corner_index", -1)))
		var base := _ground(point, cap_height, root_sink)
		match kind:
			"fern":
				_add_fern(batch, rng, base, scale)
			"clover":
				_add_clover(batch, rng, base, scale,
					clover_size, four_leaf_chance)
			"flower":
				_add_flower(batch, rng, base, 0.105 * scale,
					accent_flower_chance)
			_:
				_add_turf(batch, rng, base, scale,
					blade_counts, grass_height, blade_width)
	return {
		"meshes": [{
			"role": "detail",
			"name": "rooted_fern_clover_meadow",
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


static func _sample_scale(source: Array[float], index: int, count: int) -> float:
	if source.size() == 1 or count <= 1:
		return source[0]
	var source_position := float(index) * float(source.size() - 1) \
		/ float(count - 1)
	var low := floori(source_position)
	var high := mini(low + 1, source.size() - 1)
	return lerpf(source[low], source[high], source_position - float(low))


static func _grass_uses_edge_band(index: int, count: int) -> bool:
	if count <= 1:
		return true
	var source_index := roundi(float(index) * 8.0 / float(count - 1))
	return source_index == 0 or source_index == 3 or source_index == 7


static func _item_footprint(kind: String, scale: float,
		clover_size: Vector2) -> float:
	match kind:
		"fern":
			return 0.205 * scale
		"clover":
			return clover_size.y * 1.62 + 0.008
		"flower":
			return 0.105 * scale * 0.72 + 0.008
		_:
			# Covers the rooted collar and the longest leaning blade.
			return 0.070 + scale * 0.055


static func _shuffle(items: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	for index in range(items.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary := items[index]
		items[index] = items[swap_index]
		items[swap_index] = temporary


static func _pick_spot(rng: RandomNumberGenerator, placed: Array[Vector2],
		limit: float, placement: String, spacing: float,
		corner_index := -1) -> Vector2:
	var fallback := Vector2.ZERO
	var fallback_distance := -1.0
	for _attempt in 48:
		var candidate: Vector2
		if placement == "corner":
			var corner := posmod(corner_index, 4) \
				if corner_index >= 0 else rng.randi_range(0, 3)
			var inset_x := rng.randf_range(0.0, minf(0.075, limit * 0.16))
			var inset_y := rng.randf_range(0.0, minf(0.115, limit * 0.22))
			var sign_x := -1.0 if corner in [0, 2] else 1.0
			var sign_y := -1.0 if corner in [0, 1] else 1.0
			candidate = Vector2(sign_x * (limit - inset_x),
				sign_y * (limit - inset_y))
		elif placement == "edge":
			var side := rng.randi_range(0, 3)
			var edge := limit - rng.randf_range(0.0, 0.065)
			var along := rng.randf_range(-limit, limit)
			match side:
				0: candidate = Vector2(-edge, along)
				1: candidate = Vector2(edge, along)
				2: candidate = Vector2(along, -edge)
				_: candidate = Vector2(along, edge)
		else:
			candidate = Vector2(
				rng.randf_range(-limit, limit),
				rng.randf_range(-limit, limit))
		var nearest := limit * 2.0
		for existing in placed:
			nearest = minf(nearest, candidate.distance_to(existing))
		if nearest > fallback_distance:
			fallback_distance = nearest
			fallback = candidate
		if nearest >= spacing * rng.randf_range(0.86, 1.10):
			placed.append(candidate)
			return candidate
	placed.append(fallback)
	return fallback


static func _ground(point: Vector2, cap_height: Callable,
		root_sink: float) -> Vector3:
	var height := 0.0
	if cap_height.is_valid():
		height = float(cap_height.call(point))
	return Vector3(point.x, height - root_sink, point.y)


static func _root_collar(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, base: Vector3, radius: float,
		height: float, yaw: float) -> void:
	var ground_color := TileKitPalette.color("grass_gg_top")
	TileKitMeshUtils.add_lobed_mound(batch, "grass_rooted_gradient",
		base - Vector3.UP * height * 0.72,
		radius, radius * rng.randf_range(0.84, 1.10), height,
		yaw, rng, 0.10, 2, 8, 0.80, [ground_color, ground_color])


static func _add_turf(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, base: Vector3, scale: float,
		blade_counts: Vector2i, grass_height: Vector2,
		blade_width_range: Vector2) -> void:
	var natural_leaves := clampi(int(round(2.5 + scale * 1.10)), 3, 5)
	var leaf_mix := float(natural_leaves - 3) / 2.0
	var leaves := roundi(lerpf(
		float(blade_counts.x), float(blade_counts.y), leaf_mix))
	leaves = maxi(leaves, 1)
	var yaw := rng.randf_range(0.0, TAU)
	var step := rng.randf_range(0.38, 0.62)
	var centre_index := rng.randi_range(0, leaves - 1)
	var scale_mix := clampf((scale - 0.65) / (2.30 - 0.65), 0.0, 1.0)
	var width_mix := clampf(
		(sqrt(scale) - sqrt(0.65)) / (sqrt(2.30) - sqrt(0.65)),
		0.0, 1.0)
	var tuft_height := lerpf(grass_height.x, grass_height.y, scale_mix)
	var tuft_reach := 0.040 + scale * 0.043
	var blade_width := lerpf(
		blade_width_range.x, blade_width_range.y, width_mix)
	var collar_radius := 0.052 + scale * 0.035
	var collar_height := 0.018 + sqrt(scale) * 0.010
	_root_collar(batch, rng, base, collar_radius, collar_height, yaw)
	var ground_color := TileKitPalette.color("grass_gg_top")
	var grass_color := ground_color.lerp(
		TileKitPalette.color("grass_primary"), 0.48)
	for leaf in leaves:
		var relative := (float(leaf) - float(leaves - 1) * 0.5) * step
		relative += rng.randf_range(-0.16, 0.16)
		var angle := yaw + relative
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var dominance := 1.13 if leaf == centre_index else rng.randf_range(0.64, 0.98)
		var height := tuft_height * dominance
		var reach := tuft_reach * rng.randf_range(0.76, 1.15)
		var root := base - Vector3.UP * 0.034 \
			+ outward * rng.randf_range(0.0, collar_radius * 0.18)
		var p1 := root + Vector3.UP * height * 0.40 + outward * reach * 0.10
		var p2 := root + Vector3.UP * height * 0.80 + outward * reach * 0.62
		var p3 := root + Vector3.UP * height + outward * reach
		TileKitMeshUtils.add_blade(batch, "grass_rooted_gradient",
			root, p1, p2, p3,
			blade_width * rng.randf_range(0.88, 1.12),
			0.74, 3, 5, 1, 1.0, [ground_color, grass_color])


static func _add_fern(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, base: Vector3, scale: float) -> void:
	var yaw := rng.randf_range(0.0, TAU)
	var forward := Vector3(cos(yaw), 0.0, sin(yaw))
	var side := Vector3(-forward.z, 0.0, forward.x)
	var reach := 0.155 * scale
	var height := 0.105 * scale
	var root := base - Vector3.UP * 0.032
	var tip := base + forward * reach + Vector3.UP * height
	_root_collar(batch, rng, base, 0.075 * scale, 0.024, yaw)
	TileKitMeshUtils.add_blade(batch, "grass_rooted_gradient",
		root,
		root + forward * reach * 0.28 + Vector3.UP * height * 0.22,
		root + forward * reach * 0.68 + Vector3.UP * height * 0.70,
		tip, 0.017 * scale, 0.58, 3, 5, 1, 1.0,
		[TileKitPalette.color("grass_gg_top"),
			TileKitPalette.color("clay_leaf")])
	var fern_color := TileKitPalette.color("clay_leaf")
	for pair in 4:
		var t := 0.25 + float(pair) * 0.17
		var centre := root.lerp(tip, t) + Vector3.UP * sin(t * PI) * height * 0.10
		var leaflet_length := (0.078 - float(pair) * 0.010) * scale
		var leaflet_width := (0.024 - float(pair) * 0.002) * scale
		for sign_value in [-1.0, 1.0]:
			var direction: Vector3 = (
				side * float(sign_value) * 0.90 + forward * 0.42
			).normalized()
			var end: Vector3 = centre + direction * leaflet_length \
				+ Vector3.UP * leaflet_length * 0.24
			TileKitMeshUtils.add_blade(batch, "grass_rooted_gradient",
				centre - Vector3.UP * 0.004,
				centre.lerp(end, 0.34) + Vector3.UP * leaflet_length * 0.05,
				centre.lerp(end, 0.76) + Vector3.UP * leaflet_length * 0.04,
				end, leaflet_width, 0.44, 3, 5, 1, 0.88,
				[fern_color, fern_color])
	var terminal := tip + forward * 0.055 * scale + Vector3.UP * 0.018 * scale
	TileKitMeshUtils.add_blade(batch, "grass_rooted_gradient",
		tip - forward * 0.012 * scale,
		tip.lerp(terminal, 0.35), tip.lerp(terminal, 0.76), terminal,
		0.022 * scale, 0.44, 3, 5, 1, 0.88,
		[fern_color, fern_color])


## Readable game clover: a very short rooted pin with three oversized circular
## leaf pads, plus a rare four-leaf roll. Low enough to remain ground cover.
static func _add_clover(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, base: Vector3, scale: float,
		clover_size: Vector2, four_leaf_chance: float) -> void:
	var yaw := rng.randf_range(0.0, TAU)
	var ground_color := TileKitPalette.color("grass_gg_top")
	var clover_color := TileKitPalette.color("grass_primary")
	var root := base - Vector3.UP * 0.024
	var crown := base + Vector3.UP * (0.020 + scale * 0.008)
	_root_collar(batch, rng, base, 0.032 * scale, 0.014, yaw)
	TileKitMeshUtils.add_blade(batch, "grass_rooted_gradient",
		root, root.lerp(crown, 0.35), root.lerp(crown, 0.75), crown,
		0.018 * scale, 0.80, 3, 5, 1, 1.0,
		[ground_color, clover_color])
	var leaf_count := 4 if rng.randf() < four_leaf_chance else 3
	var size_mix := clampf((scale - 0.68) / (1.00 - 0.68), 0.0, 1.0)
	var leaf_radius := lerpf(clover_size.x, clover_size.y, size_mix)
	for leaf in leaf_count:
		var angle := yaw + TAU * float(leaf) / float(leaf_count) \
			+ rng.randf_range(-0.075, 0.075)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		TileKitMeshUtils.add_egg(batch, "grass_rooted_gradient",
			crown + outward * leaf_radius * 0.55,
			Vector3.UP, 0.018 * scale, leaf_radius,
			3, 6, 0.86, Vector3.ZERO, clover_color)


static func _add_flower(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, base: Vector3, size: float,
		accent_flower_chance: float) -> void:
	var root := base - Vector3.UP * 0.028
	var stem_top := base + Vector3.UP * size * 0.32
	TileKitMeshUtils.add_blade(batch, "grass_rooted_gradient",
		root, root.lerp(stem_top, 0.36), root.lerp(stem_top, 0.76), stem_top,
		size * 0.13, 0.90, 3, 5, 1, 1.0,
		[TileKitPalette.color("grass_gg_top"),
			TileKitPalette.color("grass_gg_tuft")])
	var head := base + Vector3.UP * size * 0.29
	if rng.randf() < accent_flower_chance:
		_add_cupped_flower_head(batch, rng, head, size)
	else:
		_add_daisy_flower_head(batch, rng, head, size)


## The familiar low cream daisy used as the quiet meadow flower.
static func _add_daisy_flower_head(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, head: Vector3, size: float) -> void:
	var yaw := rng.randf_range(0.0, TAU)
	for petal in 5:
		var angle := yaw + TAU * float(petal) / 5.0
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		TileKitMeshUtils.add_egg(batch, "grass_rooted_gradient",
			head + outward * size * 0.34,
			Vector3.UP, size * 0.22, size * 0.34, 3, 5, 1.0,
			Vector3.ZERO, TileKitPalette.color("clay_flower_cream"))
	TileKitMeshUtils.add_egg(batch, "grass_rooted_gradient",
		head + Vector3.UP * size * 0.025,
		Vector3.UP, size * 0.28, size * 0.21, 3, 5, 1.0,
		Vector3.ZERO, TileKitPalette.color("clay_flower_gold"))


## A second, unmistakably different bloom: four chunky rose-pink petals curl
## upward around a cream bead. Its taller cupped silhouette keeps Flowering
## Grass playful at game zoom without adding texture noise or another material.
static func _add_cupped_flower_head(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, head: Vector3, size: float) -> void:
	var yaw := rng.randf_range(0.0, TAU)
	var petal_color := TileKitPalette.color("blossom_pink")
	for petal in 4:
		var angle := yaw + TAU * float(petal) / 4.0
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var petal_root := head + outward * size * 0.12
		var petal_axis := (outward * 0.64 + Vector3.UP * 0.77).normalized()
		TileKitMeshUtils.add_egg(batch, "grass_rooted_gradient",
			petal_root, petal_axis, size * 0.46, size * 0.27,
			4, 6, 0.82, outward, petal_color)
	TileKitMeshUtils.add_egg(batch, "grass_rooted_gradient",
		head + Vector3.UP * size * 0.035,
		Vector3.UP, size * 0.34, size * 0.20, 4, 6, 1.0,
		Vector3.ZERO, TileKitPalette.color("clay_flower_cream"))
