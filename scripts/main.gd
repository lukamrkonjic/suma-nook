extends Node

const GameDataScript := preload("res://scripts/game_data.gd")
const GridManagerScript := preload("res://scripts/grid_manager.gd")
const GridRendererScript := preload("res://scripts/grid_renderer.gd")
const EconomyScript := preload("res://scripts/economy_manager.gd")
const StorageScript := preload("res://scripts/storage_manager.gd")
const CollectionScript := preload("res://scripts/collection_manager.gd")
const RewardScript := preload("res://scripts/reward_manager.gd")
const SaveScript := preload("res://scripts/save_manager.gd")
const AudioScript := preload("res://scripts/audio_manager.gd")
const CameraScript := preload("res://scripts/camera_rig.gd")
const PlacementScript := preload("res://scripts/placement_controller.gd")
const VisitorScript := preload("res://scripts/visitor_manager.gd")
const GroveheartScript := preload("res://scripts/groveheart.gd")
const HudScript := preload("res://scripts/hud.gd")
const EffectsScript := preload("res://scripts/effects_manager.gd")
const WorldBuilderScript := preload("res://scripts/world_builder.gd")
const PlayerScript := preload("res://scripts/player_character.gd")
const ProgressionScript := preload("res://scripts/forest_progression.gd")
const ItemScene := preload("res://scenes/build_item.tscn")

const INTERNAL_SIZE := Vector2i(1280, 720)
const WORLD_SEED := 730291

var viewport_container: SubViewportContainer
var game_viewport: SubViewport
var world: Node3D
var placed_root: Node3D
var reward_root: Node3D
var game_data: GameData
var grid: GridManager
var grid_renderer: GridRenderer
var economy: EconomyManager
var storage: StorageManager
var collection: CollectionManager
var rewards: RewardManager
var save_manager: TilegardenSaveManager
var audio: TilegardenAudioManager
var camera_rig: TilegardenCameraRig
var placement: PlacementController
var visitors: VisitorManager
var groveheart: Groveheart
var hud: TilegardenHUD
var effects: EffectsManager
var environment_style: WorldBuilder
var player: SumaPlayerCharacter
var progression: ForestProgression
var waiting_reward: BuildItem
var world_seed := WORLD_SEED
var autosave_elapsed := 0.0
var _loaded_timestamp := 0.0
var _showcase_mode := ""
var _force_fresh := false
var _capture_path := ""
var _capture_frame := 90
var _frame_count := 0
var _loaded_state: Dictionary = {}
var _pending_reward_id := &""
var _pending_reward_token := &""
var _pending_reward_first_time := false
var _performance_probe := false
var _probe_started_usec := 0
var _onboarding_visitor_announced := false
var character_created := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_command_line()
	_build_viewport()
	_build_systems()
	_load_or_create()
	_connect_signals()
	audio.setup()
	_wire_ui_audio()
	effects.setup_ambient()
	visitors.setup(grid, game_data, world_seed)
	if _loaded_timestamp > 0.0:
		var away := maxf(0.0, Time.get_unix_time_from_system() - _loaded_timestamp)
		var offline_count := mini(
			int(game_data.tuning.get("offline_visitor_cap", 4)),
			int(floor(away / maxf(1.0, float(game_data.tuning.get("visitor_interval_max", 14.0)))))
		)
		visitors.add_offline_visitors(offline_count)
	_apply_showcase_mode()
	_probe_started_usec = Time.get_ticks_usec()


func _process(delta: float) -> void:
	_frame_count += 1
	autosave_elapsed += delta
	if placement.is_holding():
		placement.update_preview(game_viewport.get_mouse_position())
	if autosave_elapsed >= float(game_data.tuning.get("autosave_interval", 45.0)):
		autosave_elapsed = 0.0
		save_game(false)
	if not _capture_path.is_empty() and _frame_count == _capture_frame:
		var image := game_viewport.get_texture().get_image()
		var path := ProjectSettings.globalize_path(_capture_path)
		var error := image.save_png(path)
		print("CAPTURE %s: %s" % [_capture_path, error_string(error)])
		get_tree().quit(0 if error == OK else 1)
	if _performance_probe and _frame_count == 600:
		var elapsed := float(Time.get_ticks_usec() - _probe_started_usec) / 1_000_000.0
		print("PERF_PROBE frames=600 elapsed=%.3fs average_fps=%.1f current_fps=%.1f draw_calls=%d objects=%d" % [
			elapsed,
			600.0 / maxf(elapsed, 0.001),
			Performance.get_monitor(Performance.TIME_FPS),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		])
		get_tree().quit(0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and save_manager != null:
		save_game(false)
		get_tree().quit()


func _build_viewport() -> void:
	viewport_container = SubViewportContainer.new()
	viewport_container.name = "GameViewportContainer"
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_container.stretch_shrink = 1
	viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(viewport_container)
	game_viewport = SubViewport.new()
	game_viewport.name = "GameViewport1280x720"
	game_viewport.size = INTERNAL_SIZE
	game_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	game_viewport.handle_input_locally = true
	game_viewport.physics_object_picking = true
	game_viewport.msaa_3d = Viewport.MSAA_DISABLED
	game_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	game_viewport.use_taa = false
	game_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport_container.add_child(game_viewport)
	world = Node3D.new()
	world.name = "WorldRoot"
	game_viewport.add_child(world)
	environment_style = WorldBuilderScript.new()
	world.add_child(environment_style)
	environment_style.setup()
	placed_root = Node3D.new()
	placed_root.name = "PlacedItemsRoot"
	world.add_child(placed_root)
	reward_root = Node3D.new()
	reward_root.name = "RewardRoot"
	world.add_child(reward_root)


func _build_systems() -> void:
	game_data = GameDataScript.new()
	if not game_data.load_all():
		push_error("Tilegarden data failed to load.")
		return
	grid = GridManagerScript.new()
	add_child(grid)
	grid.setup(game_data)
	economy = EconomyScript.new()
	add_child(economy)
	economy.setup(game_data)
	storage = StorageScript.new()
	add_child(storage)
	storage.setup(game_data)
	collection = CollectionScript.new()
	add_child(collection)
	collection.setup(game_data)
	rewards = RewardScript.new()
	add_child(rewards)
	rewards.setup(game_data, world_seed)
	save_manager = SaveScript.new()
	add_child(save_manager)
	save_manager.setup(int(game_data.tuning.get("save_version", 1)))
	audio = AudioScript.new()
	add_child(audio)
	camera_rig = CameraScript.new()
	world.add_child(camera_rig)
	camera_rig.setup()
	grid_renderer = GridRendererScript.new()
	grid_renderer.name = "GridRoot"
	placed_root.add_child(grid_renderer)
	groveheart = GroveheartScript.new()
	world.add_child(groveheart)
	groveheart.position = grid.world_position(Vector3i(0, 1, 0))
	groveheart.setup()
	groveheart.visible = false
	effects = EffectsScript.new()
	effects.name = "EffectsRoot"
	world.add_child(effects)
	visitors = VisitorScript.new()
	visitors.name = "VisitorsRoot"
	world.add_child(visitors)
	placement = PlacementScript.new()
	game_viewport.add_child(placement)
	placement.setup(grid, game_data, grid_renderer, camera_rig, world, storage, economy)
	hud = HudScript.new()
	game_viewport.add_child(hud)
	hud.setup(game_data, economy, storage, collection, grid)
	progression = ProgressionScript.new()
	add_child(progression)


func _load_or_create() -> void:
	var state := {} if _force_fresh else save_manager.read_save()
	_loaded_state = state
	if state.is_empty():
		grid.make_initial_island(int(game_data.tuning.get("initial_island_radius", 2)))
		economy.add(&"meadow_coin", 1)
	else:
		var missing: Array[String] = []
		world_seed = int(state.get("world_seed", WORLD_SEED))
		grid.restore_snapshot(state.get("grid", {}), missing)
		economy.restore_snapshot(state.get("economy", {}))
		storage.restore_snapshot(state.get("storage", {}), missing)
		collection.restore_snapshot(state.get("collection", {}), missing)
		rewards.restore_snapshot(state.get("rewards", {}))
		camera_rig.restore_snapshot(state.get("camera", {}))
		environment_style.set_preset(StringName(str(state.get("environment_preset", "greenwood"))))
		_restore_audio_snapshot(state.get("audio", {}))
		_loaded_timestamp = float(state.get("timestamp", 0.0))
		if not missing.is_empty():
			hud.show_toast("Loaded safely; unavailable definitions were skipped: %s" % ", ".join(missing), false)
	grid_renderer.setup(grid, game_data)
	progression.setup(grid, economy, storage, collection, world_seed)
	if not state.is_empty():
		progression.restore_snapshot(state.get("progression", {}))
	player = PlayerScript.new()
	world.add_child(player)
	var player_state: Dictionary = state.get("player", {})
	player.setup(
		grid,
		str(player_state.get("name", "Fern")),
		player_state.get("appearance", {"skin": 1, "hair": 0, "outfit": 0}),
		Vector3i(0, 1, 0)
	)
	if not player_state.is_empty():
		player.restore_snapshot(player_state)
	character_created = not player_state.is_empty()
	player.can_control = not state.is_empty()
	if state.is_empty() and _showcase_mode.is_empty():
		hud.call_deferred("show_character_creator")
	elif state.is_empty():
		player.can_control = true
		character_created = true
	_update_modifier_summary()
	hud.set_scene_name(environment_style.display_name())
	_update_forest_progress()
	var state_after_render := _loaded_state
	if not state_after_render.is_empty():
		visitors.call_deferred("restore_snapshot", state_after_render.get("visitors", []))
		var held_state: Dictionary = state_after_render.get("held_item", {})
		if not held_state.is_empty():
			placement.call_deferred("restore_held", held_state)
		else:
			var pending: Dictionary = state_after_render.get("pending_reward", {})
			var pending_id := StringName(str(pending.get("definition_id", "")))
			var pending_token := StringName(str(pending.get("token_id", "meadow_coin")))
			if pending_id != &"" and game_data.item(pending_id) != null:
				_pending_reward_id = pending_id
				_pending_reward_token = pending_token
				call_deferred("_resume_pending_reward")
			elif pending_id != &"":
				economy.add(pending_token, 1)
				hud.show_toast("An unavailable reward was safely returned as a coin.", false)


func _resume_pending_reward() -> void:
	if _pending_reward_id != &"":
		_spawn_waiting_reward(_pending_reward_id, false)


func _connect_signals() -> void:
	hud.seed_drag_released.connect(_on_seed_drag_released)
	hud.offer_pressed.connect(offer_seed)
	hud.retrieve_requested.connect(func(id: StringName) -> void:
		if placement.begin_from_storage(id):
			audio.play(&"pickup")
			hud.show_toast("Place %s in the garden." % game_data.item(id).display_name))
	hud.store_requested.connect(func() -> void: placement.store_current())
	hud.recycle_requested.connect(func() -> void: placement.recycle_current())
	hud.cancel_requested.connect(placement.cancel)
	hud.focus_requested.connect(camera_rig.focus_world)
	hud.save_requested.connect(func() -> void: save_game(true))
	hud.storage_toggled.connect(func() -> void: audio.play(&"ui_confirm"))
	hud.collection_toggled.connect(func() -> void: audio.play(&"collection_open"))
	hud.settings_requested.connect(func() -> void: audio.play(&"ui_confirm"))
	hud.scene_requested.connect(_cycle_environment)
	hud.grow_requested.connect(start_growth)
	hud.character_confirmed.connect(_on_character_confirmed)
	placement.hold_changed.connect(func(active: bool, definition_id: StringName) -> void:
		hud.set_held(definition_id if active else &"")
		if player != null:
			player.can_control = not active and not hud.character_overlay.visible)
	placement.action_feedback.connect(func(message: String, positive: bool) -> void:
		hud.show_toast(message, positive)
		audio.play(&"valid_drop" if positive else &"invalid_drop"))
	placement.placement_completed.connect(_on_placement_completed)
	placement.item_stored.connect(func(_id: StringName) -> void:
		audio.play(&"storage")
		save_game(false))
	placement.item_recycled.connect(func(_id: StringName, _value: int) -> void:
		audio.play(&"recycling")
		effects.burst(groveheart.global_position + Vector3(0, 0.7, 0), &"sparks")
		save_game(false))
	grid.grid_changed.connect(_update_modifier_summary)
	grid.grid_changed.connect(_update_forest_progress)
	economy.tokens_changed.connect(func(_token: StringName, _amount: int) -> void: _update_forest_progress())
	camera_rig.rotated.connect(func() -> void: audio.play(&"camera_rotate"))
	visitors.seed_launch_requested.connect(_on_mote_seed_launch)
	visitors.mote_clicked.connect(func(_mote: Mote) -> void:
		audio.play(&"mote_click")
		audio.play(&"seed_appears", 0.02, -1.0))
	visitors.mote_spawned.connect(func(mote: Mote) -> void:
		effects.magical_boundary(mote.global_position)
		audio.play(&"mote_chirp", 0.07, -2.0)
		if not _onboarding_visitor_announced:
			_onboarding_visitor_announced = true
			hud.show_toast("A woodland wisp brought Forest Light — click the wisp to collect it.", true))
	save_manager.save_failed.connect(func(message: String) -> void: hud.show_toast(message, false))
	progression.discovery_unlocked.connect(func(definition_id: StringName, message: String) -> void:
		var definition := game_data.item(definition_id)
		hud.show_toast("%s  %s is now in your pack." % [message, definition.display_name], true)
		audio.play(&"discovery")
		_update_forest_progress())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if camera_rig.panning:
			camera_rig.update_pan(event.position)
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_rig.zoom_by(-1.0)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_rig.zoom_by(1.0)
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				camera_rig.begin_pan(event.position)
			else:
				camera_rig.end_pan()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if placement.is_holding():
				placement.cancel()
			else:
				hud.close_panels()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not hud.pointer_over_ui():
			if placement.is_holding():
				if _screen_over_groveheart(event.position):
					placement.recycle_current()
				else:
					placement.confirm()
				return
			var mote := _pick_mote_at(event.position)
			if mote != null and visitors.collect(mote):
				audio.play(&"mote_click")
				audio.play(&"seed_appears", 0.02, -1.0)
				return
			var item := placement.pick_build_item_at(event.position)
			if item != null:
				if item.instance_id == "reward-waiting":
					claim_waiting_reward()
					return
				if item.definition != null and item.definition.is_ground() and player != null and player.can_control:
					player.move_to(Vector3i(item.grid_coord.x, 1, item.grid_coord.z))
					return
				if placement.begin_move(item):
					audio.play(&"pickup")
					item.animate_pickup()
					return
			if player != null and player.can_control:
				var world_point := camera_rig.screen_to_ground(event.position, 0.08)
				var walk_coord := grid.coord_from_world(world_point)
				if grid.ground.has(Vector3i(walk_coord.x, 0, walk_coord.z)):
					player.move_to(Vector3i(walk_coord.x, 1, walk_coord.z))
					return
	if event is InputEventKey and event.pressed and not event.echo:
		var command: bool = event.ctrl_pressed or event.meta_pressed
		if command and event.keycode == KEY_Z:
			if event.shift_pressed:
				if placement.redo():
					audio.play(&"redo")
			else:
				if placement.undo():
					audio.play(&"undo")
			return
		match event.keycode:
			KEY_ESCAPE:
				if placement.is_holding():
					placement.cancel()
				else:
					hud.close_panels()
			KEY_R:
				placement.rotate_held()
				audio.play(&"rotate")
			KEY_Q:
				camera_rig.rotate_quarter(-1)
			KEY_E:
				camera_rig.rotate_quarter(1)
			KEY_F:
				camera_rig.focus_world()
			KEY_DELETE, KEY_BACKSPACE:
				if placement.is_holding():
					placement.store_current()
			KEY_S:
				if command:
					save_game(true)
				elif player != null:
					player.try_step(Vector3i(0, 0, 1))
			KEY_W, KEY_UP:
				if player != null:
					player.try_step(Vector3i(0, 0, -1))
			KEY_A, KEY_LEFT:
				if player != null:
					player.try_step(Vector3i(-1, 0, 0))
			KEY_D, KEY_RIGHT:
				if player != null:
					player.try_step(Vector3i(1, 0, 0))
			KEY_DOWN:
				if player != null:
					player.try_step(Vector3i(0, 0, 1))
			KEY_G:
				start_growth()


func _pick_mote_at(screen_position: Vector2) -> Mote:
	var origin := camera_rig.camera.project_ray_origin(screen_position)
	var end := origin + camera_rig.camera.project_ray_normal(screen_position) * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, end, 4)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := camera_rig.camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider := hit.get("collider") as Area3D
	if collider != null and collider.has_meta("mote"):
		return collider.get_meta("mote") as Mote
	return null


func _screen_over_groveheart(screen_position: Vector2) -> bool:
	var origin := camera_rig.camera.project_ray_origin(screen_position)
	var end := origin + camera_rig.camera.project_ray_normal(screen_position) * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, end, 2)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := camera_rig.camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider := hit.get("collider") as Area3D
		if collider != null and collider.has_meta("groveheart"):
			return true
	return camera_rig.world_to_screen(groveheart.global_position + Vector3(0, 0.8, 0)).distance_to(screen_position) < 34.0


func _on_seed_drag_released(token_id: StringName, screen_position: Vector2) -> void:
	if _screen_over_groveheart(screen_position):
		offer_seed(token_id)
	else:
		hud.show_toast("Drop the coin on the Bloomforge to spend it.", false)


func start_growth() -> bool:
	if progression == null or player == null:
		return false
	if placement.is_holding():
		hud.show_toast("Finish placing the current piece first.", false)
		return false
	if not progression.can_grow():
		hud.show_toast("You need Forest Light. Click a glowing woodland wisp to gather one.", false)
		return false
	var sample_coord := player.grid_coord + Vector3i(progression.tiles_grown + 2, 0, 1)
	var ground_id := progression.next_ground_id(sample_coord)
	if not placement.begin_growth(ground_id):
		return false
	audio.play(&"pickup")
	hud.show_toast("Choose any glowing empty edge. One Forest Light grows one new tile.", true)
	return true


func _on_character_confirmed(player_name: String, appearance: Dictionary) -> void:
	player.set_appearance(player_name, appearance)
	character_created = true
	player.can_control = true
	hud.show_toast("Welcome, %s. Walk the nine tiles, meet a wisp, then grow beyond the clearing." % player.display_name, true)
	save_game(false)


func _update_forest_progress() -> void:
	if progression == null or hud == null or grid == null:
		return
	hud.set_forest_progress(
		progression.forest_light(),
		grid.ground.size(),
		progression.next_milestone_text()
	)


func offer_seed(token_id: StringName) -> void:
	if groveheart.busy or placement.is_holding() or _pending_reward_id != &"":
		hud.show_toast("Place or store the waiting piece first.", false)
		return
	if not economy.spend(token_id, 1):
		hud.show_toast("No %s is ready to offer." % game_data.token(token_id).display_name, false)
		return
	_pending_reward_id = rewards.draw(token_id, _reward_context())
	_pending_reward_token = token_id
	var pending_definition := game_data.item(_pending_reward_id)
	if pending_definition == null:
		_pending_reward_id = &""
		_pending_reward_token = &""
		economy.add(token_id, 1)
		hud.show_toast("The Bloomforge returned the coin safely.", false)
		return
	_pending_reward_first_time = collection.record_obtained(_pending_reward_id)
	save_game(false)
	var target := camera_rig.world_to_screen(groveheart.global_position + Vector3(0, 1.15, 0))
	hud.animate_seed_offer(token_id, target, func() -> void:
		audio.play(&"seed_offered")
		audio.play(&"grove_inhale")
		groveheart.play_offer(func() -> void:
			audio.play(&"grove_pulse")
			_reveal_reward(token_id)))


func _reveal_reward(token_id: StringName) -> void:
	if _pending_reward_id == &"":
		_pending_reward_id = rewards.draw(token_id, _reward_context())
		_pending_reward_token = token_id
		_pending_reward_first_time = collection.record_obtained(_pending_reward_id)
	var definition_id := _pending_reward_id
	var definition := game_data.item(definition_id)
	if definition == null:
		if _pending_reward_token != &"":
			economy.add(_pending_reward_token, 1)
		_pending_reward_id = &""
		_pending_reward_token = &""
		hud.show_toast("The Bloomforge returned the coin safely.", false)
		return
	var first_time := _pending_reward_first_time
	var reveal := ItemScene.instantiate() as BuildItem
	reward_root.add_child(reveal)
	reveal.setup(definition, "reward-reveal", Vector3i.ZERO, 0, grid.tile_size, true)
	reveal.clear_overlay()
	reveal.position = groveheart.position + Vector3(0, 0.72, 0)
	reveal.scale = Vector3.ONE * 0.08
	effects.burst(groveheart.global_position + Vector3(0, 1.0, 0), definition.particle_category, true)
	effects.magical_boundary(groveheart.global_position + Vector3(0, 0.55, 0))
	audio.play(&"reward_reveal")
	if first_time:
		audio.play(&"discovery", 0.02, -1.0)
		hud.show_toast("New discovery — %s!" % definition.display_name, true)
	else:
		hud.show_toast("The Bloomforge made %s." % definition.display_name, true)
	var tween := reveal.create_tween()
	tween.set_parallel(true)
	tween.tween_property(reveal, "position:y", reveal.position.y + 1.0, 0.52).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(reveal, "scale", Vector3.ONE * 0.78, 0.46).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(reveal, "rotation:y", TAU, 0.72).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(0.10)
	tween.chain().tween_callback(func() -> void:
		reveal.queue_free()
		_spawn_waiting_reward(definition_id, true)
		save_game(false))


func _spawn_waiting_reward(definition_id: StringName, animate := true) -> void:
	if waiting_reward != null and is_instance_valid(waiting_reward):
		waiting_reward.queue_free()
	var definition := game_data.item(definition_id)
	if definition == null:
		return
	waiting_reward = ItemScene.instantiate() as BuildItem
	reward_root.add_child(waiting_reward)
	waiting_reward.setup(definition, "reward-waiting", Vector3i.ZERO, 0, grid.tile_size, false)
	waiting_reward.position = groveheart.position + Vector3(1.45, 0.42, 0.52)
	waiting_reward.rotation.y = -0.18
	waiting_reward.scale = Vector3.ONE * (0.10 if animate else 0.82)
	if animate:
		var tween := waiting_reward.create_tween()
		tween.tween_property(waiting_reward, "scale", Vector3.ONE * 0.82, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	hud.show_toast("Click %s to pick it up." % definition.display_name, true)


func claim_waiting_reward() -> bool:
	if _pending_reward_id == &"" or waiting_reward == null:
		return false
	var definition_id := _pending_reward_id
	waiting_reward.queue_free()
	waiting_reward = null
	if not placement.begin_reward(definition_id):
		_spawn_waiting_reward(definition_id, false)
		return false
	_pending_reward_id = &""
	_pending_reward_token = &""
	_pending_reward_first_time = false
	audio.play(&"pickup")
	save_game(false)
	return true


func _on_mote_seed_launch(mote: Mote, token_id: StringName, world_position: Vector3) -> void:
	audio.play(&"seed_travel", 0.03, -2.0)
	effects.burst(world_position, &"sparks")
	var start := camera_rig.world_to_screen(world_position)
	hud.animate_seed_collection(start, &"meadow_coin", func() -> void:
		economy.add(&"meadow_coin", 1)
		audio.play(&"seed_lands", 0.025)
		mote.reward_delivered()
		hud.show_toast("Forest Light gathered — press G or Grow Tile to expand your nook.", true)
		_update_forest_progress()
		save_game(false))


func _on_placement_completed(definition_id: StringName, source: StringName) -> void:
	var definition := game_data.item(definition_id)
	audio.play(StringName("place_%s" % definition.placement_audio_category))
	effects.burst(grid.world_position(placement.hover_coord) + Vector3(0, 0.15, 0), definition.particle_category)
	if source == &"growth":
		var result := progression.complete_growth()
		if result.is_empty():
			hud.show_toast("The new tile grew, but the light balance changed unexpectedly.", false)
		else:
			hud.show_toast("The greenwood grew to %d tiles." % grid.ground.size(), true)
			camera_rig.target = camera_rig.target.lerp(grid.world_position(placement.hover_coord), 0.24)
		_update_forest_progress()
	save_game(false)


func _reward_context() -> Dictionary:
	var counts: Dictionary = {}
	for state: Dictionary in grid.props.values():
		var id := StringName(str(state.get("definition_id", "")))
		counts[String(id)] = int(counts.get(String(id), 0)) + 1
	return {"placed_definition_counts": counts}


func _update_modifier_summary() -> void:
	if rewards == null or hud == null or grid == null:
		return
	hud.set_modifier_summary(rewards.modifier_summary(_reward_context()))


func _cycle_environment() -> void:
	environment_style.cycle_preset()
	hud.set_scene_name(environment_style.display_name())
	audio.play(&"ui_confirm")
	hud.show_toast("%s scene applied." % environment_style.display_name(), true)
	save_game(false)


func save_game(show_feedback := false) -> void:
	if not _capture_path.is_empty():
		return
	if save_manager == null or grid == null:
		return
	if not character_created:
		return
	var payload := {
		"world_seed": world_seed,
		"grid": grid.snapshot(),
		"economy": economy.snapshot(),
		"storage": storage.snapshot(),
		"collection": collection.snapshot(),
		"rewards": rewards.snapshot(),
		"visitors": visitors.snapshot() if visitors != null else [],
		"camera": camera_rig.snapshot(),
		"environment_preset": String(environment_style.preset_id),
		"held_item": placement.held_snapshot(),
		"pending_reward": {
			"definition_id": String(_pending_reward_id),
			"token_id": String(_pending_reward_token),
		},
		"audio": _audio_snapshot(),
		"player": player.snapshot() if player != null else {},
		"progression": progression.snapshot() if progression != null else {},
	}
	if save_manager.write_save(payload) and show_feedback:
		audio.play(&"save")
		hud.show_toast("Garden saved.", true)


func _audio_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for bus: String in ["Master", "Music", "Ambience", "UI", "SFX", "Creatures"]:
		var index := AudioServer.get_bus_index(bus)
		if index >= 0:
			result[bus] = AudioServer.get_bus_volume_db(index)
	return result


func _restore_audio_snapshot(state: Dictionary) -> void:
	for bus: Variant in state:
		var index := AudioServer.get_bus_index(str(bus))
		if index >= 0:
			AudioServer.set_bus_volume_db(index, clampf(float(state[bus]), -60.0, 6.0))


func _wire_ui_audio() -> void:
	for node: Node in hud.root.find_children("*", "Button", true, false):
		var button := node as Button
		button.mouse_entered.connect(func() -> void: audio.play(&"ui_hover", 0.025, -4.0))
		button.pressed.connect(func() -> void: audio.play(&"ui_confirm", 0.02, -3.0))


func _parse_command_line() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--showcase="):
			_showcase_mode = arg.trim_prefix("--showcase=")
		elif arg.begins_with("--capture="):
			_capture_path = arg.trim_prefix("--capture=")
		elif arg == "--fresh":
			_force_fresh = true
		elif arg == "--perf-probe":
			_performance_probe = true


func _apply_showcase_mode() -> void:
	if _showcase_mode.is_empty():
		return
	match _showcase_mode:
		"initial":
			visitors.spawn_timer = 999.0
			visitors.spawn_mote(&"meadow_coin", Vector3i(1, 1, 1))
			_capture_frame = 90
		"mote":
			visitors.spawn_timer = 999.0
			visitors.spawn_mote(&"meadow_coin", Vector3i(1, 1, 1))
			camera_rig.target = Vector3(0.8, 0, 0.6)
			camera_rig.target_ortho_size = 8.6
			_capture_frame = 52
		"reward":
			_capture_frame = 105
			camera_rig.target_ortho_size = 9.4
			get_tree().create_timer(0.18).timeout.connect(func() -> void:
				_reveal_reward(&"meadow_coin"))
		"placement":
			storage.add(&"root_bench", 1)
			placement.call_deferred("begin_from_storage", &"root_bench")
			_capture_frame = 75
		"expanded":
			_capture_frame = 90
			camera_rig.target_ortho_size = 17.0
			_build_showcase_garden()
		"dusk":
			_capture_frame = 75
			camera_rig.target_ortho_size = 17.0
			environment_style.set_preset(&"firefly_dusk")
			hud.set_scene_name(environment_style.display_name())
			_build_showcase_garden()
		"rain":
			_capture_frame = 75
			camera_rig.target_ortho_size = 17.0
			environment_style.set_preset(&"moss_rain")
			hud.set_scene_name(environment_style.display_name())
			_build_showcase_garden()
		"collection":
			_capture_frame = 75
			for id: StringName in game_data.items:
				if id in [&"ground_grass", &"sapling", &"root_bench", &"glow_lantern", &"moss_rock", &"moonflowers"]:
					collection.record_obtained(id)
			storage.add(&"moss_rock", 3)
			storage.add(&"moonflowers", 2)
			storage.add(&"glow_lantern", 1)
			hud.collection_panel.size = Vector2(760, 540)
			hud.collection_panel.position = Vector2(-380, -265)
			hud.storage_panel.position = Vector2(-402, 92)
			hud.storage_panel.size = Vector2(380, 500)
			hud.collection_panel.visible = true
			hud.storage_panel.visible = true
			hud.rebuild_collection()
			hud.rebuild_storage()


func _build_showcase_garden() -> void:
	for x: int in range(-4, 5):
		for z: int in range(-3, 4):
			var coord := Vector3i(x, 0, z)
			if not grid.ground.has(coord):
				var choices := [&"ground_grass", &"ground_loam", &"ground_stone", &"ground_water"]
				grid.add_ground_unchecked(choices[posmod(x * 3 + z, choices.size())], coord)
	var showcase_props := [
		[&"sapling", Vector3i(-3, 1, -2), 0],
		[&"sapling", Vector3i(3, 1, 2), 0],
		[&"root_bench", Vector3i(2, 1, 1), 1],
		[&"glow_lantern", Vector3i(1, 1, 2), 0],
		[&"mushroom_ring", Vector3i(-2, 1, 2), 0],
		[&"stone_planter", Vector3i(3, 1, -1), 0],
		[&"wish_lantern", Vector3i(-1, 1, -2), 0],
		[&"berry_bush", Vector3i(-3, 1, 0), 0],
		[&"moonflowers", Vector3i(2, 1, -2), 0],
		[&"tea_table", Vector3i(-1, 1, 2), 0],
		[&"seed_crate", Vector3i(4, 1, 0), 0],
		[&"twig_fence", Vector3i(-4, 1, 1), 0],
		[&"old_stump", Vector3i(1, 1, -1), 0],
	]
	for row: Array in showcase_props:
		grid.place_prop(row[0], row[1], row[2])
	progression.tiles_grown = maxi(0, grid.ground.size() - 9)
	grid.grid_changed.emit()
