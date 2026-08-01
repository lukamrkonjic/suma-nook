class_name KitClutterBuilder
extends RefCounted
## Small scattered details — the layer that turns one structural block into
## many different tiles.
##
## The shape vocabulary covers the tile families in the image-generation
## research (grass, mossy floor, dirt/mulch, stone, snow): green dots and
## clumps, pebbles, twigs, wood chips, leaf litter, snow lumps, and the
## occasional whimsical mushroom. A preset picks its `shapes` list and its
## palette weights; the builder never invents either, so a snow tile cannot
## sprout terracotta and a stone field cannot grow leaves unless a preset
## says so.
##
## Placement rules are shared by every family: roughly 60% of pieces settle
## near dressing patches when any exist, minimum spacing keeps negative
## space, and every piece sits ON the cap surface — including the bevel, so
## scatter reaches the true tile edge and repetition shows no bald seams.

const ALL_SHAPES := ["dot", "oval", "leaf_pair", "lobed_clump", "nub",
	"pebble", "stone_chip", "twig", "wood_chip", "leaf_litter", "mushroom",
	"snow_lump", "bud", "boulder", "lily_pad", "crystal", "footprint"]


static func build(layer: TileKitLayer, rng: RandomNumberGenerator,
		context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var blobs: Array = context.get("dressing_blobs", [])
	var margin: float = layer.value("edge_margin", 0.03)
	var spacing: float = layer.value("min_spacing", 0.06)
	var scale: float = layer.value("scale_multiplier", 1.0)
	var on_blob: float = layer.value("on_dressing_fraction", 0.6)
	var weights: Dictionary = layer.value("color_weights", {"clutter_light": 1.0})
	var shapes: Array = layer.value("shapes", ["dot", "oval", "leaf_pair",
		"lobed_clump", "nub"])
	var count := KitDressingBuilder._int_range(rng, layer.value("count", [7, 13]))

	var batch := TileKitMeshUtils.MeshBatch.new()
	var placed: Array[Vector2] = []
	var limit := half - margin
	# Clustered even without dressing: a few deterministic anchors gather most
	# pieces into small compositions with genuinely open ground between them.
	# Uniform scatter — any piece anywhere — is the machine tell the reference
	# never shows; things accumulate where other things already are.
	var anchors: Array[Vector2] = []
	var anchor_count := 2 + (rng.randi() % 2)
	for index in anchor_count:
		anchors.append(Vector2(
			rng.randf_range(-limit * 0.62, limit * 0.62),
			rng.randf_range(-limit * 0.62, limit * 0.62)))
	var cluster_fraction: float = layer.value("cluster_fraction", 0.7)
	var cluster_radius: float = layer.value("cluster_radius", 0.24)
	var attempts := 0
	while placed.size() < count and attempts < count * 12:
		attempts += 1
		var centre: Vector2
		if not blobs.is_empty() and rng.randf() < on_blob:
			var blob: Dictionary = blobs[rng.randi() % blobs.size()]
			var blob_centre: Vector2 = blob["centre"]
			var blob_radius: float = blob["radius"]
			var angle := rng.randf() * TAU
			centre = blob_centre + Vector2(cos(angle), sin(angle)) \
				* rng.randf_range(0.0, blob_radius * 1.1)
		elif rng.randf() < cluster_fraction:
			var anchor := anchors[rng.randi() % anchors.size()]
			var angle := rng.randf() * TAU
			var distance := absf(rng.randfn(0.0, cluster_radius * 0.55))
			centre = anchor + Vector2(cos(angle), sin(angle)) * distance
		else:
			centre = Vector2(rng.randf_range(-limit, limit),
				rng.randf_range(-limit, limit))
		if absf(centre.x) > limit or absf(centre.y) > limit:
			continue
		var too_close := false
		for existing in placed:
			if existing.distance_to(centre) < spacing:
				too_close = true
				break
		if too_close:
			continue
		placed.append(centre)

		var diameter_band: Array = layer.value("diameter", [0.05, 0.11])
		var diameter := rng.randf_range(diameter_band[0], diameter_band[1]) * scale
		var height_band: Array = layer.value("height", [0.008, 0.018])
		var piece_height := rng.randf_range(height_band[0], height_band[1]) * scale
		var key := TileKitPalette.weighted_key(rng, weights)
		var surface_y := top
		if cap_height.is_valid():
			surface_y = top + float(cap_height.call(centre))
		var origin := Vector3(centre.x, surface_y, centre.y)
		var shape := String(shapes[rng.randi() % shapes.size()])
		_add_shape(batch, layer, rng, shape, key, origin, diameter, piece_height)

	context["clutter_points"] = placed
	return {
		"meshes": [{"role": "detail", "name": "tile_clutter",
			"mesh": batch.commit(), "cast_shadow": false}],
	}


static func _add_shape(batch: TileKitMeshUtils.MeshBatch, layer: TileKitLayer,
		rng: RandomNumberGenerator, shape: String, key: String,
		origin: Vector3, diameter: float, piece_height: float) -> void:
	var yaw := rng.randf() * TAU
	match shape:
		"dot":
			TileKitMeshUtils.add_dome(batch, key, origin,
				diameter * 0.5, diameter * 0.5, maxf(piece_height * 0.4, 0.003), yaw)
		"oval":
			TileKitMeshUtils.add_dome(batch, key, origin,
				diameter * 0.55, diameter * 0.38, maxf(piece_height * 0.4, 0.003), yaw)
		"leaf_pair":
			var offset := Vector3(cos(yaw), 0.0, sin(yaw)) * diameter * 0.28
			TileKitMeshUtils.add_dome(batch, key, origin + offset,
				diameter * 0.34, diameter * 0.22, piece_height, yaw)
			TileKitMeshUtils.add_dome(batch, key, origin - offset,
				diameter * 0.30, diameter * 0.20, piece_height * 0.85,
				yaw + PI * 0.9)
		"lobed_clump":
			for lobe in 3:
				var lobe_yaw := rng.randf() * TAU
				TileKitMeshUtils.add_dome(batch, key,
					origin + Vector3(cos(lobe_yaw), 0.0, sin(lobe_yaw)) * diameter * 0.22,
					diameter * 0.30, diameter * 0.30,
					piece_height * rng.randf_range(0.8, 1.25), lobe_yaw)
		"nub":
			TileKitMeshUtils.add_dome(batch, key, origin,
				diameter * 0.42, diameter * 0.42, piece_height * 1.4, yaw)
		"pebble":
			# A clay pebble is a fat squashed dome, slightly oval, sunk a
			# touch so it sits IN the ground rather than on it.
			TileKitMeshUtils.add_dome(batch, key,
				origin - Vector3(0.0, diameter * 0.06, 0.0),
				diameter * 0.55, diameter * 0.45,
				diameter * rng.randf_range(0.30, 0.42), yaw, 5, 14)
		"stone_chip":
			# Flatter and broader than a pebble — a worn flag fragment.
			TileKitMeshUtils.add_dome(batch, key,
				origin - Vector3(0.0, diameter * 0.05, 0.0),
				diameter * 0.75, diameter * 0.60,
				diameter * rng.randf_range(0.14, 0.20), yaw, 4, 14)
		"twig":
			# A near-horizontal thin blade with a gentle arc. Wood keys only
			# by convention of the presets that request it.
			var direction := Vector3(cos(yaw), 0.0, sin(yaw))
			var length := diameter * rng.randf_range(1.6, 2.4)
			var rise := diameter * 0.22
			var p0 := origin + direction * (-length * 0.5) + Vector3.UP * 0.004
			var p3 := origin + direction * (length * 0.5) + Vector3.UP * 0.004
			var mid := origin + Vector3.UP * (rise + 0.004)
			TileKitMeshUtils.add_blade(batch, key,
				p0, p0.lerp(mid, 0.6), p3.lerp(mid, 0.6), p3,
				diameter * 0.16, 0.9, 6, 8, 2)
		"wood_chip":
			# Elongated very flat sliver, scattered like mulch.
			TileKitMeshUtils.add_dome(batch, key,
				origin - Vector3(0.0, diameter * 0.03, 0.0),
				diameter * 0.62, diameter * 0.24,
				diameter * rng.randf_range(0.10, 0.16), yaw, 3, 10)
		"leaf_litter":
			# A fallen leaf with real thickness: a low oval chip that catches
			# an edge highlight. The flat 4 mm decal version read as confetti
			# dots from the gameplay camera.
			TileKitMeshUtils.add_dome(batch, key, origin,
				diameter * 0.5, diameter * 0.34,
				maxf(piece_height * 0.8, 0.008), yaw, 3, 10)
		"mushroom":
			# Squat stem dome with a wider cap dome — the one whimsical
			# accent in the vocabulary. Cap colour comes from a dedicated
			# param so presets can pick terracotta or cream caps.
			var cap_key := String(layer.value("mushroom_cap_key", "accent_terracotta"))
			var stem_height := piece_height * rng.randf_range(2.2, 3.0)
			TileKitMeshUtils.add_dome(batch, "accent_cream", origin,
				diameter * 0.20, diameter * 0.20, stem_height, yaw, 4, 10)
			TileKitMeshUtils.add_dome(batch, cap_key,
				origin + Vector3.UP * (stem_height * 0.82),
				diameter * 0.44, diameter * 0.44,
				diameter * rng.randf_range(0.26, 0.34), yaw, 5, 12)
		"boulder":
			# A hero rock: one big main mass with a shoulder lobe, tall
			# enough to change the tile's silhouette rather than dust it.
			TileKitMeshUtils.add_dome(batch, key,
				origin - Vector3(0.0, diameter * 0.10, 0.0),
				diameter * 0.52, diameter * 0.44,
				diameter * rng.randf_range(0.42, 0.55), yaw, 6, 16)
			var shoulder_yaw := yaw + rng.randf_range(1.6, 2.6)
			TileKitMeshUtils.add_dome(batch, key,
				origin + Vector3(cos(shoulder_yaw), 0.0, sin(shoulder_yaw)) 					* diameter * 0.34 - Vector3(0.0, diameter * 0.08, 0.0),
				diameter * 0.30, diameter * 0.26,
				diameter * rng.randf_range(0.22, 0.30), shoulder_yaw, 5, 12)
		"lily_pad":
			# A pond decal: flat rounded pad floating at the piece's origin
			# height (the basin's water level via cap_height).
			TileKitMeshUtils.add_dome(batch, key,
				origin + Vector3.UP * 0.006,
				diameter * 0.5, diameter * 0.46, 0.005, yaw, 2, 12)
		"bud":
			# A closed flower bud: slim stem dome with a small rounded head
			# in the piece's own colour — floral without a single petal.
			var bud_height := piece_height * rng.randf_range(2.6, 3.4)
			TileKitMeshUtils.add_dome(batch, "grass_root", origin,
				diameter * 0.14, diameter * 0.14, bud_height, yaw, 4, 8)
			TileKitMeshUtils.add_dome(batch, key,
				origin + Vector3.UP * (bud_height * 0.85),
				diameter * 0.42, diameter * 0.42,
				diameter * rng.randf_range(0.34, 0.42), yaw, 5, 12)
		"crystal":
			# A reusable faceted mineral cluster: one tall six-sided shard and
			# two smaller companions. Low segment counts keep the silhouette
			# angular so it catches light differently from organic scatter.
			var shard_height := maxf(piece_height * 3.0, diameter * 0.95)
			TileKitMeshUtils.add_dome(batch, key, origin,
				diameter * 0.24, diameter * 0.22, shard_height, yaw, 2, 6)
			for shard in 2:
				var shard_yaw := yaw + (-0.85 if shard == 0 else 1.15)
				var offset := Vector3(cos(shard_yaw), 0.0, sin(shard_yaw)) \
					* diameter * 0.25
				TileKitMeshUtils.add_dome(batch, key, origin + offset,
					diameter * 0.14, diameter * 0.13,
					shard_height * (0.48 if shard == 0 else 0.62),
					shard_yaw, 2, 5)
		"footprint":
			# One piece represents a paired impression. The material remains
			# recipe-controlled, so the same vocabulary serves snow, mud, sand,
			# or a stylized painted trail.
			var forward := Vector3(cos(yaw), 0.0, sin(yaw))
			var side := Vector3(-forward.z, 0.0, forward.x)
			for foot in 2:
				var offset := forward * diameter * (float(foot) - 0.5) * 0.72 \
					+ side * diameter * (0.18 if foot == 0 else -0.18)
				TileKitMeshUtils.add_dome(batch, key,
					origin + offset + Vector3.UP * 0.001,
					diameter * 0.28, diameter * 0.13, 0.004,
					yaw + PI * 0.5, 2, 10)
		"snow_lump":
			TileKitMeshUtils.add_dome(batch, key,
				origin - Vector3(0.0, diameter * 0.04, 0.0),
				diameter * rng.randf_range(0.5, 0.75),
				diameter * rng.randf_range(0.5, 0.75),
				diameter * rng.randf_range(0.28, 0.40), yaw, 5, 14)
		_:
			TileKitMeshUtils.add_dome(batch, key, origin,
				diameter * 0.5, diameter * 0.5, piece_height, yaw)
