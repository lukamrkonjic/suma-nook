extends SceneTree
## TEMPORARY smoke probe — deleted immediately after running.

func _make_module(radius: float, tall: float) -> TileModuleEntry:
	var entry := TileModuleEntry.new()
	entry.mesh_path = "res://tools/tile_forge/modules/fake_%.3f.glb" % radius
	entry.footprint_radius = radius
	entry.height = tall
	entry.scale_range = Vector2(0.8, 1.2)
	entry.sink = 0.006
	entry.max_tilt_deg = 6.0
	return entry


func _make_ctx() -> TileGenerationContext:
	var recipe := TileRecipe.new()
	recipe.tile_id = "probe_tile"
	recipe.seed_value = 7
	recipe.palette = TilePalette.new()
	recipe.custom_params = {
		"clumps.accent_share": 0.5,
		"stones.cluster_radius": 0.30,
		"stones.edge_scale_drop": 0.18,
		"shards.cluster_radius": 0.16,
		"shards.cluster_max": 4,
	}
	var ctx := TileGenerationContext.new(recipe)
	var field := TileHeightField.new(7, recipe.half_extent())
	for j in field.resolution:
		for i in field.resolution:
			var u := field.axis(i)
			var v := field.axis(j)
			field.heights[field.index_of(i, j)] = 0.04 * maxf(
				0.0, 1.0 - Vector2(u, v).length()
			)
	ctx.field = field
	return ctx


func _make_rule(name: String, gid: String, count: int, radius: float) -> TileDetailRule:
	var rule := TileDetailRule.new()
	rule.rule_name = name
	rule.generator_id = gid
	rule.min_count = count
	rule.max_count = count
	rule.min_separation = 0.0
	rule.border_exclusion = 0.03
	rule.scale_range = Vector2(0.85, 1.15)
	var set := TileModuleSet.new()
	set.separation_scale = 0.4
	set.max_repeats_per_module = 12
	set.modules = [
		_make_module(radius, 0.08),
		_make_module(radius * 1.3, 0.10),
		_make_module(radius * 0.8, 0.06),
	]
	rule.module_set = set
	var pattern := TileCompositionPattern.new()
	pattern.pattern = TileForgeConstants.Composition.THREE_CLUSTERS
	pattern.clustering = 0.85
	rule.composition = pattern
	return rule


func _initialize() -> void:
	var fails := 0

	# --- A: clumps stand upright, keep scale, take accents ------------------
	var ctx := _make_ctx()
	var clump_rule := _make_rule("clumps", "clump_field", 20, 0.05)
	clump_rule.max_tilt_deg = 6.0
	var clumps := ClumpFieldGenerator.new()
	var a := clumps.generate_instances(null, clump_rule, ctx)
	print("A placed=", a.size(), " reports=", ctx.messages.size())
	if ctx.messages.is_empty():
		print("  FAIL: max_count 20 > 14 should have been reported")
		fails += 1
	var accents := 0
	for inst in a:
		var up: Vector3 = inst.transform.basis.y.normalized()
		if up.angle_to(Vector3.UP) > 0.0001:
			print("  FAIL: clump not upright, lean=", rad_to_deg(up.angle_to(Vector3.UP)))
			fails += 1
		var s: float = inst.uniform_scale()
		if s < 0.8 or s > 1.2:
			print("  FAIL: clump scale out of range ", s)
			fails += 1
		if inst.material_slot == TileForgeConstants.SLOT_ACCENT:
			accents += 1
			if not inst.group_key.ends_with(TileForgeConstants.SLOT_ACCENT):
				print("  FAIL: group_key not refreshed after accent swap")
				fails += 1
	print("  accents=", accents, "/", a.size())
	if accents == 0 or accents == a.size():
		print("  FAIL: accent bias produced a degenerate split")
		fails += 1

	# yaw must still vary after the upright pass
	var yaws := {}
	for inst in a:
		yaws[snappedf(atan2(inst.transform.basis.z.x, inst.transform.basis.z.z), 0.01)] = true
	if yaws.size() < maxi(2, a.size() / 2):
		print("  FAIL: upright pass collapsed the yaw variety (", yaws.size(), ")")
		fails += 1

	# --- B: pebbles lean, get free yaw, and are size-graded -----------------
	var ctx_b := _make_ctx()
	var pebble_rule := _make_rule("stones", "pebble_field", 16, 0.04)
	var pebbles := PebbleFieldGenerator.new()
	var b := pebbles.generate_instances(null, pebble_rule, ctx_b)
	print("B placed=", b.size())
	var leaned := 0
	var graded := 0
	for inst in b:
		var module := pebble_rule.module_set.entry(inst.module_index)
		var s: float = inst.uniform_scale()
		if s < module.scale_range.x - 0.0001 or s > module.scale_range.y + 0.0001:
			print("  FAIL: graded scale left the module range ", s)
			fails += 1
		if absf(inst.footprint_radius - module.footprint_radius * s) > 0.00001:
			print("  FAIL: footprint_radius disagrees with scale")
			fails += 1
		if absf(inst.height - module.height * s) > 0.00001:
			print("  FAIL: height disagrees with scale")
			fails += 1
		var up: Vector3 = inst.transform.basis.y.normalized()
		if up.angle_to(Vector3.UP) > 0.0005:
			leaned += 1
		if s < 1.149:
			graded += 1
		# bedding must survive the rescale
		var ground: float = ctx_b.surface_height(
			inst.position().x / ctx_b.half_extent,
			inst.position().z / ctx_b.half_extent
		)
		var gap: float = inst.position().y - ground
		if gap > 0.012 or gap < -maxf(0.02, inst.height * 0.45):
			print("  FAIL: pebble bedding broke, gap=", gap)
			fails += 1
	print("  leaned=", leaned, " graded=", graded)
	if leaned == 0:
		print("  FAIL: no pebble leaned towards the surface normal")
		fails += 1

	# --- C: rubble tilts hard and culls dense clusters ----------------------
	var ctx_c := _make_ctx()
	var rubble_rule := _make_rule("shards", "rubble_field", 22, 0.03)
	rubble_rule.max_tilt_deg = 14.0
	var rubble := RubbleGenerator.new()
	var raw_count := TileDetailPlacer.place(rubble_rule, ctx_c, "rubble_field").size()
	var c := rubble.generate_instances(null, rubble_rule, ctx_c)
	print("C raw=", raw_count, " kept=", c.size(), " reports=", ctx_c.messages.size())
	if c.size() >= raw_count:
		print("  NOTE: no cluster exceeded the cap in this seed")
	var max_lean := 0.0
	var min_lean := 999.0
	for inst in c:
		var up: Vector3 = inst.transform.basis.y.normalized()
		var lean: float = rad_to_deg(up.angle_to(Vector3.UP))
		max_lean = maxf(max_lean, lean)
		min_lean = minf(min_lean, lean)
	print("  lean range=", min_lean, "..", max_lean)
	if max_lean > 14.001:
		print("  FAIL: rubble tilt exceeded rule.max_tilt_deg")
		fails += 1
	if max_lean < 6.5:
		print("  FAIL: rubble never exceeded the placer's per-module cap")
		fails += 1
	if min_lean < 14.0 * 0.35 - 0.001:
		print("  FAIL: rubble tilt fell below tilt_min_share")
		fails += 1
	if not rubble.generate_collision(null, ctx_c).is_empty():
		print("  FAIL: rubble collision should be empty")
		fails += 1
	# cluster cap actually enforced
	for i in c.size():
		var near := 0
		for j in c.size():
			var d: float = Vector2(c[i].position().x, c[i].position().z).distance_to(
				Vector2(c[j].position().x, c[j].position().z)
			)
			if d <= 0.16:
				near += 1
		if near > 8:
			print("  NOTE: dense neighbourhood of ", near, " survived (clusters are centroid-based)")
			break

	# --- determinism --------------------------------------------------------
	var ctx2 := _make_ctx()
	var a2 := clumps.generate_instances(null, _make_rule("clumps", "clump_field", 20, 0.05), ctx2)
	if a2.size() != a.size():
		print("  FAIL: clump count not reproducible")
		fails += 1
	else:
		for i in a.size():
			if a[i].transform != a2[i].transform or a[i].material_slot != a2[i].material_slot:
				print("  FAIL: clump ", i, " not reproducible")
				fails += 1
				break

	var ctx3 := _make_ctx()
	var c2 := rubble.generate_instances(null, _make_rule_tilt("shards", 22, 0.03), ctx3)
	if c2.size() != c.size():
		print("  FAIL: rubble count not reproducible")
		fails += 1
	else:
		for i in c.size():
			if c[i].transform != c2[i].transform:
				print("  FAIL: rubble ", i, " not reproducible")
				fails += 1
				break

	print("FAILS=", fails)
	quit(0)


func _make_rule_tilt(name: String, count: int, radius: float) -> TileDetailRule:
	var rule := _make_rule(name, "rubble_field", count, radius)
	rule.max_tilt_deg = 14.0
	return rule
