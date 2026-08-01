extends SceneTree
## Authors the Tile Forge's shipped data: palettes, module sets, and the ten
## proof recipes. Run headless:
##
##   Godot --headless --path . --script tools/tile_forge/editor/build_library.gd
##
## Everything it writes is an ordinary .tres a designer can then open and edit
## in the inspector. This script exists because typing 54 measured module
## footprints by hand is error-prone, not because recipes need code: the
## measurements come straight from the Blender build report, so a module set can
## never disagree with the mesh it describes.
##
## Re-running is safe and idempotent. It overwrites the generated .tres files
## and leaves anything else alone.

const MODULE_REPORT := "res://tools/tile_forge/modules/build_report.json"
const PALETTE_DIR := "res://tools/tile_forge/materials"
const MODULE_SET_DIR := "res://tools/tile_forge/modules"
const RECIPE_DIR := "res://tools/tile_forge/recipes/proof_set"

var _modules: Dictionary = {}


func _init() -> void:
	_load_modules()
	if _modules.is_empty():
		push_error("no module build report — run build_tile_forge_modules.py first")
		quit(1)
		return
	_ensure_dirs()
	var palettes := _build_palettes()
	var sets := _build_module_sets()
	var recipes := _build_recipes(palettes, sets)
	print("TILE FORGE LIBRARY: %d palettes, %d module sets, %d recipes" % [
		palettes.size(), sets.size(), recipes.size()
	])
	quit(0)


func _ensure_dirs() -> void:
	for path in [PALETTE_DIR, MODULE_SET_DIR, RECIPE_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _load_modules() -> void:
	var file := FileAccess.open(MODULE_REPORT, FileAccess.READ)
	if file == null:
		return
	var report: Variant = JSON.parse_string(file.get_as_text())
	if not (report is Dictionary):
		return
	for entry: Dictionary in (report as Dictionary).get("modules", []):
		_modules[String(entry["id"])] = entry


func _save(resource: Resource, path: String) -> Resource:
	resource.take_over_path(path)
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		push_error("could not save %s (%d)" % [path, error])
	return resource


# --- palettes ----------------------------------------------------------------


func _palette(
	id: String,
	top_primary: String,
	top_secondary: String,
	accent: String,
	shadow: String,
	side: String,
	underside: String,
	inset: String,
	detail_a: String,
	detail_b: String,
	detail_c: String
) -> TilePalette:
	var palette := TilePalette.new()
	palette.palette_id = id
	palette.display_name = id.capitalize()
	palette.top_primary = top_primary
	palette.top_secondary = top_secondary
	palette.accent = accent
	palette.shadow = shadow
	palette.side = side
	palette.underside = underside
	palette.inset = inset
	palette.detail_a = detail_a
	palette.detail_b = detail_b
	palette.detail_c = detail_c
	return _save(palette, PALETTE_DIR.path_join("pal_%s.tres" % id)) as TilePalette


func _build_palettes() -> Dictionary:
	# Each palette is a handful of neighbours in one hue family plus the shared
	# earth side wall, so every generated tile sits in the same collection.
	return {
		"grass": _palette(
			"grass",
			"grass_primary", "grass_secondary", "grass_sunlit", "grass_shade",
			"earth_mid", "earth_deep", "earth_shadow",
			"grass_lush", "grass_tuft", "moss_primary"
		),
		"straw": _palette(
			"straw",
			"wood_gold", "gold_primary", "warm_yellow", "wood_warm_shadow",
			"earth_mid", "earth_deep", "earth_shadow",
			"warm_yellow", "gold_primary", "wood_light"
		),
		"sand": _palette(
			"sand",
			"sand_top", "sand_light", "sand_highlight", "sand_shadow",
			"sand_shadow", "sand_deep", "sand_deep",
			"sand_shadow", "sand_light", "sand_highlight"
		),
		"snow": _palette(
			"snow",
			"snow_top", "snow_light", "snow_highlight", "snow_shadow",
			"snow_side", "snow_deep", "snow_deep",
			"snow_light", "snow_shadow", "snow_highlight"
		),
		"dirt": _palette(
			"dirt",
			"earth_primary", "earth_mid", "earth_light", "earth_shadow",
			"earth_mid", "earth_deep", "earth_deep",
			"stone_mid", "stone_mid_light", "stone_shadow"
		),
		"wood": _palette(
			"wood",
			"wood_primary", "wood_gold", "wood_light", "wood_warm_shadow",
			"wood_brown", "wood_dark", "wood_dark",
			"wood_light", "wood_gold", "wood_brown"
		),
		"paving": _palette(
			"paving",
			"stone_mid", "stone_mid_light", "stone_light", "stone_shadow",
			"concrete_side", "stone_deep_shadow", "stone_shadow",
			"stone_light", "stone_mid_light", "stone_shadow"
		),
		"rubble": _palette(
			"rubble",
			"earth_primary", "earth_mid", "earth_light", "earth_shadow",
			"earth_mid", "earth_deep", "earth_deep",
			"stone_mid", "stone_mid_light", "stone_shadow"
		),
		"basin": _palette(
			"basin",
			"stone_mid", "stone_mid_light", "stone_light", "stone_shadow",
			"concrete_side", "stone_deep_shadow", "stone_shadow",
			"stone_mid_light", "stone_shadow", "moss_primary"
		),
	}


# --- module sets -------------------------------------------------------------


func _entry(module_id: String, sink := 0.006, slot := "") -> TileModuleEntry:
	var record: Dictionary = _modules.get(module_id, {})
	if record.is_empty():
		push_error("unknown module '%s'" % module_id)
		return null
	var entry := TileModuleEntry.new()
	entry.mesh_path = String(record["path"])
	# Measured, not guessed: a placer trusts these for separation and bounds.
	entry.footprint_radius = float(record["footprint_radius"])
	entry.height = float(record["height"])
	entry.sink = sink
	entry.tags = PackedStringArray([String(record["family"])])
	if slot != "":
		entry.material_slot = slot
	return entry


func _module_set(
	set_id: String,
	family: String,
	module_ids: Array,
	separation_scale: float,
	max_repeats: int,
	sink := 0.006
) -> TileModuleSet:
	var result := TileModuleSet.new()
	result.set_id = set_id
	result.display_name = set_id.capitalize()
	result.family = family
	result.separation_scale = separation_scale
	result.max_repeats_per_module = max_repeats
	var entries: Array[TileModuleEntry] = []
	for index in module_ids.size():
		var entry := _entry(String(module_ids[index]), sink)
		if entry == null:
			continue
		# Unequal weights: a set with one clear favourite and two rarities
		# composes better than a set of equals.
		entry.weight = [1.0, 0.85, 0.7, 0.55, 0.45, 0.4, 0.35, 0.3][mini(index, 7)]
		entries.append(entry)
	result.modules = entries
	return _save(result, MODULE_SET_DIR.path_join("set_%s.tres" % set_id)) as TileModuleSet


func _build_module_sets() -> Dictionary:
	return {
		"grass_short": _module_set(
			"grass_short", "grass",
			["gf_grass_short_a", "gf_grass_short_b", "gf_grass_short_c",
			 "gf_grass_short_d", "gf_grass_short_e"],
			1.15, 3, 0.008
		),
		"grass_broad": _module_set(
			"grass_broad", "grass",
			["gf_grass_broad_a", "gf_grass_broad_b", "gf_grass_broad_c",
			 "gf_grass_broad_d", "gf_grass_broad_e"],
			1.05, 2, 0.010
		),
		"moss": _module_set(
			"moss", "grass",
			["gf_moss_a", "gf_moss_b", "gf_moss_c", "gf_moss_d"],
			1.0, 2, 0.008
		),
		"straw": _module_set(
			"straw", "straw",
			["gf_straw_a", "gf_straw_b", "gf_straw_c", "gf_straw_d", "gf_straw_e"],
			0.75, 3, 0.004
		),
		"pebbles": _module_set(
			"pebbles", "gravel",
			["gf_pebble_a", "gf_pebble_b", "gf_pebble_c", "gf_pebble_d",
			 "gf_pebble_e", "gf_pebble_f", "gf_pebble_g", "gf_pebble_h"],
			1.1, 3, 0.005
		),
		"stones": _module_set(
			"stones", "stones",
			["gf_stone_a", "gf_stone_b", "gf_stone_c", "gf_stone_d",
			 "gf_stone_e", "gf_stone_f"],
			1.25, 2, 0.010
		),
		"rubble": _module_set(
			"rubble", "rubble",
			["gf_rubble_a", "gf_rubble_b", "gf_rubble_c", "gf_rubble_d", "gf_rubble_e"],
			1.15, 2, 0.006
		),
		"woodchips": _module_set(
			"woodchips", "rubble",
			["gf_woodchip_a", "gf_woodchip_b", "gf_woodchip_c", "gf_woodchip_d"],
			0.9, 2, 0.004
		),
		"leaves": _module_set(
			"leaves", "leaves",
			["gf_leafpile_a", "gf_leafpile_b", "gf_leafpile_c", "gf_leafpile_d"],
			0.85, 2, 0.004
		),
		"boards": _module_set(
			"boards", "boards",
			["gf_board_a", "gf_board_b", "gf_board_c", "gf_board_d"],
			1.2, 2, 0.002
		),
		"pavers": _module_set(
			"pavers", "pavers",
			["gf_paver_a", "gf_paver_b", "gf_paver_c", "gf_paver_d"],
			1.2, 2, 0.002
		),
	}


# --- recipe helpers ----------------------------------------------------------


func _shape(
	kind: TileForgeConstants.Shape,
	cx: float,
	cy: float,
	ex: float,
	ey: float,
	height: float,
	rotation := 0.0,
	softness := 0.55,
	asymmetry := 0.0
) -> TileShapePrimitive:
	var shape := TileShapePrimitive.new()
	shape.shape = kind
	shape.center = Vector2(cx, cy)
	shape.extents = Vector2(ex, ey)
	shape.height = height
	shape.rotation_deg = rotation
	shape.softness = softness
	shape.asymmetry = asymmetry
	return shape


func _layer(
	generator_id: String,
	layer_name: String,
	slot: String,
	resolution: int,
	shapes: Array[TileShapePrimitive]
) -> TileSurfaceLayer:
	var layer := TileSurfaceLayer.new()
	layer.generator_id = generator_id
	layer.layer_name = layer_name
	layer.material_slot = slot
	layer.resolution = resolution
	layer.shapes = shapes
	return layer


func _composition(
	pattern: TileForgeConstants.Composition,
	border_margin: float,
	clustering: float,
	empty_space: float
) -> TileCompositionPattern:
	var composition := TileCompositionPattern.new()
	composition.pattern = pattern
	composition.border_margin = border_margin
	composition.clustering = clustering
	composition.empty_space_target = empty_space
	return composition


func _rule(
	rule_name: String,
	generator_id: String,
	module_set: TileModuleSet,
	composition: TileCompositionPattern,
	low: int,
	high: int,
	seed_offset: int
) -> TileDetailRule:
	var rule := TileDetailRule.new()
	rule.rule_name = rule_name
	rule.generator_id = generator_id
	rule.module_set = module_set
	rule.composition = composition
	rule.min_count = low
	rule.max_count = high
	rule.seed_offset = seed_offset
	return rule


func _base(mode: TileForgeConstants.BaseMode) -> TileBaseProfile:
	var profile := TileBaseProfile.new()
	profile.mode = mode
	profile.seam_y = profile.canonical_seam()
	return profile


func _recipe(
	tile_id: String,
	display_name: String,
	category: TileForgeConstants.Category,
	tags: Array,
	palette: TilePalette,
	base_mode: TileForgeConstants.BaseMode,
	seed_value: int
) -> TileRecipe:
	var recipe := TileRecipe.new()
	recipe.tile_id = tile_id
	recipe.display_name = display_name
	recipe.category = category
	recipe.tags = PackedStringArray(tags)
	recipe.palette = palette
	recipe.base_profile = _base(base_mode)
	recipe.seed_value = seed_value
	return recipe


# --- the ten proof recipes ---------------------------------------------------


func _build_recipes(palettes: Dictionary, sets: Dictionary) -> Array:
	var made: Array = []
	made.append(_grass_smooth(palettes))
	made.append(_grass_lush_clumps(palettes, sets))
	made.append(_straw_dense(palettes, sets))
	made.append(_sand_soft_waves(palettes))
	made.append(_snow_drift(palettes))
	made.append(_dirt_pebbles(palettes, sets))
	made.append(_wood_planks(palettes))
	made.append(_soft_pavers(palettes))
	made.append(_stone_rubble(palettes, sets))
	made.append(_recessed_water_basin(palettes))
	return made


func _write_recipe(recipe: TileRecipe) -> TileRecipe:
	return _save(
		recipe, RECIPE_DIR.path_join("%s.tres" % recipe.tile_id)
	) as TileRecipe


## 1. Plain connected meadow. Three overlapping broad mounds at different
## sizes; the boundary is locked flat so any two copies meet exactly.
func _grass_smooth(palettes: Dictionary) -> TileRecipe:
	var recipe := _recipe(
		"tf_grass_smooth", "Smooth Meadow",
		TileForgeConstants.Category.ORGANIC_SURFACE,
		["grass", "meadow"],
		palettes["grass"], TileForgeConstants.BaseMode.SHARED_STANDARD, 1701
	)
	var shapes: Array[TileShapePrimitive] = [
		_shape(TileForgeConstants.Shape.BROAD_MOUND, -0.28, 0.14, 0.78, 0.66, 0.021, 0.0, 0.62),
		_shape(TileForgeConstants.Shape.BROAD_MOUND, 0.42, -0.36, 0.62, 0.72, 0.015, 0.0, 0.7),
		_shape(TileForgeConstants.Shape.DEPRESSION, 0.06, 0.52, 0.5, 0.42, 0.011, 0.0, 0.75),
	]
	var layer := _layer(
		"heightfield_surface", "meadow_top",
		TileForgeConstants.SLOT_TOP_PRIMARY, 7, shapes
	)
	layer.secondary_slot = TileForgeConstants.SLOT_TOP_SECONDARY
	layer.secondary_share = 0.34
	layer.edge_lock_width = 0.26
	layer.params = {"micro_relief": 0.4, "micro_scale": 1.4}
	recipe.surface_layers = [layer]
	recipe.collision_mode = TileForgeConstants.CollisionMode.FLAT_BOX
	recipe.preview_notes = "Two restrained greens, no details. The control tile for seam review."
	return _write_recipe(recipe)


## 2. The same connected grass top, dressed with a handful of large clumps in
## three unequal groups. Deliberate gaps are the composition.
func _grass_lush_clumps(palettes: Dictionary, sets: Dictionary) -> TileRecipe:
	var recipe := _recipe(
		"tf_grass_lush_clumps", "Lush Meadow",
		TileForgeConstants.Category.SURFACE_WITH_DETAILS,
		["grass", "meadow"],
		palettes["grass"], TileForgeConstants.BaseMode.SHARED_STANDARD, 2244
	)
	var shapes: Array[TileShapePrimitive] = [
		_shape(TileForgeConstants.Shape.BROAD_MOUND, 0.3, 0.22, 0.72, 0.68, 0.018, 0.0, 0.66),
		_shape(TileForgeConstants.Shape.BROAD_MOUND, -0.4, -0.3, 0.58, 0.62, 0.013, 0.0, 0.7),
	]
	var layer := _layer(
		"heightfield_surface", "meadow_top",
		TileForgeConstants.SLOT_TOP_PRIMARY, 7, shapes
	)
	layer.secondary_slot = TileForgeConstants.SLOT_TOP_SECONDARY
	layer.secondary_share = 0.3
	recipe.surface_layers = [layer]

	var composition := _composition(
		TileForgeConstants.Composition.THREE_CLUSTERS, 0.2, 0.6, 0.48
	)
	var broad := _rule(
		"broad_clumps", "clump_field", sets["grass_broad"], composition, 5, 8, 17
	)
	broad.scale_range = Vector2(0.9, 1.25)
	broad.min_separation = 0.035
	broad.max_tilt_deg = 4.0
	broad.material_variant_weights = PackedFloat32Array([1.0, 0.55, 0.0])

	var accents := _composition(
		TileForgeConstants.Composition.SPARSE_ACCENTS, 0.24, 0.3, 0.6
	)
	var small := _rule(
		"small_tufts", "clump_field", sets["grass_short"], accents, 2, 4, 41
	)
	small.scale_range = Vector2(0.85, 1.1)
	small.min_separation = 0.05
	small.material_variant_weights = PackedFloat32Array([1.0, 0.55, 0.0])

	recipe.detail_rules = [broad, small]
	recipe.custom_params = {"broad_clumps.accent_share": 0.3}
	recipe.preview_notes = "5-8 large clumps in three unequal groups plus a few small tufts."
	return _write_recipe(recipe)


## 3. Dense golden straw. Density is high but a DENSE_FIELD_WITH_CLEARINGS
## composition carves real holes, so the tile stays readable.
func _straw_dense(palettes: Dictionary, sets: Dictionary) -> TileRecipe:
	var recipe := _recipe(
		"tf_straw_dense", "Straw Bed",
		TileForgeConstants.Category.SURFACE_WITH_DETAILS,
		["straw", "farm"],
		palettes["straw"], TileForgeConstants.BaseMode.SHARED_STANDARD, 3311
	)
	var shapes: Array[TileShapePrimitive] = [
		_shape(TileForgeConstants.Shape.BROAD_MOUND, 0.0, 0.0, 0.85, 0.85, 0.012, 0.0, 0.8),
	]
	var layer := _layer(
		"heightfield_surface", "straw_bed",
		TileForgeConstants.SLOT_TOP_PRIMARY, 5, shapes
	)
	layer.secondary_slot = TileForgeConstants.SLOT_TOP_SECONDARY
	layer.secondary_share = 0.4
	recipe.surface_layers = [layer]

	var composition := _composition(
		TileForgeConstants.Composition.DENSE_FIELD_WITH_CLEARINGS, 0.13, 0.4, 0.3
	)
	var straw := _rule(
		"straw_mat", "clump_field", sets["straw"], composition, 10, 15, 23
	)
	straw.scale_range = Vector2(0.85, 1.2)
	# Straw lies across itself. A mat that keeps its distance reads as scattered
	# sticks, so this family is allowed to interleave — and says so honestly.
	straw.min_separation = -0.075
	straw.permit_intersection = true
	straw.max_tilt_deg = 3.0
	straw.material_variant_weights = PackedFloat32Array([1.0, 0.6, 0.0])
	recipe.detail_rules = [straw]
	recipe.preview_notes = "Chunky hay clumps, dense but with authored clearings."
	return _write_recipe(recipe)


## 4. Three broad directional ridges from the drift generator. No details: the
## silhouette is the whole design.
func _sand_soft_waves(palettes: Dictionary) -> TileRecipe:
	var recipe := _recipe(
		"tf_sand_soft_waves", "Rippled Sand",
		TileForgeConstants.Category.ORGANIC_SURFACE,
		["sand", "beach"],
		palettes["sand"], TileForgeConstants.BaseMode.SHARED_STANDARD, 4455
	)
	var layer := _layer(
		"drift", "sand_waves",
		TileForgeConstants.SLOT_TOP_PRIMARY, 13, [] as Array[TileShapePrimitive]
	)
	layer.secondary_slot = TileForgeConstants.SLOT_TOP_SECONDARY
	layer.secondary_share = 0.28
	layer.edge_lock_width = 0.22
	layer.params = {
		"ridge_count": 3,
		"flow_angle_deg": 24.0,
		"ridge_height": 0.026,
		"ridge_spacing_jitter": 0.4,
		"crest_asymmetry": 0.5,
		"ridge_length": 1.6,
		"valley_depth_ratio": 0.4,
	}
	recipe.surface_layers = [layer]
	recipe.preview_notes = "Three uneven wind ridges; connected edge stays exact."
	return _write_recipe(recipe)


## 5. Two broad snow drifts. Cool-white palette, no sparkle, no glitter.
func _snow_drift(palettes: Dictionary) -> TileRecipe:
	var recipe := _recipe(
		"tf_snow_drift", "Snow Drift",
		TileForgeConstants.Category.ORGANIC_SURFACE,
		["snow", "winter"],
		palettes["snow"], TileForgeConstants.BaseMode.SHARED_STANDARD, 5566
	)
	var shapes: Array[TileShapePrimitive] = [
		_shape(TileForgeConstants.Shape.DRIFT, -0.22, -0.1, 0.9, 0.66, 0.052, 34.0, 0.6, 0.55),
		_shape(TileForgeConstants.Shape.DRIFT, 0.44, 0.42, 0.72, 0.44, 0.034, 22.0, 0.7, -0.4),
		_shape(TileForgeConstants.Shape.DEPRESSION, -0.5, 0.55, 0.44, 0.38, 0.014, 0.0, 0.8),
	]
	var layer := _layer(
		"heightfield_surface", "snow_top",
		TileForgeConstants.SLOT_TOP_PRIMARY, 13, shapes
	)
	layer.secondary_slot = TileForgeConstants.SLOT_TOP_SECONDARY
	layer.secondary_share = 0.3
	layer.edge_lock_width = 0.24
	layer.params = {"micro_relief": 0.3, "micro_scale": 1.1}
	recipe.surface_layers = [layer]
	recipe.collision_mode = TileForgeConstants.CollisionMode.FROM_HEIGHTFIELD_MEDIAN
	recipe.preview_notes = "Two broad drifts and one hollow. Restrained cool whites."
	return _write_recipe(recipe)


## 6. Smooth dirt with grouped stones and varied empty space.
func _dirt_pebbles(palettes: Dictionary, sets: Dictionary) -> TileRecipe:
	var recipe := _recipe(
		"tf_dirt_pebbles", "Pebbled Dirt",
		TileForgeConstants.Category.SURFACE_WITH_DETAILS,
		["dirt", "path"],
		palettes["dirt"], TileForgeConstants.BaseMode.SHARED_STANDARD, 6677
	)
	var shapes: Array[TileShapePrimitive] = [
		_shape(TileForgeConstants.Shape.BROAD_MOUND, 0.2, -0.24, 0.7, 0.66, 0.012, 0.0, 0.72),
		_shape(TileForgeConstants.Shape.DEPRESSION, -0.36, 0.3, 0.56, 0.5, 0.010, 0.0, 0.8),
	]
	var layer := _layer(
		"heightfield_surface", "dirt_top",
		TileForgeConstants.SLOT_TOP_PRIMARY, 7, shapes
	)
	layer.secondary_slot = TileForgeConstants.SLOT_TOP_SECONDARY
	layer.secondary_share = 0.32
	recipe.surface_layers = [layer]

	var groups := _composition(
		TileForgeConstants.Composition.PATCHES, 0.16, 0.72, 0.5
	)
	var pebbles := _rule(
		"pebble_groups", "pebble_field", sets["pebbles"], groups, 8, 13, 31
	)
	pebbles.scale_range = Vector2(0.8, 1.3)
	pebbles.min_separation = 0.012
	pebbles.align_to_surface_normal = true
	pebbles.normal_align_strength = 0.55
	pebbles.max_tilt_deg = 8.0
	pebbles.material_variant_weights = PackedFloat32Array([1.0, 0.5, 0.0])

	var accents := _composition(
		TileForgeConstants.Composition.SPARSE_ACCENTS, 0.22, 0.2, 0.65
	)
	var stones := _rule(
		"loose_stones", "pebble_field", sets["stones"], accents, 2, 3, 57
	)
	stones.scale_range = Vector2(0.85, 1.15)
	stones.min_separation = 0.06
	stones.align_to_surface_normal = true
	stones.material_variant_weights = PackedFloat32Array([1.0, 0.5, 0.0])

	recipe.detail_rules = [pebbles, stones]
	recipe.preview_notes = "Grouped stones with real gaps; every stone stays separable."
	return _write_recipe(recipe)


## 7. Constructed plank deck. Boards reach the boundary exactly so two tiles
## read as one deck.
func _wood_planks(palettes: Dictionary) -> TileRecipe:
	var recipe := _recipe(
		"tf_wood_planks", "Plank Deck",
		TileForgeConstants.Category.CONSTRUCTED_SURFACE,
		["wood", "constructed"],
		palettes["wood"], TileForgeConstants.BaseMode.SHARED_DEEP_RECESS, 7788
	)
	var layer := _layer(
		"board_pattern", "deck",
		TileForgeConstants.SLOT_TOP_PRIMARY, 2, [] as Array[TileShapePrimitive]
	)
	layer.secondary_slot = TileForgeConstants.SLOT_TOP_SECONDARY
	layer.smooth_shading = false
	layer.params = {
		"layout": "horizontal",
		"board_count": 5,
		"gap": 0.011,
		"board_thickness": 0.175,
		"bevel": 0.007,
		"height_variation": 0.0035,
		"colour_variation": 0.4,
		"joint_rows": 1,
	}
	recipe.surface_layers = [layer]
	recipe.connection_mode = "tiny_individual_seam"
	recipe.preview_notes = "Five boards, shallow gaps, warm two-tone variation."
	return _write_recipe(recipe)


## 8. Soft paving. Restrained rounding, shallow seams, no pillow.
func _soft_pavers(palettes: Dictionary) -> TileRecipe:
	var recipe := _recipe(
		"tf_soft_pavers", "Soft Pavers",
		TileForgeConstants.Category.CONSTRUCTED_SURFACE,
		["stone", "constructed"],
		palettes["paving"], TileForgeConstants.BaseMode.SHARED_DEEP_RECESS, 8899
	)
	var layer := _layer(
		"paver_pattern", "pavers",
		TileForgeConstants.SLOT_TOP_PRIMARY, 2, [] as Array[TileShapePrimitive]
	)
	layer.secondary_slot = TileForgeConstants.SLOT_TOP_SECONDARY
	layer.smooth_shading = false
	layer.params = {
		"template": "mixed",
		"joint": 0.016,
		"paver_thickness": 0.175,
		"bevel": 0.009,
		"corner_radius": 0.022,
		"corner_segments": 2,
		"height_variation": 0.003,
		"colour_variation": 0.32,
	}
	recipe.surface_layers = [layer]
	recipe.connection_mode = "tiny_individual_seam"
	recipe.preview_notes = "Authored mixed layout: one large slab plus fill pieces."
	return _write_recipe(recipe)


## 9. Earth base carrying a few medium rubble forms in one readable composition.
func _stone_rubble(palettes: Dictionary, sets: Dictionary) -> TileRecipe:
	var recipe := _recipe(
		"tf_stone_rubble", "Stone Rubble",
		TileForgeConstants.Category.SURFACE_WITH_DETAILS,
		["stone", "ruin"],
		palettes["rubble"], TileForgeConstants.BaseMode.SHARED_STANDARD, 9911
	)
	var shapes: Array[TileShapePrimitive] = [
		_shape(TileForgeConstants.Shape.BROAD_MOUND, -0.18, 0.26, 0.66, 0.6, 0.014, 0.0, 0.7),
		_shape(TileForgeConstants.Shape.DEPRESSION, 0.4, -0.32, 0.5, 0.46, 0.012, 0.0, 0.78),
	]
	var layer := _layer(
		"heightfield_surface", "ruin_ground",
		TileForgeConstants.SLOT_TOP_PRIMARY, 7, shapes
	)
	layer.secondary_slot = TileForgeConstants.SLOT_TOP_SECONDARY
	layer.secondary_share = 0.3
	recipe.surface_layers = [layer]

	var composition := _composition(
		TileForgeConstants.Composition.DIAGONAL_FLOW, 0.2, 0.55, 0.52
	)
	composition.flow_angle_deg = 52.0
	composition.flow_strength = 0.6
	var rubble := _rule(
		"rubble_run", "rubble_field", sets["rubble"], composition, 4, 6, 13
	)
	rubble.scale_range = Vector2(0.85, 1.3)
	rubble.min_separation = 0.02
	rubble.max_tilt_deg = 14.0
	rubble.align_to_surface_normal = true
	rubble.normal_align_strength = 0.45
	rubble.material_variant_weights = PackedFloat32Array([1.0, 0.45, 0.0])

	var chips := _composition(
		TileForgeConstants.Composition.SPARSE_ACCENTS, 0.2, 0.3, 0.6
	)
	var debris := _rule(
		"stone_chips", "pebble_field", sets["pebbles"], chips, 3, 5, 71
	)
	debris.scale_range = Vector2(0.7, 1.0)
	debris.min_separation = 0.03
	debris.align_to_surface_normal = true
	debris.material_variant_weights = PackedFloat32Array([1.0, 0.0, 0.0])

	recipe.detail_rules = [rubble, debris]
	recipe.custom_params = {"rubble_run.cluster_radius": 0.18}
	recipe.preview_notes = "A diagonal run of medium fragments, not a shard pile."
	return _write_recipe(recipe)


## 10. Structural rim, carved cavity, separate water plane, rim collision.
func _recessed_water_basin(palettes: Dictionary) -> TileRecipe:
	var recipe := _recipe(
		"tf_water_basin", "Water Basin",
		TileForgeConstants.Category.WATER_SURFACE,
		["water", "basin"],
		palettes["basin"], TileForgeConstants.BaseMode.SHARED_DEEP_RECESS, 10122
	)
	var layer := _layer(
		"basin", "basin",
		TileForgeConstants.SLOT_TOP_PRIMARY, 13, [] as Array[TileShapePrimitive]
	)
	layer.smooth_shading = false
	layer.border_policy = TileForgeConstants.BorderPolicy.EDGE_LOCK
	layer.params = {
		"shape": "rounded",
		"inner": 0.6,
		"depth": 0.15,
		"rim_height": 0.0,
		"wall_softness": 0.1,
		"step_count": 1,
		"step_inset": 0.09,
		"step_drop": 0.05,
		"water": true,
		"water_level": -0.055,
		"water_inset": 0.015,
	}
	recipe.surface_layers = [layer]
	recipe.collision_mode = TileForgeConstants.CollisionMode.RIM_BOX
	recipe.custom_params = {
		"rim_inner": 0.6,
		"rim_height": 0.2,
		"basin_floor": -0.15,
	}
	recipe.edge_policy = TileForgeConstants.EdgePolicy.CONNECTED_SAME_SURFACE
	recipe.connection_mode = "tiny_individual_seam"
	recipe.preview_notes = "Structural rim, stepped cavity, water on its own render layer."
	return _write_recipe(recipe)
