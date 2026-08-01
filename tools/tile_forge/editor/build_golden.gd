extends SceneTree
## Authors the three GOLDEN TILES that establish Suma's tile art standard.
##
##   golden_grass_lush   organic surface + composed clump field
##   golden_soft_pavers  constructed surface from curated paver modules
##   golden_wood_planks  constructed surface from curated board modules
##
## Nothing else is built here. The other seven proof recipes stay unwritten
## until these three are visually approved, because every later tile inherits
## whatever these establish — bevel weight, relief amplitude, detail scale,
## colour separation, and composition hierarchy.
##
##   Godot --headless --path . --script tools/tile_forge/editor/build_golden.gd

const MODULE_REPORT := "res://tools/tile_forge/modules/build_report.json"
const PALETTE_DIR := "res://tools/tile_forge/materials"
const MODULE_SET_DIR := "res://tools/tile_forge/modules"
const RECIPE_DIR := "res://tools/tile_forge/recipes/golden"

var _modules: Dictionary = {}
var _art: SumaTileArtProfile


func _init() -> void:
	_load_modules()
	if _modules.is_empty():
		push_error("no module build report — run build_tile_forge_modules.py first")
		quit(1)
		return
	for path in [PALETTE_DIR, MODULE_SET_DIR, RECIPE_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))

	_art = _build_art_profile()
	var palettes := _build_palettes()
	var sets := _build_module_sets()
	var recipes := [
		_golden_grass_lush(palettes, sets),
		_golden_soft_pavers(palettes),
		_golden_wood_planks(palettes),
	]
	print("GOLDEN LIBRARY: %d palettes, %d module sets, %d recipes" % [
		palettes.size(), sets.size(), recipes.size()
	])
	quit(0)


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


# --- shared art direction ----------------------------------------------------


func _build_art_profile() -> SumaTileArtProfile:
	var profile := SumaTileArtProfile.new()
	profile.profile_id = "suma_diorama"
	# Bevels in LIVE metres. The brief's 0.035-0.055 was quoted against the
	# 1.70 m authored footprint; 0.036 live is the middle of that band.
	profile.top_bevel = 0.036
	profile.top_bevel_segments = 2
	profile.bottom_bevel = 0.016
	profile.bottom_bevel_segments = 1
	profile.relief_min = 0.022
	profile.relief_max = 0.075
	profile.detail_readable_minimum = 0.11
	profile.hero_scale = 1.18
	profile.support_scale = 0.96
	profile.accent_scale = 0.78
	profile.side_darken = 0.09
	profile.inset_darken = 0.16
	profile.roughness = 0.96
	profile.specular = 0.14
	return _save(
		profile, PALETTE_DIR.path_join("suma_tile_art_profile.tres")
	) as SumaTileArtProfile


func _palette(id: String, top: String, second: String, shadow: String,
		detail_a: String, detail_b: String) -> TilePalette:
	var palette := TilePalette.new()
	palette.palette_id = id
	palette.display_name = id.capitalize()
	palette.top_primary = top
	palette.top_secondary = second
	# Accent, side, underside, and inset are all DERIVED from the top at bake
	# time, so the family can never drift apart in value or hue. The keys here
	# are only the fallback when derivation is switched off.
	palette.accent = top
	palette.shadow = shadow
	palette.side = top
	palette.underside = top
	palette.inset = shadow
	palette.detail_a = detail_a
	palette.detail_b = detail_b
	palette.detail_c = ""
	palette.derive_side_from_top = true
	palette.derive_rim_from_top = true
	palette.rim_lighten = 0.10
	return _save(palette, PALETTE_DIR.path_join("pal_%s.tres" % id)) as TilePalette


func _build_palettes() -> Dictionary:
	return {
		# Two restrained mossy greens, never a sharp neon green.
		"grass": _palette(
			"golden_grass",
			"grass_primary", "grass_secondary", "grass_shade",
			"grass_lush", "moss_primary"
		),
		"paving": _palette(
			"golden_paving",
			"stone_mid", "stone_mid_light", "stone_shadow",
			"stone_light", "stone_mid_light"
		),
		"wood": _palette(
			"golden_wood",
			"wood_gold", "wood_primary", "wood_warm_shadow",
			"wood_light", "wood_primary"
		),
	}


# --- module sets -------------------------------------------------------------


func _entry(module_id: String, sink: float) -> TileModuleEntry:
	var record: Dictionary = _modules.get(module_id, {})
	if record.is_empty():
		push_error("unknown module '%s'" % module_id)
		return null
	var entry := TileModuleEntry.new()
	entry.mesh_path = String(record["path"])
	entry.footprint_radius = float(record["footprint_radius"])
	entry.height = float(record["height"])
	entry.sink = sink
	entry.tags = PackedStringArray([String(record["family"])])
	# The narrow, approved variation band the brief asks for: a seed picks
	# between authored decisions, it does not invent art direction.
	entry.scale_range = Vector2(0.92, 1.12)
	entry.max_tilt_deg = 5.0
	return entry


func _module_set(set_id: String, family: String, ids: Array,
		separation: float, repeats: int, sink: float) -> TileModuleSet:
	var result := TileModuleSet.new()
	result.set_id = set_id
	result.display_name = set_id.capitalize()
	result.family = family
	result.separation_scale = separation
	result.max_repeats_per_module = repeats
	var entries: Array[TileModuleEntry] = []
	for index in ids.size():
		var entry := _entry(String(ids[index]), sink)
		if entry != null:
			entry.weight = [1.0, 0.85, 0.7, 0.6, 0.5, 0.42][mini(index, 5)]
			entries.append(entry)
	result.modules = entries
	return _save(result, MODULE_SET_DIR.path_join("set_%s.tres" % set_id)) as TileModuleSet


func _build_module_sets() -> Dictionary:
	return {
		"clumps": _module_set(
			"golden_grass_clumps", "grass",
			["gf_clump_hero_a", "gf_clump_hero_b", "gf_clump_mid_a",
			 "gf_clump_mid_b", "gf_clump_small_a", "gf_clump_small_b"],
			0.7, 2, 0.014
		),
		"moss": _module_set(
			"golden_moss", "grass",
			["gf_moss_a", "gf_moss_b", "gf_moss_c"],
			1.0, 2, 0.010
		),
	}


# --- recipe helpers ----------------------------------------------------------


func _shape(kind: TileForgeConstants.Shape, cx: float, cy: float,
		ex: float, ey: float, height: float, rotation := 0.0,
		softness := 0.6) -> TileShapePrimitive:
	var shape := TileShapePrimitive.new()
	shape.shape = kind
	shape.center = Vector2(cx, cy)
	shape.extents = Vector2(ex, ey)
	shape.height = height
	shape.rotation_deg = rotation
	shape.softness = softness
	return shape


func _recipe(tile_id: String, display_name: String,
		category: TileForgeConstants.Category, tags: Array,
		palette: TilePalette, base_mode: TileForgeConstants.BaseMode,
		seed_value: int) -> TileRecipe:
	var recipe := TileRecipe.new()
	recipe.tile_id = tile_id
	recipe.display_name = display_name
	recipe.category = category
	recipe.tags = PackedStringArray(tags)
	recipe.palette = palette
	recipe.art_profile = _art
	var profile := TileBaseProfile.new()
	profile.mode = base_mode
	profile.seam_y = profile.canonical_seam()
	# The Forge owns the whole block for a golden tile, so it can chamfer the
	# bottom edge as well as the top. A shared base cannot be re-bevelled.
	profile.generate_side_wall = true
	profile.generate_underside = false
	recipe.base_profile = profile
	recipe.seed_value = seed_value
	return recipe


func _write(recipe: TileRecipe) -> TileRecipe:
	return _save(recipe, RECIPE_DIR.path_join("%s.tres" % recipe.tile_id)) as TileRecipe


# --- 1. golden_grass_lush ----------------------------------------------------


## A gently sculpted green top carrying one hero clump, two supports, and a few
## accents, with a clear resting area left open. Everything the brief asks a
## lush tile to be, and nothing else.
func _golden_grass_lush(palettes: Dictionary, sets: Dictionary) -> TileRecipe:
	var recipe := _recipe(
		"golden_grass_lush", "Lush Meadow",
		TileForgeConstants.Category.SURFACE_WITH_DETAILS,
		["grass", "meadow"],
		palettes["grass"], TileForgeConstants.BaseMode.GENERATED, 4181
	)
	# Three macro forms, each spanning most of the tile: a broad rise, a second
	# lower swell, and one shallow bowl that reads as the resting area.
	var shapes: Array[TileShapePrimitive] = [
		_shape(TileForgeConstants.Shape.BROAD_MOUND, -0.26, -0.18, 0.86, 0.78, 0.046),
		_shape(TileForgeConstants.Shape.BROAD_MOUND, 0.44, 0.34, 0.66, 0.62, 0.030),
		_shape(TileForgeConstants.Shape.DEPRESSION, 0.30, -0.44, 0.58, 0.52, 0.022),
	]
	var layer := TileSurfaceLayer.new()
	layer.generator_id = "heightfield_surface"
	layer.layer_name = "meadow_top"
	layer.material_slot = TileForgeConstants.SLOT_TOP_PRIMARY
	layer.resolution = 9
	layer.shapes = shapes
	layer.edge_lock_width = 0.22
	layer.smooth_shading = true
	recipe.surface_layers = [layer]

	# One hero, two supports, a couple of accents — and an empty quadrant.
	var composition := TileCompositionPattern.new()
	composition.pattern = TileForgeConstants.Composition.ONE_HERO_TWO_SUPPORT
	composition.border_margin = 0.20
	composition.clustering = 0.55
	composition.empty_space_target = 0.26
	composition.jitter = 0.08

	var clumps := TileDetailRule.new()
	clumps.rule_name = "clumps"
	clumps.generator_id = "clump_field"
	clumps.module_set = sets["clumps"]
	clumps.composition = composition
	clumps.min_count = 7
	clumps.max_count = 9
	clumps.seed_offset = 11
	clumps.scale_range = Vector2(0.95, 1.12)
	clumps.min_separation = -0.055
	clumps.permit_intersection = true
	clumps.border_exclusion = 0.035
	clumps.max_tilt_deg = 4.0
	clumps.material_variant_weights = PackedFloat32Array([1.0, 0.42, 0.0])

	# Two moss cushions filling the low ground: supporting mass, not detail.
	var moss_pattern := TileCompositionPattern.new()
	moss_pattern.pattern = TileForgeConstants.Composition.EDGE_CLUSTER_WITH_OPEN_CENTRE
	moss_pattern.border_margin = 0.24
	moss_pattern.empty_space_target = 0.40
	moss_pattern.jitter = 0.1

	var moss := TileDetailRule.new()
	moss.rule_name = "moss"
	moss.generator_id = "clump_field"
	moss.module_set = sets["moss"]
	moss.composition = moss_pattern
	moss.min_count = 2
	moss.max_count = 3
	moss.seed_offset = 37
	moss.scale_range = Vector2(1.0, 1.25)
	moss.min_separation = -0.02
	moss.border_exclusion = 0.05
	moss.material_variant_weights = PackedFloat32Array([0.35, 1.0, 0.0])

	recipe.detail_rules = [clumps, moss]
	recipe.collision_mode = TileForgeConstants.CollisionMode.FROM_HEIGHTFIELD_MEDIAN
	recipe.preview_notes = (
		"Hero clump, two supports, moss on the low side, one clear resting area."
	)
	return _write(recipe)


# --- 2. golden_soft_pavers ---------------------------------------------------


## Four broad paving slabs from the Blender library, raised above a shallow
## bed, with real seams. The tile reads as a constructed surface, not as blocks
## dropped onto dirt.
func _golden_soft_pavers(palettes: Dictionary) -> TileRecipe:
	var recipe := _recipe(
		"golden_soft_pavers", "Soft Pavers",
		TileForgeConstants.Category.CONSTRUCTED_SURFACE,
		["stone", "constructed"],
		palettes["paving"], TileForgeConstants.BaseMode.GENERATED, 5240
	)
	# A shallow bed under the slabs so the seams read as joints in a surface
	# rather than as gaps showing the void.
	var bed := TileSurfaceLayer.new()
	bed.generator_id = "flat_surface"
	bed.layer_name = "bed"
	bed.material_slot = TileForgeConstants.SLOT_SHADOW
	bed.resolution = 2
	bed.height_bias = -0.028
	bed.smooth_shading = false
	bed.border_policy = TileForgeConstants.BorderPolicy.EDGE_LOCK
	bed.edge_lock_height = -0.028
	bed.edge_lock_width = 0.02

	var slabs := TileSurfaceLayer.new()
	slabs.generator_id = "module_layout"
	slabs.layer_name = "slabs"
	slabs.material_slot = TileForgeConstants.SLOT_TOP_PRIMARY
	slabs.secondary_slot = TileForgeConstants.SLOT_TOP_SECONDARY
	slabs.smooth_shading = false
	slabs.params = {
		"layout": "paver_quad",
		"seam": 0.030,
		# Slab tops land ~0.030 above the walk plane: inside the brief's
		# 0.035-0.07 authored band once converted to live metres.
		"lift": -0.028,
		"height_variation": 0.0025,
		"yaw_variation": 0.0,
		"colour_variation": 0.35,
	}
	recipe.surface_layers = [bed, slabs]
	recipe.connection_mode = "tiny_individual_seam"
	recipe.collision_mode = TileForgeConstants.CollisionMode.FLAT_BOX
	recipe.walk_surface_height = 0.03
	recipe.preview_notes = "Four curated slabs, 30 mm seams, chamfered rims."
	return _write(recipe)


# --- 3. golden_wood_planks ---------------------------------------------------


## Three broad boards filling the cell, with a shallow shadow gap between them
## and a warm two-tone variation. No thin strips, no extruded bars.
func _golden_wood_planks(palettes: Dictionary) -> TileRecipe:
	var recipe := _recipe(
		"golden_wood_planks", "Plank Deck",
		TileForgeConstants.Category.CONSTRUCTED_SURFACE,
		["wood", "constructed"],
		palettes["wood"], TileForgeConstants.BaseMode.GENERATED, 6355
	)
	var bed := TileSurfaceLayer.new()
	bed.generator_id = "flat_surface"
	bed.layer_name = "joists"
	bed.material_slot = TileForgeConstants.SLOT_SHADOW
	bed.resolution = 2
	bed.height_bias = -0.034
	bed.smooth_shading = false
	bed.border_policy = TileForgeConstants.BorderPolicy.EDGE_LOCK
	bed.edge_lock_height = -0.034
	bed.edge_lock_width = 0.02

	var boards := TileSurfaceLayer.new()
	boards.generator_id = "module_layout"
	boards.layer_name = "deck"
	boards.material_slot = TileForgeConstants.SLOT_TOP_PRIMARY
	boards.secondary_slot = TileForgeConstants.SLOT_TOP_SECONDARY
	boards.smooth_shading = false
	boards.params = {
		"layout": "board_three",
		"seam": 0.026,
		"lift": -0.034,
		"height_variation": 0.003,
		"yaw_variation": 0.0,
		"colour_variation": 0.42,
	}
	recipe.surface_layers = [bed, boards]
	recipe.connection_mode = "tiny_individual_seam"
	recipe.collision_mode = TileForgeConstants.CollisionMode.FLAT_BOX
	recipe.walk_surface_height = 0.028
	recipe.preview_notes = "Three broad boards, shallow gaps, warm two-tone."
	return _write(recipe)
