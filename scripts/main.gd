class_name Main
extends Node
## Boots and wires the whole game: core logic (GameCore), the 3D world
## (renderer/effects/lighting), the player, cameras, placement, UI, and audio.
## Owns global input routing and the handful of cross-cutting flows (weather,
## defeat recovery, landmark encounters, footsteps, tutorial hints).

const InteractionTargetResolverScript := preload(
	"res://scripts/world/interaction_target_resolver.gd"
)

var palette: CozyPalette
var materials: MaterialLibrary
var assets: AssetLibrary
var kit: UiKit

var core: GameCore
var world_root: Node3D
var lighting: LightingRig
var renderer: WorldRenderer
var effects: EffectsManager
var delivery_point: DeliveryPoint
var ferry_presentation: FerryArrivalPresentation
var player: PlayerController
var player_visual: PlayerVisual
var camera_rig: CameraRig
var placement: PlacementController
var skill_actions: SkillActions
var hud: Hud
var pixel_look: PixelLook
const LightingTunerScript := preload("res://scripts/ui/lighting_tuner.gd")
var lighting_tuner: CanvasLayer
var panels: GamePanels
var pause_menu: PauseMenu
var parcel_reveal: ParcelReveal
var audio: GameAudio
var interaction_targets
var save_path_override := ""  # injected before _ready by isolated scene tests

var _encounters: Dictionary = {}   # landmark_id -> LandmarkEncounter
var _footstep_accum := 0.0
var _gameplay_started := false
var _celebration_pending := false


func _ready() -> void:
	palette = load("res://assets/palettes/gg_material_palette.tres")
	materials = MaterialLibrary.new(palette)
	assets = AssetLibrary.new(materials)
	kit = UiKit.new(palette)

	core = GameCore.new()
	core.setup()
	if save_path_override != "":
		core.save_manager.save_path = save_path_override
		core.save_manager.backup_path = save_path_override + ".backup"

	_build_world_scene()
	_build_ui()
	_connect_flows()

	if core.save_manager.has_save() and core.load_game():
		_start_gameplay(false)
	else:
		_start_character_creation()


# ------------------------------------------------------------------ scene assembly

func _build_world_scene() -> void:
	world_root = Node3D.new()
	world_root.name = "GameWorld"
	add_child(world_root)

	lighting = (load("res://scenes/visual/SumaSoftDaylight.tscn") as PackedScene).instantiate()
	world_root.add_child(lighting)

	renderer = WorldRenderer.new()
	renderer.name = "WorldRenderer"
	world_root.add_child(renderer)

	effects = EffectsManager.new()
	effects.name = "Effects"
	world_root.add_child(effects)
	effects.setup(assets)

	delivery_point = DeliveryPoint.new()
	world_root.add_child(delivery_point)
	delivery_point.setup(
		materials,
		core.grid.tile_size,
		Vector3(0, 0, -1),
		assets,
		core.grid
	)

	ferry_presentation = FerryArrivalPresentation.new()
	ferry_presentation.name = "FerryArrivalPresentation"
	world_root.add_child(ferry_presentation)
	ferry_presentation.setup(materials)

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
	camera_rig.zoom_changed.connect(lighting.set_camera_shadow_distance)
	lighting.set_camera_shadow_distance(camera_rig.zoom_distance())
	interaction_targets = InteractionTargetResolverScript.new(
		self, core, camera_rig.camera, delivery_point
	)

	placement = PlacementController.new()
	placement.name = "Placement"
	world_root.add_child(placement)
	placement.setup(core, assets, camera_rig, player, effects, renderer)

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
	pixel_look = PixelLook.new()
	pixel_look.name = "PixelLook"
	add_child(pixel_look)

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

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.setup(core, kit, self)


## ReShade-style live lighting overlay (debug builds), toggled from the pause
## menu's Admin page. Built lazily so release sessions never carry it.
func toggle_lighting_tuner() -> bool:
	if not OS.is_debug_build():
		return false
	if lighting_tuner == null:
		lighting_tuner = LightingTunerScript.new()
		lighting_tuner.name = "LightingTuner"
		add_child(lighting_tuner)
		lighting_tuner.setup(lighting, kit)
		return true
	lighting_tuner.visible = not lighting_tuner.visible
	if lighting_tuner.visible:
		lighting_tuner.refresh()
	return lighting_tuner.visible


# A hand-composed showcase island (Admin page): every tile family, stacked
# elevation, a wrapping water region and a broad spread of structures. Rows
# run north to south from MOCK_WORLD_ORIGIN; place_tile overwrites whatever
# stood on each cell, so building it replaces the current island in place.
const MOCK_WORLD_ORIGIN := Vector2i(-4, -3)
const MOCK_WORLD_TILES := {
	"W": "tile_open_water", "G": "tile_grass", "F": "tile_grass_flower",
	"V": "tile_grove_mature", "C": "tile_cobblestone", "L": "tile_flagstone",
	"T": "tile_courtyard", "R": "tile_dirt_road", "X": "tile_dirt_crossroad",
	"D": "tile_dirt", "S": "tile_sand", "N": "tile_snowfield",
	"M": "tile_mud", "K": "tile_wooden_planks", "Y": "tile_clay",
	"U": "tile_garden", "P": "tile_path", "B": "tile_plain_ground",
	"O": "tile_stone_clearing",
}
const MOCK_WORLD_ROWS := [
	"WWWWWWWWWW",
	"WGGVVGFGGW",
	"WGRCCCCRGW",
	"WVRCTTCRUW",
	"WGRCLLCRUW",
	"WFXRRRRXDW",
	"WKKKKNNDMW",
	"WKSSKNNYBW",
]
const MOCK_WORLD_STRUCTURES := [
	[Vector2i(-1, -2), "struct_pine_tall", 0],
	[Vector2i(0, -2), "struct_pine", 0],
	[Vector2i(2, -2), "struct_stone_wall_low", 0],
	[Vector2i(3, -2), "struct_stone_wall_corner", 0],
	[Vector2i(-3, -1), "struct_bush", 0],
	[Vector2i(2, -1), "struct_bench", 2],
	[Vector2i(0, 0), "struct_stone_well", 0],
	[Vector2i(4, 0), "struct_garden_trellis", 1],
	[Vector2i(-1, 1), "struct_lantern", 0],
	[Vector2i(1, 1), "struct_birdbath", 0],
	[Vector2i(4, 1), "struct_planter", 0],
	[Vector2i(-2, 2), "struct_wooden_arch", 1],
	[Vector2i(3, 2), "struct_wheelbarrow", 3],
	[Vector2i(4, 2), "struct_pot", 0],
	[Vector2i(-3, 3), "struct_barrel", 0],
	[Vector2i(-2, 3), "struct_crate", 0],
	[Vector2i(2, 3), "struct_log_pile", 1],
	[Vector2i(3, 3), "struct_snowman", 0],
	[Vector2i(-1, 4), "struct_campfire", 0],
	[Vector2i(4, 4), "struct_milk_churn", 0],
	[Vector2i(-4, 0), "struct_water_wheel", 0],
	[Vector2i(5, 1), "struct_fishing_marker", 0],
]


func debug_build_mock_world() -> int:
	if not OS.is_debug_build():
		return 0
	for row_index in MOCK_WORLD_ROWS.size():
		var row: String = MOCK_WORLD_ROWS[row_index]
		for col in row.length():
			var tile_id: String = MOCK_WORLD_TILES.get(row[col], "")
			if not tile_id.is_empty():
				core.grid.place_tile(MOCK_WORLD_ORIGIN + Vector2i(col, row_index), tile_id)
	# A stacked grass rise with a young pine crown, showing the covered forms.
	core.grid.place_tile_at(Vector2i(-3, -2), 1, "tile_grass")
	core.grid.place_tile_at(Vector2i(-2, -2), 1, "tile_grass")
	core.grid.place_tile_at(Vector2i(-3, -2), 2, "tile_grass")
	var placed := 0
	for spec in MOCK_WORLD_STRUCTURES:
		if core.grid.add_structure(spec[0], String(spec[1]), _mock_socket(String(spec[1])), int(spec[2])) != null:
			placed += 1
	if core.grid.add_structure(
		Vector2i(-3, -2), "struct_pine_young", _mock_socket("struct_pine_young"), 0, 2
	) != null:
		placed += 1
	player.global_position = core.grid.cell_to_world(Vector2i(-1, -1)) + Vector3(0, 0.05, 0)
	core.autosave_soon()
	return placed


func _mock_socket(structure_id: String) -> int:
	## Buildings occupy the tile's single structure socket (index 0); decor
	## lives in the numbered decor sockets starting at 1.
	var definition := core.registries.structure(structure_id)
	return 0 if definition != null and definition.socket_type == "structure" else 1


func debug_reset_save() -> void:
	if not OS.is_debug_build():
		return
	core.autosave_paused = true
	for path in [core.save_manager.save_path, core.save_manager.backup_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	get_tree().paused = false
	get_tree().reload_current_scene()


func _connect_flows() -> void:
	hud.open_parcel_requested.connect(func():
		audio.play_event("parcel_open")
		parcel_reveal.open_best_available())
	hud.pause_requested.connect(func(): open_pause_menu())
	hud.build_piece_selected.connect(func(kind, id):
		audio.play_event("build_preview")
		placement.hold_new(kind, id))
	parcel_reveal.reveal_finished.connect(_on_tile_chosen)
	core.parcels.options_revealed.connect(func(_p, _o): audio.play_event("parcel_reveal"))
	panels.landmark_resolution_chosen.connect(_on_landmark_resolution)
	panels.panel_toggled.connect(func(_n, open): audio.play_event("panel_open" if open else "panel_close"))

	skill_actions.action_feedback.connect(_on_action_feedback)
	skill_actions.storage_requested.connect(func(): panels.toggle("inventory"))
	skill_actions.delivery_package_requested.connect(_open_delivery_package)
	skill_actions.landmark_prompt_requested.connect(func(node):
		panels.show_landmark_choice(String(node.get_meta("landmark_id"))))

	placement.action_result.connect(_on_placement_result)
	player.interaction_focus_changed.connect(_on_focus_changed)
	player.click_interaction_reached.connect(_on_click_interaction_reached)

	core.skills.level_up.connect(_on_skill_level_up)
	core.equipment.equipment_changed.connect(func():
		player_visual.apply_equipment(core.equipment)
	)
	player.state_changed.connect(_on_player_state_changed)
	core.collection.discovered.connect(func(_c, _i): audio.play_event("discovery"))
	if core.registries.feature("combat_enabled", false):
		core.combat.health_changed.connect(_on_health_changed)
		core.combat.player_defeated.connect(_on_player_defeated)
		core.combat.enemy_hit.connect(func(_s, _r): audio.play_event("enemy_hit"))
		core.combat.enemy_defeated.connect(_on_enemy_defeated)
	core.landmarks.opportunity_appeared.connect(_on_opportunity)
	core.landmarks.landmark_revealed.connect(_on_landmark_revealed)
	core.landmarks.landmark_reclaimed.connect(_on_landmark_reclaimed)
	core.rewards.loot_granted.connect(_on_loot)
	core.rewards.hobby_result_resolved.connect(_on_hobby_result)
	core.arrivals.arrival_requested.connect(_on_arrival_requested)
	core.arrivals.delivery_ready.connect(_on_delivery_ready)
	core.arrivals.delivery_resolved.connect(func(): delivery_point.hide_package())
	ferry_presentation.arrival_started.connect(_on_presentation_arrival_started)
	ferry_presentation.delivery_ready.connect(_on_presentation_delivery_ready)
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
	# Present the actual front of the avatar while customization is open.
	player.rotation.y = PI
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
	camera_rig.restore_state(core.view_state)
	_apply_saved_visual_state()
	pause_menu.load_preferences_from_core()
	if not fresh:
		renderer.rebuild_all()
		player.position = core.profile.position
		player.suspend_water_rescue()
		player.rotation.y = core.profile.facing
		player_visual.apply_profile(core.profile)
		player_visual.apply_equipment(core.equipment)
		if core.registries.feature("hostile_landmarks_enabled", false):
			_spawn_saved_encounters()
		hud._refresh_all()
	if lighting.current_profile != null:
		_on_profile_applied(lighting.current_profile)
	hud.update_tutorial()
	hud.toast("Welcome%s, %s." % ["" if fresh else " back", core.profile.display_name], "good")
	core.arrivals.announce_restored_delivery()


func _apply_saved_visual_state() -> void:
	lighting.apply_runtime_state(core.visual_state)


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

## Resource regrow pop: terrain anchors and object-owned anchors are watched
## independently so a tree keeps its cycle when moved between ordinary tiles.
func _tick_anchor_visuals() -> void:
	for coord: Vector2i in core.grid.cells:
		var state := core.grid.cell(coord)
		var was_resting: bool = _anchor_watch.get(coord, false)
		if was_resting and not state.anchor_resting:
			renderer.refresh_anchor(coord)
			audio.play_event("leaf_rustle")
		_anchor_watch[coord] = state.anchor_resting
	for slot: Dictionary in core.grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			var structure_def := core.registries.structure(structure.structure_id)
			if structure_def == null or structure_def.anchor_id == "":
				continue
			var watch_key := "structure:%d" % structure.instance_id
			var was_resting: bool = _anchor_watch.get(watch_key, false)
			if was_resting and not structure.anchor_resting:
				renderer.refresh_structure_anchor(structure.instance_id)
				audio.play_event("leaf_rustle")
			_anchor_watch[watch_key] = structure.anchor_resting


# ------------------------------------------------------------------ input routing

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	var interactive := _hovered_clickable_control() != null
	if (
		not interactive
		and _gameplay_started
		and not placement.active
		and not panels.is_open()
		and not parcel_reveal.is_open()
	):
		interactive = not _interaction_at_screen(mouse.position).is_empty()
	effects.click_marker(mouse.position, interactive)


func _hovered_clickable_control() -> Control:
	var control := get_viewport().gui_get_hovered_control()
	while control != null:
		if control is BaseButton or control is Range or control is LineEdit or control is TextEdit:
			return control
		control = control.get_parent() as Control
	return null


func _unhandled_input(event: InputEvent) -> void:
	if not _gameplay_started:
		return
	if event.is_action_pressed("build_mode"):
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
			player.cancel_click_command()
			skill_actions.try_interact()
	elif event.is_action_pressed("cancel"):
		if panels.is_open():
			panels.close()
		elif parcel_reveal.is_open():
			return
		elif placement.active:
			placement.cancel_click()
		else:
			skill_actions.cancel_all()
			player.cancel_click_command()
			player.set_state(PlayerController.State.FREE)
			open_pause_menu()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if placement.active:
				if mouse.pressed:
					placement.pointer_press(mouse.position)
				else:
					placement.pointer_release(mouse.position)
			elif mouse.pressed:
				_handle_world_click(mouse.position)
		elif mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			if placement.active:
				placement.cancel_click()
	elif event is InputEventMouseMotion and placement.active:
		placement.pointer_motion((event as InputEventMouseMotion).position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_X and placement.active:
			placement.store_held()
			audio.play_event("store")


func open_pause_menu(page := "menu") -> void:
	if not _gameplay_started or parcel_reveal.is_open():
		return
	placement.prepare_for_save()
	if panels.is_open():
		panels.close()
	pause_menu.open(page)


# ------------------------------------------------------------------ click commands

func _handle_world_click(screen_position: Vector2) -> void:
	if panels.is_open() or parcel_reveal.is_open():
		return
	var interaction := _interaction_at_screen(screen_position)
	var destination: Variant
	if interaction.is_empty():
		destination = _ground_point_at_screen(screen_position)
		if destination == null:
			return
		var cell := core.grid.world_to_cell(destination)
		if not core.grid.is_traversable(cell):
			return
	else:
		destination = interaction["point"]
	skill_actions.cancel_all()
	if player.state != PlayerController.State.FREE:
		player.set_state(PlayerController.State.FREE)
	player.set_click_command(destination, interaction)


func _ground_point_at_screen(screen_position: Vector2) -> Variant:
	return interaction_targets.ground_point(screen_position)


func _interaction_at_screen(screen_position: Vector2) -> Dictionary:
	return interaction_targets.interaction_at(screen_position)


# ------------------------------------------------------------------ cross-cutting flows

func _on_action_feedback(kind: String, data: Dictionary) -> void:
	match kind:
		"fish_cast":
			audio.play_event("fish_cast")
		"fish_bite":
			audio.play_event("fish_bite")
		"fish_catch":
			audio.play_event("fish_catch")
			hud.update_tutorial()
		"chop_windup":
			audio.play_event("chop_windup")
		"chop_impact":
			audio.play_event("chop_impact")
			hud.update_tutorial()
		"grove_rest":
			audio.play_event("grove_rest")
			if int(data.get("instance_id", 0)) > 0:
				renderer.refresh_structure_anchor(int(data["instance_id"]))
			elif data.has("coord"):
				renderer.refresh_anchor(data["coord"])
		"tool_equip":
			audio.play_event("tool_equip")


func _on_skill_level_up(_skill_id: String, _level: int, _unlock: Variant) -> void:
	audio.play_event("levelup")
	hud.update_tutorial()
	if player.state == PlayerController.State.FREE:
		player_visual.play("celebrate")
	else:
		# Fishing and woodcutting own their full action clips. Queue the flourish
		# rather than cutting a cast, hold, or chop loop in half.
		_celebration_pending = true


func _on_player_state_changed(new_state: PlayerController.State) -> void:
	if new_state != PlayerController.State.FREE or not _celebration_pending:
		return
	_celebration_pending = false
	player_visual.play("celebrate")


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
	core.arrivals.resolve_delivery()
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
			hud.set_prompt("E — open Tile & Build Library")
		"delivery_package":
			hud.set_prompt("E — open the ferry's Land Parcel")
		"enemy":
			hud.set_prompt("E — attack   ·   Space — jump   ·   Shift — dodge")
		"landmark_prompt":
			hud.set_prompt("E — claim the watchpost")
		_:
			hud.set_prompt("")


func _on_click_interaction_reached(interaction: Dictionary) -> void:
	match interaction.get("kind", ""):
		"delivery_package":
			_open_delivery_package()
		"feature_interaction":
			_execute_feature_interaction(interaction)
		_:
			skill_actions.interact_with(interaction)


func _execute_feature_interaction(interaction: Dictionary) -> void:
	var option = interaction.get("option")
	if option == null:
		return
	if not option.enabled:
		hud.toast(option.disabled_reason, "warn")
		return
	if (
		option.feature_id == "camping"
		and core.camping.interactions.execute(
			option.id, "player", int(interaction.get("instance_id", 0))
		)
	):
		hud.toast("You settle into the shelter.", "good")
		core.autosave_soon()


func _open_delivery_package() -> void:
	var options := core.arrivals.open_waiting(core.parcels)
	if options.is_empty():
		return
	delivery_point.hide_package()
	audio.play_event("parcel_open")
	parcel_reveal.open_best_available()


func _on_arrival_requested(payload: LandParcelPayload) -> void:
	ferry_presentation.play(delivery_point, payload, core.registries.arrival_config)


func _on_presentation_arrival_started() -> void:
	audio.play_event("parcel_appear")
	hud.toast("A little ferry is approaching the northern dock.", "good")


func _on_presentation_delivery_ready(payload: LandParcelPayload) -> void:
	core.arrivals.mark_delivery_ready(payload)


func _on_delivery_ready(payload: LandParcelPayload) -> void:
	delivery_point.show_package(payload)
	audio.play_event("parcel_appear")
	hud.toast("A Land Parcel is waiting at the northern dock.", "good")


func _on_hobby_result(result: HobbyActionResult) -> void:
	if result.was_new_discovery:
		hud.toast("New journal discovery: %s" % result.collection_discovery_id.replace("_", " ").capitalize(), "good")
	if result.optional_tile_reward_id != "":
		var tile := core.registries.tile(result.optional_tile_reward_id)
		hud.toast("Rare find — %s added to your Tile Library!" % tile.display_name, "rare")
		audio.play_event("reward_rare")


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
	camera_rig.reset_pan()
	hud.toast("Home again.", "good")


func _on_profile_applied(profile: VisualStyleProfile) -> void:
	audio.set_rain(profile.rain_enabled)
	hud.apply_weather_contrast(profile.rain_enabled or lighting.is_dark_background())
	for light in get_tree().get_nodes_in_group("warm_lights"):
		var omni := light as OmniLight3D
		omni.light_energy = lighting.local_light_energy(float(omni.get_meta("base_energy", 1.0)))


func reload_from_save() -> void:
	if core.load_game():
		renderer.rebuild_all()
		player.position = core.profile.position
		player.suspend_water_rescue()
		player_visual.apply_profile(core.profile)
		player_visual.apply_equipment(core.equipment)
		for encounter in _encounters.values():
			encounter.queue_free()
		_encounters.clear()
		if core.registries.feature("hostile_landmarks_enabled", false):
			_spawn_saved_encounters()
		core.arrivals.announce_restored_delivery()
		hud._refresh_all()
		hud.toast("Save reloaded.", "good")


func reset_world() -> void:
	core.save_manager.delete_save()
	get_tree().reload_current_scene()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _gameplay_started:
		core.save()
