@tool
class_name TileValidator
extends RefCounted
## Rejects a build before it can become a shipped asset.
##
## Every check here corresponds to a failure the brief calls out by name. They
## are cheap and they run on every bake and every variant, because the whole
## point of a curated variant set is that bad seeds are discarded automatically
## rather than found later in a screenshot review.

class Report:
	extends RefCounted
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var checks := 0
	var stats: Dictionary = {}

	func ok() -> bool:
		return errors.is_empty()

	func add_error(message: String) -> void:
		errors.append(message)

	func add_warning(message: String) -> void:
		warnings.append(message)

	func text() -> String:
		var lines: Array[String] = []
		lines.append("checks: %d  errors: %d  warnings: %d" % [
			checks, errors.size(), warnings.size()
		])
		for error in errors:
			lines.append("  ERROR   %s" % error)
		for warning in warnings:
			lines.append("  warning %s" % warning)
		return "\n".join(lines)


## Tolerance for "a vertex is exactly on the boundary", metres.
const BOUNDARY_EPSILON := 0.0005
## Two module footprints may overlap by this much before it counts as an
## intersection. A little nestling looks natural; more looks broken.
const OVERLAP_TOLERANCE := 0.012


static func validate(result: TileBuildResult) -> Report:
	var report := Report.new()
	if result == null or result.recipe == null:
		report.add_error("no build result")
		return report

	var recipe := result.recipe
	var ctx := result.context

	for error in ctx.errors:
		report.add_error(error)

	_check_footprint(result, recipe, report)
	_check_boundary_lock(result, recipe, report)
	_check_height_budget(result, recipe, report)
	_check_details_in_bounds(result, recipe, report)
	_check_detail_bedding(result, recipe, report)
	_check_detail_overlap(result, report)
	_check_repetition(result, report)
	_check_empty_space(result, recipe, report)
	_check_materials(result, report)
	_check_geometry_budget(result, report)
	_check_output_modes(result, report)
	_check_collision(result, recipe, report)
	_check_surface_connectivity(result, report)

	report.stats = {
		"triangles": result.triangle_count(),
		"instances": result.instances.size(),
		"slots": Array(result.slots_used()),
		"bounds": result.bounds(),
		"build_msec": result.build_msec,
	}
	return report


## The outer footprint must be EXACT. Organic variation is allowed to move the
## top up and down; it is never allowed to move the silhouette.
static func _check_footprint(
	result: TileBuildResult,
	recipe: TileRecipe,
	report: Report
) -> void:
	report.checks += 1
	var extent := recipe.half_extent()
	for part in result.parts:
		if part == null or part.mesh == null or part.part_role == "detail":
			continue
		var box := part.mesh.get_aabb()
		if box.position.x < -extent - BOUNDARY_EPSILON \
			or box.position.z < -extent - BOUNDARY_EPSILON \
			or box.end.x > extent + BOUNDARY_EPSILON \
			or box.end.z > extent + BOUNDARY_EPSILON:
			report.add_error(
				"part '%s' exceeds the tile footprint (%.4f..%.4f x, %.4f..%.4f z, limit %.4f)"
				% [part.part_role, box.position.x, box.end.x, box.position.z, box.end.z, extent]
			)

	report.checks += 1
	if recipe.is_connected_surface():
		# A connected top must actually REACH the boundary. Shrinking every
		# surface away from its edge is the "dark trench around every tile"
		# failure, and it is just as wrong as overflowing.
		var reached := false
		for part in result.parts:
			if part == null or part.mesh == null or part.part_role != "surface":
				continue
			var box := part.mesh.get_aabb()
			if absf(box.position.x + extent) <= BOUNDARY_EPSILON \
				and absf(box.end.x - extent) <= BOUNDARY_EPSILON \
				and absf(box.position.z + extent) <= BOUNDARY_EPSILON \
				and absf(box.end.z - extent) <= BOUNDARY_EPSILON:
				reached = true
		if not reached and not result.surface_parts().is_empty():
			report.add_error(
				"connected surface does not reach the tile boundary on all four sides"
			)


static func _check_boundary_lock(
	result: TileBuildResult,
	recipe: TileRecipe,
	report: Report
) -> void:
	report.checks += 1
	if not recipe.is_connected_surface():
		return
	var field := result.context.field
	if field == null:
		return
	var target := recipe.connected_edge_height
	var worst := 0.0
	for height in field.boundary_heights():
		worst = maxf(worst, absf(height - target))
	if worst > BOUNDARY_EPSILON:
		report.add_error(
			"boundary height drifts %.5f m from the connected height %.3f — neighbouring copies will not meet"
			% [worst, target]
		)


static func _check_height_budget(
	result: TileBuildResult,
	recipe: TileRecipe,
	report: Report
) -> void:
	report.checks += 1
	var field := result.context.field
	if field == null:
		return
	var top := field.max_height()
	var bottom := field.min_height()
	if top > TileForgeConstants.MAX_RAISED_TOP:
		report.add_error(
			"surface rises to %.3f m, above the raised-top ceiling %.3f"
			% [top, TileForgeConstants.MAX_RAISED_TOP]
		)
	if bottom < TileForgeConstants.MIN_RECESSED_TOP - 0.001:
		report.add_error(
			"surface drops to %.3f m, below the recessed floor %.3f"
			% [bottom, TileForgeConstants.MIN_RECESSED_TOP]
		)
	# A gently modulated top is the target; a 12 cm swing on ordinary terrain
	# reads as lumpy rather than as a miniature.
	if recipe.category == TileForgeConstants.Category.ORGANIC_SURFACE \
		and top - bottom > 0.12:
		report.add_warning(
			"organic surface relief is %.3f m peak-to-trough — check it still reads as a clean block"
			% (top - bottom)
		)


static func _check_details_in_bounds(
	result: TileBuildResult,
	recipe: TileRecipe,
	report: Report
) -> void:
	report.checks += 1
	var extent := recipe.half_extent()
	for instance in result.instances:
		var pos := instance.position()
		var reach := instance.footprint_radius
		if absf(pos.x) + reach > extent + BOUNDARY_EPSILON \
			or absf(pos.z) + reach > extent + BOUNDARY_EPSILON:
			report.add_error(
				"detail '%s' (rule %s) crosses the tile boundary at (%.3f, %.3f)"
				% [instance.module_path.get_file(), instance.rule_name, pos.x, pos.z]
			)


## Floating and buried modules are the two most visible detail failures, and
## both are invisible in a top-down screenshot — so they are checked
## numerically against the surface the module was placed on.
static func _check_detail_bedding(
	result: TileBuildResult,
	recipe: TileRecipe,
	report: Report
) -> void:
	report.checks += 1
	var field := result.context.field
	if field == null:
		return
	for instance in result.instances:
		var pos := instance.position()
		var u := pos.x / recipe.half_extent()
		var v := pos.z / recipe.half_extent()
		var ground := field.sample(u, v)
		var gap := pos.y - ground
		if gap > 0.012:
			report.add_error(
				"detail '%s' floats %.4f m above the surface"
				% [instance.module_path.get_file(), gap]
			)
		elif gap < -maxf(0.02, instance.height * 0.45):
			report.add_error(
				"detail '%s' is buried %.4f m into the surface"
				% [instance.module_path.get_file(), -gap]
			)


static func _check_detail_overlap(result: TileBuildResult, report: Report) -> void:
	report.checks += 1
	var overlaps := 0
	for i in result.instances.size():
		for j in range(i + 1, result.instances.size()):
			var a := result.instances[i]
			var b := result.instances[j]
			if a.permits_overlap and b.permits_overlap:
				continue
			if a.overlaps(b, OVERLAP_TOLERANCE):
				overlaps += 1
	if overlaps > 0:
		var budget: int = maxi(1, result.instances.size() / 6)
		if overlaps > budget:
			report.add_error(
				"%d detail pairs intersect beyond tolerance (budget %d)"
				% [overlaps, budget]
			)
		else:
			report.add_warning("%d detail pairs nestle closely" % overlaps)


## One module appearing five times on a tile is the single loudest "this was
## generated" signal. The module set's own cap should prevent it; this proves
## the cap was honoured.
static func _check_repetition(result: TileBuildResult, report: Report) -> void:
	report.checks += 1
	var counts: Dictionary = {}
	for instance in result.instances:
		var key := instance.module_path
		counts[key] = int(counts.get(key, 0)) + 1
	var total := result.instances.size()
	if total < 4:
		return
	for key: String in counts:
		var count: int = counts[key]
		if float(count) / float(total) > 0.55 and count >= 4:
			report.add_warning(
				"module '%s' is %d of %d placements — the field will read as repeated"
				% [key.get_file(), count, total]
			)


## Readable empty space is a composition requirement, not a nicety. Without it
## a tile becomes a texture and stops reading as a miniature.
static func _check_empty_space(
	result: TileBuildResult,
	recipe: TileRecipe,
	report: Report
) -> void:
	report.checks += 1
	if result.instances.is_empty():
		return
	var covered := 0.0
	for instance in result.instances:
		covered += PI * instance.footprint_radius * instance.footprint_radius
	var area := recipe.tile_size * recipe.tile_size
	var ratio := covered / maxf(0.0001, area)
	var target := 0.42
	for rule in recipe.enabled_detail_rules():
		if rule.composition != null:
			target = minf(target, rule.composition.empty_space_target)
	if ratio > 1.0 - target:
		report.add_error(
			"details cover %.0f%% of the tile; at least %.0f%% must stay readable empty space"
			% [ratio * 100.0, target * 100.0]
		)
	elif ratio > 0.85 - target:
		report.add_warning("detail coverage %.0f%% is close to the density limit" % (ratio * 100.0))


static func _check_materials(result: TileBuildResult, report: Report) -> void:
	report.checks += 1
	var slots := result.slots_used()
	# Every slot resolves to a SHARED semantic material, so a generated tile
	# never adds a unique material to the game. What this bounds is surface
	# count in the merged chunk mesh, and the collection's coherence: past six
	# tones one tile stops matching its neighbours.
	if slots.size() > 6:
		report.add_warning(
			"%d material slots on one tile — past six the tile stops reading as part of the set"
			% slots.size()
		)
	var palette := result.context.palette
	for slot in slots:
		if palette.key_for_slot(slot) == "":
			report.add_error("material slot '%s' is not bound by the palette" % slot)


static func _check_geometry_budget(result: TileBuildResult, report: Report) -> void:
	report.checks += 1
	var triangles := result.triangle_count()
	if triangles > 4000:
		report.add_error("%d triangles is far past the tile budget" % triangles)
	elif triangles > 1600:
		report.add_warning("%d triangles is heavy for one tile" % triangles)
	if triangles == 0:
		report.add_error("build produced no geometry")


## MULTIMESH output is legal but is NOT picked up by Suma's chunk batcher or by
## the cover cross-fade, both of which walk MeshInstance3D. Saying so here is
## cheaper than discovering it as an un-hiding tile under a stack.
static func _check_output_modes(result: TileBuildResult, report: Report) -> void:
	report.checks += 1
	for instance in result.instances:
		match instance.output:
			TileForgeConstants.DetailOutput.INDIVIDUAL_DEBUG_NODES:
				report.add_warning(
					"rule '%s' uses INDIVIDUAL_DEBUG_NODES — debug only, never ship it"
					% instance.rule_name
				)
				return
			TileForgeConstants.DetailOutput.MULTIMESH:
				report.add_warning(
					"rule '%s' uses MULTIMESH — Suma's world batcher and cover fade only walk MeshInstance3D"
					% instance.rule_name
				)
				return


static func _check_collision(
	result: TileBuildResult,
	recipe: TileRecipe,
	report: Report
) -> void:
	report.checks += 1
	if recipe.collision_mode == TileForgeConstants.CollisionMode.NONE:
		return
	if result.collision.is_empty():
		report.add_error("collision mode requests shapes but none were produced")
		return
	for entry in result.collision:
		var shape: Variant = entry.get("shape")
		if shape == null:
			report.add_error("collision entry has no shape")
			continue
		if shape is BoxShape3D:
			var size: Vector3 = (shape as BoxShape3D).size
			if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
				report.add_error("collision box has a non-positive dimension")
	report.checks += 1
	var triangles := result.triangle_count()
	if result.collision.size() > 6:
		report.add_warning(
			"%d collision shapes — collision should stay much simpler than the render mesh (%d tris)"
			% [result.collision.size(), triangles]
		)


## A surface split into disconnected islands means a hole opened somewhere in
## the field, usually from an over-aggressive SUBTRACT.
static func _check_surface_connectivity(result: TileBuildResult, report: Report) -> void:
	report.checks += 1
	var field := result.context.field
	if field == null:
		return
	var holes := 0
	for value in field.holes:
		if value == 1:
			holes += 1
	if holes == 0:
		return
	var total := field.resolution * field.resolution
	if float(holes) / float(total) > 0.6:
		report.add_error("surface is more hole than geometry (%d of %d vertices)" % [holes, total])
