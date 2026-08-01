@tool
class_name TileForgeBuilder
extends RefCounted
## Runs a recipe through the generator passes and returns a TileBuildResult.
##
## The pass order is the whole architecture in eight lines:
##
##   1. validate every layer against its generator
##   2. size the shared heightfield to the coarsest resolution that still
##      carries the intended silhouette
##   3. HEIGHTFIELD pass  — layers blend into one top
##   4. lock the boundary  — once, centrally, unconditionally
##   5. triangulate the top and its structural skirt
##   6. MESH pass          — constructed and custom geometry appends
##   7. INSTANCE pass      — modules sample the finished top, so nothing floats
##   8. collision
##
## No step reaches backwards. A detail can therefore never change the surface
## it sits on, and a mesh layer can never move a boundary vertex.

const FORGE_VERSION := "1.0.0"


static func build(
	recipe: TileRecipe,
	neighbours: Dictionary = {},
	preview := false,
	shared_modules: Dictionary = {}
) -> TileBuildResult:
	var started := Time.get_ticks_msec()
	var result := TileBuildResult.new()
	result.recipe = recipe

	if recipe == null:
		return result

	var ctx := TileGenerationContext.new(recipe)
	ctx.neighbours = neighbours
	ctx.preview_mode = preview
	ctx.module_library = shared_modules
	result.context = ctx

	var registry := TileGeneratorRegistry.shared()
	for error in registry.load_errors():
		ctx.fail(error)

	var layers := recipe.enabled_surface_layers()

	# --- 1. validate -----------------------------------------------------
	for layer in layers:
		var generator := registry.get_generator(layer.generator_id)
		if generator == null:
			ctx.fail("unknown generator '%s' on layer '%s'" % [
				layer.generator_id, layer.layer_name
			])
			continue
		for problem in generator.validate(layer, ctx):
			ctx.fail("[%s] %s" % [layer.layer_name, problem])

	# --- 2. size the field ----------------------------------------------
	var resolution := 2
	var has_height_layer := false
	for layer in layers:
		var generator := registry.get_generator(layer.generator_id)
		if generator == null:
			continue
		if generator.handles_kind(TileForgeConstants.Kind.HEIGHTFIELD):
			resolution = maxi(resolution, layer.resolution)
			has_height_layer = true
	# The field stops short of the true boundary by exactly one bevel width. The
	# chamfer ring then carries it out to ±half_extent, so the square footprint
	# is untouched while the top perimeter gains the facet that stops a tile
	# reading as an untreated cube.
	var bevel: float = ctx.art.top_bevel if _wants_chamfer(recipe) else 0.0
	var field_extent: float = maxf(recipe.half_extent() * 0.5, recipe.half_extent() - bevel)
	ctx.field = TileHeightField.new(resolution, field_extent)
	ctx.field.slot_names = PackedStringArray([_first_top_slot(layers)])

	# --- 3. heightfield pass --------------------------------------------
	for layer in layers:
		var generator := registry.get_generator(layer.generator_id)
		if generator == null:
			continue
		if not generator.handles_kind(TileForgeConstants.Kind.HEIGHTFIELD):
			continue
		generator.generate_height(layer, ctx)
		result.debug.append(generator.get_debug_info(layer, ctx))

	# --- 4. central boundary lock ---------------------------------------
	# Runs regardless of what any generator did. This single call is the whole
	# no-holes guarantee: every boundary vertex of every connected tile ends on
	# the same declared height, bit for bit.
	if recipe.is_connected_surface() and has_height_layer:
		ctx.field.lock_edges(
			recipe.connected_edge_height,
			_narrowest_edge_lock(layers)
		)

	# --- 5. triangulate the top and its chamfered shell ------------------
	if has_height_layer:
		var smooth := _any_smooth(layers)
		var top := TileLayerGenerator.build_field_mesh(ctx.field, smooth)
		if top != null:
			result.parts.append(top)
		if bevel > 0.0005:
			var chamfer := TileLayerGenerator.build_top_chamfer(
				ctx.field,
				recipe.half_extent(),
				bevel,
				ctx.art.top_bevel_segments,
				_rim_slot(ctx)
			)
			if chamfer != null:
				result.parts.append(chamfer)
		if ctx.base_profile.generate_side_wall:
			var wall := TileLayerGenerator.build_side_wall(
				ctx.field,
				ctx.base_profile.canonical_seam(),
				ctx.base_profile.side_slot,
				recipe.half_extent(),
				bevel
			)
			if wall != null:
				result.parts.append(wall)
		if ctx.base_profile.mode == TileForgeConstants.BaseMode.GENERATED:
			# The Forge owns the whole block: it can chamfer the bottom edge too,
			# which is what stops a stacked tile welding to the one below it.
			for part in TileLayerGenerator.build_block_body(
				recipe.half_extent(),
				ctx.base_profile.canonical_seam(),
				ctx.base_profile.bottom_y,
				ctx.art.bottom_bevel,
				ctx.art.bottom_bevel_segments,
				ctx.base_profile.side_slot,
				ctx.base_profile.underside_slot,
				ctx.base_profile.generate_underside
			):
				result.parts.append(part)

	# --- 6. mesh pass ----------------------------------------------------
	for layer in layers:
		var generator := registry.get_generator(layer.generator_id)
		if generator == null:
			continue
		if not generator.handles_kind(TileForgeConstants.Kind.MESH):
			continue
		for part in generator.generate_mesh(layer, ctx):
			if part == null:
				continue
			part.layer_name = layer.layer_name
			part.separate_render_layer = layer.separate_render_layer
			result.parts.append(part)
		result.debug.append(generator.get_debug_info(layer, ctx))

	# --- 7. instance pass ------------------------------------------------
	for rule in recipe.enabled_detail_rules():
		var generator := registry.get_generator(rule.generator_id)
		if generator == null:
			ctx.fail("unknown generator '%s' on detail rule '%s'" % [
				rule.generator_id, rule.rule_name
			])
			continue
		if not generator.handles_kind(TileForgeConstants.Kind.INSTANCE):
			ctx.fail("generator '%s' cannot place instances (rule '%s')" % [
				rule.generator_id, rule.rule_name
			])
			continue
		var placed := generator.generate_instances(null, rule, ctx)
		for instance in placed:
			result.instances.append(instance)

	# Merge instances into static geometry unless the rule asked otherwise.
	_materialise_instances(result, ctx)

	# --- 8. collision -----------------------------------------------------
	result.collision = _build_collision(recipe, ctx)
	for layer in layers:
		var generator := registry.get_generator(layer.generator_id)
		if generator == null:
			continue
		for shape in generator.generate_collision(layer, ctx):
			result.collision.append(shape)

	result.build_msec = Time.get_ticks_msec() - started
	return result


## Groups mergeable instances into one part per material slot, leaving
## MULTIMESH / SEPARATE_RENDER_LAYER / debug instances for the baker.
static func _materialise_instances(result: TileBuildResult, ctx: TileGenerationContext) -> void:
	var mergeable: Array[TileModuleInstance] = []
	for instance in result.instances:
		if instance.output == TileForgeConstants.DetailOutput.MERGED_STATIC_MESH:
			mergeable.append(instance)
	if mergeable.is_empty():
		return
	var merged := TileDetailPlacer.merge_instances(mergeable, ctx)
	if merged != null:
		result.parts.append(merged)


static func _build_collision(recipe: TileRecipe, ctx: TileGenerationContext) -> Array:
	var shapes: Array = []
	match recipe.collision_mode:
		TileForgeConstants.CollisionMode.NONE:
			return shapes
		TileForgeConstants.CollisionMode.FLAT_BOX, \
		TileForgeConstants.CollisionMode.FROM_HEIGHTFIELD_MEDIAN:
			# Collision is always simpler than the render surface: one box
			# spanning the block, topped at the median visual height so physics
			# agrees with what the eye reads as ground.
			var top := 0.0
			if (
				recipe.collision_mode
				== TileForgeConstants.CollisionMode.FROM_HEIGHTFIELD_MEDIAN
				and ctx.field != null
			):
				top = ctx.field.median_height()
			var height := TileForgeConstants.BLOCK_DEPTH + top
			var box := BoxShape3D.new()
			box.size = Vector3(recipe.tile_size, height, recipe.tile_size)
			shapes.append({
				"shape": box,
				"transform": Transform3D(
					Basis.IDENTITY,
					Vector3(0.0, (top - TileForgeConstants.BLOCK_DEPTH) * 0.5, 0.0)
				),
				"layer": 1,
				"name": "GroundBox",
			})
		TileForgeConstants.CollisionMode.RIM_BOX:
			# Four walls around an open centre: the basin case. The floor of the
			# recess is still walkable, so the ground box is emitted too.
			var rim_inner: float = float(recipe.custom_params.get("rim_inner", 0.62))
			var extent := recipe.half_extent()
			var inner := extent * rim_inner
			var thickness: float = maxf(0.02, extent - inner)
			var wall_height: float = float(recipe.custom_params.get("rim_height", 0.22))
			var offsets := [
				Vector3(0.0, 0.0, -(extent - thickness * 0.5)),
				Vector3(0.0, 0.0, extent - thickness * 0.5),
				Vector3(-(extent - thickness * 0.5), 0.0, 0.0),
				Vector3(extent - thickness * 0.5, 0.0, 0.0),
			]
			var sizes := [
				Vector3(extent * 2.0, wall_height, thickness),
				Vector3(extent * 2.0, wall_height, thickness),
				Vector3(thickness, wall_height, extent * 2.0),
				Vector3(thickness, wall_height, extent * 2.0),
			]
			for index in offsets.size():
				var wall := BoxShape3D.new()
				wall.size = sizes[index]
				shapes.append({
					"shape": wall,
					"transform": Transform3D(
						Basis.IDENTITY,
						offsets[index] + Vector3(0.0, wall_height * 0.5 - 0.02, 0.0)
					),
					"layer": 1,
					"name": "Rim%d" % index,
				})
			var floor_box := BoxShape3D.new()
			var floor_top: float = float(recipe.custom_params.get("basin_floor", -0.14))
			var floor_height := TileForgeConstants.BLOCK_DEPTH + floor_top
			floor_box.size = Vector3(recipe.tile_size, floor_height, recipe.tile_size)
			shapes.append({
				"shape": floor_box,
				"transform": Transform3D(
					Basis.IDENTITY,
					Vector3(0.0, (floor_top - TileForgeConstants.BLOCK_DEPTH) * 0.5, 0.0)
				),
				"layer": 1,
				"name": "BasinFloor",
			})
	return shapes


## Constructed surfaces build their own pieces at the boundary, so the shell
## chamfer would double up on them. Everything organic gets the rim.
static func _wants_chamfer(recipe: TileRecipe) -> bool:
	for layer in recipe.enabled_surface_layers():
		if layer.generator_id == "module_layout" or layer.generator_id == "custom_mesh":
			return false
	return true


## The rim shares the TOP colour. Giving the chamfer its own lighter tone was
## tried and rejected: it read as a painted border around every tile, and a 3x3
## repeat turned into a bright grid. A chamfer is a lighting event, not a
## colour one — the facet angle supplies the highlight on its own.
static func _rim_slot(ctx: TileGenerationContext) -> String:
	return _first_top_slot(ctx.recipe.enabled_surface_layers())


static func _first_top_slot(layers: Array[TileSurfaceLayer]) -> String:
	for layer in layers:
		if layer.material_slot != "":
			return layer.material_slot
	return TileForgeConstants.SLOT_TOP_PRIMARY


## The tightest lock any connected layer asked for. Using the narrowest keeps
## the flattened band as small as the strictest layer wanted, so a tile does
## not lose its shape to an over-generous neighbour policy.
static func _narrowest_edge_lock(layers: Array[TileSurfaceLayer]) -> float:
	var width := 0.24
	var found := false
	for layer in layers:
		if layer.border_policy != TileForgeConstants.BorderPolicy.EDGE_LOCK:
			continue
		width = layer.edge_lock_width if not found else minf(width, layer.edge_lock_width)
		found = true
	return maxf(0.02, width)


static func _any_smooth(layers: Array[TileSurfaceLayer]) -> bool:
	for layer in layers:
		if layer.smooth_shading:
			return true
	return false
