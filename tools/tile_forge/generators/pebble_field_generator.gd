@tool
class_name PebbleFieldGenerator
extends TileLayerGenerator
## Gravel, stony ground, scattered pebbles, rocky dirt.
##
## Scatter, separation, border exclusion, and bedding stay in TileDetailPlacer.
## What lives here is the two rules that separate observed gravel from sprinkled
## gravel:
##
##   1. a stone RESTS. Its up axis leans towards the surface normal it sits on,
##      and its yaw is free, so no two stones present the same silhouette to the
##      three-quarter camera.
##   2. a group of stones has the big ones in the middle and the small ones at
##      its edge. Grading the outermost members down is the single cheapest rule
##      that makes a gravel patch look settled rather than emitted, and it is
##      the reason this generator exists at all.
##
## The grade is deliberately small. Past roughly 18% the outer stones stop
## reading as the same material as the inner ones and the patch turns into a
## gradient, so the drop is clamped here regardless of what a recipe asks for.
##
## No mesh surfaces are produced: each instance carries a
## TileForgeConstants.SLOT_* name and the baker merges one surface per slot.
##
## Params: read from `ctx.recipe.custom_params` under "<rule_name>.<key>", and
## overridden by a TileSurfaceLayer's own `params` when the lab supplies one.
##   normal_align     0.6   lean strength used when the rule leaves it at 0
##   cluster_radius   0.20  LIVE metres; grouping distance for the size grade
##   edge_scale_drop  0.18  fraction the outermost stone is shrunk (hard cap)
##   grade_start      0.45  normalised rank at which the grade starts biting

## Placement stream name. TileDetailPlacer appends the rule name, so two pebble
## rules on one tile never correlate.
const CHANNEL := "pebble_field"
## Lean applied when a rule left `normal_align_strength` at 0. A stone flat on a
## sloped top reads as a floating disc, so "no answer" must not mean "upright".
const DEFAULT_NORMAL_ALIGN := 0.6
## Hard ceiling on the size grade. See the class note.
const MAX_EDGE_DROP := 0.18


func generator_id() -> String:
	return "pebble_field"


func kinds() -> Array:
	return [TileForgeConstants.Kind.INSTANCE]


func description() -> String:
	return "Resting pebbles and gravel, size-graded outwards from each cluster."


func validate(layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> PackedStringArray:
	var problems := PackedStringArray()
	if layer == null:
		return problems
	# The builder only hands a TileSurfaceLayer to the HEIGHTFIELD and MESH
	# passes, so an INSTANCE-only generator named on a layer contributes nothing.
	problems.append(
		"'%s' places detail modules; declare it on a detail rule, not a surface layer"
		% generator_id()
	)
	var drop := layer.get_float("edge_scale_drop", 0.0)
	if drop > MAX_EDGE_DROP:
		problems.append(
			"edge_scale_drop %.2f exceeds the %.2f cap; a stronger grade reads as a gradient"
			% [drop, MAX_EDGE_DROP]
		)
	return problems


func generate_instances(
	layer: TileSurfaceLayer,
	rule: TileDetailRule,
	ctx: TileGenerationContext
) -> Array[TileModuleInstance]:
	var placed := TileDetailPlacer.place(rule, ctx, CHANNEL)
	if placed.is_empty():
		return placed

	_settle_on_ground(layer, rule, ctx, placed)
	_grade_by_cluster(layer, rule, ctx, placed)
	return placed


func get_bounds(_layer: TileSurfaceLayer, ctx: TileGenerationContext) -> AABB:
	# Footprint is exactly the tile — the placer guarantees it. Stones are the
	# lowest detail family, so the vertical reach stays small on purpose.
	var extent := ctx.half_extent
	var reach := 0.03
	if ctx.recipe != null:
		for rule in ctx.recipe.enabled_detail_rules():
			if rule.generator_id == generator_id() and rule.module_set != null:
				reach = maxf(reach, rule.module_set.max_height() + rule.height_offset)
	if ctx.field != null:
		reach += ctx.field.max_height()
	return AABB(
		Vector3(-extent, -0.2, -extent),
		Vector3(extent * 2.0, 0.2 + reach, extent * 2.0)
	)


func get_debug_info(_layer: TileSurfaceLayer, ctx: TileGenerationContext) -> Dictionary:
	var rules := PackedStringArray()
	if ctx.recipe != null:
		for rule in ctx.recipe.enabled_detail_rules():
			if rule.generator_id == generator_id():
				rules.append(rule.rule_name)
	return {
		"generator": generator_id(),
		"kind": "instance",
		"rules": Array(rules),
	}


# --- Family post-passes -------------------------------------------------------

## Free yaw plus a lean onto the surface normal. The placer's small settle tilt
## is composed with, not replaced, so the stone keeps the character it was given
## and only gains the ground contact this family requires.
static func _settle_on_ground(
	layer: TileSurfaceLayer,
	rule: TileDetailRule,
	ctx: TileGenerationContext,
	placed: Array[TileModuleInstance]
) -> void:
	var strength := rule.normal_align_strength
	if strength <= 0.0:
		strength = clampf(
			_tuned(layer, rule, ctx, "normal_align", DEFAULT_NORMAL_ALIGN), 0.0, 1.0
		)
	elif rule.align_to_surface_normal:
		# The placer already seated this rule against the normal at exactly this
		# strength. Leaning a second time would tip the stone off its footprint.
		strength = 0.0

	var rng := ctx.rng("pebble_yaw|" + rule.rule_name, rule.seed_offset)
	for instance in placed:
		# Drawn before the FIXED test so the stream does not depend on which
		# module a placement happened to pick.
		var free_yaw := rng.randf() * TAU
		var scale_value := instance.uniform_scale()
		if scale_value <= 0.0:
			continue
		var module: TileModuleEntry = null
		if rule.module_set != null:
			module = rule.module_set.entry(instance.module_index)
		var locked := rule.rotation_mode == TileForgeConstants.RotationMode.FIXED
		if module != null and module.rotation_mode == TileForgeConstants.RotationMode.FIXED:
			locked = true

		var rotation := instance.transform.basis.orthonormalized()
		if not locked:
			rotation = Basis(Vector3.UP, free_yaw) * rotation
		if strength > 0.0:
			var origin := instance.position()
			var normal := ctx.surface_normal(
				origin.x / ctx.half_extent,
				origin.z / ctx.half_extent
			)
			rotation = _lean(rotation, normal, strength)
		instance.transform = Transform3D(
			rotation.scaled(Vector3.ONE * scale_value),
			instance.transform.origin
		)


## Big stones in the middle, small ones at the rim. Rank inside a cluster, not
## absolute distance, drives the grade so a tight group and a loose group both
## read as one observed pile.
static func _grade_by_cluster(
	layer: TileSurfaceLayer,
	rule: TileDetailRule,
	ctx: TileGenerationContext,
	placed: Array[TileModuleInstance]
) -> void:
	var drop: float = clampf(
		_tuned(layer, rule, ctx, "edge_scale_drop", MAX_EDGE_DROP), 0.0, MAX_EDGE_DROP
	)
	if drop <= 0.0001:
		return
	var radius: float = maxf(0.01, _tuned(layer, rule, ctx, "cluster_radius", 0.20))
	var start: float = clampf(_tuned(layer, rule, ctx, "grade_start", 0.45), 0.0, 0.95)

	for members in _cluster(placed, radius):
		# Two stones have no inside and no outside; grading them just makes one
		# arbitrarily smaller than its neighbour.
		if members.size() < 3:
			continue
		var centroid := Vector2.ZERO
		for index in members:
			var point := placed[index].position()
			centroid += Vector2(point.x, point.z)
		centroid /= float(members.size())

		# Vector2 sorts lexicographically, so packing (distance, index) gives a
		# total order without a comparator — and a total order is what keeps the
		# grade identical across runs.
		var ranked := PackedVector2Array()
		for index in members:
			var point := placed[index].position()
			ranked.append(Vector2(centroid.distance_to(Vector2(point.x, point.z)), float(index)))
		ranked.sort()

		for rank in ranked.size():
			var t := float(rank) / float(maxi(1, ranked.size() - 1))
			var reduction := drop * smoothstep(start, 1.0, t)
			if reduction <= 0.0001:
				continue
			_rescale(placed[int(ranked[rank].y)], 1.0 - reduction, rule)


## Applies a graded scale, clamped into the module's own authored range so the
## grade can never stretch a stone past what it was modelled to survive.
static func _rescale(
	instance: TileModuleInstance,
	factor: float,
	rule: TileDetailRule
) -> void:
	if rule.module_set == null:
		return
	var module := rule.module_set.entry(instance.module_index)
	if module == null:
		return
	var current := instance.uniform_scale()
	var low: float = minf(module.scale_range.x, module.scale_range.y)
	var high: float = maxf(module.scale_range.x, module.scale_range.y)
	var graded: float = clampf(current * factor, low, high)
	if is_equal_approx(graded, current) or graded <= 0.0:
		return

	var origin := instance.transform.origin
	# A smaller stone bites less deeply into the top, so the contact point moves.
	# Correcting it here keeps the placer's bedding honest at the new scale.
	origin.y += module.sink * (current - graded)
	instance.transform = Transform3D(
		instance.transform.basis.orthonormalized().scaled(Vector3.ONE * graded),
		origin
	)
	# Separation, boundary, and coverage checks all read these back, so they must
	# never disagree with the transform they describe.
	instance.footprint_radius = module.footprint_radius * graded
	instance.height = module.height * graded


# --- Local helpers ------------------------------------------------------------

## First-fit grouping in the XZ plane, returning member indices per cluster.
## Consumes no randomness: placement order is already deterministic, so retuning
## the radius cannot reshuffle which stone received which yaw.
static func _cluster(placed: Array[TileModuleInstance], radius: float) -> Array[PackedInt32Array]:
	var groups: Array[PackedInt32Array] = []
	var centroids: Array[Vector2] = []
	for index in placed.size():
		var point := placed[index].position()
		var flat := Vector2(point.x, point.z)
		var chosen := -1
		for group in groups.size():
			if centroids[group].distance_to(flat) <= radius:
				chosen = group
				break
		if chosen < 0:
			groups.append(PackedInt32Array([index]))
			centroids.append(flat)
			continue
		var members: PackedInt32Array = groups[chosen]
		members.append(index)
		groups[chosen] = members
		centroids[chosen] = centroids[chosen] + (flat - centroids[chosen]) / float(members.size())
	return groups


## Blends a frame's up axis towards `normal` by `strength`. Rotating by the
## minimal arc means the yaw and the settle tilt the frame already carried both
## survive — only the ground contact changes.
static func _lean(rotation: Basis, normal: Vector3, strength: float) -> Basis:
	var target := rotation.y.slerp(normal, clampf(strength, 0.0, 1.0))
	if target.length_squared() <= 0.0001:
		return rotation
	var axis := rotation.y.cross(target)
	if axis.length_squared() <= 0.000001:
		return rotation
	return Basis(axis.normalized(), rotation.y.angle_to(target)) * rotation


## Tuning lookup. A detail rule has no TileSurfaceLayer, so the primary source
## is the recipe's custom_params under a "<rule_name>.<key>" prefix; a layer,
## when the lab supplies one, wins. Either way a designer never edits this file.
static func _tuned(
	layer: TileSurfaceLayer,
	rule: TileDetailRule,
	ctx: TileGenerationContext,
	key: String,
	fallback: float
) -> float:
	var value := fallback
	if ctx.recipe != null:
		var raw: Variant = ctx.recipe.custom_params.get("%s.%s" % [rule.rule_name, key], null)
		if raw is float or raw is int:
			value = float(raw)
	if layer != null:
		value = layer.get_float(key, value)
	return value
