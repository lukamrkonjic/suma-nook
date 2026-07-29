extends SceneTree
## Headless validation suite. Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/test_runner.gd
## Must print "ALL TESTS PASSED".

var failures: PackedStringArray = []
var assertions := 0
const GameContentCatalogScript := preload("res://scripts/core/game_content_catalog.gd")
const CurrentSaveValidatorScript := preload(
	"res://scripts/systems/current_save_validator.gd"
)


func _init() -> void:
	_run()
	if failures.is_empty():
		print("ALL TESTS PASSED — %d assertions" % assertions)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		print("TESTS FAILED — %d failures / %d assertions" % [failures.size(), assertions])
		quit(1)


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func fresh_core(seed_value := 12345) -> GameCore:
	var core := GameCore.new()
	core.setup("res://data", seed_value)
	core.save_manager.save_path = "user://test_save.json"
	core.save_manager.backup_path = "user://test_save.json.backup"
	var profile := PlayerProfile.new()
	profile.display_name = "Testkeeper"
	core.new_game(profile)
	return core


func _run() -> void:
	_test_input_bindings()
	_test_registries()
	_test_content_catalog_architecture()
	_test_build_library_categories()
	_test_content_assets()
	_test_tile_slot_fill()
	_test_catalog_expansion()
	_test_gg_render_contract()
	_test_game_preferences()
	_test_starting_world()
	_test_xp_only_hobbies()
	_test_hobby_journal_and_direct_rewards()
	_test_out_of_scope_systems_disabled()
	_test_arrival_and_parcel_loop()
	_test_arrival_queue_invariants()
	_test_xp_and_unlocks()
	_test_deterministic_rng()
	_test_parcels_choice_and_duplicates()
	_test_new_tile_pity()
	_test_tile_adjacency_overlap_rotation()
	_test_elevation_stacking()
	_test_connectivity_and_relocation()
	_test_sockets_and_overlap_prevention()
	_test_object_support_graph()
	_test_camping_feature_contract()
	_test_anchor_cycle_and_regen()
	_test_crafting_transactions()
	_test_equipment()
	_test_landmark_lifecycle()
	_test_guardian_idempotency()
	_test_pack_and_salvage()
	_test_deed_replacement()
	_test_rework_save_round_trip()
	_test_current_save_policy()
	_test_interrupted_reveal_recovery()
	_test_player_defeat_safety()


func _test_input_bindings() -> void:
	check(_action_has_key("move_up", KEY_W), "W remains bound to character movement")
	check(_action_has_key("move_left", KEY_A), "A remains bound to character movement")
	check(not _action_has_key("move_up", KEY_UP), "up arrow no longer moves the character")
	check(not _action_has_key("move_left", KEY_LEFT), "left arrow no longer moves the character")
	check(_action_has_key("camera_rotate_right", KEY_LEFT), "left arrow uses the reversed camera spin")
	check(_action_has_key("camera_rotate_left", KEY_RIGHT), "right arrow uses the reversed camera spin")
	check(_action_has_key("camera_zoom_in", KEY_UP), "up arrow zooms the camera in")
	check(_action_has_key("camera_zoom_out", KEY_DOWN), "down arrow zooms the camera out")
	check(_action_has_key("cancel", KEY_ESCAPE), "Escape opens and closes the pause flow")


func _action_has_key(action: StringName, physical_keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event != null and key_event.physical_keycode == physical_keycode:
			return true
	return false


func _test_registries() -> void:
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "all data files load and cross-validate: " + ", ".join(regs.load_errors))
	check(regs.skills.size() == 3, "three skills defined")
	check(regs.tiles.size() >= 15, "at least 15 tile variants")
	check(regs.skill("mining").future, "mining is a future (data-only) skill")
	check(not regs.feature("combat_enabled"), "combat is disabled")
	check(regs.feature("ferry_arrivals_enabled"), "periodic arrivals are enabled")
	check(
		is_equal_approx(regs.tunef("tile_size", 0.0), 1.35)
		and is_equal_approx(regs.tunef("block_depth", 0.0), 0.5),
		"tile dimensions use the GG-like 1.35 m footprint and audited 0.50 m stacking step"
	)
	check(
		regs.tile("tile_open_water").render_profile == "continuous_water"
		and regs.tile("tile_open_water").collision_profile == "none",
		"open water presentation is selected by behavior profiles"
	)
	check(
		regs.tile("tile_grass_pond_edge").collision_profile == "pond_basin",
		"pond collision is selected by its definition instead of a renderer id check"
	)
	check(
		regs.tile("tile_grass").surface_detail_profile == "grass_speckles",
		"Open Meadow opts into coverable raised grass speckles"
	)
	check(
		regs.structure("struct_dock").collision_profile == "walkable_surface",
		"the dock is classified as a walkable surface rather than a solid object blocker"
	)
	check(
		regs.structure("struct_dock").grid_fit_profile == "tile_span",
		"the dock opts into live-grid footprint fitting"
	)
	var fishing := regs.skill("fishing")
	check(fishing.xp_to_next(1) > 0 and fishing.xp_to_next(2) > fishing.xp_to_next(1), "xp curve increases")


func _test_content_catalog_architecture() -> void:
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "catalog snapshot loads before atomic reload test")
	var expected_kinds := [
		"skills", "items", "tiles", "structures", "recipes", "loot_tables",
		"parcels", "anchors", "capabilities", "enemies", "landmarks",
	]
	check(
		regs.definition_kinds() == expected_kinds,
		"one global catalog lifecycle covers every current definition family"
	)
	var global_count := 0
	for kind: String in regs.definition_kinds():
		var family: Dictionary = regs.definitions(kind)
		check(not family.is_empty(), "%s participates in the global catalog" % kind)
		for content_id: String in family:
			global_count += 1
			check(
				regs.definition(kind, content_id) == family[content_id]
				and regs.definition_source(kind, content_id) != null
				and regs.definition_traits(kind, content_id) != null,
				"%s/%s has typed data, provenance, and common traits"
				% [kind, content_id]
			)
	check(global_count > 0, "every shipped definition uses the global contract")
	check(
		regs.definition_has_tag("items", "fish_dawnfin", "fish"),
		"item tags are available through the global definition API"
	)
	check(
		regs.definition_has_capability(
			"structures", "struct_high_tent", "shelter"
		)
		and int(regs.definition_capability(
			"structures", "struct_high_tent", "shelter"
		).get("capacity", 0)) == 2,
		"capabilities use the same global API rather than a tent-only registry"
	)
	var original_snapshot: Variant = regs.snapshot
	var original_tile_count := regs.tiles.size()
	var source: Variant = regs.definition_source("structures", "struct_bench")
	check(source != null, "definitions retain source provenance")
	check(
		source.path.ends_with("structures.json") and source.content_id == "struct_bench",
		"definition provenance identifies its exact file and stable id"
	)
	check(
		not regs.reload_all_atomic("user://definitely_missing_suma_catalog", false),
		"invalid development reload is rejected"
	)
	check(
		regs.snapshot == original_snapshot and regs.tiles.size() == original_tile_count,
		"failed reload preserves the previously published immutable catalog"
	)
	check(
		not regs.load_issues.is_empty()
		and String(regs.load_errors[0]).contains("definitely_missing_suma_catalog"),
		"structured reload failures report the source path"
	)


func _test_build_library_categories() -> void:
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "build-library category registry loads")
	var expected_tiles := {
		"tile_open_water": "ground",
		"tile_grass": "ground",
		"tile_plain_ground": "ground",
		"tile_grass_flower": "ground",
		"tile_grass_pond_edge": "ground",
		"tile_path": "ground",
		"tile_garden": "ground",
		"tile_courtyard": "ground",
		"tile_dirt": "ground",
		"tile_dirt_road": "ground",
		"tile_dirt_crossroad": "ground",
		"tile_mud": "ground",
		"tile_sand": "ground",
		"tile_clay": "ground",
		"tile_grove_mature": "woodland",
		"tile_grove_birch": "woodland",
		"tile_grove_mossy": "woodland",
		"tile_grove_autumn": "woodland",
		"tile_grove_flowering": "woodland",
		"tile_stone_clearing": "stone",
		"tile_stone_mossy": "stone",
		"tile_stone_ruin": "stone",
		"tile_stone_crystal": "stone",
		"tile_stone_road": "stone",
		"tile_cobblestone": "stone",
		"tile_flagstone": "stone",
		"tile_snowfield": "winter",
		"tile_snow_drift": "winter",
		"tile_snow_path": "winter",
		"tile_frosted_stone": "winter",
	}
	for tile_id: String in expected_tiles:
		check(
			Hud.category_for_tile(regs.tile(tile_id)) == expected_tiles[tile_id],
			"%s appears in the expected build-library terrain category" % tile_id
		)

	var expected_structures := {
		"struct_bench": "furniture",
		"struct_stool": "furniture",
		"struct_table": "furniture",
		"struct_fence": "boundaries",
		"struct_gate": "boundaries",
		"struct_lantern": "utilities",
		"struct_campfire": "utilities",
		"struct_firepit_polished": "utilities",
		"struct_high_tent": "buildings",
		"struct_planter": "nature",
		"struct_pot": "nature",
		"struct_chest": "storage",
		"struct_box": "storage",
		"struct_dock": "buildings",
		"struct_sign": "boundaries",
		"struct_ruin_arch": "buildings",
		"struct_stone_wall": "boundaries",
		"struct_stone_wall_polished": "boundaries",
		"struct_fishing_marker": "utilities",
		"struct_pine": "nature",
		"struct_pine_tall": "nature",
		"struct_pine_young": "nature",
		"struct_bush": "nature",
		"struct_stone_wall_low": "boundaries",
		"struct_stone_wall_corner": "boundaries",
		"struct_stone_pillar": "boundaries",
		"struct_stone_well": "utilities",
		"struct_stone_bench": "furniture",
		"struct_birdbath": "nature",
		"struct_watering_can": "utilities",
		"struct_barrel": "storage",
		"struct_crate": "storage",
		"struct_wheelbarrow": "utilities",
		"struct_log_pile": "storage",
		"struct_wooden_arch": "buildings",
		"struct_milk_churn": "storage",
		"struct_garden_trellis": "boundaries",
		"struct_snowman": "nature",
		"struct_water_wheel": "buildings",
	}
	for structure_id: String in expected_structures:
		check(
			Hud.category_for_structure(regs.structure(structure_id))
			== expected_structures[structure_id],
			"%s appears in the expected build-library object category" % structure_id
		)


## The slot-fill contract — the root guarantee behind "no seams ever": every
## land tile's structural shell (its `*_body`/`*_cap` meshes) fills EXACTLY
## one tile slot — precisely TILE wide on both axes, from the -0.50 block
## bottom to the y=0 walkable plane, with a full-footprint, full-depth body.
## Anything narrower opens see-through cracks to water or sky behind;
## anything wider or deeper bleeds into neighbouring slots. Decorative
## relief may float inside the slot, but the shell must fill it.
func _test_tile_slot_fill() -> void:
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "slot-fill contract registry loads")
	const HALF := 0.85
	const EPS := 0.005
	const GEOMETRY_PROFILES := [
		"hard_square", "micro_bevel_square", "soft_recessed_top",
		"rounded_corner_slab", "stepped_platform", "constructed_material",
		"organic_overlay_square", "connected_water",
	]
	const CONNECTION_MODES := [
		"full_flush", "tiny_individual_seam", "soft_isolated", "merged_surface",
	]
	for tile_id in regs.tiles:
		var def: Defs.TileDefinition = regs.tiles[tile_id]
		check(
			def.geometry_profile in GEOMETRY_PROFILES,
			"tile %s declares a known geometry profile (got '%s')" % [tile_id, def.geometry_profile]
		)
		check(
			def.connection_mode in CONNECTION_MODES,
			"tile %s declares a known connection mode (got '%s')" % [tile_id, def.connection_mode]
		)
		check(
			def.geometry_profile != "connected_water" or def.surface_kind == "water",
			"tile %s only uses the connected water profile on a water surface" % tile_id
		)
		check(
			def.exposed_top in ["flush", "recessed", "raised"],
			"tile %s declares a known exposed-top kind (got '%s')" % [tile_id, def.exposed_top]
		)
		if def.surface_kind == "water":
			continue
		var scene := _tile_scene(def.asset_id)
		check(scene != null, "tile %s resolves a GLB for slot validation" % tile_id)
		if scene == null:
			continue
		var root := scene.instantiate()
		var shell := AABB()
		var has_shell := false
		var has_filler := false
		for found in root.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := found as MeshInstance3D
			var lower := String(mesh_instance.name).to_lower()
			if not (lower.ends_with("_body") or lower.ends_with("_cap")):
				continue
			var relative := Transform3D.IDENTITY
			var cursor: Node3D = mesh_instance
			while cursor != null and cursor != root:
				relative = cursor.transform * relative
				cursor = cursor.get_parent() as Node3D
			var bounds: AABB = relative * mesh_instance.get_aabb()
			shell = bounds if not has_shell else shell.merge(bounds)
			has_shell = true
			# A slot filler: one structural mesh whose own footprint is the
			# full cell AND that reaches the block bottom — a wide cap over a
			# narrow body would merge to a passing AABB while leaving open
			# flanks below cap level, so the guarantee must come from a
			# single mesh.
			if (
				bounds.size.x >= TILE_SLOT - EPS and bounds.size.z >= TILE_SLOT - EPS
				and bounds.position.y <= -0.5 + EPS
			):
				has_filler = true
		root.free()
		check(has_shell, "tile %s has structural _body/_cap meshes" % tile_id)
		if not has_shell:
			continue
		check(
			absf(shell.position.x + HALF) <= EPS and absf(shell.end.x - HALF) <= EPS
			and absf(shell.position.z + HALF) <= EPS and absf(shell.end.z - HALF) <= EPS,
			"tile %s shell spans exactly one slot footprint (got x %.3f..%.3f, z %.3f..%.3f)"
			% [tile_id, shell.position.x, shell.end.x, shell.position.z, shell.end.z]
		)
		# The exposed top's vertical freedom depends on its declared kind; the
		# COVERED form is always exact because the runtime swaps the whole top
		# layer for a flush infill lid over the (validated) full-depth filler.
		var top_ok := false
		match def.exposed_top:
			"recessed":
				top_ok = shell.end.y >= -0.12 - EPS and shell.end.y <= EPS
			"raised":
				top_ok = shell.end.y >= -EPS and shell.end.y <= 0.35 + EPS
			_:
				top_ok = absf(shell.end.y) <= EPS
		check(
			absf(shell.position.y + 0.5) <= EPS and top_ok,
			"tile %s shell spans block bottom to its declared %s top (got y %.3f..%.3f)"
			% [tile_id, def.exposed_top, shell.position.y, shell.end.y]
		)
		check(
			has_filler,
			"tile %s has a full-footprint structural mesh flush to the block bottom" % tile_id
		)


const TILE_SLOT := 1.70
const _TILE_GLB_PATHS := [
	"res://assets/3d/reworked/%s.glb",
	"res://assets/3d/final/%s.glb",
	"res://assets/3d/proxies/%s.glb",
]


func _tile_scene(asset_id: String) -> PackedScene:
	for path_template in _TILE_GLB_PATHS:
		var path: String = String(path_template) % asset_id
		if ResourceLoader.exists(path):
			return load(path) as PackedScene
	return null


func _test_content_assets() -> void:
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "content asset validation registry loads")
	var errors := ContentValidator.validate(regs)
	check(errors.is_empty(), "every production definition resolves its visual asset: " + ", ".join(errors))


func _test_catalog_expansion() -> void:
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "expanded catalog loads before focused contract checks")
	var winter_tiles := [
		"tile_snowfield",
		"tile_snow_drift",
		"tile_snow_path",
		"tile_frosted_stone",
	]
	for tile_id: String in winter_tiles:
		var tile := regs.tile(tile_id)
		check(
			tile != null and tile.family == "winter"
			and tile.stackable and tile.supports_tiles and tile.surface_kind == "flat",
			"%s remains a modular flat winter tile" % tile_id
		)
	var earth_and_stone_tiles := [
		"tile_dirt",
		"tile_dirt_road",
		"tile_dirt_crossroad",
		"tile_mud",
		"tile_sand",
		"tile_clay",
		"tile_cobblestone",
		"tile_flagstone",
	]
	for tile_id: String in earth_and_stone_tiles:
		var tile := regs.tile(tile_id)
		check(
			tile != null and tile.stackable and tile.supports_tiles,
			"%s participates in the global tile stacking contract" % tile_id
		)
	check(
		regs.item("parcel_winter") != null
		and regs.parcel("parcel_winter") != null
		and regs.recipe("recipe_winter_parcel") != null,
		"winter terrain is obtainable through a registered parcel and recipe"
	)
	var watering_can := regs.structure("struct_watering_can")
	check(
		watering_can.can_be_stacked
		and watering_can.placement_tags.has("small_surface_item")
		and watering_can.placement_tags.has("tabletop_item"),
		"watering can can sit on compatible stools, benches, tables, and containers"
	)
	for structure_id in [
		"struct_stone_wall_low",
		"struct_stone_wall_corner",
		"struct_stone_pillar",
	]:
		check(
			regs.structure(structure_id).blocks_movement,
			"%s participates in object collision" % structure_id
		)
	var wheel := regs.structure("struct_water_wheel")
	check(
		wheel.allowed_surface_kinds == ["water"]
		and wheel.has_capability("ambient_motion")
		and wheel.grid_fit_profile == "tile_span",
		"waterside wheel is water-only, grid-fitted, and data-animated"
	)
	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	var wheel_visual := assets.instantiate("prop_water_wheel")
	check(
		wheel_visual.find_child("WaterWheelRotor", true, false) is Node3D,
		"water-wheel GLB preserves the named runtime rotor hierarchy"
	)
	var motion_root := Node3D.new()
	var rotor := Node3D.new()
	rotor.name = "Rotor"
	motion_root.add_child(rotor)
	var motion := AmbientMotion.new()
	check(
		motion.configure(motion_root, {"node": "Rotor", "axis": "z", "speed": 1.0}),
		"generic ambient motion resolves a data-named authored node"
	)
	var before := rotor.quaternion
	motion._process(0.5)
	check(
		not rotor.quaternion.is_equal_approx(before),
		"generic ambient motion advances the target transform"
	)
	wheel_visual.free()
	motion.free()
	motion_root.free()


func _test_gg_render_contract() -> void:
	var profile := load("res://assets/visual_profiles/suma_soft_daylight_warm.tres") as VisualStyleProfile
	check(profile != null, "Suma soft-daylight visual profile loads")
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "render-contract tuning registry loads")
	check(
		regs.tunef("camera_min_size", 40.0) <= 14.0
		and regs.tunef("camera_default_size", 40.0) == 32.0,
		"camera supports a deep close-up with the closer default composition"
	)
	check(
		profile.shadow_max_distance >= 75.0,
		"Soft-daylight shadow range covers the complete gameplay camera envelope"
	)
	check(
		profile.shadow_opacity >= 0.65 and profile.shadow_opacity <= 0.75
		and profile.shadow_normal_bias >= 1.0
		and profile.shadow_cascade_mode == "pssm_4",
		"Soft-daylight shadows keep the miniature grounded with GG-like plane separation"
	)
	check(
		profile.ssao_enabled and profile.ssao_intensity >= 0.8 and profile.ssao_radius <= 0.3,
		"Soft-daylight SSAO is tight and contact-focused"
	)
	check(
		profile.tonemap == "agx"
		and profile.agx_white >= 12.0
		and profile.agx_white <= 16.0
		and profile.contrast <= 1.06
		and profile.glow_enabled
		and profile.glow_hdr_threshold >= 1.6,
		"Soft-daylight uses a restrained pop grade and emissive-only bloom"
	)
	check(
		ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d") == 2
		and ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa") == 1
		and not ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa")
		and ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size") == 4096,
		"Soft-daylight uses balanced 4x MSAA and a bounded shadow map"
	)


func _test_game_preferences() -> void:
	var preferences := GamePreferences.new()
	preferences.from_dict({
		"fullscreen": true,
		"vsync": false,
		"anti_aliasing": GamePreferences.AA_BALANCED,
		"ssao": false,
		"bloom": false,
		"master_volume": 0.35,
		"music_volume": 0.2,
		"tutorial_hints": false,
	})
	var saved := preferences.to_dict()
	check(
		saved["fullscreen"] and not saved["vsync"]
		and saved["anti_aliasing"] == GamePreferences.AA_BALANCED,
		"display and anti-aliasing preferences round-trip"
	)
	check(
		not saved["ssao"] and not saved["bloom"]
		and is_equal_approx(saved["master_volume"], 0.35)
		and is_equal_approx(saved["music_volume"], 0.2),
		"post-processing and audio preferences round-trip"
	)
	check(not saved["tutorial_hints"], "tutorial visibility preference round-trips")
	preferences.from_dict({"anti_aliasing": "not-a-quality", "master_volume": 4.0})
	check(
		preferences.anti_aliasing == GamePreferences.AA_BALANCED
		and preferences.master_volume == 1.0,
		"invalid preference values fall back safely"
	)


func _test_starting_world() -> void:
	var core := fresh_core()
	check(core.grid.cells.size() == 9, "fresh save starts with exactly nine cells")
	var water: Array[Vector2i] = []
	var walkable := 0
	for coord: Vector2i in core.grid.cells:
		if core.grid.tile_def(coord).id == "tile_open_water":
			water.append(coord)
		if core.grid.is_walkable(coord):
			walkable += 1
	check(water.size() == 3, "starting world has exactly three water cells")
	check(water.has(Vector2i(-1, -1)) and water.has(Vector2i(0, -1)) and water.has(Vector2i(1, -1)), "water occupies the northern/top row")
	check(walkable == 6, "the other six starting cells are walkable land")
	check(water[0].distance_squared_to(water[1]) <= 4 and water[1].distance_squared_to(water[2]) <= 4, "the water cells form one connected edge")
	for y in [0, 1]:
		check(
			core.grid.tile_def(Vector2i(-1, y)).id == "tile_grass"
			and core.grid.tile_def(Vector2i(0, y)).id == "tile_plain_ground"
			and core.grid.tile_def(Vector2i(1, y)).id == "tile_grass",
			"opening land row %d is forest / path / forest" % y
		)
	var locked: Array[Vector2i] = []
	for coord: Vector2i in core.grid.cells:
		if core.grid.cell(coord).movement_locked:
			locked.append(coord)
	check(
		locked == [GameCore.FIRST_WATER_COORD],
		"only the first water tile is movement-locked"
	)
	for coord: Vector2i in core.grid.cells:
		check(
			core.grid.cell(coord).structures.size() <= 1,
			"opening tile %s has at most one independently placeable object" % coord
		)
	var placed_tree_count := 0
	var chest_count := 0
	for slot: Dictionary in core.grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			var definition := core.registries.structure(structure.structure_id)
			if definition != null and definition.anchor_id == "grove_anchor":
				placed_tree_count += 1
			if (
				definition != null
				and definition.has_capability("storage_access")
				and slot["coord"] == Vector2i(1, 0)
			):
				chest_count += 1
	check(placed_tree_count == 0, "fresh worlds do not pre-place any trees")
	check(chest_count == 1, "the inventory chest starts as one independent object")
	check(core.stock.structure_count("struct_pine") == 1, "the starter tree waits in build stock")
	check(
		core.stock.structure_count("struct_stone_wall_polished") == 1,
		"the polished stone wall is immediately discoverable in build stock"
	)
	check(
		core.stock.structure_count("struct_firepit_polished") == 1,
		"the polished firepit is immediately discoverable in build stock"
	)
	for tile_id: String in [
		"tile_grove_mature",
		"tile_grove_birch",
		"tile_grove_mossy",
		"tile_grove_autumn",
		"tile_grove_flowering",
	]:
		check(core.registries.tile(tile_id).anchor_id == "", "%s is cosmetic terrain only" % tile_id)
	for tree_id: String in ["struct_pine", "struct_pine_tall", "struct_pine_young"]:
		check(
			core.registries.structure(tree_id).anchor_id == "grove_anchor",
			"%s independently owns Woodland Tending" % tree_id
		)
	check(core.grid.is_walkable(Vector2i.ZERO), "home cell walkable")
	check(core.grid.world_to_cell(core.profile.position) == Vector2i.ZERO, "player spawns safely on central land")
	check(core.equipment.owns("tool_rod_basic"), "starter rod owned")


func _test_xp_only_hobbies() -> void:
	var core := fresh_core(404)
	var inventory_before := core.inventory.counts.duplicate()
	for hobby_id in ["fishing", "woodcutting"]:
		var skill := core.registries.skill(hobby_id)
		var old_chance := skill.direct_tile_reward_chance
		skill.direct_tile_reward_chance = 0.0
		var result := core.rewards.resolve_hobby_action(skill)
		core.skills.record_action(hobby_id)
		core.skills.add_xp(hobby_id, result.xp_awarded)
		check(result.xp_awarded == skill.action_xp, "%s action returns configured XP" % hobby_id)
		check(core.skills.xp_progress(hobby_id)["current"] == skill.action_xp, "%s XP reaches hobby progression" % hobby_id)
		check(not result.has_world_reward(), "ordinary %s action has no forced world reward" % hobby_id)
		skill.direct_tile_reward_chance = old_chance
	check(str(core.inventory.counts) == str(inventory_before), "Fishing and Woodland Tending add no common inventory items")


func _test_hobby_journal_and_direct_rewards() -> void:
	var core := fresh_core(505)
	var fishing := core.registries.skill("fishing")
	core.registries.tuning["fishing_collection_chance"] = 1.0
	var old_entries := fishing.collection_entries.duplicate()
	fishing.collection_entries = ["test_sunfish"] as Array[String]
	var first := core.rewards.resolve_hobby_action(fishing)
	check(first.collection_discovery_id == "test_sunfish", "first-time fish resolves a journal entry")
	check(first.was_new_discovery, "first journal catch is marked new")
	check(core.collection.is_discovered("fish", "test_sunfish"), "journal metadata is recorded")
	check(core.inventory.counts.is_empty(), "journal discovery creates no fish item stack")
	var before_tiles := core.stock.tile_count("tile_open_water")
	var old_chance := fishing.direct_tile_reward_chance
	var old_pool := fishing.direct_tile_reward_pool.duplicate()
	fishing.direct_tile_reward_chance = 1.0
	fishing.direct_tile_reward_pool = ["tile_open_water"] as Array[String]
	var rare := core.rewards.resolve_hobby_action(fishing)
	check(rare.optional_tile_reward_id == "tile_open_water", "rare hobby reward is already a finished tile")
	check(core.stock.tile_count("tile_open_water") == before_tiles + 1, "rare tile enters the Tile Library directly")
	check(core.inventory.counts.is_empty(), "rare world reward bypasses material inventory")
	fishing.collection_entries = old_entries
	fishing.direct_tile_reward_chance = old_chance
	fishing.direct_tile_reward_pool = old_pool


func _test_out_of_scope_systems_disabled() -> void:
	var core := fresh_core()
	check(core.crafting.available_recipes().is_empty(), "material crafting recipes are hidden")
	check(not core.crafting.craft("recipe_meadow_parcel"), "material-to-land crafting is disabled")
	for i in 20:
		core.stock.add_tile("tile_grass")
		var coord := Vector2i(2 + i, 0)
		core.place_tile_from_stock(coord, "tile_grass", 0)
	check(core.landmarks.active.is_empty(), "world growth creates no hostile landmarks")
	check(not core.registries.feature("monsters_enabled"), "monster spawning flag remains disabled")
	check(not core.registries.feature("hostile_landmarks_enabled"), "hostile landmark flag remains disabled")


func _test_arrival_and_parcel_loop() -> void:
	var core := fresh_core(606)
	var requested: Array = []
	core.arrivals.arrival_requested.connect(func(payload): requested.append(payload))
	core.arrivals.time_until_next = 0.01
	core.tick(0.02)
	check(requested.size() == 1, "arrival timer requests exactly one presentation")
	check(core.arrivals.state == ArrivalScheduler.ARRIVING, "arrival enters presentation state")
	var payload := requested[0] as LandParcelPayload
	check(payload.parcel_id == "parcel_wild", "ferry payload is a Land Parcel")
	core.arrivals.mark_delivery_ready(payload)
	check(core.arrivals.has_waiting_package(), "ferry unloads one waiting package")
	var options := core.arrivals.open_waiting(core.parcels)
	check(options.size() == 3, "dock package reveals three tile choices")
	check(core.arrivals.state == ArrivalScheduler.OPENED, "scheduler pauses while parcel choice is open")
	var chosen := core.parcels.choose(0)
	check(chosen == options[0], "selected parcel option is authoritative")
	check(core.stock.tile_count(chosen) == 1, "selected tile enters the Tile Library")
	for index in range(1, options.size()):
		if options[index] != chosen:
			check(core.stock.tile_count(options[index]) == 0, "unselected tile does not enter any inventory")
	core.arrivals.resolve_delivery()
	check(core.arrivals.state == ArrivalScheduler.IDLE, "next timer begins after the choice is stored")
	check(core.arrivals.time_until_next >= 300.0, "later arrival uses configured relaxed timing")


func _test_arrival_queue_invariants() -> void:
	var core := fresh_core(707)
	var requests := [0]
	core.arrivals.arrival_requested.connect(func(_payload): requests[0] += 1)
	check(core.arrivals.trigger_arrival(), "arrival uses the shared scheduler")
	check(requests[0] == 1, "presentation receives one generic request")
	var payload := core.arrivals.current_payload
	core.arrivals.mark_delivery_ready(payload)
	check(not core.arrivals.trigger_arrival(), "unopened package blocks delivery accumulation")
	var fishing := core.registries.skill("fishing")
	fishing.direct_tile_reward_chance = 0.0
	core.rewards.resolve_hobby_action(fishing)
	check(core.arrivals.has_waiting_package(), "player can perform a hobby while ferry package waits")
	check(core.arrivals.deliveries_created == 0, "waiting never creates unattended delivery stacks")


func _test_xp_and_unlocks() -> void:
	var core := fresh_core()
	var levels: Array = []
	core.skills.level_up.connect(func(_s, l, _u): levels.append(l))
	var def := core.registries.skill("fishing")
	core.skills.add_xp("fishing", def.xp_to_next(1))
	check(core.skills.level("fishing") == 2, "xp reaching threshold levels up")
	check(levels == [2], "level_up signal fired once")
	check(core.stock.structure_count("struct_bench") == 0, "journal-only level does not create unrelated inventory")
	core.skills.add_xp("fishing", def.xp_to_next(2))
	check(core.stock.structure_count("struct_bench") == 1, "level 3 grants its data-defined bench reward")
	# leveling far unlocks tile pool entries
	core.skills.add_xp("fishing", 100000)
	check(core.skills.level("fishing") == def.max_level, "xp clamps at max level")


func _test_deterministic_rng() -> void:
	var a := fresh_core(777)
	var b := fresh_core(777)
	var seq_a: Array = []
	var seq_b: Array = []
	for i in 12:
		seq_a.append(a.rng.randi_range("determinism_probe", 0, 1_000_000))
		seq_b.append(b.rng.randi_range("determinism_probe", 0, 1_000_000))
	check(str(seq_a) == str(seq_b), "identical seeds produce identical loot sequences")
	var c := fresh_core(778)
	var differs := false
	for i in 12:
		if c.rng.randi_range("determinism_probe", 0, 1_000_000) != seq_a[i]:
			differs = true
	check(differs, "different seeds diverge")


func _test_parcels_choice_and_duplicates() -> void:
	var core := fresh_core()
	core.inventory.grant("parcel_wild", 2, false, true)
	var options := core.parcels.open("parcel_wild")
	check(options.size() == 3, "parcel reveals three options")
	var guaranteed: Array = core.registries.tune("guaranteed_first_parcel_options", [])
	check(str(options) == str(guaranteed), "first-ever parcel offers the guaranteed grove trio")
	var chosen := core.parcels.choose(0)
	check(chosen == options[0], "choose returns the picked tile")
	check(core.stock.tile_count(chosen) == 1, "chosen tile lands in build stock")
	check(core.collection.is_discovered("tiles", chosen), "choice recorded in collection")
	# duplicate → pattern dust
	var before_dust := core.inventory.count("pattern_dust")
	core.parcels.open("parcel_wild")
	core.parcels.pending_options = [chosen, chosen, chosen] as Array[String]
	core.parcels.choose(0)
	check(core.inventory.count("pattern_dust") > before_dust, "duplicate choice converts to Pattern Dust")
	check(core.parcels.duplicate_streak == 1, "duplicate streak advanced")


func _test_new_tile_pity() -> void:
	var core := fresh_core()
	core.parcels.opened_count = 1   # skip tutorial guarantee
	core.parcels.duplicate_streak = core.registries.tunei("new_tile_pity_max_duplicates", 4)
	core.collection.record("tiles", "tile_grass")
	core.inventory.grant("parcel_wild", 1, false, true)
	var options := core.parcels.open("parcel_wild")
	var has_fresh := false
	for tile_id in options:
		if not core.collection.is_discovered("tiles", tile_id):
			has_fresh = true
	check(has_fresh, "duplicate pity forces an undiscovered tile into the reveal")


func _test_tile_adjacency_overlap_rotation() -> void:
	var core := fresh_core()
	check(not core.grid.can_place_tile(Vector2i(5, 5)), "detached placement rejected")
	check(not core.grid.can_place_tile(Vector2i.ZERO), "overlap rejected")
	check(core.grid.can_place_tile(Vector2i(2, 0)), "edge-adjacent placement accepted")
	core.stock.add_tile("tile_grass")
	check(core.place_tile_from_stock(Vector2i(2, 0), "tile_grass", 3), "placement from stock succeeds")
	check(core.grid.cell(Vector2i(2, 0)).rotation == 3, "rotation persists on the placed cell")
	check(not core.place_tile_from_stock(Vector2i(2, 0), "tile_grass", 0), "double placement rejected")
	check(core.stock.tile_count("tile_grass") == 0, "stock consumed exactly once")


func _test_elevation_stacking() -> void:
	var core := fresh_core()
	var coord := Vector2i.ZERO
	var initial_count := core.grid.total_tile_count()
	core.stock.add_tile("tile_grass", 2)
	check(
		core.grid.can_place_tile_at(coord, 1, "tile_grass"),
		"a clear flat tile supports an upper land block"
	)
	check(
		core.place_tile_from_stock(coord, "tile_grass", 1, 1),
		"tile stock can be placed into elevation one"
	)
	check(
		core.grid.top_elevation(coord) == 1
		and core.grid.cell_at(coord, 1).rotation == 1,
		"elevated tile owns an independent layer and rotation"
	)
	check(
		is_equal_approx(core.grid.cell_to_world(coord, 1).y, core.grid.block_depth),
		"elevated holder aligns exactly one authored block depth above its support"
	)
	check(
		core.grid.total_tile_count() == initial_count + 1,
		"placed tile totals include upper layers"
	)
	check(not core.grid.is_walkable(coord), "an unconnected raised column is not used as a ground route")
	check(
		core.grid.has_walkable_top_surface(coord),
		"a raised column still exposes its top to physical jump traversal"
	)
	check(
		core.grid.remove_tile_at(coord, 0) == null,
		"a supporting block cannot be removed from beneath an upper block"
	)

	check(
		core.place_tile_from_stock(coord, "tile_grass", 0, 2),
		"flat upper blocks can form a taller contiguous column"
	)
	check(core.grid.top_elevation(coord) == 2, "column reports its highest occupied level")
	check(
		not core.grid.can_place_structure_at(coord, 0, "struct_lantern")
		and core.grid.free_socket(coord, "decor", 0) < 0
		and core.grid.add_structure(coord, "struct_lantern", 1, 0, 0) == null,
		"covered lower elevations cannot receive objects through any grid API"
	)
	check(
		core.grid.can_place_structure_at(coord, 2, "struct_pot"),
		"small decorations can sit on an elevated block"
	)
	var pot_socket := core.grid.free_socket(coord, "decor", 2)
	var elevated_pot := core.grid.add_structure(coord, "struct_pot", pot_socket, 0, 2)
	check(elevated_pot != null, "elevated decoration receives independent saved state")
	check(
		not core.grid.can_place_tile_at(coord, 3, "tile_grass"),
		"a decorated support rejects a land block that would overlap it"
	)
	check(
		core.registries.tile("tile_grass_flower").stackable
		and core.registries.tile("tile_grass_flower").supports_tiles,
		"ordinary flat tile definitions inherit modular stacking defaults"
	)
	var moved_column := core.grid.detach_tile_stack(coord, 1)
	var column_destination := Vector2i(2, 1)
	core.grid.place_tile(column_destination, "tile_path")
	check(
		moved_column.size() == 2
		and core.grid.restore_tile_stack(column_destination, 1, moved_column),
		"a selected middle tile moves itself and every upper layer atomically"
	)
	check(
		core.grid.top_elevation(column_destination) == 2
		and core.grid.cell_at(column_destination, 2).structures.has(elevated_pot),
		"an atomic tile move retains the complete supported object hierarchy"
	)
	moved_column = core.grid.detach_tile_stack(column_destination, 1)
	check(
		core.grid.restore_tile_stack(coord, 1, moved_column),
		"an atomic tile column can return to its original support"
	)
	core.grid.remove_tile(column_destination)

	var stairs := Defs.TileDefinition.from_dict({
		"id": "tile_test_stairs",
		"name": "Test Stairs",
		"asset_id": "tile_path",
		"stackable": true,
		"supports_tiles": false,
		"supports_decor": true,
		"surface_kind": "stairs",
		"decor_sockets": 2,
	})
	var penny_pig := Defs.StructureDefinition.from_dict({
		"id": "struct_test_penny_pig",
		"name": "Penny Pig",
		"asset_id": "prop_pot",
		"socket_type": "decor",
		"allow_elevated": true,
	})
	core.registries.tiles[stairs.id] = stairs
	core.registries.structures[penny_pig.id] = penny_pig
	var stair_coord := Vector2i(2, 0)
	core.grid.place_tile(stair_coord, stairs.id)
	check(
		not core.grid.can_place_tile_at(stair_coord, 1, "tile_grass"),
		"stairs explicitly reject a tile stacked on their uneven top"
	)
	check(
		core.grid.can_place_structure_at(stair_coord, 0, penny_pig.id),
		"stairs still accept compatible decor such as the penny pig"
	)

	core.registries.tiles.erase(stairs.id)
	core.registries.structures.erase(penny_pig.id)
	core.grid.remove_tile(stair_coord)
	check(core.save(), "elevated world state saves")
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	check(restored.load_game(), "elevated world state loads")
	check(
		restored.grid.top_elevation(coord) == 2
		and restored.grid.cell_at(coord, 2).structures.size() == 1,
		"upper blocks and their decorations round-trip together"
	)


func _test_connectivity_and_relocation() -> void:
	var core := fresh_core()
	core.stock.add_tile("tile_grass")
	core.stock.add_tile("tile_grass")
	core.place_tile_from_stock(Vector2i(2, 0), "tile_grass", 0)
	core.place_tile_from_stock(Vector2i(3, 0), "tile_grass", 0)
	check(not core.grid.connected_without(Vector2i(2, 0), core.grid.home_cell), "removing a bridge tile is detected as a split")
	check(core.grid.connected_without(Vector2i(3, 0), core.grid.home_cell), "removing a leaf tile keeps the world whole")
	var refuge := core.grid.nearest_walkable(Vector2i(3, 0), Vector2i(3, 0))
	check(refuge != Vector2i(3, 0) and core.grid.is_walkable(refuge), "safe relocation finds a nearby walkable cell")


func _test_sockets_and_overlap_prevention() -> void:
	var core := fresh_core()
	var coord := Vector2i(0, 0)
	var def := core.grid.tile_def(coord)
	var placed := 0
	while core.grid.free_socket(coord, "decor") >= 0:
		core.grid.add_structure(coord, "struct_pot", core.grid.free_socket(coord, "decor"))
		placed += 1
	check(
		placed == 1,
		"one direct object occupies the tile even when its visual definition exposes %d sockets"
		% def.decor_sockets
	)
	check(core.grid.free_socket(coord, "decor") == -1, "a second direct object cannot use the tile")
	var major := core.grid.free_socket(coord, "structure")
	check(major == -1, "major and decoration types share the one tile-root position")
	check(
		core.grid.add_structure(coord, "struct_campfire", 0) == null,
		"a major structure cannot overlap a direct decoration"
	)
	var pot: WorldGrid.StructureState = core.grid.cell(coord).structures[0]
	check(
		core.grid.structure_local_transform(pot.instance_id).origin.is_equal_approx(Vector3.ZERO),
		"direct objects use the exact center of their tile"
	)

	var starter_dock := core.grid.cell(Vector2i(0, -1)).structures[0]
	check(
		starter_dock.structure_id == "struct_dock"
		and starter_dock.rotation == 2,
		"the opening dock is a movable world object on the middle water tile"
	)
	check(
		core.registries.structure(starter_dock.structure_id).collision_profile
		== "walkable_surface",
		"the opening dock keeps its walkable collision contract"
	)
	check(
		not core.grid.is_walkable(Vector2i(0, -1))
		and core.grid.is_traversable(Vector2i(0, -1)),
		"a dock makes its water cell traversable without reclassifying it as land"
	)
	var water := Vector2i(1, -1)
	check(
		core.grid.can_place_structure_at(water, 0, "struct_dock"),
		"the dock accepts the water surface type"
	)
	check(
		not core.grid.can_place_structure_at(coord, 0, "struct_dock"),
		"the dock rejects solid terrain"
	)
	check(
		not core.grid.can_place_structure_at(water, 0, "struct_bench"),
		"ordinary furniture rejects water surfaces"
	)
	var dock := core.grid.add_structure(water, "struct_dock", 0)
	check(
		dock != null
		and core.grid.structure_local_transform(dock.instance_id).origin.is_equal_approx(Vector3.ZERO),
		"water-only docks are centered on their water tile"
	)
	check(
		core.grid.is_traversable(water),
		"a newly placed dock makes its destination water cell traversable"
	)
	core.grid.remove_structure(water, dock.instance_id)
	check(
		not core.grid.is_traversable(water),
		"removing a dock removes the temporary traversal surface from that water cell"
	)


func _test_object_support_graph() -> void:
	var core := fresh_core()
	var first := Vector2i(7, 7)
	var second := Vector2i(8, 7)
	core.grid.place_tile(first, "tile_grass")
	core.grid.place_tile(second, "tile_grass")
	var expected_stackable := {
		"struct_chest": true,
		"struct_planter": true,
		"struct_pot": true,
		"struct_watering_can": true,
		"struct_milk_churn": true,
	}
	var expected_supports := {
		"struct_bench": {
			"seat_left": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
			"seat_right": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
		},
		"struct_stool": {
			"top": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
		},
		"struct_table": {
			"top_center": [
				"struct_chest",
				"struct_planter",
				"struct_pot",
				"struct_watering_can",
				"struct_milk_churn",
			],
		},
		"struct_chest": {
			"lid": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
		},
		"struct_box": {
			"top": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
		},
		"struct_stone_bench": {
			"seat_left": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
			"seat_right": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
		},
		"struct_barrel": {
			"top": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
		},
		"struct_crate": {
			"top": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
		},
	}
	for definition: Defs.StructureDefinition in core.registries.structures.values():
		check(
			definition.placement_policy_explicit,
			"every structure explicitly declares its scalable support policy: " + definition.id
		)
		check(
			definition.can_be_stacked == expected_stackable.has(definition.id),
			"catalog classifies whether %s can sit on another object" % definition.id
		)
		var expected_slots: Dictionary = expected_supports.get(definition.id, {})
		check(
			definition.support_slots.size() == expected_slots.size(),
			"catalog classifies every support surface exposed by %s" % definition.id
		)
		for slot: Defs.SupportSlotDefinition in definition.support_slots:
			check(
				expected_slots.has(slot.id),
				"%s exposes only its audited support slots" % definition.id
			)
			var accepted_ids: Array = expected_slots.get(slot.id, [])
			for candidate: Defs.StructureDefinition in core.registries.structures.values():
				check(
					slot.accepts_definition(candidate) == accepted_ids.has(candidate.id),
					"%s:%s classifies %s consistently"
						% [definition.id, slot.id, candidate.id]
				)

	var table := core.grid.add_structure(first, "struct_table", 1)
	check(table != null, "a table can be rooted directly on a tile")
	check(
		not core.grid.can_place_structure_at(first, 0, "struct_pot"),
		"one direct object per tile elevation remains enforced"
	)
	var chest := core.grid.add_structure_on(
		table.instance_id,
		"struct_chest",
		"top_center"
	)
	check(
		chest != null
		and chest.parent_instance_id == table.instance_id
		and chest.support_slot_id == "top_center",
		"a storage chest fits the round table's audited tabletop surface"
	)
	check(
		core.grid.add_structure_on(table.instance_id, "struct_planter", "top_center") == null,
		"a named support slot accepts exactly one child"
	)
	var pot := core.grid.add_structure_on(chest.instance_id, "struct_pot", "lid")
	check(
		pot != null and pot.parent_instance_id == chest.instance_id,
		"the chest lid accepts a genuinely small surface item"
	)
	check(
		core.grid.add_structure_on(pot.instance_id, "struct_chest") == null,
		"a terminal object cannot hold another item"
	)
	check(
		not core.grid.can_place_tile_at(first, 1, "tile_grass"),
		"a land tile can never be placed on an object graph"
	)
	var table_transform := core.grid.structure_local_transform(table.instance_id)
	var chest_transform := core.grid.structure_local_transform(chest.instance_id)
	var pot_transform := core.grid.structure_local_transform(pot.instance_id)
	check(
		chest_transform.origin.y > table_transform.origin.y
		and pot_transform.origin.y > chest_transform.origin.y,
		"support transforms compose upward without floating gaps from tile elevation"
	)

	var detached := core.grid.detach_structure_stack(table.instance_id)
	check(
		detached.size() == 3
		and core.grid.find_structure(table.instance_id).is_empty(),
		"moving a supporter detaches its complete descendant stack atomically"
	)
	check(
		core.grid.restore_structure_stack(second, 0, detached, 0, "", 1, 1),
		"a detached object stack restores intact at a new tile root"
	)
	check(
		core.grid.find_structure(chest.instance_id)["structure"].parent_instance_id
			== table.instance_id,
		"moving a base preserves every internal support edge"
	)

	var snapshot := core.grid.to_save_dict()
	var restored_grid := WorldGrid.new(core.registries)
	restored_grid.from_save_dict(snapshot)
	var restored_chest := restored_grid.find_structure(chest.instance_id)
	var restored_pot := restored_grid.find_structure(pot.instance_id)
	check(
		not restored_chest.is_empty()
		and restored_chest["structure"].parent_instance_id == table.instance_id
		and restored_chest["structure"].support_slot_id == "top_center"
		and restored_pot["structure"].parent_instance_id == chest.instance_id,
		"support graph ids and named slots round-trip through save data"
	)


func _test_anchor_cycle_and_regen() -> void:
	var core := fresh_core()
	core.grid.place_tile(Vector2i(2, 0), "tile_grass", 0)
	var tree := core.grid.add_structure(Vector2i(2, 0), "struct_pine", 1)
	var anchor := core.registries.anchor("grove_anchor")
	check(tree != null, "a tree can be placed independently on ordinary terrain")
	tree.anchor_actions_done = anchor.cycle_actions
	tree.anchor_resting = true
	tree.anchor_regen_left = 2.0
	core.track_resting_structure(tree.instance_id)
	core.tick(1.0)
	check(tree.anchor_resting, "tree still resting mid-regen")
	var restored_grid := WorldGrid.new(core.registries)
	restored_grid.from_save_dict(core.grid.to_save_dict())
	var restored_tree: WorldGrid.StructureState = restored_grid.find_structure(
		tree.instance_id
	).get("structure")
	check(
		restored_tree != null
		and restored_tree.anchor_resting
		and restored_tree.anchor_actions_done == anchor.cycle_actions
		and is_equal_approx(restored_tree.anchor_regen_left, 1.0),
		"tree resource state round-trips on the movable object instance"
	)
	core.tick(1.5)
	check(
		not tree.anchor_resting and tree.anchor_actions_done == 0,
		"tree regenerates and resets independently from its tile"
	)


func _test_crafting_transactions() -> void:
	var core := fresh_core()
	core.registries.features["material_crafting_enabled"] = true
	check(not core.crafting.craft("recipe_bench"), "crafting without skill/materials fails")
	core.skills.add_xp("fishing", 1000)   # reach level for bench
	check(not core.crafting.craft("recipe_bench"), "crafting without materials fails")
	var inv_before := core.inventory.count("softwood")
	var benches_before := core.stock.structure_count("struct_bench")
	core.inventory.grant("softwood", 2, false, true)
	core.inventory.grant("reeds", 2, false, true)
	check(core.crafting.craft("recipe_bench"), "crafting with everything succeeds")
	check(core.inventory.count("softwood") == inv_before and core.inventory.count("reeds") == 0, "materials consumed atomically")
	check(core.stock.structure_count("struct_bench") == benches_before + 1, "crafted structure lands in stock")
	core.inventory.grant("hardwood", 2, false, true)
	core.inventory.grant("old_metal", 2, false, true)
	core.inventory.grant("resin", 1, false, true)
	core.skills.add_xp("woodcutting", 2000)
	check(core.crafting.craft("recipe_axe_fine"), "tool recipe crafts")
	check(core.equipment.owns("tool_axe_fine"), "crafted tool is owned equipment")
	check(core.equipment.best_tool("axe").id == "tool_axe_fine", "best tool resolves to the higher tier")


func _test_equipment() -> void:
	var core := fresh_core()
	check(
		core.equipment.owns("cosmetic_cowboy_vest"),
		"starter wardrobe grants the cowboy vest"
	)
	check(
		core.equipment.equipped_in("body").id == "cosmetic_cowboy_vest",
		"cowboy vest starts equipped in the body slot"
	)
	var vest_definition := core.registries.item("cosmetic_cowboy_vest")
	check(
		vest_definition != null
		and vest_definition.asset_id == "cowboy_vest",
		"cowboy vest item resolves the production GLB asset id"
	)
	var vest_scene := load(
		"res://assets/3d/reworked/cowboy_vest.glb"
	) as PackedScene
	check(vest_scene != null, "cowboy vest GLB imports as a PackedScene")
	if vest_scene != null:
		var vest_root := vest_scene.instantiate()
		var vest_mesh := vest_root.find_child(
			"CowboyVest", true, false
		) as MeshInstance3D
		var exposed_body := vest_root.find_child(
			"BodyExposedForCowboyVest", true, false
		) as MeshInstance3D
		check(
			vest_root.find_children("*", "Skeleton3D", true, false).size() == 1,
			"cowboy vest bundle exports one helper skeleton"
		)
		check(
			vest_mesh != null and vest_mesh.skin != null,
			"cowboy vest mesh keeps its skin after GLB import"
		)
		check(
			exposed_body != null and exposed_body.skin != null,
			"covered-body replacement keeps its skin after GLB import"
		)
		vest_root.free()
	core.equipment.equipped.erase("body")
	core.equipment.owned.erase("cosmetic_cowboy_vest")
	core.equipment.appearance_unlocked.erase("cosmetic_cowboy_vest")
	check(core.save(), "pre-wardrobe development save fixture writes")
	var migrated_core := GameCore.new()
	check(migrated_core.setup(), "migration core loads content")
	migrated_core.save_manager.save_path = "user://test_save.json"
	migrated_core.save_manager.backup_path = "user://test_save.json.backup"
	check(migrated_core.load_game(), "pre-wardrobe development save loads")
	check(
		migrated_core.equipment.owns("cosmetic_cowboy_vest")
		and (
			migrated_core.equipment.equipped_in("body").id
			== "cosmetic_cowboy_vest"
		),
		"existing saves gain and equip the vest when their body slot is empty"
	)
	core.equipment.acquire("cape_watchpost")
	check(core.equipment.equip("cape_watchpost"), "owned equipment can be equipped")
	check(core.equipment.equipped_in("back").id == "cape_watchpost", "slot query returns equipped item")
	check(core.equipment.appearance_unlocked.has("cape_watchpost"), "appearance unlock recorded separately from ownership")
	check(core.combat.defense() >= 1, "equipment stats aggregate")
	check(not core.equipment.equip("weapon_thorn_sword"), "unowned equipment cannot be equipped")


func _make_revealed_landmark(core: GameCore) -> LandmarkManager.LandmarkState:
	# Grow east until the watchpost spawns, then bridge to it.
	for i in range(2, 12):
		core.stock.add_tile("tile_grass")
		core.place_tile_from_stock(Vector2i(i, 0), "tile_grass", 0)
		if not core.landmarks.active.is_empty():
			break
	if core.landmarks.active.is_empty():
		return null
	var state: LandmarkManager.LandmarkState = core.landmarks.active[0]
	var guard := 0
	while state.phase == LandmarkManager.PHASE_SILHOUETTE and guard < 24:
		guard += 1
		var target := core.landmarks.footprint_cells(state)[0]
		var frontier := _frontier_toward(core, target)
		if frontier == Vector2i(9999, 9999):
			break
		core.stock.add_tile("tile_grass")
		core.place_tile_from_stock(frontier, "tile_grass", 0)
	return state


func _frontier_toward(core: GameCore, target: Vector2i) -> Vector2i:
	var best := Vector2i(9999, 9999)
	var best_distance := 999999
	for coord: Vector2i in core.grid.cells:
		for offset: Vector2i in WorldGrid.NEIGHBORS:
			var candidate: Vector2i = coord + offset
			if core.grid.has_cell(candidate) or not core.grid.can_place_tile(candidate):
				continue
			var distance := absi(candidate.x - target.x) + absi(candidate.y - target.y)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best


func _test_landmark_lifecycle() -> void:
	var core := fresh_core()
	core.registries.features["hostile_landmarks_enabled"] = true
	var state := _make_revealed_landmark(core)
	check(state != null, "a horizon opportunity spawns as the world grows")
	if state == null:
		return
	var def := core.registries.landmark(state.landmark_id)
	for cell in core.landmarks.footprint_cells(state):
		check(not core.grid.has_cell(cell) or state.phase != LandmarkManager.PHASE_SILHOUETTE, "silhouette never overlaps placed land")
	check(state.phase == LandmarkManager.PHASE_REVEALED, "connecting land reveals the landmark")
	check(core.grid.has_cell(core.landmarks.footprint_cells(state)[0]), "revealed footprint becomes real ground")
	check(state.enemies_alive.size() == 3, "enemy roster spawned from definition")


func _test_guardian_idempotency() -> void:
	var core := fresh_core()
	core.registries.features["hostile_landmarks_enabled"] = true
	var state := _make_revealed_landmark(core)
	if state == null:
		failures.append("guardian test could not build landmark")
		return
	var def := core.registries.landmark(state.landmark_id)
	var grants_a := core.landmarks.on_enemy_defeated(state, def.guardian_id + ":g", true)
	check(core.equipment.owns(def.guardian_reward), "guardian reward granted")
	check(state.phase == LandmarkManager.PHASE_RECLAIMED, "guardian defeat reclaims the landmark")
	var grants_b := core.landmarks.on_enemy_defeated(state, def.guardian_id + ":g", true)
	check(grants_b.is_empty(), "guardian reward is idempotent — no double grant")


func _test_pack_and_salvage() -> void:
	var core := fresh_core()
	core.registries.features["hostile_landmarks_enabled"] = true
	var state := _make_revealed_landmark(core)
	if state == null:
		failures.append("pack test could not build landmark")
		return
	var def := core.registries.landmark(state.landmark_id)
	core.landmarks.on_enemy_defeated(state, def.guardian_id + ":g", true)
	var cells := core.landmarks.footprint_cells(state)
	core.landmarks.resolve(state, "packed")
	check(core.stock.landmark_deeds.has(state.landmark_id), "packing yields a deed")
	check(not core.grid.has_cell(cells[0]), "packed landmark releases its cells")
	# salvage path on a fresh core
	var core2 := fresh_core(999)
	core2.registries.features["hostile_landmarks_enabled"] = true
	var state2 := _make_revealed_landmark(core2)
	if state2 != null:
		var def2 := core2.registries.landmark(state2.landmark_id)
		core2.landmarks.on_enemy_defeated(state2, def2.guardian_id + ":g", true)
		var before := core2.inventory.count("carved_stone")
		core2.landmarks.resolve(state2, "salvaged")
		check(core2.inventory.count("carved_stone") > before, "salvage grants materials")


func _test_deed_replacement() -> void:
	var core := fresh_core()
	core.registries.features["hostile_landmarks_enabled"] = true
	var state := _make_revealed_landmark(core)
	if state == null:
		return
	var def := core.registries.landmark(state.landmark_id)
	core.landmarks.on_enemy_defeated(state, def.guardian_id + ":g", true)
	core.landmarks.resolve(state, "packed")
	var placed_ok := false
	for y in range(-8, 9):
		for x in range(-8, 9):
			if core.landmarks.place_deed(state.landmark_id, Vector2i(x, y)):
				placed_ok = true
				break
		if placed_ok:
			break
	check(placed_ok, "deed re-places beside the world")
	var placed := core.landmarks.state_for(state.landmark_id)
	check(placed != null and placed.phase == LandmarkManager.PHASE_RECLAIMED, "re-placed landmark is peaceful")


func _test_rework_save_round_trip() -> void:
	var core := fresh_core(31415)
	core.skills.add_xp("fishing", 55)
	core.stock.add_tile("tile_grove_birch")
	core.profile.position = Vector3(0.234, 0.0, 0.345)   # continuous, between tile centers
	core.profile.facing = 1.11
	core.view_state = {"yaw": 135.0, "distance": 55.0}
	core.visual_state = {
		"weather": "snow",
		"time_of_day": "night",
		"background": "dusk",
		"particle_quality": "medium",
	}
	core.arrivals.trigger_arrival()
	core.arrivals.mark_delivery_ready(core.arrivals.current_payload)
	var rng_next := core.rng.randi_range("probe", 0, 999999)
	check(core.save(), "save writes")
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	check(restored.load_game(), "save loads")
	check(restored.skills.xp["fishing"] == core.skills.xp["fishing"], "xp round-trips")
	check(restored.inventory.counts.is_empty(), "active material inventory stays empty")
	check(restored.stock.tile_count("tile_grove_birch") == 1, "stock round-trips")
	check(restored.grid.cells.size() == core.grid.cells.size(), "grid round-trips")
	check(restored.profile.position.is_equal_approx(Vector3(0.234, 0.0, 0.345)), "exact float player position round-trips")
	check(absf(restored.profile.facing - 1.11) < 0.0001, "facing round-trips")
	check(restored.view_state == core.view_state, "camera orbit and distance round-trip")
	check(restored.visual_state == core.visual_state, "weather, time, background, and particle quality round-trip")
	check(restored.arrivals.has_waiting_package(), "unopened ferry parcel survives restart")
	check(restored.arrivals.current_payload.parcel_id == "parcel_wild", "delivery payload survives restart")
	# RNG stream continues identically after reload (probe stream was consumed once pre-save)
	var loaded_next := restored.rng.randi_range("probe", 0, 999999)
	var fresh_again := GameCore.new()
	fresh_again.setup("res://data", 31415)
	fresh_again.rng.randi_range("probe", 0, 999999)
	check(loaded_next == fresh_again.rng.randi_range("probe", 0, 999999), "rng stream state round-trips")


func _test_camping_feature_contract() -> void:
	var core := fresh_core(451)
	var tent := core.grid.add_structure(Vector2i(-1, 0), "struct_high_tent", 0)
	check(tent != null, "High Tent places through the generic structure API")
	if tent == null:
		return
	var definition = core.camping.definitions.structure("struct_high_tent")
	check(definition != null, "camping module discovers the High Tent through capabilities")
	check(definition.shelter.capacity == 2, "shelter capacity comes from definition data")
	check(definition.sleep.comfort == 6, "sleep comfort comes from definition data")
	check(definition.storage.slots == 6, "camping storage capacity comes from definition data")
	var options: Array = core.camping.interactions.options_for("keeper", tent.instance_id)
	check(options.size() == 1 and options[0].id == "sleep", "sleep interaction is capability-driven")
	check(
		options[0].feature_id == "camping" and options[0].disabled_reason == "",
		"feature interaction uses the shared presentation-neutral option contract"
	)
	check(core.camping.interactions.execute("sleep", "keeper", tent.instance_id), "keeper can occupy the tent")
	check(core.camping.shelters.damage(tent.instance_id, 17.5), "placed shelter owns mutable durability")
	var state = core.camping.shelters.state_for(tent.instance_id)
	check(is_equal_approx(state.durability, 82.5), "durability mutates independently of static definition")
	check(state.occupants == ["keeper"], "shelter occupants are instance state")
	check(core.save(), "camping feature state saves")
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	check(restored.load_game(), "camping feature state loads")
	var restored_state = restored.camping.shelters.state_for(tent.instance_id, false)
	check(restored_state != null, "saved tent state reconnects by stable instance id")
	if restored_state != null:
		check(is_equal_approx(restored_state.durability, 82.5), "tent durability round-trips")
		check(restored_state.occupants == ["keeper"], "tent occupants round-trip")
	var stored_stack := restored.grid.detach_structure_stack(tent.instance_id)
	check(stored_stack.size() == 1, "stateful tent detaches as one inventory piece")
	if not stored_stack.is_empty():
		restored.stock.add_structure_instance(stored_stack[0])
	check(
		restored.stock.has_structure_instance(tent.instance_id),
		"stateful stock keeps the tent's stable instance id"
	)
	check(restored.save(), "stored stateful tent saves")
	var stored_reload := GameCore.new()
	stored_reload.setup("res://data", 1)
	stored_reload.save_manager.save_path = core.save_manager.save_path
	stored_reload.save_manager.backup_path = core.save_manager.backup_path
	check(stored_reload.load_game(), "stored stateful tent loads")
	check(
		stored_reload.stock.has_structure_instance(tent.instance_id),
		"stored tent identity survives restart"
	)
	var token := stored_reload.stock.take_structure_token(
		"struct_high_tent", tent.instance_id
	)
	var stored_state: Dictionary = token.get("state", {})
	var returned_tent := WorldGrid.StructureState.from_dict(stored_state)
	var returned_stack: Array[WorldGrid.StructureState] = [returned_tent]
	check(
		stored_reload.grid.restore_structure_stack(
			Vector2i(1, 1), 0, returned_stack, 0, "", 0, 0
		),
		"stored tent places again through the generic support API"
	)
	var returned_state = stored_reload.camping.shelters.state_for(tent.instance_id, false)
	check(returned_state != null, "re-placed tent reconnects to its feature state")
	if returned_state != null:
		check(
			is_equal_approx(returned_state.durability, 82.5),
			"store and re-place does not heal or replace the tent"
		)


func _test_current_save_policy() -> void:
	var core := fresh_core(7001)
	check(core.save(), "current-format development save writes")
	var current := core.save_manager.read()
	check(
		int(current.get("format", 0)) == SaveManager.CURRENT_FORMAT,
		"save records the single current pre-release format"
	)
	var stale := current.duplicate(true)
	stale["format"] = 0
	var stale_path := "user://stale_format_test.json"
	var file := FileAccess.open(stale_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(stale))
	file.close()
	var reader := SaveManager.new(core.registries)
	reader.save_path = stale_path
	reader.backup_path = stale_path + ".backup"
	check(
		reader.read().is_empty(),
		"stale pre-release format is rejected instead of migrated"
	)
	DirAccess.remove_absolute(stale_path)
	var retired := current.duplicate(true)
	retired["stock"] = {
		"tiles": {"retired_tile": 1},
		"structures": {},
		"structure_instances": [],
		"deeds": [],
	}
	var errors: PackedStringArray = CurrentSaveValidatorScript.validate(
		retired, core.registries
	)
	check(
		not errors.is_empty(),
		"retired content is reported before any world state mutates"
	)
	var retired_reference_cases := [
		{
			"label": "skill state",
			"mutate": func(save: Dictionary) -> void:
				save["skills"]["xp"]["retired_skill"] = 1,
		},
		{
			"label": "parcel state",
			"mutate": func(save: Dictionary) -> void:
				save["parcels"]["pending_parcel"] = "retired_parcel",
		},
		{
			"label": "equipment state",
			"mutate": func(save: Dictionary) -> void:
				save["equipment"]["owned"].append("retired_item"),
		},
		{
			"label": "landmark state",
			"mutate": func(save: Dictionary) -> void:
				save["landmarks"]["active"].append({
					"id": "retired_landmark",
					"x": 0,
					"y": 0,
					"phase": "silhouette",
					"enemies": [],
				}),
		},
		{
			"label": "collection state",
			"mutate": func(save: Dictionary) -> void:
				save["collection"]["entries"]["gear/retired_item"] = {"count": 1},
		},
		{
			"label": "feature instance state",
			"mutate": func(save: Dictionary) -> void:
				save["features"]["camping"]["shelters"].append({
					"iid": 999999,
					"durability": 1.0,
					"occupants": [],
					"construction_progress": 1.0,
				}),
		},
	]
	for case: Dictionary in retired_reference_cases:
		var invalid := current.duplicate(true)
		(case["mutate"] as Callable).call(invalid)
		check(
			not CurrentSaveValidatorScript.validate(
				invalid, core.registries
			).is_empty(),
			"current-save validation rejects retired %s before hydration"
			% case["label"]
		)


func _test_interrupted_reveal_recovery() -> void:
	var core := fresh_core()
	core.inventory.grant("parcel_wild", 1, false, true)
	core.parcels.open("parcel_wild")
	check(core.parcels.has_pending(), "reveal pending")
	core.save()   # player closes the game mid-reveal
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	restored.load_game()
	check(restored.parcels.has_pending(), "pending reveal survives restart")
	check(restored.parcels.pending_options.size() == 3, "all three options intact")
	var chosen := restored.parcels.choose(1)
	check(chosen != "" and restored.stock.tile_count(chosen) == 1, "resumed reveal completes; nothing lost or duplicated")


func _test_player_defeat_safety() -> void:
	var core := fresh_core()
	core.inventory.grant("softwood", 3, false, true)
	var defeated := [false]   # lambdas capture locals by value; use a container
	core.combat.player_defeated.connect(func(): defeated[0] = true)
	var guard := 0
	while not defeated[0] and guard < 10:
		guard += 1
		core.combat.damage_player(2)
	check(defeated[0], "defeat fires")
	check(core.combat.health == core.combat.max_health, "defeat restores full health (no corpse run)")
	check(core.inventory.count("softwood") == 3, "nothing is lost on defeat")
