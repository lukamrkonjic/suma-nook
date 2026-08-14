extends Node
## Real-scene smoke test for the shipped Worldheart loop. Uses an isolated
## save and exercises collection-vibe setup, pointer/controller targeting,
## physical contributions, progress presentation, and a movable host tile.

const SAVE_PATH := "user://diorama_scene_test_save.json"

var main: Main
var failures: PackedStringArray = []
var checks := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("  ok - " + message)
	else:
		failures.append(message)
		printerr("DIORAMA SCENE FAIL: " + message)


func _ready() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_path_override = SAVE_PATH
	add_child(main)
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(0.45).timeout
	await get_tree().process_frame
	check(
		not main._gameplay_started
		and main.collection_vibe_panel.is_open()
		and main.core.grid.cells.is_empty()
		and not main.hud.visible
		and not main.project_panel.hud_visible()
		and not main.project_panel.blocks_world_pointer(Vector2(40.0, 40.0))
		and not main.player.visible
		and not main.pigeon_mascot.visible
		and not main.worldheart_presenter.visible,
		"the vibe question appears over an empty backdrop with no old actors"
	)
	main.collection_vibe_panel._choose("winter")
	await get_tree().create_timer(0.2).timeout
	var all_snow := true
	for state: WorldGrid.CellState in main.core.grid.cells.values():
		if state.tile_id != "tile_snowfield":
			all_snow = false
	check(
		main._gameplay_started
		and main.core.diorama.worldheart.vibe_collection_id == "winter"
		and not main.nook_offer_panel.is_open()
		and main.core.grid.cells.size() == 9
		and main.core.grid.has_cell(Vector2i.ZERO)
		and main.core.grid.cell(Vector2i.ZERO).movement_locked
		and all_snow
		and not main.project_panel.hud_visible()
		and not main.player.visible
		and not main.pigeon_mascot.visible,
		"Winter creates exactly nine Snowfield tiles with only the centre Worldheart"
	)
	check(
		main.discovery_tray_panel == null
		and main.worldheart_presenter != null
		and main.worldheart_presenter.hole != null
		and main.worldheart_presenter.portal_fx_root.name == "PortalFxRoot"
		and main.worldheart_presenter.vortex_pivot.name == "WellVisualPivot"
		and main.worldheart_presenter.well_visual_root != null
		and main.worldheart_presenter.well_visual_root.visible
		and main.worldheart_presenter.hole.visible
		and (
			main.worldheart_presenter.hole.material_override
			as StandardMaterial3D
		).albedo_color == Color.BLACK
		and (
			main.worldheart_presenter.hole.material_override
			as StandardMaterial3D
		).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		and main.worldheart_presenter.outer_aura_pivot.get_child_count() == 0
		and main.worldheart_presenter.rune_stone_ring_pivot.get_child_count() == 0
		and main.worldheart_presenter.mote_emitter_pivot.get_child_count() == 0
		and main.worldheart_presenter.portal_light == null,
		"the permanent Worldheart is the wishing well with an always-dark, effect-free mouth"
	)
	var well_materials_are_crisp := true
	var well_mesh_count := 0
	for mesh_variant in main.worldheart_presenter.well_visual_root.find_children(
		"*", "MeshInstance3D", true, false
	):
		var well_mesh := mesh_variant as MeshInstance3D
		if well_mesh == main.worldheart_presenter.hole:
			continue
		well_mesh_count += 1
		for surface in well_mesh.mesh.get_surface_count():
			var well_material := (
				well_mesh.get_active_material(surface) as StandardMaterial3D
			)
			well_materials_are_crisp = (
				well_materials_are_crisp
				and well_material != null
				and well_material.texture_filter
					== BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				and well_material.diffuse_mode
					== BaseMaterial3D.DIFFUSE_TOON
				and well_material.specular_mode
					== BaseMaterial3D.SPECULAR_TOON
			)
	check(
		well_mesh_count > 0 and well_materials_are_crisp,
		"well textures use crisp sampling and stepped terrain-style lighting"
	)
	var well_screen := main.camera_rig.camera.unproject_position(
		main.worldheart_presenter._well_interaction_anchor()
	)
	var well_hover := main.placement._interaction_hover_at_screen(
		well_screen
	)
	main.placement._show_interaction_hover(well_hover)
	await get_tree().process_frame
	check(
		well_hover.get("visual")
			== main.worldheart_presenter.well_visual_root
		and not main.renderer._outlined_meshes.is_empty(),
		"hovering the well sends its authored mesh through the white outline pass"
	)
	main.renderer.clear_structure_hover()
	# The world is permanently editable; the old Build Bag focus flag must not
	# authorize or reject a direct right-click on the well.
	main.placement.set_active(false)
	var well_right_click := InputEventMouseButton.new()
	well_right_click.button_index = MOUSE_BUTTON_RIGHT
	well_right_click.pressed = true
	well_right_click.position = well_screen
	main._input(well_right_click)
	await get_tree().create_timer(0.38).timeout
	check(
		main.core.diorama.worldheart.worldheart_rotation_quarters == 1
		and is_equal_approx(
			main.worldheart_presenter.vortex_pivot.rotation.y, PI * 0.5
		)
		and int(main.core.diorama.worldheart.to_save_dict().get(
			"worldheart_rotation_quarters", -1
		)) == 1,
		"right-click rotates the well without requiring legacy build mode"
	)
	InputDeviceService.shared().input_method = InputDeviceService.InputMethod.CONTROLLER
	main.placement.set_controller_mode(true)
	main.placement._controller_cell = main.core.diorama.worldheart.worldheart_cell
	var controller_rotate := InputEventAction.new()
	controller_rotate.action = &"rotate_piece"
	controller_rotate.pressed = true
	main._handle_controller_build_input(controller_rotate)
	await get_tree().create_timer(0.55).timeout
	check(
		main.core.diorama.worldheart.worldheart_rotation_quarters == 2
		and is_equal_approx(
			main.worldheart_presenter.vortex_pivot.rotation.y, PI
		),
		"the controller rotate action turns the focused well through the same state"
	)
	main.placement.set_controller_mode(false)
	main.placement.set_active(false)
	InputDeviceService.shared().input_method = InputDeviceService.InputMethod.KEYBOARD_MOUSE
	var camera_pan_before := main.camera_rig._pan_offset
	Input.action_press("camera_pan_down", 0.3)
	main.camera_rig._apply_continuous_pan(1.0)
	Input.action_release("camera_pan_down")
	check(
		main.camera_rig._pan_offset.is_equal_approx(camera_pan_before),
		"idle analogue drift cannot continuously pan the camera downward"
	)
	check(
		not main.player.deployed
		and main.player.state == PlayerController.State.DISABLED
		and main.player.position.is_equal_approx(
			main.core.grid.cell_to_world(main.core.grid.home_cell)
		),
		"Worldheart parks its hidden camera anchor at home and removes it from physics"
	)
	var build_toggle := InputEventAction.new()
	build_toggle.action = &"build_mode"
	build_toggle.pressed = true
	var zoom_while_open := InputEventAction.new()
	zoom_while_open.action = &"camera_zoom_in"
	zoom_while_open.pressed = true
	var camera_zoom_before := main.camera_rig._size_target
	var anchor_before := main.player.position
	main._unhandled_input(build_toggle)
	await get_tree().process_frame
	Input.action_press("camera_pan_down", 1.0)
	main.camera_rig._apply_continuous_pan(1.0)
	main.camera_rig._unhandled_input(zoom_while_open)
	await get_tree().create_timer(0.15).timeout
	check(
		main.placement.active
		and main.hud.build_library_expanded()
		and main.player.state == PlayerController.State.DISABLED
		and main.player.position.is_equal_approx(anchor_before)
		and main.camera_rig._pan_offset.is_equal_approx(camera_pan_before)
		and is_equal_approx(main.camera_rig._size_target, camera_zoom_before),
		"opening Build Bag cannot wake the hidden player, pan, or zoom the camera"
	)
	main._unhandled_input(build_toggle)
	await get_tree().process_frame
	main.camera_rig._apply_continuous_pan(1.0)
	check(
		not main.placement.active
		and main.player.state == PlayerController.State.DISABLED
		and main.camera_rig._pan_offset.is_equal_approx(camera_pan_before),
		"closing Build Bag keeps held stick input disarmed until neutral"
	)
	Input.action_release("camera_pan_down")
	main.camera_rig._apply_continuous_pan(0.01)
	Input.action_press("camera_pan_down", 1.0)
	main.camera_rig._apply_continuous_pan(0.1)
	check(
		not main.camera_rig._pan_offset.is_equal_approx(camera_pan_before),
		"intentional camera pan resumes after the stick returns to neutral"
	)
	Input.action_release("camera_pan_down")
	main.camera_rig._pan_offset = camera_pan_before
	main._on_focus_changed({"kind": "void_fishing"})
	check(
		main.hud._prompt_label.text.is_empty(),
		"the retired void-fishing prompt never leaks into the new loop"
	)

	await get_tree().create_timer(2.7).timeout
	var visible := main.core.diorama.worldheart.visible_entries()
	check(
		visible.size() == 1
		and main.worldheart_presenter._entry_nodes.size() == 1,
		"a timed pulse creates one saved, clickable world miniature"
	)
	var first_entry: Dictionary = visible[0]
	var first_entry_id := String(first_entry.get("entry_id", ""))
	var reward_node := main.worldheart_presenter._entry_nodes[first_entry_id] as Node3D
	var first_offset := (
		reward_node.position - main.worldheart_presenter._centre()
	)
	check(
		Vector2(first_offset.x, first_offset.z).length() > 0.4,
		"the first settled pulse lands beside the well, not inside it"
	)
	var reward_screen := main.camera_rig.camera.unproject_position(
		reward_node.global_position
	)
	var pointer_target := main.worldheart_presenter.interaction_at_screen(
		main.camera_rig.camera,
		reward_screen,
		72.0
	)
	check(
		String(pointer_target.get("kind", "")) == "worldheart_reward"
		and pointer_target.get("visual") == reward_node,
		"mouse targeting selects the surfaced miniature, not the hole or tile"
	)
	var provider_target := main.placement._interaction_hover_at_screen(reward_screen)
	check(
		provider_target.get("visual") == reward_node,
		"the build hover provider outlines the exact dropped-item visual"
	)

	InputDeviceService.shared().input_method = InputDeviceService.InputMethod.CONTROLLER
	main.placement.set_controller_mode(true)
	main.placement._controller_cell = main.worldheart_presenter._entry_cells[first_entry_id]
	var controller_target := main._interaction_at_controller_cursor()
	check(
		String(controller_target.get("kind", "")) == "worldheart_reward",
		"controller world-cursor targeting reaches the same exact reward"
	)
	main._perform_interaction(controller_target)
	await get_tree().process_frame
	check(
		_stock_count(first_entry) == 1
		and main.core.diorama.worldheart.visible_entries().is_empty(),
		"hovered controller interaction transfers the piece to the Build Bag"
	)

	main.core.tick(30.0)
	var emerging_entries := main.core.diorama.worldheart.visible_entries()
	var emerging_id := String(emerging_entries[0].get("entry_id", ""))
	var paused_emerging_node := (
		main.worldheart_presenter._entry_nodes.get(emerging_id) as Node3D
	)
	main.worldheart_presenter.set_player_interaction_busy(true)
	var paused_emergence_position := paused_emerging_node.position
	await get_tree().create_timer(0.18).timeout
	check(
		paused_emerging_node.position.is_equal_approx(
			paused_emergence_position
		)
		and bool(paused_emerging_node.get_meta(
			&"worldheart_launching", false
		)),
		"active reward presentation yields completely to build interaction"
	)
	main.worldheart_presenter.set_player_interaction_busy(false)
	# The launch resumes on its own clock after the pause, so sample every frame
	# rather than betting on one instant: the reward must be seen ABOVE the
	# mouth at some point of its flight.
	var emergence_seen := false
	var emergence_deadline := Time.get_ticks_msec() + 2000
	var emerging_node: Node3D = null
	while Time.get_ticks_msec() < emergence_deadline:
		emerging_node = (
			main.worldheart_presenter._entry_nodes.get(emerging_id) as Node3D
		)
		if (
			is_instance_valid(emerging_node)
			and emerging_node.position.y
				> main.worldheart_presenter._well_mouth_anchor().y + 0.12
		):
			emergence_seen = true
			break
		await get_tree().process_frame
	check(
		emergence_seen,
		"timed rewards visibly shoot up out of the well mouth before falling to a slot"
	)
	await get_tree().create_timer(0.76).timeout
	await get_tree().create_timer(1.15).timeout
	var fixed_reward_position := emerging_node.global_position
	var fixed_reward_cell: Vector2i = main.worldheart_presenter._entry_cells[
		emerging_id
	]
	main.worldheart_presenter.rotate_clockwise()
	await get_tree().create_timer(0.38).timeout
	var rotated_reward_position := emerging_node.global_position
	check(
		Vector2(
			rotated_reward_position.x, rotated_reward_position.z
		).is_equal_approx(Vector2(
			fixed_reward_position.x, fixed_reward_position.z
		))
		and main.worldheart_presenter._entry_cells[emerging_id]
			== fixed_reward_cell,
		"surfaced loot stays fixed when the well rotates"
	)
	main.core.diorama.worldheart.move_to(Vector2i(1, 1))
	await get_tree().process_frame
	var moved_reward_position := emerging_node.global_position
	check(
		Vector2(
			moved_reward_position.x, moved_reward_position.z
		).is_equal_approx(Vector2(
			fixed_reward_position.x, fixed_reward_position.z
		))
		and main.worldheart_presenter._entry_cells[emerging_id]
			== fixed_reward_cell,
		"surfaced loot stays fixed when the well moves"
	)
	main.core.diorama.worldheart.move_to(Vector2i.ZERO)
	await get_tree().process_frame
	main.core.tick(30.0)
	var waiting_entries := main.core.diorama.worldheart.visible_entries()
	main.placement._controller_cell = Vector2i.ZERO
	var collect_all_target := main._interaction_at_controller_cursor()
	check(
		String(collect_all_target.get("kind", "")) == "worldheart_collect_all",
		"the hole itself exposes a one-action collect-all target"
	)
	main._perform_interaction(collect_all_target)
	await get_tree().process_frame
	var all_collected := true
	for entry: Dictionary in waiting_entries:
		if _stock_count(entry) <= 0:
			all_collected = false
	check(
		main.core.diorama.worldheart.visible_entries().is_empty()
		and all_collected,
		"collect-all clears visible clutter and keeps every gift"
	)

	var camera_distance_before_edit := main.camera_rig._size_target
	main.placement.set_active(false)
	var always_build_coord := Vector2i(-1, -1)
	var always_build_cell := main.core.grid.cell(always_build_coord)
	var always_build_rotation_before := always_build_cell.rotation
	var tile_right_click := InputEventMouseButton.new()
	tile_right_click.button_index = MOUSE_BUTTON_RIGHT
	tile_right_click.pressed = true
	tile_right_click.position = main.camera_rig.camera.unproject_position(
		main.core.grid.cell_to_world(always_build_coord) + Vector3.UP * 0.12
	)
	main._input(tile_right_click)
	await get_tree().create_timer(0.02).timeout
	check(
		always_build_cell.rotation == posmod(always_build_rotation_before + 1, 4),
		"right-click rotates a hovered world tile while the Build Bag is closed"
	)
	main.core.stock.add_tile("tile_grass_flower", 3)
	InputDeviceService.shared().input_method = InputDeviceService.InputMethod.KEYBOARD_MOUSE
	main.placement.set_controller_mode(false)
	main.placement.set_active(true)
	main.placement.hold_new("tile", "tile_grass_flower")
	var held_rotation_before := int(main.placement.held.get("rotation", -1))
	var held_right_click := InputEventMouseButton.new()
	held_right_click.button_index = MOUSE_BUTTON_RIGHT
	held_right_click.pressed = true
	held_right_click.position = main.camera_rig.camera.unproject_position(
		main.core.grid.cell_to_world(Vector2i(1, 0)) + Vector3.UP * 0.3
	)
	main._input(held_right_click)
	check(
		int(main.placement.held.get("rotation", -1))
			== posmod(held_rotation_before + 1, 4),
		"right-click reaches the early input route and rotates the held build item"
	)
	InputDeviceService.shared().input_method = InputDeviceService.InputMethod.CONTROLLER
	main.placement.set_controller_mode(true)
	main.placement._controller_cell = main.core.diorama.worldheart.worldheart_cell
	main._sync_worldheart_offer_preview()
	await get_tree().create_timer(0.16).timeout
	check(
		main.worldheart_presenter._well_is_stirred,
		"hover visibly stirs the well"
	)
	await get_tree().create_timer(0.40).timeout
	var hover_shake_before := main.worldheart_presenter.well_shake_root.rotation
	await get_tree().create_timer(0.05).timeout
	var hover_shake_after := main.worldheart_presenter.well_shake_root.rotation
	check(
		main.worldheart_presenter._well_is_stirred
		and hover_shake_before.distance_to(hover_shake_after) > 0.001,
		"controller hover completes the stir and gives the well a visible shake"
	)
	main.placement._controller_cell = Vector2i(2, 2)
	main._sync_worldheart_offer_preview()
	await get_tree().create_timer(0.42).timeout
	check(
		not main.worldheart_presenter._well_is_stirred,
		"moving the held item away settles the well without consuming it"
	)
	InputDeviceService.shared().input_method = InputDeviceService.InputMethod.KEYBOARD_MOUSE
	main.placement.set_controller_mode(false)
	main.worldheart_presenter.show_offering_preview(
		"tile", "tile_grass_flower"
	)
	main.placement.set_external_offer_preview(true)
	check(
		is_equal_approx(
			main.camera_rig._size_target, camera_distance_before_edit
		)
		and main.worldheart_presenter.has_offering_preview()
		and (
			main.placement._ghost == null
			or not main.placement._ghost.visible
		)
		and main.worldheart_presenter._offering_preview.global_position.distance_to(
			main.worldheart_presenter._offering_anchor()
		) < 0.08
		and main.worldheart_presenter._well_is_stirred
		and not main.worldheart_presenter.progress_card_sprite.visible,
		"hover stirs the well around a miniature without revealing duplication UI"
	)
	var offer_hole_screen := main.camera_rig.camera.unproject_position(
		main.worldheart_presenter._well_interaction_anchor()
	)
	main._begin_build_pointer(offer_hole_screen)
	check(
		main._worldheart_offer_pointer_pressed
		and not main.placement.held.is_empty()
		and main.worldheart_presenter.has_offering_preview()
		and main.core.diorama.worldheart.contribution_progress("meadow") == 0,
		"pressing over the hole keeps the tile visibly held and never commits early"
	)
	main._finish_build_pointer(offer_hole_screen)
	check(
		main.worldheart_presenter._offering_dropping
		and main.core.diorama.worldheart.contribution_progress("meadow") == 0,
		"release begins a visible fall before ownership or progress changes"
	)
	await get_tree().create_timer(0.82).timeout
	var progress_card_style := (
		main.worldheart_presenter.progress_card.get_theme_stylebox("panel")
		as StyleBoxFlat
	)
	check(
		main.core.diorama.worldheart.contribution_progress("meadow") == 1
		and main.core.stock.tile_count("tile_grass_flower") == 2
		and main.worldheart_presenter.progress_card_sprite.visible
		and main.worldheart_presenter.progress_icon.texture != null
		and main.worldheart_presenter.progress_count_label.text == "1 / 2"
		and main.worldheart_presenter.progress_count_label.get_theme_font("font")
			== main.kit.font_bold
		and progress_card_style != null
		and progress_card_style.bg_color.is_equal_approx(
			Color(main.kit.ui_color("cell"), 0.99)
		)
		and progress_card_style.shadow_size == 0
		and progress_card_style.get_border_width(SIDE_LEFT) == 0
		and not main.worldheart_presenter._well_is_stirred,
		"dropping the first spare shows a tiny flat beige card in the shared UI font"
	)
	main.hud.worldheart_offer_requested.emit("tile", "tile_grass_flower")
	await get_tree().create_timer(0.62).timeout
	check(
		main.core.diorama.worldheart.contribution_progress("meadow") == 0
		and main.core.stock.tile_count("tile_grass_flower") == 1
		and main.worldheart_presenter.progress_count_label.text == "2 / 2",
		"a second offering shows 2 / 2 before visibly spitting out the new member"
	)
	# Drop (0.34s), meter fill (0.34s), and its celebratory hold (0.78s)
	# complete before the directional launch becomes visible.
	await get_tree().create_timer(1.56).timeout
	var spit_is_airborne := false
	if is_instance_valid(main.worldheart_presenter._exchange_reward_visual):
		# The direction is random, so the observable contract is height: the
		# reward is above the mouth, on its way up and out of the well.
		spit_is_airborne = (
			main.worldheart_presenter._exchange_reward_visual.position.y
			> main.worldheart_presenter._well_mouth_anchor().y + 0.10
		)
	check(
		spit_is_airborne and main.worldheart_presenter._well_is_stirred,
		"completed exchanges shoot the new member up out of the well"
	)

	var hole_screen := main.camera_rig.camera.unproject_position(
		main.worldheart_presenter._well_interaction_anchor()
	)
	var destination_screen := main.camera_rig.camera.unproject_position(
		main.core.grid.cell_to_world(Vector2i(1, 1))
	)
	main._begin_build_pointer(hole_screen)
	var drag := InputEventMouseMotion.new()
	drag.position = destination_screen
	main._input(drag)
	var cadence_during_move := (
		main.core.diorama.worldheart.next_pulse_seconds
	)
	main.core.diorama.worldheart.tick(60.0)
	check(
		main.worldheart_presenter._moving_preview
		and main.core.diorama.worldheart.generation_paused()
		and is_equal_approx(
			main.core.diorama.worldheart.next_pulse_seconds,
			cadence_during_move
		)
		and main.worldheart_presenter.progress_card_viewport.render_target_update_mode
			== SubViewport.UPDATE_DISABLED
		and main.renderer._outlined_meshes.is_empty(),
		"pointer movement pauses generation, live card rendering, and the outline pass"
	)
	main._finish_build_pointer(destination_screen)
	check(
		main.core.diorama.worldheart.worldheart_cell == Vector2i(1, 1)
		and not main.core.grid.cell(Vector2i.ZERO).movement_locked
		and main.core.grid.cell(Vector2i(1, 1)).movement_locked
		and not main.core.diorama.worldheart.generation_paused(),
		"click-dragging moves the Worldheart like an ordinary model"
	)
	await get_tree().process_frame
	check(
		main.worldheart_presenter.portal_fx_root.global_position.distance_to(
			main.core.grid.cell_to_world(Vector2i(1, 1)) + Vector3.UP * 0.025
		) < 0.05,
		"the complete well follows the saved host cell"
	)
	# The well is radially symmetric, so its mouth anchor must be rotation
	# independent -- launches go straight up regardless of the quarter turn.
	var anchors_stable := true
	for quarter in 4:
		main.core.diorama.worldheart.worldheart_rotation_quarters = quarter
		anchors_stable = (
			anchors_stable
			and main.worldheart_presenter._well_mouth_anchor().is_equal_approx(
				main.worldheart_presenter._centre()
				+ Vector3.UP * main.worldheart_presenter.WELL_MOUTH_ANCHOR_HEIGHT
			)
		)
	check(
		anchors_stable,
		"the well mouth anchor holds still through all four rotations"
	)
	main.core.diorama.worldheart.worldheart_rotation_quarters = 2
	main.worldheart_presenter._sync_well_rotation(false)

	InputDeviceService.shared().input_method = InputDeviceService.InputMethod.CONTROLLER
	main.placement.set_controller_mode(true)
	main.placement._controller_cell = main.core.diorama.worldheart.worldheart_cell
	var controller_move := InputEventAction.new()
	controller_move.action = &"move_piece"
	controller_move.pressed = true
	main._handle_controller_build_input(controller_move)
	check(
		main._worldheart_controller_move_active
		and main.core.diorama.worldheart.generation_paused(),
		"controller movement owns the same generation pause as pointer movement"
	)
	var controller_cancel := InputEventAction.new()
	controller_cancel.action = &"cancel"
	controller_cancel.pressed = true
	main._handle_controller_build_input(controller_cancel)
	check(
		not main._worldheart_controller_move_active
		and not main.core.diorama.worldheart.generation_paused(),
		"controller cancel restores Worldheart generation"
	)
	main.placement.set_controller_mode(false)
	InputDeviceService.shared().input_method = InputDeviceService.InputMethod.KEYBOARD_MOUSE

	if failures.is_empty():
		print("DIORAMA SCENE PASSED - %d checks" % checks)
	else:
		print("DIORAMA SCENE FAILED - %d/%d failed" % [failures.size(), checks])
	var exit_code := 0 if failures.is_empty() else 1
	main.core.save()
	get_tree().quit(exit_code)


func _stock_count(entry: Dictionary) -> int:
	var content_id := String(entry.get("id", ""))
	return (
		main.core.stock.tile_count(content_id)
		if String(entry.get("kind", "")) == "tile"
		else main.core.stock.structure_count(content_id)
	)
