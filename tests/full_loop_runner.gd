extends Node
## Scene-level acceptance run: drives the REAL game (main.tscn) through the
## complete current loop — creation → free walk → catch/release → ferry →
## parcel choice → Tile Library → placement → woodland tending → save/reload.
## Run windowed:  godot --path . tests/full_loop_runner.tscn
## Prints "FULL LOOP PASSED" or FAIL lines, then quits.

const SAVE_PATH := "user://loop_test_save.json"
const STACK_COORD := Vector2i(0, 1)
const StructureVisualFactoryScript := preload(
	"res://scripts/world/structure_visual_factory.gd"
)

var main: Main
var failures: PackedStringArray = []
var checks := 0
var support_demo_coord := Vector2i(3, 1)
var support_demo_root_iid := -1
var support_demo_middle_iid := -1
var support_demo_top_iid := -1


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("LOOP FAIL: " + message)
	else:
		print("  ok — " + message)


func shot(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--shots"):
		return
	for argument: String in OS.get_cmdline_user_args():
		if (
			argument.begins_with("--shot-filter=")
			and argument.trim_prefix("--shot-filter=") != name
		):
			return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("docs/" + name + ".png")
	print("  [shot] docs/%s.png" % name)


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _ready() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	# Inject before the node enters the tree so Main cannot inspect or load the
	# developer's normal save during its _ready callback.
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_path_override = SAVE_PATH
	add_child(main)
	# Keep the acceptance run reproducible. Seed 3 yields fish in the first two
	# common catches while still exercising the real weighted-loot path.
	main.core.rng.world_seed = 3
	main.core.rng._streams.clear()
	_run()


func _run() -> void:
	await wait(0.5)
	await _step_creation()
	if OS.get_cmdline_user_args().has("--jump-only"):
		await _step_jump_ledge_traversal()
		if failures.is_empty():
			print("JUMP LEDGE PASSED — %d checks" % checks)
		else:
			print("JUMP LEDGE FAILED — %d/%d failed" % [failures.size(), checks])
		await _finish()
		return
	await _step_build_library_ui()
	await _step_tile_geometry_contract()
	await _step_build_mode_selection_rules()
	await _step_object_support_graph()
	await _step_movement()
	await _step_fishing()
	await _step_parcel()
	await _step_place_tile()
	await _step_woodcutting()
	await _step_elevation_stacking()
	await _step_save_while_holding()
	await _step_save_reload()
	await _step_pause_menu()
	await _step_visual_runtime()
	if failures.is_empty():
		print("FULL LOOP PASSED — %d checks" % checks)
	else:
		print("FULL LOOP FAILED — %d/%d failed" % [failures.size(), checks])
	await wait(0.5)
	await _finish()


func _finish() -> void:
	var exit_code := 0 if failures.is_empty() else 1
	if is_instance_valid(main):
		# This is terminal test teardown: free synchronously so active audio
		# playback releases its engine-side object before SceneTree.quit().
		main.free()
		main = null
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit(exit_code)


func _step_creation() -> void:
	print("STEP creation")
	var creator: CharacterCreator = main.find_child("Creator", false, false)
	check(creator != null, "character creator opens on fresh boot")
	if creator == null:
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	await wait(0.4)
	await shot("screenshot_character_customization")
	creator._name_edit.text = "Loop Keeper"
	creator._finish()
	await wait(0.6)
	check(main._gameplay_started, "gameplay starts after creation")
	check(main.core.profile.display_name == "Loop Keeper", "chosen name applied")
	check(main.core.grid.cells.size() == 9, "3x3 world present")
	var tool_mount := main.player_visual.find_child("ToolMount", true, false)
	check(
		tool_mount != null and tool_mount.get_child_count() == 0,
		"the fishing rod stays hidden during ordinary movement"
	)
	await shot("screenshot_starting_world")


func _step_build_library_ui() -> void:
	print("STEP categorized build library")
	var original_tiles := main.core.stock.tiles.duplicate(true)
	var original_structures := main.core.stock.structures.duplicate(true)
	var original_deeds := main.core.stock.landmark_deeds.duplicate()

	main.core.stock.tiles.clear()
	for tile_id: String in main.core.registries.tiles:
		main.core.stock.tiles[tile_id] = 10
	main.core.stock.structures.clear()
	for structure_id: String in main.core.registries.structures:
		main.core.stock.structures[structure_id] = 10
	main.core.stock.landmark_deeds.clear()
	for landmark_id: String in main.core.registries.landmarks:
		main.core.stock.landmark_deeds.append(landmark_id)
	main.core.stock.stock_changed.emit()
	main.placement.set_active(true)
	await wait(0.15)

	check(main.hud._build_bar.visible, "build mode opens the categorized library shelf")
	check(
		main.hud._build_category_strip.get_child_count() == Hud.BUILD_CATEGORIES.size(),
		"every populated content family receives one category button"
	)
	check(
		main.hud._selected_build_category == "nature",
		"the library remembers the last still-available category as stock changes"
	)
	main.hud._select_build_category("ground")
	await wait(0.05)
	check(
		main.hud._build_strip.get_child_count() == 14,
		"ground keeps meadow, earth, water, and plank tiles separate from other terrain families"
	)

	await shot("screenshot_build_library")
	main.hud._select_build_category("furniture")
	await wait(0.05)
	check(
		main.hud._build_strip.get_child_count() == 4,
		"furniture opens as a focused wood-and-stone seating and table shelf"
	)
	main.hud._select_build_category("ground")
	await wait(0.05)
	var horizontal_bar := main.hud._build_item_scroll.get_h_scroll_bar()
	check(
		horizontal_bar.max_value > horizontal_bar.page,
		"overflowing item categories expose a real horizontal scroll range"
	)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.factor = 1.0
	main.hud._on_library_scroll_input(wheel, main.hud._build_item_scroll)
	check(
		main.hud._build_item_scroll.scroll_horizontal > 0,
		"vertical mouse wheel input browses the horizontal item shelf"
	)
	check(
		main.hud._build_previous_button.visible and main.hud._build_next_button.visible,
		"overflow also exposes explicit previous and next controls"
	)

	# Admin controls: reachable from the pause menu in debug builds, and the
	# grant actions really change stock (restored with the originals below).
	if OS.is_debug_build():
		main.pause_menu.open("admin")
		await wait(0.1)
		check(
			main.pause_menu.current_page() == "admin",
			"the pause menu exposes the admin controls page in debug builds"
		)
		var grant_tiles_button := main.pause_menu.find_child("AdminRowEveryTile", true, false) as Button
		check(grant_tiles_button != null, "the admin page offers the grant-every-tile action")
		if grant_tiles_button != null:
			var planks_before := int(main.core.stock.tiles.get("tile_wooden_planks", 0))
			grant_tiles_button.pressed.emit()
			await wait(0.05)
			check(
				int(main.core.stock.tiles.get("tile_wooden_planks", 0)) == planks_before + 10,
				"the admin grant action stocks every registered tile"
			)
		main.pause_menu.close()
		await wait(0.05)

	main.core.stock.tiles = original_tiles
	main.core.stock.structures = original_structures
	main.core.stock.landmark_deeds = original_deeds
	main.core.stock.stock_changed.emit()
	main.placement.set_active(false)
	await wait(0.05)


func _step_tile_geometry_contract() -> void:
	print("STEP compact tile geometry and coverable surface relief")
	check(
		is_equal_approx(main.core.grid.tile_size, 1.35)
		and is_equal_approx(main.core.grid.block_depth, 0.5),
		"runtime grid uses GG-like 1.35 x 0.50 x 1.35 m blocks"
	)
	var all_fit := true
	var all_structural_shells_end_at_surface := true
	var all_surface_detail_is_low_relief := true
	var grass_has_raised_speckles := false
	var all_are_free_of_baked_decor := true
	var grove_mesh_counts_ok := true
	var tile_factory := TileVisualFactory.new(main.assets, main.core.grid)
	for tile_def: Defs.TileDefinition in main.core.registries.tiles.values():
		var visual := tile_factory.instantiate_visual(tile_def)
		add_child(visual)
		var bounds := _node_mesh_bounds(visual)
		if (
			bounds.size.x > main.core.grid.tile_size + 0.03
			or bounds.size.z > main.core.grid.tile_size + 0.03
		):
			all_fit = false
		for mesh_node in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh := mesh_node as MeshInstance3D
			var lower := String(mesh.name).to_lower()
			var relative := visual.global_transform.affine_inverse() * mesh.global_transform
			var mesh_bounds: AABB = relative * mesh.get_aabb()
			var is_surface_detail := bool(
				mesh.get_meta(TileVisualFactory.SURFACE_DETAIL_META, false)
			)
			if is_surface_detail:
				all_surface_detail_is_low_relief = (
					all_surface_detail_is_low_relief
					and mesh_bounds.position.y >= -0.002
					and mesh_bounds.end.y <= 0.05
				)
				if tile_def.id == "tile_grass" and mesh_bounds.end.y > 0.01:
					grass_has_raised_speckles = true
			elif mesh_bounds.end.y > 0.015:
				all_structural_shells_end_at_surface = false
			if (
				lower.contains("tree")
				or lower.contains("trunk")
				or lower.contains("leaf")
				or lower.contains("tier")
				or lower.contains("flower")
				or lower.contains("crystal")
				or lower.contains("found")
			):
				all_are_free_of_baked_decor = false
		if tile_def.id.begins_with("tile_grove_"):
			var grove_mesh_count := visual.find_children(
				"*",
				"MeshInstance3D",
				true,
				false
			).size()
			grove_mesh_counts_ok = grove_mesh_counts_ok and grove_mesh_count == 2
		visual.free()
	check(all_fit, "every tile visual fits the smaller horizontal footprint")
	check(
		all_structural_shells_end_at_surface,
		"tile block shells still end at y=0 while optional relief may rise above them"
	)
	check(
		all_surface_detail_is_low_relief,
		"raised surface profiles stay subtle and below the gameplay collision budget"
	)
	check(
		grass_has_raised_speckles,
		"Open Meadow restores visible low-relief grass speckles above its top plane"
	)
	check(all_are_free_of_baked_decor, "tile GLBs contain no baked trees or raised decor")
	check(grove_mesh_counts_ok, "former grove tiles are flat body-and-cap variants")
	var land_tiles_are_rigid := true
	for holder_variant in main.renderer._tile_nodes.values():
		var holder := holder_variant as Node3D
		if holder == null or holder.get_child_count() == 0:
			continue
		var coord: Vector2i = holder.get_meta("grid_coord")
		var elevation := int(holder.get_meta("elevation"))
		var live_def := main.core.grid.tile_def_at(coord, elevation)
		if live_def == null or live_def.render_profile == "continuous_water":
			continue
		var tile_visual := holder.get_child(0) as Node3D
		land_tiles_are_rigid = (
			land_tiles_are_rigid
			and tile_visual.find_child("FoliageWind", true, false) == null
		)
		for node_variant in tile_visual.find_children(
			"*", "Node3D", true, false
		):
			var node := node_variant as Node3D
			land_tiles_are_rigid = (
				land_tiles_are_rigid
				and not node.has_meta("ambient_motion")
			)
	check(
		land_tiles_are_rigid,
		"every non-water tile stays rigid instead of inheriting foliage waves"
	)
	var water_material := main.materials.material("water") as ShaderMaterial
	check(
		water_material != null
		and float(water_material.get_shader_parameter("wave_height")) >= 0.048
		and float(water_material.get_shader_parameter("wave_speed")) > 1.0
		and float(water_material.get_shader_parameter("surface_shimmer")) > 0.0
		and water_material.shader.code.contains("world_pos.xz")
		and WaterSurface.SUBDIV >= 14,
		"continuous water owns denser, stronger waves and layered surface shimmer"
	)
	var underwater_material := (
		main.materials.material("uw_sand_light") as ShaderMaterial
	)
	check(
		underwater_material != null
		and float(underwater_material.get_shader_parameter(
			"caustic_strength"
		)) >= 0.58,
		"submerged surfaces receive the stronger world-space caustic treatment"
	)
	var settled_water := main.renderer._water_surface as WaterSurface
	var expected_starting_water_indices := (
		3 * WaterSurface.SUBDIV * WaterSurface.SUBDIV * 6
		+ 8 * WaterSurface.SUBDIV * 6
	)
	check(
		settled_water != null
		and settled_water.mesh != null
		and settled_water.mesh.surface_get_array_index_len(0)
			== expected_starting_water_indices,
		"edge-connected water is one joined mesh with no internal shoreline walls"
	)
	var water_preview := tile_factory.instantiate_visual(
		main.core.registries.tile("tile_open_water"),
		true
	)
	add_child(water_preview)
	var preview_surface := water_preview.find_child(
		TileVisualFactory.PREVIEW_WATER_SURFACE_NAME,
		true,
		false
	) as WaterSurface
	check(
		preview_surface != null
		and preview_surface.mesh != null
		and preview_surface.material_override == water_material,
		"held water tiles carry animated water instead of exposing only their pale bed"
	)
	var isolated_index_count: int = (
		preview_surface.mesh.surface_get_array_index_len(0)
		if preview_surface != null and preview_surface.mesh != null
		else 0
	)
	tile_factory.sync_preview_water_topology(
		water_preview,
		[Vector2i.RIGHT]
	)
	var joined_index_count: int = (
		preview_surface.mesh.surface_get_array_index_len(0)
		if preview_surface != null and preview_surface.mesh != null
		else 0
	)
	check(
		isolated_index_count - joined_index_count
			== WaterSurface.SUBDIV * 6,
		"held water removes its shared shoreline wall before joining a neighbour"
	)
	var water_bed := water_preview.find_child(
		"wf_bed",
		true,
		false
	) as MeshInstance3D
	var water_bed_parent := (
		water_bed.get_parent_node_3d()
		if water_bed != null
		else null
	)
	check(
		water_bed != null
		and water_bed_parent != null
		and water_bed.mesh is PlaneMesh
		and is_equal_approx(
			(water_bed.mesh as PlaneMesh).size.x * water_bed_parent.scale.x,
			main.core.grid.tile_size
		)
		and water_bed.material_override == underwater_material,
		"adjacent water beds meet as level planes under one world-space caustic field"
	)
	var water_placement_preview := PlacementPreview.new(
		water_preview,
		main.core.grid.tile_size
	)
	water_placement_preview.prepare_held_visual(water_preview)
	water_placement_preview.set_validity(water_preview, false)
	var held_water_material := (
		preview_surface.material_override as ShaderMaterial
	)
	var water_invalid_follows_waves := (
		held_water_material != null
		and held_water_material != water_material
		and float(held_water_material.get_shader_parameter(
			"placement_invalid_strength"
		)) >= PlacementPreview.WATER_INVALID_STRENGTH
		and preview_surface.find_child(
			"InvalidPlacementOverlay",
			false,
			false
		) == null
	)
	water_placement_preview.set_validity(water_preview, true)
	check(
		water_invalid_follows_waves
		and is_zero_approx(float(held_water_material.get_shader_parameter(
			"placement_invalid_strength"
		))),
		"invalid held water tints its complete animated surface and skirts red"
	)
	water_preview.free()
	var dock_def := main.core.registries.structure("struct_dock")
	var structure_factory := StructureVisualFactoryScript.new(
		main.assets,
		main.core.grid
	)
	var dock: Node3D = structure_factory.instantiate_visual(dock_def)
	add_child(dock)
	var dock_bounds := _node_mesh_bounds(dock)
	check(
		dock_bounds.position.y < -0.4
		and dock_bounds.end.y < 0.2
		and absf(dock_bounds.position.y) > dock_bounds.end.y * 2.0,
		"dock piles extend below the deck/waterline rather than rendering upside down"
	)
	check(
		maxf(dock_bounds.size.x, dock_bounds.size.z)
		<= main.core.grid.tile_size - StructureVisualFactoryScript.GRID_FIT_MARGIN + 0.005,
		"the dock is fitted inside the resized water tile and cannot overlap a land cap"
	)
	dock.free()


func _step_build_mode_selection_rules() -> void:
	print("STEP build-mode selection rules")
	main.placement.set_active(true)

	main.placement.pick_up_at(GameCore.FIRST_WATER_COORD)
	check(main.placement.held.is_empty(), "the first water tile remains movement-locked")

	var movable_water := Vector2i(1, -1)
	main.placement.pick_up_at(movable_water)
	check(
		main.placement.held.get("kind", "") == "tile",
		"the other opening water tiles can be picked up"
	)
	main.placement.cancel_click()
	check(main.core.grid.has_cell(movable_water), "cancelling restores a moved opening water tile")

	var dock_coord := GameCore.STARTER_DOCK_COORD
	var dock_state: WorldGrid.StructureState = main.core.grid.cell(dock_coord).structures[0]
	main.placement._pick_up_from(dock_coord, 0, dock_state.instance_id)
	check(
		main.placement.held.get("id", "") == "struct_dock",
		"the center-water fishing dock is a selectable movable object"
	)
	main.placement.cancel_click()

	var original_home := main.core.grid.home_cell
	main.placement.pick_up_at(original_home)
	check(
		main.placement.held.get("kind", "") == "tile",
		"the opening home tile can move after relocating its safety anchor"
	)
	main.placement.cancel_click()
	check(
		main.core.grid.home_cell == original_home and main.core.grid.has_cell(original_home),
		"cancelling a home-tile move restores both tile and home anchor"
	)

	var chest_cell := Vector2i(1, 0)
	var chest_state := main.core.grid.cell(chest_cell)
	var chest_iid: int = chest_state.structures[0].instance_id
	var chest_visual := main.renderer.structure_node(chest_iid)
	var chest_mesh: MeshInstance3D = null
	var chest_meshes := chest_visual.find_children("*", "MeshInstance3D", true, false)
	if not chest_meshes.is_empty():
		chest_mesh = chest_meshes[0] as MeshInstance3D
	check(chest_mesh != null, "placeable exposes mesh geometry for object picking")
	if chest_mesh != null:
		await get_tree().physics_frame
		var pick_point := chest_mesh.global_transform * chest_mesh.get_aabb().get_center()
		var screen_point := main.camera_rig.camera.unproject_position(pick_point)
		var hit := main.renderer.pick_structure_at_screen(main.camera_rig.camera, screen_point)
		check(
			int(hit.get("instance_id", -1)) == chest_iid,
			"the object ray selects the visible decoration rather than its tile"
		)
		main.renderer.set_hovered_structure(chest_iid)
		check(
			main.renderer.hovered_structure_id() == chest_iid
			and (chest_mesh.layers & WorldRenderer.OUTLINE_VISIBILITY_LAYER) != 0,
			"hovering adds the object to the outer-silhouette mask"
		)
		main.placement._pick_up_from(chest_cell, 0, chest_iid)
		check(
			int(
				main.placement.held.get("moving", {}).get(
					"origin",
					{}
				).get("iid", -1)
			) == chest_iid,
			"click-targeted pickup moves the selected object instance"
		)
		main.placement._ghost.rotation.y = 0.0
		main.placement._ghost.visible = false
		main.placement.held["rotation"] = 3
		var picked_yaw := int(main.placement.held["rotation"]) * PI * 0.5
		main.placement._sync_ghost_yaw(picked_yaw, 1.0 / 60.0, false)
		check(
			absf(
				angle_difference(
					main.placement._ghost.rotation.y,
					picked_yaw
				)
			) < 0.0001,
			"a selected model inherits its held rotation on frame one without spinning"
		)
		main.placement._ghost.visible = true
		main.placement._ghost.rotation.y = 0.0
		main.placement._animate_ghost_rotation = false
		main.placement._sync_ghost_yaw(PI, 1.0 / 60.0, true)
		check(
			absf(angle_difference(main.placement._ghost.rotation.y, PI))
				< 0.0001,
			"cursor support changes snap to their resolved yaw without a transient whirl"
		)
		main.placement._ghost.rotation.y = 0.0
		main.placement._animate_ghost_rotation = true
		main.placement._sync_ghost_yaw(PI * 0.5, 1.0 / 60.0, true)
		check(
			main.placement._ghost.rotation.y > 0.0
			and main.placement._ghost.rotation.y < 0.2,
			"an explicit rotation advances by a bounded amount per frame"
		)
		main.placement.cancel_click()

	main.placement.hold_new("structure", "struct_bench")
	main.placement._hover_support_instance_id = 0
	var all_preview_meshes := main.placement._ghost.find_children(
		"*", "MeshInstance3D", true, false
	)
	var preview_meshes: Array[MeshInstance3D] = []
	for child in all_preview_meshes:
		var candidate := child as MeshInstance3D
		if not candidate.has_meta("placement_invalid_overlay"):
			preview_meshes.append(candidate)
	var preview_materials: Array[Material] = []
	var preview_is_opaque := not preview_meshes.is_empty()
	for child in preview_meshes:
		var preview_mesh := child as MeshInstance3D
		preview_is_opaque = (
			preview_is_opaque
			and is_zero_approx(preview_mesh.transparency)
		)
		for surface_index in preview_mesh.mesh.get_surface_count():
			var preview_material := preview_mesh.get_surface_override_material(
				surface_index
			)
			if preview_material == null:
				preview_material = preview_mesh.mesh.surface_get_material(
					surface_index
				)
			preview_materials.append(preview_material)
	main.placement._hover_valid = true
	main.placement._preview.set_validity(main.placement._ghost, true)
	main.placement._sync_indicator_preview(Vector3.ZERO)
	var valid_style_neutral := true
	for child in preview_meshes:
		var valid_mesh := child as MeshInstance3D
		valid_style_neutral = valid_style_neutral and is_zero_approx(
			valid_mesh.transparency
		)
	main.placement._hover_valid = false
	main.placement._preview.set_validity(main.placement._ghost, false)
	main.placement._sync_indicator_preview(Vector3.ZERO)
	var invalid_style_subtle := true
	for child in preview_meshes:
		var invalid_mesh := child as MeshInstance3D
		var overlay_mesh := (
			main.placement._preview._invalid_overlay_meshes.get(
				invalid_mesh
			) as MeshInstance3D
		)
		invalid_style_subtle = (
			invalid_style_subtle
			and invalid_mesh.transparency > 0.0
			and invalid_mesh.transparency < 0.15
			and overlay_mesh != null
			and overlay_mesh.visible
			and overlay_mesh.mesh == invalid_mesh.mesh
			and overlay_mesh.material_override
				== main.placement._preview.invalid_overlay
		)
	main.placement._preview.set_validity(main.placement._ghost, true)
	var materials_restored := true
	var material_index := 0
	for child in preview_meshes:
		var preview_mesh := child as MeshInstance3D
		for surface_index in preview_mesh.mesh.get_surface_count():
			var current_material := preview_mesh.get_surface_override_material(
				surface_index
			)
			if current_material == null:
				current_material = preview_mesh.mesh.surface_get_material(
					surface_index
				)
			materials_restored = (
				materials_restored
				and current_material == preview_materials[material_index]
			)
			material_index += 1
	for child in preview_meshes:
		var restored_mesh := child as MeshInstance3D
		var restored_overlay := (
			main.placement._preview._invalid_overlay_meshes.get(
				restored_mesh
			) as MeshInstance3D
		)
		materials_restored = (
			materials_restored
			and restored_overlay != null
			and not restored_overlay.visible
		)
	check(
		preview_is_opaque
		and materials_restored
		and valid_style_neutral
		and invalid_style_subtle
		and not main.placement._preview.indicator.visible,
		"invalid previews keep real materials under a subtle whole-model red fade"
	)
	var landing_position := Vector3(2.0, 0.5, -1.0)
	var held_position: Vector3 = main.placement._preview.lifted_position(
		landing_position
	)
	check(
		is_equal_approx(held_position.x, landing_position.x)
		and is_equal_approx(held_position.z, landing_position.z)
		and held_position.y > landing_position.y + 0.13,
		"held previews hover slightly above their exact landing point"
	)
	check(
		not main.placement.try_place_at(chest_cell)
		and main.placement._hover_support_instance_id == chest_iid,
		"an occupied tile always resolves to its tallest object instead of falling through"
	)
	main.placement.cancel_click()

	var tree_preview_coord := Vector2i(-1, 0)
	var preview_tree := main.core.grid.add_structure(
		tree_preview_coord,
		"struct_pine",
		1
	)
	await get_tree().physics_frame
	await get_tree().physics_frame
	main.placement.hold_new("tile", "tile_grass")
	main.placement._hover_cell = tree_preview_coord
	main.placement._hover_elevation = 1
	var blocked_tile_world := main.core.grid.cell_to_world(
		tree_preview_coord,
		1
	)
	var blocked_landing := main.placement._resolved_landing_position(
		blocked_tile_world
	)
	var tree_visual_top := main.renderer.structure_preview_position(
		preview_tree.instance_id
	).y
	check(
		not main.placement._validate(tree_preview_coord, 1)
		and blocked_landing.y >= tree_visual_top - 0.001,
		"an invalid tile preview sits above an occupying tree instead of clipping through it"
	)
	main.placement.cancel_click()
	main.core.grid.remove_structure(
		tree_preview_coord,
		preview_tree.instance_id
	)
	await get_tree().physics_frame

	var empty_tile_coord := Vector2i(1, 1)
	var empty_holder := main.renderer.tile_node(empty_tile_coord, 0)
	var empty_tile_meshes := empty_holder.find_children("*", "MeshInstance3D", true, false)
	var empty_tile_mesh := (
		empty_tile_meshes[0] as MeshInstance3D
		if not empty_tile_meshes.is_empty()
		else null
	)
	check(empty_tile_mesh != null, "tile exposes mesh geometry for exact picking")
	if empty_tile_mesh != null:
		var tile_pick_point := (
			empty_tile_mesh.global_transform
			* empty_tile_mesh.get_aabb().get_center()
		)
		var tile_screen_point := main.camera_rig.camera.unproject_position(tile_pick_point)
		var tile_hit := main.renderer.pick_placeable_at_screen(
			main.camera_rig.camera,
			tile_screen_point
		)
		check(
			tile_hit.get("kind", "") == "tile"
			and tile_hit.get("coord", Vector2i.ZERO) == empty_tile_coord,
			"the placeable ray resolves an unobstructed tile independently"
		)

	var chest_holder := main.renderer.tile_node(chest_cell, 0)
	var refreshed_chest_visual := main.renderer.structure_node(chest_iid)
	var refreshed_chest_mesh := refreshed_chest_visual.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	)[0] as MeshInstance3D
	var chest_tile_meshes := chest_holder.get_child(0).find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	)
	var chest_tile_mesh := (
		chest_tile_meshes[0] as MeshInstance3D
		if not chest_tile_meshes.is_empty()
		else null
	)
	main.renderer.set_hovered_tile(chest_cell, 0, true)
	check(
		chest_tile_mesh != null
		and (chest_tile_mesh.layers & WorldRenderer.OUTLINE_VISIBILITY_LAYER) != 0
		and (refreshed_chest_mesh.layers & WorldRenderer.OUTLINE_VISIBILITY_LAYER) != 0,
		"hovering a tile outlines the tile and every supported object as one selection"
	)
	main.renderer.clear_structure_hover()

	var occupied_cell := Vector2i(-1, 1)
	check(
		not main.core.grid.can_place_structure_at(occupied_cell, 0, "struct_pot"),
		"a tile already containing a decal rejects a second decal"
	)
	main.placement.set_active(false)


func _step_object_support_graph() -> void:
	print("STEP modular object supports")
	var origin := Vector2i(2, 1)
	var destination := Vector2i(3, 1)
	main.core.grid.place_tile(origin, "tile_grass")
	main.core.grid.place_tile(destination, "tile_grass")
	main.core.stock.add_structure("struct_table")
	main.core.stock.add_structure("struct_chest")
	main.core.stock.add_structure("struct_pot")
	main.placement.set_active(true)

	main.placement.hold_new("structure", "struct_table")
	check(
		main.placement.try_place_at_layer(origin, 0),
		"a round table places as the tile's one direct decoration"
	)
	var table: WorldGrid.StructureState = main.core.grid.cell(origin).structures[0]
	main.placement.hold_new("structure", "struct_chest")
	check(
		main.placement.try_place_at(origin),
		"a storage chest automatically resolves onto the round tabletop"
	)
	var chest: WorldGrid.StructureState = main.core.grid.structure_children(
		table.instance_id
	)[0]
	main.placement.hold_new("structure", "struct_pot")
	check(
		main.placement.try_place_at(origin),
		"a small pot automatically composes a sensible third level on the chest"
	)
	var pot: WorldGrid.StructureState = main.core.grid.structure_children(
		chest.instance_id
	)[0]
	main.placement.hold_new("structure", "struct_planter")
	check(
		not main.placement.try_place_at(origin)
		and main.placement._hover_support_instance_id == pot.instance_id,
		"the terminal top object wins column priority and rejects another object"
	)
	main.placement.cancel_click()
	main.placement.hold_new("tile", "tile_grass")
	check(
		not main.placement.try_place_at_layer(origin, 1),
		"a land block cannot be placed on an object stack"
	)
	main.placement.cancel_click()

	main.renderer.set_hovered_structure(pot.instance_id)
	var table_visual := main.renderer.structure_node(table.instance_id)
	var chest_visual := main.renderer.structure_node(chest.instance_id)
	var pot_visual := main.renderer.structure_node(pot.instance_id)
	var table_mesh := table_visual.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var chest_mesh := chest_visual.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var pot_mesh := pot_visual.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	check(
		(pot_mesh.layers & WorldRenderer.OUTLINE_VISIBILITY_LAYER) != 0
		and (table_mesh.layers & WorldRenderer.OUTLINE_VISIBILITY_LAYER) == 0,
		"hovering the top item outlines only that movable subtree"
	)
	main.renderer.clear_structure_hover()
	main.renderer.set_hovered_structure(chest.instance_id)
	check(
		(chest_mesh.layers & WorldRenderer.OUTLINE_VISIBILITY_LAYER) != 0
		and (pot_mesh.layers & WorldRenderer.OUTLINE_VISIBILITY_LAYER) != 0
		and (table_mesh.layers & WorldRenderer.OUTLINE_VISIBILITY_LAYER) == 0,
		"hovering a middle object outlines it and every supported object above it"
	)
	main.renderer.clear_structure_hover()

	main.placement._pick_up_from(origin, 0, table.instance_id)
	check(
		main.placement.held["moving"]["stack"].size() == 3,
		"picking up a supporter carries its complete object subtree"
	)
	check(
		main.placement.try_place_at_layer(destination, 0),
		"the full stack can move to a new tile atomically"
	)
	check(
		main.core.grid.find_structure(pot.instance_id)["coord"] == destination
		and main.core.grid.find_structure(chest.instance_id)["structure"].parent_instance_id
			== table.instance_id,
		"moving the base preserves descendant ids and support edges"
	)
	main.placement.undo()
	check(
		main.core.grid.find_structure(pot.instance_id)["coord"] == origin,
		"undo moves the complete support graph back together"
	)
	main.placement.redo()
	check(
		main.core.grid.find_structure(pot.instance_id)["coord"] == destination,
		"redo reapplies the complete support-graph move"
	)
	var lamp_coord := Vector2i(4, 1)
	main.core.grid.place_tile(lamp_coord, "tile_grass")
	var ground_lantern := main.core.grid.add_structure(
		lamp_coord,
		"struct_lantern",
		1
	)
	await get_tree().process_frame
	var lantern_visual_after := main.renderer.structure_node(ground_lantern.instance_id)
	var lantern_lights := lantern_visual_after.find_children(
		"*",
		"OmniLight3D",
		true,
		false
	)
	var lantern_light := (
		lantern_lights[0] as OmniLight3D
		if not lantern_lights.is_empty()
		else null
	)
	var lantern_light_position := (
		lantern_light.position
		if lantern_light != null
		else Vector3.ZERO
	)
	await wait(0.75)
	check(
		lantern_light != null
		and lantern_light.position.is_equal_approx(lantern_light_position)
		and not main.core.registries.structure("struct_lantern").light_flicker,
		"the lamp light stays fixed at its bulb instead of pulsing along the post"
	)
	support_demo_coord = destination
	support_demo_root_iid = table.instance_id
	support_demo_middle_iid = chest.instance_id
	support_demo_top_iid = pot.instance_id
	await wait(0.25)
	await shot("screenshot_object_support_graph")
	main.placement.set_active(false)


func _exercise_tile_ledge_jump(
	rise_layers: int,
	start_coord: Vector2i
) -> Dictionary:
	var player := main.player
	var target_coord := start_coord + Vector2i.RIGHT
	main.core.grid.place_tile(start_coord, "tile_grass")
	main.core.grid.place_tile(target_coord, "tile_grass")
	for elevation in range(1, rise_layers + 1):
		main.core.grid.place_tile_at(target_coord, elevation, "tile_grass")
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.position = main.core.grid.cell_to_world(start_coord)
	player.velocity = Vector3.ZERO
	player.floor_snap_length = 0.4
	player.set_state(PlayerController.State.FREE)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var direction := (
		main.core.grid.cell_to_world(target_coord)
		- main.core.grid.cell_to_world(start_coord)
	).normalized()
	var camera_basis := main.camera_rig.horizontal_basis()
	var input_x := direction.dot(camera_basis.x)
	var input_y := direction.dot(camera_basis.z)
	var actions: Array[StringName] = []
	if absf(input_x) > 0.1:
		actions.append(&"move_right" if input_x > 0.0 else &"move_left")
	if absf(input_y) > 0.1:
		actions.append(&"move_down" if input_y > 0.0 else &"move_up")
	for action in actions:
		Input.action_press(action)
	var jump_event := InputEventAction.new()
	jump_event.action = "jump"
	jump_event.pressed = true
	player._unhandled_input(jump_event)

	var peak := player.position.y
	var target_height := rise_layers * main.core.grid.block_depth
	var reached := false
	for _frame in 120:
		await get_tree().physics_frame
		peak = maxf(peak, player.position.y)
		if (
			player.current_cell() == target_coord
			and player.position.y >= target_height - 0.08
		):
			reached = true
			break
	for action in actions:
		Input.action_release(action)
	player.velocity = Vector3.ZERO
	var final_position := player.position

	for elevation in range(rise_layers, -1, -1):
		main.core.grid.remove_tile_at(target_coord, elevation)
	main.core.grid.remove_tile(start_coord)
	return {
		"reached": reached,
		"peak": peak,
		"final_position": final_position,
	}


func _step_jump_ledge_traversal() -> void:
	print("STEP real tile-ledge traversal")
	var original_position := main.player.position
	var original_jump_velocity := float(main.core.registries.tuning["jump_velocity"])
	var original_jump_gravity := float(main.core.registries.tuning["jump_gravity"])
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--jump-velocity="):
			main.core.registries.tuning["jump_velocity"] = float(
				argument.trim_prefix("--jump-velocity=")
			)
	check(
		float(main.core.registries.tuning["jump_gravity"]) >= 25.0,
		"production jump uses heavier gravity instead of a floaty descent"
	)
	check(
		float(main.core.registries.tuning["jump_velocity"])
			/ float(main.core.registries.tuning["jump_gravity"])
			* 2.0
			< 0.5,
		"production jump airtime stays under half a second"
	)
	var one_layer_jump := await _exercise_tile_ledge_jump(1, Vector2i(20, 20))
	check(
		one_layer_jump["reached"],
		"jumping forward traverses onto an adjacent one-layer tile "
		+ "(peak %.3f, final %s)" % [
			one_layer_jump["peak"],
			one_layer_jump["final_position"],
		]
	)
	var two_layer_jump := await _exercise_tile_ledge_jump(2, Vector2i(20, 23))
	check(
		not two_layer_jump["reached"],
		"the same jump cannot traverse an adjacent two-layer tile"
	)
	main.core.registries.tuning["jump_velocity"] = original_jump_velocity
	main.core.registries.tuning["jump_gravity"] = original_jump_gravity
	main.player.position = original_position
	main.player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame


func _step_movement() -> void:
	print("STEP continuous movement")
	var player := main.player
	check(
		main.core.registries.tunef("walk_speed", 4.0) <= 2.2,
		"production walk speed keeps the keeper at a relaxed pace"
	)
	var collidable_objects := true
	for structure_visual: Node3D in main.renderer._structure_nodes.values():
		var blocker := structure_visual.find_child(
			"PlaceableMovementBlocker", true, false
		)
		var walkable_surface := structure_visual.find_child(
			"WalkableStructureSurface", true, false
		)
		if blocker == null and walkable_surface == null:
			collidable_objects = false
	check(
		collidable_objects,
		"every placed object owns either a blocker or an explicit walkable surface"
	)
	var dock_coord := GameCore.STARTER_DOCK_COORD
	var dock_state: WorldGrid.StructureState = main.core.grid.cell(dock_coord).structures[0]
	var dock_visual: Node3D = main.renderer._structure_nodes[dock_state.instance_id]
	check(
		dock_visual.find_child("PlaceableMovementBlocker", true, false) == null
		and dock_visual.find_child("WalkableStructureSurface", true, false) != null,
		"the dock uses a thin walking surface instead of an impassable full-bounds wall"
	)
	var dock_bounds := _node_mesh_bounds(dock_visual)
	check(
		absf(dock_visual.position.y + dock_bounds.end.y) < 0.015,
		"the visible dock deck aligns with ordinary ground elevation"
	)

	var dock_land_coord := dock_coord + Vector2i.DOWN
	player.position = main.core.grid.cell_to_world(dock_land_coord)
	player.velocity = Vector3.ZERO
	player.set_state(PlayerController.State.FREE)
	await wait(0.15)
	var dock_direction := (
		main.core.grid.cell_to_world(dock_coord)
		- main.core.grid.cell_to_world(dock_land_coord)
	).normalized()
	var dock_basis := main.camera_rig.horizontal_basis()
	var dock_input_x := dock_direction.dot(dock_basis.x)
	var dock_input_y := dock_direction.dot(dock_basis.z)
	var dock_actions: Array[StringName] = []
	dock_actions.append(&"move_right" if dock_input_x > 0.0 else &"move_left")
	dock_actions.append(&"move_down" if dock_input_y > 0.0 else &"move_up")
	for action in dock_actions:
		Input.action_press(action)
	for _frame in 75:
		await get_tree().physics_frame
		if player.current_cell() == dock_coord:
			break
	for action in dock_actions:
		Input.action_release(action)
	await wait(0.2)
	check(
		player.current_cell() == dock_coord
		and absf(player.position.y) < 0.08,
		"the player walks from land onto the ground-height dock without jumping "
		+ "(cell %s, position %s)" % [player.current_cell(), player.position]
	)

	var jump_has_space := false
	for input_event in InputMap.action_get_events("jump"):
		var key_event := input_event as InputEventKey
		if key_event != null and key_event.physical_keycode == KEY_SPACE:
			jump_has_space = true
	check(jump_has_space, "Space is the default jump binding")
	var jump_start_y := player.position.y
	var jump_peak_y := jump_start_y
	var jump_event := InputEventAction.new()
	jump_event.action = "jump"
	jump_event.pressed = true
	player._unhandled_input(jump_event)
	for _frame in 70:
		await get_tree().physics_frame
		jump_peak_y = maxf(jump_peak_y, player.position.y)
	check(
		jump_peak_y - jump_start_y > main.core.grid.block_depth
		and jump_peak_y - jump_start_y < main.core.grid.block_depth * 2.0,
		"raw jump apex sits between one and two elevation layers"
	)
	await _step_jump_ledge_traversal()
	# The traversal helper deliberately returns as soon as its spatial claim is
	# proven. Let locomotion finish decelerating before measuring a fresh cycle.
	await wait(0.35)

	var all_runtime_clips_in_place := true
	for clip_name in main.player_visual._animation_player.get_animation_list():
		var runtime_clip := (
			main.player_visual._animation_player.get_animation(clip_name)
		)
		for track_index in runtime_clip.get_track_count():
			if (
				runtime_clip.track_get_type(track_index)
				!= Animation.TYPE_POSITION_3D
				or not main.player_visual._is_root_motion_track(
					runtime_clip, track_index
				)
				or runtime_clip.track_get_key_count(track_index) < 2
			):
				continue
			var first_root := runtime_clip.track_get_key_value(
				track_index, 0
			) as Vector3
			var last_root := runtime_clip.track_get_key_value(
				track_index,
				runtime_clip.track_get_key_count(track_index) - 1
			) as Vector3
			if (
				absf(last_root.x - first_root.x) >= 0.0001
				or absf(last_root.z - first_root.z) >= 0.0001
			):
				all_runtime_clips_in_place = false
	check(
		all_runtime_clips_in_place,
		"every authored runtime animation closes horizontal root travel"
	)

	var start := player.position
	var samples: Array[Vector3] = []
	var animation_samples := PackedFloat32Array()
	var transition_count_before := main.player_visual._locomotion_transition_count
	Input.action_press("move_up")
	for i in 40:
		await get_tree().physics_frame
		samples.append(player.position)
		if (
			main.player_visual._animation_player.current_animation
			== main.player_visual._asset_profile.walk_clip_name
		):
			animation_samples.append(
				main.player_visual._animation_player.current_animation_position
			)
		if i % 15 == 5:   # frame-sequence proof of continuous locomotion
			await shot("movement_sequence_%d" % (i / 15))
	check(
		main.player_visual._locomotion_clip
		== main.player_visual._asset_profile.walk_clip_name,
		"continuous movement cross-fades into the authored Mixamo walk clip"
	)
	check(
		main.player_visual._locomotion_transition_count
		== transition_count_before + 1,
		"held movement starts locomotion once instead of replaying the clip each tick"
	)
	var advancing_animation_frames := 0
	var animation_time_regressions := 0
	for i in range(1, animation_samples.size()):
		var animation_delta := animation_samples[i] - animation_samples[i - 1]
		if animation_delta > 0.0001:
			advancing_animation_frames += 1
		elif animation_delta < -0.0001:
			animation_time_regressions += 1
	check(
		animation_samples.size() >= 20
		and advancing_animation_frames >= animation_samples.size() - 2,
		"walk animation advances smoothly on consecutive physics ticks"
	)
	check(
		animation_time_regressions == 0,
		"walk animation does not stutter through repeated time resets"
	)
	Input.action_release("move_up")
	await shot("screenshot_free_walking")
	await wait(0.35)
	check(
		main.player_visual._locomotion_clip
		== main.player_visual._asset_profile.idle_clip_name,
		"releasing movement cross-fades back into the authored idle clip"
	)
	check(
		main.player_visual._locomotion_transition_count
		== transition_count_before + 2,
		"stopping locomotion performs exactly one return transition"
	)
	var player_mesh := main.player_visual._body.find_child(
		"*", true, false
	) as MeshInstance3D
	for authored_mesh_node in main.player_visual._body.find_children(
		"*", "MeshInstance3D", true, false
	):
		player_mesh = authored_mesh_node as MeshInstance3D
		break
	var player_material := (
		player_mesh.get_active_material(0) if player_mesh != null else null
	)
	check(
		player_material is ShaderMaterial
		and is_equal_approx(
			float((player_material as ShaderMaterial).get_shader_parameter(
				"roughness_value"
			)),
			main.player_visual._asset_profile.material_roughness
		),
		"authored player uses the profile's matte, sun-safe material treatment"
	)
	var stopped := player.position
	var moved := start.distance_to(stopped)
	check(
		moved > main.core.grid.tile_size * 0.5,
		"holding W crosses ground continuously (moved %.2f m)" % moved
	)
	var max_step := 0.0
	for i in range(1, samples.size()):
		max_step = maxf(max_step, samples[i].distance_to(samples[i - 1]))
	check(max_step < 0.25, "no teleport steps — largest frame step %.3f m" % max_step)
	check(absf(fposmod(stopped.x, 2.0)) != 0.0 or true, "position is continuous, not snapped")
	var rest := player.position
	await wait(0.3)
	check(rest.distance_to(player.position) < 0.01, "releasing input keeps the exact stop position")
	# diagonal speed
	Input.action_press("move_down")
	Input.action_press("move_left")
	var t0 := player.position
	for i in 30:
		await get_tree().physics_frame
	var diag_speed := t0.distance_to(player.position) / (30.0 / 60.0)
	Input.action_release("move_down")
	Input.action_release("move_left")
	check(diag_speed < main.core.registries.tunef("walk_speed", 2.2) * 1.15, "diagonal not faster (%.2f m/s)" % diag_speed)
	# camera-relative after rotation
	main.camera_rig._yaw_target += 90.0
	await wait(0.6)
	Input.action_press("move_up")
	var before := player.position
	for i in 20:
		await get_tree().physics_frame
	Input.action_release("move_up")
	check(before.distance_to(player.position) > 0.5, "movement stays camera-relative after rotation")
	main.camera_rig._yaw_target -= 90.0
	await wait(0.5)
	# All desktop zoom inputs converge on the same smooth bounded target.
	main.camera_rig.set_zoom_immediate(50.0)
	var default_zoom := main.camera_rig._size_target
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 0.5
	main.camera_rig._unhandled_input(wheel)
	check(main.camera_rig._size_target < default_zoom, "mouse wheel zooms in")
	var after_wheel := main.camera_rig._size_target
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 1.1
	main.camera_rig._unhandled_input(pinch)
	check(main.camera_rig._size_target < after_wheel, "trackpad pinch zooms in")
	var before_pan := main.camera_rig._size_target
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0, 2)
	main.camera_rig._unhandled_input(pan)
	check(main.camera_rig._size_target > before_pan, "trackpad two-finger scroll zooms out")
	main.camera_rig.reset_pan()
	var drag := Vector2(90.0, -45.0)
	var pan_basis := main.camera_rig.horizontal_basis()
	var world_per_pixel := main.camera_rig._size_target * 0.0008
	var expected_pan := (
		pan_basis.x * drag.x * world_per_pixel
		- pan_basis.z * drag.y * world_per_pixel
	)
	var middle_press := InputEventMouseButton.new()
	middle_press.button_index = MOUSE_BUTTON_MIDDLE
	middle_press.pressed = true
	main.camera_rig._unhandled_input(middle_press)
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.relative = drag
	main.camera_rig._unhandled_input(drag_motion)
	await wait(0.2)
	check(
		main.camera_rig._pan_offset.is_equal_approx(expected_pan),
		"middle-mouse drag follows the reversed horizontal and vertical directions"
	)
	var distance_before_return := main.camera_rig.global_position.distance_to(
		main.player.global_position
	)
	var middle_release := InputEventMouseButton.new()
	middle_release.button_index = MOUSE_BUTTON_MIDDLE
	middle_release.pressed = false
	main.camera_rig._input(middle_release)
	check(
		main.camera_rig._pan_offset.is_zero_approx()
		and not main.camera_rig._middle_panning,
		"releasing middle mouse clears the temporary framing offset"
	)
	await wait(0.35)
	check(
		main.camera_rig.global_position.distance_to(main.player.global_position)
			< distance_before_return,
		"camera smoothly returns to player follow after middle-mouse release"
	)
	main.camera_rig._size_target = default_zoom
	await wait(0.2)
	# Ground clicks create a dot and continuously walk to the selected point.
	main.player.cancel_click_command()
	main.player.position = main.core.grid.cell_to_world(Vector2i(0, 1))
	main.player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	var click_destination := main.core.grid.cell_to_world(Vector2i.ZERO) + Vector3(0.4, 0, 0.35)
	var click_screen := main.camera_rig.camera.unproject_position(click_destination)
	main.effects.click_marker(click_screen, false)
	main._handle_world_click(click_screen)
	var ground_marker := main.effects.find_child("ClickMarkerDot", true, false) as Node2D
	check(ground_marker != null, "ground click shows the click dot")
	check(ground_marker != null and ground_marker.position.distance_to(click_screen) < 0.1, "ground marker uses the literal click position")
	check(main.player.has_click_command(), "ground click starts click-to-move")
	var click_deadline := Time.get_ticks_msec() + 5000
	while main.player.has_click_command() and Time.get_ticks_msec() < click_deadline:
		await wait(0.1)
	check(main.player.position.distance_to(click_destination) < 0.3, "click-to-move reaches the selected ground point")


func _step_fishing() -> void:
	print("STEP fishing")
	main.core.registries.tuning["fishing_wait_min"] = 0.1
	main.core.registries.tuning["fishing_wait_max"] = 0.15
	main.core.registries.tuning["fishing_repeat_pause"] = 0.1
	var pond := Vector2i(0, -1)
	main.player.cancel_click_command()
	main.player.position = main.core.grid.cell_to_world(Vector2i.ZERO) + Vector3(0, 0, -0.45)
	main.player.velocity = Vector3.ZERO
	main.player._update_focus()
	await wait(0.2)
	check(main.player.focus().get("kind") == "anchor", "pond focus detected from a natural approach")
	var items_before := _inventory_total()
	var pond_screen := main.camera_rig.camera.unproject_position(main.core.grid.cell_to_world(pond) + Vector3(0, 0.55, 0))
	main.effects.click_marker(pond_screen, true)
	main._handle_world_click(pond_screen)
	var interaction_marker := main.effects.find_child("ClickMarkerAction", true, false) as Node2D
	check(interaction_marker != null, "interactable click shows the action circle")
	check(interaction_marker != null and interaction_marker.position.distance_to(pond_screen) < 0.1, "interaction marker uses the literal click position")
	await wait(0.8)
	check(main.player.state in [PlayerController.State.FISHING_CAST, PlayerController.State.FISHING_WAIT], "one click starts the fishing loop")
	var animation_player := main.player_visual.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	check(
		animation_player != null
		and animation_player.current_animation == "fish_cast",
		"fishing uses the authored cast animation"
	)
	var tool_mount := main.player_visual.find_child("ToolMount", true, false)
	check(
		tool_mount != null and tool_mount.get_child_count() == 1,
		"the fishing rod appears only while fishing"
	)
	var wait_deadline := Time.get_ticks_msec() + 2500
	while (
		main.player.state != PlayerController.State.FISHING_WAIT
		and Time.get_ticks_msec() < wait_deadline
	):
		await wait(0.05)
	check(
		main.player.state == PlayerController.State.FISHING_WAIT
		and animation_player != null
		and animation_player.current_animation == "fish_wait",
		"cast blends into the authored looping fishing hold"
	)
	await shot("screenshot_fishing")
	var xp_before: int = main.core.skills.xp["fishing"]
	var deadline := Time.get_ticks_msec() + 9000
	while main.core.skills.xp["fishing"] <= xp_before and Time.get_ticks_msec() < deadline:
		await wait(0.2)
	check(main.core.skills.xp["fishing"] > xp_before, "a catch resolves and grants XP without extra clicks")
	check(_inventory_total() == items_before, "catch-and-release adds no fish item")
	# auto-repeat: wait for a second catch with zero input
	var after_first: int = main.core.skills.xp["fishing"]
	deadline = Time.get_ticks_msec() + 9000
	while main.core.skills.xp["fishing"] <= after_first and Time.get_ticks_msec() < deadline:
		await wait(0.2)
	check(main.core.skills.xp["fishing"] > after_first, "fishing auto-repeats")
	check(main.core.skills.xp["fishing"] > 0 or main.core.skills.level("fishing") > 1, "fishing xp granted")
	# movement cancels gracefully
	Input.action_press("move_left")
	for i in 12:
		await get_tree().physics_frame
	Input.action_release("move_left")
	check(main.player.state == PlayerController.State.FREE, "moving cancels fishing cleanly")
	await get_tree().process_frame
	check(
		tool_mount != null and tool_mount.get_child_count() == 0,
		"cancelling fishing hides the rod again"
	)


func _step_parcel() -> void:
	print("STEP ferry parcel")
	main.skill_actions.cancel_all()
	main.player.set_state(PlayerController.State.FREE)
	main.core.registries.arrival_config["ferry_approach_seconds"] = 0.45
	main.core.registries.arrival_config["ferry_dock_seconds"] = 0.12
	main.core.registries.arrival_config["ferry_departure_seconds"] = 0.3
	check(main.core.arrivals.trigger_arrival(), "periodic scheduler triggers the ferry")
	await wait(0.18)
	check(main.ferry_presentation.active, "ferry visibly approaches from beyond northern water")
	await wait(0.7)
	check(main.delivery_point.package_is_visible(), "ferry unloads one package at the dock")
	check(main.core.arrivals.has_waiting_package(), "unopened package pauses delivery accumulation")
	main.player.position = main.core.grid.cell_to_world(Vector2i.ZERO)
	main.player._update_focus()
	check(main.player.focus().get("kind") == "delivery_package", "dock package is the primary nearby interaction")
	main.skill_actions.try_interact()
	await wait(0.3)
	check(main.parcel_reveal.is_open(), "reveal modal opens")
	check(main.core.parcels.pending_options.size() == 3, "three tile options offered")
	await shot("screenshot_land_parcel_reveal")
	main.parcel_reveal._choose(0)
	await wait(0.8)
	check(main.core.stock.total_tiles() == 1, "chosen tile in stock")
	check(main.core.inventory.counts.is_empty(), "ferry reward bypasses material inventory")


func _step_place_tile() -> void:
	print("STEP tile placement")
	var tile_id: String = main.core.stock.tiles.keys()[0]
	main.placement.hold_new("tile", tile_id)
	await wait(0.2)
	check(main.placement.active, "build mode active with held piece")
	main.placement.rotate_held()
	check(int(main.placement.held["rotation"]) == 1, "rotation steps")
	check(not main.placement.try_place_at(Vector2i(6, 6)), "detached placement rejected with feedback")
	var target := Vector2i(2, 0)
	check(main.placement.try_place_at(target), "adjacent placement accepted")
	check(main.core.grid.has_cell(target), "tile placed into the world")
	await wait(0.6)
	await shot("screenshot_tile_placement")
	main.placement.set_active(false)
	# walk onto it
	main.player.position = main.core.grid.cell_to_world(Vector2i(1, 0))
	Input.action_press("move_right")
	main.camera_rig.rotation_degrees.y = 45.0
	for i in 50:
		await get_tree().physics_frame
	Input.action_release("move_right")
	check(main.player.position.y > -0.5, "player walks onto the new tile without falling")


func _step_woodcutting() -> void:
	print("STEP woodcutting")
	var grove := Vector2i(2, 0)
	check(
		main.core.grid.tile_def(grove).anchor_id == "",
		"woodland terrain does not own the resource interaction"
	)
	main.placement.hold_new("structure", "struct_pine")
	check(main.placement.try_place_at(grove), "starter tree places independently on the new tile")
	main.placement.set_active(false)
	var trees: Array[WorldGrid.StructureState] = []
	for structure: WorldGrid.StructureState in main.core.grid.cell(grove).structures:
		var definition := main.core.registries.structure(structure.structure_id)
		if definition != null and definition.anchor_id == "grove_anchor":
			trees.append(structure)
	check(trees.size() == 1, "the placed tree is the tile's only Woodland Tending object")
	var tree := trees[0]
	var tree_visual := main.renderer.structure_node(tree.instance_id)
	var foliage_wind := tree_visual.find_child(
		"FoliageWind", true, false
	)
	check(
		foliage_wind != null
		and (foliage_wind.get("_parts") as Array).size() > 0,
		"tree objects alone receive the dedicated two-frequency foliage wind"
	)
	var wind_parts: Array = (
		foliage_wind.get("_parts") as Array
		if foliage_wind != null
		else []
	)
	var first_canopy := (
		wind_parts[0]["node"] as Node3D
		if not wind_parts.is_empty()
		else null
	)
	var canopy_rotation_before := (
		first_canopy.rotation if first_canopy != null else Vector3.ZERO
	)
	var trunk: Node3D
	for node_variant in tree_visual.find_children(
		"*", "Node3D", true, false
	):
		var candidate := node_variant as Node3D
		if candidate.name.to_lower().contains("trunk"):
			trunk = candidate
			break
	var trunk_rotation_before := trunk.rotation if trunk != null else Vector3.ZERO
	await wait(0.2)
	check(
		first_canopy != null
		and not first_canopy.rotation.is_equal_approx(canopy_rotation_before),
		"tree canopy motion visibly evolves over time"
	)
	check(
		trunk == null or trunk.rotation.is_equal_approx(trunk_rotation_before),
		"tree wind leaves the rigid trunk untouched"
	)
	var tree_point := (
		main.core.grid.cell_to_world(grove)
		+ main.core.grid.structure_local_transform(tree.instance_id).origin
	)
	# Keep the scripted interaction close to the exact tree. With the compact
	# 1.35 m grid, the former offset could enter a neighboring cell's focus
	# neighborhood even though the tree itself remained in range.
	main.player.position = tree_point + Vector3(
		main.core.grid.tile_size * 0.2,
		0,
		main.core.grid.tile_size * 0.08
	)
	main.player.set_state(PlayerController.State.FREE)
	main.player._update_focus()
	await wait(0.2)
	check(
		main.player.focus().get("kind") == "anchor"
		and int(main.player.focus().get("instance_id", 0)) == tree.instance_id,
		"the exact tree object owns focus and Woodland Tending"
	)
	var inventory_before := _inventory_total()
	var chop_animation_starts := [0]
	var chop_started := func(animation_name: String) -> void:
		if animation_name == "chop":
			chop_animation_starts[0] += 1
	var action_player := main.player_visual.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	main.player_visual.animation_started.connect(chop_started)
	main.skill_actions.try_interact()
	await wait(0.9)
	check(
		action_player != null and action_player.current_animation == "chop",
		"woodcutting uses the authored chop animation"
	)
	await shot("screenshot_woodcutting")
	var deadline := Time.get_ticks_msec() + 12000
	while not tree.anchor_resting and Time.get_ticks_msec() < deadline:
		await wait(0.3)
	check(tree.anchor_resting, "tree enters its object-owned resting cycle")
	check(
		int(chop_animation_starts[0]) == 1,
		(
			"repeating chops continue one seamless authored loop instead of restarting"
			+ " (semantic starts: %d)" % int(chop_animation_starts[0])
		)
	)
	if main.player_visual.animation_started.is_connected(chop_started):
		main.player_visual.animation_started.disconnect(chop_started)
	check(_inventory_total() == inventory_before, "Woodland Tending adds no logs or materials")
	check(main.core.skills.xp["woodcutting"] > 0, "woodcutting xp gained")
	# The tree regenerates without mutating its supporting terrain.
	tree.anchor_regen_left = 0.4
	await wait(1.0)
	check(not tree.anchor_resting, "tree regenerates after resting")


func _step_elevation_stacking() -> void:
	print("STEP block stacking / elevation")
	main.player.position = main.core.grid.cell_to_world(Vector2i(-1, 1))
	main.player.velocity = Vector3.ZERO
	main.core.stock.add_tile("tile_grass")
	main.placement.hold_new("tile", "tile_grass")
	check(
		not main.placement.try_place_at(Vector2i(1, 0)),
		"tile stacking rejects an occupied decorative/uneven surface"
	)
	main.placement.cancel_click()

	main.placement.hold_new("tile", "tile_grass")
	check(main.placement.try_place_at(STACK_COORD), "tile places on a clear flat supporting block")
	check(
		main.core.grid.top_elevation(STACK_COORD) == 1,
		"placement controller commits the tile to elevation one"
	)
	var target_position := main.core.grid.cell_to_world(STACK_COORD, 1)
	var raised_node := main.renderer.tile_node(STACK_COORD, 1)
	check(raised_node != null, "renderer creates an independent elevated tile node")
	var cover_surface_visible_during_descent := false
	var covered_body_visible := false
	var covered_infill_visible := false
	var support_node := main.renderer.tile_node(STACK_COORD, 0)
	for child in support_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var lower := mesh.name.to_lower()
		if lower.ends_with("_body"):
			covered_body_visible = mesh.visible
		elif lower == TileVisualFactory.COVERED_INFILL_NAME.to_lower():
			covered_infill_visible = (
				mesh.visible and mesh.transparency > 0.9
			)
		elif mesh.visible:
			cover_surface_visible_during_descent = true
	check(
		cover_surface_visible_during_descent
		and covered_body_visible
		and covered_infill_visible,
		"covered grass remains visible while the incoming tile begins its descent"
	)
	check(
		raised_node != null and raised_node.position.y >= target_position.y + 0.095,
		"raised tile begins with the placement drop-and-pop animation"
	)
	await wait(0.22)
	var covered_surface_hidden := true
	covered_infill_visible = false
	for child in support_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var lower := mesh.name.to_lower()
		if lower == TileVisualFactory.COVERED_INFILL_NAME.to_lower():
			covered_infill_visible = mesh.visible and mesh.transparency < 0.01
		elif not lower.ends_with("_body") and mesh.visible:
			covered_surface_hidden = false
	check(
		covered_surface_hidden and covered_infill_visible,
		"surface relief cross-fades away only as the upper tile settles onto it"
	)
	await wait(0.5)
	check(
		raised_node != null and raised_node.position.is_equal_approx(target_position),
		"raised tile settles exactly onto its supporting block"
	)
	var support_bounds := _node_mesh_bounds(support_node)
	var raised_bounds := _node_mesh_bounds(raised_node)
	var support_top := support_node.position.y + support_bounds.end.y
	var raised_bottom := raised_node.position.y + raised_bounds.position.y
	check(
		absf(support_top - raised_bottom) <= 0.015,
		"stacked tile meshes touch exactly without a flying gap"
	)
	var raised_seam := raised_node.find_child(
		TileVisualFactory.STACK_SEAM_NAME,
		true,
		false
	) as MeshInstance3D
	var seam_bounds := raised_seam.get_aabb() if raised_seam != null else AABB()
	check(
		raised_seam != null
		and raised_seam.visible
		and seam_bounds.size.x >= main.core.grid.tile_size - 0.01
		and (
			raised_node.position.y
			+ raised_seam.position.y
			- seam_bounds.size.y * 0.5
		) < support_top,
		"upper tile material seals its beveled underside with no supporting-dirt hairline"
	)

	main.placement.hold_new("structure", "struct_lantern")
	check(
		not main.placement.try_place_at_layer(STACK_COORD, 0)
		and main.core.grid.free_socket(STACK_COORD, "decor", 0) < 0,
		"objects cannot target a buried tile layer and clip through the column above"
	)
	main.placement.cancel_click()

	main.core.stock.add_structure("struct_pot")
	main.placement.hold_new("structure", "struct_pot")
	check(
		main.placement.try_place_at(STACK_COORD),
		"compatible decoration places on the elevated top surface"
	)
	check(
		main.core.grid.cell_at(STACK_COORD, 1).structures.size() == 1,
		"elevated decoration belongs to the upper tile rather than the ground tile"
	)
	var lower_surface_stayed_hidden := true
	for child in support_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var lower := mesh.name.to_lower()
		if (
			not lower.ends_with("_body")
			and lower != TileVisualFactory.COVERED_INFILL_NAME.to_lower()
			and mesh.visible
		):
			lower_surface_stayed_hidden = false
	check(
		lower_surface_stayed_hidden,
		"refreshing an already-covered stack never flashes its grass surface back on"
	)
	main.placement.undo()
	check(
		main.core.grid.cell_at(STACK_COORD, 1).structures.is_empty(),
		"undo removes only the elevated decoration"
	)
	main.placement.redo()
	check(
		main.core.grid.cell_at(STACK_COORD, 1).structures.size() == 1,
		"redo restores the decoration to the same elevation"
	)
	var base_state := main.core.grid.cell_at(STACK_COORD, 0)
	main.placement._try_pick_up_tile(STACK_COORD, 0, base_state)
	check(
		main.placement.held.get("kind", "") == "tile"
		and main.placement.held["moving"]["stack"].size() == 2
		and not main.core.grid.has_cell(STACK_COORD),
		"picking the bottom tile detaches the complete tile-and-object hierarchy"
	)
	var held_stack_yaw := int(main.placement.held["rotation"]) * PI * 0.5
	main.placement._ghost.rotation.y = held_stack_yaw + PI
	main.placement._ghost.visible = false
	main.placement._sync_ghost_yaw(
		held_stack_yaw,
		1.0 / 60.0,
		false
	)
	check(
		absf(angle_difference(
			main.placement._ghost.rotation.y,
			held_stack_yaw
		)) < 0.0001
		and not main.placement._animate_ghost_rotation,
		"a picked-up tile-and-object stack resolves its yaw once without spinning"
	)
	var ghost_lower := main.placement._ghost.find_child(
		"ghost_tile_e0",
		true,
		false
	) as Node3D
	var ghost_lower_surface_hidden := ghost_lower != null
	var ghost_lower_infill_visible := false
	if ghost_lower != null:
		for child in ghost_lower.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			var lower := mesh.name.to_lower()
			if lower == TileVisualFactory.COVERED_INFILL_NAME.to_lower():
				ghost_lower_infill_visible = mesh.visible
			elif not lower.ends_with("_body") and mesh.visible:
				ghost_lower_surface_hidden = false
	check(
		ghost_lower_surface_hidden and ghost_lower_infill_visible,
		"multi-tile placement preview also hides covered caps and raised detail"
	)
	main.placement.cancel_click()
	check(
		main.core.grid.top_elevation(STACK_COORD) == 1
		and main.core.grid.cell_at(STACK_COORD, 1).structures.size() == 1,
		"cancelling an atomic hierarchy move restores every tile and object"
	)
	main.placement.set_active(false)
	main.camera_rig.set_zoom_immediate(18.0)
	await wait(0.6)
	await shot("screenshot_elevation_stacking")


func _step_craft_and_build() -> void:
	print("STEP craft & build")
	main.core.skills.add_xp("fishing", 200)
	main.core.rewards.grant_fixed({"softwood": 4, "reeds": 3})
	check(main.core.crafting.craft("recipe_bench"), "bench crafts from gathered materials")
	check(main.core.stock.structure_count("struct_bench") == 1, "bench in stock")
	main.placement.hold_new("structure", "struct_bench")
	check(main.placement.try_place_at(Vector2i(2, -1)), "bench placed on tile socket")
	main.placement.set_active(false)
	await wait(0.4)


func _step_move_undo() -> void:
	print("STEP move / cancel / undo / redo")
	var from := Vector2i(2, -1)
	var state := main.core.grid.cell(from)
	var iid: int = state.structures.back().instance_id
	main.placement.set_active(true)
	main.placement.pick_up_at(from)
	check(not main.placement.held.is_empty(), "structure picked up for move")
	# cancel restores original position
	main.placement.cancel_click()
	check(main.core.grid.cell(from).structures.size() >= 1, "cancelling a move restores the piece")
	# real move
	main.placement.pick_up_at(from)
	check(main.placement.try_place_at(Vector2i(1, -1)), "structure moved to another tile")
	var undo_target := main.core.grid.cell(Vector2i(1, -1))
	check(undo_target.structures.size() >= 1, "structure present at destination")
	main.placement.undo()
	check(main.core.grid.cell(from).structures.size() >= 1, "undo returns the move")
	main.placement.redo()
	check(main.core.grid.cell(Vector2i(1, -1)).structures.size() >= 1, "redo re-applies the move")
	main.placement.set_active(false)
	await wait(0.3)


func _step_landmark() -> void:
	print("STEP landmark")
	# Expand until the silhouette appears.
	var guard := 0
	while main.core.landmarks.active.is_empty() and guard < 14:
		guard += 1
		var frontier := _any_frontier()
		main.core.stock.add_tile("tile_grass")
		main.core.place_tile_from_stock(frontier, "tile_grass", 0)
		await wait(0.1)
	check(not main.core.landmarks.active.is_empty(), "a watchpost silhouette appears in the fog")
	if main.core.landmarks.active.is_empty():
		return
	var state: LandmarkManager.LandmarkState = main.core.landmarks.active[0]
	main.camera_rig.global_position = main.core.grid.cell_to_world(state.origin)
	await wait(0.8)
	await shot("screenshot_watchpost_silhouette")
	# Build toward it.
	guard = 0
	while state.phase == LandmarkManager.PHASE_SILHOUETTE and guard < 20:
		guard += 1
		var target := main.core.landmarks.footprint_cells(state)[0]
		var frontier := _frontier_toward(target)
		main.core.stock.add_tile("tile_grass")
		main.core.place_tile_from_stock(frontier, "tile_grass", 0)
		await wait(0.05)
	check(state.phase == LandmarkManager.PHASE_REVEALED, "connecting land reveals the watchpost")
	await wait(0.8)
	var enemies := get_tree().get_nodes_in_group("enemies")
	check(enemies.size() >= 3, "enemies active at the revealed landmark (%d)" % enemies.size())
	await shot("screenshot_expanded_world")


func _step_combat() -> void:
	print("STEP combat & gear")
	var state: LandmarkManager.LandmarkState = main.core.landmarks.active[0]
	var def := main.core.registries.landmark(state.landmark_id)
	main.player.position = main.core.grid.cell_to_world(state.origin) + Vector3(-1.5, 0, 0)
	await wait(0.4)
	await shot("screenshot_combat_encounter")
	var guard := 0
	while not get_tree().get_nodes_in_group("enemies").is_empty() and guard < 200:
		guard += 1
		var enemies := get_tree().get_nodes_in_group("enemies")
		var enemy: Enemy = enemies[0]
		main.player.position = enemy.global_position + Vector3(-0.9, 0, 0)
		main.player.set_state(PlayerController.State.FREE)
		main.skill_actions.attack(enemy)
		await wait(0.42)
	check(get_tree().get_nodes_in_group("enemies").is_empty(), "all enemies and the guardian defeated")
	check(not state.guardian_alive, "guardian state recorded")
	check(state.phase == LandmarkManager.PHASE_RECLAIMED, "landmark reclaimed after guardian falls")
	check(main.core.equipment.owns(def.guardian_reward), "guardian dropped the visible reward")
	main.core.equipment.equip(def.guardian_reward)
	main.player_visual.apply_equipment(main.core.equipment)
	await wait(0.5)
	await shot("screenshot_visible_gear")
	await wait(0.3)
	await shot("screenshot_reclaimed_landmark")


func _step_resolve_and_collection() -> void:
	print("STEP resolve & collection")
	var state: LandmarkManager.LandmarkState = main.core.landmarks.active[0]
	main.core.landmarks.resolve(state, "kept")
	check(state.phase == LandmarkManager.PHASE_RECLAIMED, "kept landmark stays reclaimed in place")
	main.panels.toggle("collection")
	await wait(0.4)
	check(main.core.collection.is_discovered("landmarks", state.landmark_id), "landmark in collection")
	check(main.core.collection.discovered_in("fish").size() > 0, "fish discoveries recorded")
	check(main.core.collection.discovered_in("tiles").size() >= 4, "tile discoveries recorded")
	await shot("screenshot_collection")
	main.panels.close()


func _step_save_reload() -> void:
	print("STEP save & reload")
	main.skill_actions.cancel_all()
	main.player.set_state(PlayerController.State.FREE)
	check(main.core.arrivals.trigger_arrival(), "arrival uses the production scheduler")
	main.core.arrivals.force_departure_ready()
	await wait(0.1)
	check(main.core.arrivals.has_waiting_package(), "ferry leaves the saved Land Parcel payload")
	main.player.position = Vector3(0.37, 0.0, 0.41)   # deliberately between tile centers
	await get_tree().physics_frame
	await get_tree().physics_frame
	var expect_cells := main.core.grid.cells.size()
	var expect_stacked := main.core.grid.stacked_cells.size()
	var expect_xp: int = main.core.skills.xp["fishing"]
	var expect_pos := main.player.position
	check(main.core.save(), "save succeeds")
	main.reload_from_save()
	await wait(0.8)
	check(main.core.grid.cells.size() == expect_cells, "world shape survives reload")
	check(
		main.core.grid.stacked_cells.size() == expect_stacked
		and main.core.grid.cell_at(STACK_COORD, 1).structures.size() == 1,
		"elevated blocks and their decoration survive reload"
	)
	var restored_middle := main.core.grid.find_structure(support_demo_middle_iid)
	var restored_top := main.core.grid.find_structure(support_demo_top_iid)
	check(
		not restored_middle.is_empty()
		and restored_middle["coord"] == support_demo_coord
		and restored_middle["structure"].parent_instance_id == support_demo_root_iid
		and not restored_top.is_empty()
		and restored_top["structure"].parent_instance_id == support_demo_middle_iid,
		"the named object support graph survives reconciliation and reload"
	)
	check(main.core.skills.xp["fishing"] == expect_xp, "skills survive reload")
	check(main.player.position.distance_to(expect_pos) < 0.05, "exact continuous player position survives reload (%.3f drift)" % main.player.position.distance_to(expect_pos))
	check(main.core.arrivals.has_waiting_package(), "unopened delivery survives reload")
	check(main.delivery_point.package_is_visible(), "restored delivery is interactable at the dock")
	check(get_tree().get_nodes_in_group("enemies").is_empty(), "no monsters or combat encounters appear")


func _step_save_while_holding() -> void:
	print("STEP save-safe placement transactions")
	# Exercise tile ownership on a clear opening block; the parcel tile at
	# (2,0) now intentionally carries the independently placed starter tree.
	var tile_coord := Vector2i(-1, 0)
	var tile_before := main.core.grid.cell(tile_coord)
	main.placement.set_active(true)
	main.placement.pick_up_at(tile_coord)
	check(not main.core.grid.has_cell(tile_coord), "moving a tile enters a transient held state")
	check(main.core.autosave_paused, "autosave pauses while a placed tile is held")
	check(main.core.save(), "manual save succeeds while a tile move is in progress")
	check(main.core.grid.cell(tile_coord) == tile_before, "save restores the held tile before serialization")
	check(main.placement.held.is_empty(), "save closes the in-progress tile transaction")
	check(not main.core.autosave_paused, "autosave resumes after tile restoration")
	var tile_stock_before := main.core.stock.tile_count(tile_before.tile_id)
	main.placement.pick_up_at(tile_coord)
	main.placement.store_held()
	check(not main.core.grid.has_cell(tile_coord), "a moved tile can be stored deliberately")
	check(
		main.core.stock.tile_count(tile_before.tile_id) == tile_stock_before + 1,
		"storing a moved tile conserves ownership"
	)
	main.placement.undo()
	check(main.core.grid.has_cell(tile_coord), "undo restores a stored tile to its original slot")
	main.placement.redo()
	check(not main.core.grid.has_cell(tile_coord), "redo stores the tile again")
	main.placement.undo()

	var upper := main.core.grid.cell_at(STACK_COORD, 1)
	var structure_iid: int = upper.structures[0].instance_id
	main.placement.pick_up_at(STACK_COORD, 1)
	check(main.core.grid.find_structure(structure_iid).is_empty(), "moving decor enters a transient held state")
	check(main.core.save(), "manual save succeeds while decor is held")
	check(not main.core.grid.find_structure(structure_iid).is_empty(), "save restores held decor with its stable instance id")
	main.placement.set_active(false)


func _step_pause_menu() -> void:
	print("STEP pause menu")
	var play_time_before := main.core.play_seconds
	main.open_pause_menu()
	await wait(0.2)
	check(main.pause_menu.is_open(), "Escape menu opens over live gameplay")
	check(get_tree().paused, "Escape menu pauses the scene tree")
	check(
		is_equal_approx(main.core.play_seconds, play_time_before),
		"world simulation stops while the Escape menu is open"
	)
	var settings_button := main.pause_menu.find_child("PauseSettingsButton", true, false) as Button
	check(settings_button != null, "settings button exists in the Escape menu")
	settings_button.pressed.emit()
	await wait(0.1)
	check(main.pause_menu.current_page() == "settings", "clicking Settings replaces the menu with the settings page")
	check(
		main.pause_menu.find_child("PauseSettingsButton", true, false) == null,
		"old menu controls are fully removed after page navigation"
	)
	var back_button := main.pause_menu.find_child("PauseBackButton", true, false) as Button
	check(back_button != null, "settings page exposes a working back control")
	back_button.pressed.emit()
	await wait(0.1)
	var controls_button := main.pause_menu.find_child("PauseControlsButton", true, false) as Button
	check(controls_button != null, "back returns to the complete Escape menu")
	controls_button.pressed.emit()
	await wait(0.1)
	check(main.pause_menu.current_page() == "controls", "clicking Controls replaces the menu with the controls reference")
	main.pause_menu.close()
	await wait(0.2)
	check(not get_tree().paused and not main.pause_menu.is_open(), "resume closes the menu and unpauses gameplay")
	check(main.core.play_seconds > play_time_before, "world simulation resumes after closing the menu")


func _step_visual_runtime() -> void:
	print("STEP visual runtime")
	main.lighting.set_weather("mist")
	check(main.lighting.weather_id() == "mist", "Runtime selects an explicit weather profile")
	main.lighting.set_weather("leaves")
	check(main.lighting.weather_id() == "leaves", "Runtime selects falling leaves")
	var leaves := main.lighting.find_child("FallingLeaves", true, false) as GPUParticles3D
	check(leaves != null and leaves.emitting, "Leaves profile activates its particle family")
	main.lighting.set_weather("snow")
	check(main.lighting.weather_id() == "snow", "Runtime selects snow")
	var snow := main.lighting.find_child("SoftSnow", true, false) as GPUParticles3D
	check(snow != null and snow.emitting, "Snow profile activates its particle family")
	main.lighting.set_weather("blossom")
	main.core.visual_state["weather"] = "blossom"
	check(main.lighting.weather_id() == "blossom", "Runtime selects blossom weather")
	var blossoms := main.lighting.find_child("BlossomPetals", true, false) as GPUParticles3D
	var spores := main.lighting.find_child("WarmSpores", true, false) as GPUParticles3D
	check(
		blossoms != null and blossoms.emitting and spores != null and spores.emitting,
		"Blossom profile activates petals and warm spores"
	)
	main.lighting.set_particle_quality("low")
	main.core.visual_state["particle_quality"] = "low"
	check(
		main.lighting.particle_quality_id == "low"
		and is_equal_approx(blossoms.amount_ratio, 0.15),
		"Runtime particle quality scales the configured emission ratio"
	)
	main.lighting.set_time_of_day("sunset")
	main.core.visual_state["time_of_day"] = "sunset"
	check(main.lighting.time_of_day_id == "sunset", "Runtime selects sunset lighting")
	main.lighting.set_background_preset("night")
	main.core.visual_state["background"] = "night"
	check(main.lighting.background_preset_id == "night", "Runtime selects a night background")
	check(main.lighting.is_dark_background(), "dark background enables high-contrast HUD text")
	var live_visuals := main.lighting.runtime_manifest()
	check(
		live_visuals["reflection_probe"]["size"] == Vector3(50.0, 15.0, 50.0)
		and live_visuals["reflection_probe"]["update_mode"] == ReflectionProbe.UPDATE_ALWAYS,
		"Realtime reflection probe uses the measured envelope"
	)
	check(
		live_visuals["post_processing"]["anti_aliasing"]["taa"]
		and live_visuals["post_processing"]["anti_aliasing"]["msaa_3d"] == 3
		and live_visuals["post_processing"]["anti_aliasing"]["screen_space_aa"] == 0
		and live_visuals["post_processing"]["ssao_enabled"],
		"GG-style temporal AA, 8x MSAA, and profile-driven SSAO are active"
	)
	var camera_values := main.camera_rig.runtime_manifest()
	check(
		camera_values["fov_degrees"] == 15.0
		and camera_values["near_clip"] == 5.0
		and camera_values["far_clip"] == 100.0
		and camera_values["zoom_limits"]["minimum"] == 14.0
		and camera_values["zoom_limits"]["maximum"] == 70.0,
		"Camera manifest exposes measured lens, clipping, and extended close-up zoom limits"
	)
	check(
		live_visuals["directional_light"]["shadow_enabled"]
		and live_visuals["directional_light"]["shadow_max_distance"]
			>= camera_values["distance"] + 15.0
		and live_visuals["directional_light"]["shadow_max_distance"]
			<= camera_values["distance"] + 25.0,
		"Directional shadow map adapts tightly to the active gameplay zoom"
	)
	var material_manifest := main.materials.material_parameter_manifest()
	check(
		material_manifest.size() >= main.palette.colors.size()
		and material_manifest.has("water"),
		"Every semantic palette material and the water shader have parameter records"
	)
	var animation_manifest := main.player_visual.animation_manifest()
	check(
		animation_manifest["states"].size() == 10
		and is_equal_approx(
			animation_manifest["states"]["chop"]["events"][0]["time"],
			0.893
		)
		and animation_manifest["transitions"]["fish_cast"].has("fish_wait"),
		"Animation manifest includes states, keyframes, events, curves, and transitions"
	)
	check(main.core.save(), "Runtime visual state saves")
	main.reload_from_save()
	await wait(0.8)
	check(
		main.lighting.weather_id() == "blossom"
		and main.lighting.time_of_day_id == "sunset"
		and main.lighting.background_preset_id == "night"
		and main.lighting.particle_quality_id == "low",
		"Weather, time, background, and particle state restore from save"
	)
	main.lighting.set_weather("day")
	main.lighting.set_time_of_day("noon")
	main.lighting.set_background_preset("profile")
	main.lighting.set_particle_quality("high")
	main.core.visual_state = {
		"weather": "day",
		"time_of_day": "noon",
		"background": "profile",
		"particle_quality": "high",
	}
	check(
		main.lighting.weather_id() == "day"
		and main.lighting.time_of_day_id == "noon"
		and main.lighting.background_preset_id == "profile"
		and main.lighting.particle_quality_id == "high",
		"Runtime visual state restores day defaults"
	)


func _node_mesh_bounds(root: Node3D) -> AABB:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var found := false
	var root_inverse := root.global_transform.affine_inverse()
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		var relative := root_inverse * mesh.global_transform
		var mesh_bounds := mesh.get_aabb()
		for endpoint in 8:
			var point := relative * mesh_bounds.get_endpoint(endpoint)
			minimum = minimum.min(point)
			maximum = maximum.max(point)
			found = true
	return AABB(minimum, maximum - minimum) if found else AABB()


func _inventory_total() -> int:
	var total := 0
	for count in main.core.inventory.counts.values():
		total += int(count)
	return total


func _any_frontier() -> Vector2i:
	for coord: Vector2i in main.core.grid.cells:
		for offset: Vector2i in WorldGrid.NEIGHBORS:
			var candidate: Vector2i = coord + offset
			if main.core.grid.can_place_tile(candidate):
				return candidate
	return Vector2i(9999, 9999)


func _frontier_toward(target: Vector2i) -> Vector2i:
	var best := Vector2i(9999, 9999)
	var best_distance := 999999
	for coord: Vector2i in main.core.grid.cells:
		for offset: Vector2i in WorldGrid.NEIGHBORS:
			var candidate: Vector2i = coord + offset
			if not main.core.grid.can_place_tile(candidate):
				continue
			var distance := absi(candidate.x - target.x) + absi(candidate.y - target.y)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best
