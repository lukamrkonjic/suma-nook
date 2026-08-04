class_name KitClayTuftsBuilder
extends RefCounted
## Suma's own grass: small solid clay sprouts on a clean slab.
##
## The failure ladder that shaped this: big rosettes read as clutter, and a
## dense nub pile read as too much grass. The style references all agree on
## the opposite — a mostly FLAT smooth clay top whose grass identity is the
## sunny colour, punctuated by a FEW chunky sprout accents. So the builder
## has two placements:
##   "accents" (default): 4–6 small egg-lobe sprouts, spaced and kept off
##   the rim, each one a deliberate clay piece — minimal, calm, toy-like.
##   "grid": the tile-periodic pile carpet (kept for denser tile families;
##   requires detail_rotation_variants = 1 so the rhythm survives seams).
## Every sprout is smooth spheroid volume — real clay, never billboards.


static func build(layer: TileKitLayer, rng: RandomNumberGenerator,
		context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", KitBaseBuilder.HALF)
	var cap_height: Callable = context.get("cap_height", Callable())
	var placement := String(layer.value("placement", "accents"))
	var primary_key := String(layer.value("primary_key", "grass_gg_tuft"))
	var root_key := String(layer.value("root_key", "grass_gg_tuft"))
	var spacing := maxf(0.12, float(layer.value("grid_spacing", 0.195)))
	var row_offset := float(layer.value("row_offset_fraction", 0.5))
	var footprint: Array = layer.value("tuft_footprint", [0.17, 0.24])
	var height_ratio := float(layer.value("height_ratio", 0.9))
	var jitter := float(layer.value("position_jitter", 0.045))
	var lobe_count: Array = layer.value("lobe_count", [3, 4])
	var splay: Array = layer.value("splay_degrees", [30.0, 40.0])
	var margin := float(layer.value("edge_margin", 0.18))
	var sink := float(layer.value("root_sink", 0.03))
	var skip := float(layer.value("skip_fraction", 0.0))
	var accents: Array = layer.value("accent_count", [4, 6])
	var min_spacing := float(layer.value("accent_min_spacing", 0.45))

	var batch := TileKitMeshUtils.MeshBatch.new()
	if placement == "accents":
		_build_accents(batch, rng, layer, primary_key, root_key, half,
			cap_height, footprint, height_ratio, lobe_count, splay, margin,
			sink, accents, min_spacing)
		return {
			"meshes": [{
				"role": "detail",
				"name": "clay_tufts",
				"mesh": batch.commit(),
			}],
		}
	# TILE-PERIODIC grid: the span divides into an even number of exact
	# steps with half-step insets, so the nub rhythm CONTINUES across equal
	# neighbours — the boundary gap between two cells' edge nubs is exactly
	# one step, indistinguishable from an interior gap. An inner margin here
	# would print a bright bare lane along every cell seam.
	var span := (half - margin) * 2.0
	var rows := maxi(2, int(round(span / spacing)))
	if rows % 2 == 1:
		rows += 1
	var step := span / float(rows)
	for row in rows:
		var z := -span * 0.5 + (float(row) + 0.5) * step
		# Odd rows shift by the offset fraction and may overhang one edge;
		# the neighbour's identical shifted row fills the matching phase.
		var shift := step * row_offset * float(row % 2)
		for col in rows:
			var x := -span * 0.5 + (float(col) + 0.5) * step + shift
			# Fixed rolls per grid slot: parameter tweaks never rearrange
			# the rest of the carpet.
			var roll_skip := rng.randf()
			var size: float = rng.randf_range(
				float(footprint[0]), float(footprint[1]))
			var yaw := rng.randf_range(0.0, TAU)
			var dx := rng.randf_range(-jitter, jitter)
			var dz := rng.randf_range(-jitter, jitter)
			if roll_skip < skip:
				continue
			var centre := Vector2(x + dx, z + dz)
			var ground := 0.0
			if cap_height.is_valid():
				ground = float(cap_height.call(centre))
			_add_tuft(batch, rng, primary_key, root_key,
				Vector3(centre.x, ground - sink, centre.y),
				size, height_ratio, yaw,
				rng.randi_range(int(lobe_count[0]), int(lobe_count[1])),
				deg_to_rad(rng.randf_range(float(splay[0]), float(splay[1]))))

	return {
		"meshes": [{
			"role": "detail",
			"name": "clay_tufts",
			"mesh": batch.commit(),
			# Dozens of tiny casters throw spiky shadow noise across the
			# plane — the pile grounds itself through tone and SSAO instead.
			"cast_shadow": false,
		}],
	}


## Sparse accent placement: a handful of sprouts dropped with simple
## farthest-candidate rejection so they spread naturally without a grid
## rhythm. Deterministic: a fixed candidate budget per accent, the same
## rolls every rebuild.
static func _build_accents(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, layer: TileKitLayer, primary_key: String,
		root_key: String, half: float, cap_height: Callable,
		footprint: Array, height_ratio: float, lobe_count: Array,
		splay: Array, margin: float, sink: float, accents: Array,
		min_spacing: float) -> void:
	var count := rng.randi_range(int(accents[0]), int(accents[1]))
	var limit := half - margin
	var placed: Array[Vector2] = []
	for _accent in count:
		var best := Vector2.ZERO
		var best_score := -1.0
		for _candidate in 8:
			var candidate := Vector2(
				rng.randf_range(-limit, limit),
				rng.randf_range(-limit, limit))
			var score := INF
			for existing in placed:
				score = minf(score, candidate.distance_to(existing))
			if placed.is_empty():
				score = min_spacing * 2.0
			if score > best_score:
				best_score = score
				best = candidate
		if best_score < min_spacing * 0.55:
			continue
		placed.append(best)
		var size: float = rng.randf_range(
			float(footprint[0]), float(footprint[1]))
		var yaw := rng.randf_range(0.0, TAU)
		var ground := 0.0
		if cap_height.is_valid():
			ground = float(cap_height.call(best))
		_add_tuft(batch, rng, primary_key, root_key,
			Vector3(best.x, ground - sink, best.y),
			size, height_ratio, yaw,
			rng.randi_range(int(lobe_count[0]), int(lobe_count[1])),
			deg_to_rad(rng.randf_range(float(splay[0]), float(splay[1]))))


## One sprout: a sunk crown shoulder, one blunt centre egg, and `lobes`
## shorter ring lobes tilted outward — a small pinched clay plant. The same
## composer serves both placements; the params decide whether it reads as a
## pile nub (0–1 fat lobes, low splay) or an accent rosette (3–4 lobes).
static func _add_tuft(batch: TileKitMeshUtils.MeshBatch,
		rng: RandomNumberGenerator, primary_key: String, root_key: String,
		base: Vector3, footprint: float, height_ratio: float, yaw: float,
		lobes: int, splay: float) -> void:
	# Crown: an oblate shoulder that fuses the sprout into the plane.
	TileKitMeshUtils.add_egg(batch, root_key,
		base + Vector3(0.0, -0.14 * footprint, 0.0), Vector3.UP,
		0.30 * footprint, 0.34 * footprint, 4, 6)
	# Centre: one blunt egg, barely off vertical.
	var centre_lean := rng.randf_range(0.0, deg_to_rad(7.0))
	var centre_dir := rng.randf_range(0.0, TAU)
	TileKitMeshUtils.add_egg(batch, primary_key,
		base + Vector3(0.0, 0.02 * footprint, 0.0),
		Vector3(
			sin(centre_lean) * cos(centre_dir),
			cos(centre_lean),
			sin(centre_lean) * sin(centre_dir)
		),
		0.70 * footprint * height_ratio, 0.22 * footprint, 4, 6)
	# Ring lobes: shorter companions leaning outward; bases offset toward
	# their lean so the cluster fuses through the crown.
	for lobe in lobes:
		var lobe_yaw := yaw + TAU * float(lobe) / float(maxi(lobes, 1)) \
			+ rng.randf_range(-0.28, 0.28)
		var tilt := splay + rng.randf_range(-deg_to_rad(4.0), deg_to_rad(4.0))
		var out := Vector3(cos(lobe_yaw), 0.0, sin(lobe_yaw))
		var axis := Vector3(
			sin(tilt) * out.x, cos(tilt), sin(tilt) * out.z)
		var length := footprint * height_ratio * rng.randf_range(0.50, 0.60)
		TileKitMeshUtils.add_egg(batch, primary_key,
			base + out * 0.08 * footprint
				+ Vector3(0.0, 0.01 * footprint, 0.0),
			axis, length, 0.17 * footprint, 4, 6)
