@tool
class_name ClumpFieldGenerator
extends TileLayerGenerator
## Grass clumps, straw, hay, moss tufts, leaf piles — stylised ground
## vegetation.
##
## Scatter, separation, border exclusion, and bedding all belong to
## TileDetailPlacer; re-implementing them here is exactly how a detail family
## drifts away from the rest of the collection. What this generator owns is the
## two rules that make a field read as VEGETATION rather than as scattered
## props:
##
##   1. a clump GROWS, so its axis is world up no matter what the ground under
##      it does. A tuft leaning with the slope reads as fallen debris.
##   2. the crests of a modulated top catch the light, so clumps standing above
##      the tile's median height are biased towards the palette's accent slot.
##      The lift is a SLOT SELECTION from an approved palette entry — never a
##      jittered colour, never a per-vertex tint.
##
## No mesh surfaces are produced: each instance carries a
## TileForgeConstants.SLOT_* name and the baker merges one surface per slot.
##
## A readable clump field is a handful of large forms. Counts above
## `readable_limit` are reported rather than silently placed, because the
## failure is compositional and invisible in a numeric bake log.
##
## Params: read from `ctx.recipe.custom_params` under "<rule_name>.<key>", and
## overridden by a TileSurfaceLayer's own `params` when the lab supplies one.
##   accent_share         0.25   chance a crown clump takes the accent slot
##   accent_shade_share   0.06   chance for a clump at or below the median
##   accent_crown_margin  0.004  metres above the median that counts as a crown
##   readable_limit       14     max_count above which the field stops reading

## Placement stream name. TileDetailPlacer appends the rule name, so two clump
## rules on one tile never correlate.
const CHANNEL := "clump_field"
const DEFAULT_READABLE_LIMIT := 14


func generator_id() -> String:
	return "clump_field"


func kinds() -> Array:
	return [TileForgeConstants.Kind.INSTANCE]


func description() -> String:
	return "Upright vegetation clumps with a sunlit-crown accent bias."


func validate(layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> PackedStringArray:
	var problems := PackedStringArray()
	if layer == null:
		return problems
	# The builder only ever hands a TileSurfaceLayer to a HEIGHTFIELD or MESH
	# pass. An INSTANCE-only generator named on a layer therefore contributes
	# nothing at all, which is far easier to catch here than in a screenshot.
	problems.append(
		"'%s' places detail modules; declare it on a detail rule, not a surface layer"
		% generator_id()
	)
	var share := layer.get_float("accent_share", 0.25)
	if share < 0.0 or share > 1.0:
		problems.append("accent_share %.2f is outside 0..1" % share)
	return problems


func generate_instances(
	layer: TileSurfaceLayer,
	rule: TileDetailRule,
	ctx: TileGenerationContext
) -> Array[TileModuleInstance]:
	var placed := TileDetailPlacer.place(rule, ctx, CHANNEL)
	if placed.is_empty():
		return placed

	var limit := int(_tuned(layer, rule, ctx, "readable_limit", float(DEFAULT_READABLE_LIMIT)))
	if rule.max_count > limit:
		# Reported, not failed: the count is legal, it just stops reading as a
		# few deliberate forms. validate() cannot see it — it is given a layer.
		ctx.report(
			"clump rule '%s' allows up to %d clumps; above %d the field reads as a lawn of small forms rather than a handful of large ones"
			% [rule.rule_name, rule.max_count, limit]
		)

	if not rule.align_to_surface_normal:
		_stand_upright(placed)
	_bias_sunlit_crowns(layer, rule, ctx, placed)
	return placed


func get_bounds(_layer: TileSurfaceLayer, ctx: TileGenerationContext) -> AABB:
	# The footprint is exactly the tile — the placer guarantees it. Only the
	# vertical reach is family-specific, and vegetation is the tallest thing a
	# detail pass adds to a tile.
	var extent := ctx.half_extent
	var reach := 0.04
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

## Vegetation grows towards the sky, not away from the ground it stands on. The
## placer's yaw survives so module variety is untouched; only the lean it was
## allowed to add goes, along with any slope the surface imposed.
static func _stand_upright(placed: Array[TileModuleInstance]) -> void:
	for instance in placed:
		var scale_value := instance.uniform_scale()
		if scale_value <= 0.0:
			continue
		var rotation := instance.transform.basis.orthonormalized()
		var axis := rotation.y.cross(Vector3.UP)
		if axis.length_squared() > 0.000001:
			# Minimal arc back to vertical. The placer tilts about a HORIZONTAL
			# axis, so this undoes exactly that tilt and leaves its yaw bit-for-
			# bit intact. Rebuilding the frame from an atan2 of the forward axis
			# would instead drift with the tilt magnitude, which would make a
			# clump field change every time a recipe touched max_tilt_deg.
			rotation = Basis(axis.normalized(), rotation.y.angle_to(Vector3.UP)) * rotation
		instance.transform = Transform3D(
			rotation.scaled(Vector3.ONE * scale_value),
			instance.transform.origin
		)


## Clumps on the crests take the accent slot more often than clumps in the
## hollows. Driven by the shared heightfield, so the colour break follows the
## macro form the surface layers authored instead of speckling the field.
static func _bias_sunlit_crowns(
	layer: TileSurfaceLayer,
	rule: TileDetailRule,
	ctx: TileGenerationContext,
	placed: Array[TileModuleInstance]
) -> void:
	var accent_slot := TileForgeConstants.SLOT_ACCENT
	if layer != null and layer.secondary_slot != "":
		accent_slot = layer.secondary_slot
	if ctx.palette == null or ctx.palette.key_for_slot(accent_slot) == "":
		# Nothing bound to lift towards. Leaving the placer's detail slots alone
		# is better than emitting a slot the validator would reject outright.
		return

	var crown_share: float = clampf(_tuned(layer, rule, ctx, "accent_share", 0.25), 0.0, 1.0)
	var shade_share: float = clampf(
		_tuned(layer, rule, ctx, "accent_shade_share", 0.06), 0.0, 1.0
	)
	var margin := _tuned(layer, rule, ctx, "accent_crown_margin", 0.004)
	var median := 0.0
	if ctx.field != null:
		median = ctx.field.median_height()
	var rng := ctx.rng("clump_accent|" + rule.rule_name, rule.seed_offset)

	for instance in placed:
		# One draw per instance whatever the outcome: retuning the crown margin
		# then re-colours clumps without reshuffling the rest of the field.
		var roll := rng.randf()
		var origin := instance.position()
		var ground := ctx.surface_height(
			origin.x / ctx.half_extent,
			origin.z / ctx.half_extent
		)
		var share := crown_share if ground > median + margin else shade_share
		if roll >= share:
			continue
		instance.material_slot = accent_slot
		# The baker batches on module+slot, so the key has to follow the slot.
		instance.make_group_key()


# --- Local helpers ------------------------------------------------------------

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
