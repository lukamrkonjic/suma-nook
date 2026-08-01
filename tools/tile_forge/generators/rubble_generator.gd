@tool
class_name RubbleGenerator
extends TileLayerGenerator
## Broken stone, wood debris, collapsed surfaces, fragmented constructed
## terrain.
##
## Scatter, separation, border exclusion, and bedding stay in TileDetailPlacer.
## What lives here is the two rules that make debris read as debris:
##
##   1. rubble is ANGULAR. A fragment that has fallen settles at an angle you
##      can see from the three-quarter camera, so the tilt is re-applied here up
##      to the RULE's `max_tilt_deg` and the per-module cap is deliberately
##      bypassed. That cap exists to stop a grass tuft leaning; a shard has no
##      such constraint, and clamping it back to six degrees is what makes
##      procedural rubble look like litter sitting flat on a floor.
##   2. rubble must stay READABLE. Four medium pieces in one place is a
##      collapsed corner; nine is a shard explosion that turns into visual
##      noise at 37 units out. Clusters over the limit lose their excess
##      members, largest kept, so the silhouette that survives is the one that
##      was carrying the read.
##
## The cull runs AFTER the tilt so a dropped piece cannot consume a different
## random draw than a kept one — the tilt stream is indexed by placement order,
## not by survival.
##
## No mesh surfaces are produced: each instance carries a
## TileForgeConstants.SLOT_* name and the baker merges one surface per slot.
##
## Params: read from `ctx.recipe.custom_params` under "<rule_name>.<key>", and
## overridden by a TileSurfaceLayer's own `params` when the lab supplies one.
##   cluster_radius  0.16  LIVE metres; footprints inside this form one cluster
##   cluster_max     4     members a readable cluster is allowed to keep
##   tilt_min_share  0.35  floor on tilt as a fraction of rule.max_tilt_deg

## Placement stream name. TileDetailPlacer appends the rule name, so two rubble
## rules on one tile never correlate.
const CHANNEL := "rubble_field"
const DEFAULT_CLUSTER_RADIUS := 0.16
const DEFAULT_CLUSTER_MAX := 4
## Below this fraction of the tilt budget the angle stops being legible and the
## piece just looks badly placed, so tilts are never drawn near zero.
const DEFAULT_TILT_MIN_SHARE := 0.35


func generator_id() -> String:
	return "rubble_field"


func kinds() -> Array:
	return [TileForgeConstants.Kind.INSTANCE]


func description() -> String:
	return "Angular debris at readable settle angles, culled to legible clusters."


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
	var cap := layer.get_int("cluster_max", DEFAULT_CLUSTER_MAX)
	if cap < 1:
		problems.append("cluster_max %d leaves no rubble at all" % cap)
	return problems


func generate_instances(
	layer: TileSurfaceLayer,
	rule: TileDetailRule,
	ctx: TileGenerationContext
) -> Array[TileModuleInstance]:
	var placed := TileDetailPlacer.place(rule, ctx, CHANNEL)
	if placed.is_empty():
		return placed

	_apply_settle_tilt(layer, rule, ctx, placed)
	return _cull_dense_clusters(layer, rule, ctx, placed)


## Rubble is visual-only by default. A fragment lying on a floor is not a
## surface the player stands on, and giving every shard its own shape would put
## dozens of bodies under a tile whose walkable top is already one box. A recipe
## that genuinely needs a climbable pile sets `detail_collision` on the rule —
## the placer forwards it to `TileModuleInstance.wants_collision` — or raises the
## tile's own `collision_mode`.
func generate_collision(_layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> Array:
	return []


func get_bounds(_layer: TileSurfaceLayer, ctx: TileGenerationContext) -> AABB:
	# Footprint is exactly the tile — the placer guarantees it. Tilting a
	# fragment lifts its far corner, so the vertical reach gets the tilt back.
	var extent := ctx.half_extent
	var reach := 0.04
	if ctx.recipe != null:
		for rule in ctx.recipe.enabled_detail_rules():
			if rule.generator_id != generator_id() or rule.module_set == null:
				continue
			var tall := rule.module_set.max_height() + rule.height_offset
			var lift := rule.module_set.max_footprint_radius() * sin(deg_to_rad(rule.max_tilt_deg))
			reach = maxf(reach, tall + lift)
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

## Re-seats each fragment on the rule's own tilt budget. The frame is rebuilt
## from the placer's yaw rather than added to, because accumulating a second
## tilt on top of the first makes the total angle depend on the module cap the
## budget was meant to escape.
static func _apply_settle_tilt(
	layer: TileSurfaceLayer,
	rule: TileDetailRule,
	ctx: TileGenerationContext,
	placed: Array[TileModuleInstance]
) -> void:
	var budget := rule.max_tilt_deg
	var floor_share: float = clampf(
		_tuned(layer, rule, ctx, "tilt_min_share", DEFAULT_TILT_MIN_SHARE), 0.0, 1.0
	)
	var rng := ctx.rng("rubble_tilt|" + rule.rule_name, rule.seed_offset)

	for instance in placed:
		# Both draws happen for every instance so the stream stays indexed by
		# placement order and a zero-budget rule stays reproducible.
		var axis_angle := rng.randf() * TAU
		var share := rng.randf_range(floor_share, 1.0)
		var scale_value := instance.uniform_scale()
		if scale_value <= 0.0:
			continue

		var rotation := instance.transform.basis.orthonormalized()
		var upright := rotation.y.cross(Vector3.UP)
		if upright.length_squared() > 0.000001:
			# Strip the small tilt the placer's per-module cap allowed, by the
			# minimal arc: the placer tilts about a HORIZONTAL axis, so this
			# undoes exactly that and keeps its yaw bit-for-bit. Accumulating a
			# second tilt instead would make the total angle depend on the cap
			# this family exists to escape.
			rotation = Basis(upright.normalized(), rotation.y.angle_to(Vector3.UP)) * rotation
		if rule.align_to_surface_normal:
			# The frame was rebuilt, so the bedding the placer applied has to be
			# restated. It goes on FIRST: bedding is where the ground is, the
			# tilt is the angle the fragment settled at relative to it, and
			# blending the two together would eat most of the tilt budget.
			var origin := instance.position()
			var normal := ctx.surface_normal(
				origin.x / ctx.half_extent,
				origin.z / ctx.half_extent
			)
			rotation = _lean(rotation, normal, rule.normal_align_strength)
		if budget > 0.01:
			# A full-turn axis already covers both lean directions, so no sign
			# draw is needed and the stream stays two values per fragment.
			var axis := Vector3(cos(axis_angle), 0.0, sin(axis_angle))
			rotation = Basis(axis, deg_to_rad(budget * share)) * rotation
		instance.transform = Transform3D(
			rotation.scaled(Vector3.ONE * scale_value),
			instance.transform.origin
		)


## Keeps a cluster to a few medium pieces. Largest survive: a big fragment is
## what carries the silhouette, and the small ones around it are the members a
## viewer would never miss.
static func _cull_dense_clusters(
	layer: TileSurfaceLayer,
	rule: TileDetailRule,
	ctx: TileGenerationContext,
	placed: Array[TileModuleInstance]
) -> Array[TileModuleInstance]:
	var radius: float = maxf(
		0.01, _tuned(layer, rule, ctx, "cluster_radius", DEFAULT_CLUSTER_RADIUS)
	)
	var cap: int = maxi(
		1, int(_tuned(layer, rule, ctx, "cluster_max", float(DEFAULT_CLUSTER_MAX)))
	)

	var dropped: Dictionary = {}
	for members in _cluster(placed, radius):
		if members.size() <= cap:
			continue
		# Vector2 sorts lexicographically, so packing (-radius, index) ranks the
		# largest first with a total order — and a total order is what keeps the
		# same fragments surviving on every rebuild.
		var ranked := PackedVector2Array()
		for index in members:
			ranked.append(Vector2(-placed[index].footprint_radius, float(index)))
		ranked.sort()
		for rank in range(cap, ranked.size()):
			dropped[int(ranked[rank].y)] = true

	if dropped.is_empty():
		return placed

	var kept: Array[TileModuleInstance] = []
	for index in placed.size():
		if not dropped.has(index):
			kept.append(placed[index])
	ctx.report(
		"rubble rule '%s' dropped %d of %d pieces: a cluster held more than %d members within %.2f m"
		% [rule.rule_name, dropped.size(), placed.size(), cap, radius]
	)
	return kept


# --- Local helpers ------------------------------------------------------------

## First-fit grouping in the XZ plane, returning member indices per cluster.
## Consumes no randomness: placement order is already deterministic, so retuning
## the radius cannot reshuffle which fragment received which tilt.
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
## minimal arc means the yaw the frame already carried survives — only the
## ground contact changes.
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
