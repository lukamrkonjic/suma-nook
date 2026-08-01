class_name KitDressingBuilder
extends RefCounted
## Broad soft patches across the tile top — moss cushions, snow pillows,
## soil beds, wet sheens.
##
## Two profiles, chosen per layer:
##
## "cushion" (default) — a shallow raised pillow with a rolled edge and real
## analytic normals. It catches its own broad highlight and settles a soft
## contact line into the ground, so a moss patch reads as MATERIAL resting on
## the tile. This retired the flat painted circles that read as stains on
## every judged capture.
##
## "sheen" — the old flat sky-lit decal, kept deliberately for marks that ARE
## flat: wet mud, damp rings, shadows of dampness. Never use it for moss,
## snow, or soil.
##
## Placement is clustered, not scattered: centres are drawn around two or
## three loose region anchors, so blobs overlap into organic archipelagos and
## leave genuinely clear ground elsewhere. Uniform scatter reads as noise;
## regions read as composition.

## High enough to clear directional shadow acne from the top plane — at
## 1.5 mm the patches sit inside the shadow bias band and render as murky
## puddles; at 4 mm they are clean while still reading as flat paint.
const LIFT := 0.004


static func build(layer: TileKitLayer, rng: RandomNumberGenerator,
		context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var top: float = context.get("surface_top", 0.0)
	var cap_height: Callable = context.get("cap_height", Callable())
	var margin: float = layer.value("edge_margin", 0.02)
	var scale: float = layer.value("scale_multiplier", 1.0)
	var weights: Dictionary = layer.value("color_weights", {"dressing_light": 1.0})
	var profile := String(layer.value("patch_profile", "cushion"))
	var height_scale: float = layer.value("height_scale", 1.0)
	var edge_softness: float = clampf(layer.value("edge_softness", 0.55), 0.0, 1.0)

	# Overlap is a CHOICE, not a fate. On: centres gravitate to region
	# anchors and blobs merge into organic archipelagos (the grass look).
	# Off: centres spread uniformly and any candidate that would touch an
	# existing blob is rejected — clean separated patches for mud, mulch,
	# and sand, where merged blobs read as a stain.
	var allow_overlap: bool = layer.value("allow_overlap", true)
	var region_count := _int_range(rng, layer.value("region_count", [2, 3]))
	var anchors: Array[Vector2] = []
	for index in region_count:
		anchors.append(Vector2(
			rng.randf_range(-half * 0.55, half * 0.55),
			rng.randf_range(-half * 0.55, half * 0.55)
		))
	var spread: float = layer.value("region_spread", 0.30)

	var batch := TileKitMeshUtils.MeshBatch.new()
	var placed: Array[Dictionary] = []
	for size_key: String in ["large", "medium", "small"]:
		var count := _int_range(rng, layer.value(size_key + "_count", [3, 5]))
		var radius_band: Array = layer.value(size_key + "_radius", [0.1, 0.2])
		for index in count:
			var radius := rng.randf_range(radius_band[0], radius_band[1]) * scale
			if profile == "cushion":
				# Below this footprint a raised patch reads as a dot at the
				# gameplay camera. Grow it or it has no business existing.
				radius = maxf(radius, 0.075)
			var aspect_band: Array = layer.value("aspect", [0.70, 1.35])
			var aspect := rng.randf_range(aspect_band[0], aspect_band[1])
			var radius_x := radius
			var radius_z := radius * aspect
			var reach := maxf(radius_x, radius_z)
			var limit := half - margin - reach
			if limit <= 0.0:
				continue
			var centre: Vector2
			var placed_ok := true
			if profile == "cushion" and size_key == "small" and not placed.is_empty():
				# Small cushions never stand alone — a lone raised dot reads as
				# a droplet. They lobe onto an existing patch, extending its
				# silhouette the way moss creeps outward from an anchor mass.
				var host: Dictionary = placed[rng.randi() % placed.size()]
				var host_angle := rng.randf() * TAU
				var host_reach: float = float(host["radius"]) * rng.randf_range(0.7, 1.0)
				centre = Vector2(
					clampf(float((host["centre"] as Vector2).x)
						+ cos(host_angle) * host_reach, -limit, limit),
					clampf(float((host["centre"] as Vector2).y)
						+ sin(host_angle) * host_reach, -limit, limit)
				)
			elif allow_overlap:
				var anchor := anchors[rng.randi() % anchors.size()]
				centre = Vector2(
					clampf(anchor.x + rng.randf_range(-spread, spread), -limit, limit),
					clampf(anchor.y + rng.randf_range(-spread, spread), -limit, limit)
				)
			else:
				placed_ok = false
				for attempt in 14:
					centre = Vector2(rng.randf_range(-limit, limit),
						rng.randf_range(-limit, limit))
					var clear := true
					for existing: Dictionary in placed:
						var minimum: float = reach + float(existing["radius"]) + 0.015
						if centre.distance_to(existing["centre"]) < minimum:
							clear = false
							break
					if clear:
						placed_ok = true
						break
			if not placed_ok:
				continue
			var irregularity_band: Array = layer.value("irregularity", [0.08, 0.14])
			var irregularity := rng.randf_range(
				float(irregularity_band[0]), float(irregularity_band[1]))
			var smoothing := int(layer.value("smoothing_passes", 3))
			if profile == "cushion":
				# A raised form shows its outline in silhouette, where a flat
				# decal only showed it in plan — the same jitter that read as
				# organic on a sheen reads as a boiled egg on a cushion.
				# Push the wobble up and smooth one pass less, so patches come
				# out lobed and hand-torn rather than oval.
				irregularity = clampf(irregularity * 1.9 + 0.06, 0.10, 0.34)
				smoothing = maxi(2, smoothing - 1)
			var radii := TileKitMeshUtils.soft_blob_outline(
				rng,
				layer.value("outline_points", 20),
				irregularity,
				smoothing
			)
			var key := TileKitPalette.weighted_key(rng, weights)
			# Cushion height grows with footprint but stays a SHALLOW form:
			# a broad moss bed rises a few centimetres, a small tuft less.
			# Sheen patches stay flat by definition.
			var cushion := 0.0
			if profile == "cushion":
				cushion = clampf(reach * 0.30, 0.010, 0.048) * height_scale
			TileKitMeshUtils.add_cushion_blob(batch, key,
				Vector2(centre.x, centre.y), top + LIFT,
				radius_x, radius_z, rng.randf() * TAU, radii, cap_height,
				cushion, edge_softness)
			placed.append({
				"centre": centre,
				"radius": (radius_x + radius_z) * 0.5,
			})

	# Downstream context: clutter prefers to sit on or near these.
	context["dressing_blobs"] = placed
	# Cushions are real forms and ground themselves with their own shadow;
	# flat sheens stay shadowless so they cannot double-darken the surface.
	return {
		"meshes": [{"role": "detail", "name": "tile_dressing",
			"mesh": batch.commit(), "cast_shadow": profile == "cushion"}],
	}


static func _int_range(rng: RandomNumberGenerator, band: Variant) -> int:
	if band is Array and (band as Array).size() >= 2:
		return rng.randi_range(int((band as Array)[0]), int((band as Array)[1]))
	return int(band)
