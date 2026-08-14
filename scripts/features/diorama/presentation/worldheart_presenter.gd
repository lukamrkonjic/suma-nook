class_name WorldheartPresenter
extends Node3D
## Permanent wishing-well presentation plus a small set of collectible reward
## miniatures. Targeting is screen/cell based so these visuals never need to
## occupy the authoritative build grid.

## Instantiated through AssetLibrary by id -- AssetEditLibrary only reaches
## assets instantiated that way, so a preloaded PackedScene here would make
## Asset Studio edits save and then visibly do nothing (measured on the
## wardrobe this replaced).
const WELL_ASSET := "prop_wishing_well"
const WELL_SCALE := 1.16
## The well's shaft, measured on the imported glb (unscaled): inner wall radius
## runs 0.20-0.23 from z 0.19 up to the rim at 0.87, with no floor.
##
## A flat disc sunk mid-shaft, oversized so its edge is buried inside the
## opaque stone. A closed cylinder was tried instead, to stop sightlines
## through the ruin's missing back -- it made things worse, not better: its
## WALL is visible through that same gap, reading as a huge black mass rising
## past the rim rather than a hole in the ground.
const WELL_MOUTH_DISC_RADIUS := 0.27
const WELL_MOUTH_DISC_HEIGHT := 0.21
## Interaction and animation heights, in world units after WELL_SCALE. The
## click anchor sits at the body's visual centre, NOT at the mouth: right-click
## targeting claims a 73px screen radius around it, and at mouth height that
## circle reached the neighbouring tile and stole its rotation clicks.
const WELL_CLICK_ANCHOR_HEIGHT := 0.58
const WELL_MOUTH_ANCHOR_HEIGHT := 0.78
const WELL_HOVER_HEIGHT := 1.02
## How high a launched reward flies above the mouth before falling outward.
## High enough to clearly clear the rim (1.01 world) and read as "shot up out
## of the well" rather than lifted over its lip.
const WELL_LAUNCH_APEX := 1.55
const WELL_LAUNCH_DELAY := 0.34
const REWARD_LAUNCH_DURATION := 0.86
const PROGRESS_CARD_VIEWPORT_SIZE := Vector2i(132, 52)
const PROGRESS_CARD_SIZE := Vector2(126, 46)
const INVALID_PREVIEW_CELL := Vector2i(2147483647, 2147483647)
const MOVE_GENERATION_PAUSE := &"worldheart_move_preview"
const MOVE_PREVIEW_RESPONSE := 24.0

var core: GameCore
var assets: AssetLibrary
var audio: GameAudio
var camera: Camera3D
var kit: UiKit
var portal_fx_root: Node3D
var vortex_pivot: Node3D
var outer_aura_pivot: Node3D
var rune_stone_ring_pivot: Node3D
var mote_emitter_pivot: Node3D
var portal_light: OmniLight3D
var hole: MeshInstance3D
var well_motion_root: Node3D
var well_shake_root: Node3D
var well_visual_root: Node3D
var progress_card_viewport: SubViewport
var progress_card_sprite: Sprite3D
var progress_card: PanelContainer
var progress_icon: TextureRect
var progress_count_label: Label
var _tile_factory: TileVisualFactory
var _structure_factory: StructureVisualFactory
var _entry_nodes: Dictionary = {}
var _entry_cells: Dictionary = {}
var _elapsed := 0.0
var _moving_preview := false
var _move_preview_cell := INVALID_PREVIEW_CELL
var _move_preview_target := Vector3.ZERO
var _move_preview_scale_target := Vector3.ONE
var _move_shadow_modes: Dictionary = {}
var _offering_preview: Node3D
var _offering_kind := ""
var _offering_id := ""
var _offering_collection_id := ""
var _offering_dropping := false
var _offering_swallowed_callback: Callable
var _exchange_reward_visual: Node3D
var _light_flash_boost := 0.0
var _meter_tween: Tween
var _well_tween: Tween
var _well_rotation_tween: Tween
var _well_is_stirred := false
var _reward_launch_ids: Dictionary = {}
var _motes: Array[MeshInstance3D] = []
var _active_tweens: Array[Tween] = []
var _reward_tweens: Array[Tween] = []
var _reward_visual_templates: Dictionary = {}
var _reward_template_warming := false
var _player_interaction_busy := false
var _pending_pulse_entries: Dictionary = {}
var _move_paused_tweens: Dictionary = {}
var _interaction_paused_tweens: Dictionary = {}


func setup(
	game_core: GameCore,
	asset_library: AssetLibrary,
	game_audio: GameAudio,
	view_camera: Camera3D,
	ui_kit: UiKit
) -> void:
	core = game_core
	assets = asset_library
	audio = game_audio
	camera = view_camera
	kit = ui_kit
	_tile_factory = TileVisualFactory.new(assets, core.grid)
	_structure_factory = StructureVisualFactory.new(assets, core.grid)
	_build_portal()
	_build_progress_card()
	core.diorama.worldheart.pulse_queued.connect(_on_pulse_queued)
	core.diorama.worldheart.state_changed.connect(_sync_entries)
	core.diorama.worldheart.contribution_changed.connect(_on_contribution_changed)
	core.diorama.worldheart.worldheart_moved.connect(_on_worldheart_moved)
	core.diorama.worldheart.worldheart_rotated.connect(_on_worldheart_rotated)
	_sync_well_rotation(false)
	_sync_entries()
	_sync_progress_card()
	set_process(true)
	prime_reward_collection()


func prime_reward_collection(collection_id := "") -> void:
	if DisplayServer.get_name() == "headless" or _reward_template_warming:
		return
	_reward_template_warming = true
	var members := core.diorama.collections.eligible_members("", collection_id)
	var asset_ids: Array = []
	var seen_assets := {}
	for member: Dictionary in members:
		var content_id := String(member.get("id", ""))
		if String(member.get("kind", "")) == "structure":
			var structure := core.registries.structure(content_id)
			if structure != null and not seen_assets.has(structure.asset_id):
				seen_assets[structure.asset_id] = true
				asset_ids.append(structure.asset_id)
		else:
			var tile := core.registries.tile(content_id)
			if tile == null:
				continue
			if not tile.uses_layered_visual():
				if not seen_assets.has(tile.asset_id):
					seen_assets[tile.asset_id] = true
					asset_ids.append(tile.asset_id)
			else:
				for layer: Defs.TileVisualLayerDefinition in tile.visual_layers:
					if not seen_assets.has(layer.asset_id):
						seen_assets[layer.asset_id] = true
						asset_ids.append(layer.asset_id)
	await assets.prime_packed_scenes_async(asset_ids)
	if not is_inside_tree():
		_reward_template_warming = false
		return
	var tree := get_tree()
	for member: Dictionary in members:
		if not is_inside_tree():
			_reward_template_warming = false
			return
		var key := _reward_visual_key(member)
		if _reward_visual_templates.has(key):
			continue
		if tree != null:
			await tree.process_frame
		while _player_interaction_busy and is_inside_tree():
			await tree.process_frame
		if not is_inside_tree():
			_reward_template_warming = false
			return
		if _reward_visual_templates.has(key):
			continue
		_reward_visual_templates[key] = _build_reward_visual(member)
	_reward_template_warming = false


func set_player_interaction_busy(busy: bool) -> void:
	if _player_interaction_busy == busy:
		return
	_player_interaction_busy = busy
	if busy:
		_interaction_paused_tweens.clear()
		var candidates: Array[Tween] = _reward_tweens.duplicate()
		if (
			not _reward_launch_ids.is_empty()
			and _well_tween != null
			and not candidates.has(_well_tween)
		):
			candidates.append(_well_tween)
		for tween: Tween in candidates:
			if tween != null and tween.is_valid() and tween.is_running():
				tween.pause()
				_interaction_paused_tweens[tween] = true
		return
	for tween: Tween in _interaction_paused_tweens.keys():
		if tween == null or not tween.is_valid() or _moving_preview:
			continue
		tween.play()
	_interaction_paused_tweens.clear()


func interaction_at_screen(
	camera: Camera3D,
	screen_position: Vector2,
	radius: float
) -> Dictionary:
	var closest: Dictionary = {}
	var closest_distance := INF
	for entry_id: String in _entry_nodes:
		var node := _entry_nodes[entry_id] as Node3D
		if not is_instance_valid(node) or camera.is_position_behind(node.global_position):
			continue
		var distance := screen_position.distance_to(
			camera.unproject_position(node.global_position + Vector3.UP * 0.08)
		)
		if distance <= radius and distance < closest_distance:
			closest_distance = distance
			closest = {
				"kind": "worldheart_reward",
				"entry_id": entry_id,
				"point": node.global_position,
				"visual": node,
				"display_name": core.build_rewards.display_name(_entry(entry_id)),
				"collection_name": _collection_name(_entry(entry_id)),
			}
	if not closest.is_empty():
		return closest
	var centre := _well_interaction_anchor()
	if not camera.is_position_behind(centre):
		var hole_distance := screen_position.distance_to(
			camera.unproject_position(centre)
		)
		# No widening: the well is a compact round target, and the wardrobe's
		# 1.3x fudge made this circle reach clicks meant for neighbouring
		# tiles and rewards.
		if hole_distance <= radius:
			return {
				"kind": "worldheart_collect_all",
				"point": centre,
				"visual": _well_interaction_visual(),
				"display_name": "Worldheart",
				"collection_name": "Collect gifts or offer a spare",
			}
	return {}


func interaction_at_cell(cell: Vector2i) -> Dictionary:
	for entry_id: String in _entry_cells:
		if _entry_cells[entry_id] == cell and _entry_nodes.has(entry_id):
			return {
				"kind": "worldheart_reward",
				"entry_id": entry_id,
				"point": (_entry_nodes[entry_id] as Node3D).global_position,
				"visual": _entry_nodes[entry_id],
				"display_name": core.build_rewards.display_name(_entry(entry_id)),
				"collection_name": _collection_name(_entry(entry_id)),
			}
	if cell == core.diorama.worldheart.worldheart_cell:
		return {
			"kind": "worldheart_collect_all",
			"point": _well_interaction_anchor(),
			"visual": _well_interaction_visual(),
			"display_name": "Worldheart",
			"collection_name": "Collect gifts or offer a spare",
		}
	return {}


func event_at_screen(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	return interaction_at_screen(
		camera,
		screen_position,
		core.registries.tunef("click_target_screen_radius", 54.0)
	)


func event_at_cell(cell: Vector2i) -> Dictionary:
	return interaction_at_cell(cell)


func hole_at_screen(
	camera: Camera3D,
	screen_position: Vector2,
	radius := 42.0
) -> bool:
	var target := _well_interaction_anchor()
	if camera == null or camera.is_position_behind(target):
		return false
	# Plain radius for the same reason as interaction_at_screen: the widened
	# wardrobe-era circle stole right-click rotations from the tile beside it.
	return screen_position.distance_to(camera.unproject_position(target)) <= radius


func rotate_at_screen(
	view_camera: Camera3D,
	screen_position: Vector2,
	radius := 54.0
) -> bool:
	if not hole_at_screen(view_camera, screen_position, radius):
		return false
	rotate_clockwise()
	return true


func rotate_clockwise() -> void:
	core.diorama.worldheart.rotate_clockwise()


func show_offering_preview(
	kind: String,
	content_id: String,
	source_world_position := Vector3.ZERO,
	animate_from_source := false
) -> bool:
	if _offering_dropping:
		return false
	var membership := core.diorama.collections.membership(kind, content_id)
	if membership.is_empty():
		clear_offering_preview()
		return false
	if (
		is_instance_valid(_offering_preview)
		and _offering_kind == kind
		and _offering_id == content_id
	):
		_stir_well()
		return true
	clear_offering_preview()
	_offering_kind = kind
	_offering_id = content_id
	_offering_collection_id = String(membership.get("collection_id", ""))
	_offering_preview = _create_reward_visual({"kind": kind, "id": content_id})
	_offering_preview.name = "WorldheartOfferingPreview"
	add_child(_offering_preview)
	_stir_well()
	var target := _offering_anchor()
	progress_card_sprite.visible = false
	if animate_from_source:
		_offering_preview.global_position = source_world_position
		_offering_preview.scale = Vector3.ONE * 1.34
	else:
		_offering_preview.position = target
		_offering_preview.scale = Vector3.ONE * 0.56
	return true


func clear_offering_preview() -> void:
	if _offering_dropping:
		return
	var cleared_preview := is_instance_valid(_offering_preview)
	if is_instance_valid(_offering_preview):
		_offering_preview.queue_free()
	_offering_preview = null
	_offering_kind = ""
	_offering_id = ""
	_offering_collection_id = ""
	# Main polls this method while no item is held. Do not let that idle polling
	# cancel the separate reward-ejection open animation every frame.
	if cleared_preview and not is_instance_valid(_exchange_reward_visual):
		_settle_well()


func has_offering_preview() -> bool:
	return is_instance_valid(_offering_preview) and not _offering_dropping


## The miniature remains continuous with the hover preview, then dives into
## the well's dark mouth. Ownership changes only once the hole swallows it.
func drop_offering(on_swallowed: Callable) -> void:
	if not has_offering_preview():
		if on_swallowed.is_valid():
			on_swallowed.call()
		return
	_offering_dropping = true
	_offering_swallowed_callback = on_swallowed
	_stir_well()
	var visual := _offering_preview
	var visual_instance_id := visual.get_instance_id()
	var fall := _create_tracked_tween()
	fall.set_parallel()
	fall.tween_property(
		visual,
		"position",
		_well_mouth_anchor(),
		0.34
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(visual, "scale", Vector3.ONE * 0.025, 0.34).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_IN)
	fall.tween_property(visual, "rotation:y", visual.rotation.y + PI * 1.5, 0.34)
	fall.chain().tween_callback(_finish_offering_drop.bind(visual_instance_id))


func _finish_offering_drop(visual_instance_id: int) -> void:
	var visual := instance_from_id(visual_instance_id) as Node3D
	if is_instance_valid(visual):
		visual.queue_free()
	_offering_preview = null
	_offering_dropping = false
	_offering_kind = ""
	_offering_id = ""
	_offering_collection_id = ""
	if audio != null:
		audio.play_event("store", -3.0, 0.82)
	var swallowed_callback := _offering_swallowed_callback
	_offering_swallowed_callback = Callable()
	if swallowed_callback.is_valid():
		swallowed_callback.call()
	_settle_well(true)


func begin_move_preview() -> void:
	if _moving_preview:
		return
	_moving_preview = true
	_move_preview_cell = INVALID_PREVIEW_CELL
	_move_preview_target = portal_fx_root.position
	_move_preview_scale_target = Vector3.ONE
	core.diorama.worldheart.set_generation_paused(
		MOVE_GENERATION_PAUSE, true
	)
	_set_reward_presentation_paused(true)
	_set_move_shadows_enabled(false)
	if progress_card_sprite != null:
		progress_card_sprite.visible = false
	if progress_card_viewport != null:
		progress_card_viewport.render_target_update_mode = (
			SubViewport.UPDATE_DISABLED
		)


func preview_move(cell: Vector2i) -> void:
	if not _moving_preview:
		return
	# Mouse motion arrives once per pixel, while the well only moves between
	# snapped cells. Avoid propagating thousands of redundant transforms through
	# both authored wardrobe hierarchies while the pointer remains in one cell.
	if cell == _move_preview_cell:
		return
	_move_preview_cell = cell
	_move_preview_target = core.grid.cell_to_world(cell) + Vector3.UP * 0.025
	_move_preview_scale_target = (
		Vector3.ONE
		if core.diorama.worldheart.can_move_to(cell)
		else Vector3(0.76, 1.0, 0.76)
	)


func cancel_move_preview() -> void:
	_finish_move_preview()
	portal_fx_root.scale = Vector3.ONE
	portal_fx_root.position = _centre() + Vector3.UP * 0.025
	_sync_progress_card()


func _process(delta: float) -> void:
	_elapsed += delta
	if _moving_preview:
		# Pointer events only select the next cell. The authored hierarchy receives
		# one eased transform per rendered frame, avoiding event-rate transform and
		# shadow work while making both pointer and controller movement feel fluid.
		var response := 1.0 - exp(-delta * MOVE_PREVIEW_RESPONSE)
		portal_fx_root.position = portal_fx_root.position.lerp(
			_move_preview_target, response
		)
		portal_fx_root.scale = portal_fx_root.scale.lerp(
			_move_preview_scale_target, response
		)
		return
	var index := 0
	for entry_id: String in _entry_nodes:
		var node := _entry_nodes[entry_id] as Node3D
		if is_instance_valid(node):
			if bool(node.get_meta(&"worldheart_launching", false)):
				continue
			node.position.y = 0.28 + sin(_elapsed * 1.65 + float(index) * 1.3) * 0.035
			node.rotation.y += delta * (0.32 + float(index) * 0.025)
		index += 1
	if well_shake_root != null:
		if _well_is_stirred and is_instance_valid(_offering_preview):
			# A delighted, slightly impatient well: the model stays grounded
			# while the nested root supplies the funny hover wobble.
			well_shake_root.rotation.z = sin(_elapsed * 13.0) * 0.026
			well_shake_root.rotation.y = sin(_elapsed * 9.0 + 0.7) * 0.035
			well_shake_root.position.y = abs(sin(_elapsed * 11.0)) * 0.012
		else:
			well_shake_root.rotation = well_shake_root.rotation.lerp(
				Vector3.ZERO, 1.0 - exp(-delta * 15.0)
			)
			well_shake_root.position = well_shake_root.position.lerp(
				Vector3.ZERO, 1.0 - exp(-delta * 15.0)
			)
	if is_instance_valid(_offering_preview) and not _offering_dropping:
		var hover_target := _offering_anchor() + Vector3.UP * (
			sin(_elapsed * 2.4) * 0.025
		)
		_offering_preview.position = _offering_preview.position.lerp(
			hover_target, 1.0 - exp(-delta * 12.0)
		)
		_offering_preview.scale = _offering_preview.scale.lerp(
			Vector3.ONE * 0.56, 1.0 - exp(-delta * 10.0)
		)
		_offering_preview.rotation.y += delta * 0.7
func _build_portal() -> void:
	portal_fx_root = Node3D.new()
	portal_fx_root.name = "PortalFxRoot"
	portal_fx_root.position = _centre() + Vector3.UP * 0.025
	add_child(portal_fx_root)

	vortex_pivot = Node3D.new()
	vortex_pivot.name = "WellVisualPivot"
	portal_fx_root.add_child(vortex_pivot)

	well_motion_root = Node3D.new()
	well_motion_root.name = "WellMotionRoot"
	vortex_pivot.add_child(well_motion_root)
	well_shake_root = Node3D.new()
	well_shake_root.name = "WellShakeRoot"
	well_motion_root.add_child(well_shake_root)
	well_visual_root = Node3D.new()
	well_visual_root.name = "WellModel"
	well_visual_root.scale = Vector3.ONE * WELL_SCALE
	well_shake_root.add_child(well_visual_root)

	var well_visual := assets.instantiate(WELL_ASSET)
	well_visual.name = "WishingWell"
	well_visual_root.add_child(well_visual)
	_style_well_meshes(well_visual)

	# The imported shaft is open all the way down with no floor, so without this
	# the camera would see terrain through the well. A flat unlit black disc sunk
	# mid-shaft IS the game's dark hole: items vanish into it and shoot out of it.
	hole = MeshInstance3D.new()
	hole.name = "WellMouthHole"
	var hole_mesh := CylinderMesh.new()
	hole_mesh.top_radius = WELL_MOUTH_DISC_RADIUS
	hole_mesh.bottom_radius = WELL_MOUTH_DISC_RADIUS
	hole_mesh.height = 0.02
	hole_mesh.radial_segments = 24
	hole_mesh.cap_bottom = false
	hole.mesh = hole_mesh
	hole.position = Vector3(0.0, WELL_MOUTH_DISC_HEIGHT, 0.0)
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hole_material := StandardMaterial3D.new()
	hole_material.albedo_color = Color.BLACK
	hole_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hole_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	hole_material.render_priority = 1
	hole.material_override = hole_material
	# Child of the MODEL, not of the holder: AssetEditLibrary.decorate applies
	# the asset's edit scale to the instantiated model root, so a sibling keeps
	# its original size and the shaft stayed full-sized when the well was
	# scaled down in Asset Studio.
	well_visual.add_child(hole)

	# Stable empty attachment roots keep save/review tooling compatible without
	# rendering any of the retired neon portal furniture.
	outer_aura_pivot = Node3D.new()
	outer_aura_pivot.name = "RetiredAuraPivot"
	portal_fx_root.add_child(outer_aura_pivot)
	rune_stone_ring_pivot = Node3D.new()
	rune_stone_ring_pivot.name = "RetiredRuneStonePivot"
	portal_fx_root.add_child(rune_stone_ring_pivot)
	mote_emitter_pivot = Node3D.new()
	mote_emitter_pivot.name = "RetiredMotePivot"
	portal_fx_root.add_child(mote_emitter_pivot)

	portal_fx_root.scale = Vector3.ONE * 0.01
	var opening := _create_tracked_tween()
	opening.tween_property(portal_fx_root, "scale", Vector3.ONE * 1.08, 0.28).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	opening.tween_property(portal_fx_root, "scale", Vector3.ONE, 0.2).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_OUT)


func _build_progress_card() -> void:
	progress_card_viewport = SubViewport.new()
	progress_card_viewport.name = "WorldheartProgressCardViewport"
	progress_card_viewport.size = PROGRESS_CARD_VIEWPORT_SIZE
	progress_card_viewport.transparent_bg = true
	# Card contents only change on contribution events. Keeping this viewport
	# live every frame made dragging the detailed model needlessly expensive.
	progress_card_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	progress_card_viewport.snap_2d_transforms_to_pixel = true
	progress_card_viewport.snap_2d_vertices_to_pixel = true
	add_child(progress_card_viewport)

	var canvas := Control.new()
	canvas.name = "WorldheartProgressCardCanvas"
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.theme = kit.theme
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_card_viewport.add_child(canvas)

	# This is the same card component and token palette used by the Build Bag,
	# simply reduced to a small, flat world-space status chip.
	progress_card = kit.card(PROGRESS_CARD_SIZE)
	progress_card.name = "WorldheartProgressCard"
	progress_card.position = Vector2(3, 3)
	progress_card.size = PROGRESS_CARD_SIZE
	progress_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_style := kit.surface_style(
		Color(kit.ui_color("cell"), 0.99), 12
	)
	card_style.content_margin_left = 10
	card_style.content_margin_right = 10
	card_style.content_margin_top = 6
	card_style.content_margin_bottom = 6
	progress_card.add_theme_stylebox_override("panel", card_style)
	canvas.add_child(progress_card)

	var row := HBoxContainer.new()
	row.name = "WorldheartProgressContent"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_card.add_child(row)

	progress_icon = TextureRect.new()
	progress_icon.name = "WorldheartCollectionIcon"
	progress_icon.custom_minimum_size = Vector2(24, 24)
	progress_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	progress_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	progress_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(progress_icon)

	progress_count_label = kit.label("0 / 2", 18, false, true)
	progress_count_label.name = "WorldheartContributionCount"
	progress_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	progress_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(progress_count_label)

	progress_card_sprite = Sprite3D.new()
	progress_card_sprite.name = "WorldheartProgressCardSprite"
	progress_card_sprite.texture = progress_card_viewport.get_texture()
	progress_card_sprite.pixel_size = 0.003
	progress_card_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	progress_card_sprite.no_depth_test = true
	progress_card_sprite.render_priority = 11
	progress_card_sprite.position = _meter_anchor()
	progress_card_sprite.visible = false
	add_child(progress_card_sprite)


func _on_pulse_queued(entry: Dictionary) -> void:
	var entry_id := String(entry.get("entry_id", ""))
	if entry_id == "":
		return
	_pending_pulse_entries[entry_id] = entry.duplicate(true)
	if DisplayServer.get_name() == "headless":
		_pending_pulse_entries.erase(entry_id)
		_sync_entries()
		var node := _entry_nodes.get(entry_id) as Node3D
		if node != null:
			_begin_pulse_launch(entry, node)
		return
	_prepare_pulse_entry(entry.duplicate(true))


func _prepare_pulse_entry(entry: Dictionary) -> void:
	var entry_id := String(entry.get("entry_id", ""))
	var key := _reward_visual_key(entry)
	if not _reward_visual_templates.has(key):
		var asset_ids := _reward_asset_ids(entry)
		await assets.prime_packed_scenes_async(asset_ids)
		if not is_inside_tree():
			return
		await get_tree().process_frame
		if not is_inside_tree():
			return
		while _player_interaction_busy and is_inside_tree():
			await get_tree().process_frame
		if not is_inside_tree():
			return
		if not _reward_visual_templates.has(key):
			_reward_visual_templates[key] = _build_reward_visual(entry)
	# Never build or begin a spawn presentation in the same frame as a click,
	# held-piece edit, Build Bag interaction, or modal transition.
	while _player_interaction_busy and is_inside_tree():
		await get_tree().process_frame
	if not is_inside_tree() or not _pending_pulse_entries.has(entry_id):
		return
	_pending_pulse_entries.erase(entry_id)
	_sync_entries()
	var node := _entry_nodes.get(entry_id) as Node3D
	# Reserve entries beyond the visible cap are warmed now and presented only
	# if they later rotate into the visible set.
	if node == null:
		return
	_begin_pulse_launch(entry, node)


func _begin_pulse_launch(entry: Dictionary, node: Node3D) -> void:
	_sync_entries()
	var landing := node.position
	var start := _well_mouth_anchor()
	var node_instance_id := node.get_instance_id()
	node.set_meta(&"worldheart_launching", true)
	node.position = start
	node.scale = Vector3.ONE * 0.04
	_begin_reward_launch(node_instance_id)
	var pulse := _create_reward_tween()
	pulse.tween_interval(WELL_LAUNCH_DELAY)
	pulse.tween_method(
		_animate_well_reward.bind(node_instance_id, start, landing),
		0.0,
		1.0,
		REWARD_LAUNCH_DURATION
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pulse.parallel().tween_property(node, "scale", Vector3.ONE, 0.54).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	pulse.parallel().tween_property(
		node, "rotation:y", node.rotation.y + PI * 1.35, REWARD_LAUNCH_DURATION
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pulse.tween_property(node, "scale", Vector3(1.08, 0.86, 1.08), 0.07)
	pulse.tween_property(node, "scale", Vector3(0.96, 1.06, 0.96), 0.10)
	pulse.tween_property(node, "scale", Vector3.ONE, 0.13).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	pulse.tween_callback(
		_finish_pulse_launch.bind(node_instance_id, landing)
	)
	if audio != null:
		audio.play_event("parcel_appear", -2.0, 0.92)


func _animate_well_reward(
	progress: float,
	node_instance_id: int,
	start: Vector3,
	landing: Vector3
) -> void:
	var node := instance_from_id(node_instance_id) as Node3D
	if not is_instance_valid(node):
		return
	# Straight up out of the mouth first -- the miniature has to visibly clear
	# the rim before it may drift sideways, or it clips through the stone. Then
	# a ballistic fall outward to wherever its landing slot is, which is what
	# spreads consecutive gifts in different directions around the well.
	var apex := Vector3(start.x, _centre().y + WELL_LAUNCH_APEX, start.z)
	if progress < 0.38:
		var rise := progress / 0.38
		# Ease-out on the climb: fast out of the hole, slowing near the top.
		node.position = start.lerp(apex, 1.0 - (1.0 - rise) * (1.0 - rise))
		return
	var arc := (progress - 0.38) / 0.62
	node.position = apex.lerp(landing, arc)
	# Falling from the apex, not floating: height eases DOWN along the whole
	# second phase, with a small residual curve so it reads thrown, not dropped.
	node.position.y = lerpf(apex.y, landing.y, arc * arc) + sin(arc * PI) * 0.10


func _finish_pulse_launch(node_instance_id: int, landing: Vector3) -> void:
	var node := instance_from_id(node_instance_id) as Node3D
	if is_instance_valid(node):
		node.position = landing
		node.scale = Vector3.ONE
		node.set_meta(&"worldheart_launching", false)
	_end_reward_launch(node_instance_id)


func _begin_reward_launch(node_instance_id: int) -> void:
	_reward_launch_ids[node_instance_id] = true
	_stir_well()


func _end_reward_launch(node_instance_id: int) -> void:
	_reward_launch_ids.erase(node_instance_id)
	if _reward_launch_ids.is_empty():
		_settle_well(true)


func _play_portal_flash(strength: float) -> void:
	if well_motion_root == null:
		return
	var amount := clampf(strength, 0.0, 1.0)
	var kick := _create_tracked_tween()
	kick.tween_property(
		well_motion_root,
		"scale",
		Vector3(1.0 + amount * 0.06, 1.0 - amount * 0.05, 1.0),
		0.08
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	kick.tween_property(
		well_motion_root, "scale", Vector3.ONE, 0.16
	).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## The well has no doors, so its excitement is all body language: a quick
## anticipation squash, a stretch, and an elastic settle -- the same silhouette
## beats the wardrobe animated with, minus the swings.
func _stir_well() -> void:
	if _well_is_stirred or well_motion_root == null:
		return
	_well_is_stirred = true
	_kill_well_tween()
	well_motion_root.scale = Vector3.ONE
	well_motion_root.rotation = Vector3.ZERO
	_well_tween = create_tween()
	_well_tween.tween_property(
		well_motion_root, "scale", Vector3(0.93, 1.07, 0.93), 0.09
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_well_tween.parallel().tween_property(
		well_motion_root, "rotation:z", 0.05, 0.09
	)
	_well_tween.tween_property(
		well_motion_root, "scale", Vector3(1.07, 0.95, 1.07), 0.18
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_well_tween.parallel().tween_property(
		well_motion_root, "rotation:z", -0.04, 0.18
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_well_tween.tween_property(
		well_motion_root, "scale", Vector3.ONE, 0.18
	).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_well_tween.parallel().tween_property(
		well_motion_root, "rotation", Vector3.ZERO, 0.20
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if audio != null:
		audio.play_event("build_preview", -7.0, 1.12)


func _settle_well(swallowed := false) -> void:
	if well_motion_root == null:
		return
	if not _reward_launch_ids.is_empty():
		return
	if is_instance_valid(_offering_preview) and not _offering_dropping:
		return
	if not _well_is_stirred:
		return
	_well_is_stirred = false
	_kill_well_tween()
	well_shake_root.rotation = Vector3.ZERO
	well_shake_root.position = Vector3.ZERO
	_well_tween = create_tween()
	var anticipation := 0.12 if swallowed else 0.08
	_well_tween.tween_property(
		well_motion_root,
		"scale",
		Vector3(1.12, 0.88, 1.12) if swallowed else Vector3(1.05, 0.95, 1.05),
		anticipation
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_well_tween.parallel().tween_property(
		well_motion_root, "rotation:z", 0.06 if swallowed else 0.03, anticipation
	)
	_well_tween.tween_property(
		well_motion_root,
		"scale",
		Vector3(0.90, 1.11, 0.90) if swallowed else Vector3(0.96, 1.04, 0.96),
		0.10
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_well_tween.parallel().tween_property(
		well_motion_root, "rotation:z", -0.045 if swallowed else -0.02, 0.10
	)
	_well_tween.tween_property(
		well_motion_root, "scale", Vector3.ONE, 0.27 if swallowed else 0.16
	).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_well_tween.parallel().tween_property(
		well_motion_root, "rotation", Vector3.ZERO, 0.20
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _kill_well_tween() -> void:
	if _well_tween != null and _well_tween.is_valid():
		_well_tween.kill()
	_well_tween = null


func _sync_entries() -> void:
	if core == null:
		return
	var visible := core.diorama.worldheart.visible_entries()
	if not _moving_preview:
		portal_fx_root.position = _centre() + Vector3.UP * 0.025
	var live_ids: Array[String] = []
	for index in visible.size():
		var entry: Dictionary = visible[index]
		var entry_id := String(entry.get("entry_id", ""))
		live_ids.append(entry_id)
		var created := false
		if (
			_pending_pulse_entries.has(entry_id)
			and not _entry_nodes.has(entry_id)
		):
			continue
		if not _entry_nodes.has(entry_id):
			var node := _create_reward_visual(entry)
			node.name = "WorldheartReward_%s" % entry_id.replace(":", "_")
			add_child(node)
			_entry_nodes[entry_id] = node
			created = true
		var cell := _entry_landing_cell(entry, index)
		if not _entry_cells.has(entry_id):
			_entry_cells[entry_id] = cell
		var holder := _entry_nodes[entry_id] as Node3D
		if bool(holder.get_meta(&"worldheart_launching", false)):
			continue
		# Landing transforms belong to the reward, not to the well. A moved or
		# rotated well must never drag already-surfaced loot around the world.
		if created:
			holder.position = _entry_landing_position(entry, index)
	for entry_id: String in _entry_nodes.keys():
		if live_ids.has(entry_id):
			continue
		var stale := _entry_nodes[entry_id] as Node3D
		_entry_nodes.erase(entry_id)
		_entry_cells.erase(entry_id)
		if is_instance_valid(stale):
			if bool(stale.get_meta(&"worldheart_launching", false)):
				stale.set_meta(&"worldheart_launching", false)
				_end_reward_launch(stale.get_instance_id())
			var vanish := _create_tracked_tween()
			vanish.tween_property(stale, "scale", Vector3.ONE * 0.03, 0.16).set_trans(
				Tween.TRANS_BACK
			).set_ease(Tween.EASE_IN)
			vanish.tween_callback(stale.queue_free)


func _create_reward_visual(reward: Dictionary) -> Node3D:
	var key := _reward_visual_key(reward)
	if _reward_visual_templates.has(key):
		var template := _reward_visual_templates[key] as Node3D
		if is_instance_valid(template):
			return template.duplicate() as Node3D
	return _build_reward_visual(reward)


func _build_reward_visual(reward: Dictionary) -> Node3D:
	var holder := Node3D.new()
	var visual: Node3D
	match String(reward.get("kind", "")):
		"tile":
			var tile := core.registries.tile(String(reward.get("id", "")))
			if tile != null:
				visual = _tile_factory.instantiate_visual(tile, true)
		"structure":
			var structure := core.registries.structure(String(reward.get("id", "")))
			if structure != null:
				visual = _structure_factory.instantiate_visual(
					structure, false, hash(String(reward.get("id", "")))
				)
	if visual == null:
		var fallback := SphereMesh.new()
		fallback.radius = 0.12
		fallback.height = 0.24
		var mesh := MeshInstance3D.new()
		mesh.mesh = fallback
		visual = mesh
	holder.add_child(visual)
	var bounds_data := StructureVisualFactory.local_mesh_bounds(holder)
	if bool(bounds_data.get("found", false)):
		var bounds: AABB = bounds_data["bounds"]
		var largest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		if largest > 0.0001:
			var fit := 0.42 / largest
			visual.scale *= fit
			visual.position -= (bounds.position + bounds.size * 0.5) * fit
	return holder


func _reward_visual_key(reward: Dictionary) -> String:
	return "%s:%s" % [reward.get("kind", ""), reward.get("id", "")]


func _reward_asset_ids(reward: Dictionary) -> Array:
	var result: Array = []
	var content_id := String(reward.get("id", ""))
	if String(reward.get("kind", "")) == "structure":
		var structure := core.registries.structure(content_id)
		if structure != null:
			result.append(structure.asset_id)
		return result
	var tile := core.registries.tile(content_id)
	if tile == null:
		return result
	if not tile.uses_layered_visual():
		result.append(tile.asset_id)
		return result
	for layer: Defs.TileVisualLayerDefinition in tile.visual_layers:
		if not result.has(layer.asset_id):
			result.append(layer.asset_id)
	return result


func _entry_landing_cell(entry: Dictionary, fallback_index: int) -> Vector2i:
	var raw: Variant = entry.get("landing_cell", [])
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return _anchor_cell(fallback_index)


func _entry_landing_position(
	entry: Dictionary, fallback_index: int
) -> Vector3:
	var raw: Variant = entry.get("landing_position", [])
	if raw is Array and (raw as Array).size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	var cell := _anchor_cell(fallback_index)
	return core.grid.cell_to_world(cell) + _anchor_inset(fallback_index) + Vector3.UP * 0.28


func _anchor_cell(index: int) -> Vector2i:
	# Fill the space in front of the doors first, then fan remaining gifts around
	# the well. Rotating the well rotates this whole local layout.
	var local_offset: Vector2i = [
		Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP
	][index % 4]
	return (
		core.diorama.worldheart.worldheart_cell
		+ _rotate_grid_offset(local_offset)
	)


func _rotate_grid_offset(local_offset: Vector2i) -> Vector2i:
	match posmod(core.diorama.worldheart.worldheart_rotation_quarters, 4):
		1:
			return Vector2i(local_offset.y, -local_offset.x)
		2:
			return -local_offset
		3:
			return Vector2i(-local_offset.y, local_offset.x)
	return local_offset


func _anchor_inset(index: int) -> Vector3:
	var offset := _anchor_cell(index) - core.diorama.worldheart.worldheart_cell
	var direction := Vector3(-offset.x, 0.0, -offset.y)
	return direction * core.grid.tile_size * 0.23


func _centre() -> Vector3:
	return core.grid.cell_to_world(core.diorama.worldheart.worldheart_cell)


func _well_interaction_visual() -> Node3D:
	return well_visual_root


## Everything targets the mouth: the well is radially symmetric, so unlike the
## wardrobe's doorway none of these anchors depends on the rotation quarter.
func _well_interaction_anchor() -> Vector3:
	return _centre() + Vector3.UP * WELL_CLICK_ANCHOR_HEIGHT


func _well_mouth_anchor() -> Vector3:
	return _centre() + Vector3.UP * WELL_MOUTH_ANCHOR_HEIGHT


func _offering_anchor() -> Vector3:
	return _centre() + Vector3.UP * WELL_HOVER_HEIGHT


func _meter_anchor() -> Vector3:
	return _centre() + Vector3.UP * 1.34


func _entry(entry_id: String) -> Dictionary:
	for entry: Dictionary in core.diorama.worldheart.visible_entries():
		if String(entry.get("entry_id", "")) == entry_id:
			return entry
	return {}


func _collection_name(entry: Dictionary) -> String:
	var definition = core.registries.creative_collection(
		String(entry.get("creative_collection_id", ""))
	)
	return definition.display_name if definition != null else "Worldheart Gift"


func _sync_progress_card(collection_id := "", force_visible := false) -> void:
	if progress_card_sprite == null or _moving_preview:
		return
	if progress_card_viewport != null:
		progress_card_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	progress_card_sprite.position = _meter_anchor()
	if collection_id == "":
		collection_id = core.diorama.worldheart.active_contribution_collection_id
	var progress := core.diorama.worldheart.contribution_progress(collection_id)
	# Stored progress lives in the save, but the card is a reaction to a
	# completed drop—not permanent furniture and never part of hover preview.
	progress_card_sprite.visible = collection_id != "" and force_visible
	if not progress_card_sprite.visible:
		return
	progress_count_label.text = "%d / %d" % [
		progress,
		core.diorama.worldheart.contribution_required(),
	]
	progress_icon.texture = load(_collection_icon_path(collection_id)) as Texture2D


func _collection_icon_path(collection_id: String) -> String:
	return {
		"meadow": "res://assets/ui/icons/category_nature.svg",
		"woodland": "res://assets/ui/icons/category_woodland.svg",
		"homestead": "res://assets/ui/icons/category_furniture.svg",
		"waterside": "res://assets/ui/icons/category_utilities.svg",
		"stone": "res://assets/ui/icons/category_stone.svg",
		"winter": "res://assets/ui/icons/category_winter.svg",
	}.get(collection_id, "res://assets/ui/icons/category_nature.svg")


func _on_contribution_changed(
	collection_id: String,
	progress: int,
	required: int,
	completed: bool,
	reward: Dictionary
) -> void:
	if _meter_tween != null and _meter_tween.is_valid():
		_meter_tween.kill()
	_meter_tween = null
	_sync_progress_card(collection_id, true)
	progress_card_sprite.visible = true
	progress_card_sprite.position = _meter_anchor() + Vector3.DOWN * 0.025
	progress_count_label.text = "%d / %d" % [progress, required]
	progress_card_sprite.modulate.a = 1.0
	progress_card_sprite.scale = Vector3.ONE * 0.82
	var fill := create_tween()
	_meter_tween = fill
	fill.tween_property(
		progress_card_sprite, "scale", Vector3.ONE * 1.06, 0.18
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	fill.parallel().tween_property(
		progress_card_sprite, "position", _meter_anchor(), 0.18
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fill.tween_property(
		progress_card_sprite, "scale", Vector3.ONE, 0.14
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if completed:
		fill.tween_interval(0.78)
		fill.tween_callback(_spit_exchange_reward.bind(reward.duplicate(true)))
		fill.tween_interval(1.15)
		fill.tween_property(
			progress_card_sprite, "scale", Vector3.ONE * 0.74, 0.18
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		fill.parallel().tween_property(
			progress_card_sprite, "modulate:a", 0.0, 0.18
		)
		fill.tween_callback(_finish_progress_card_reaction)
	else:
		fill.tween_interval(2.45)
		fill.tween_property(
			progress_card_sprite, "scale", Vector3.ONE * 0.74, 0.18
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		fill.parallel().tween_property(
			progress_card_sprite, "modulate:a", 0.0, 0.18
		)
		fill.tween_callback(_finish_progress_card_reaction)


func _finish_progress_card_reaction() -> void:
	if is_instance_valid(progress_card_sprite):
		progress_card_sprite.scale = Vector3.ONE
		progress_card_sprite.modulate.a = 1.0
	_sync_progress_card()
	_meter_tween = null


func _spit_exchange_reward(reward: Dictionary) -> void:
	if reward.is_empty():
		return
	if is_instance_valid(_exchange_reward_visual):
		_end_reward_launch(_exchange_reward_visual.get_instance_id())
		_exchange_reward_visual.queue_free()
	_exchange_reward_visual = _create_reward_visual(reward)
	_exchange_reward_visual.name = "WorldheartExchangeReward"
	_exchange_reward_visual.position = _well_mouth_anchor()
	_exchange_reward_visual.scale = Vector3.ONE * 0.04
	add_child(_exchange_reward_visual)
	var reward_visual := _exchange_reward_visual
	var reward_visual_instance_id := reward_visual.get_instance_id()
	_begin_reward_launch(reward_visual_instance_id)
	var start := _well_mouth_anchor()
	# An exchange has no reserved landing slot, so the direction is genuinely
	# random: up out of the mouth, then out to a hover point on a random bearing
	# around the well.
	var bearing := randf() * TAU
	var out := Vector3(cos(bearing), 0.0, sin(bearing))
	var finish := start + out * 0.92 + Vector3.UP * 0.13
	var launch := _create_reward_tween()
	launch.tween_interval(WELL_LAUNCH_DELAY)
	launch.tween_method(
		_animate_exchange_reward.bind(
			reward_visual_instance_id, start, finish
		),
		0.0,
		1.0,
		0.82
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	launch.parallel().tween_property(
		reward_visual, "scale", Vector3.ONE, 0.52
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	launch.parallel().tween_property(
		reward_visual, "rotation:y", reward_visual.rotation.y + PI * 1.5, 0.82
	)
	launch.tween_property(
		reward_visual, "scale", Vector3(1.10, 0.82, 1.10), 0.07
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	launch.tween_property(
		reward_visual, "scale", Vector3(0.94, 1.10, 0.94), 0.11
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	launch.tween_property(reward_visual, "scale", Vector3.ONE, 0.14).set_trans(
		Tween.TRANS_ELASTIC
	).set_ease(Tween.EASE_OUT)
	launch.tween_interval(0.50)
	launch.tween_property(
		reward_visual, "scale", Vector3.ONE * 0.04, 0.25
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	launch.tween_callback(_finish_exchange_reward.bind(reward_visual_instance_id))


func _animate_exchange_reward(
	value: float,
	reward_visual_instance_id: int,
	start: Vector3,
	finish: Vector3
) -> void:
	var reward_visual := instance_from_id(reward_visual_instance_id) as Node3D
	if not is_instance_valid(reward_visual):
		return
	# Same shape as the gift launch: vertically out of the mouth, then fall
	# outward to the hover point.
	var apex := Vector3(start.x, _centre().y + WELL_LAUNCH_APEX, start.z)
	if value < 0.40:
		var rise := value / 0.40
		reward_visual.position = start.lerp(apex, 1.0 - (1.0 - rise) * (1.0 - rise))
		return
	var arc := (value - 0.40) / 0.60
	reward_visual.position = apex.lerp(finish, arc)
	reward_visual.position.y = lerpf(apex.y, finish.y, arc * arc) + sin(arc * PI) * 0.10


func _finish_exchange_reward(reward_visual_instance_id: int) -> void:
	var reward_visual := instance_from_id(reward_visual_instance_id) as Node3D
	if is_instance_valid(reward_visual):
		reward_visual.queue_free()
	if (
		is_instance_valid(_exchange_reward_visual)
		and _exchange_reward_visual.get_instance_id() == reward_visual_instance_id
	):
		_exchange_reward_visual = null
	_end_reward_launch(reward_visual_instance_id)


func _on_worldheart_moved(_from: Vector2i, _to: Vector2i) -> void:
	_finish_move_preview()
	portal_fx_root.scale = Vector3.ONE
	var settle := _create_tracked_tween()
	settle.tween_property(
		portal_fx_root, "position", _centre() + Vector3.UP * 0.025, 0.14
	).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	_sync_entries()
	if is_instance_valid(_offering_preview) and not _offering_dropping:
		_offering_preview.position = _offering_anchor()
	_sync_progress_card()


func _on_worldheart_rotated(_rotation_quarters: int) -> void:
	_sync_well_rotation(true)
	_sync_entries()
	if is_instance_valid(_offering_preview) and not _offering_dropping:
		_offering_preview.position = _offering_anchor()


func _sync_well_rotation(animated: bool) -> void:
	if vortex_pivot == null:
		return
	if _well_rotation_tween != null and _well_rotation_tween.is_valid():
		_well_rotation_tween.kill()
	var target := (
		float(core.diorama.worldheart.worldheart_rotation_quarters)
		* PI
		* 0.5
	)
	if not animated:
		vortex_pivot.rotation.y = target
		return
	var resolved_target := vortex_pivot.rotation.y + angle_difference(
		vortex_pivot.rotation.y, target
	)
	_well_rotation_tween = create_tween()
	_well_rotation_tween.tween_property(
		vortex_pivot, "rotation:y", resolved_target, 0.34
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_well_rotation_tween.parallel().tween_property(
		well_motion_root, "scale", Vector3(0.94, 1.06, 0.94), 0.12
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_well_rotation_tween.tween_property(
		well_motion_root, "scale", Vector3.ONE, 0.20
	).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _style_well_meshes(root: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root as MeshInstance3D)
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(candidate as MeshInstance3D)
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.get_active_material(surface)
			if source is StandardMaterial3D:
				var styled := source.duplicate(true) as StandardMaterial3D
				styled.texture_filter = (
					BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				)
				styled.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				styled.specular_mode = BaseMaterial3D.SPECULAR_TOON
				styled.roughness = maxf(styled.roughness, 0.82)
				mesh_instance.set_surface_override_material(surface, styled)


func _create_tracked_tween() -> Tween:
	var tween := create_tween()
	_active_tweens.append(tween)
	tween.finished.connect(_forget_tween.bind(tween), CONNECT_ONE_SHOT)
	return tween


func _forget_tween(tween: Tween) -> void:
	_active_tweens.erase(tween)
	_move_paused_tweens.erase(tween)
	_interaction_paused_tweens.erase(tween)


func _create_reward_tween() -> Tween:
	var tween := _create_tracked_tween()
	_reward_tweens.append(tween)
	tween.finished.connect(_forget_reward_tween.bind(tween), CONNECT_ONE_SHOT)
	if _player_interaction_busy:
		tween.pause()
		_interaction_paused_tweens[tween] = true
	return tween


func _forget_reward_tween(tween: Tween) -> void:
	_reward_tweens.erase(tween)


func _set_reward_presentation_paused(paused: bool) -> void:
	if paused:
		_move_paused_tweens.clear()
		var candidates: Array[Tween] = _active_tweens.duplicate()
		for special: Tween in [
			_well_tween, _meter_tween, _well_rotation_tween
		]:
			if special != null and not candidates.has(special):
				candidates.append(special)
		for tween: Tween in candidates:
			if tween != null and tween.is_valid() and tween.is_running():
				tween.pause()
				_move_paused_tweens[tween] = true
		return
	for tween: Tween in _move_paused_tweens.keys():
		if tween == null or not tween.is_valid():
			continue
		if _player_interaction_busy and _reward_tweens.has(tween):
			continue
		tween.play()
	_move_paused_tweens.clear()


func _set_move_shadows_enabled(enabled: bool) -> void:
	if enabled:
		for mesh: MeshInstance3D in _move_shadow_modes:
			if is_instance_valid(mesh):
				mesh.cast_shadow = int(_move_shadow_modes[mesh])
		_move_shadow_modes.clear()
		return
	_move_shadow_modes.clear()
	if well_visual_root == null:
		return
	for candidate in well_visual_root.find_children(
		"*", "MeshInstance3D", true, false
	):
		var mesh := candidate as MeshInstance3D
		_move_shadow_modes[mesh] = mesh.cast_shadow
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _finish_move_preview() -> void:
	if not _moving_preview:
		return
	_moving_preview = false
	_move_preview_cell = INVALID_PREVIEW_CELL
	core.diorama.worldheart.set_generation_paused(
		MOVE_GENERATION_PAUSE, false
	)
	_set_reward_presentation_paused(false)
	_set_move_shadows_enabled(true)
	if progress_card_viewport != null:
		progress_card_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _exit_tree() -> void:
	if core != null and core.diorama != null and core.diorama.worldheart != null:
		core.diorama.worldheart.set_generation_paused(
			MOVE_GENERATION_PAUSE, false
		)
		core.diorama.worldheart.set_generation_paused(
			&"player_interaction", false
		)
	_offering_swallowed_callback = Callable()
	_kill_well_tween()
	if (
		_well_rotation_tween != null
		and _well_rotation_tween.is_valid()
	):
		_well_rotation_tween.kill()
	_well_rotation_tween = null
	if _meter_tween != null and _meter_tween.is_valid():
		_meter_tween.kill()
	_meter_tween = null
	# Tween-method callables retain their animated nodes. Stop them before the
	# presenter hierarchy is released so save reloads and scene changes cannot
	# invoke a lambda whose reward miniature has already been freed.
	for tween: Tween in _active_tweens:
		if tween != null:
			tween.kill()
	_active_tweens.clear()
	_reward_tweens.clear()
	for template: Node3D in _reward_visual_templates.values():
		if is_instance_valid(template):
			template.free()
	_reward_visual_templates.clear()
	_pending_pulse_entries.clear()
	_move_paused_tweens.clear()
	_interaction_paused_tweens.clear()
