class_name KitClaySproutsBuilder
extends RefCounted
## Plasticine garden dressing: leaf-pair sprouts, tiny shoots, flowers,
## berries — the modelled-clay top the grass tile is authored against.
##
## Each sprout is a small fan of BLUNT TEARDROP LEAVES (flattened eggs,
## broad face-on and thin edge-on) sharing one base: a tall centre leaf
## with shorter siblings splayed around it. That silhouette, plus smooth
## spheroid normals and real contact shadows, is what reads as pressed
## plasticine rather than modelled grass.
##
## AUTHORING GOTCHA — the runtime scales X/Z to the live cell but leaves Y
## alone (authored 1.70 m footprint → 1.00 m cell, factor ~0.588). Widths
## here are therefore authored ~1.7× their intended in-game size while
## heights are authored at true in-game size; otherwise every sprout
## renders stretched and skinny in the world.


static func build(layer: TileKitLayer, rng: RandomNumberGenerator,
		context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", KitBaseBuilder.HALF)
	var cap_height: Callable = context.get("cap_height", Callable())
	var leaf_key := String(layer.value("leaf_key", "clay_leaf"))
	# The mound wears the TURF colour, not the leaf colour: it is the
	# ground swelling up around the roots, so it must disappear into the
	# plane and leave only the leaves reading as separate pieces.
	var mound_key := String(layer.value("mound_key", "grass_gg_top"))
	var mound_height := float(layer.value("mound_height", 0.055))
	var mound_spread := float(layer.value("mound_spread", 0.95))
	var petal_key := String(layer.value("petal_key", "clay_flower_cream"))
	var centre_key := String(layer.value("flower_centre_key", "clay_flower_gold"))
	var berry_key := String(layer.value("berry_key", "clay_berry"))
	var sprouts: Array = layer.value("sprout_count", [7, 9])
	var shoots: Array = layer.value("shoot_count", [4, 6])
	var flowers: Array = layer.value("flower_count", [2, 4])
	var berries: Array = layer.value("berry_count", [2, 3])
	var leaves: Array = layer.value("leaves_per_sprout", [3, 5])
	var leaf_height: Array = layer.value("leaf_height", [0.15, 0.20])
	var leaf_width: Array = layer.value("leaf_width", [0.075, 0.10])
	var depth_ratio := float(layer.value("leaf_depth_ratio", 0.5))
	var splay: Array = layer.value("splay_degrees", [15.0, 28.0])
	var margin := float(layer.value("edge_margin", 0.16))
	var min_spacing := float(layer.value("min_spacing", 0.34))
	var sink := float(layer.value("root_sink", 0.02))

	var batch := TileKitMeshUtils.MeshBatch.new()
	var limit := maxf(0.05, half - margin)
	# One shared occupancy list: shoots, flowers, and berries all keep clear
	# of the big sprouts (and of each other), so the top stays composed
	# instead of collapsing into a pile.
	var placed: Array[Vector2] = []

	for _sprout in rng.randi_range(int(sprouts[0]), int(sprouts[1])):
		var spot: Variant = _pick_spot(rng, placed, limit, min_spacing)
		if spot == null:
			continue
		var centre: Vector2 = spot
		var sprout_width := rng.randf_range(
			float(leaf_width[0]), float(leaf_width[1]))
		_add_mound(batch, mound_key, _ground(centre, cap_height, 0.0),
			sprout_width * mound_spread, mound_height)
		_add_sprout(batch, rng, leaf_key,
			_ground(centre, cap_height, sink),
			rng.randi_range(int(leaves[0]), int(leaves[1])),
			rng.randf_range(float(leaf_height[0]), float(leaf_height[1])),
			sprout_width, depth_ratio,
			deg_to_rad(rng.randf_range(float(splay[0]), float(splay[1]))),
			rng.randf_range(0.0, TAU))

	# Tiny two/three-leaf shoots: the small punctuation between sprouts.
	for _shoot in rng.randi_range(int(shoots[0]), int(shoots[1])):
		var spot: Variant = _pick_spot(rng, placed, limit, min_spacing * 0.62)
		if spot == null:
			continue
		var centre: Vector2 = spot
		var shoot_width := rng.randf_range(
			float(leaf_width[0]), float(leaf_width[1])) * 0.72
		_add_mound(batch, mound_key, _ground(centre, cap_height, 0.0),
			shoot_width * mound_spread, mound_height * 0.6)
		_add_sprout(batch, rng, leaf_key,
			_ground(centre, cap_height, sink),
			rng.randi_range(2, 3),
			rng.randf_range(float(leaf_height[0]), float(leaf_height[1])) * 0.56,
			shoot_width, depth_ratio,
			deg_to_rad(rng.randf_range(26.0, 40.0)),
			rng.randf_range(0.0, TAU))

	for _flower in rng.randi_range(int(flowers[0]), int(flowers[1])):
		var spot: Variant = _pick_spot(rng, placed, limit, min_spacing * 0.62)
		if spot == null:
			continue
		var centre: Vector2 = spot
		_add_flower(batch, rng, petal_key, centre_key,
			_ground(centre, cap_height, 0.0),
			rng.randf_range(0.075, 0.095))

	for _berry in rng.randi_range(int(berries[0]), int(berries[1])):
		var spot: Variant = _pick_spot(rng, placed, limit, min_spacing * 0.5)
		if spot == null:
			continue
		var centre: Vector2 = spot
		var pair := rng.randi_range(1, 2)
		for index in pair:
			var offset := Vector2(
				cos(float(index) * 2.2), sin(float(index) * 2.2)) * 0.045
			var radius := rng.randf_range(0.038, 0.052)
			# Length 1.18r, not 2r: X/Z is squashed to the live cell while
			# height is not, so an authored sphere renders as a tall egg.
			TileKitMeshUtils.add_egg(batch, berry_key,
				_ground(centre + offset, cap_height, radius * 0.22),
				Vector3.UP, radius * 1.18, radius, 4, 7)

	return {
		"meshes": [{
			"role": "detail",
			"name": "clay_sprouts",
			"mesh": batch.commit(),
			# No cast shadows. At this scale the directional light throws a
			# hard dark spoke from every single leaf, and since the leaves
			# sit close to the turf's own colour those spokes become the
			# dominant read — clusters turn into dark spiders. Grounding
			# comes from the turf mound and SSAO instead.
			"cast_shadow": false,
		}],
	}


static func _ground(centre: Vector2, cap_height: Callable,
		sink: float) -> Vector3:
	var height := 0.0
	if cap_height.is_valid():
		height = float(cap_height.call(centre))
	return Vector3(centre.x, height - sink, centre.y)


## Farthest-of-N candidate placement: natural spread, no grid rhythm, and
## deterministic (fixed candidate budget). Returns null when the tile is
## too crowded to honour `spacing`.
static func _pick_spot(rng: RandomNumberGenerator, placed: Array[Vector2],
		limit: float, spacing: float) -> Variant:
	var best := Vector2.ZERO
	var best_score := -1.0
	for _candidate in 12:
		var candidate := Vector2(
			rng.randf_range(-limit, limit), rng.randf_range(-limit, limit))
		var score := spacing * 2.0
		for existing in placed:
			score = minf(score, candidate.distance_to(existing))
		if score > best_score:
			best_score = score
			best = candidate
	if best_score < spacing * 0.72:
		return null
	placed.append(best)
	return best


## The turf swelling the leaves grow out of: a low oblate dome in the
## ground colour, sunk so only its shoulder shows. Without it the leaves
## meet the flat plane at a hard line and read as props dropped on top.
static func _add_mound(batch: TileKitMeshUtils.MeshBatch, key: String,
		base: Vector3, radius: float, height: float) -> void:
	TileKitMeshUtils.add_egg(batch, key,
		base - Vector3(0.0, height * 0.75, 0.0), Vector3.UP,
		height * 1.75, radius, 4, 9)


## One sprout: a fan of blunt teardrop leaves sharing a base. The centre
## leaf stands tallest and the siblings splay outward, each turned so its
## BROAD face points away from the cluster — the reference's leaf-pair read.
static func _add_sprout(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, leaf_key: String, base: Vector3,
		leaves: int, height: float, width: float, depth_ratio: float,
		splay: float, yaw: float) -> void:
	# Centre leaf: near-vertical, the tallest of the cluster. Only the very
	# bottom is buried — a deeply sunk leaf loses its teardrop base and the
	# whole cluster collapses into one lumpy mound.
	var lean := rng.randf_range(0.0, deg_to_rad(7.0))
	var lean_dir := Vector3(cos(yaw), 0.0, sin(yaw))
	# broad_dir is TANGENTIAL (perpendicular to the lean), never radial: a
	# leaf whose wide face points outward presents its thin edge to the
	# camera, and the cluster reads as dark radiating spider legs.
	TileKitMeshUtils.add_egg(batch, leaf_key,
		base + Vector3(0.0, -height * 0.06, 0.0),
		(Vector3.UP + lean_dir * sin(lean)).normalized(),
		height, width * 0.5, 5, 7, depth_ratio,
		Vector3(-lean_dir.z, 0.0, lean_dir.x))
	# Siblings: splayed outward, shorter, bases nudged toward their lean so
	# the cluster fuses at the root instead of radiating from one point.
	var siblings := maxi(leaves - 1, 0)
	for index in siblings:
		var angle := yaw + PI + TAU * float(index) / float(maxi(siblings, 1)) \
			+ rng.randf_range(-0.3, 0.3)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var tilt := splay + rng.randf_range(-deg_to_rad(4.0), deg_to_rad(4.0))
		var axis := (Vector3.UP + outward * tan(tilt)).normalized()
		var sibling_height := height * rng.randf_range(0.62, 0.84)
		var sibling_width := width * rng.randf_range(0.80, 0.96)
		TileKitMeshUtils.add_egg(batch, leaf_key,
			base + outward * width * 0.16
				+ Vector3(0.0, -sibling_height * 0.07, 0.0),
			axis, sibling_height, sibling_width * 0.5, 5, 7,
			depth_ratio, Vector3(-outward.z, 0.0, outward.x))


## One flower: five ROUND petal discs in a ring around a centre bead, lying
## flat on the turf. Petals are discs (thin on the vertical axis, round in
## plan) rather than outward-pointing ellipses — elongated petals read as
## insect wings from the game's fixed diagonal camera, not as a bloom.
static func _add_flower(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, petal_key: String, centre_key: String,
		base: Vector3, size: float) -> void:
	var yaw := rng.randf_range(0.0, TAU)
	var lift := Vector3(0.0, size * 0.05, 0.0)
	for petal in 5:
		var angle := yaw + TAU * float(petal) / 5.0
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		TileKitMeshUtils.add_egg(batch, petal_key,
			base + lift + outward * size * 0.30,
			Vector3.UP, size * 0.15, size * 0.27, 4, 7)
	TileKitMeshUtils.add_egg(batch, centre_key,
		base + lift, Vector3.UP, size * 0.20, size * 0.18, 4, 7)
