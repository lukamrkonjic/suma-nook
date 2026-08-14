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
const NookArrivalGhostScript := preload(
	"res://scripts/world/nook_arrival_ghost.gd"
)
const NookFrontierPickerScript := preload(
	"res://scripts/ui/nook_frontier_picker.gd"
)
const ProjectPanelScript := preload("res://scripts/ui/project_panel.gd")
const HarvestPresentationAdapterScript := preload(
	"res://scripts/features/harvesting/presentation/harvest_presentation_adapter.gd"
)
const ProvisionFishingSpotsScript := preload(
	"res://scripts/features/fishing/presentation/provision_fishing_spots.gd"
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
const DirectRewardPresenterScript := preload(
	"res://scripts/features/rewards/presentation/direct_reward_presenter.gd"
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
const DiscoveryTrayPanelScript := preload(
	"res://scripts/ui/discovery_tray_panel.gd"
)
const WorldheartPresenterScript := preload(
	"res://scripts/features/diorama/presentation/worldheart_presenter.gd"
)
const CollectionVibePanelScript := preload(
	"res://scripts/ui/collection_vibe_panel.gd"
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
var tile_selection: TileSelection
var _selection_pointer_down := false
var _selection_moving := false
var _selection_move_coord := Vector2i.ZERO
var _selection_press_position := Vector2.ZERO
var _selection_pointer_position := Vector2.ZERO
var _selection_rect_dirty := false
var _selection_preview_delta := Vector2i.ZERO
var frontier_markers: NookFrontierMarkers
var frontier_picker: CanvasLayer
var nook_arrival_ghost
var skill_actions: SkillActions
var harvest_presentation: Node
var provision_fishing_spots: ProvisionFishingSpots
var reward_reveal: RewardRevealSceneAdapter
var reward_reveal_presenter_registry: RewardRevealPresenterRegistry
var visitor_scene: Node3D
var worldheart_presenter: WorldheartPresenter
var visitor_presenter_registry: RefCounted
var hud: Hud
var pixel_look: PixelLook
const LightingTunerScript := preload("res://scripts/ui/lighting_tuner.gd")
const AssetViewerScript := preload("res://scripts/ui/asset_viewer.gd")
const PerformanceHudScript := preload("res://scripts/ui/performance_hud.gd")
const DebugMenuScript := preload("res://scripts/ui/debug_menu.gd")
var lighting_tuner: CanvasLayer
var asset_viewer: AssetViewer
var performance_hud
var debug_menu
var panels: GamePanels
var pause_menu: PauseMenu
var wish_offer_panel: WishOfferPanel
var arrival_picker: ArrivalLandPicker
var nook_offer_panel: NookOfferPanel
var project_panel: ProjectPanel
var discovery_tray_panel: DiscoveryTrayPanel
var collection_vibe_panel: CollectionVibePanel
var nook_reveal_presenter: NookRevealPresenter
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
var _debug_menu_visible_before_hide := false
var _controller_hud_hold_elapsed := 0.0
var _controller_hud_hold_active := false
var _controller_hud_hold_home_fired := false
var _player_dock_busy := false
var _player_drop_target: Dictionary = {}
var _pending_build_interaction: Dictionary = {}
var _worldheart_pointer_pressed := false
var _worldheart_pointer_press_position := Vector2.ZERO
var _worldheart_pointer_move_active := false
var _worldheart_offer_pointer_pressed := false
var _worldheart_controller_move_active := false
var _pending_vibe_fresh := true
var _nook_reveal_in_progress := false
var _queued_frontier_expansions: Array[Dictionary] = []


func _ready() -> void:
	# Window mode is settled by the DisplayBoot autoload, which runs before this
	# scene is even instantiated. Doing it here as well was still late enough to
	# show a fullscreen window for the whole of main.tscn's load.
	palette = load("res://assets/palettes/gg_material_palette.tres")
	materials = MaterialLibrary.new(palette)
	assets = AssetLibrary.new(materials)
	kit = UiKit.new(palette)

	core = GameCore.new()
	core.setup()
	# The scene acceptance runner deliberately exercises the archived guided
	# canvas. Production never sets this environment variable.
	if OS.get_environment("SUMA_LEGACY_OPENING") == "1":
		core.diorama.enabled = false
		core.harvesting.enabled = true
		core.visitors.enabled = true
		for structure_id: String in core.nooks.sapling_stage_zero_ids():
			core.stock.set_unlimited_structure(structure_id)
	var showcase_world_requested := _showcase_world_requested()
	var debug_world_tiles := _requested_debug_world_tiles()
	var debug_world_models := _requested_debug_world_models(
		debug_world_tiles
	)
	if debug_world_tiles > 0 or showcase_world_requested:
		_isolate_debug_save()
	if save_path_override != "":
		core.save_manager.save_path = save_path_override
		core.save_manager.backup_path = save_path_override + ".backup"

	_build_world_scene()
	_build_ui()
	_connect_flows()

	if showcase_world_requested:
		var showcase_profile := PlayerProfile.new()
		showcase_profile.display_name = "Garden Keeper"
		core.new_game(showcase_profile)
		debug_build_showcase_world()
		player_visual.apply_profile(core.profile)
		player_visual.apply_equipment(core.equipment)
		_start_gameplay(true)
	elif debug_world_tiles > 0:
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
		# Pre-rework saves can carry a half-finished guided lesson the
		# shipped seeded opening no longer supports. Never resume it into a
		# dead end: close the lesson and hand the world straight to play.
		if core.diorama.enabled and core.diorama.worldheart.vibe_collection_id == "":
			_pending_vibe_fresh = false
			player.position = core.profile.position
			player_visual.apply_profile(core.profile)
			player_visual.apply_equipment(core.equipment)
			_prepare_diorama_vibe_choice()
			collection_vibe_panel.open()
		elif core.onboarding.is_active() \
			and OS.get_environment("SUMA_LEGACY_OPENING") != "1":
			core.onboarding.set_stage(OnboardingState.COMPLETE)
			core.save()
			_start_gameplay(false)
		else:
			_start_gameplay(false)
			call_deferred("_resume_guided_onboarding")
	else:
		# The live loop starts immediately in the compact Worldheart garden;
		# there is no seed prompt or forced choice carousel.
		var opening_profile := PlayerProfile.new()
		opening_profile.display_name = "Keeper"
		core.new_game(opening_profile)
		player.position = core.profile.position
		player_visual.apply_profile(core.profile)
		player_visual.apply_equipment(core.equipment)
		if core.diorama.enabled:
			_pending_vibe_fresh = true
			_prepare_diorama_vibe_choice()
			collection_vibe_panel.open()
		else:
			_start_gameplay(true, false)
	_apply_debug_visual_overrides()
	_schedule_debug_capture()
	# Nook generation can select any registered biome. Stream its small model
	# vocabulary and canonical terrain layers gradually while the player is
	# already looking around, so the first Expand click does not pay cold GLB /
	# baked-scene presentation costs. Structure assets go first because their
	# smoothing profiles were the last measurable single-frame spike.
	if DisplayServer.get_name() != "headless":
		call_deferred("_prime_nook_generation_assets_async")


func _prime_nook_generation_assets_async() -> void:
	if assets == null or core == null:
		return
	var content_ids := {}
	for biome: NookDefs.NookBiomeDefinition in (
		core.registries.nook_biomes.values()
	):
		for pool_variant: Variant in biome.resolve.values():
			var pool := pool_variant as NookDefs.SlotPool
			if pool == null:
				continue
			for content_id: String in pool.ids:
				content_ids[content_id] = true

	var structure_assets: Array = []
	var tile_assets: Array = []
	var seen_structure_assets := {}
	var seen_tile_assets := {}
	for content_id: String in content_ids:
		var structure_definition := core.registries.structure(content_id)
		if structure_definition != null:
			var structure_asset_id: String = structure_definition.asset_id
			if not seen_structure_assets.has(structure_asset_id):
				seen_structure_assets[structure_asset_id] = true
				structure_assets.append(structure_asset_id)
			continue
		var tile_definition := core.registries.tile(content_id)
		if tile_definition == null:
			continue
		if not tile_definition.uses_layered_visual():
			if not seen_tile_assets.has(tile_definition.asset_id):
				seen_tile_assets[tile_definition.asset_id] = true
				tile_assets.append(tile_definition.asset_id)
			continue
		for layer: Defs.TileVisualLayerDefinition in (
			tile_definition.visual_layers
		):
			if not seen_tile_assets.has(layer.asset_id):
				seen_tile_assets[layer.asset_id] = true
				tile_assets.append(layer.asset_id)

	await assets.prime_packed_scenes_async(structure_assets)
	await assets.prime_presentations_async(structure_assets)
	await assets.prime_packed_scenes_async(tile_assets)
	await assets.prime_presentations_async(tile_assets)


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
	provision_fishing_spots = ProvisionFishingSpotsScript.new()
	provision_fishing_spots.name = "ProvisionFishingSpots"
	world_root.add_child(provision_fishing_spots)
	provision_fishing_spots.setup(core, assets, effects)

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
	interaction_targets.call("set_provision_fishing_spots", provision_fishing_spots)
	if core.diorama.enabled:
		worldheart_presenter = WorldheartPresenterScript.new()
		worldheart_presenter.name = "Worldheart"
		world_root.add_child(worldheart_presenter)

	placement = PlacementController.new()
	placement.name = "Placement"
	world_root.add_child(placement)
	placement.setup(core, assets, camera_rig, player, effects, renderer)
	tile_selection = TileSelection.new(core.grid)
	frontier_markers = NookFrontierMarkers.new()
	frontier_markers.name = "NookFrontierMarkers"
	world_root.add_child(frontier_markers)
	frontier_markers.setup(core, camera_rig.camera, placement, palette)
	interaction_targets.call("set_frontier_markers", frontier_markers)
	nook_arrival_ghost = NookArrivalGhostScript.new()
	nook_arrival_ghost.name = "NookArrivalGhost"
	world_root.add_child(nook_arrival_ghost)
	nook_arrival_ghost.setup(core)

	skill_actions = SkillActions.new()
	skill_actions.name = "SkillActions"
	add_child(skill_actions)

	audio = GameAudio.new()
	audio.name = "Audio"
	add_child(audio)
	if worldheart_presenter != null:
		worldheart_presenter.renderer = renderer
		worldheart_presenter.setup(core, assets, audio, camera_rig.camera, kit)
		worldheart_presenter.visible = false
		interaction_targets.call("set_worldheart_presenter", worldheart_presenter)
		placement.add_interaction_hover_provider(worldheart_presenter)

	renderer.setup(core, assets)
	harvest_presentation.call("setup", core.harvesting, renderer, effects, audio)
	reward_reveal_presenter_registry = RewardRevealPresenterRegistryScript.new()
	reward_reveal_presenter_registry.register(
		"world_bud",
		func(): return WorldBudRewardPresenterScript.new() as Node3D
	)
	reward_reveal_presenter_registry.register(
		"direct_reward",
		func(): return DirectRewardPresenterScript.new() as Node3D
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
	# VisitorScene is assembled after the generic resolver. Bind it here, once
	# the real adapter exists, so mouse and controller targeting can reach live
	# visitors as well as the gifts they leave behind.
	interaction_targets.call("set_visitor_scene", visitor_scene)
	placement.add_interaction_hover_provider(visitor_scene)
	player.setup(core, camera_rig, player_visual)
	player.set_provision_fishing_spots(provision_fishing_spots)
	pigeon_mascot = PIGEON_MASCOT_SCENE.instantiate() as CharacterBody3D
	pigeon_mascot.name = "PigeonMascot"
	world_root.add_child(pigeon_mascot)
	pigeon_controller = pigeon_mascot.get_node("MascotController") as PigeonMascotController
	pigeon_controller.setup(player, core.grid)
	if core.diorama.enabled:
		player.visible = false
		player_visual.visible = false
		pigeon_mascot.visible = false
		pigeon_mascot.process_mode = Node.PROCESS_MODE_DISABLED
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
	placement.set_ui_pointer_blocker(
		Callable(self, "_screen_position_blocked_by_ui")
	)

	panels = GamePanels.new()
	panels.name = "Panels"
	add_child(panels)
	panels.setup(core, kit, self)

	wish_offer_panel = WishOfferPanel.new()
	wish_offer_panel.name = "WishOfferPanel"
	add_child(wish_offer_panel)
	wish_offer_panel.setup(core, kit, assets)

	arrival_picker = ArrivalLandPicker.new()
	arrival_picker.name = "ArrivalLandPicker"
	add_child(arrival_picker)
	arrival_picker.setup(core, kit, assets)

	nook_offer_panel = NookOfferPanel.new()
	nook_offer_panel.name = "NookOfferPanel"
	add_child(nook_offer_panel)
	nook_offer_panel.setup(core, kit)

	project_panel = ProjectPanelScript.new()
	project_panel.name = "ProjectPanel"
	add_child(project_panel)
	project_panel.setup(core, kit)
	project_panel.panel_toggled.connect(func(_open): _refresh_controller_hints())
	collection_vibe_panel = CollectionVibePanelScript.new()
	collection_vibe_panel.name = "CollectionVibePanel"
	add_child(collection_vibe_panel)
	collection_vibe_panel.setup(core, kit)

	# Optional composition: the world-facing requirements card can be removed
	# without changing the direct click/controller activation path.
	if _frontier_picker_enabled() and not core.diorama.enabled:
		frontier_picker = NookFrontierPickerScript.new()
		frontier_picker.name = "NookFrontierPicker"
		add_child(frontier_picker)
		frontier_picker.call("setup", core, kit, frontier_markers, placement)
		frontier_picker.connect("frontier_activated", _activate_frontier)
		frontier_picker.connect(
			"panel_toggled", func(_open): _refresh_controller_hints()
		)

	nook_reveal_presenter = NookRevealPresenter.new()
	nook_reveal_presenter.name = "NookRevealPresenter"
	add_child(nook_reveal_presenter)
	nook_reveal_presenter.setup(core, renderer)

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
	if OS.is_debug_build():
		debug_menu = DebugMenuScript.new()
		debug_menu.name = "DebugMenu"
		add_child(debug_menu)
		debug_menu.setup(core, kit, self)
	camera_rig.set_input_blocker(Callable(self, "_camera_input_blocked_by_ui"))


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


## Leaves the larger diagnostic tools in Pause -> Admin, while giving both
## mouse and controller users a route into the compact live-world card.
func open_debug_menu() -> void:
	if not OS.is_debug_build() or debug_menu == null:
		return
	if pause_menu.is_open():
		pause_menu.close()
	debug_menu.show_and_focus()


func debug_prompt_skyfall() -> bool:
	if not OS.is_debug_build() or wish_offer_panel == null:
		return false
	var choices := core.progression.discovery.prepare_wish_offer(true)
	if choices.is_empty() and not core.progression.discovery.has_pending():
		return false
	wish_offer_panel.notify_ready(false)
	wish_offer_panel.open_pending()
	return wish_offer_panel.is_open()


## Forces the Worldheart to surface a gift now, so the well's stir and launch
## can be watched without waiting for a pulse.
##
## _roll_pulse_reward can legitimately return nothing -- it draws from the
## collection members currently eligible for the next role, and with none
## eligible there is no reward to roll. Relying on it alone made the button
## report failure rather than do the one thing it exists for, so it falls back to
## any registered piece.
func debug_wardrobe_gift() -> bool:
	if not OS.is_debug_build() or not core.diorama.enabled:
		return false
	var worldheart := core.diorama.worldheart
	if worldheart == null:
		return false
	# A full queue is the normal state once gifts have accumulated -- reserve_cap
	# defaults to 12 -- and enqueueing into it always fails. That is what made the
	# button report "could not queue": there was nothing wrong except that the
	# well already had twelve gifts waiting. So deliver one instead, which is
	# what "give me an item" actually means, and only enqueue when it is empty.
	if not worldheart.reward_queue.is_empty():
		var waiting := String(
			worldheart.reward_queue[0].get("entry_id", "")
		)
		if worldheart.claim(waiting).is_empty():
			return false
		_debug_swing_wardrobe()
		return true
	var reward: Dictionary = worldheart._roll_pulse_reward()
	if reward.is_empty():
		reward = _any_debug_reward(worldheart)
	if reward.is_empty():
		return false
	if not worldheart.enqueue_external_reward(reward, "debug"):
		return false
	var queued := String(worldheart.reward_queue[-1].get("entry_id", ""))
	if worldheart.claim(queued).is_empty():
		return false
	_debug_swing_wardrobe()
	return true


## Runs the stir/settle directly. Claiming a gift changes state but does not
## itself animate the well, and watching the animation is the whole point of the
## button.
func _debug_swing_wardrobe() -> void:
	if worldheart_presenter == null:
		return
	worldheart_presenter.call("_stir_well")
	await get_tree().create_timer(1.1).timeout
	if worldheart_presenter != null:
		worldheart_presenter.call("_settle_well", true)


## Any valid reward, decorated the way a rolled one would be so the queue and the
## presentation treat it identically.
func _any_debug_reward(worldheart: Object) -> Dictionary:
	for structure_id: String in core.registries.structures:
		return worldheart._decorate_reward(
			{"kind": "structure", "id": structure_id}, "detail"
		)
	for tile_id: String in core.registries.tiles:
		return worldheart._decorate_reward(
			{"kind": "tile", "id": tile_id}, "terrain"
		)
	return {}


func debug_grant_all_items(amount := 99) -> int:
	if not OS.is_debug_build():
		return 0
	var grant_amount := maxi(1, amount)
	for item_id in core.registries.items:
		core.inventory.grant(String(item_id), grant_amount, false, true)
	return core.registries.items.size()


func debug_grant_all_tiles(amount := 99) -> int:
	if not OS.is_debug_build():
		return 0
	var tile_ids := core.registries.obtainable_tile_ids()
	var grant_amount := maxi(1, amount)
	for tile_id in tile_ids:
		core.stock.add_tile(String(tile_id), grant_amount)
	return tile_ids.size()


func debug_grant_all_models(amount := 99) -> int:
	if not OS.is_debug_build():
		return 0
	var grant_amount := maxi(1, amount)
	for structure_id in core.registries.structures:
		core.stock.add_structure(String(structure_id), grant_amount)
	return core.registries.structures.size()


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
		if debug_menu != null:
			debug_menu.visible = _debug_menu_visible_before_hide
		if discovery_tray_panel != null:
			discovery_tray_panel.set_hud_suppressed(false)
		_refresh_controller_hints()
		return false
	_hud_visible_before_hide = hud != null and hud.visible
	_input_hints_visible_before_hide = (
		input_hints != null and input_hints.visible
	)
	_performance_hud_visible_before_hide = (
		performance_hud != null and performance_hud.visible
	)
	_debug_menu_visible_before_hide = debug_menu != null and debug_menu.visible
	_hud_hidden = true
	if hud != null:
		hud.visible = false
	if input_hints != null:
		input_hints.visible = false
	if performance_hud != null:
		performance_hud.visible = false
	if debug_menu != null:
		debug_menu.visible = false
	if discovery_tray_panel != null:
		discovery_tray_panel.set_hud_suppressed(true)
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

# A separate art-direction vignette for screenshots and visual review. Unlike
# the mock/testing island above, this is deliberately composed as a lived-in
# garden: shaded woodland, flowers, a wandering path, a pond and dock, garden
# beds, a tiny paved court, and a warm plank porch share one organic island.
const SHOWCASE_WORLD_ORIGIN := Vector2i(-4, -3)
const SHOWCASE_WORLD_TILES := {
	"G": "tile_grass",
	"F": "tile_grass_flower",
	"M": "tile_grove_mossy",
	"P": "tile_path",
	"W": "tile_open_water",
	"S": "tile_sand",
	"D": "tile_garden",
	"C": "tile_cobblestone",
	"B": "tile_wooden_planks",
}
const SHOWCASE_WORLD_ROWS := [
	"..MMGGGG..",
	".MMFGFGGG.",
	"MGGPPGGGGG",
	"GGGPPGGWWG",
	"GGDPSGSWWG",
	"GGDPSSGWWG",
	".GCCPGGGG.",
	"..GGBBGG..",
]
const SHOWCASE_WORLD_STRUCTURES := [
	[Vector2i(-3, -3), "struct_pine_tall", 0],
	[Vector2i(-2, -2), "struct_pine", 1],
	[Vector2i(-1, -2), "struct_birdbath", 0],
	[Vector2i(1, -2), "struct_planter", 1],
	[Vector2i(-2, 0), "struct_wheelbarrow", 3],
	[Vector2i(2, 0), "struct_bench", 2],
	[Vector2i(3, 0), "struct_dock", 1],
	[Vector2i(-2, 1), "struct_garden_trellis", 0],
	[Vector2i(-3, 2), "struct_watering_can", 2],
	[Vector2i(0, 2), "struct_lantern", 0],
	[Vector2i(2, 2), "struct_campfire", 0],
	[Vector2i(4, 2), "struct_log_pile", 1],
	[Vector2i(-2, 3), "struct_stone_well", 0],
	[Vector2i(0, 3), "struct_wooden_arch", 0],
	[Vector2i(0, 4), "struct_barrel", 0],
	[Vector2i(1, 4), "struct_pot", 0],
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


func debug_build_showcase_world() -> Dictionary:
	if not OS.is_debug_build():
		return {}
	core.autosave_paused = true
	if placement != null and placement.active:
		placement.cancel_click()
	core.grid.cells.clear()
	core.grid.stacked_cells.clear()
	core.grid.next_instance_id = 1
	core.grid.home_cell = Vector2i.ZERO
	core.landmarks.active.clear()
	var tile_count := 0
	for row_index in SHOWCASE_WORLD_ROWS.size():
		var row: String = SHOWCASE_WORLD_ROWS[row_index]
		for col in row.length():
			var tile_id: String = SHOWCASE_WORLD_TILES.get(row[col], "")
			if tile_id.is_empty():
				continue
			core.grid.place_tile(
				SHOWCASE_WORLD_ORIGIN + Vector2i(col, row_index),
				tile_id
			)
			tile_count += 1
	var structure_count := 0
	for spec in SHOWCASE_WORLD_STRUCTURES:
		if core.grid.add_structure(
			spec[0],
			String(spec[1]),
			_mock_socket(String(spec[1])),
			int(spec[2])
		) != null:
			structure_count += 1
	core.grid.rebuild_structure_index()
	core._rebuild_resting_anchors()
	core.profile.position = core.grid.cell_to_world(Vector2i(0, 1))
	core.profile.facing = PI
	renderer.rebuild_all()
	player.global_position = core.profile.position + Vector3(0, 0.05, 0)
	player.rotation.y = core.profile.facing
	player.suspend_water_rescue()
	player.cancel_click_command()
	delivery_point._sync_to_dock()
	hud._refresh_all()
	hud.update_tutorial()
	return {
		"tiles": tile_count,
		"models": structure_count,
		"theme": "mosslight_garden",
	}


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


func _showcase_world_requested() -> bool:
	return "--showcase-world" in OS.get_cmdline_user_args()


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
	if _showcase_world_requested():
		# The showcase is a clean art-review scene. Keep its composition free of
		# build outlines and onboarding chrome; H can restore the HUD at any time.
		placement.set_active(false)
		renderer.clear_structure_hover()
		if not _hud_hidden:
			toggle_all_hud()
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
	hud.token_pouch_requested.connect(func(): panels.toggle("inventory"))
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
	hud.worldheart_offer_requested.connect(_on_worldheart_offer_requested)
	collection_vibe_panel.vibe_selected.connect(_on_starting_vibe_selected)
	if discovery_tray_panel != null:
		discovery_tray_panel.offer_selected.connect(_on_diorama_offer_selected)
		discovery_tray_panel.gift_selected.connect(_on_world_gift_selected)
	arrival_picker.land_chosen.connect(_on_first_land_chosen)
	wish_offer_panel.reveal_finished.connect(_on_discovery_accepted)
	wish_offer_panel.reveal_started.connect(
		func(_entry): _refresh_controller_hints()
	)
	wish_offer_panel.panel_toggled.connect(
		func(_open): _refresh_controller_hints()
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
	nook_reveal_presenter.reveal_started.connect(_on_nook_reveal_started)
	nook_reveal_presenter.terrain_cell_landed.connect(
		_on_nook_reveal_cell_landed
	)
	nook_reveal_presenter.reveal_finished.connect(_on_nook_reveal_finished)

	skill_actions.action_feedback.connect(_on_action_feedback)
	skill_actions.storage_requested.connect(func(): panels.toggle("inventory"))
	skill_actions.delivery_package_requested.connect(_open_delivery_package)
	skill_actions.landmark_prompt_requested.connect(func(node):
		panels.show_landmark_choice(String(node.get_meta("landmark_id"))))

	placement.action_result.connect(_on_placement_result)
	placement.tile_splashed.connect(
		func(_impact_position: Vector3, _landing_position: Vector3):
			audio.play_event("fish_splash")
	)
	placement.mode_changed.connect(func(_active): _refresh_controller_hints())
	placement.held_changed.connect(func(_held): _refresh_controller_hints())
	player.interaction_focus_changed.connect(_on_focus_changed)
	player.click_interaction_reached.connect(_on_click_interaction_reached)
	player.arrival_choice_ready.connect(_open_first_land_picker)
	player.arrival_landed.connect(_on_first_arrival_landed)
	player.worldheart_arrival_finished.connect(func():
		player.dock_for_placement()
	)
	player.deployment_changed.connect(_on_player_deployment_changed)
	core.fire.burning_changed.connect(_on_fire_burning_changed)
	core.frontiers.expansion_ready.connect(_begin_frontier_expansion)
	core.projects.project_reward_granted.connect(_on_project_reward_granted)
	core.special_finds.special_find_spawned.connect(_on_special_find_spawned)
	core.special_finds.special_find_collected.connect(_on_special_find_collected)
	core.reward_drops.reward_claimed.connect(_on_reward_drop_claimed)
	core.diorama.gifts.expansion_requested.connect(func(coord, seed_card):
		_begin_frontier_expansion(coord, "", seed_card)
	)
	core.diorama.gifts.targeting_changed.connect(func(_gift_id):
		if frontier_markers != null:
			frontier_markers.rebuild()
		_update_frontier_marker_availability()
		_refresh_controller_hints()
	)
	core.diorama.worldheart.pulse_queued.connect(_on_worldheart_pulse)
	core.diorama.worldheart.exchange_rejected.connect(func(message: String):
		hud.toast(message, "warn")
	)
	core.diorama.curiosities.curiosity_landed.connect(_on_curiosity_landed)
	core.diorama.curiosities.curiosity_opened.connect(_on_curiosity_opened)
	core.diorama.collections.milestone_reached.connect(
		_on_creative_collection_milestone
	)

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
	provision_fishing_spots.feedback.connect(_on_provision_fishing_feedback)
	provision_fishing_spots.spot_state_changed.connect(
		_on_provision_fishing_state_changed
	)
	reward_reveal.reveal_started.connect(func(_reward):
		_refresh_controller_hints()
	)
	reward_reveal.reveal_finished.connect(func(_reward):
		_refresh_controller_hints()
	)
	core.token_pouch.box_opened.connect(_on_token_box_opened)
	visitor_scene.connect("reward_presented", _on_visitor_reward_presented)
	visitor_scene.connect("vase_smashed", _on_visitor_vase_smashed)
	visitor_scene.connect("visitor_greeted", _on_visitor_greeted)
	core.visitors.visitor_available.connect(func(_event):
		hud.toast("A curious visitor has arrived.", "rare")
		audio.play_event("parcel_appear")
	)
	core.visitors.visitor_vase_ready.connect(func(_event):
		hud.toast("Your visitor left a little gift behind.", "good")
		_refresh_controller_hints()
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


## Compatibility hook for archived seeded-opening fixtures. The live fresh-save
## path starts directly in the Worldheart garden above.
func _begin_seeded_opening(opening_profile: PlayerProfile) -> void:
	if OS.get_environment("SUMA_LEGACY_OPENING") == "1" \
		or not core.registries.feature("nooks_enabled", true):
		# Feature flag off: the legacy guided canvas is the fallback.
		core.begin_build_onboarding(opening_profile)
		renderer.rebuild_all()
		player_visual.apply_profile(core.profile)
		player_visual.apply_equipment(core.equipment)
		_start_gameplay(true, false)
		call_deferred("_resume_guided_onboarding")
		return
	get_tree().paused = false
	_gameplay_started = false
	hud.visible = false
	player_visual.apply_profile(opening_profile)
	nook_offer_panel.first_seed_chosen.connect(func(card: Dictionary):
		core.begin_seeded_game(opening_profile, card)
		player.position = core.profile.position
		player_visual.apply_profile(core.profile)
		player_visual.apply_equipment(core.equipment)
		_start_gameplay(true, false)
	, CONNECT_ONE_SHOT)
	nook_offer_panel.open_for_first_boot()


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


func _on_starting_vibe_selected(collection_id: String) -> void:
	if not core.choose_diorama_starting_vibe(collection_id):
		collection_vibe_panel.open()
		return
	renderer.rebuild_all()
	if worldheart_presenter != null:
		worldheart_presenter.visible = true
		worldheart_presenter.prime_reward_collection()
	core.save()
	_start_gameplay(_pending_vibe_fresh, false)


func _prepare_diorama_vibe_choice() -> void:
	_gameplay_started = false
	hud.visible = false
	if project_panel != null:
		project_panel.set_hud_visible(false)
	player.visible = false
	player_visual.visible = false
	player.set_state(PlayerController.State.DISABLED)
	if pigeon_mascot != null:
		pigeon_mascot.visible = false
	if worldheart_presenter != null:
		worldheart_presenter.visible = false
	renderer.rebuild_all()
	_refresh_controller_hints()


func _start_gameplay(fresh: bool, show_welcome := true) -> void:
	_gameplay_started = true
	hud.visible = true
	if project_panel != null:
		project_panel.set_hud_visible(not core.diorama.enabled)
	if discovery_tray_panel != null:
		discovery_tray_panel.visible = true
	if debug_menu != null and not _hud_hidden:
		debug_menu.show_for_gameplay()
	player.set_state(
		PlayerController.State.DISABLED
		if core.diorama.enabled else PlayerController.State.FREE
	)
	player.visible = not core.diorama.enabled
	player_visual.visible = not core.diorama.enabled
	if pigeon_mascot != null:
		pigeon_mascot.visible = not core.diorama.enabled
	if worldheart_presenter != null:
		worldheart_presenter.visible = core.diorama.enabled
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
	# Calm god-view interaction is the default. Build/edit mode is an explicit
	# intent so a fire click can never also pick the firepit up.
	placement.set_active(false)
	if core.diorama.enabled:
		# CameraRig historically follows the keeper. Worldheart deliberately has
		# no keeper, so park that hidden anchor on the stable home tile and remove
		# it from physics. This also repairs saves made while the old hidden body
		# was falling and dragging the camera down.
		player.position = core.grid.cell_to_world(core.grid.home_cell)
		player.dock_for_placement(false)
	else:
		player.dock_for_placement()
	player_drop_preview.visible = false
	frontier_markers.rebuild()
	if not core.diorama.enabled:
		for frontier: Dictionary in core.frontiers.pending_expansions():
			call_deferred(
				"_begin_frontier_expansion",
				Vector2i(frontier["coord"][0], frontier["coord"][1]),
				String(frontier.get("project_id", "")),
				(frontier.get("seed_card", {}) as Dictionary).duplicate(true)
			)
	hud.update_tutorial()
	if fresh and core.diorama.enabled:
		hud.toast("The Worldheart is waking. Its gifts can wait until you are ready.", "good")
	if show_welcome:
		hud.toast("Welcome%s, %s." % ["" if fresh else " back", core.profile.display_name], "good")
	if fresh and not core.diorama.enabled and core.projects.tracked_project().is_empty():
		hud.toast(
			"Choose a Project and contribute a few things from your world.",
			"good"
		)
	core.arrivals.announce_restored_delivery()
	if not core.diorama.enabled:
		wish_offer_panel.notify_ready(false)
		visitor_scene.call("sync_from_module")
	_refresh_controller_hints()
	if (
		not core.diorama.enabled
		and player.deployed
		and is_instance_valid(pigeon_controller)
	):
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
	_update_frontier_marker_availability()
	if not _gameplay_started:
		return
	if _selection_rect_dirty and _selection_pointer_down and not _selection_moving:
		_resolve_tile_selection_rect()
	if (
		_worldheart_offer_pointer_pressed
		and (
			placement.held.is_empty()
			or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		)
	):
		# Focus loss or a GUI-consumed release cancels safely. The piece remains
		# held; only the explicit world release path below may consume it.
		_cancel_worldheart_offer_pointer()
	_sync_worldheart_offer_preview()
	_tick_controller_hud_hold(delta)
	core.major_events_blocked = (
		pause_menu.is_open()
		or panels.is_open()
		or project_panel.is_open()
		or wish_offer_panel.is_open()
		or nook_offer_panel.is_open()
		or discovery_tray_panel != null and discovery_tray_panel.has_focus()
		or (asset_viewer != null and asset_viewer.is_open())
	)
	var worldheart_interaction_busy := (
		core.major_events_blocked
		or hud.build_library_expanded()
		or not placement.held.is_empty()
		or placement.pointer_is_down()
		or _worldheart_pointer_pressed
		or _worldheart_pointer_move_active
		or _worldheart_offer_pointer_pressed
		or _worldheart_controller_move_active
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	)
	core.diorama.worldheart.set_generation_paused(
		&"player_interaction", worldheart_interaction_busy
	)
	if worldheart_presenter != null:
		worldheart_presenter.set_player_interaction_busy(
			worldheart_interaction_busy
		)
	core.tick(delta)
	if not core.diorama.enabled:
		_tick_footsteps(delta)


func _sync_worldheart_offer_preview() -> void:
	if worldheart_presenter == null:
		return
	if (
		not core.diorama.enabled
		or placement.held.is_empty()
		or pause_menu.is_open()
		or panels.is_open()
		or project_panel.is_open()
	):
		placement.set_external_offer_preview(false)
		worldheart_presenter.clear_offering_preview()
		return
	var over_hole := false
	if InputDeviceService.shared().is_controller():
		over_hole = (
			placement.controller_cursor_active()
			and placement.controller_cursor_cell()
				== core.diorama.worldheart.worldheart_cell
		)
	else:
		# Either test starts the offer: the tight screen radius around the mouth,
		# or simply hovering the well's own cell. The cell test is what makes the
		# handover seamless -- it is exactly the condition under which the
		# placement ghost stands down, so the offering preview takes over in the
		# same frame instead of leaving a gap the invalid state used to fill.
		over_hole = (
			worldheart_presenter.hole_at_screen(
				camera_rig.camera,
				get_viewport().get_mouse_position(),
				58.0 if worldheart_presenter.has_offering_preview() else 42.0
			)
			or placement.hover_cell() == core.diorama.worldheart.worldheart_cell
		)
	var previewing := false
	if over_hole:
		previewing = worldheart_presenter.show_offering_preview(
			String(placement.held.get("kind", "")),
			String(placement.held.get("id", "")),
			placement.external_offer_preview_origin(),
			true
		)
	else:
		worldheart_presenter.clear_offering_preview()
	placement.set_external_offer_preview(previewing)


func _update_frontier_marker_availability() -> void:
	if frontier_markers == null:
		return
	var enabled: bool = (
		_gameplay_started
		and (
			not core.diorama.enabled
			or core.diorama.gifts.is_targeting_expansion()
		)
		and not placement.active
		and placement.held.is_empty()
		and not _nook_reveal_in_progress
		and not pause_menu.is_open()
		and not panels.is_open()
		and not project_panel.is_open()
		and not wish_offer_panel.is_open()
		and not nook_offer_panel.is_open()
		and (asset_viewer == null or not asset_viewer.is_open())
	)
	frontier_markers.set_interaction_enabled(enabled)
	if frontier_picker != null:
		frontier_picker.call(
			"set_interaction_enabled",
			enabled and _frontier_picker_enabled()
		)


func _frontier_picker_enabled() -> bool:
	return (
		core != null
		and not core.diorama.enabled
		and core.registries.feature("nook_frontier_picker_enabled", true)
	)


func _on_nook_reveal_started(coord: Vector2i, duration: float) -> void:
	_nook_reveal_in_progress = true
	if nook_arrival_ghost != null:
		nook_arrival_ghost.begin_landing(coord, duration)
	_update_frontier_marker_availability()


func _on_nook_reveal_cell_landed(coord: Vector2i, cell: Vector2i) -> void:
	if nook_arrival_ghost != null:
		nook_arrival_ghost.land_cell(coord, cell)


func _on_nook_reveal_finished(coord: Vector2i) -> void:
	_nook_reveal_in_progress = false
	if nook_arrival_ghost != null and nook_arrival_ghost.is_previewing(coord):
		nook_arrival_ghost.cancel_preview(coord)
	if frontier_markers != null:
		frontier_markers.rebuild()
	_update_frontier_marker_availability()
	if core.diorama.enabled and coord != Vector2i.ZERO:
		core.diorama.curiosities.spawn_for_new_land(coord)
	_refresh_controller_hints()
	_start_next_frontier_expansion()


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
	if (
		_gameplay_started
		and core.diorama.enabled
		and core.diorama.gifts.is_targeting_expansion()
		and event.is_action_pressed("cancel")
		and not placement.active
		and (discovery_tray_panel == null or not discovery_tray_panel.has_focus())
	):
		core.diorama.gifts.cancel_targeting()
		get_viewport().set_input_as_handled()
		return
	# Return focus from the compact frontier picker before Escape's global pause
	# alias gets a chance to open another layer over it.
	if (
		_gameplay_started
		and frontier_picker != null
		and bool(frontier_picker.call("has_focus"))
		and event.is_action_pressed("cancel")
	):
		frontier_picker.call("close_controller_focus")
		_refresh_controller_hints()
		get_viewport().set_input_as_handled()
		return
	# A held placement owns Escape even when a Build Bag control has focus.
	# Handle it before the global pause shortcut so the piece is restored or
	# returned to stock instead of trapping the player behind the pause menu.
	if (
		_gameplay_started
		and event is InputEventKey
		and not event.echo
		and event.is_action_pressed("cancel")
		and placement.active
		and not placement.held.is_empty()
	):
		_cancel_build_or_open_library()
		get_viewport().set_input_as_handled()
		return
	# Outside an active placement, Escape remains the global pause shortcut.
	if (
		_gameplay_started
		and event is InputEventKey
		and event.is_action_pressed("pause")
		and not pause_menu.is_open()
		and not wish_offer_panel.is_open()
		and not project_panel.is_open()
		and (asset_viewer == null or not asset_viewer.is_open())
	):
		open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if (
		_gameplay_started
		and not pause_menu.is_open()
		and not wish_offer_panel.is_open()
		and not project_panel.is_open()
		and not panels.is_open()
		and (asset_viewer == null or not asset_viewer.is_open())
	):
		if _handle_tile_selection_input(event):
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseMotion and _worldheart_pointer_pressed:
			var worldheart_motion := event as InputEventMouseMotion
			if (
				not _worldheart_pointer_move_active
				and worldheart_motion.position.distance_to(
					_worldheart_pointer_press_position
				) >= 7.0
			):
				_worldheart_pointer_move_active = true
				renderer.clear_structure_hover()
				worldheart_presenter.begin_move_preview()
			if _worldheart_pointer_move_active:
				_preview_worldheart_move(worldheart_motion.position)
			return
		if event is InputEventMouseMotion and _worldheart_offer_pointer_pressed:
			# The held piece remains a Worldheart preview until release. Never let
			# the same motion fall through to ordinary placement or camera input.
			return
		if event is InputEventMouseMotion and placement.pointer_is_down():
			placement.pointer_motion(
				(event as InputEventMouseMotion).position
			)
			return
		if (
			event is InputEventMouseButton
			and event.is_action_pressed("rotate_piece")
		):
			var rotate_mouse := event as InputEventMouseButton
			if _screen_position_blocked_by_ui(rotate_mouse.position):
				return
			if _rotate_build_target_at_screen(rotate_mouse.position):
				get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			var build_mouse := event as InputEventMouseButton
			if build_mouse.button_index == MOUSE_BUTTON_LEFT:
				if build_mouse.pressed:
					if _screen_position_blocked_by_ui(build_mouse.position):
						return
					_begin_build_pointer(build_mouse.position)
					get_viewport().set_input_as_handled()
					return
				if (
					placement.pointer_is_down()
					or _worldheart_pointer_pressed
					or _worldheart_pointer_move_active
					or _worldheart_offer_pointer_pressed
				):
					# A dragged world piece released over the Build Bag is stored by
					# HUD polling; ordinary world releases commit here immediately.
					if (
						_screen_position_blocked_by_ui(build_mouse.position)
						and placement.pointer_dragging_moved_piece()
					):
						return
					_finish_build_pointer(build_mouse.position)
					get_viewport().set_input_as_handled()
					return
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	if _screen_position_blocked_by_ui(mouse.position):
		return
	if (
		_gameplay_started
		and not placement.active
		and not panels.is_open()
		and not wish_offer_panel.is_open()
		and not _interaction_at_screen(mouse.position).is_empty()
	):
		effects.click_marker(mouse.position, true)


func _screen_position_blocked_by_ui(screen_position: Vector2) -> bool:
	# Any mouse-enabled Control shields the world, including empty panel space.
	# Restricting this to buttons allowed selection and right-click actions to
	# leak through the Build Bag background.
	if collection_vibe_panel != null and collection_vibe_panel.is_open():
		return true
	if (
		wish_offer_panel != null
		and wish_offer_panel.blocks_world_pointer(screen_position)
	):
		return true
	if (
		discovery_tray_panel != null
		and discovery_tray_panel.blocks_world_pointer(screen_position)
	):
		return true
	if project_panel != null and project_panel.blocks_world_pointer(screen_position):
		return true
	if (
		frontier_picker != null
		and bool(frontier_picker.call(
			"blocks_world_pointer", screen_position
		))
	):
		return true
	if debug_menu != null and debug_menu.blocks_world_pointer(screen_position):
		return true
	if hud != null:
		return hud.blocks_world_pointer(screen_position)
	return get_viewport().gui_get_hovered_control() != null


func _rotate_build_target_at_screen(screen_position: Vector2) -> bool:
	var rotated := false
	if not placement.held.is_empty():
		placement.rotate_held()
		rotated = true
	elif (
		worldheart_presenter != null
		and worldheart_presenter.rotate_at_screen(
			camera_rig.camera,
			screen_position,
			core.registries.tunef("click_target_screen_radius", 54.0)
		)
	):
		core.autosave_soon()
		rotated = true
	else:
		rotated = placement.rotate_at_screen(screen_position)
	if rotated:
		audio.play_event("build_rotate")
	return rotated


func _camera_input_blocked_by_ui() -> bool:
	if not _gameplay_started:
		return true
	if hud != null and hud.build_library_expanded():
		return true
	if panels != null and panels.is_open():
		return true
	if pause_menu != null and pause_menu.is_open():
		return true
	if wish_offer_panel != null and wish_offer_panel.is_open():
		return true
	if project_panel != null and project_panel.is_open():
		return true
	if collection_vibe_panel != null and collection_vibe_panel.is_open():
		return true
	if arrival_picker != null and arrival_picker.is_open():
		return true
	if nook_offer_panel != null and nook_offer_panel.is_open():
		return true
	if discovery_tray_panel != null and discovery_tray_panel.has_focus():
		return true
	if asset_viewer != null and asset_viewer.is_open():
		return true
	return lighting_tuner != null and lighting_tuner.visible


## Ctrl-drag selects a rectangle of tiles, and dragging from inside a settled
## selection moves the whole set.
##
## Returns whether the gesture was claimed. This runs before every other pointer
## path so a held Ctrl can never fall through to placement, camera orbit or the
## Worldheart -- a modifier that sometimes edits the world and sometimes does
## not would be worse than no modifier at all.
func _handle_tile_selection_input(event: InputEvent) -> bool:
	if tile_selection == null:
		return false
	if event is InputEventKey and event.is_action_pressed("cancel"):
		if tile_selection.has_selection() or tile_selection.is_dragging():
			_clear_tile_selection()
			return true
		return false

	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mouse.pressed:
			if _screen_position_blocked_by_ui(mouse.position):
				return false
			var coord := placement.cell_at_screen(mouse.position)
			# A settled selection owns every press that lands on it, modifier or
			# not. Requiring ctrl again to move it meant a plain click inside the
			# selection fell through to placement and picked up the single block
			# under the cursor, destroying the selection to do it -- the opposite
			# of what a selection is for.
			if tile_selection.has_selection() and tile_selection.contains(coord):
				_selection_pointer_down = true
				_selection_moving = true
				_selection_move_coord = coord
				_selection_preview_delta = Vector2i.ZERO
				# A sweep left pending from an earlier gesture must not resolve
				# against a stale rectangle once this move ends.
				_selection_rect_dirty = false
				camera_rig.begin_pointer_edit()
				return true
			if not mouse.ctrl_pressed:
				# Clicking away cancels, and the click is consumed rather than
				# also acting on whatever it landed on. Dismissing and editing in
				# one press makes an accidental click destructive.
				if tile_selection.has_selection():
					_clear_tile_selection()
					return true
				return false
			_selection_pointer_down = true
			_selection_moving = false
			_selection_press_position = mouse.position
			_selection_pointer_position = mouse.position
			_selection_rect_dirty = true
			camera_rig.begin_pointer_edit()
			tile_selection.begin_drag()
			return true
		if not _selection_pointer_down:
			return false
		# Captured before the flags are reset. Testing _selection_moving after
		# clearing it made the commit branch unreachable, so a move drag ended by
		# discarding its preview and snapping every tile home.
		var was_moving := _selection_moving
		var committed := _selection_preview_delta
		_selection_pointer_down = false
		_selection_moving = false
		_selection_preview_delta = Vector2i.ZERO
		camera_rig.end_pointer_edit()
		if was_moving:
			renderer.clear_selection_preview_offset()
			if committed != Vector2i.ZERO and tile_selection.move_by(committed):
				# The commit rebuilt those cells, so the cached meshes behind
				# the shifted coords are freed and must be re-gathered.
				_refresh_tile_selection_outline(true)
			return true
		if _selection_rect_dirty:
			_resolve_tile_selection_rect()
		tile_selection.end_drag()
		renderer.clear_selection_marquee()
		_refresh_tile_selection_outline()
		return true

	if event is InputEventMouseMotion and _selection_pointer_down:
		var motion := event as InputEventMouseMotion
		var coord := placement.cell_at_screen(motion.position)
		if _selection_moving:
			# Preview only. The grid is untouched until release, so crossing a
			# cell costs a handful of transform writes instead of rebuilding
			# every selected column.
			var delta := coord - _selection_move_coord
			if delta != _selection_preview_delta and tile_selection.can_move_by(delta):
				_selection_preview_delta = delta
				renderer.set_selection_preview_offset(
					_selection_world_offset(delta)
				)
		else:
			# Marked dirty and resolved once in _process. Resolving here would
			# run the whole screen-rectangle sweep for every motion event, and
			# those arrive far more often than frames are drawn.
			_selection_pointer_position = motion.position
			_selection_rect_dirty = true
		return true
	return false


## Resolves the pending drag rectangle. Called from _process so a burst of
## motion events costs one sweep, not one per event.
func _resolve_tile_selection_rect() -> void:
	_selection_rect_dirty = false
	var screen_rect := Rect2(
		_selection_press_position, Vector2.ZERO
	).expand(_selection_pointer_position)
	renderer.set_selection_marquee_screen(screen_rect)
	if tile_selection.drag_to_coords(
		placement.coords_in_screen_rect(screen_rect)
	):
		_refresh_tile_selection_outline()


## A grid delta as a world offset, taken as the difference between two cell
## centres so it follows whatever tile size and layout the grid uses.
func _selection_world_offset(delta: Vector2i) -> Vector3:
	return (
		core.grid.cell_to_world(delta, 0)
		- core.grid.cell_to_world(Vector2i.ZERO, 0)
	)


func _refresh_tile_selection_outline(force := false) -> void:
	if renderer == null:
		return
	renderer.set_selection_outline(tile_selection.coords(), force)


func _clear_tile_selection() -> void:
	tile_selection.clear()
	_selection_pointer_down = false
	_selection_moving = false
	_selection_preview_delta = Vector2i.ZERO
	if renderer != null:
		renderer.clear_selection_preview_offset()
	if renderer != null:
		renderer.clear_selection_outline()
		renderer.clear_selection_marquee()


func _begin_build_pointer(screen_position: Vector2) -> void:
	_pending_build_interaction = {}
	if (
		worldheart_presenter != null
		and not placement.held.is_empty()
		and worldheart_presenter.hole_at_screen(
			camera_rig.camera,
			screen_position,
			58.0 if worldheart_presenter.has_offering_preview() else 42.0
		)
	):
		# Claim the gesture before PlacementController.pointer_press(), whose
		# click-to-place behavior intentionally commits ordinary pieces on press.
		# A Worldheart offering must remain held and visible until mouse release.
		_worldheart_offer_pointer_pressed = true
		camera_rig.begin_pointer_edit()
		return
	if worldheart_presenter != null and placement.held.is_empty():
		var worldheart_target := worldheart_presenter.interaction_at_screen(
			camera_rig.camera,
			screen_position,
			core.registries.tunef("click_target_screen_radius", 54.0)
		)
		if String(worldheart_target.get("kind", "")) == "worldheart_reward":
			_perform_interaction(worldheart_target)
			return
		if worldheart_presenter.hole_at_screen(camera_rig.camera, screen_position):
			_worldheart_pointer_pressed = true
			_worldheart_pointer_press_position = screen_position
			_pending_build_interaction = worldheart_target
			return
	if placement.active:
		placement.pointer_press(screen_position)
		return
	# In interaction mode a short click always interacts. Actionable targets
	# require an intentional hold before the same gesture may become direct
	# world editing, so normal click jitter can never steal a harvest or fish.
	_pending_build_interaction = _interaction_at_screen(screen_position)
	var interaction_kind := String(
		_pending_build_interaction.get("kind", "")
	)
	placement.pointer_press(
		screen_position,
		true,
		not _pending_build_interaction.is_empty(),
		interaction_kind not in ["visitor", "visitor_vase"]
	)


func _finish_build_pointer(screen_position: Vector2) -> void:
	if _worldheart_offer_pointer_pressed:
		_cancel_worldheart_offer_pointer()
		if (
			worldheart_presenter.has_offering_preview()
			and worldheart_presenter.hole_at_screen(
				camera_rig.camera, screen_position, 58.0
			)
		):
			_contribute_held_to_worldheart()
		return
	if _worldheart_pointer_move_active:
		var projected: Variant = interaction_targets.ground_point(screen_position)
		var moved := false
		if projected is Vector3:
			moved = core.diorama.worldheart.move_to(
				core.grid.world_to_cell(projected)
			)
		_worldheart_pointer_move_active = false
		_worldheart_pointer_pressed = false
		worldheart_presenter.cancel_move_preview()
		hud.toast(
			"The Worldheart settles into its new tile."
			if moved else "The Worldheart needs a clear land tile.",
			"good" if moved else "warn"
		)
		return
	if _worldheart_pointer_pressed:
		_worldheart_pointer_pressed = false
		if not _pending_build_interaction.is_empty():
			_perform_interaction(_pending_build_interaction)
		_pending_build_interaction = {}
		return
	if (
		worldheart_presenter != null
		and not placement.held.is_empty()
		and worldheart_presenter.hole_at_screen(camera_rig.camera, screen_position)
	):
		_contribute_held_to_worldheart()
		return
	var was_dragging := placement.pointer_release(screen_position)
	if not _pending_build_interaction.is_empty():
		var interaction := _pending_build_interaction
		_pending_build_interaction = {}
		if not was_dragging:
			effects.click_marker(screen_position, true)
			_perform_interaction(interaction)


func _preview_worldheart_move(screen_position: Vector2) -> void:
	var projected: Variant = interaction_targets.ground_point(screen_position)
	if projected is Vector3:
		worldheart_presenter.preview_move(core.grid.world_to_cell(projected))


func _cancel_worldheart_offer_pointer() -> void:
	if not _worldheart_offer_pointer_pressed:
		return
	_worldheart_offer_pointer_pressed = false
	camera_rig.end_pointer_edit()


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
	if (
		core.diorama.enabled
		and discovery_tray_panel != null
		and event.is_action_pressed("discovery_tray")
		and not pause_menu.is_open()
		and not panels.is_open()
		and not placement.active
	):
		discovery_tray_panel.open_focus()
		_refresh_controller_hints()
		get_viewport().set_input_as_handled()
		return
	if (
		wish_offer_panel != null
		and wish_offer_panel.is_ready()
		and event.is_action_pressed("wish_menu")
	):
		wish_offer_panel.toggle()
		_refresh_controller_hints()
		get_viewport().set_input_as_handled()
		return
	if not core.diorama.enabled and event.is_action_pressed("project_menu"):
		project_panel.toggle()
		_refresh_controller_hints()
		get_viewport().set_input_as_handled()
		return
	if (
		pause_menu.is_open()
		or wish_offer_panel.is_open()
		or panels.is_open()
		or project_panel.is_open()
		or discovery_tray_panel != null and discovery_tray_panel.has_focus()
	):
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
	if not placement.active and placement.controller_mode():
		if _handle_controller_interaction_input(event):
			return
	if event.is_action_pressed("build_mode"):
		placement.set_active(not placement.active)
		if placement.active:
			hud.request_build_library_open()
		else:
			hud.set_build_library_expanded(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("rotate_piece"):
		_rotate_build_target_at_screen(get_viewport().get_mouse_position())
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
		elif (
			not placement.active
			and not player.deployed
			and not _is_controller_event(event)
		):
			_perform_interaction(
				_interaction_at_screen(get_viewport().get_mouse_position())
			)
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
		elif wish_offer_panel.is_open():
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
			if not placement.active and mouse.pressed:
				_handle_world_click(mouse.position)
		elif mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			if (
				not _screen_position_blocked_by_ui(mouse.position)
				and _rotate_build_target_at_screen(mouse.position)
			):
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and placement.active:
		placement.pointer_motion((event as InputEventMouseMotion).position)
	elif event.is_action_pressed("store_piece") and placement.active:
		placement.store_held()
		audio.play_event("store")


func _handle_controller_build_input(event: InputEvent) -> void:
	if (
		frontier_picker != null
		and bool(frontier_picker.call("has_focus"))
	):
		# ui_accept and directional navigation belong to the focused controls.
		return
	if event.is_action_pressed("build_mode"):
		if placement.held.is_empty() and not _guided_placement_locked():
			placement.set_active(false)
			hud.set_build_library_expanded(false)
			hud.release_build_focus()
		get_viewport().set_input_as_handled()
		_refresh_controller_hints()
		return
	if event.is_action_pressed("cancel"):
		if _worldheart_controller_move_active:
			_worldheart_controller_move_active = false
			worldheart_presenter.cancel_move_preview()
			get_viewport().set_input_as_handled()
			_refresh_controller_hints()
			return
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
		if _worldheart_controller_move_active:
			worldheart_presenter.preview_move(
				placement.controller_cursor_cell()
			)
		get_viewport().set_input_as_handled()
		_refresh_controller_hints()
		return
	if (
		event.is_action_pressed("build_confirm")
		and placement.controller_cursor_active()
	):
		if _worldheart_controller_move_active:
			var moved := core.diorama.worldheart.move_to(
				placement.controller_cursor_cell()
			)
			if moved:
				_worldheart_controller_move_active = false
				worldheart_presenter.cancel_move_preview()
			hud.toast(
				"The Worldheart settles into its new tile."
				if moved else "The Worldheart needs a clear land tile.",
				"good" if moved else "warn"
			)
		elif (
			core.diorama.enabled
			and not placement.held.is_empty()
			and placement.controller_cursor_cell()
				== core.diorama.worldheart.worldheart_cell
		):
			_contribute_held_to_worldheart()
		else:
			placement.click()
	elif event.is_action_pressed("move_piece") and placement.held.is_empty():
		if (
			core.diorama.enabled
			and placement.controller_cursor_cell()
				== core.diorama.worldheart.worldheart_cell
		):
			_worldheart_controller_move_active = true
			renderer.clear_structure_hover()
			worldheart_presenter.begin_move_preview()
		else:
			placement.pick_up_at(
				placement.controller_cursor_cell(),
				core.grid.top_elevation(placement.controller_cursor_cell())
			)
	elif event.is_action_pressed("rotate_piece"):
		if (
			placement.held.is_empty()
			and core.diorama.enabled
			and placement.controller_cursor_cell()
				== core.diorama.worldheart.worldheart_cell
		):
			worldheart_presenter.rotate_clockwise()
			core.autosave_soon()
		elif not placement.held.is_empty():
			placement.rotate_held()
		else:
			return
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


func _handle_controller_interaction_input(event: InputEvent) -> bool:
	if event.is_action_pressed("build_mode"):
		placement.set_active(true)
		hud.request_build_library_open()
		hud.focus_build_library()
		get_viewport().set_input_as_handled()
		_refresh_controller_hints()
		return true
	var direction := Vector2i.ZERO
	if event.is_action_pressed("build_cursor_left"):
		direction = Vector2i.LEFT
	elif event.is_action_pressed("build_cursor_right"):
		direction = Vector2i.RIGHT
	elif event.is_action_pressed("build_cursor_up"):
		direction = Vector2i.UP
	elif event.is_action_pressed("build_cursor_down"):
		direction = Vector2i.DOWN
	if direction != Vector2i.ZERO:
		placement.move_controller_cursor(direction)
		get_viewport().set_input_as_handled()
		_refresh_controller_hints()
		return true
	if (
		event.is_action_pressed("interact")
		or event.is_action_pressed("build_confirm")
	):
		_perform_interaction(_interaction_at_controller_cursor())
		get_viewport().set_input_as_handled()
		return true
	return false


func _cancel_build_or_open_library() -> void:
	if not placement.active:
		return
	# A held piece is an in-progress placement transaction. Cancel owns this
	# keypress completely: restore a moved world piece (or discard the unused
	# stock preview), close the Build Bag, and return straight to the world.
	# Opening the library here made one Escape perform two contradictory actions.
	if not placement.held.is_empty():
		_cancel_worldheart_offer_pointer()
		placement.cancel_click()
		hud.set_build_library_expanded(false)
		hud.release_build_focus()
		_pending_build_interaction = {}
		return
	if _guided_placement_locked():
		hud.toast("This piece is part of your arrival — place it first.", "warn")
		return
	if hud.build_library_collapsed():
		hud.request_build_library_open()
		return
	hud.set_build_library_expanded(false)
	if placement.controller_mode():
		_begin_controller_world_browse()


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
	if not _gameplay_started or wish_offer_panel.is_open() or project_panel.is_open():
		return
	placement.prepare_for_save()
	if panels.is_open():
		panels.close()
	pause_menu.open(page)


func _on_input_method_changed(method: int) -> void:
	var using_controller := method == InputDeviceService.InputMethod.CONTROLLER
	placement.set_controller_mode(using_controller)
	if using_controller:
		if collection_vibe_panel != null and collection_vibe_panel.is_open():
			collection_vibe_panel.focus_default()
		elif arrival_picker != null and arrival_picker.is_open():
			arrival_picker.focus_default()
		elif pause_menu.is_open():
			pause_menu.focus_default()
		elif panels.is_open():
			panels.focus_default()
		elif wish_offer_panel.is_open():
			wish_offer_panel.focus_default()
		elif project_panel.is_open():
			project_panel.focus_default()
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
	elif discovery_tray_panel != null and discovery_tray_panel.has_focus():
		actions = [
			{"action": &"ui_accept", "label": "Choose miniature"},
			{"action": &"cancel", "label": "Back to world"},
		]
	elif wish_offer_panel.is_open():
		actions = [
			{"action": &"ui_accept", "label": "Choose wish"},
			{"action": &"cancel", "label": "Not yet"},
		]
	elif project_panel.is_open():
		actions = [
			{"action": &"ui_accept", "label": "Track / contribute"},
			{"action": &"cancel", "label": "Back to world"},
		]
	elif panels.is_open():
		actions = [
			{"action": &"panel_previous", "label": "Previous page"},
			{"action": &"panel_next", "label": "Next page"},
			{"action": &"cancel", "label": "Close"},
		]
	elif (
		frontier_picker != null
		and bool(frontier_picker.call("has_focus"))
	):
		actions = [
			{"action": &"ui_accept", "label": "Choose"},
			{"action": &"cancel", "label": "Back to world"},
		]
	elif placement.active:
		if _worldheart_controller_move_active:
			actions = [
				{"action": &"build_cursor_up", "label": "Move Worldheart"},
				{"action": &"build_confirm", "label": "Set Worldheart"},
				{"action": &"cancel", "label": "Cancel move"},
			]
		elif not placement.held.is_empty():
			var place_label := "Place"
			if (
				core.diorama.enabled
				and placement.controller_cursor_active()
				and placement.controller_cursor_cell()
					== core.diorama.worldheart.worldheart_cell
			):
				place_label = "Offer to Worldheart"
			actions = [
				{"action": &"build_cursor_up", "label": "Move cursor"},
				{"action": &"camera_pan_up", "label": "Pan camera"},
				{"action": &"build_confirm", "label": place_label},
				{"action": &"rotate_piece", "label": "Rotate"},
				{"action": &"cancel", "label": "Cancel"},
			]
			if placement.held.get("moving") != null:
				actions.insert(
					3,
					{"action": &"store_piece", "label": "Store"}
				)
		elif placement.controller_cursor_active():
			var confirm_label := "Interact"
			var move_label := "Move piece"
			var cursor_over_worldheart := false
			if (
				frontier_markers != null
				and not frontier_markers.marker_at_cell(
					placement.controller_cursor_cell()
				).is_empty()
			):
				var frontier_marker := frontier_markers.marker_at_cell(
					placement.controller_cursor_cell()
				)
				if core.diorama.enabled:
					confirm_label = "Use Expansion Ripple"
				else:
					var frontier_status := core.frontiers.status(
						frontier_marker.get("nook", Vector2i.ZERO)
					)
					confirm_label = (
						"Unfold land"
						if bool(frontier_status.get("ready", false))
						else "Track frontier"
					)
			if (
				core.diorama.enabled
				and placement.controller_cursor_cell()
					== core.diorama.worldheart.worldheart_cell
			):
				move_label = "Move Worldheart"
				cursor_over_worldheart = true
			actions = [
				{"action": &"build_cursor_up", "label": "Move cursor"},
				{"action": &"camera_pan_up", "label": "Pan camera"},
				{"action": &"build_confirm", "label": confirm_label},
				{"action": &"move_piece", "label": move_label},
				{"action": &"build_mode", "label": "Library"},
				{"action": &"cancel", "label": "Exit"},
			]
			if cursor_over_worldheart:
				actions.insert(
					4, {"action": &"rotate_piece", "label": "Rotate"}
				)
		else:
			actions = [
				{"action": &"ui_accept", "label": "Choose piece"},
				{"action": &"build_mode", "label": "Browse world"},
				{"action": &"cancel", "label": "Exit"},
			]
			if core.diorama.enabled:
				actions.insert(1, {
					"action": &"offer_to_worldheart",
					"label": "Offer spare",
				})
	else:
		var interact_label := "Interact"
		if placement.interaction_cursor_active():
			var cursor_interaction := _interaction_at_controller_cursor()
			match String(cursor_interaction.get("kind", "")):
				"visitor":
					interact_label = "Greet visitor"
				"visitor_vase":
					interact_label = "Break gift vase"
				"provision_fishing_spot":
					interact_label = "Fish"
				"worldheart_reward":
					interact_label = "Collect gift"
				"worldheart_collect_all":
					interact_label = "Collect all gifts"
		actions = [
			{"action": &"build_cursor_up", "label": "Move world cursor"},
			{"action": &"interact", "label": interact_label},
			{
				"action": &"panel_collection" if core.diorama.enabled else &"project_menu",
				"label": "Collections" if core.diorama.enabled else "Projects",
			},
			{"action": &"build_mode", "label": "Edit mode"},
		]
	if not core.diorama.enabled and wish_offer_panel.is_ready() and not wish_offer_panel.is_open():
		actions.push_front({"action": &"wish_menu", "label": "Open wish"})
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
	if panels.is_open() or wish_offer_panel.is_open() or project_panel.is_open():
		return
	var interaction := _interaction_at_screen(screen_position)
	if interaction.is_empty():
		return
	skill_actions.cancel_all()
	_perform_interaction(interaction)


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
	if _try_expand_frontier_at_cell(cell):
		return true
	if core.diorama.enabled:
		return false
	var visitor: Dictionary = visitor_scene.call("event_at_cell", cell)
	if not visitor.is_empty():
		return bool(visitor_scene.call("interact", int(visitor["event_id"])))
	return _try_harvest_instance(placement.controller_target_instance_id())


func _try_expand_frontier_at_screen(screen_position: Vector2) -> bool:
	if frontier_markers == null:
		return false
	var marker := frontier_markers.marker_at_screen(screen_position)
	if marker.is_empty():
		return false
	return _activate_frontier(marker.get("nook", Vector2i.ZERO))


func _try_expand_frontier_at_cell(cell: Vector2i) -> bool:
	if frontier_markers == null:
		return false
	var marker := frontier_markers.marker_at_cell(cell)
	if marker.is_empty():
		return false
	return _activate_frontier(marker.get("nook", Vector2i.ZERO))


func _activate_frontier(coord: Vector2i) -> bool:
	if core.diorama.enabled:
		var prepared: Dictionary = core.diorama.gifts.prepare_expansion(coord)
		if prepared.is_empty():
			return false
		core.save()
		_refresh_controller_hints()
		return true
	var result := core.frontiers.activate(coord)
	if not bool(result.get("accepted", false)):
		return false
	core.autosave_soon()
	if frontier_picker != null:
		frontier_picker.call("refresh")
	_refresh_controller_hints()
	return true


## Compatibility port for old scene fixtures. Preferences are intentionally
## ignored: the reserved deterministic world card owns the generated terrain.
func _expand_nook_at(coord: Vector2i, _preferences: Dictionary = {}) -> bool:
	return _activate_frontier(coord)


func _begin_frontier_expansion(
	coord: Vector2i,
	project_id: String,
	seed_card: Dictionary
) -> void:
	if core.nooks.world.has_nook(coord):
		if core.diorama.enabled:
			core.diorama.gifts.finish_expansion(coord, true)
		else:
			core.frontiers.mark_generated(coord)
		return
	if _nook_reveal_in_progress:
		for queued: Dictionary in _queued_frontier_expansions:
			if queued.get("coord", Vector2i.ZERO) == coord:
				return
		_queued_frontier_expansions.append({
			"coord": coord,
			"project_id": project_id,
			"seed_card": seed_card.duplicate(true),
		})
		return
	_nook_reveal_in_progress = true
	if project_panel != null:
		project_panel.close()
	if nook_arrival_ghost != null:
		nook_arrival_ghost.preview_nook(coord, _expansion_seam_side(coord))
	_update_frontier_marker_availability()
	call_deferred("_expand_frontier_project_async", coord, project_id, seed_card)


func _expand_frontier_project_async(
	coord: Vector2i,
	project_id: String,
	seed_card: Dictionary
) -> void:
	renderer.begin_bulk_update()
	var staged_plan: NookGenerator.NookPlan
	var staged_origin := core.nooks.world.chunk_origin(coord)
	var prepared: Dictionary = await core.nooks.prepare_reveal_nook_async(
		coord, seed_card, 1
	)
	if not prepared.is_empty():
		var prepared_plan := prepared.get("plan") as NookGenerator.NookPlan
		if prepared_plan != null:
			staged_plan = prepared_plan
			renderer.stage_nook_reveal(
				staged_origin,
				prepared_plan
			)
	await renderer.end_bulk_update_async(not prepared.is_empty())
	var plan: NookGenerator.NookPlan = (
		core.nooks.finish_prepared_expansion(prepared)
		if not prepared.is_empty()
		else null
	)
	if plan == null:
		if staged_plan != null:
			renderer.release_nook_reveal_staging(
				staged_origin,
				staged_plan
			)
		_nook_reveal_in_progress = false
		if nook_arrival_ghost != null:
			nook_arrival_ghost.cancel_preview(coord)
		_update_frontier_marker_availability()
		if core.diorama.enabled:
			core.diorama.gifts.finish_expansion(coord, false)
		else:
			core.frontiers.mark_generation_failed(coord)
		audio.play_event("build_invalid")
		_start_next_frontier_expansion()
		return
	if core.diorama.enabled:
		core.diorama.gifts.finish_expansion(coord, true)
	else:
		core.frontiers.mark_generated(coord)
	audio.play_event("parcel_reveal")
	hud.toast(
		"The Expansion Ripple unfolds into new land."
		if core.diorama.enabled
		else "Frontier Project complete — new land is arriving.",
		"rare"
	)
	core.autosave_soon()
	_refresh_controller_hints()


func _start_next_frontier_expansion() -> void:
	if _nook_reveal_in_progress or _queued_frontier_expansions.is_empty():
		return
	var queued: Dictionary = _queued_frontier_expansions.pop_front()
	_begin_frontier_expansion(
		queued.get("coord", Vector2i.ZERO),
		String(queued.get("project_id", "")),
		queued.get("seed_card", {}) as Dictionary
	)


func _expansion_seam_side(coord: Vector2i) -> Vector2i:
	for offset: Vector2i in WorldGrid.NEIGHBORS:
		if core.nooks.world.nook(coord + offset) != null:
			return offset
	return Vector2i.ZERO


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
	var interaction: Dictionary = interaction_targets.interaction_at(screen_position)
	if core.diorama.enabled and interaction.get("kind", "") == "frontier_project":
		interaction["kind"] = "expansion_ripple"
	return interaction


func _interaction_at_controller_cursor() -> Dictionary:
	var cell := placement.controller_cursor_cell()
	if core.diorama.enabled and worldheart_presenter != null:
		var worldheart_target := worldheart_presenter.interaction_at_cell(cell)
		if not worldheart_target.is_empty():
			return worldheart_target
	var marker: Dictionary = frontier_markers.marker_at_cell(cell)
	if not marker.is_empty():
		return {
			"kind": "expansion_ripple" if core.diorama.enabled else "frontier_project",
			"coord": marker.get("nook", Vector2i.ZERO),
			"point": core.grid.cell_to_world(cell),
		}
	if not core.diorama.enabled:
		var fishing_spot := provision_fishing_spots.interaction_at_cell(cell)
		if not fishing_spot.is_empty():
			return fishing_spot
		var visitor_target: Dictionary = visitor_scene.call("event_at_cell", cell)
		if not visitor_target.is_empty():
			return visitor_target
	var instance_id := placement.controller_target_instance_id()
	if instance_id <= 0:
		return {}
	var found := core.grid.find_structure(instance_id)
	if found.is_empty():
		return {}
	var options: Array = core.interactions.options_for("player", instance_id)
	if core.diorama.enabled:
		options = options.filter(func(option):
			return String(option.feature_id) == "world_curiosity"
		)
	if options.is_empty():
		return {}
	return {
		"kind": "feature_interaction",
		"feature": options[0].feature_id,
		"option": options[0],
		"instance_id": instance_id,
		"point": core.grid.cell_to_world(
			found["coord"], int(found["elevation"])
		),
	}


# ------------------------------------------------------------------ cross-cutting flows

func _on_diorama_offer_selected(offer: Dictionary) -> void:
	audio.play_event("build_preview")
	placement.hold_diorama_offer(offer)
	_refresh_controller_hints()


func _on_worldheart_pulse(_entry: Dictionary) -> void:
	# Pointer controls do not change when a gift appears. Rebuilding the HUD in
	# the spawn frame used to compete with model creation and could eat a click.
	if (
		InputDeviceService.shared().is_controller()
		and placement.controller_cursor_active()
		and placement.controller_cursor_cell()
			== core.diorama.worldheart.worldheart_cell
	):
		call_deferred("_refresh_controller_hints")


func _on_worldheart_offer_requested(kind: String, content_id: String) -> void:
	if (
		worldheart_presenter != null
		and worldheart_presenter.show_offering_preview(kind, content_id)
	):
		worldheart_presenter.drop_offering(
			_commit_worldheart_contribution.bind(kind, content_id)
		)
		return
	_commit_worldheart_contribution(kind, content_id)


func _contribute_held_to_worldheart() -> void:
	if placement.held.is_empty():
		return
	var kind := String(placement.held.get("kind", ""))
	var content_id := String(placement.held.get("id", ""))
	if kind not in ["tile", "structure"]:
		hud.toast("Only tiles and models can be offered to the Worldheart.", "warn")
		return
	if not worldheart_presenter.has_offering_preview():
		worldheart_presenter.show_offering_preview(kind, content_id)
	placement.cancel_pointer_gesture()
	if placement.held.get("moving") != null:
		placement.store_held()
	else:
		placement.cancel_click()
	placement.set_external_offer_preview(false)
	placement.set_active(false)
	worldheart_presenter.drop_offering(
		_commit_worldheart_contribution.bind(kind, content_id)
	)


func _commit_worldheart_contribution(kind: String, content_id: String) -> void:
	var result := core.diorama.worldheart.contribute_from_stock(kind, content_id)
	_handle_worldheart_contribution_result(result)


func _handle_worldheart_contribution_result(result: Dictionary) -> void:
	if not bool(result.get("accepted", false)):
		return
	var collection_id := String(result.get("collection_id", ""))
	var definition = core.registries.creative_collection(collection_id)
	var collection_name: String = (
		String(definition.display_name) if definition != null else "collection"
	)
	if bool(result.get("completed", false)):
		var reward: Dictionary = result.get("reward", {})
		hud.toast(
			"%s filled - %s surfaced."
			% [collection_name, core.build_rewards.display_name(reward)],
			"rare" if bool(reward.get("was_new", false)) else "good"
		)
		audio.play_event(
			"discovery" if bool(reward.get("was_new", false)) else "reward_common"
		)
	else:
		hud.toast(
			"%s offering: %d / %d."
			% [
				collection_name,
				int(result.get("progress", 0)),
				int(result.get("required", 2)),
			],
			"good"
		)
		audio.play_event("store")
	_refresh_controller_hints()


func _on_diorama_offer_committed(
	reward: Dictionary,
	_replacement: Dictionary,
	_slot: int
) -> void:
	if bool(reward.get("was_new", false)):
		reward_reveal.enqueue(
			reward,
			core.grid.cell_to_world(core.grid.home_cell) + Vector3.UP * 0.2,
			"reveal_world_bud_evergreen"
		)
	audio.play_event("discovery" if bool(reward.get("was_new", false)) else "reward_common")
	_refresh_controller_hints()


func _on_world_gift_selected(gift_id: String) -> void:
	if not core.diorama.gifts.begin_targeting(gift_id):
		return
	placement.set_active(false)
	if InputDeviceService.shared().is_controller():
		placement.begin_controller_interaction_browse()
	frontier_markers.rebuild()
	_update_frontier_marker_availability()
	_refresh_controller_hints()


func _on_curiosity_landed(instance_id: int, _state: Dictionary) -> void:
	call_deferred("_animate_curiosity_landing", instance_id)
	audio.play_event("parcel_appear")


func _animate_curiosity_landing(instance_id: int) -> void:
	renderer.refresh_structure_opportunity(instance_id)
	renderer.animate_structure_wish_landing(instance_id)


func _on_curiosity_opened(_instance_id: int, result: Dictionary) -> void:
	var coord: Vector2i = result.get("position_coord", core.grid.home_cell)
	var position := core.grid.cell_to_world(coord) + Vector3.UP * 0.18
	audio.play_event("place_stone", 1.5, 1.35)
	effects.burst("fx_spark", position + Vector3.UP * 0.22, 18, 3.8)
	effects.burst("fx_smoke_puff", position + Vector3.UP * 0.08, 10, 1.7)
	var profile_id := String(result.get("reveal_profile_id", "reveal_visitor_vase"))
	for reward: Dictionary in result.get("rewards", []):
		reward_reveal.enqueue(reward, position, profile_id)
	_refresh_controller_hints()


func _on_creative_collection_milestone(
	_collection_id: String,
	_milestone: Dictionary
) -> void:
	if worldheart_presenter != null:
		worldheart_presenter.prime_reward_collection()
	audio.play_event("levelup")
	if player.state == PlayerController.State.FREE:
		player_visual.play("celebrate")
	else:
		_celebration_pending = true
	_refresh_controller_hints()

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
			if String(reward.get("kind", "")) in ["tile", "structure"]:
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
			elif (
				String(reward.get("kind", "")) == "token"
				and core.onboarding.stage == OnboardingState.OPEN_FOREST_BOX
			):
				call_deferred("_open_onboarding_token_pouch")
		"ready":
			audio.play_event("leaf_rustle")
			if core.onboarding.stage == OnboardingState.HARVEST_TREE:
				hud.toast("Your tree is ready.", "good")
	hud.update_tutorial()


func _on_provision_fishing_feedback(kind: String, data: Dictionary) -> void:
	match kind:
		"armed":
			audio.play_event("fish_splash")
			hud.toast("The shoal is circling — watch for the bubbles.", "common")
		"bubble":
			audio.play_event("fish_bite")
		"early":
			audio.play_event("fish_splash")
		"hit":
			audio.play_event("fish_bite")
			hud.toast(
				"Good timing · %d/%d" % [
					int(data.get("progress", 0)),
					int(data.get("hits_required", 3)),
				],
				"good"
			)
		"complete":
			audio.play_event("fish_catch")
			var contribution: Dictionary = data.get("contribution", {})
			hud.toast(
				(
					"Provision caught — the shoal will return."
					if bool(contribution.get("accepted", false))
					else "A fine catch — no Project needs provisions right now."
				),
				"good"
			)
		"cooldown":
			audio.play_event("fish_splash")
	hud.update_tutorial()


func _on_provision_fishing_state_changed(coord: Vector2i) -> void:
	var current_focus := player.focus()
	if (
		String(current_focus.get("kind", "")) == "provision_fishing_spot"
		and current_focus.get("coord", Vector2i.ZERO) == coord
	):
		_on_focus_changed(current_focus)
	else:
		_refresh_controller_hints()


func _open_onboarding_token_pouch() -> void:
	if (
		core.onboarding.stage == OnboardingState.OPEN_FOREST_BOX
		and not panels.is_open()
	):
		panels.toggle("inventory")


func _on_token_box_opened(_box_id: String, reward: Dictionary) -> void:
	var reveal_profile_id := String(reward.get("reveal_profile_id", ""))
	if reveal_profile_id == "":
		return
	var source_position := (
		player.global_position + Vector3.UP * 0.25
		if player != null and player.deployed
		else core.grid.cell_to_world(core.grid.home_cell) + Vector3.UP * 0.25
	)
	reward_reveal.enqueue(reward, source_position, reveal_profile_id)


func _on_visitor_reward_presented(reward: Dictionary) -> void:
	var name: String = core.build_rewards.call("display_name", reward)
	hud.toast(
		"%d × %s dropped into your Build Library."
		% [int(reward.get("amount", 1)), name],
		"rare"
	)
	hud.update_tutorial()


func _on_visitor_vase_smashed(
	position: Vector3,
	reward: Dictionary,
	container_style: Dictionary
) -> void:
	audio.play_event("place_stone", 1.5, 1.35)
	effects.visitor_container_burst(
		position + Vector3.UP * 0.18,
		18,
		container_style
	)
	effects.burst("fx_spark", position + Vector3.UP * 0.22, 14, 3.8)
	effects.burst("fx_smoke_puff", position + Vector3.UP * 0.08, 8, 1.7)
	reward_reveal.enqueue(reward, position + Vector3.UP * 0.16, "reveal_visitor_vase")


func _on_visitor_greeted(position: Vector3, _display_name: String) -> void:
	audio.play_event("parcel_select", -3.0, 1.18)
	effects.burst("fx_spark", position + Vector3.UP * 0.38, 5, 1.4)


func _on_onboarding_stage_changed(_stage: String) -> void:
	if hud == null:
		return
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
	var source := String(entry.get("source", ""))
	if source == "delivery":
		core.progression.discovery.acknowledge_next()
		core.arrivals.resolve_delivery()
	hud.update_tutorial()
	var kind := String(entry.get("kind", ""))
	var content_id := String(entry.get("id", ""))
	var display_name := content_id
	if kind == DiscoverySystem.KIND_TILE and core.registries.tile(content_id) != null:
		display_name = core.registries.tile(content_id).display_name
	elif kind == DiscoverySystem.KIND_STRUCTURE and core.registries.structure(content_id) != null:
		display_name = core.registries.structure(content_id).display_name
	if source == "wish":
		var preferred_coord := core.grid.world_to_cell(
			camera_rig.focus_world_position()
		)
		var landed: Dictionary = core.reward_drops.land(entry, preferred_coord)
		if not bool(landed.get("accepted", false)):
			hud.toast(
				"The sky is waiting for a clear landing spot for %s." % display_name,
				"warn"
			)
			wish_offer_panel.notify_ready(false)
			return
		core.progression.discovery.acknowledge_next()
		call_deferred(
			"_animate_reward_drop_landing",
			int(landed.get("instance_id", 0))
		)
		hud.toast(
			"A star has landed. Find its golden glint and claim it.",
			"rare"
		)
		core.save()
	else:
		hud.toast("%s added to your Build Bag." % display_name, "good")
		placement.hold_new(kind, content_id)


func _animate_reward_drop_landing(instance_id: int) -> void:
	renderer.refresh_structure_opportunity(instance_id)
	renderer.animate_structure_wish_landing(instance_id)


func _open_pending_discovery_when_ready() -> void:
	if not core.progression.discovery.has_pending():
		return
	wish_offer_panel.notify_ready()


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
		"visitor":
			hud.set_prompt(
				&"interact",
				"Greet %s" % String(focus.get("display_name", "the visitor"))
			)
		"visitor_vase":
			hud.set_prompt(&"interact", "Break the visitor's gift vase")
		"provision_fishing_spot":
			hud.set_prompt(
				&"interact",
				provision_fishing_spots.prompt_for(
					focus.get("coord", Vector2i.ZERO)
				)
			)
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
		"worldheart_reward":
			hud.set_prompt(&"interact", "Collect into Build Bag")
		"worldheart_collect_all":
			hud.set_prompt(&"interact", "Collect nearby Worldheart gifts")
		_:
			hud.set_prompt(&"", "")
	_refresh_controller_hints()


func _on_click_interaction_reached(interaction: Dictionary) -> void:
	_perform_interaction(interaction)


func _perform_interaction(interaction: Dictionary) -> void:
	if core.diorama.enabled:
		var kind := String(interaction.get("kind", ""))
		if kind == "feature_interaction":
			var option = interaction.get("option")
			if option == null or String(option.feature_id) != "world_curiosity":
				return
		elif kind not in ["expansion_ripple", "worldheart_reward", "worldheart_collect_all"]:
			return
	match interaction.get("kind", ""):
		"worldheart_reward":
			var reward := core.diorama.worldheart.claim(
				String(interaction.get("entry_id", ""))
			)
			if not reward.is_empty():
				hud.toast(
					"%s tucked into your Build Bag."
					% core.build_rewards.display_name(reward),
					"rare" if bool(reward.get("was_new", false)) else "good"
				)
				audio.play_event("discovery" if bool(reward.get("was_new", false)) else "reward_common")
		"worldheart_collect_all":
			var rewards := core.diorama.worldheart.claim_all_visible()
			if rewards.is_empty():
				hud.toast("The Worldheart is resting.", "common")
			else:
				hud.toast(
					"%d gift%s tucked into your Build Bag."
					% [rewards.size(), "" if rewards.size() == 1 else "s"],
					"good"
				)
				audio.play_event("reward_common")
		"visitor", "visitor_vase":
			# Release transient outline RIDs before a visitor visual starts a tween
			# or the vase is queued for deletion.
			renderer.clear_structure_hover()
			visitor_scene.call("interact", int(interaction.get("event_id", 0)))
		"provision_fishing_spot":
			provision_fishing_spots.interact(
				interaction.get("coord", Vector2i.ZERO)
			)
		"frontier_project", "expansion_ripple":
			_activate_frontier(interaction.get("coord", Vector2i.ZERO))
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
	# Harvesting owns a presentation adapter because a hit is more than a data
	# mutation: the same call must drive impact, felling/shattering, and the
	# persistent depleted visual. Sending it through the generic registry first
	# used to consume the hit before any of that presentation could run.
	if String(option.feature_id) == "harvesting":
		if _try_harvest_instance(option.target_instance_id):
			core.autosave_soon()
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


func _on_project_reward_granted(
	project: Dictionary,
	reward: Dictionary
) -> void:
	var display_name: String = core.build_rewards.display_name(reward)
	hud.toast(
		"%s complete — %s joins your Build Bag." % [
			project.get("name", "Collection Project"), display_name,
		],
		"rare"
	)
	reward_reveal.enqueue(
		reward,
		core.grid.cell_to_world(core.grid.home_cell),
		"reveal_world_bud_evergreen"
	)
	audio.play_event("discovery")


func _on_special_find_spawned(instance_id: int, find_id: String) -> void:
	renderer.refresh_structure_opportunity(instance_id)
	var definition = core.registries.special_find(find_id)
	hud.toast(
		"A %s glints somewhere in the world." % (
			definition.display_name if definition != null else "Special Find"
		),
		"rare"
	)


func _on_special_find_collected(instance_id: int, find_id: String) -> void:
	renderer.refresh_structure_opportunity(instance_id)
	var definition = core.registries.special_find(find_id)
	hud.toast(
		"%s saved in your Special Finds reserve." % (
			definition.display_name if definition != null else "Special Find"
		),
		"good"
	)
	audio.play_event("discovery")


func _on_reward_drop_claimed(_instance_id: int, reward: Dictionary) -> void:
	hud.toast(
		"%s claimed for your Build Bag." % core.build_rewards.display_name(reward),
		"rare"
	)
	audio.play_event("discovery")
	core.save()


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
		frontier_markers.rebuild()
		hud.toast("Save reloaded.", "good")
		if player.deployed and is_instance_valid(pigeon_controller):
			pigeon_controller.spawn_near_player()


func reset_world() -> void:
	core.save_manager.delete_save()
	get_tree().reload_current_scene()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _gameplay_started:
		core.save()
