class_name Main
extends Node
## Boots and wires the whole game: core logic (GameCore), the 3D world
## (renderer/effects/lighting), the player, cameras, placement, UI, and audio.
## Owns global input routing and the handful of cross-cutting flows (weather,
## defeat recovery, landmark encounters, footsteps, tutorial hints).

var palette: CozyPalette
var materials: MaterialLibrary
var assets: AssetLibrary
var kit: UiKit

var core: GameCore
var world_root: Node3D
var lighting: LightingRig
var renderer: WorldRenderer
var effects: EffectsManager
var player: PlayerController
var player_visual: PlayerVisual
var camera_rig: CameraRig
var placement: PlacementController
var skill_actions: SkillActions
var hud: Hud
var panels: GamePanels
var parcel_reveal: ParcelReveal
var audio: GameAudio

var _encounters: Dictionary = {}   # landmark_id -> LandmarkEncounter
var _footstep_accum := 0.0
var _gameplay_started := false


func _ready() -> void:
	palette = load("res://assets/palettes/cozy_diorama_palette.tres")
	materials = MaterialLibrary.new(palette)
	assets = AssetLibrary.new(materials)
	kit = UiKit.new(palette)

	core = GameCore.new()
	core.setup()

	_build_world_scene()
	_build_ui()
	_connect_flows()

	var user_args := OS.get_cmdline_user_args()
	for arg in user_args:
		if arg.begins_with("--save="):   # test harness isolation
			core.save_manager.save_path = arg.trim_prefix("--save=")
			core.save_manager.backup_path = core.save_manager.save_path + ".backup"
	if _handle_dev_shot(user_args):
		return
	if core.save_manager.has_save() and core.load_game():
		_start_gameplay(false)
	else:
		_start_character_creation()


## Dev harness: `godot -- --shot=docs/foo.png [--rain] [--zoom=9] [--creator]`
## boots a fresh throwaway world, waits for frames to settle, captures, quits.
func _handle_dev_shot(user_args: PackedStringArray) -> bool:
	var shot_path := ""
	for arg in user_args:
		if arg.begins_with("--shot="):
			shot_path = arg.trim_prefix("--shot=")
	if shot_path == "":
		return false
	core.save_manager.save_path = "user://shot_throwaway.json"
	core.save_manager.backup_path = "user://shot_throwaway.json.backup"
	var profile := PlayerProfile.new()
	profile.display_name = "Keeper"
	if user_args.has("--creator"):
		_start_character_creation()
	else:
		core.new_game(profile)
		renderer.rebuild_all()
		player.position = core.profile.position
		_start_gameplay(true)
	if user_args.has("--rain"):
		core.grid.add_structure(Vector2i(-1, 0), "struct_campfire", 0, 0)
		core.grid.add_structure(Vector2i(0, 1), "struct_lantern", 2, 0)
		renderer.rebuild_all()
		lighting.apply_profile(lighting.rain_profile)
	for arg in user_args:
		if arg.begins_with("--zoom="):
			camera_rig._size_target = float(arg.trim_prefix("--zoom="))
			camera_rig.camera.size = camera_rig._size_target
	get_tree().create_timer(2.2).timeout.connect(func():
		var image := get_viewport().get_texture().get_image()
		image.save_png(shot_path)
		print("SHOT SAVED: " + shot_path)
		get_tree().quit())
	return true


# ------------------------------------------------------------------ scene assembly

func _build_world_scene() -> void:
	world_root = Node3D.new()
	world_root.name = "GameWorld"
	add_child(world_root)

	lighting = (load("res://scenes/visual/GardenStyleLightingRig.tscn") as PackedScene).instantiate()
	world_root.add_child(lighting)

	renderer = WorldRenderer.new()
	renderer.name = "WorldRenderer"
	world_root.add_child(renderer)

	effects = EffectsManager.new()
	effects.name = "Effects"
	world_root.add_child(effects)
	effects.setup(assets)

	player = PlayerController.new()
	player.name = "Player"
	var capsule := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.1
	capsule.shape = shape
	capsule.position.y = 0.56
	player.add_child(capsule)
	player_visual = PlayerVisual.new()
	player_visual.name = "Visual"
	player.add_child(player_visual)
	world_root.add_child(player)
	player_visual.build(assets, palette)

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	world_root.add_child(camera_rig)
	camera_rig.setup(core, player)

	placement = PlacementController.new()
	placement.name = "Placement"
	world_root.add_child(placement)
	placement.setup(core, assets, camera_rig, player, effects)

	skill_actions = SkillActions.new()
	skill_actions.name = "SkillActions"
	add_child(skill_actions)

	audio = GameAudio.new()
	audio.name = "Audio"
	add_child(audio)

	renderer.setup(core, assets)
	player.setup(core, camera_rig, player_visual)
	skill_actions.setup(core, player, player_visual, effects)
	player_visual.apply_profile(core.profile)
	player_visual.apply_equipment(core.equipment)


func _build_ui() -> void:
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(core, kit, placement)

	panels = GamePanels.new()
	panels.name = "Panels"
	add_child(panels)
	panels.setup(core, kit, self)

	parcel_reveal = ParcelReveal.new()
	parcel_reveal.name = "ParcelReveal"
	add_child(parcel_reveal)
	parcel_reveal.setup(core, kit)


func _connect_flows() -> void:
	hud.open_parcel_requested.connect(func():
		audio.play_event("parcel_open")
		parcel_reveal.open_best_available())
	hud.build_piece_selected.connect(func(kind, id):
		audio.play_event("build_preview")
		placement.hold_new(kind, id))
	parcel_reveal.reveal_finished.connect(_on_tile_chosen)
	core.parcels.options_revealed.connect(func(_p, _o): audio.play_event("parcel_reveal"))
	panels.landmark_resolution_chosen.connect(_on_landmark_resolution)
	panels.panel_toggled.connect(func(_n, open): audio.play_event("panel_open" if open else "panel_close"))

	skill_actions.action_feedback.connect(_on_action_feedback)
	skill_actions.storage_requested.connect(func(): panels.toggle("inventory"))
	skill_actions.landmark_prompt_requested.connect(func(node):
		panels.show_landmark_choice(String(node.get_meta("landmark_id"))))

	placement.action_result.connect(_on_placement_result)
	player.interaction_focus_changed.connect(_on_focus_changed)

	core.skills.level_up.connect(func(_s, _l, _u):
		audio.play_event("levelup")
		player_visual.play("celebrate")
		hud.update_tutorial())
	core.collection.discovered.connect(func(_c, _i): audio.play_event("discovery"))
	core.combat.health_changed.connect(_on_health_changed)
	core.combat.player_defeated.connect(_on_player_defeated)
	core.combat.enemy_hit.connect(func(_s, _r): audio.play_event("enemy_hit"))
	core.combat.enemy_defeated.connect(_on_enemy_defeated)
	core.landmarks.opportunity_appeared.connect(_on_opportunity)
	core.landmarks.landmark_revealed.connect(_on_landmark_revealed)
	core.landmarks.landmark_reclaimed.connect(_on_landmark_reclaimed)
	core.rewards.loot_granted.connect(_on_loot)
	lighting.profile_applied.connect(_on_profile_applied)
	if lighting.current_profile != null:
		_on_profile_applied(lighting.current_profile)


# ------------------------------------------------------------------ boot flows

func _start_character_creation() -> void:
	var creator := CharacterCreator.new()
	creator.name = "Creator"
	add_child(creator)
	core.profile = creator.profile
	creator.setup(kit, palette, func(profile):
		player_visual.apply_profile(profile))
	# A pleasant preview world sits behind the creator.
	core._compose_starting_world()
	renderer.rebuild_all()
	player.position = core.grid.cell_to_world(Vector2i.ZERO)
	camera_rig.zoom_for_creator()
	player.set_state(PlayerController.State.DISABLED)
	creator.creation_finished.connect(_on_creation_finished)


func _on_creation_finished(profile: PlayerProfile) -> void:
	core.new_game(profile)
	renderer.rebuild_all()
	player_visual.apply_profile(profile)
	player.position = profile.position
	camera_rig.restore_gameplay_zoom()
	_start_gameplay(true)


func _start_gameplay(fresh: bool) -> void:
	_gameplay_started = true
	player.set_state(PlayerController.State.FREE)
	player_visual.apply_equipment(core.equipment)
	if not fresh:
		renderer.rebuild_all()
		player.position = core.profile.position
		player.rotation.y = core.profile.facing
		player_visual.apply_profile(core.profile)
		player_visual.apply_equipment(core.equipment)
		_spawn_saved_encounters()
		hud._refresh_all()
	hud.update_tutorial()
	hud.toast("Welcome%s, %s." % ["" if fresh else " back", core.profile.display_name], "good")


func _process(delta: float) -> void:
	if not _gameplay_started:
		return
	core.tick(delta)
	_tick_footsteps(delta)
	_tick_anchor_visuals()


func _tick_footsteps(delta: float) -> void:
	var speed := Vector3(player.velocity.x, 0, player.velocity.z).length()
	if speed < 1.0 or not player.is_on_floor():
		return
	_footstep_accum += delta * speed
	if _footstep_accum >= 1.9:
		_footstep_accum = 0.0
		var def := core.grid.tile_def(player.current_cell())
		var surface := "stone" if def != null and def.placement_sound == "stone" else "grass"
		audio.play_event("footstep_" + surface)


var _anchor_watch: Dictionary = {}

## Grove regrow pop: when a resting anchor finishes, bounce its vegetation back.
func _tick_anchor_visuals() -> void:
	for coord: Vector2i in core.grid.cells:
		var state := core.grid.cell(coord)
		var was_resting: bool = _anchor_watch.get(coord, false)
		if was_resting and not state.anchor_resting:
			renderer.refresh_anchor(coord)
			audio.play_event("leaf_rustle")
		_anchor_watch[coord] = state.anchor_resting


# ------------------------------------------------------------------ input routing

func _unhandled_input(event: InputEvent) -> void:
	if not _gameplay_started:
		return
	if event.is_action_pressed("debug_panel") and OS.is_debug_build():
		panels.toggle("debug")
	elif event.is_action_pressed("build_mode"):
		skill_actions.cancel_all()
		placement.toggle()
	elif event.is_action_pressed("rotate_piece"):
		placement.rotate_held()
		if placement.active:
			audio.play_event("build_rotate")
	elif event.is_action_pressed("undo"):
		placement.undo()
	elif event.is_action_pressed("redo"):
		placement.redo()
	elif event.is_action_pressed("panel_inventory"):
		panels.toggle("inventory")
	elif event.is_action_pressed("panel_character"):
		panels.toggle("character")
	elif event.is_action_pressed("panel_skills"):
		panels.toggle("skills")
	elif event.is_action_pressed("panel_collection"):
		panels.toggle("collection")
	elif event.is_action_pressed("panel_map"):
		panels.toggle("map")
	elif event.is_action_pressed("return_home"):
		_return_home()
	elif event.is_action_pressed("interact"):
		if placement.active:
			placement.click()
		else:
			skill_actions.try_interact()
	elif event.is_action_pressed("cancel"):
		if panels.is_open():
			panels.close()
		elif placement.active:
			placement.cancel_click()
		else:
			skill_actions.cancel_all()
			player.set_state(PlayerController.State.FREE)
	elif event is InputEventMouseButton and event.pressed:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if placement.active:
				placement.click()
			else:
				skill_actions.try_interact()
		elif mouse.button_index == MOUSE_BUTTON_RIGHT:
			if placement.active:
				placement.cancel_click()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_X and placement.active:
			placement.store_held()
			audio.play_event("store")


# ------------------------------------------------------------------ cross-cutting flows

func _on_action_feedback(kind: String, data: Dictionary) -> void:
	match kind:
		"fish_cast":
			audio.play_event("fish_cast")
		"fish_bite":
			audio.play_event("fish_bite")
		"fish_catch":
			audio.play_event("fish_catch")
			_reward_sound(data.get("grants", []))
			hud.update_tutorial()
		"chop_windup":
			audio.play_event("chop_windup")
		"chop_impact":
			audio.play_event("chop_impact")
			_reward_sound(data.get("grants", []))
			hud.update_tutorial()
		"grove_rest":
			audio.play_event("grove_rest")
			renderer.refresh_anchor(data["coord"])
		"tool_equip":
			audio.play_event("tool_equip")


func _reward_sound(grants: Array) -> void:
	for grant in grants:
		if bool(grant.get("rare", false)):
			audio.play_event("reward_rare")
			return
	if not grants.is_empty():
		audio.play_event("reward_common")


func _on_loot(grants: Array) -> void:
	for grant in grants:
		if String(grant.get("item_id", "")).begins_with("parcel_"):
			audio.play_event("parcel_appear")
			hud.update_tutorial()


func _on_tile_chosen(tile_id: String) -> void:
	audio.play_event("parcel_select")
	hud.update_tutorial()
	hud.toast("%s added to your build storage." % core.registries.tile(tile_id).display_name, "good")
	placement.hold_new("tile", tile_id)


func _on_placement_result(ok: bool, _message: String, kind: String) -> void:
	if kind.begins_with("place_"):
		audio.play_event(kind if ok else "build_invalid")
		hud.update_tutorial()
	elif kind == "invalid":
		audio.play_event("build_invalid")
	elif kind in ["undo", "redo", "pickup"]:
		audio.play_event("undo" if kind == "undo" else "redo" if kind == "redo" else "pickup")


func _on_focus_changed(focus: Dictionary) -> void:
	match focus.get("kind", ""):
		"anchor":
			var anchor: Defs.AnchorDefinition = focus["anchor"]
			var skill := core.registries.skill(anchor.skill_id)
			hud.set_prompt("E — %s (%s)" % [skill.display_name, anchor.display_name])
		"storage":
			hud.set_prompt("E — open storage")
		"enemy":
			hud.set_prompt("E — attack   ·   Space — dodge")
		"landmark_prompt":
			hud.set_prompt("E — claim the watchpost")
		_:
			hud.set_prompt("")


func _on_health_changed(current: int, _maximum: int) -> void:
	if current < core.combat.max_health:
		audio.play_event("hurt")


func _on_player_defeated() -> void:
	hud.toast("The world catches you. You wake at home, whole.", "warn")
	var fade := ColorRect.new()
	fade.color = Color(0.1, 0.1, 0.08, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.add_child(fade)
	var tween := fade.create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.4)
	tween.tween_callback(func(): player.teleport_home())
	tween.tween_property(fade, "color:a", 0.0, 0.5)
	tween.tween_callback(fade.queue_free)


func _on_enemy_defeated(slot_id: String, grants: Array) -> void:
	var enemy_id := slot_id.get_slice(":", 0)
	var def := core.registries.enemy(enemy_id)
	audio.play_event("guardian_defeat" if def != null and def.guardian else "enemy_defeat")
	_reward_sound(grants)


func _on_opportunity(state: LandmarkManager.LandmarkState) -> void:
	var def := core.registries.landmark(state.landmark_id)
	hud.toast("Something dark stands in the fog… (check the map, M)", "rare")
	audio.play_event("parcel_appear")


func _on_landmark_revealed(state: LandmarkManager.LandmarkState) -> void:
	hud.toast("The fog pulls back — %s is awake." % core.registries.landmark(state.landmark_id).display_name, "warn")
	audio.play_event("enemy_telegraph")
	_spawn_encounter(state)


func _on_landmark_reclaimed(state: LandmarkManager.LandmarkState) -> void:
	audio.play_event("landmark_reclaimed")
	hud.toast("%s is peaceful now. It's yours." % core.registries.landmark(state.landmark_id).display_name, "levelup")
	core.autosave_soon()


func _on_landmark_resolution(landmark_id: String, resolution: String) -> void:
	var state := core.landmarks.state_for(landmark_id)
	if state != null:
		core.landmarks.resolve(state, resolution)
		match resolution:
			"packed":
				hud.toast("Packed into a deed — rebuild it from Build mode.", "good")
			"salvaged":
				hud.toast("Salvaged. The old stones will build something new.", "good")
			_:
				hud.toast("It stays — a watchtower for your little world.", "good")


func _spawn_encounter(state: LandmarkManager.LandmarkState) -> void:
	if _encounters.has(state.landmark_id):
		return
	var encounter := LandmarkEncounter.new()
	encounter.name = "encounter_" + state.landmark_id
	world_root.add_child(encounter)
	encounter.setup(core, assets, state, player)
	_encounters[state.landmark_id] = encounter


func _spawn_saved_encounters() -> void:
	for state in core.landmarks.active:
		if state.phase != LandmarkManager.PHASE_SILHOUETTE:
			_spawn_encounter(state)


func _return_home() -> void:
	player.teleport_home()
	hud.toast("Home again.", "good")


# ------------------------------------------------------------------ settings bridge (panels call these)

func toggle_weather() -> void:
	lighting.toggle_profile()


func _on_profile_applied(profile: VisualStyleProfile) -> void:
	audio.set_rain(profile.rain_enabled)
	hud.apply_weather_contrast(profile.rain_enabled)
	for light in get_tree().get_nodes_in_group("warm_lights"):
		var omni := light as OmniLight3D
		omni.light_energy = float(omni.get_meta("base_energy", 1.0)) * (1.0 if profile.rain_enabled else profile.local_light_multiplier)


func reload_from_save() -> void:
	if core.load_game():
		renderer.rebuild_all()
		player.position = core.profile.position
		player_visual.apply_profile(core.profile)
		player_visual.apply_equipment(core.equipment)
		for encounter in _encounters.values():
			encounter.queue_free()
		_encounters.clear()
		_spawn_saved_encounters()
		hud._refresh_all()
		hud.toast("Save reloaded.", "good")


func reset_world() -> void:
	core.save_manager.delete_save()
	get_tree().reload_current_scene()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _gameplay_started:
		core.save()
