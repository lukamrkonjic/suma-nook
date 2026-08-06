class_name Main
extends Node
## Boots and wires the whole game: core logic (GameCore), the 3D world
## (renderer/effects/lighting), the player, cameras, placement, UI, and audio.
## Owns global input routing and the handful of cross-cutting flows (weather,
## defeat recovery, landmark encounters, footsteps, tutorial hints).

const InteractionTargetResolverScript := preload(
	"res://scripts/world/interaction_target_resolver.gd"
)
const DebugWorldBuilderScript := preload(
	"res://scripts/debug/debug_world_builder.gd"
)
const InputHintOverlayScript := preload(
	"res://scripts/ui/input_hint_overlay.gd"
)
const PIGEON_MASCOT_SCENE := preload(
	"res://characters/mascots/pigeon_mascot.tscn"
)
const ProceduralOwlMascotScript := preload(
	"res://scripts/characters/owl/procedural_owl_mascot.gd"
)
const DebugCreatureParadeScript := preload(
	"res://scripts/debug/creature_parade.gd"
)
const HarvestPresentationAdapterScript := preload(
	"res://scripts/features/harvesting/presentation/harvest_presentation_adapter.gd"
)
const WorldBudRewardPresenterScript := preload(
	"res://scripts/features/rewards/presentation/world_bud_reward_presenter.gd"
)
const RewardRevealPresenterRegistryScript := preload(
	"res://scripts/features/rewards/presentation/reward_reveal_presenter_registry.gd"
)
const RewardRevealSceneAdapterScript := preload(
	"res://scripts/features/rewards/presentation/reward_reveal_scene_adapter.gd"
)
const VisitorSceneAdapterScript := preload(
	"res://scripts/features/visitors/presentation/visitor_scene_adapter.gd"
)
const VisitorPresenterRegistryScript := preload(
	"res://scripts/features/visitors/presentation/visitor_presenter_registry.gd"
)
const SdfCreatureVisitorPresenterScript := preload(
	"res://scripts/features/visitors/presentation/sdf_creature_visitor_presenter.gd"
)
const DEBUG_WORLD_TILE_COUNT := 5000
const DEBUG_WORLD_MODEL_COUNT := 1250
const MAXED_WORLD_TILE_COUNT := 10000
const MAXED_WORLD_MODEL_COUNT := 10000
const DEBUG_WORLD_SEED := 8675309
const CONTROLLER_HOME_HOLD_SECONDS := 0.65

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
var player_drop_preview: Node3D
var player_drop_preview_visual: PlayerVisual
var pigeon_mascot: CharacterBody3D
var pigeon_controller: PigeonMascotController
var camera_rig: CameraRig
var placement: PlacementController
var skill_actions: SkillActions
var harvest_presentation: Node
var reward_reveal: RewardRevealSceneAdapter
var reward_reveal_presenter_registry: RewardRevealPresenterRegistry
var visitor_scene: Node3D
var visitor_presenter_registry: RefCounted
var hud: Hud
var pixel_look: PixelLook
const LightingTunerScript := preload("res://scripts/ui/lighting_tuner.gd")
const AssetViewerScript := preload("res://scripts/ui/asset_viewer.gd")
const PerformanceHudScript := preload("res://scripts/ui/performance_hud.gd")
var lighting_tuner: CanvasLayer
var asset_viewer: AssetViewer
var performance_hud
var panels: GamePanels
var pause_menu: PauseMenu
var discovery_reveal: DiscoveryReveal
var arrival_picker: ArrivalLandPicker
var catch_basket_view: CatchBasketView
var input_hints: InputHintOverlay
var character_creator: CharacterCreator
var audio: GameAudio
var interaction_targets
var save_path_override := ""  # injected before _ready by isolated scene tests

var _encounters: Dictionary = {}   # landmark_id -> LandmarkEncounter
var _footstep_accum := 0.0
var _gameplay_started := false
var _celebration_pending := false
var _hud_hidden := false
var _hud_visible_before_hide := true
var _input_hints_visible_before_hide := true
var _performance_hud_visible_before_hide := false
var _controller_hud_hold_elapsed := 0.0
var _controller_hud_hold_active := false
var _controller_hud_hold_home_fired := false
var _player_dock_busy := false
var _player_drop_target: Dictionary = {}


func _ready() -> void:
	palette = load("res://assets/palettes/gg_material_palette.tres")
	materials = MaterialLibrary.new(palette)
	assets = AssetLibrary.new(materials)
	kit = UiKit.new(palette)

	core = GameCore.new()
	core.setup()
	var debug_world_tiles := _requested_debug_world_tiles()
	var debug_world_models := _requested_debug_world_models(
		debug_world_tiles
	)
	if debug_world_tiles > 0:
		_isolate_debug_save()
	if save_path_override != "":
		core.save_manager.save_path = save_path_override
		core.save_manager.backup_path = save_path_override + ".backup"

	_build_world_scene()
	_build_ui()
	_connect_flows()

	if debug_world_tiles > 0:
		var debug_profile := PlayerProfile.new()
		debug_profile.display_name = "Debug Keeper"
		core.new_game(debug_profile)
		debug_build_performance_world(
			debug_world_tiles,
			debug_world_models
		)
		player_visual.apply_profile(core.profile)
		player_visual.apply_equipment(core.equipment)
		_start_gameplay(true)
	elif core.save_manager.has_save() and core.load_game():
		_start_gameplay(false)
		call_deferred("_resume_guided_onboarding")
	else:
		var opening_profile := PlayerProfile.new()
		opening_profile.display_name = "Keeper"
		core.begin_build_onboarding(opening_profile)
		renderer.rebuild_all()
		player_visual.apply_profile(core.profile)
		player_visual.apply_equipment(core.equipment)
		_start_gameplay(true, false)
		call_deferred("_resume_guided_onboarding")
	_apply_debug_visual_overrides()
	_schedule_debug_capture()


# ------------------------------------------------------------------ scene assembly

func _build_world_scene() -> void:
	world_root = Node3D.new()
	world_root.name = "GameWorld"
	add_child(world_root)

	lighting = (load("res://scenes/visual/SumaSoftDaylight.tscn") as PackedScene).instantiate()
	# Temporarily keep the cloud sea out of the sky. The feature switch leaves
	# the implementation intact for a later art-direction pass.
	lighting.void_clouds_enabled = core.registries.feature(
		"void_clouds_enabled", false
	)
	world_root.add_child(lighting)

	renderer = WorldRenderer.new()
	renderer.name = "WorldRenderer"
	world_root.add_child(renderer)

	effects = EffectsManager.new()
	effects.name = "Effects"
	world_root.add_child(effects)
	effects.setup(assets)
	harvest_presentation = HarvestPresentationAdapterScript.new()
	harvest_presentation.name = "HarvestPresentation"
	add_child(harvest_presentation)

	delivery_point = DeliveryPoint.new()
	world_root.add_child(delivery_point)
	delivery_point.setup(
		materials,
		core.grid.tile_size,
		Vector3(0, 0, -1),
		assets,
		core.grid
	)

	if core.registries.feature("ferry_arrivals_enabled", false):
		ferry_presentation = FerryArrivalPresentation.new()
		ferry_presentation.name = "FerryArrivalPresentation"
		world_root.add_child(ferry_presentation)
		ferry_presentation.setup(materials)

	player = PlayerController.new()
	player.name = "Player"
	var procedural_critter_enabled := core.registries.feature(
		"procedural_critter_player_enabled", false
	)
	var capsule := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.16 if procedural_critter_enabled else 0.3
	shape.height = 0.52 if procedural_critter_enabled else 1.1
	capsule.shape = shape
	capsule.position.y = 0.26 if procedural_critter_enabled else 0.56
	player.add_child(capsule)
	player_visual = PlayerVisual.new()
	player_visual.name = "Visual"
	player.add_child(player_visual)
	world_root.add_child(player)
	player_visual.build(assets, palette)
	player_visual.set_procedural_critter_enabled(procedural_critter_enabled)
	player_drop_preview = Node3D.new()
	player_drop_preview.name = "PlayerDropPreview"
	player_drop_preview.visible = false
	world_root.add_child(player_drop_preview)
	player_drop_preview_visual = PlayerVisual.new()
	player_drop_preview_visual.name = "Visual"
	player_drop_preview.add_child(player_drop_preview_visual)
	player_drop_preview_visual.build(assets, palette)
	player_drop_preview_visual.set_procedural_critter_enabled(
		procedural_critter_enabled
	)

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	world_root.add_child(camera_rig)
	camera_rig.setup(core, player)
	camera_rig.zoom_changed.connect(lighting.set_camera_shadow_distance)
	lighting.set_camera_shadow_distance(camera_rig.zoom_distance())

	# The volumetric void-cloud ocean lives inside the lighting rig; it only
	# needs the world's lowest structural underside and a focus to follow.
	lighting.set_void_cloud_world(-core.grid.block_depth, camera_rig)
	interaction_targets = InteractionTargetResolverScript.new(
		self,
		core,
		camera_rig.camera,
		delivery_point,
		renderer
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
	harvest_presentation.call("setup", core.harvesting, renderer, effects, audio)
	reward_reveal_presenter_registry = RewardRevealPresenterRegistryScript.new()
	reward_reveal_presenter_registry.register(
		"world_bud",
		func(): return WorldBudRewardPresenterScript.new() as Node3D
	)
	reward_reveal = RewardRevealSceneAdapterScript.new()
	reward_reveal.name = "WorldBudRewards"
	world_root.add_child(reward_reveal)
	reward_reveal.setup(
		core.registries,
		reward_reveal_presenter_registry,
		assets,
		core.grid,
		camera_rig.camera,
		audio
	)
	visitor_presenter_registry = VisitorPresenterRegistryScript.new()
	visitor_presenter_registry.call(
		"register", "sdf_creature",
		func(): return SdfCreatureVisitorPresenterScript.new() as Node3D
	)
	visitor_scene = VisitorSceneAdapterScript.new() as Node3D
	visitor_scene.name = "VisitorScene"
	world_root.add_child(visitor_scene)
	visitor_scene.call(
		"setup", core.visitors, core.registries, core.grid,
		visitor_presenter_registry
	)
	player.setup(core, camera_rig, player_visual)
	pigeon_mascot = PIGEON_MASCOT_SCENE.instantiate() as CharacterBody3D
	pigeon_mascot.name = "PigeonMascot"
	world_root.add_child(pigeon_mascot)
	pigeon_controller = pigeon_mascot.get_node("MascotController") as PigeonMascotController
	pigeon_controller.setup(player, core.grid)
	if core.registries.feature("procedural_owl_mascot_enabled", false):
		var owl_visual := ProceduralOwlMascotScript.new() as Node3D
		owl_visual.name = "ProceduralOwlVisual"
		pigeon_mascot.add_child(owl_visual)
		owl_visual.call("build")
		owl_visual.call("setup", pigeon_controller)
		pigeon_controller.attach_procedural_visual(owl_visual)
	# TEST-ONLY creature showcase; flip debug_creature_parade_enabled off in
	# data/features.json to remove it entirely.
	if core.registries.feature("debug_creature_parade_enabled", false):
		var parade := DebugCreatureParadeScript.new() as Node3D
		parade.name = "DebugCreatureParade"
		world_root.add_child(parade)
		parade.call("setup", core.grid, player.global_position)
	effects.bind_water_interaction(core, player)
	effects.bind_ground_impacts(core, player, audio)
	effects.bind_soft_terrain(core, player)
	effects.bind_void_fishing(core, player, player_visual)
	lighting.bind_fog_interactors(player, camera_rig)
	skill_actions.setup(core, player, player_visual, effects)
	catch_basket_view = CatchBasketView.new()
	catch_basket_view.name = "CatchBasketView"
	world_root.add_child(catch_basket_view)
	catch_basket_view.setup(core.fishing.basket, core.registries)
	catch_basket_view.visible = core.fishing.basket.haul_count() > 0
	core.fishing.session.fishing_started.connect(_place_catch_basket_view)
	core.fishing.basket.basket_changed.connect(func():
		catch_basket_view.visible = (
			core.fishing.basket.haul_count() > 0
			or core.fishing.session.is_active()
		)
	)
	player_visual.apply_profile(core.profile)
	player_visual.apply_equipment(core.equipment)
	player_drop_preview_visual.apply_profile(core.profile)
	player_drop_preview_visual.apply_equipment(core.equipment)


## The basket sits one step behind the keeper's fishing spot, on land.
func _place_catch_basket_view(anchor: Vector2i) -> void:
	var base := core.grid.cell_to_world(anchor, core.grid.top_elevation(anchor))
	var back := -player.global_basis.z
	back.y = 0.0
	if back.length_squared() > 0.001:
		back = back.normalized()
	catch_basket_view.global_position = base - back * 0.55 + Vector3(0.4, 0.02, 0.0)
	catch_basket_view.visible = true


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

	discovery_reveal = DiscoveryReveal.new()
	discovery_reveal.name = "DiscoveryReveal"
	add_child(discovery_reveal)
	discovery_reveal.setup(core, kit, assets)

	arrival_picker = ArrivalLandPicker.new()
	arrival_picker.name = "ArrivalLandPicker"
	add_child(arrival_picker)
	arrival_picker.setup(core, kit, assets)

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.setup(core, kit, self)

	input_hints = InputHintOverlayScript.new()
	input_hints.name = "InputHints"
	add_child(input_hints)
	input_hints.setup(kit)

	performance_hud = PerformanceHudScript.new()
	performance_hud.name = "PerformanceHud"
	add_child(performance_hud)
	performance_hud.setup(core, renderer)
	if "--perf-overlay" in OS.get_cmdline_user_args():
		performance_hud.show_profiler()


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
		lighting_tuner.closed.connect(func():
			if pause_menu.is_open():
				pause_menu.focus_default()
		)
		if InputDeviceService.shared().is_controller():
			lighting_tuner.focus_default()
		return true
	lighting_tuner.visible = not lighting_tuner.visible
	if lighting_tuner.visible:
		lighting_tuner.refresh()
		if InputDeviceService.shared().is_controller():
			lighting_tuner.focus_default()
	elif pause_menu.is_open():
		pause_menu.focus_default()
	return lighting_tuner.visible


func toggle_performance_hud() -> bool:
	if not OS.is_debug_build() or performance_hud == null:
		return false
	var wants_visible: bool = performance_hud.toggle()
	if _hud_hidden:
		_performance_hud_visible_before_hide = wants_visible
		performance_hud.visible = false
		return false
	return wants_visible


## H hides the normal gameplay overlays for clean screenshots and immersion.
## Menus remain independent so the player can always pause and recover them.
func toggle_all_hud() -> bool:
	if not _gameplay_started:
		return false
	if _hud_hidden:
		_hud_hidden = false
		if hud != null:
			hud.visible = _hud_visible_before_hide
		if input_hints != null:
			input_hints.visible = _input_hints_visible_before_hide
		if performance_hud != null:
			performance_hud.visible = _performance_hud_visible_before_hide
		_refresh_controller_hints()
		return false
	_hud_visible_before_hide = hud != null and hud.visible
	_input_hints_visible_before_hide = (
		input_hints != null and input_hints.visible
	)
	_performance_hud_visible_before_hide = (
		performance_hud != null and performance_hud.visible
	)
	_hud_hidden = true
	if hud != null:
		hud.visible = false
	if input_hints != null:
		input_hints.visible = false
	if performance_hud != null:
		performance_hud.visible = false
	return true


func hud_hidden() -> bool:
	return _hud_hidden


## Opens a production-material asset review room from the debug Admin page.
## It is built lazily and restores the current game exactly when closed.
func open_asset_viewer() -> void:
	if not OS.is_debug_build():
		return
	if pause_menu.is_open():
		pause_menu.close()
	if asset_viewer == null:
		asset_viewer = AssetViewerScript.new()
		asset_viewer.name = "AssetViewer"
		add_child(asset_viewer)
		asset_viewer.setup(self)
		asset_viewer.closed.connect(_refresh_controller_hints)
	asset_viewer.open()
	_refresh_controller_hints()


# A hand-composed showcase island (Admin page): every tile family, stacked
# elevation, a wrapping water region and a broad spread of structures. Rows
# run north to south from MOCK_WORLD_ORIGIN; place_tile overwrites whatever
# stood on each cell, so building it replaces the current island in place.
const MOCK_WORLD_ORIGIN := Vector2i(-4, -3)
const MOCK_WORLD_TILES := {
	"W": "tile_open_water",
	"G": "tile_grass",
	"S": "tile_sand",
	"C": "tile_concrete_brutalist",
	"N": "tile_snowfield",
}
const MOCK_WORLD_ROWS := [
	"WWWWWWWWWW",
	"WGGGGGGGGW",
	"WGSSSSSSGW",
	"WGSSGGSSGW",
	"WGCCGGCCGW",
	"WGNNNNNNGW",
	"WGGSSGGGGW",
	"WWWWWWWWWW",
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


func debug_build_performance_world(
	tile_count: int = DEBUG_WORLD_TILE_COUNT,
	model_count: int = DEBUG_WORLD_MODEL_COUNT,
	seed_value: int = DEBUG_WORLD_SEED
) -> Dictionary:
	if not OS.is_debug_build():
		return {}
	_isolate_debug_save()
	core.autosave_paused = true
	if placement != null and placement.active:
		placement.cancel_click()
	var report: Dictionary = DebugWorldBuilderScript.populate(
		core,
		tile_count,
		model_count,
		seed_value
	)
	if report.is_empty():
		return report
	renderer.rebuild_all()
	player.global_position = (
		core.grid.cell_to_world(Vector2i.ZERO) + Vector3(0, 0.05, 0)
	)
	player.rotation.y = PI
	core.profile.facing = PI
	player.suspend_water_rescue()
	player.cancel_click_command()
	delivery_point._sync_to_dock()
	hud._refresh_all()
	hud.update_tutorial()
	return report


func debug_build_maxed_world() -> Dictionary:
	return debug_build_performance_world(
		MAXED_WORLD_TILE_COUNT,
		MAXED_WORLD_MODEL_COUNT,
		DEBUG_WORLD_SEED
	)


func _isolate_debug_save() -> void:
	core.save_manager.save_path = "user://suma_nook_debug_world.json"
	core.save_manager.backup_path = "user://suma_nook_debug_world.json.backup"


func _requested_debug_world_tiles() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--maxed-world" or arg == "--debug-world=maxed":
			return MAXED_WORLD_TILE_COUNT
		if arg == "--debug-world":
			return DEBUG_WORLD_TILE_COUNT
		if arg.begins_with("--debug-world="):
			return maxi(1, int(arg.trim_prefix("--debug-world=")))
	return 0


func _requested_debug_world_models(tile_count: int) -> int:
	if tile_count <= 0:
		return DEBUG_WORLD_MODEL_COUNT
	if _maxed_world_requested():
		return tile_count
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--debug-models="):
			return clampi(
				int(arg.trim_prefix("--debug-models=")),
				0,
				tile_count
			)
	return mini(DEBUG_WORLD_MODEL_COUNT, tile_count)


func _maxed_world_requested() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--maxed-world" or arg == "--debug-world=maxed":
			return true
	return false


func _apply_debug_visual_overrides() -> void:
	if not OS.is_debug_build():
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--time-of-day="):
			var requested_time := arg.trim_prefix("--time-of-day=")
			if requested_time in ["morning", "noon", "sunset", "night"]:
				lighting.set_time_of_day(requested_time)
		elif arg.begins_with("--weather="):
			var requested_weather := arg.trim_prefix("--weather=")
			if requested_weather in [
				"day", "mist", "rain", "leaves", "snow", "blossom"
			]:
				lighting.set_weather(requested_weather)


func _schedule_debug_capture() -> void:
	if not OS.is_debug_build():
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--debug-shot="):
			_capture_debug_shot.call_deferred(
				arg.trim_prefix("--debug-shot=")
			)
			return


func _capture_debug_shot(path: String) -> void:
	# Let imported resources, shadows, the character rig, and the performance
	# sampler all settle before capturing an evidence frame.
	for _frame in 300:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var absolute_path := (
		ProjectSettings.globalize_path(path)
		if path.begins_with("res://") or path.begins_with("user://")
		else path
	)
	var error := image.save_png(absolute_path)
	print("DEBUG_SHOT ", absolute_path, " error=", error)
	if "--quit-after-shot" in OS.get_cmdline_user_args():
		get_tree().quit(0 if error == OK else 1)


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
	hud.pause_requested.connect(func(): open_pause_menu())
	hud.player_dock_activated.connect(_on_player_dock_activated)
	hud.player_dock_drag_started.connect(_on_player_dock_drag_started)
	hud.player_dock_drag_moved.connect(_on_player_dock_drag_moved)
	hud.player_dock_drag_released.connect(_on_player_dock_drag_released)
	hud.catch_basket_requested.connect(panels.show_catch_basket)
	hud.spirit_pouch_requested.connect(panels.show_spirit_pouch)
	panels.basket_tile_bundle_taken.connect(_on_basket_tile_bundle_taken)
	panels.basket_model_taken.connect(_on_basket_model_taken)
	core.fishing.basket.basket_changed.connect(func():
		hud.refresh_fishing_buttons()
	)
	core.fishing.pouch.pouch_changed.connect(func():
		hud.refresh_fishing_buttons()
	)
	core.fishing.pouch.spirit_added.connect(func(spirit_id: String):
		var spirit := core.registries.spirit(spirit_id)
		if spirit != null:
			hud.toast("%s settles into your pouch." % spirit.display_name, "good")
			audio.play_event("discovery")
	)
	core.fishing.pouch.spirit_rejected_full.connect(func(_spirit_id: String):
		hud.toast("Your Spirit Pouch is full — five charms is plenty.", "warn")
	)
	# Leaving build mode returns any unplaced bundle copies to the basket.
	placement.mode_changed.connect(func(active: bool):
		if not active and core.fishing.basket.has_active_bundle():
			core.fishing.basket.reconcile_bundle_checkout()
	)
	hud.build_piece_selected.connect(func(kind, id):
		audio.play_event("build_preview")
		placement.hold_new(kind, id))
	hud.build_world_browse_requested.connect(_begin_controller_world_browse)
	hud.build_store_requested.connect(func():
		placement.store_held()
		audio.play_event("store"))
	arrival_picker.land_chosen.connect(_on_first_land_chosen)
	discovery_reveal.reveal_finished.connect(_on_discovery_accepted)
	discovery_reveal.reveal_started.connect(
		func(_entry): _refresh_controller_hints()
	)
	core.progression.discovery.discovery_ready.connect(func(entry):
		hud.update_tutorial()
		audio.play_event("parcel_reveal")
		call_deferred("_open_pending_discovery_when_ready")
	)
	panels.landmark_resolution_chosen.connect(_on_landmark_resolution)
	panels.panel_toggled.connect(func(_n, open):
		audio.play_event("panel_open" if open else "panel_close")
		_refresh_controller_hints()
	)
	pause_menu.opened.connect(_refresh_controller_hints)
	pause_menu.closed.connect(_refresh_controller_hints)

	skill_actions.action_feedback.connect(_on_action_feedback)
	skill_actions.storage_requested.connect(func(): panels.toggle("inventory"))
	skill_actions.delivery_package_requested.connect(_open_delivery_package)
	skill_actions.landmark_prompt_requested.connect(func(node):
		panels.show_landmark_choice(String(node.get_meta("landmark_id"))))

	placement.action_result.connect(_on_placement_result)
	placement.mode_changed.connect(func(_active): _refresh_controller_hints())
	placement.held_changed.connect(func(_held): _refresh_controller_hints())
	player.interaction_focus_changed.connect(_on_focus_changed)
	player.click_interaction_reached.connect(_on_click_interaction_reached)
	player.arrival_choice_ready.connect(_open_first_land_picker)
	player.arrival_landed.connect(_on_first_arrival_landed)
	player.deployment_changed.connect(_on_player_deployment_changed)
	core.fire.burning_changed.connect(_on_fire_burning_changed)

	core.progression.milestones.milestone_reached.connect(_on_milestone_reached)
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
	core.anchor_regenerated.connect(_on_anchor_regenerated)
	core.arrivals.arrival_requested.connect(_on_arrival_requested)
	core.arrivals.delivery_ready.connect(_on_delivery_ready)
	core.arrivals.delivery_resolved.connect(func(): delivery_point.hide_package())
	core.onboarding_guidance_ready.connect(func(_kind, _content_id):
		call_deferred("_resume_guided_onboarding")
	)
	core.onboarding.stage_changed.connect(_on_onboarding_stage_changed)
	harvest_presentation.connect("feedback", _on_harvest_feedback)
	reward_reveal.reveal_started.connect(func(_reward):
		_refresh_controller_hints()
	)
	reward_reveal.reveal_finished.connect(func(_reward):
		_refresh_controller_hints()
	)
	visitor_scene.connect("reward_presented", _on_visitor_reward_presented)
	core.visitors.visitor_available.connect(func(_event):
		hud.toast("A curious visitor has arrived.", "rare")
		audio.play_event("parcel_appear")
	)
	if ferry_presentation != null:
		ferry_presentation.arrival_started.connect(_on_presentation_arrival_started)
		ferry_presentation.delivery_ready.connect(_on_presentation_delivery_ready)
	lighting.profile_applied.connect(_on_profile_applied)
	if lighting.current_profile != null:
		_on_profile_applied(lighting.current_profile)
	InputDeviceService.shared().input_method_changed.connect(_on_input_method_changed)
	InputDeviceService.shared().controller_connection_changed.connect(
		_on_controller_connection_changed
	)
	InputDeviceService.shared().active_controller_changed.connect(
		func(_device): _refresh_controller_hints()
	)
	_on_input_method_changed(InputDeviceService.shared().input_method)


# ------------------------------------------------------------------ boot flows

func _start_character_creation() -> void:
	character_creator = CharacterCreator.new()
	character_creator.name = "Creator"
	add_child(character_creator)
	core.profile = character_creator.profile
	character_creator.setup(
		kit, palette,
		func(profile): player_visual.apply_profile(profile)
	)
	# The world does not exist yet: creation is a dedicated scene — the
	# character stands alone against the soft sky, no tiles behind and no
	# gameplay HUD. The world materializes only when the player finishes.
	hud.visible = false
	player.position = Vector3.ZERO
	camera_rig.zoom_for_creator()
	# Face the portrait camera directly instead of presenting a gameplay
	# three-quarter angle.
	player.rotation.y = camera_rig.rotation.y + PI
	player.set_state(PlayerController.State.DISABLED)
	character_creator.creation_finished.connect(_on_creation_finished)
	if InputDeviceService.shared().is_controller():
		character_creator.focus_default()
	_refresh_controller_hints()


## Curated arrival choices from tuning — small on purpose: exciting, not
## overwhelming. The pick is the player's first act of world-making.
func _starter_land_option_ids() -> Array:
	var options: Array = []
	for raw_tile_id in core.registries.tune("starter_land_options", []):
		var tile := core.registries.tile(String(raw_tile_id))
		if tile != null and core.registries.is_tile_active(tile.id):
			options.append(tile.id)
	return options


func _on_creation_finished(profile: PlayerProfile) -> void:
	character_creator = null
	core.begin_onboarding_game(profile)
	player_visual.apply_profile(profile)
	player.position = profile.position
	_begin_first_arrival()


func _begin_first_arrival() -> void:
	get_tree().paused = false
	_gameplay_started = false
	hud.visible = false
	renderer.rebuild_all()
	player_visual.apply_profile(core.profile)
	player_visual.apply_equipment(core.equipment)
	player.position = Vector3.ZERO
	player.rotation.y = core.profile.facing
	camera_rig.frame_for_arrival()
	player.begin_portal_arrival()
	_refresh_controller_hints()


func _open_first_land_picker() -> void:
	# Retained as a disconnected compatibility hook for the archived portal
	# presentation. The current opening starts directly in Shape Land.
	return


func _on_first_land_chosen(tile_id: String) -> void:
	get_tree().paused = false
	if not core.choose_onboarding_land(tile_id):
		arrival_picker.open(_starter_land_option_ids())
		get_tree().paused = true
		return
	renderer.animate_arrival_island()
	var definition := core.registries.tile(tile_id)
	if definition != null:
		audio.play_event("place_" + definition.placement_sound)
	await get_tree().create_timer(0.72).timeout
	player.finish_portal_arrival()


func _on_first_arrival_landed() -> void:
	_start_gameplay(true, false)
	hud.toast("A quiet water shape followed you through.", "good")
	call_deferred("_resume_guided_onboarding")


func _start_gameplay(fresh: bool, show_welcome := true) -> void:
	_gameplay_started = true
	hud.visible = true
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
	# Shape Land is the permanent primary mode. The keeper begins in the HUD
	# dock every session and only receives a world body after a valid drag/drop.
	placement.set_active(true)
	player.dock_for_placement()
	hud.set_player_dock_visible(not core.onboarding.is_active())
	player_drop_preview.visible = false
	hud.update_tutorial()
	if show_welcome:
		hud.toast("Welcome%s, %s." % ["" if fresh else " back", core.profile.display_name], "good")
	core.arrivals.announce_restored_delivery()
	visitor_scene.call("sync_from_module")
	_refresh_controller_hints()
	if player.deployed and is_instance_valid(pigeon_controller):
		pigeon_controller.spawn_near_player()


func _resume_guided_onboarding() -> void:
	var guided := core.ensure_onboarding_guided_piece()
	if guided.is_empty():
		hud.update_tutorial()
		return
	placement.hold_new(String(guided["kind"]), String(guided["id"]))
	hud.update_tutorial()


func _advance_guided_onboarding() -> void:
	var next := core.advance_onboarding_after_placement()
	if next.is_empty():
		hud.update_tutorial()
		return
	var message := String(next.get("message", ""))
	if message != "":
		hud.toast(message, "good")
	var kind := String(next.get("kind", ""))
	var content_id := String(next.get("id", ""))
	if kind != "" and content_id != "":
		placement.hold_new(kind, content_id)
	else:
		# Guided rewards are bundles. The lesson places one copy; remaining
		# copies stay safely in stock instead of trapping the player in a
		# continuous-placement preview after the stage has advanced.
		if not placement.held.is_empty():
			placement.cancel_click()
		placement.set_active(true)
	hud.update_tutorial()


func _guided_placement_locked() -> bool:
	return core.onboarding.requires_guided_placement()


# --------------------------------------------------------- keeper world dock

func _on_player_dock_drag_started(screen_position: Vector2) -> void:
	if _player_dock_busy or player.deployed:
		return
	if not placement.held.is_empty():
		placement.cancel_click()
	skill_actions.cancel_all()
	player_drop_preview_visual.apply_profile(core.profile)
	player_drop_preview_visual.apply_equipment(core.equipment)
	player_drop_preview_visual.play("idle")
	_update_player_drop_preview(screen_position)


func _on_player_dock_drag_moved(screen_position: Vector2) -> void:
	if _player_dock_busy or player.deployed:
		return
	_update_player_drop_preview(screen_position)


func _on_player_dock_drag_released(screen_position: Vector2) -> void:
	if _player_dock_busy or player.deployed:
		return
	_update_player_drop_preview(screen_position)
	player_drop_preview.visible = false
	if _player_drop_target.is_empty():
		hud.set_player_drop_valid(false)
		hud.toast("Drop your keeper onto a clear, walkable tile.", "warn")
		return
	_deploy_player_target(_player_drop_target)


func _on_player_dock_activated() -> void:
	if _player_dock_busy:
		return
	if not player.deployed:
		# Mouse placement is deliberately spatial. A controller has no drag
		# gesture, so activating the focused dock uses the safe home tile.
		if InputDeviceService.shared().is_controller():
			try_place_player_at_cell(core.grid.home_cell)
		else:
			hud.toast("Drag your keeper from here onto the island.", "good")
		return
	if not placement.held.is_empty():
		placement.cancel_click()
	skill_actions.cancel_all()
	_player_dock_busy = player.recall_to_dock()


func _update_player_drop_preview(screen_position: Vector2) -> void:
	_player_drop_target = placement.player_drop_target(screen_position)
	var valid := not _player_drop_target.is_empty()
	hud.set_player_drop_valid(valid)
	player_drop_preview.visible = valid
	if valid:
		player_drop_preview.global_position = _player_drop_target["position"]


func try_place_player_at_cell(coord: Vector2i) -> bool:
	if _player_dock_busy or player.deployed:
		return false
	var target := placement.player_drop_target_at_cell(coord)
	if target.is_empty():
		return false
	return _deploy_player_target(target)


func _deploy_player_target(target: Dictionary) -> bool:
	if target.is_empty() or not target.get("position") is Vector3:
		return false
	player_drop_preview.visible = false
	_player_drop_target = {}
	_player_dock_busy = player.deploy_from_dock(target["position"])
	if _player_dock_busy:
		hud.set_player_deployed(true)
		camera_rig.reset_pan()
	return _player_dock_busy


func _on_player_deployment_changed(deployed: bool) -> void:
	_player_dock_busy = false
	_player_drop_target = {}
	player_drop_preview.visible = false
	hud.set_player_deployed(deployed)
	if deployed:
		core.autosave_soon()
		if is_instance_valid(pigeon_controller):
			pigeon_controller.spawn_near_player()
	hud.update_tutorial()
	_refresh_controller_hints()


func _apply_saved_visual_state() -> void:
	lighting.apply_runtime_state(core.visual_state)


func _process(delta: float) -> void:
	if not _gameplay_started:
		return
	_tick_controller_hud_hold(delta)
	core.tick(delta)
	_tick_footsteps(delta)


func _tick_controller_hud_hold(delta: float) -> void:
	if (
		not _controller_hud_hold_active
		or _controller_hud_hold_home_fired
	):
		return
	_controller_hud_hold_elapsed += delta
	if _controller_hud_hold_elapsed < CONTROLLER_HOME_HOLD_SECONDS:
		return
	_controller_hud_hold_home_fired = true
	_return_home()


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


func _on_anchor_regenerated(
	coord: Vector2i,
	_elevation: int,
	instance_id: int
) -> void:
	if instance_id > 0:
		renderer.refresh_structure_anchor(instance_id)
	else:
		renderer.refresh_anchor(coord)
	audio.play_event("leaf_rustle")


# ------------------------------------------------------------------ input routing

func _input(event: InputEvent) -> void:
	# Pause is global and must run before a focused Build Bag control can
	# consume Escape as contextual cancel. The open PauseMenu owns the same
	# action while the tree is paused and closes itself.
	if (
		_gameplay_started
		and event is InputEventKey
		and event.is_action_pressed("pause")
		and not pause_menu.is_open()
		and not discovery_reveal.is_open()
		and (asset_viewer == null or not asset_viewer.is_open())
	):
		open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if _hovered_clickable_control() != null:
		return
	if (
		_gameplay_started
		and not placement.active
		and not panels.is_open()
		and not discovery_reveal.is_open()
		and not _interaction_at_screen(mouse.position).is_empty()
	):
		effects.click_marker(mouse.position, true)


func _hovered_clickable_control() -> Control:
	var control := get_viewport().gui_get_hovered_control()
	while control != null:
		if control is BaseButton or control is Range or control is LineEdit or control is TextEdit:
			return control
		control = control.get_parent() as Control
	return null


func _unhandled_input(event: InputEvent) -> void:
	if (
		OS.is_debug_build()
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and (event as InputEventKey).physical_keycode == KEY_F3
	):
		toggle_performance_hud()
		get_viewport().set_input_as_handled()
		return
	if not _gameplay_started:
		return
	if asset_viewer != null and asset_viewer.is_open():
		return
	if pause_menu.is_open() or discovery_reveal.is_open() or panels.is_open():
		return
	if _handle_hud_shortcut(event):
		get_viewport().set_input_as_handled()
		return
	if (
		OS.is_debug_build()
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and (event as InputEventKey).physical_keycode == KEY_F8
	):
		open_asset_viewer()
		return
	if event.is_action_pressed("pause"):
		open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if placement.active and placement.controller_mode():
		_handle_controller_build_input(event)
		return
	if event.is_action_pressed("build_mode"):
		if hud.build_library_collapsed():
			hud.request_build_library_open()
		else:
			hud.set_build_library_expanded(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("rotate_piece") and placement.active:
		placement.rotate_held()
		audio.play_event("build_rotate")
	elif (
		event.is_action_pressed("move_piece")
		and placement.active
		and placement.held.is_empty()
	):
		placement.pick_up_under_pointer()
	elif (
		event.is_action_pressed("undo")
		and not _is_controller_event(event)
	):
		placement.undo()
	elif (
		event.is_action_pressed("redo")
		and not _is_controller_event(event)
	):
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
	elif (
		event.is_action_pressed("interact")
		and not event is InputEventMouseButton
	):
		if (
			placement.active
			and (
				not placement.held.is_empty()
				or placement.controller_cursor_active()
			)
		):
			placement.click()
		elif player.deployed and player.state == PlayerController.State.FREE:
			player.cancel_click_command()
			_perform_interaction(player.focus())
		elif player.state in [
			PlayerController.State.FISHING_CAST,
			PlayerController.State.FISHING_WAIT,
		]:
			# At the bite this retrieves the catch faster; otherwise nothing.
			skill_actions.fishing_input()
	elif event.is_action_pressed("cancel"):
		if (
			_is_controller_event(event)
			and core.registries.feature("combat_enabled", false)
			and event.is_action_pressed("dodge")
		):
			# B/Circle is dodge in combat and Back everywhere else.
			return
		if panels.is_open():
			panels.close()
		elif discovery_reveal.is_open():
			return
		elif placement.active:
			_cancel_build_or_open_library()
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
					if (
						not placement.held.is_empty()
						or not _try_build_world_action_at_screen(mouse.position)
					):
						placement.pointer_press(mouse.position)
				else:
					placement.pointer_release(mouse.position)
			elif mouse.pressed:
				_handle_world_click(mouse.position)
		elif mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			if placement.active:
				if placement.held.is_empty():
					placement.pick_up_under_pointer()
				else:
					_cancel_build_or_open_library()
	elif event is InputEventMouseMotion and placement.active:
		placement.pointer_motion((event as InputEventMouseMotion).position)
	elif event.is_action_pressed("store_piece") and placement.active:
		placement.store_held()
		audio.play_event("store")


func _handle_controller_build_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode"):
		if placement.held.is_empty():
			if placement.controller_cursor_active():
				placement.show_controller_library()
				hud.request_build_library_open()
				hud.focus_build_library()
			else:
				_begin_controller_world_browse()
		get_viewport().set_input_as_handled()
		_refresh_controller_hints()
		return
	if event.is_action_pressed("cancel"):
		_cancel_build_or_open_library()
		get_viewport().set_input_as_handled()
		_refresh_controller_hints()
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		# Directional and confirm input belongs to the focused build library.
		return
	var cursor_direction := Vector2i.ZERO
	if event.is_action_pressed("build_cursor_left"):
		cursor_direction = Vector2i.LEFT
	elif event.is_action_pressed("build_cursor_right"):
		cursor_direction = Vector2i.RIGHT
	elif event.is_action_pressed("build_cursor_up"):
		cursor_direction = Vector2i.UP
	elif event.is_action_pressed("build_cursor_down"):
		cursor_direction = Vector2i.DOWN
	if cursor_direction != Vector2i.ZERO:
		placement.move_controller_cursor(cursor_direction)
		get_viewport().set_input_as_handled()
		return
	if (
		event.is_action_pressed("build_confirm")
		and placement.controller_cursor_active()
	):
		if (
			not placement.held.is_empty()
			or not _try_build_world_action_at_cell(
				placement.controller_cursor_cell()
			)
		):
			placement.click()
	elif event.is_action_pressed("move_piece") and placement.held.is_empty():
		placement.pick_up_at(
			placement.controller_cursor_cell(),
			core.grid.top_elevation(placement.controller_cursor_cell())
		)
	elif event.is_action_pressed("rotate_piece"):
		placement.rotate_held()
		audio.play_event("build_rotate")
	elif event.is_action_pressed("store_piece"):
		placement.store_held()
		audio.play_event("store")
	elif event.is_action_pressed("undo"):
		placement.undo()
	elif event.is_action_pressed("redo"):
		placement.redo()
	else:
		return
	get_viewport().set_input_as_handled()


func _cancel_build_or_open_library() -> void:
	if not placement.active:
		return
	if _guided_placement_locked():
		hud.toast("This piece is part of your arrival — place it first.", "warn")
		return
	if hud.build_library_collapsed():
		if not placement.held.is_empty():
			placement.cancel_click()
		hud.request_build_library_open()
		return
	if not placement.held.is_empty():
		placement.cancel_click()
	hud.set_build_library_expanded(false)


func _handle_hud_shortcut(event: InputEvent) -> bool:
	if not event.is_action("toggle_hud"):
		return false
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if button.pressed:
			_controller_hud_hold_elapsed = 0.0
			_controller_hud_hold_active = true
			_controller_hud_hold_home_fired = false
		elif _controller_hud_hold_active:
			if not _controller_hud_hold_home_fired:
				toggle_all_hud()
			_controller_hud_hold_elapsed = 0.0
			_controller_hud_hold_active = false
			_controller_hud_hold_home_fired = false
		return true
	if event.is_action_pressed("toggle_hud"):
		toggle_all_hud()
		return true
	return false


func _begin_controller_world_browse() -> void:
	placement.begin_controller_browse()
	hud.set_build_library_expanded(false)
	hud.release_build_focus()
	_refresh_controller_hints()


func _is_controller_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


func open_pause_menu(page := "menu") -> void:
	if not _gameplay_started or discovery_reveal.is_open():
		return
	placement.prepare_for_save()
	if panels.is_open():
		panels.close()
	pause_menu.open(page)


func _on_input_method_changed(method: int) -> void:
	var using_controller := method == InputDeviceService.InputMethod.CONTROLLER
	placement.set_controller_mode(using_controller)
	if using_controller:
		if arrival_picker != null and arrival_picker.is_open():
			arrival_picker.focus_default()
		elif pause_menu.is_open():
			pause_menu.focus_default()
		elif panels.is_open():
			panels.focus_default()
		elif discovery_reveal.is_open():
			discovery_reveal.focus_default()
		elif (
			character_creator != null
			and is_instance_valid(character_creator)
		):
			character_creator.focus_default()
		elif placement.active and placement.held.is_empty():
			hud.focus_build_library()
	else:
		hud.release_build_focus()
	_refresh_controller_hints()


func _on_controller_connection_changed(
	device: int,
	connected: bool
) -> void:
	if not connected or not _gameplay_started:
		return
	var controller_name := Input.get_joy_name(device)
	hud.toast(
		"%s connected — controller prompts are ready."
		% (controller_name if controller_name != "" else "Controller"),
		"good"
	)


func _refresh_controller_hints() -> void:
	if input_hints == null:
		return
	var actions: Array[Dictionary] = []
	if arrival_picker != null and arrival_picker.is_open():
		actions = [
			{"action": &"ui_accept", "label": "Choose your first land"},
		]
	elif (
		character_creator != null
		and is_instance_valid(character_creator)
	):
		actions = [
			{"action": &"ui_accept", "label": "Choose"},
		]
	elif asset_viewer != null and asset_viewer.is_open():
		actions = [
			{"action": &"look_right", "label": "Orbit"},
			{"action": &"camera_zoom_in", "label": "Zoom"},
			{"action": &"cancel", "label": "Return"},
		]
	elif pause_menu.is_open():
		actions = [
			{"action": &"ui_accept", "label": "Select"},
			{"action": &"cancel", "label": "Back"},
		]
	elif discovery_reveal.is_open():
		actions = [
			{"action": &"ui_accept", "label": "Choose land"},
		]
	elif panels.is_open():
		actions = [
			{"action": &"panel_previous", "label": "Previous page"},
			{"action": &"panel_next", "label": "Next page"},
			{"action": &"cancel", "label": "Close"},
		]
	elif placement.active:
		if not placement.held.is_empty():
			actions = [
				{"action": &"build_cursor_up", "label": "Move cursor"},
				{"action": &"camera_pan_up", "label": "Pan camera"},
				{"action": &"build_confirm", "label": "Place"},
				{"action": &"rotate_piece", "label": "Rotate"},
				{"action": &"cancel", "label": "Cancel"},
			]
			if placement.held.get("moving") != null:
				actions.insert(
					3,
					{"action": &"store_piece", "label": "Store"}
				)
		elif placement.controller_cursor_active():
			actions = [
				{"action": &"build_cursor_up", "label": "Move cursor"},
				{"action": &"camera_pan_up", "label": "Pan camera"},
				{"action": &"build_confirm", "label": "Interact"},
				{"action": &"move_piece", "label": "Move piece"},
				{"action": &"build_mode", "label": "Library"},
				{"action": &"cancel", "label": "Exit"},
			]
		else:
			actions = [
				{"action": &"ui_accept", "label": "Choose piece"},
				{"action": &"build_mode", "label": "Browse world"},
				{"action": &"cancel", "label": "Exit"},
			]
	else:
		actions = [
			{"action": &"move_up", "label": "Move"},
			{"action": &"jump", "label": "Jump"},
			{"action": &"build_mode", "label": "Build"},
			{"action": &"panel_map", "label": "Map"},
		]
		if not player.focus().is_empty():
			actions.insert(1, {"action": &"interact", "label": "Interact"})
	var has_interact_prompt := false
	for action: Dictionary in actions:
		if action.get("action", &"") == &"interact":
			has_interact_prompt = true
			break
	if (
		reward_reveal != null
		and reward_reveal.is_revealing()
		and not has_interact_prompt
	):
		actions.push_front({"action": &"interact", "label": "Hurry reward"})
	input_hints.set_context(actions)


# ------------------------------------------------------------------ click commands

func _handle_world_click(screen_position: Vector2) -> void:
	if panels.is_open() or discovery_reveal.is_open():
		return
	var interaction := _interaction_at_screen(screen_position)
	if interaction.is_empty():
		return
	var destination: Variant = interaction.get("point")
	if not destination is Vector3:
		return
	skill_actions.cancel_all()
	if player.state != PlayerController.State.FREE:
		player.set_state(PlayerController.State.FREE)
	player.set_click_command(destination, interaction)


func _try_build_world_action_at_screen(screen_position: Vector2) -> bool:
	var visitor: Dictionary = visitor_scene.call(
		"event_at_screen", camera_rig.camera, screen_position
	)
	if not visitor.is_empty():
		return bool(visitor_scene.call("interact", int(visitor["event_id"])))
	var hit := renderer.pick_structure_at_screen(camera_rig.camera, screen_position)
	return (
		_try_harvest_instance(int(hit.get("instance_id", 0)))
		if not hit.is_empty() else false
	)


func _try_build_world_action_at_cell(cell: Vector2i) -> bool:
	var visitor: Dictionary = visitor_scene.call("event_at_cell", cell)
	if not visitor.is_empty():
		return bool(visitor_scene.call("interact", int(visitor["event_id"])))
	return _try_harvest_instance(placement.controller_target_instance_id())


func _try_harvest_instance(instance_id: int) -> bool:
	if instance_id <= 0 or not bool(core.harvesting.call("can_harvest", instance_id)):
		return false
	var result: Dictionary = harvest_presentation.call(
		"request_hit", instance_id, "player"
	)
	if not bool(result.get("accepted", false)):
		var reason := String(result.get("reason", ""))
		if reason in ["maturing", "regrowing"]:
			hud.toast(
				"Growing — ready in %d seconds." % ceili(float(result.get("remaining", 0.0))),
				"common"
			)
	return true


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
			if bool(data.get("void", false)):
				hud.refresh_fishing_buttons()
		"basket_full":
			hud.toast("The Catch Basket is full. Take or return a haul to keep fishing.", "warn")
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


func _on_harvest_feedback(kind: String, data: Dictionary) -> void:
	match kind:
		"final":
			if String(data.get("presentation", "clay_tree")) == "clay_tree":
				audio.play_event("grove_rest")
			var reward: Dictionary = data.get("reward", {})
			if not reward.is_empty():
				var visual := renderer.structure_node(int(data.get("instance_id", 0)))
				var source_position := (
					visual.global_position
					if visual != null else Vector3.ZERO
				)
				reward_reveal.enqueue(
					reward,
					source_position,
					String(data.get("reveal_profile_id", ""))
				)
		"ready":
			audio.play_event("leaf_rustle")
			if core.onboarding.stage == OnboardingState.HARVEST_TREE:
				hud.toast("Your tree is ready.", "good")
	hud.update_tutorial()


func _on_visitor_reward_presented(reward: Dictionary) -> void:
	var name: String = core.build_rewards.call("display_name", reward)
	audio.play_event(
		"reward_rare" if String(reward.get("rarity", "common")) == "rare"
		else "reward_common"
	)
	hud.toast(
		"%d × %s dropped into your Build Library."
		% [int(reward.get("amount", 1)), name],
		"rare"
	)
	hud.update_tutorial()


func _on_onboarding_stage_changed(_stage: String) -> void:
	if hud == null:
		return
	hud.set_player_dock_visible(not core.onboarding.is_active())
	hud.update_tutorial()
	_refresh_controller_hints()


func _on_milestone_reached(_milestone_id: String, _rewards: Array) -> void:
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


## Taking a tile bundle from the basket checks its copies into the Build
## Library and enters the existing tile-placement mode holding that tile.
## Unplaced copies return to the bundle when build mode closes.
func _on_basket_tile_bundle_taken(haul_id: int, entry_index: int) -> void:
	var taken: Dictionary = core.fishing.basket.take_tile_bundle(haul_id, entry_index)
	if taken.is_empty():
		return
	panels.close()
	audio.play_event("build_preview")
	placement.hold_new("tile", String(taken["tile_id"]))


func _on_basket_model_taken(haul_id: int, entry_index: int) -> void:
	var structure_id: String = core.fishing.basket.take_model(haul_id, entry_index)
	if structure_id == "":
		return
	panels.close()
	audio.play_event("build_preview")
	placement.hold_new("structure", structure_id)


func _on_discovery_accepted(entry: Dictionary) -> void:
	audio.play_event("parcel_select")
	if String(entry.get("source", "")) == "delivery":
		core.arrivals.resolve_delivery()
	hud.update_tutorial()
	var kind := String(entry.get("kind", ""))
	var content_id := String(entry.get("id", ""))
	var display_name := content_id
	if kind == DiscoverySystem.KIND_TILE and core.registries.tile(content_id) != null:
		display_name = core.registries.tile(content_id).display_name
	elif kind == DiscoverySystem.KIND_STRUCTURE and core.registries.structure(content_id) != null:
		display_name = core.registries.structure(content_id).display_name
	hud.toast("%s added to your Build Bag." % display_name, "good")
	placement.hold_new(kind, content_id)


func _open_pending_discovery_when_ready() -> void:
	if discovery_reveal.is_open() or not core.progression.discovery.has_pending():
		return
	if player.state != PlayerController.State.FREE:
		await player.state_changed
	if panels.is_open():
		panels.close()
	discovery_reveal.open_pending()


func _on_placement_result(ok: bool, _message: String, kind: String) -> void:
	if kind.begins_with("place_"):
		audio.play_event(kind if ok else "build_invalid")
		hud.update_tutorial()
		if ok and _guided_placement_locked():
			call_deferred("_advance_guided_onboarding")
	elif kind == "invalid":
		audio.play_event("build_invalid")
	elif kind in ["undo", "redo", "pickup"]:
		audio.play_event("undo" if kind == "undo" else "redo" if kind == "redo" else "pickup")


func _on_focus_changed(focus: Dictionary) -> void:
	match focus.get("kind", ""):
		"void_fishing":
			hud.set_prompt(&"interact", "Fish into the unknown")
		"anchor":
			var anchor: Defs.AnchorDefinition = focus["anchor"]
			var skill := core.registries.skill(anchor.skill_id)
			hud.set_prompt(
				&"interact",
				"%s (%s)" % [skill.display_name, anchor.display_name]
			)
		"storage":
			hud.set_prompt(&"interact", "Open Tile & Build Library")
		"delivery_package":
			hud.set_prompt(&"interact", "Open the ferry's discovery")
		"enemy":
			hud.set_prompt(
				&"interact",
				"Attack",
				[
					{"action": &"jump", "label": "Jump"},
					{"action": &"dodge", "label": "Dodge"},
				]
			)
		"landmark_prompt":
			hud.set_prompt(&"interact", "Claim the watchpost")
		"feature_interaction":
			var option = focus.get("option")
			hud.set_prompt(
				&"interact",
				String(option.label) if option != null else "Interact"
			)
		_:
			hud.set_prompt(&"", "")
	_refresh_controller_hints()


func _on_click_interaction_reached(interaction: Dictionary) -> void:
	_perform_interaction(interaction)


func _perform_interaction(interaction: Dictionary) -> void:
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
	if not core.interactions.execute(option, "player"):
		return
	match String(option.feature_id):
		"camping":
			hud.toast("You settle into the shelter.", "good")
		"fire":
			var burning: bool = bool(
				core.fire.is_burning(option.target_instance_id)
			)
			hud.toast(
				"The fire catches." if burning else "The fire dies down.",
				"good"
			)
	core.autosave_soon()


func _on_fire_burning_changed(instance_id: int, burning: bool) -> void:
	var point: Vector3 = renderer.structure_fire_world_position(instance_id)
	var width: float = 0.56
	var found: Dictionary = core.grid.find_structure(instance_id)
	if not found.is_empty():
		var state: WorldGrid.StructureState = found["structure"]
		var definition := core.registries.structure(state.structure_id)
		if definition != null and definition.has_capability("fire"):
			width = float(
				definition.capability("fire").get("width", width)
			)
	renderer.set_structure_burning(instance_id, burning)
	if burning:
		effects.fire_ignition(point, width)
		audio.play_event("fire_crackle", -2.0, 1.08)
	else:
		effects.fire_extinguish(point, width)
		audio.play_event("leaf_rustle", -7.0, 0.72)


func _open_delivery_package() -> void:
	var reward := core.arrivals.open_waiting(core.progression)
	if reward.is_empty():
		return
	delivery_point.hide_package()
	audio.play_event("parcel_open")
	call_deferred("_open_pending_discovery_when_ready")


func _on_arrival_requested(payload: LandParcelPayload) -> void:
	if ferry_presentation != null:
		ferry_presentation.play(
			delivery_point, payload, core.registries.arrival_config
		)


func _on_presentation_arrival_started() -> void:
	audio.play_event("parcel_appear")
	hud.toast("A little ferry is approaching the northern dock.", "good")


func _on_presentation_delivery_ready(payload: LandParcelPayload) -> void:
	core.arrivals.mark_delivery_ready(payload)


func _on_delivery_ready(payload: LandParcelPayload) -> void:
	delivery_point.show_package(payload)
	audio.play_event("parcel_appear")
	hud.toast("A gift crate is waiting at the northern dock.", "good")


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
	fade.color = palette.color("ui_scene_fade")
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
	if not player.deployed:
		hud.toast("Drag your keeper onto the island first.", "warn")
		return
	player.teleport_home()
	camera_rig.reset_pan()
	hud.toast("Home again.", "good")


func _on_profile_applied(profile: VisualStyleProfile) -> void:
	audio.set_rain(profile.rain_enabled)
	hud.apply_weather_contrast(profile.rain_enabled or lighting.is_dark_background())
	for light in get_tree().get_nodes_in_group("warm_lights"):
		var omni := light as OmniLight3D
		lighting.refresh_local_light(omni)


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
		placement.set_active(true)
		player.dock_for_placement()
		hud.toast("Save reloaded.", "good")
		if player.deployed and is_instance_valid(pigeon_controller):
			pigeon_controller.spawn_near_player()


func reset_world() -> void:
	core.save_manager.delete_save()
	get_tree().reload_current_scene()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _gameplay_started:
		core.save()
