class_name WorldheartPresenter
extends Node3D
## Permanent wardrobe presentation plus a small set of collectible reward
## miniatures. Targeting is screen/cell based so these visuals never need to
## occupy the authoritative build grid.

const WARDROBE_CLOSED_SCENE: PackedScene = preload(
	"res://assets/3d/reworked/worldheart_wardrobe_closed.glb"
)
const WARDROBE_OPEN_SCENE: PackedScene = preload(
	"res://assets/3d/reworked/worldheart_wardrobe_hinged.glb"
)
const WARDROBE_SCALE := 1.16
const WARDROBE_BASE_HEIGHT := 0.58
## Shut angles for the current hinged model, solved rather than eyeballed: each
## door's yaw is swept and the angle that collapses its depth footprint -- the
## one property a shut door has and an open one does not -- is taken, within the
## half-turn that keeps it on its own side. Both land on a quarter turn, which is
## the symmetry the old model's 125/-142 pair never had.
const LEFT_DOOR_CLOSED_YAW := deg_to_rad(-90.0)
const RIGHT_DOOR_CLOSED_YAW := deg_to_rad(90.0)
const WARDROBE_LAUNCH_DELAY := 0.52
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
var wardrobe_motion_root: Node3D
var wardrobe_shake_root: Node3D
var wardrobe_visual_root: Node3D
var wardrobe_closed: Node3D
var wardrobe_open: Node3D
var wardrobe_door_left: Node3D
var wardrobe_door_right: Node3D
var wardrobe_cavity: MeshInstance3D
var wardrobe_upper_cavity_mask: MeshInstance3D
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
var _wardrobe_tween: Tween
var _wardrobe_rotation_tween: Tween
var _wardrobe_is_open := false
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
	_sync_wardrobe_rotation(false)
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
			and _wardrobe_tween != null
			and not candidates.has(_wardrobe_tween)
		):
			candidates.append(_wardrobe_tween)
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
	var centre := _wardrobe_interaction_anchor()
	if not camera.is_position_behind(centre):
		var hole_distance := screen_position.distance_to(
			camera.unproject_position(centre)
		)
		if hole_distance <= radius * 1.3:
			return {
				"kind": "worldheart_collect_all",
				"point": centre,
				"visual": _wardrobe_interaction_visual(),
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
			"point": _wardrobe_interaction_anchor(),
			"visual": _wardrobe_interaction_visual(),
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
	var target := _wardrobe_interaction_anchor()
	if camera == null or camera.is_position_behind(target):
		return false
	return screen_position.distance_to(camera.unproject_position(target)) <= radius * 1.35


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
		_play_wardrobe_open()
		return true
	clear_offering_preview()
	_offering_kind = kind
	_offering_id = content_id
	_offering_collection_id = String(membership.get("collection_id", ""))
	_offering_preview = _create_reward_visual({"kind": kind, "id": content_id})
	_offering_preview.name = "WorldheartOfferingPreview"
	add_child(_offering_preview)
	_play_wardrobe_open()
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
		_play_wardrobe_close()


func has_offering_preview() -> bool:
	return is_instance_valid(_offering_preview) and not _offering_dropping


## The miniature remains continuous with the hover preview, then shoots into
## the pitch-black wardrobe. Ownership changes only once the doors swallow it.
func drop_offering(on_swallowed: Callable) -> void:
	if not has_offering_preview():
		if on_swallowed.is_valid():
			on_swallowed.call()
		return
	_offering_dropping = true
	_offering_swallowed_callback = on_swallowed
	_play_wardrobe_open()
	var visual := _offering_preview
	var visual_instance_id := visual.get_instance_id()
	var fall := _create_tracked_tween()
	fall.set_parallel()
	fall.tween_property(
		visual,
		"position",
		_wardrobe_swallow_anchor(),
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
	_play_wardrobe_close(true)


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
	# Mouse motion arrives once per pixel, while the wardrobe only moves between
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
	if wardrobe_shake_root != null:
		if _wardrobe_is_open and is_instance_valid(_offering_preview):
			# A delighted, slightly impatient cupboard: the model stays grounded
			# while the nested root supplies the funny hover wobble.
			wardrobe_shake_root.rotation.z = sin(_elapsed * 13.0) * 0.026
			wardrobe_shake_root.rotation.y = sin(_elapsed * 9.0 + 0.7) * 0.035
			wardrobe_shake_root.position.y = abs(sin(_elapsed * 11.0)) * 0.012
		else:
			wardrobe_shake_root.rotation = wardrobe_shake_root.rotation.lerp(
				Vector3.ZERO, 1.0 - exp(-delta * 15.0)
			)
			wardrobe_shake_root.position = wardrobe_shake_root.position.lerp(
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
	vortex_pivot.name = "WardrobeVisualPivot"
	portal_fx_root.add_child(vortex_pivot)

	wardrobe_motion_root = Node3D.new()
	wardrobe_motion_root.name = "WardrobeMotionRoot"
	vortex_pivot.add_child(wardrobe_motion_root)
	wardrobe_shake_root = Node3D.new()
	wardrobe_shake_root.name = "WardrobeShakeRoot"
	wardrobe_motion_root.add_child(wardrobe_shake_root)
	wardrobe_visual_root = Node3D.new()
	wardrobe_visual_root.name = "WardrobeModels"
	wardrobe_visual_root.position.y = WARDROBE_BASE_HEIGHT
	wardrobe_visual_root.scale = Vector3.ONE * WARDROBE_SCALE
	wardrobe_shake_root.add_child(wardrobe_visual_root)

	wardrobe_closed = WARDROBE_CLOSED_SCENE.instantiate() as Node3D
	wardrobe_closed.name = "WardrobeClosed"
	wardrobe_visual_root.add_child(wardrobe_closed)
	_style_wardrobe_meshes(wardrobe_closed)
	wardrobe_open = WARDROBE_OPEN_SCENE.instantiate() as Node3D
	wardrobe_open.name = "WardrobeOpen"
	wardrobe_open.visible = false
	wardrobe_visual_root.add_child(wardrobe_open)
	wardrobe_door_left = wardrobe_open.find_child(
		"WardrobeDoorLeft", true, false
	) as Node3D
	wardrobe_door_right = wardrobe_open.find_child(
		"WardrobeDoorRight", true, false
	) as Node3D
	assert(
		wardrobe_door_left != null and wardrobe_door_right != null,
		"The hinged Worldheart wardrobe must expose both authored doors"
	)
	_style_wardrobe_meshes(wardrobe_open)

	# The supplied open mesh has a fully modelled cavity. An opaque, unlit box
	# sits immediately behind the frame so no camera angle can see the terrain,
	# rewards, or scene lighting through the wardrobe.
	wardrobe_cavity = MeshInstance3D.new()
	wardrobe_cavity.name = "WorldheartWardrobeCavity"
	var cavity_mesh := BoxMesh.new()
	cavity_mesh.size = Vector3(0.37, 0.44, 0.035)
	wardrobe_cavity.mesh = cavity_mesh
	wardrobe_cavity.position = Vector3(0.0, -0.14, 0.075)
	wardrobe_cavity.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cavity_material := StandardMaterial3D.new()
	cavity_material.albedo_color = Color.BLACK
	cavity_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cavity_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cavity_material.render_priority = 1
	wardrobe_cavity.material_override = cavity_material
	wardrobe_cavity.visible = false
	wardrobe_visual_root.add_child(wardrobe_cavity)

	# The open source mesh has a thin wooden sliver crossing the gable interior.
	# A compact rectangular patch covers it without projecting a pointed edge
	# beyond the doorway or intersecting the offered-item preview.
	wardrobe_upper_cavity_mask = MeshInstance3D.new()
	wardrobe_upper_cavity_mask.name = "WardrobeUpperCavityMask"
	var mask_mesh := QuadMesh.new()
	mask_mesh.size = Vector2(0.15, 0.055)
	wardrobe_upper_cavity_mask.mesh = mask_mesh
	wardrobe_upper_cavity_mask.position = Vector3(0.0, 0.078, 0.19)
	wardrobe_upper_cavity_mask.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	wardrobe_upper_cavity_mask.material_override = cavity_material
	wardrobe_upper_cavity_mask.visible = false
	wardrobe_visual_root.add_child(wardrobe_upper_cavity_mask)
	# Retain the historical targeting seam while its visual is now a wardrobe.
	hole = wardrobe_cavity

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
	# live every frame made dragging the detailed wardrobe needlessly expensive.
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
	var start := _wardrobe_swallow_anchor()
	var clear_point := _doorway_clear_point(
		start, core.grid.tile_size * 0.56, 0.10
	)
	var node_instance_id := node.get_instance_id()
	node.set_meta(&"worldheart_launching", true)
	node.position = start
	node.scale = Vector3.ONE * 0.04
	_begin_reward_launch(node_instance_id)
	var pulse := _create_reward_tween()
	pulse.tween_interval(WARDROBE_LAUNCH_DELAY)
	pulse.tween_method(
		_animate_doorway_reward.bind(
			node_instance_id, start, clear_point, landing
		),
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


func _animate_doorway_reward(
	progress: float,
	node_instance_id: int,
	start: Vector3,
	clear_point: Vector3,
	landing: Vector3
) -> void:
	var node := instance_from_id(node_instance_id) as Node3D
	if not is_instance_valid(node):
		return
	# Keep the first beat constrained to the wardrobe's forward axis. Only once
	# the miniature has cleared the doors may it curve toward a side reserve slot.
	if progress < 0.42:
		var emerge := progress / 0.42
		node.position = start.lerp(clear_point, emerge)
		node.position.y += sin(emerge * PI) * 0.09
		return
	var arc := (progress - 0.42) / 0.58
	node.position = clear_point.lerp(landing, arc)
	node.position.y += sin(arc * PI) * 0.27


func _finish_pulse_launch(node_instance_id: int, landing: Vector3) -> void:
	var node := instance_from_id(node_instance_id) as Node3D
	if is_instance_valid(node):
		node.position = landing
		node.scale = Vector3.ONE
		node.set_meta(&"worldheart_launching", false)
	_end_reward_launch(node_instance_id)


func _begin_reward_launch(node_instance_id: int) -> void:
	_reward_launch_ids[node_instance_id] = true
	_play_wardrobe_open()


func _end_reward_launch(node_instance_id: int) -> void:
	_reward_launch_ids.erase(node_instance_id)
	if _reward_launch_ids.is_empty():
		_play_wardrobe_close(true)


func _play_portal_flash(strength: float) -> void:
	if wardrobe_motion_root == null:
		return
	var amount := clampf(strength, 0.0, 1.0)
	var kick := _create_tracked_tween()
	kick.tween_property(
		wardrobe_motion_root,
		"scale",
		Vector3(1.0 + amount * 0.06, 1.0 - amount * 0.05, 1.0),
		0.08
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	kick.tween_property(
		wardrobe_motion_root, "scale", Vector3.ONE, 0.16
	).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _play_wardrobe_open() -> void:
	if _wardrobe_is_open or wardrobe_motion_root == null:
		return
	_wardrobe_is_open = true
	_kill_wardrobe_tween()
	wardrobe_motion_root.scale = Vector3.ONE
	wardrobe_motion_root.rotation = Vector3.ZERO
	_wardrobe_tween = create_tween()
	_wardrobe_tween.tween_property(
		wardrobe_motion_root, "scale", Vector3(0.93, 1.07, 0.96), 0.09
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_wardrobe_tween.parallel().tween_property(
		wardrobe_motion_root, "rotation:z", 0.065, 0.09
	)
	_wardrobe_tween.tween_callback(_begin_wardrobe_door_swing)
	_wardrobe_tween.tween_property(
		wardrobe_door_left, "rotation:y", -0.10, 0.28
	).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_wardrobe_tween.parallel().tween_property(
		wardrobe_door_right, "rotation:y", 0.10, 0.28
	).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_wardrobe_tween.parallel().tween_property(
		wardrobe_motion_root, "scale", Vector3(1.08, 0.94, 1.04), 0.20
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_wardrobe_tween.parallel().tween_property(
		wardrobe_motion_root, "rotation:z", -0.055, 0.20
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_wardrobe_tween.parallel().tween_property(
		wardrobe_motion_root, "rotation:y", -0.075, 0.20
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_wardrobe_tween.tween_property(
		wardrobe_door_left, "rotation:y", 0.0, 0.16
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_wardrobe_tween.parallel().tween_property(
		wardrobe_door_right, "rotation:y", 0.0, 0.16
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_wardrobe_tween.tween_property(
		wardrobe_motion_root, "scale", Vector3.ONE, 0.18
	).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_wardrobe_tween.parallel().tween_property(
		wardrobe_motion_root, "rotation", Vector3.ZERO, 0.20
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if audio != null:
		audio.play_event("build_preview", -7.0, 1.12)


func _play_wardrobe_close(swallowed := false) -> void:
	if wardrobe_motion_root == null:
		return
	if not _reward_launch_ids.is_empty():
		return
	if is_instance_valid(_offering_preview) and not _offering_dropping:
		return
	if not _wardrobe_is_open:
		_set_wardrobe_open_visual(false)
		return
	_wardrobe_is_open = false
	_kill_wardrobe_tween()
	wardrobe_shake_root.rotation = Vector3.ZERO
	wardrobe_shake_root.position = Vector3.ZERO
	_wardrobe_tween = create_tween()
	var anticipation := 0.12 if swallowed else 0.08
	_wardrobe_tween.tween_property(
		wardrobe_motion_root,
		"scale",
		Vector3(1.12, 0.88, 1.08) if swallowed else Vector3(1.05, 0.95, 1.03),
		anticipation
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_wardrobe_tween.parallel().tween_property(
		wardrobe_motion_root, "rotation:z", 0.075 if swallowed else 0.035, anticipation
	)
	_wardrobe_tween.tween_property(
		wardrobe_door_left, "rotation:y", LEFT_DOOR_CLOSED_YAW, 0.28
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	_wardrobe_tween.parallel().tween_property(
		wardrobe_door_right, "rotation:y", RIGHT_DOOR_CLOSED_YAW, 0.28
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	_wardrobe_tween.tween_callback(_reveal_wardrobe_closed)
	_wardrobe_tween.tween_property(
		wardrobe_motion_root,
		"scale",
		Vector3(0.88, 1.13, 0.92) if swallowed else Vector3(0.96, 1.04, 0.98),
		0.10
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_wardrobe_tween.parallel().tween_property(
		wardrobe_motion_root, "rotation:z", -0.055 if swallowed else -0.02, 0.10
	)
	_wardrobe_tween.tween_property(
		wardrobe_motion_root, "scale", Vector3.ONE, 0.27 if swallowed else 0.16
	).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_wardrobe_tween.parallel().tween_property(
		wardrobe_motion_root, "rotation", Vector3.ZERO, 0.20
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _begin_wardrobe_door_swing() -> void:
	_set_wardrobe_open_visual(true)
	wardrobe_door_left.rotation.y = LEFT_DOOR_CLOSED_YAW
	wardrobe_door_right.rotation.y = RIGHT_DOOR_CLOSED_YAW
	wardrobe_motion_root.scale = Vector3(0.82, 1.12, 0.88)
	wardrobe_motion_root.rotation = Vector3(0.0, 0.11, -0.085)


func _reveal_wardrobe_closed() -> void:
	_set_wardrobe_open_visual(false)


func _set_wardrobe_open_visual(opened: bool) -> void:
	if wardrobe_closed != null:
		wardrobe_closed.visible = not opened
	if wardrobe_open != null:
		wardrobe_open.visible = opened
	if wardrobe_cavity != null:
		wardrobe_cavity.visible = opened
	if wardrobe_upper_cavity_mask != null:
		wardrobe_upper_cavity_mask.visible = opened


func _kill_wardrobe_tween() -> void:
	if _wardrobe_tween != null and _wardrobe_tween.is_valid():
		_wardrobe_tween.kill()
	_wardrobe_tween = null


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
		# Landing transforms belong to the reward, not to the wardrobe. A moved or
		# rotated wardrobe must never drag already-surfaced loot around the world.
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
	# the cabinet. Rotating the wardrobe rotates this whole local layout.
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


func _facing_forward() -> Vector3:
	# Exact cardinal vectors keep doorway ejection aligned after every quarter
	# turn without accumulating tiny trigonometric drift.
	match posmod(core.diorama.worldheart.worldheart_rotation_quarters, 4):
		1:
			return Vector3.RIGHT
		2:
			return Vector3.FORWARD
		3:
			return Vector3.LEFT
	return Vector3.BACK


func _doorway_clear_point(
	start: Vector3, forward_distance: float, rise: float
) -> Vector3:
	return start + _facing_forward() * forward_distance + Vector3.UP * rise


func _wardrobe_interaction_visual() -> Node3D:
	return (
		wardrobe_open
		if wardrobe_open != null and wardrobe_open.visible
		else wardrobe_closed
	)


func _wardrobe_interaction_anchor() -> Vector3:
	return _centre() + Vector3.UP * 0.58 + _facing_forward() * 0.08


func _wardrobe_swallow_anchor() -> Vector3:
	return _centre() + Vector3.UP * 0.47 + _facing_forward() * 0.08


func _offering_anchor() -> Vector3:
	return _centre() + Vector3.UP * 0.50 + _facing_forward() * 0.285


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
	_exchange_reward_visual.position = _wardrobe_swallow_anchor()
	_exchange_reward_visual.scale = Vector3.ONE * 0.04
	add_child(_exchange_reward_visual)
	var reward_visual := _exchange_reward_visual
	var reward_visual_instance_id := reward_visual.get_instance_id()
	_begin_reward_launch(reward_visual_instance_id)
	var start := _wardrobe_swallow_anchor()
	var clear_point := _doorway_clear_point(start, 0.54, 0.10)
	var finish := _doorway_clear_point(start, 0.92, 0.13)
	var launch := _create_reward_tween()
	launch.tween_interval(WARDROBE_LAUNCH_DELAY)
	launch.tween_method(
		_animate_exchange_reward.bind(
			reward_visual_instance_id, start, clear_point, finish
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
	clear_point: Vector3,
	finish: Vector3
) -> void:
	var reward_visual := instance_from_id(reward_visual_instance_id) as Node3D
	if not is_instance_valid(reward_visual):
		return
	if value < 0.40:
		var emerge := value / 0.40
		reward_visual.position = start.lerp(clear_point, emerge)
		reward_visual.position.y += sin(emerge * PI) * 0.08
		return
	var arc := (value - 0.40) / 0.60
	reward_visual.position = clear_point.lerp(finish, arc)
	reward_visual.position.y += sin(arc * PI) * 0.24


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
	_sync_wardrobe_rotation(true)
	_sync_entries()
	if is_instance_valid(_offering_preview) and not _offering_dropping:
		_offering_preview.position = _offering_anchor()


func _sync_wardrobe_rotation(animated: bool) -> void:
	if vortex_pivot == null:
		return
	if _wardrobe_rotation_tween != null and _wardrobe_rotation_tween.is_valid():
		_wardrobe_rotation_tween.kill()
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
	_wardrobe_rotation_tween = create_tween()
	_wardrobe_rotation_tween.tween_property(
		vortex_pivot, "rotation:y", resolved_target, 0.34
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_wardrobe_rotation_tween.parallel().tween_property(
		wardrobe_motion_root, "scale", Vector3(0.94, 1.06, 0.94), 0.12
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_wardrobe_rotation_tween.tween_property(
		wardrobe_motion_root, "scale", Vector3.ONE, 0.20
	).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _style_wardrobe_meshes(root: Node3D) -> void:
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
			_wardrobe_tween, _meter_tween, _wardrobe_rotation_tween
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
	for model: Node3D in [wardrobe_closed, wardrobe_open]:
		if model == null:
			continue
		var meshes: Array[MeshInstance3D] = []
		if model is MeshInstance3D:
			meshes.append(model as MeshInstance3D)
		for candidate in model.find_children(
			"*", "MeshInstance3D", true, false
		):
			meshes.append(candidate as MeshInstance3D)
		for mesh: MeshInstance3D in meshes:
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
	_kill_wardrobe_tween()
	if (
		_wardrobe_rotation_tween != null
		and _wardrobe_rotation_tween.is_valid()
	):
		_wardrobe_rotation_tween.kill()
	_wardrobe_rotation_tween = null
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
