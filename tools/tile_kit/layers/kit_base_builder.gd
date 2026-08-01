class_name KitBaseBuilder
extends RefCounted
## The structural tile: Suma's stacking contract made visible.
##
## This is the one layer that is NOT free-form art. Its numbers are the grid's
## numbers, and every generated tile shares them so placement, stacking, side
## stacking, and covering keep working:
##
##   footprint          1.70 × 1.70 authored, centred; runtime scales X/Z
##   base body          y −0.50 … −0.18   persists when covered (deep seam —
##                      the chunky rounded cap needs more than the 5.5 cm skin)
##   surface cap        y −0.18 … 0.0     hides when covered
##   walk plane         y  0.0            the flat top props stand on
##
## Inside that envelope it builds the reference look: broad flat top, generous
## rounded top bevel, rounded plan corners, clean vertical sides, a slight
## chamfer at the very bottom. The bevel is the tile's identity — two of these
## side by side form the soft groove the diorama reads as handcrafted blocks.

const TILE := 1.70
const HALF := TILE / 2.0
const BODY_BOTTOM := -0.50
const SEAM := -0.18


static func build(layer: TileKitLayer, rng: RandomNumberGenerator,
		context: Dictionary) -> Dictionary:
	var bevel: float = layer.value("top_bevel", 0.075)
	var corner: float = layer.value("corner_radius", 0.075)
	var segments: int = layer.value("bevel_segments", 6)
	var chamfer: float = layer.value("bottom_chamfer", 0.016)
	# Shell palette keys, so one structural builder serves every material
	# family: grass, moss, earth, snow — same block, different clay.
	var keys := {
		"top": String(layer.value("top_key", "tile_top")),
		"bevel": String(layer.value("bevel_key", "tile_top_bevel")),
		"side": String(layer.value("side_key", "tile_side")),
		"lower": String(layer.value("lower_key", "tile_lower")),
	}

	var mask := int(context.get("neighbour_mask", 0))

	# Surface relief: the material-defining variation for soft tops. ONE
	# colour, sculpted height — dunes on sand, pillowed drifts on snow, low
	# swells on mud — read through lighting exactly like the clay references,
	# where flat colour patches only ever read as printed dots. The relief
	# feathers to zero before the bevel rim, so the tile's silhouette, seams,
	# and stacking contract stay untouched.
	var relief := _relief_function(layer, rng, bevel, mask == 0)
	var relief_edge_feather: float = layer.value("relief_edge_feather", 0.16)

	# Downstream layers place across the WHOLE footprint — a detail carpet
	# that stops at the bevel leaves a bald strip along every tile seam, and
	# a 3x3 of those reads as a grid of gaps. surface_half is therefore the
	# true half-footprint; cap_height tells each layer how far the surface
	# has curved down at any local point — bevel drop plus relief — so edge
	# placements hug the real surface instead of floating over it.
	context["surface_half"] = HALF
	context["flat_half"] = HALF - bevel
	context["surface_top"] = 0.0
	var bevel_height := _cap_height_function(bevel, corner)
	context["cap_height"] = func(local: Vector2) -> float:
		return float(bevel_height.call(local)) + float(relief.call(local))

	# Connected mode: when any edge has a same-family neighbour, that edge
	# loses its bevel and wall entirely — the cap runs dead flush to the
	# boundary at the walk plane, so two fused tiles meet as one continuous
	# surface with no groove. This is how the reference game's platforms
	# read as single slabs: the chunky block silhouette belongs to the RIM
	# of a land mass, never to its interior seams.
	if mask != 0:
		var world_origin: Vector2 = context.get("world_origin", Vector2.ZERO)
		var connected_height := _connected_height_function(bevel, mask,
			relief, world_origin, relief_edge_feather)
		context["cap_height"] = connected_height
		return {
			"meshes": [
				{"role": "base", "name": "tile_body",
					"mesh": _body(0.0015, chamfer, keys)},
				{"role": "surface", "name": "tile_cap",
					"mesh": _connected_cap(bevel, segments, keys, mask,
						connected_height,
						int(layer.value("relief_resolution", 18)))},
			],
		}

	# Basin mode reshapes the cap into a rimmed pool: a walkable ring at the
	# walk plane, an inner wall, a recessed floor, and a still-water plane —
	# the pond tile's whole identity is this silhouette change.
	var basin_depth: float = layer.value("basin_depth", 0.0)
	if basin_depth > 0.0:
		var rim: float = layer.value("basin_rim", 0.17)
		context["cap_height"] = _basin_height_function(bevel, corner,
			bevel_height, rim, basin_depth)
		context["basin_floor"] = -basin_depth
		return {
			"meshes": [
				{"role": "base", "name": "tile_body",
					"mesh": _body(corner, chamfer, keys)},
				{"role": "surface", "name": "tile_cap",
					"mesh": _basin_cap(bevel, corner, segments, keys, rim,
						basin_depth)},
				{"role": "surface", "name": "tile_water",
					"mesh": _basin_water(bevel, corner, rim, basin_depth,
						String(layer.value("water_key", "water_blue")))},
			],
		}

	return {
		"meshes": [
			{"role": "base", "name": "tile_body", "mesh": _body(corner, chamfer, keys)},
			{"role": "surface", "name": "tile_cap",
				"mesh": _cap(bevel, corner, segments, keys, relief,
					int(layer.value("relief_resolution", 18)))},
		],
	}


## Deterministic single-colour height relief for the cap top. Styles:
##   "none"    flat walkable plane (grass, paving)
##   "pillow"  soft rounded undulation — moss, mulch
##   "dunes"   directional waves with noise breakup — sand
##   "sculpted_dunes" staggered asymmetric wind strokes — source-like sand
##             dunes and broad snow drifts, periodic across the tile footprint
##   "heaps"   distinct rounded mounds with textured ground between — snow
##             drifts and mud piles, the "mini mountains" read
## The feather to the rim is part of the function, so every consumer (mesh,
## clutter settle, paver settle) sees one truth.
static func _relief_function(layer: TileKitLayer, rng: RandomNumberGenerator,
		bevel: float, feather_to_tile_edge := true) -> Callable:
	var style := String(layer.value("relief_style", "none"))
	var amplitude: float = layer.value("relief_amplitude", 0.0)
	if style == "none" or amplitude <= 0.0:
		return func(_local: Vector2) -> float: return 0.0
	var frequency: float = layer.value("relief_frequency", 2.2)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.38
	var dune_yaw := rng.randf() * TAU
	var dune_direction := Vector2(cos(dune_yaw), sin(dune_yaw))
	var dune_phase := rng.randf() * TAU
	var sculpted_dunes: Callable
	if style == "sculpted_dunes":
		sculpted_dunes = _sculpted_dune_function(layer, rng)

	# Heap centres are drawn once, deterministically, and kept far enough
	# inside that the rim feather never slices a mound in half — a cut heap
	# reads as damage, a whole heap reads as a drift someone piled up.
	var heaps: Array = []
	var micro: float = layer.value("relief_micro", amplitude * 0.14)
	if style == "heaps":
		var flat_limit := HALF - bevel
		var count_band: Array = layer.value("relief_heap_count", [4, 6])
		var radius_band: Array = layer.value("relief_heap_radius", [0.16, 0.28])
		var heap_count := rng.randi_range(int(count_band[0]), int(count_band[1]))
		for index in heap_count:
			var radius := rng.randf_range(float(radius_band[0]),
				float(radius_band[1]))
			var reach := flat_limit - radius * 0.55 - 0.10
			heaps.append({
				"centre": Vector2(rng.randf_range(-reach, reach),
					rng.randf_range(-reach, reach)),
				"radius": radius,
				"height": rng.randf_range(0.55, 1.0),
			})
	var captured_corner: float = layer.value("corner_radius", 0.075)
	return func(local: Vector2) -> float:
		# Feather: full relief in the interior, easing to dead flat at the
		# bevel rim so the silhouette every neighbour sees is authored, not
		# noisy — that is what keeps seams and side-stacking clean. Distance
		# uses the rounded-rect SDF so the feather follows the actual rim,
		# corners included.
		var feather := 1.0
		if feather_to_tile_edge:
			var q := Vector2(absf(local.x), absf(local.y)) \
				- Vector2.ONE * (HALF - captured_corner)
			var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
			var inset := -(
				outside + minf(maxf(q.x, q.y), 0.0) - captured_corner
			)
			var rim_distance := inset - bevel
			feather = smoothstep(
				0.0,
				float(layer.value("relief_edge_feather", 0.16)),
				rim_distance
			)
		if feather <= 0.0:
			return 0.0
		if style == "sculpted_dunes":
			return feather * float(sculpted_dunes.call(local)) * amplitude
		if style == "furrows":
			# Parallel tilled ridges: shaped |sin| crests along one axis,
			# axis-aligned so the field reads as deliberately worked rows.
			var rows_count := float(layer.value("relief_rows", 5))
			var axis := local.x if int(layer.value("relief_axis", 0)) == 0 else local.y
			var crest := pow(absf(sin(axis * PI * rows_count / (HALF - bevel))), 1.35)
			var breakup := noise.get_noise_2d(local.x, local.y) * 0.10
			return feather * (crest + breakup) * amplitude
		if style == "heaps":
			# Distinct mounds: a smooth cosine dome per heap, summed, over a
			# quiet micro-noise ground so the flats between heaps still have
			# tooth. The heap term dominates; the micro term is texture.
			var mound := 0.0
			for heap: Dictionary in heaps:
				var distance: float = (local - (heap["centre"] as Vector2)).length()
				var radius: float = heap["radius"]
				if distance < radius:
					var t := distance / radius
					mound += float(heap["height"]) \
						* pow(cos(t * PI * 0.5), 2.0)
			var ground := (noise.get_noise_2d(local.x, local.y) * 0.5 + 0.5) * micro
			return feather * (minf(mound, 1.35) * amplitude + ground)
		var value: float
		if style == "dunes":
			var wave := sin(local.dot(dune_direction) * frequency * 2.6 + dune_phase)
			value = wave * 0.62 + noise.get_noise_2d(local.x, local.y) * 2.0 * 0.38
		else:
			value = noise.get_noise_2d(local.x, local.y) * 2.0
		# Bipolar relief swings both ways around the walk plane — churned wet
		# ground with troughs AND ridges, the mud read. Default keeps the
		# floor: mounds only rise. The feather MULTIPLIES — an early-out
		# alone leaves a height cliff at the rim band's inner edge.
		if bool(layer.value("relief_bipolar", false)):
			return feather * clampf(value, -1.0, 1.0) * amplitude
		return feather * maxf(0.0, value * 0.5 + 0.5) * amplitude


## Periodic field of hand-brushed dune strokes. Each stroke has a long curved
## shoulder and a narrower lee-side groove, which reproduces the authored
## sand/snow language much more closely than uniform sine bands. Periodic
## copies make both the height and its derivative agree at opposite tile edges,
## so a baked topology variant remains seamless when repeated by the runtime.
static func _sculpted_dune_function(
	layer: TileKitLayer,
	rng: RandomNumberGenerator
) -> Callable:
	var seed_offset := int(layer.value("dune_seed_offset", 0))
	var pattern_rng := RandomNumberGenerator.new()
	pattern_rng.seed = hash("%d|sculpted_dunes|%d" % [rng.seed, seed_offset])
	var scale: float = layer.value("dune_scale", 0.72)
	var amount: float = clampf(layer.value("dune_amount", 0.5), 0.0, 1.0)
	var softness: float = clampf(layer.value("dune_softness", 0.7), 0.0, 1.0)
	var irregularity: float = clampf(
		layer.value("dune_irregularity", 0.65), 0.0, 1.0
	)
	var lee_depth: float = clampf(layer.value("dune_lee_depth", 0.3), 0.0, 1.0)
	var direction_degrees: float = layer.value(
		"dune_direction_degrees",
		pattern_rng.randf_range(0.0, 360.0)
	)
	var prevailing_yaw := deg_to_rad(direction_degrees)
	var height_exponent: float = layer.value("dune_height_exponent", 1.0)
	# A few readable strokes look hand-sculpted. Packing too many into one
	# cell raises the whole cap into a featureless plateau.
	var stroke_count := roundi(lerpf(3.0, 8.0, amount))
	var strokes: Array[Dictionary] = []
	for _index in stroke_count:
		var yaw := prevailing_yaw + pattern_rng.randf_range(
			-0.85 * irregularity,
			0.85 * irregularity
		)
		strokes.append({
			"centre": Vector2(
				pattern_rng.randf_range(-HALF, HALF),
				pattern_rng.randf_range(-HALF, HALF)
			),
			"axis": Vector2(cos(yaw), sin(yaw)),
			"length": scale * pattern_rng.randf_range(
				0.72 - irregularity * 0.12,
				1.26 + irregularity * 0.22
			),
			# Thin wind-brushed shoulders create visible gradients at the
			# measured 6 cm sand amplitude. Broad Gaussians overlap into a flat
			# raised sheet and only become readable at destructive strengths.
			"width": scale * pattern_rng.randf_range(
				0.065,
				0.145 + irregularity * 0.035
			),
			"curve": pattern_rng.randf_range(-0.72, 0.72) * irregularity,
			"height": pattern_rng.randf_range(
				0.72 - irregularity * 0.18,
				1.0
			),
		})
	var ridge_power := lerpf(5.2, 2.0, softness)
	var along_power := lerpf(4.2, 2.0, softness)
	return func(world: Vector2) -> float:
		# Evaluate in one repeating authoring cell. Neighbouring copies of every
		# stroke contribute across the wrap, making the function truly periodic.
		var local := Vector2(
			fposmod(world.x + HALF, TILE) - HALF,
			fposmod(world.y + HALF, TILE) - HALF
		)
		var accumulation := 0.0
		for stroke: Dictionary in strokes:
			var axis: Vector2 = stroke["axis"]
			var across_axis := Vector2(-axis.y, axis.x)
			var length: float = stroke["length"]
			var width: float = stroke["width"]
			for copy_y in range(-1, 2):
				for copy_x in range(-1, 2):
					var centre: Vector2 = stroke["centre"] + Vector2(
						copy_x * TILE,
						copy_y * TILE
					)
					var relative := local - centre
					var along := relative.dot(axis)
					if absf(along) > length * 1.55:
						continue
					var across := relative.dot(across_axis)
					across -= float(stroke["curve"]) * along * along \
						/ maxf(length, 0.001)
					var side_width := width * (0.68 if across > 0.0 else 1.12)
					var along_norm := absf(along) / maxf(length, 0.001)
					var across_norm := absf(across) / maxf(side_width, 0.001)
					var ridge := exp(
						-pow(along_norm, along_power)
						- pow(across_norm, ridge_power)
					) * float(stroke["height"])
					# The lee groove pinches one shoulder instead of subtracting a
					# trench. Subtractive grooves looked convincing at medium
					# strength but became canyon walls at the slider's dramatic end.
					var groove_across := (
						across - width * lerpf(0.78, 1.08, irregularity)
					) / maxf(width * lerpf(0.72, 0.42, 1.0 - softness), 0.001)
					var groove := exp(
						-pow(along_norm, maxf(1.5, along_power * 0.82))
						- groove_across * groove_across
					)
					var shaped := ridge * (1.0 - groove * lee_depth * 0.42)
					accumulation += shaped
		# Exponential union is a smooth maximum: overlapping brush strokes
		# reinforce one another without hard winner-change creases. Keeping the
		# Gaussian tails (instead of thresholding them) is what gives snow its
		# polished roll and keeps maximum-strength sand free of faceted cliffs.
		var value := 1.0 - exp(-accumulation * 1.35)
		return pow(value, maxf(0.35, height_exponent))


## Height function for a connected tile: the bevel drop applies only near
## OPEN edges (no neighbour), measured per-edge, so fused edges sit at the
## walk plane right up to the boundary and match their neighbour exactly.
## Relief rides on top, sampled in WORLD space so its texture continues
## across the seam, and feathered only against open edges.
static func _connected_height_function(bevel: float, mask: int,
		relief: Callable, world_origin: Vector2, edge_feather := 0.16) -> Callable:
	var open_north := (mask & 1) == 0
	var open_east := (mask & 2) == 0
	var open_south := (mask & 4) == 0
	var open_west := (mask & 8) == 0
	return func(local: Vector2) -> float:
		var inset := INF
		if open_north:
			inset = minf(inset, local.y + HALF)
		if open_south:
			inset = minf(inset, HALF - local.y)
		if open_west:
			inset = minf(inset, local.x + HALF)
		if open_east:
			inset = minf(inset, HALF - local.x)
		var drop := 0.0
		if inset < bevel:
			var t := 1.0 - clampf(inset, 0.0, bevel) / bevel
			drop = -bevel * (1.0 - sqrt(maxf(0.0, 1.0 - t * t)))
		# World-anchored relief: the same world position produces the same
		# height on both sides of a fused seam.
		var feather := 1.0 if inset == INF \
			else smoothstep(0.0, edge_feather, inset - bevel)
		var sculpt := float(relief.call(world_origin + local)) * feather
		return drop + sculpt


## Cap for a connected tile: a displaced full-footprint grid (the height
## function carries bevel and relief), plus wall strips down to the seam
## along open edges only.
static func _connected_cap(bevel: float, segments: int, keys: Dictionary,
		mask: int, height_at: Callable, resolution: int) -> ArrayMesh:
	var batch := TileKitMeshUtils.MeshBatch.new()
	var cells := maxi(resolution, 12)
	var step := TILE / float(cells)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in cells + 1:
		for column in cells + 1:
			var local := Vector2(-HALF + column * step, -HALF + row * step)
			var height := float(height_at.call(local))
			vertices.append(Vector3(local.x, height, local.y))
			var d := step * 0.5
			var left := float(height_at.call(local - Vector2(d, 0.0)))
			var right := float(height_at.call(local + Vector2(d, 0.0)))
			var back := float(height_at.call(local - Vector2(0.0, d)))
			var front := float(height_at.call(local + Vector2(0.0, d)))
			normals.append(Vector3(left - right, d * 2.0, back - front).normalized())
	var stride := cells + 1
	for row in cells:
		for column in cells:
			var a := row * stride + column
			var b := row * stride + column + 1
			var c := (row + 1) * stride + column + 1
			var d := (row + 1) * stride + column
			indices.append_array([a, b, c, a, c, d])
	batch.add(String(keys["top"]), vertices, normals, indices)

	# Wall strips on open edges: from the bevel's foot down to the seam.
	var wall_edges := [
		[1, Vector2(0.0, -1.0)], [2, Vector2(1.0, 0.0)],
		[4, Vector2(0.0, 1.0)], [8, Vector2(-1.0, 0.0)],
	]
	for entry: Array in wall_edges:
		if (mask & int(entry[0])) != 0:
			continue
		var outward: Vector2 = entry[1]
		var along := Vector2(-outward.y, outward.x)
		var wall_vertices := PackedVector3Array()
		var wall_normals := PackedVector3Array()
		var wall_indices := PackedInt32Array()
		var strips := 8
		for strip in strips + 1:
			var t := float(strip) / float(strips) - 0.5
			var point := outward * HALF + along * (TILE * t)
			var wall_normal := Vector3(outward.x, 0.0, outward.y)
			wall_vertices.append(Vector3(point.x, SEAM, point.y))
			wall_normals.append(wall_normal)
			wall_vertices.append(Vector3(point.x, -bevel, point.y))
			wall_normals.append(wall_normal)
		for strip in strips:
			var a := strip * 2
			var b := strip * 2 + 1
			var c := strip * 2 + 3
			var d := strip * 2 + 2
			# Outward wall winding mirrors the ring-shell convention; the
			# along direction decides which order faces out.
			if outward.x + outward.y > 0.0:
				wall_indices.append_array([a, d, c, a, c, b])
			else:
				wall_indices.append_array([a, c, d, a, b, c])
		batch.add(String(keys["side"]), wall_vertices, wall_normals, wall_indices)
	return batch.commit()


## Basin cap: walkable rim ring at y = 0, inner wall, recessed floor.
static func _basin_cap(bevel: float, corner: float, segments: int,
		keys: Dictionary, rim: float, depth: float) -> ArrayMesh:
	var batch := TileKitMeshUtils.MeshBatch.new()
	# Outer wall + bevel identical to the standard cap.
	TileKitMeshUtils.add_ring_shell(batch, String(keys["side"]), HALF, corner, 3, [
		[0.0, SEAM, 0.0],
		[0.0, -bevel, 0.0],
	])
	var rings: Array = []
	for step in segments + 1:
		var angle := (PI / 2.0) * float(step) / float(segments)
		rings.append([
			bevel * (1.0 - cos(angle)),
			-bevel * (1.0 - sin(angle)),
			angle * 0.5,
		])
	TileKitMeshUtils.add_ring_shell(batch, String(keys["bevel"]), HALF, corner,
		maxi(segments, 3), rings)

	var outline: Array = TileKitMeshUtils.rounded_rect_outline(HALF, corner,
		maxi(segments, 3))
	var points: PackedVector2Array = outline[0]
	var outwards: PackedVector2Array = outline[1]
	var count := points.size()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var inner_inset := bevel + rim

	# Rim ring cap: outer edge at the bevel line, inner edge at the pool lip,
	# flat at y = 0 — the ledge you walk on.
	for index in count:
		var outer := points[index] - outwards[index] * bevel
		var inner := points[index] - outwards[index] * inner_inset
		vertices.append(Vector3(outer.x, 0.0, outer.y))
		normals.append(Vector3.UP)
		vertices.append(Vector3(inner.x, 0.0, inner.y))
		normals.append(Vector3.UP)
	for index in count:
		var next := (index + 1) % count
		var a := index * 2
		var b := index * 2 + 1
		var c := next * 2 + 1
		var d := next * 2
		indices.append_array([a, d, c, a, c, b])
	batch.add(String(keys["top"]), vertices, normals, indices)

	# Inner wall: pool lip down to the floor, faces INWARD.
	vertices = PackedVector3Array()
	normals = PackedVector3Array()
	indices = PackedInt32Array()
	for index in count:
		var inner := points[index] - outwards[index] * inner_inset
		var inward := -Vector3(outwards[index].x, 0.0, outwards[index].y)
		vertices.append(Vector3(inner.x, -depth, inner.y))
		normals.append(inward)
		vertices.append(Vector3(inner.x, 0.0, inner.y))
		normals.append(inward)
	for index in count:
		var next := (index + 1) % count
		var a := index * 2
		var b := index * 2 + 1
		var c := next * 2 + 1
		var d := next * 2
		# Inward-facing wall: mirrored winding relative to the outward shells.
		indices.append_array([a, c, d, a, b, c])
	batch.add(String(keys["side"]), vertices, normals, indices)

	# Pool floor.
	TileKitMeshUtils.add_rect_cap(batch, String(keys["side"]), HALF, corner,
		maxi(segments, 3), inner_inset, -depth, true)
	return batch.commit()


## Still-water plane sitting a little below the rim.
static func _basin_water(bevel: float, corner: float, rim: float, depth: float,
		water_key: String) -> ArrayMesh:
	var batch := TileKitMeshUtils.MeshBatch.new()
	TileKitMeshUtils.add_rect_cap(batch, water_key, HALF, corner, 6,
		bevel + rim - 0.008, -depth * 0.45, true)
	return batch.commit()


## Basin cap-height: rim ledge at 0, pool interior at the floor depth, outer
## bevel unchanged — so lily pads settle onto the water's floor level and
## rim clutter stays on the ledge.
static func _basin_height_function(bevel: float, corner: float,
		bevel_height: Callable, rim: float, depth: float) -> Callable:
	return func(local: Vector2) -> float:
		var q := Vector2(absf(local.x), absf(local.y)) \
			- Vector2.ONE * (HALF - corner)
		var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
		var inset := -(outside + minf(maxf(q.x, q.y), 0.0) - corner)
		if inset >= bevel + rim:
			# Inside the pool: the water surface is the effective ground.
			return -depth * 0.45
		return float(bevel_height.call(local))


## Pure local-XZ -> surface-Y function for the cap: 0 on the flat top, the
## quarter-round drop across the bevel band, clamped to the wall top beyond
## the footprint. Uses the rounded-rect signed distance so corners follow the
## same curve as edges.
static func _cap_height_function(bevel: float, corner: float) -> Callable:
	return func(local: Vector2) -> float:
		var q := Vector2(absf(local.x), absf(local.y)) - Vector2.ONE * (HALF - corner)
		var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
		var signed := outside + minf(maxf(q.x, q.y), 0.0) - corner
		var inset := -signed
		if inset >= bevel:
			return 0.0
		var t := 1.0 - clampf(inset, 0.0, bevel) / bevel
		return -bevel * (1.0 - sqrt(maxf(0.0, 1.0 - t * t)))


## Structural body, −0.50…−0.18. Persists when covered, so it is plain by
## design: side wall in the two structural greens, tiny bottom chamfer so a
## floating or edge-exposed tile ends in a soft line instead of a razor edge.
static func _body(corner: float, chamfer: float, keys: Dictionary) -> ArrayMesh:
	var batch := TileKitMeshUtils.MeshBatch.new()
	var side_split := lerpf(BODY_BOTTOM, SEAM, 0.42)
	# Rings are listed BOTTOM-UP — add_ring_shell's winding contract.
	TileKitMeshUtils.add_ring_shell(batch, String(keys["side"]), HALF, corner, 3, [
		[0.0, side_split, 0.0],
		[0.0, SEAM, 0.0],
	])
	TileKitMeshUtils.add_ring_shell(batch, String(keys["lower"]), HALF, corner, 3, [
		[chamfer, BODY_BOTTOM, -PI / 4.0],
		[0.0, BODY_BOTTOM + chamfer, 0.0],
		[0.0, side_split, 0.0],
	])
	TileKitMeshUtils.add_rect_cap(batch, String(keys["lower"]), HALF, corner, 3,
		chamfer, BODY_BOTTOM, false)
	# Flush lid at the seam so the body is watertight when the cap is hidden
	# by a covering tile.
	TileKitMeshUtils.add_rect_cap(batch, String(keys["side"]), HALF, corner, 3,
		0.0, SEAM, true)
	return batch.commit()


## Surface cap, −0.18…0.0: wall, rounded bevel, flat top, and — when the
## preset asks for it — a sculpted relief blanket over that top. The bevel
## band and the top are separate palette keys — the highlight edge is painted
## into the material split exactly as in the reference, not left to lighting
## luck.
static func _cap(bevel: float, corner: float, segments: int, keys: Dictionary,
		relief: Callable, resolution: int) -> ArrayMesh:
	var batch := TileKitMeshUtils.MeshBatch.new()

	# Side wall from the seam up to where the bevel arc begins.
	TileKitMeshUtils.add_ring_shell(batch, String(keys["side"]), HALF, corner, 3, [
		[0.0, SEAM, 0.0],
		[0.0, -bevel, 0.0],
	])

	# Quarter-round bevel: from the wall (pitch 0) curving to flat (pitch
	# PI/2). Analytic pitch per ring is what makes it read as one continuous
	# soft curve at any resolution.
	var rings: Array = []
	for step in segments + 1:
		var angle := (PI / 2.0) * float(step) / float(segments)
		rings.append([
			bevel * (1.0 - cos(angle)),
			-bevel * (1.0 - sin(angle)),
			angle * 0.5,
		])
	TileKitMeshUtils.add_ring_shell(batch, String(keys["bevel"]), HALF, corner,
		maxi(segments, 3), rings)

	# The flat walkable top, inset by the bevel, exactly at y = 0.
	TileKitMeshUtils.add_rect_cap(batch, String(keys["top"]), HALF, corner,
		maxi(segments, 3), bevel, 0.0, true)
	_add_relief_blanket(batch, String(keys["top"]), bevel, corner, relief,
		resolution)
	return batch.commit()


## Displaced grid laid over the flat top: the same colour as the top, a hair
## proud of it, height from the relief function, positions clipped to the
## rounded flat outline. Where relief is zero the blanket hugs the cap and
## disappears; where it rises, lighting sculpts the single colour into dunes
## or drifts — variation with no second tone anywhere.
static func _add_relief_blanket(batch: TileKitMeshUtils.MeshBatch, key: String,
		bevel: float, corner: float, relief: Callable, resolution: int) -> void:
	# Probe: skip the whole blanket for flat styles.
	if float(relief.call(Vector2.ZERO)) <= 0.0 \
			and float(relief.call(Vector2(0.2, 0.13))) <= 0.0:
		return
	var flat_edge := HALF - bevel
	var cells := maxi(resolution, 8)
	var lift := 0.0008
	var step := (flat_edge * 2.0) / float(cells)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for row in cells + 1:
		for column in cells + 1:
			var local := Vector2(-flat_edge + column * step,
				-flat_edge + row * step)
			local = _clip_to_flat_outline(local, bevel, corner)
			var height := float(relief.call(local))
			vertices.append(Vector3(local.x, lift + height, local.y))
			# Finite-difference normal from the shared relief function, so
			# shading matches the sculpt exactly.
			var d := step * 0.5
			var left := float(relief.call(local - Vector2(d, 0.0)))
			var right := float(relief.call(local + Vector2(d, 0.0)))
			var back := float(relief.call(local - Vector2(0.0, d)))
			var front := float(relief.call(local + Vector2(0.0, d)))
			normals.append(Vector3(left - right, d * 2.0, back - front).normalized())

	var stride := cells + 1
	for row in cells:
		for column in cells:
			var a := row * stride + column
			var b := row * stride + column + 1
			var c := (row + 1) * stride + column + 1
			var d := (row + 1) * stride + column
			# The repo's verified up-facing winding under Godot's clockwise
			# front-face rule.
			indices.append_array([a, b, c, a, c, d])
	batch.add(key, vertices, normals, indices)


## Pulls a grid vertex that falls outside the rounded flat-top outline back
## onto it, so the blanket's corners follow the tile's rounded plan instead
## of poking square tips over the bevel.
static func _clip_to_flat_outline(local: Vector2, bevel: float,
		corner: float) -> Vector2:
	var flat_edge := HALF - bevel
	var r := clampf(corner - bevel * 0.35, 0.01, flat_edge - 0.001)
	var inner := flat_edge - r
	var q := Vector2(absf(local.x) - inner, absf(local.y) - inner)
	if q.x <= 0.0 or q.y <= 0.0:
		return local
	var excess := q.length() - r
	if excess <= 0.0:
		return local
	var pullback := q.normalized() * excess
	return Vector2(
		local.x - sign(local.x) * pullback.x,
		local.y - sign(local.y) * pullback.y
	)
