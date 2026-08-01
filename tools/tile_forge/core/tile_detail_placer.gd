@tool
class_name TileDetailPlacer
extends RefCounted
## Shared placement engine for every module-scattering generator.
##
## Keeping this in one place is what makes clumps, pebbles, and rubble obey the
## same rules: the same border exclusion, the same separation test, the same
## surface sampling, the same repetition cap. A new detail family gets correct
## behaviour by calling `place()` rather than by re-implementing scatter — and
## re-implementing scatter is exactly how procedural fields drift into looking
## random.

## Places one detail rule. Returns instances already bedded onto the shared
## heightfield, inside the boundary, and separated.
static func place(
	rule: TileDetailRule,
	ctx: TileGenerationContext,
	channel: String
) -> Array[TileModuleInstance]:
	var result: Array[TileModuleInstance] = []
	if not rule.is_valid():
		return result

	var rng := ctx.rng(channel + "|" + rule.rule_name, rule.seed_offset)
	var pattern := rule.composition
	if pattern == null:
		pattern = TileCompositionPattern.new()

	var wanted := rule.count_for(rng)
	if wanted <= 0:
		return result

	# Ask for extra anchors: rejection for mask, clearing, border, and
	# separation will discard some, and a short field is better than a field
	# padded with badly-placed extras.
	var anchors := pattern.composed(int(ceil(float(wanted) * 1.9)) + 2, rng)
	var used_counts: Dictionary = {}
	# Seeded with what earlier rules already claimed, so separation is a
	# tile-wide property rather than a per-rule one.
	var placed_positions: Array[Vector2] = []
	var placed_radii: PackedFloat32Array = PackedFloat32Array()
	for claim in ctx.occupied:
		placed_positions.append(Vector2(claim.x, claim.y))
		placed_radii.append(claim.z)

	for entry in anchors:
		if result.size() >= wanted:
			break
		var anchor := Vector2(entry.x, entry.y)
		var role := int(entry.z)
		if not rule.region_allows(anchor.x, anchor.y):
			continue

		var module_index := _pick_module(rule, role, rng, used_counts)
		var module := rule.module_set.entry(module_index)
		if module == null or module.mesh_path == "":
			continue

		var scale_value := _pick_scale(rule, module, rng) * _role_scale(role, ctx)
		# A form the art profile calls unreadable is dropped rather than shrunk
		# further: a dot at gameplay distance is worse than an absence.
		var placed_width := module.footprint_radius * 2.0 * scale_value
		if not ctx.art.is_detail_readable(placed_width):
			continue
		var radius := module.footprint_radius * scale_value

		var world := ctx.to_world(anchor.x, anchor.y)
		if not _inside_border(world, radius, rule, module, ctx):
			continue
		if not _separated(world, radius, placed_positions, placed_radii, rule, module):
			continue

		var instance := _build_instance(
			rule, module, module_index, scale_value, radius, anchor, world, ctx, rng, pattern
		)
		instance.role = role
		result.append(instance)
		placed_positions.append(world)
		placed_radii.append(radius)
		ctx.occupied.append(Vector3(world.x, world.y, radius))
		used_counts[module_index] = int(used_counts.get(module_index, 0)) + 1

	return result


## Size hierarchy comes from the art profile, not from the recipe, so every
## family in the collection separates hero/support/accent by the same ratio.
static func _role_scale(role: int, ctx: TileGenerationContext) -> float:
	match role:
		TileForgeConstants.Role.HERO:
			return ctx.art.hero_scale
		TileForgeConstants.Role.ACCENT:
			return ctx.art.accent_scale
	return ctx.art.support_scale


## A hero should be one of the LARGEST modules in its set, not a random one
## scaled up — scaling a small module into the hero slot reads as a zoom, while
## a genuinely bigger mesh reads as a different plant.
static func _pick_module(
	rule: TileDetailRule,
	role: int,
	rng: RandomNumberGenerator,
	used_counts: Dictionary
) -> int:
	if role != TileForgeConstants.Role.HERO and role != TileForgeConstants.Role.ACCENT:
		return rule.module_set.pick(rng, used_counts)
	var ranked: Array[int] = []
	for index in rule.module_set.modules.size():
		var module := rule.module_set.entry(index)
		if module != null and module.mesh_path != "":
			ranked.append(index)
	if ranked.is_empty():
		return 0
	ranked.sort_custom(func(a: int, b: int) -> bool:
		var left := rule.module_set.entry(a)
		var right := rule.module_set.entry(b)
		return left.footprint_radius > right.footprint_radius
	)
	# Heroes draw from the largest third, accents from the smallest third.
	var third: int = maxi(1, ranked.size() / 3)
	if role == TileForgeConstants.Role.HERO:
		return ranked[rng.randi_range(0, third - 1)]
	return ranked[rng.randi_range(maxi(0, ranked.size() - third), ranked.size() - 1)]


static func _pick_scale(
	rule: TileDetailRule,
	module: TileModuleEntry,
	rng: RandomNumberGenerator
) -> float:
	# Intersect the rule's range with the module's own allowed range so a rule
	# cannot stretch a module past what it was authored to survive.
	var low: float = maxf(minf(rule.scale_range.x, rule.scale_range.y), module.scale_range.x)
	var high: float = minf(maxf(rule.scale_range.x, rule.scale_range.y), module.scale_range.y)
	if high <= low:
		return low
	# Biased towards the middle: a field of extremes reads as noise, a field of
	# identical sizes reads as a stamp.
	var t := (rng.randf() + rng.randf()) * 0.5
	return lerpf(low, high, t)


static func _inside_border(
	world: Vector2,
	radius: float,
	rule: TileDetailRule,
	module: TileModuleEntry,
	ctx: TileGenerationContext
) -> bool:
	var margin := rule.border_exclusion
	if module.is_edge_safe():
		margin = 0.0
	var limit := ctx.half_extent - margin - radius
	if limit <= 0.0:
		return false
	return absf(world.x) <= limit and absf(world.y) <= limit


static func _separated(
	world: Vector2,
	radius: float,
	positions: Array[Vector2],
	radii: PackedFloat32Array,
	rule: TileDetailRule,
	_module: TileModuleEntry
) -> bool:
	var gap: float = rule.min_separation * rule.module_set.separation_scale
	for index in positions.size():
		var required := radius + radii[index] + gap
		if positions[index].distance_to(world) < required:
			return false
	return true


static func _build_instance(
	rule: TileDetailRule,
	module: TileModuleEntry,
	module_index: int,
	scale_value: float,
	radius: float,
	anchor: Vector2,
	world: Vector2,
	ctx: TileGenerationContext,
	rng: RandomNumberGenerator,
	pattern: TileCompositionPattern
) -> TileModuleInstance:
	var instance := TileModuleInstance.new()
	instance.module_path = module.mesh_path
	instance.rule_name = rule.rule_name
	instance.module_index = module_index
	instance.footprint_radius = radius
	instance.height = module.height * scale_value
	instance.output = rule.output
	instance.wants_collision = rule.detail_collision
	instance.permits_overlap = rule.permit_intersection
	instance.material_slot = ctx.palette.pick_detail_slot(
		rng, rule.material_variant_weights
	)
	if module.material_slot != TileForgeConstants.SLOT_DETAIL_A:
		# A module that declares a specific slot overrides the rule's variant
		# roll — used by two-tone sets where one member is deliberately darker.
		instance.material_slot = module.material_slot

	var ground := ctx.surface_height(anchor.x, anchor.y)
	var origin := Vector3(
		world.x,
		ground + rule.height_offset - module.sink * scale_value,
		world.y
	)

	var basis := Basis.IDENTITY
	basis = basis.rotated(Vector3.UP, _pick_yaw(rule, module, rng, pattern))
	var tilt: float = minf(rule.max_tilt_deg, module.max_tilt_deg)
	if tilt > 0.01:
		var tilt_axis := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
		if tilt_axis.length_squared() > 0.0001:
			basis = basis.rotated(
				tilt_axis.normalized(),
				deg_to_rad(rng.randf_range(-tilt, tilt))
			)
	if rule.align_to_surface_normal:
		var normal := ctx.surface_normal(anchor.x, anchor.y)
		var aligned := Vector3.UP.slerp(normal, rule.normal_align_strength)
		if aligned.length_squared() > 0.0001:
			var axis := Vector3.UP.cross(aligned)
			if axis.length_squared() > 0.000001:
				basis = Basis(axis.normalized(), Vector3.UP.angle_to(aligned)) * basis
	basis = basis.scaled(Vector3.ONE * scale_value)

	instance.transform = Transform3D(basis, origin)
	instance.make_group_key()
	return instance


static func _pick_yaw(
	rule: TileDetailRule,
	module: TileModuleEntry,
	rng: RandomNumberGenerator,
	pattern: TileCompositionPattern
) -> float:
	var mode := rule.rotation_mode
	if module.rotation_mode == TileForgeConstants.RotationMode.FIXED:
		mode = TileForgeConstants.RotationMode.FIXED
	match mode:
		TileForgeConstants.RotationMode.FIXED:
			return 0.0
		TileForgeConstants.RotationMode.QUARTER_TURNS:
			return float(rng.randi_range(0, 3)) * PI * 0.5
		TileForgeConstants.RotationMode.YAW_FROM_FLOW:
			# Aligned to the composition's flow, with a little scatter so a
			# drift field does not look combed.
			return deg_to_rad(pattern.flow_angle_deg + rng.randf_range(-22.0, 22.0))
		_:
			return rng.randf() * TAU


## Merges instances into one ArrayMesh per material slot, applying each
## instance transform. This is the production output path for Suma: the world
## renderer already batches whole tiles, so merged static detail is what
## actually reaches the chunk MultiMeshes.
static func merge_instances(
	instances: Array[TileModuleInstance],
	ctx: TileGenerationContext
) -> TileMeshPart:
	if instances.is_empty():
		return null
	var tools: Dictionary = {}
	var slot_order := PackedStringArray()
	for instance in instances:
		var source := ctx.module_mesh(instance.module_path)
		if source == null:
			continue
		for surface in source.get_surface_count():
			# A module may name a surface after a slot to keep a deliberate
			# second tone — the dark base of a grass clump, the shaded face of a
			# chip. Anything else follows the placement's own slot, so one module
			# can appear in three approved colours across a field.
			var slot := instance.material_slot
			var surface_name := source.surface_get_name(surface)
			if TileForgeConstants.ALL_SLOTS.has(surface_name):
				slot = surface_name
			if not tools.has(slot):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[slot] = tool
				slot_order.append(slot)
			(tools[slot] as SurfaceTool).append_from(source, surface, instance.transform)
	if slot_order.is_empty():
		return null
	var mesh := ArrayMesh.new()
	for slot in slot_order:
		var tool: SurfaceTool = tools[slot]
		tool.commit(mesh)
		mesh.surface_set_name(mesh.get_surface_count() - 1, slot)
	var part := TileMeshPart.make(mesh, slot_order, "detail")
	return part
