@tool
class_name TileCompositionPattern
extends Resource
## Turns a count into an ART-DIRECTED set of anchor positions.
##
## This resource is the reason generated tiles do not read as random noise.
## Uniform scatter produces the two failures the brief bans at once: accidental
## clumps that look like mistakes, and an even sprinkle that looks like a
## particle system. Every pattern here instead defines broad zones, deliberate
## empty space, and clustering, then perturbs inside those constraints.
##
## Output is a list of positions in normalized tile space (-1..1 on both axes),
## already respecting `border_margin`. Callers still apply minimum separation
## and mask rejection, because those depend on module footprint.

@export var pattern: TileForgeConstants.Composition = TileForgeConstants.Composition.THREE_CLUSTERS

@export_group("Framing")
## Keep anchors this far inside the boundary, in normalized units. Details that
## touch the tile edge are the single most common seam artefact, so this is
## deliberately generous by default.
@export_range(0.0, 0.6, 0.01) var border_margin := 0.16
## Fraction of the tile that must stay visibly empty. Enforced by the
## validator, and used here to size the clearing zones.
@export_range(0.0, 0.9, 0.01) var empty_space_target := 0.42

@export_group("Clustering")
## 0 = anchors spread evenly across their zone, 1 = anchors pull hard into the
## zone centre. Mid values give the "a few deliberate groups" reading.
@export_range(0.0, 1.0, 0.01) var clustering := 0.55
## Random offset applied to every anchor, normalized units. Small on purpose:
## the composition, not the jitter, should carry the variation.
@export_range(0.0, 0.5, 0.01) var jitter := 0.11
## Pulls anchors towards `focal_point` regardless of pattern.
@export_range(0.0, 1.0, 0.01) var focal_bias := 0.0
@export var focal_point := Vector2.ZERO

@export_group("Flow")
## Direction used by DIAGONAL_FLOW and by YAW_FROM_FLOW module rotation.
@export_range(-180.0, 180.0, 1.0) var flow_angle_deg := 35.0
## How strongly density follows the flow direction.
@export_range(0.0, 1.0, 0.01) var flow_strength := 0.7

@export_group("Density")
## Multiplies the requested count. Lets one pattern be reused at two densities
## without duplicating the resource.
@export_range(0.2, 2.0, 0.05) var density_scale := 1.0
## Breaks up mechanical regularity in RING/FOUR_CORNERS by dropping members.
@export_range(0.0, 0.6, 0.01) var dropout := 0.12

@export_group("Custom")
## Used by CUSTOM_ANCHORS. Normalized tile space.
@export var custom_anchors: PackedVector2Array = []
## Regions that must stay empty, as (centre.x, centre.y, radius) triples in
## normalized space. Anchors landing inside are rejected.
@export var clearings: PackedVector3Array = []


## Produces anchors WITH a role, which is what gives a tile a focal hierarchy
## instead of a uniform field. Each entry is (x, y, role) where role indexes
## TileForgeConstants.Role.
##
## The seven authored templates live here. Older patterns are kept for recipes
## that already reference them and are assigned roles by prominence.
func composed(count: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	var wanted := maxi(0, int(round(float(count) * density_scale)))
	if wanted == 0:
		return PackedVector3Array()
	var raw := _composed_raw(wanted, rng)
	var result := PackedVector3Array()
	var limit := 1.0 - border_margin
	for entry in raw:
		var moved := Vector2(entry.x, entry.y)
		if focal_bias > 0.0:
			moved = moved.lerp(focal_point, focal_bias)
		# A hero is nudged less than an accent: the subject should land where it
		# was composed, and the supporting pieces can absorb the variation.
		var wobble: float = jitter * (0.35 if int(entry.z) == 0 else 1.0)
		moved += Vector2(rng.randfn(0.0, wobble * 0.5), rng.randfn(0.0, wobble * 0.5))
		moved.x = clampf(moved.x, -limit, limit)
		moved.y = clampf(moved.y, -limit, limit)
		if _inside_clearing(moved):
			continue
		result.append(Vector3(moved.x, moved.y, entry.z))
	return result


func _composed_raw(count: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	match pattern:
		TileForgeConstants.Composition.ONE_HERO_TWO_SUPPORT:
			return _one_hero_two_support(count, rng)
		TileForgeConstants.Composition.THREE_ASYMMETRIC_CLUSTERS:
			return _asymmetric_clusters(count, rng)
		TileForgeConstants.Composition.EDGE_CLUSTER_WITH_OPEN_CENTRE:
			return _edge_cluster_open_centre(count, rng)
		TileForgeConstants.Composition.DENSE_CORNER_SPARSE_OPPOSITE:
			return _dense_corner(count, rng)
		TileForgeConstants.Composition.FOUR_LARGE_PATCHES:
			return _four_large_patches(count, rng)
		TileForgeConstants.Composition.BROAD_FIELD_WITH_TWO_CLEARINGS:
			return _broad_field_two_clearings(count, rng)
		TileForgeConstants.Composition.DIAGONAL_FLOW:
			return _roles_by_order(_diagonal_flow(count, rng))
	# Legacy patterns keep working; the first anchor becomes the hero.
	return _roles_by_order(_raw_anchors(count, rng))


## One dominant form, two clear supports, and a couple of small accents that
## sit well away from the subject. The most reliable composition in the set.
func _one_hero_two_support(count: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	var result := PackedVector3Array()
	# The hero sits off-centre on the diagonal, never dead centre.
	var hero := Vector2(
		rng.randf_range(0.10, 0.34) * (1.0 if rng.randf() < 0.5 else -1.0),
		rng.randf_range(0.10, 0.34) * (1.0 if rng.randf() < 0.5 else -1.0)
	)
	result.append(Vector3(hero.x, hero.y, TileForgeConstants.Role.HERO))
	# Supports flank it at unequal distances and unequal angles.
	var base_angle := rng.randf() * TAU
	for index in 2:
		if result.size() >= count:
			return result
		var angle := base_angle + PI * rng.randf_range(0.55, 1.45) * float(index + 1)
		var distance := rng.randf_range(0.42, 0.68)
		var point := hero + Vector2(cos(angle), sin(angle)) * distance
		result.append(Vector3(point.x, point.y, TileForgeConstants.Role.SUPPORT))
	# Accents live in the emptiest quadrant, which is the one opposite the hero.
	var away := -hero.normalized() if hero.length() > 0.01 else Vector2(1.0, -1.0).normalized()
	while result.size() < count:
		var offset := away * rng.randf_range(0.4, 0.78) + Vector2(
			rng.randfn(0.0, 0.2), rng.randfn(0.0, 0.2)
		)
		result.append(Vector3(offset.x, offset.y, TileForgeConstants.Role.ACCENT))
	return result


## Three groups of deliberately unequal size and spacing. Each group has its own
## largest member, so the tile reads at two levels: group, then form.
func _asymmetric_clusters(count: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	var result := PackedVector3Array()
	var centres := PackedVector2Array()
	var angle := rng.randf() * TAU
	# Unequal radii and unequal angular steps: evenly spread group centres are
	# the tell that a composition was generated.
	for index in 3:
		angle += TAU / 3.0 * rng.randf_range(0.6, 1.4)
		centres.append(Vector2(cos(angle), sin(angle)) * rng.randf_range(0.24, 0.6))
	var shares := _unequal_shares(count, 3, rng)
	var hero_group := rng.randi_range(0, 2)
	for group in 3:
		var share: int = shares[group]
		for index in share:
			if result.size() >= count:
				break
			var spread: float = lerpf(0.4, 0.16, clustering)
			var point: Vector2 = centres[group] + _spread(index, share, rng, spread)
			var role := TileForgeConstants.Role.SUPPORT
			if index == 0:
				role = (
					TileForgeConstants.Role.HERO
					if group == hero_group
					else TileForgeConstants.Role.SUPPORT
				)
			elif index > 1:
				role = TileForgeConstants.Role.ACCENT
			result.append(Vector3(point.x, point.y, role))
	return result


## Forms hug one or two edges and leave the middle of the tile completely open.
## The empty centre is the composition; it is what a resting area looks like.
func _edge_cluster_open_centre(count: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	var result := PackedVector3Array()
	var dominant := rng.randi_range(0, 3)
	var secondary := (dominant + rng.randi_range(1, 3)) % 4
	for index in count:
		var edge := dominant if rng.randf() < 0.68 else secondary
		var along := rng.randf_range(-0.72, 0.72)
		var depth := rng.randf_range(0.54, 0.8)
		var point := Vector2.ZERO
		match edge:
			0: point = Vector2(along, -depth)
			1: point = Vector2(depth, along)
			2: point = Vector2(along, depth)
			_: point = Vector2(-depth, along)
		var role := TileForgeConstants.Role.SUPPORT
		if index == 0:
			role = TileForgeConstants.Role.HERO
		elif index > count / 2:
			role = TileForgeConstants.Role.ACCENT
		result.append(Vector3(point.x, point.y, role))
	return result


## Weight piles into one corner and thins to nothing across the diagonal. The
## strongest density gradient in the set, and the easiest to read as intent.
func _dense_corner(count: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	var result := PackedVector3Array()
	var corner := Vector2(
		1.0 if rng.randf() < 0.5 else -1.0,
		1.0 if rng.randf() < 0.5 else -1.0
	) * 0.62
	for index in count:
		# Squared bias pulls most members towards the corner while still letting
		# one or two drift across the tile.
		var t := rng.randf()
		var pull := t * t
		var point := corner.lerp(-corner, pull) + Vector2(
			rng.randfn(0.0, 0.18), rng.randfn(0.0, 0.18)
		)
		var role := TileForgeConstants.Role.SUPPORT
		if index == 0:
			role = TileForgeConstants.Role.HERO
		elif pull > 0.55:
			role = TileForgeConstants.Role.ACCENT
		result.append(Vector3(point.x, point.y, role))
	return result


## Four broad patches of unequal size with real lanes between them.
func _four_large_patches(count: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	var result := PackedVector3Array()
	var centres := [
		Vector2(-0.42, -0.44), Vector2(0.46, -0.38),
		Vector2(0.40, 0.46), Vector2(-0.46, 0.42),
	]
	# Nudge each patch so the lanes between them are not a clean cross.
	var nudged := PackedVector2Array()
	for centre in centres:
		nudged.append(centre + Vector2(rng.randfn(0.0, 0.09), rng.randfn(0.0, 0.09)))
	var shares := _unequal_shares(count, 4, rng)
	var hero_patch := rng.randi_range(0, 3)
	for patch in 4:
		var share: int = shares[patch]
		for index in share:
			if result.size() >= count:
				break
			var point: Vector2 = nudged[patch] + _spread(index, share, rng, 0.26)
			var role := TileForgeConstants.Role.SUPPORT
			if index == 0 and patch == hero_patch:
				role = TileForgeConstants.Role.HERO
			elif index > 0:
				role = TileForgeConstants.Role.ACCENT
			result.append(Vector3(point.x, point.y, role))
	return result


## A full field with two carved holes. Density high, but the clearings keep it
## readable — the difference between a lush tile and a texture.
func _broad_field_two_clearings(count: int, rng: RandomNumberGenerator) -> PackedVector3Array:
	var result := PackedVector3Array()
	var voids: Array[Vector3] = []
	for _index in 2:
		voids.append(Vector3(
			rng.randf_range(-0.5, 0.5),
			rng.randf_range(-0.5, 0.5),
			rng.randf_range(0.3, 0.46)
		))
	var attempts := 0
	var salt := int(rng.seed & 0xFFF)
	while result.size() < count and attempts < count * 40:
		attempts += 1
		var candidate := Vector2(
			TileSeedUtil.halton(attempts + salt, 2) * 1.6 - 0.8,
			TileSeedUtil.halton(attempts + salt, 3) * 1.6 - 0.8
		)
		var blocked := false
		for hole in voids:
			if candidate.distance_to(Vector2(hole.x, hole.y)) < hole.z:
				blocked = true
				break
		if blocked:
			continue
		var role := TileForgeConstants.Role.SUPPORT
		if result.is_empty():
			role = TileForgeConstants.Role.HERO
		elif result.size() % 3 == 2:
			role = TileForgeConstants.Role.ACCENT
		result.append(Vector3(candidate.x, candidate.y, role))
	return result


## Assigns roles to a legacy pattern by placement order: first is the subject,
## the next third support it, the rest are accents.
func _roles_by_order(points: PackedVector2Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	var supports: int = maxi(1, points.size() / 3)
	for index in points.size():
		var role := TileForgeConstants.Role.ACCENT
		if index == 0:
			role = TileForgeConstants.Role.HERO
		elif index <= supports:
			role = TileForgeConstants.Role.SUPPORT
		result.append(Vector3(points[index].x, points[index].y, role))
	return result


## Deterministically produce `count` anchors. `count` is already clamped by the
## caller against the detail rule's min/max. Retained for callers that do not
## need the role hierarchy.
func anchors(count: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var wanted := maxi(0, int(round(float(count) * density_scale)))
	if wanted == 0:
		return PackedVector2Array()
	var raw := _raw_anchors(wanted, rng)
	var result := PackedVector2Array()
	var limit := 1.0 - border_margin
	for point in raw:
		var moved := point
		if focal_bias > 0.0:
			moved = moved.lerp(focal_point, focal_bias)
		moved += Vector2(
			rng.randfn(0.0, jitter * 0.5),
			rng.randfn(0.0, jitter * 0.5)
		)
		moved.x = clampf(moved.x, -limit, limit)
		moved.y = clampf(moved.y, -limit, limit)
		if _inside_clearing(moved):
			continue
		result.append(moved)
	return result


func _inside_clearing(point: Vector2) -> bool:
	for clearing in clearings:
		if point.distance_to(Vector2(clearing.x, clearing.y)) < clearing.z:
			return true
	return false


func _raw_anchors(count: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	match pattern:
		TileForgeConstants.Composition.CENTRAL_FOCUS:
			return _central_focus(count, rng)
		TileForgeConstants.Composition.THREE_CLUSTERS:
			return _clusters(count, rng, 3)
		TileForgeConstants.Composition.FOUR_CORNERS_WITH_GAPS:
			return _four_corners(count, rng)
		TileForgeConstants.Composition.DIAGONAL_FLOW:
			return _diagonal_flow(count, rng)
		TileForgeConstants.Composition.EDGE_BIASED:
			return _edge_biased(count, rng)
		TileForgeConstants.Composition.PATCHES:
			return _clusters(count, rng, 2)
		TileForgeConstants.Composition.RING:
			return _ring(count, rng)
		TileForgeConstants.Composition.SPARSE_ACCENTS:
			return _sparse_accents(count, rng)
		TileForgeConstants.Composition.DENSE_FIELD_WITH_CLEARINGS:
			return _dense_with_clearings(count, rng)
		TileForgeConstants.Composition.CUSTOM_ANCHORS:
			return _custom(count, rng)
	return _clusters(count, rng, 3)


## One dominant group slightly off-centre, plus a couple of satellites. Never
## dead-centre: exact symmetry is the fastest way to look procedural.
func _central_focus(count: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var result := PackedVector2Array()
	var hub := Vector2(rng.randf_range(-0.18, 0.18), rng.randf_range(-0.18, 0.18))
	var main := maxi(1, int(round(float(count) * 0.7)))
	for index in main:
		result.append(hub + _spread(index, main, rng, 0.38))
	for index in count - main:
		var angle := rng.randf() * TAU
		result.append(hub + Vector2(cos(angle), sin(angle)) * rng.randf_range(0.5, 0.82))
	return result


## The workhorse: a few groups of unequal size with real gaps between them.
func _clusters(count: int, rng: RandomNumberGenerator, groups: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	var centers := _unequal_centers(groups, rng)
	var shares := _unequal_shares(count, centers.size(), rng)
	for group in centers.size():
		var share: int = shares[group]
		var radius: float = lerpf(0.46, 0.2, clustering)
		for index in share:
			result.append(centers[group] + _spread(index, share, rng, radius))
	return result


func _four_corners(count: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var result := PackedVector2Array()
	var corners := [
		Vector2(-0.55, -0.55), Vector2(0.55, -0.55),
		Vector2(0.55, 0.55), Vector2(-0.55, 0.55),
	]
	# Drop one corner outright so the tile never reads as fourfold symmetric.
	var skipped := rng.randi_range(0, 3)
	var slot := 0
	for index in count:
		var corner := slot % 4
		while corner == skipped:
			slot += 1
			corner = slot % 4
		var base: Vector2 = corners[corner]
		result.append(base + _spread(index, count, rng, 0.3))
		slot += 1
	return result


func _diagonal_flow(count: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var result := PackedVector2Array()
	var direction := Vector2.RIGHT.rotated(deg_to_rad(flow_angle_deg))
	var across := Vector2(-direction.y, direction.x)
	for index in count:
		var t: float = (float(index) + rng.randf() * 0.8) / maxf(1.0, float(count))
		var along: float = lerpf(-0.78, 0.78, t)
		var spread: float = rng.randfn(0.0, lerpf(0.42, 0.14, flow_strength))
		result.append(direction * along + across * spread)
	return result


func _edge_biased(count: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var result := PackedVector2Array()
	# Weight edges unevenly: one edge dominant, one secondary, two sparse.
	var weights := PackedFloat32Array([
		rng.randf_range(0.8, 1.0),
		rng.randf_range(0.35, 0.7),
		rng.randf_range(0.1, 0.4),
		rng.randf_range(0.1, 0.4),
	])
	for index in count:
		var edge := TileSeedUtil.weighted_index(rng, weights)
		var along := rng.randf_range(-0.8, 0.8)
		var depth := rng.randf_range(0.52, 0.82)
		match edge:
			0: result.append(Vector2(along, -depth))
			1: result.append(Vector2(depth, along))
			2: result.append(Vector2(along, depth))
			_: result.append(Vector2(-depth, along))
	return result


func _ring(count: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var result := PackedVector2Array()
	var radius := rng.randf_range(0.46, 0.62)
	var start := rng.randf() * TAU
	for index in count:
		if rng.randf() < dropout:
			continue
		var angle := start + TAU * float(index) / maxf(1.0, float(count))
		# Per-member radius wobble keeps it from reading as a drawn circle.
		var r := radius * rng.randf_range(0.86, 1.12)
		result.append(Vector2(cos(angle), sin(angle)) * r)
	return result


## Deliberately few, deliberately far apart. Used for "a couple of accents on
## an otherwise clean tile" — the single most valuable composition in a
## miniature collection.
func _sparse_accents(count: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var result := PackedVector2Array()
	var attempts := 0
	while result.size() < count and attempts < count * 40:
		attempts += 1
		var candidate := Vector2(
			rng.randf_range(-0.78, 0.78),
			rng.randf_range(-0.78, 0.78)
		)
		var ok := true
		for existing in result:
			if existing.distance_to(candidate) < 0.62:
				ok = false
				break
		if ok:
			result.append(candidate)
	return result


func _dense_with_clearings(count: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var result := PackedVector2Array()
	# Carve two or three clearings first, then fill everything else densely.
	var voids: Array[Vector3] = []
	var void_count := rng.randi_range(2, 3)
	for _index in void_count:
		voids.append(Vector3(
			rng.randf_range(-0.6, 0.6),
			rng.randf_range(-0.6, 0.6),
			rng.randf_range(0.24, 0.42) * (0.6 + empty_space_target)
		))
	var attempts := 0
	while result.size() < count and attempts < count * 30:
		attempts += 1
		# Halton keeps the fill even without the visible lattice of a grid.
		var candidate := Vector2(
			TileSeedUtil.halton(attempts + int(rng.seed & 0xFFF), 2) * 1.7 - 0.85,
			TileSeedUtil.halton(attempts + int(rng.seed & 0xFFF), 3) * 1.7 - 0.85
		)
		var blocked := false
		for hole in voids:
			if candidate.distance_to(Vector2(hole.x, hole.y)) < hole.z:
				blocked = true
				break
		if not blocked:
			result.append(candidate)
	return result


func _custom(count: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var result := PackedVector2Array()
	if custom_anchors.is_empty():
		return _clusters(count, rng, 3)
	for index in count:
		var base: Vector2 = custom_anchors[index % custom_anchors.size()]
		result.append(base)
	return result


## Group centres at unequal distances. Equal spacing is what makes procedural
## placement look procedural, so this deliberately breaks it.
func _unequal_centers(groups: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var result := PackedVector2Array()
	var angle := rng.randf() * TAU
	for index in groups:
		angle += TAU / float(groups) * rng.randf_range(0.62, 1.38)
		var radius := rng.randf_range(0.2, 0.56)
		result.append(Vector2(cos(angle), sin(angle)) * radius)
	return result


## Split a count into unequal shares. A 5/3/1 split reads as composed; a
## 3/3/3 split reads as generated.
func _unequal_shares(count: int, groups: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var result := PackedInt32Array()
	var remaining := count
	for index in groups:
		var left := groups - index
		if left == 1:
			result.append(remaining)
			break
		var average := float(remaining) / float(left)
		var take: int = clampi(
			int(round(average * rng.randf_range(0.55, 1.6))),
			1,
			maxi(1, remaining - (left - 1))
		)
		result.append(take)
		remaining -= take
	return result


## Spread member `index` of `total` inside a group. Uses a golden-angle spiral
## so members never overlap exactly and never form a visible ring.
func _spread(index: int, total: int, rng: RandomNumberGenerator, radius: float) -> Vector2:
	if total <= 1:
		return Vector2(rng.randfn(0.0, radius * 0.25), rng.randfn(0.0, radius * 0.25))
	var golden := 2.39996323
	var angle := float(index) * golden + rng.randf() * 0.5
	var r := radius * sqrt((float(index) + rng.randf_range(0.3, 0.9)) / float(total))
	return Vector2(cos(angle), sin(angle)) * r
