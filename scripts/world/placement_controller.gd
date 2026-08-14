class_name PlacementController
extends Node3D
## Build mode: ghost previews, grid snapping, rotation, move-with-cancel,
## undo/redo, and every placement safety rule (adjacency, overlap, world
## occupancy, support, and player standing-cell relocation). The grid snaps pieces;
## the player character never snaps.

signal mode_changed(active: bool)
signal held_changed(held: Dictionary)
signal action_result(ok: bool, message: String, kind: String)
signal hover_changed(display_name: String, collection_name: String)
signal tile_splashed(impact_position: Vector3, landing_position: Vector3)

const POINTER_DRAG_DISTANCE := 8.0
const ACTIONABLE_PICKUP_HOLD_SECONDS := 0.32

const StructureVisualFactoryScript := preload(
	"res://scripts/world/structure_visual_factory.gd"
)
const PlacementHistoryScript := preload(
	"res://scripts/world/placement/placement_history.gd"
)
const PlacementRulesScript := preload(
	"res://scripts/world/placement/placement_rules.gd"
)
const PlacementTargetResolverScript := preload(
	"res://scripts/world/placement/placement_target_resolver.gd"
)
const PlacementPreviewScript := preload(
	"res://scripts/world/placement/placement_preview.gd"
)

var core: GameCore
var assets: AssetLibrary
var camera_rig: CameraRig
var player: PlayerController
var effects: EffectsManager
var world_renderer: WorldRenderer
var _tile_visual_factory: TileVisualFactory
var _structure_visual_factory: RefCounted
var _history
var _rules
var _target_resolver
var _preview

var active := false
var held: Dictionary = {}      # {kind: tile|structure|deed, id, rotation, moving: {...}|null}
var _ghost: Node3D
var _hover_cell := Vector2i(9999, 9999)
var _hover_elevation := 0
var _hover_valid := false
var _hover_support_instance_id := 0
var _hover_support_slot := ""
var _pointer_down := false
var _pointer_dragging := false
var _pointer_press_position := Vector2.ZERO
var _pointer_screen_position := Vector2.ZERO
var _picked_on_pointer_press := false
var _deferred_pickup_hit: Dictionary = {}
var _deferred_pickup_requires_hold := false
var _deferred_pickup_attempted := false
var _pointer_hold_elapsed := 0.0
## A mouse drag may temporarily borrow build preview/validation while the game
## stays in interaction mode. Keeping this separate from `active` prevents a
## mid-gesture camera reframe and leaves explicit controller Build mode intact.
var _transient_pointer_edit := false
var _hover_info_signature := ""
var _animate_ghost_rotation := false
var _controller_mode := false
var _controller_cursor_active := false
var _interaction_cursor_mode := false
var _controller_cell := Vector2i.ZERO
var _ui_pointer_blocker := Callable()
var _interaction_hover_providers: Array[Object] = []
var _external_offer_preview := false
var _water_skip_cache_key := ""
var _water_skip_cache_target: Dictionary = {}
var _water_skip_preview_target: Dictionary = {}
var _pending_water_skip: Dictionary = {}

func setup(
	game_core: GameCore,
	asset_library: AssetLibrary,
	rig: CameraRig,
	player_controller: PlayerController,
	effects_manager: EffectsManager,
	renderer: WorldRenderer
) -> void:
	core = game_core
	assets = asset_library
	camera_rig = rig
	player = player_controller
	effects = effects_manager
	world_renderer = renderer
	_tile_visual_factory = TileVisualFactory.new(assets, core.grid)
	_structure_visual_factory = StructureVisualFactoryScript.new(assets, core.grid)
	_history = PlacementHistoryScript.new()
	_rules = PlacementRulesScript.new(core, player)
	_target_resolver = PlacementTargetResolverScript.new(core.grid, world_renderer)
	_preview = PlacementPreviewScript.new(self, core.grid.tile_size)
	core.before_save.connect(prepare_for_save)
	held_changed.connect(func(value: Dictionary):
		_invalidate_water_skip_cache()
		if _controller_mode and value.is_empty():
			_controller_cursor_active = false
	)
	core.grid.grid_changed.connect(_invalidate_water_skip_cache)


func set_ui_pointer_blocker(blocker: Callable) -> void:
	_ui_pointer_blocker = blocker


## World interaction props live outside the placeable grid, but share its
## exact silhouette hover language. The provider exposes event_at_screen/cell
## without coupling the placement system to visitors or any future feature.
func set_interaction_hover_provider(provider: Object) -> void:
	_interaction_hover_providers.clear()
	add_interaction_hover_provider(provider)


func add_interaction_hover_provider(provider: Object) -> void:
	if provider != null and not _interaction_hover_providers.has(provider):
		_interaction_hover_providers.append(provider)


## The Worldheart owns a miniature loot-style preview while a held piece is
## over its mouth. Suppress the normal full-size placement ghost for that beat.
func set_external_offer_preview(enabled: bool) -> void:
	_external_offer_preview = enabled
	if _ghost != null and enabled:
		_ghost.visible = false


func external_offer_preview_origin() -> Vector3:
	if is_instance_valid(_ghost):
		return _ghost.global_position
	return _held_landing_world()


# ------------------------------------------------------------------ mode

func toggle() -> void:
	set_active(not active)


func set_active(enabled: bool) -> void:
	if active == enabled:
		return
	_transient_pointer_edit = false
	active = enabled
	_interaction_cursor_mode = false
	if active and _controller_mode:
		_controller_cell = player.current_cell()
		_controller_cursor_active = not held.is_empty()
	if not active:
		_controller_cursor_active = false
		world_renderer.clear_structure_hover()
		_emit_hover_info("", "", "")
		_cancel_held(true)
		if _controller_mode:
			begin_controller_interaction_browse()
	camera_rig.set_build_mode(active)
	# Worldheart has no playable keeper. Its hidden legacy player is retained as
	# a fixed camera/grid anchor only, and must never be re-enabled when the Build
	# Bag changes placement mode.
	player.set_state(
		PlayerController.State.DISABLED
		if core.diorama.enabled
		else PlayerController.State.BUILDING if active else PlayerController.State.FREE
	)
	mode_changed.emit(active)


## HUD hands over a piece from stock (or a packed deed).
func hold_new(kind: String, id: String, arrival := "") -> void:
	if not active:
		set_active(true)
	_cancel_held(true)
	held = {
		"kind": kind,
		"id": id,
		"rotation": 0,
		"moving": null,
		"arrival": arrival,
	}
	if _controller_mode:
		_controller_cursor_active = true
	_build_ghost()
	held_changed.emit(held)


## Discovery Tray offers do not enter Stock before ownership. The stable offer
## receipt stays attached to the cursor until first placement or cancellation.
func hold_diorama_offer(offer: Dictionary) -> void:
	var offer_id := String(offer.get("offer_id", ""))
	var kind := String(offer.get("kind", ""))
	var content_id := String(offer.get("id", ""))
	if (
		offer_id == ""
		or not core.can_commit_diorama_offer(offer_id, kind, content_id)
	):
		return
	if not active:
		set_active(true)
	_cancel_held(true)
	held = {
		"kind": kind,
		"id": content_id,
		"rotation": 0,
		"moving": null,
		"arrival": "discovery_tray",
		"offer_id": offer_id,
		"tray_slot": int(offer.get("slot", -1)),
	}
	if _controller_mode:
		_controller_cursor_active = true
	_build_ghost()
	held_changed.emit(held)


## A chosen wish belongs to the world immediately: pick a valid, visible spot
## near the current camera focus and commit the single stock copy there. The
## caller never enters a cursor-placement step. Returns false only when the
## current world has no legal landing spot; in that case the copy remains safe
## in the Build Bag.
func drop_wish(kind: String, id: String) -> bool:
	var was_active := active
	hold_new(kind, id, "wish")
	var placed := false
	for candidate: Dictionary in _wish_landing_candidates(kind):
		if try_place_at(candidate["coord"]):
			placed = true
			break
	if not placed:
		_cancel_held(true)
	if not was_active:
		set_active(false)
	return placed


func _wish_landing_candidates(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	var focus := camera_rig.focus_world_position()
	if kind == "tile":
		# New tiles prefer the visible shoreline, so each wish can gently grow
		# the island. Existing columns remain a legal stacking fallback.
		for base_coord: Vector2i in core.grid.cells:
			for direction: Vector2i in WorldGrid.NEIGHBORS:
				var frontier := base_coord + direction
				if core.grid.has_cell(frontier) or seen.has(frontier):
					continue
				seen[frontier] = true
				result.append(_wish_candidate(frontier, 0, 0, focus))
		for stack_coord: Vector2i in core.grid.cells:
			result.append(_wish_candidate(
				stack_coord,
				core.grid.top_elevation(stack_coord) + 1,
				1,
				focus
			))
	else:
		# Models first seek uncluttered top surfaces. Placement validation still
		# owns every support, collision, landmark, and walkability rule.
		for model_coord: Vector2i in core.grid.cells:
			var elevation := core.grid.top_elevation(model_coord)
			var state := core.grid.cell_at(model_coord, elevation)
			var clutter_priority := 0
			if state == null or not state.structures.is_empty() or state.landmark_id != "":
				clutter_priority = 1
			result.append(_wish_candidate(
				model_coord,
				elevation,
				clutter_priority,
				focus
			))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) < float(b["score"])
	)
	return result


func _wish_candidate(
	coord: Vector2i,
	elevation: int,
	placement_priority: int,
	focus: Vector3
) -> Dictionary:
	var world_position := core.grid.cell_to_world(coord, maxi(0, elevation))
	var distance := Vector2(
		world_position.x - focus.x,
		world_position.z - focus.z
	).length()
	var visibility_priority := 0 if _wish_landing_is_visible(world_position) else 1
	var jitter := core.rng.randf_range(
		"wish_landing",
		0.0,
		core.grid.tile_size * 2.25
	)
	return {
		"coord": coord,
		"score": visibility_priority * 100000.0
			+ placement_priority * 10000.0
			+ distance
			+ jitter,
	}


func _wish_landing_is_visible(world_position: Vector3) -> bool:
	if camera_rig == null or camera_rig.camera == null:
		return true
	var active_camera := camera_rig.camera
	if active_camera.is_position_behind(world_position):
		return false
	var screen_position := active_camera.unproject_position(world_position)
	var view_size := get_viewport().get_visible_rect().size
	var margin := minf(96.0, minf(view_size.x, view_size.y) * 0.12)
	return (
		screen_position.x >= margin
		and screen_position.y >= margin
		and screen_position.x <= view_size.x - margin
		and screen_position.y <= view_size.y - margin
	)


## Controller placement is an explicit grid cursor, not a simulated mouse.
## That keeps selection deterministic at any resolution and leaves the OS
## pointer untouched when switching devices.
func set_controller_mode(enabled: bool) -> void:
	if _controller_mode == enabled:
		return
	_controller_mode = enabled
	world_renderer.clear_structure_hover()
	_emit_hover_info("", "", "")
	if not enabled:
		_interaction_cursor_mode = false
		_controller_cursor_active = false
		return
	_controller_cell = player.current_cell()
	if active:
		_controller_cursor_active = not held.is_empty()
	else:
		begin_controller_interaction_browse()


func begin_controller_interaction_browse() -> void:
	if active or not _controller_mode:
		return
	_interaction_cursor_mode = true
	_controller_cursor_active = true
	if not core.grid.has_cell(_controller_cell):
		_controller_cell = core.grid.home_cell


func end_controller_interaction_browse() -> void:
	_interaction_cursor_mode = false
	if not active:
		_controller_cursor_active = false
		_preview.hide_indicator()
		world_renderer.clear_structure_hover()
		_emit_hover_info("", "", "")


func interaction_cursor_active() -> bool:
	return not active and _interaction_cursor_mode and controller_cursor_active()


func begin_controller_browse() -> void:
	if not active or not _controller_mode:
		return
	_controller_cursor_active = true
	if not core.grid.has_cell(_controller_cell):
		_controller_cell = player.current_cell()


func show_controller_library() -> void:
	if not active or not _controller_mode or not held.is_empty():
		return
	_controller_cursor_active = false
	world_renderer.clear_structure_hover()
	_emit_hover_info("", "", "")


func controller_cursor_active() -> bool:
	return _controller_mode and _controller_cursor_active


func controller_mode() -> bool:
	return _controller_mode


func controller_cursor_cell() -> Vector2i:
	return _controller_cell


func controller_target_instance_id() -> int:
	if not controller_cursor_active():
		return 0
	var elevation := core.grid.top_elevation(_controller_cell)
	return (
		_highest_structure_instance_at(_controller_cell, elevation)
		if elevation >= 0 else 0
	)


func pick_up_under_pointer() -> void:
	if active and held.is_empty():
		_try_pick_up()


## Resolves the keeper-dock drag against the same authored tile/structure
## colliders used by build selection. Returning an empty dictionary keeps the
## UI preview and the authoritative drop decision on one validity contract.
func player_drop_target(screen_position: Vector2) -> Dictionary:
	var hit := world_renderer.pick_placeable_at_screen(
		camera_rig.camera,
		screen_position
	)
	if hit.is_empty():
		return {}
	var coord: Vector2i = hit.get("coord", Vector2i(9999, 9999))
	var elevation := int(hit.get("elevation", core.grid.top_elevation(coord)))
	if hit.get("kind", "") == "structure":
		var found := core.grid.find_structure(int(hit.get("instance_id", 0)))
		if found.is_empty():
			return {}
		var structure := found.get("structure") as WorldGrid.StructureState
		var definition := (
			core.registries.structure(structure.structure_id)
			if structure != null else null
		)
		if definition == null or definition.collision_profile != "walkable_surface":
			return {}
	return player_drop_target_at_cell(
		coord,
		elevation,
		hit.get("point", null)
	)


## Testable cell form of player_drop_target(). It deliberately rejects water,
## landmarks, and blocking center props while accepting authored walkable
## structure surfaces such as docks.
func player_drop_target_at_cell(
	coord: Vector2i,
	elevation := -1,
	surface_point: Variant = null
) -> Dictionary:
	var top := core.grid.top_elevation(coord)
	if top < 0:
		return {}
	var target_elevation := top if elevation < 0 else elevation
	if target_elevation != top:
		return {}
	var state := core.grid.cell_at(coord, target_elevation)
	var tile_definition := core.grid.tile_def_at(coord, target_elevation)
	if state == null or tile_definition == null or state.landmark_id != "":
		return {}
	var walkable := tile_definition.walkable
	if target_elevation == 0 and core.grid.has_walkable_structure_surface(coord):
		walkable = true
	if not walkable:
		return {}
	for structure: WorldGrid.StructureState in state.structures:
		if structure.parent_instance_id != 0:
			continue
		var definition := core.registries.structure(structure.structure_id)
		if definition != null and definition.blocks_movement:
			return {}
	var center := core.grid.cell_to_world(coord, target_elevation)
	var target := center
	if surface_point is Vector3:
		var point := surface_point as Vector3
		var inset := core.grid.tile_size * 0.28
		target.x = clampf(point.x, center.x - inset, center.x + inset)
		target.z = clampf(point.z, center.z - inset, center.z + inset)
		target.y = maxf(center.y, point.y)
	return {
		"coord": coord,
		"elevation": target_elevation,
		"position": target + Vector3.UP * 0.025,
	}


func move_controller_cursor(screen_direction: Vector2i) -> void:
	if (not active and not _interaction_cursor_mode) or not controller_cursor_active():
		return
	var quarter_turn := posmod(
		roundi((camera_rig.rotation_degrees.y - 45.0) / 90.0),
		4
	)
	var grid_direction := controller_grid_direction(
		screen_direction,
		quarter_turn
	)
	_controller_cell += grid_direction


static func controller_grid_direction(
	screen_direction: Vector2i,
	quarter_turn: int
) -> Vector2i:
	var grid_direction := screen_direction
	for _turn in posmod(quarter_turn, 4):
		grid_direction = Vector2i(grid_direction.y, -grid_direction.x)
	return grid_direction


func rotate_held() -> void:
	if held.is_empty():
		return
	held["rotation"] = (int(held["rotation"]) + 1) % 4
	_animate_ghost_rotation = true
	action_result.emit(true, "", "rotate")


func rotate_at_screen(screen_position: Vector2) -> bool:
	# World editing is permanently available. `active` now describes transient
	# Build Bag/controller focus, not whether a hovered world piece may rotate.
	if _pointer_is_over_ui(screen_position):
		return false
	if not held.is_empty():
		rotate_held()
		return true
	var hit := world_renderer.pick_placeable_at_screen(
		camera_rig.camera,
		screen_position
	)
	if hit.is_empty():
		return false
	world_renderer.clear_structure_hover()
	match String(hit.get("kind", "")):
		"structure":
			var instance_id := int(hit.get("instance_id", 0))
			var found := core.grid.find_structure(instance_id)
			if found.is_empty():
				return false
			var structure: WorldGrid.StructureState = found["structure"]
			var from_rotation := structure.rotation
			var to_rotation := posmod(from_rotation + 1, 4)
			world_renderer.prepare_rotation_refresh(
				found["coord"], int(found["elevation"])
			)
			if not core.grid.set_structure_rotation(instance_id, to_rotation):
				world_renderer.cancel_rotation_refresh(
					found["coord"], int(found["elevation"])
				)
				return false
			world_renderer.animate_structure_rotation(instance_id, 1)
			_push_undo({
				"type": "rotate_structure",
				"iid": instance_id,
				"from_rotation": from_rotation,
				"to_rotation": to_rotation,
			})
		"tile":
			var coord: Vector2i = hit["coord"]
			var elevation := int(hit.get("elevation", 0))
			var state := core.grid.cell_at(coord, elevation)
			if state == null:
				return false
			var from_rotation := state.rotation
			var to_rotation := posmod(from_rotation + 1, 4)
			world_renderer.prepare_tile_stack_rotation(coord, elevation)
			if not core.grid.rotate_tile_stack_at(coord, elevation, 1):
				world_renderer.cancel_tile_stack_rotation(coord, elevation)
				return false
			world_renderer.animate_tile_stack_rotation(coord, elevation, 1)
			_push_undo({
				"type": "rotate_tile_stack",
				"coord": coord,
				"elevation": elevation,
				"from_rotation": from_rotation,
				"to_rotation": to_rotation,
			})
		_:
			return false
	core.autosave_soon()
	action_result.emit(true, "", "rotate")
	return true


func _pointer_is_over_ui(screen_position: Vector2) -> bool:
	# Main provides a geometry-based HUD query for the event's exact position.
	# Do not then consult gui_get_hovered_control(): that value can lag behind a
	# fast move out of the Build Bag and used to reject valid world drags.
	if _ui_pointer_blocker.is_valid():
		return bool(_ui_pointer_blocker.call(screen_position))
	return get_viewport().gui_get_hovered_control() != null


func _build_ghost() -> void:
	_animate_ghost_rotation = false
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	if held.is_empty():
		return
	if (
		held.get("kind", "") == "tile"
		and held.get("moving") != null
		and held["moving"].has("stack")
	):
		var moving_tile: Dictionary = held["moving"]
		_build_tile_stack_ghost(
			moving_tile["stack"],
			moving_tile.get("coord", Vector2i.ZERO),
			int(moving_tile.get("elevation", 0))
		)
		add_child(_ghost)
		_initialize_ghost_yaw()
		_preview.prepare_held_visual(_ghost)
		_ghost.visible = false
		return
	var asset_id := ""
	match held["kind"]:
		"tile":
			var tile_def := core.registries.tile(held["id"])
			if tile_def == null:
				action_result.emit(false, "That tile is no longer available.", "invalid")
				return
			_ghost = _tile_visual_factory.instantiate_visual(tile_def, true)
		"structure":
			var structure_def := core.registries.structure(held["id"])
			if structure_def == null:
				action_result.emit(false, "That decoration is no longer available.", "invalid")
				return
			var moving_structure: Variant = held.get("moving")
			var source: WorldGrid.StructureState = null
			if moving_structure is Dictionary and moving_structure.has("stack"):
				var source_stack: Array = moving_structure["stack"]
				if not source_stack.is_empty():
					source = source_stack[0]
			_ghost = _instantiate_structure_ghost(structure_def, source)
		"deed":
			var landmark_def := core.registries.landmark(held["id"])
			if landmark_def == null:
				action_result.emit(false, "That landmark is no longer available.", "invalid")
				return
			asset_id = landmark_def.asset_id
	if _ghost == null:
		_ghost = assets.instantiate(asset_id)
	if (
		held.get("kind", "") == "structure"
		and held.get("moving") != null
		and held["moving"].has("stack")
	):
		_add_stack_descendants_to_ghost(held["moving"]["stack"])
	add_child(_ghost)
	_initialize_ghost_yaw()
	_preview.prepare_held_visual(_ghost)
	# The first preview frame resolves the real cursor target before revealing
	# the model, preventing a newly held piece from flying in from world origin.
	_ghost.visible = false


func _initialize_ghost_yaw() -> void:
	if _ghost == null:
		return
	var yaw := int(held.get("rotation", 0)) * PI * 0.5
	if held.get("kind", "") == "structure" and held.get("moving") is Dictionary:
		var origin: Dictionary = held["moving"].get("origin", {})
		var parent_instance_id := int(origin.get("parent", 0))
		if parent_instance_id > 0:
			yaw += core.grid.structure_local_transform(
				parent_instance_id
			).basis.get_euler().y
	_ghost.rotation.y = yaw


func _instantiate_structure_ghost(
	definition: Defs.StructureDefinition,
	source: WorldGrid.StructureState = null
) -> Node3D:
	var harvest_state: Dictionary = (
		source.runtime_state.get("harvest", {})
		if source != null else {}
	)
	var visual_seed := int(harvest_state.get(
		"visual_seed",
		source.instance_id if source != null else 0
	))
	var visual: Node3D = _structure_visual_factory.instantiate_visual(
		definition,
		true,
		visual_seed
	)
	if source != null:
		_structure_visual_factory.sync_harvest_visual(
			visual,
			definition,
			String(harvest_state.get("state", "maturing")),
			false
		)
	return visual


func _build_tile_stack_ghost(
	stack: Array,
	source_coord: Vector2i,
	source_elevation: int
) -> void:
	_ghost = Node3D.new()
	_ghost.name = "TileStackGhost"
	if stack.is_empty():
		return
	var base_state: WorldGrid.CellState = stack[0]["state"]
	var base_angle := base_state.rotation * PI * 0.5
	var inverse_base := Transform3D(Basis(Vector3.UP, -base_angle), Vector3.ZERO)
	for entry: Dictionary in stack:
		var relative := int(entry["relative_elevation"])
		var state: WorldGrid.CellState = entry["state"]
		var definition := core.registries.tile(state.tile_id)
		if definition == null:
			continue
		var source_level := source_elevation + relative
		var detail_variant := TileVisualFactory.detail_variant_for_coord(
			definition,
			source_coord,
			source_level
		)
		# A held stack floats free of the grid, so it must use the
		# self-contained topology (mask 0). Sampling the source neighbours here
		# instantiated an edge variant whose rim walls were consumed by tiles it
		# no longer touches, leaving the cap hovering above the body while the
		# piece was carried.
		var tile_visual := _tile_visual_factory.instantiate_visual(
			definition,
			true,
			0,
			detail_variant
		)
		tile_visual.name = "ghost_tile_e%d" % relative
		tile_visual.set_meta("ghost_relative_elevation", relative)
		# Detached stack entries no longer exist at their source coordinate, so
		# cell_to_world() cannot infer a fractional cap's lowered seating plane.
		# Keep every child relative to the base tile's own prospective holder.
		tile_visual.position.y = core.grid.tile_stack_local_y(
			base_state.tile_id,
			state.tile_id,
			relative
		)
		tile_visual.rotation.y = (state.rotation - base_state.rotation) * PI * 0.5
		_tile_visual_factory.set_surface_covered(
			tile_visual,
			relative < int(stack.back()["relative_elevation"])
		)
		_tile_visual_factory.set_stack_seam_visible(tile_visual, relative > 0)
		_ghost.add_child(tile_visual)
		for structure: WorldGrid.StructureState in state.structures:
			var structure_def := core.registries.structure(structure.structure_id)
			if structure_def == null:
				continue
			var structure_visual: Node3D = _instantiate_structure_ghost(
				structure_def,
				structure
			)
			structure_visual.name = "ghost_structure_%d" % structure.instance_id
			var elevation_transform := Transform3D(
				Basis.IDENTITY,
				Vector3(0, relative * core.grid.block_depth, 0)
			)
			structure_visual.transform = (
				elevation_transform
				* inverse_base
				* core.grid.structure_local_transform_in_cell(
					state,
					structure.instance_id
				)
			)
			_ghost.add_child(structure_visual)


func _add_stack_descendants_to_ghost(stack: Array[WorldGrid.StructureState]) -> void:
	if _ghost == null or stack.size() <= 1:
		return
	var root: WorldGrid.StructureState = stack[0]
	var by_id := {}
	for structure: WorldGrid.StructureState in stack:
		by_id[structure.instance_id] = structure
	for structure: WorldGrid.StructureState in stack:
		if structure.instance_id == root.instance_id:
			continue
		var definition := core.registries.structure(structure.structure_id)
		if definition == null:
			continue
		var child_visual: Node3D = _instantiate_structure_ghost(
			definition,
			structure
		)
		child_visual.name = "ghost_descendant_%d" % structure.instance_id
		child_visual.transform = _stack_relative_transform(
			structure.instance_id,
			root.instance_id,
			by_id,
			{}
		)
		_ghost.add_child(child_visual)


func _stack_relative_transform(
	instance_id: int,
	root_instance_id: int,
	by_id: Dictionary,
	visiting: Dictionary
) -> Transform3D:
	if instance_id == root_instance_id:
		return Transform3D.IDENTITY
	if not by_id.has(instance_id) or visiting.has(instance_id):
		return Transform3D.IDENTITY
	visiting[instance_id] = true
	var structure: WorldGrid.StructureState = by_id[instance_id]
	if not by_id.has(structure.parent_instance_id):
		visiting.erase(instance_id)
		return Transform3D.IDENTITY
	var parent: WorldGrid.StructureState = by_id[structure.parent_instance_id]
	var parent_def := core.registries.structure(parent.structure_id)
	var slot := (
		parent_def.support_slot(structure.support_slot_id)
		if parent_def != null
		else null
	)
	if slot == null:
		visiting.erase(instance_id)
		return Transform3D.IDENTITY
	var parent_transform := _stack_relative_transform(
		parent.instance_id,
		root_instance_id,
		by_id,
		visiting
	)
	visiting.erase(instance_id)
	return parent_transform * Transform3D(
		Basis(Vector3.UP, structure.rotation * PI * 0.5),
		core.grid.model_space_offset(slot.offset)
	)


# ------------------------------------------------------------------ per-frame preview

func _process(delta: float) -> void:
	_tick_actionable_pickup_hold(delta)
	if not active and not _transient_pointer_edit:
		if _ghost != null:
			_ghost.visible = false
		if interaction_cursor_active():
			var elevation := core.grid.top_elevation(_controller_cell)
			var indicator_elevation := maxi(0, elevation)
			_preview.sync_indicator(
				core.grid.cell_to_world(_controller_cell, indicator_elevation),
				false,
				elevation >= 0
			)
			_update_controller_placeable_hover()
		else:
			_preview.hide_indicator()
			if _controller_mode:
				_emit_hover_info("", "", "")
			else:
				_update_placeable_hover()
		return
	if held.is_empty():
		_external_offer_preview = false
		_preview.hide_indicator()
		if _ghost != null:
			_ghost.visible = false
		if _controller_mode:
			if _controller_cursor_active:
				_update_controller_placeable_hover()
			else:
				world_renderer.clear_structure_hover()
				_emit_hover_info("", "", "")
		else:
			_update_placeable_hover()
		return
	if _external_offer_preview:
		world_renderer.clear_structure_hover()
		_emit_hover_info("", "", "")
		_preview.hide_indicator()
		if _ghost != null:
			_ghost.visible = false
		# While the offer preview owns the held piece it is an offering, never a
		# placement, so the action must be disarmed -- leaving a stale true here
		# is how a tile ended up stacked on top of the well.
		_hover_valid = false
		_water_skip_preview_target = {}
		# The hover target must stay live even so. Main asks hover_cell()
		# whether the pointer is still on the Worldheart, and returning without
		# updating it froze the answer at the well's cell: the offer then never
		# released and every tile placed afterwards went into the well.
		_update_hover_target()
		return
	world_renderer.clear_structure_hover()
	_emit_hover_info("", "", "")
	_update_hover_target()
	# The Worldheart's own cell is never a placement target -- it is an offer
	# target -- so the ghost yields to the offering preview instead of turning
	# red. Without this, approaching the well flashed the invalid state for
	# every frame between entering its tile and satisfying the tighter
	# screen-radius test that starts the offer, which read as a bug.
	if (
		core.diorama.enabled
		and _hover_cell == core.diorama.worldheart.worldheart_cell
	):
		# Hiding the ghost must NOT skip validation. Leaving _hover_valid at
		# whatever the last cell set made the click path read a stale true and
		# place the tile onto the Worldheart's cell -- a tile stacked on top of
		# the well, which no model may ever do.
		_hover_valid = false
		# Same reasoning for the water-skip target: _placement_action_valid
		# accepts a stale one as permission to act.
		_water_skip_preview_target = {}
		_preview.hide_indicator()
		if _ghost != null:
			_ghost.visible = false
		return
	_hover_valid = _validate(_hover_cell, _hover_elevation)
	_water_skip_preview_target = (
		{}
		if _hover_valid
		else water_skip_target_for(_hover_cell)
	)
	var world := _held_landing_world()
	var landing_position := _resolved_landing_position(world)
	if _ghost != null:
		var was_visible := _ghost.visible
		_ghost.visible = true
		var target_position: Vector3 = _preview.lifted_position(
			landing_position
		)
		if was_visible:
			_ghost.position = _ghost.position.lerp(target_position, 1.0 - exp(-delta * 20.0))
		else:
			_ghost.position = target_position
		var target_yaw := int(held["rotation"]) * PI * 0.5
		if _hover_support_instance_id > 0 and _hover_support_slot != "":
			target_yaw += world_renderer.support_slot_world_transform(
				_hover_support_instance_id,
				_hover_support_slot
			).basis.get_euler().y
		_sync_ghost_yaw(target_yaw, delta, was_visible)
		_sync_ghost_stack_seams()
		_sync_ghost_water_topology()
		_preview.set_validity(_ghost, _placement_action_valid())
		var glow_position := landing_position
		glow_position.x = _ghost.position.x
		glow_position.z = _ghost.position.z
		_sync_indicator_preview(glow_position)
	else:
		_sync_indicator_preview(landing_position)


func _held_landing_world() -> Vector3:
	if not _water_skip_preview_target.is_empty():
		return _water_skip_impact_position(_hover_cell)
	if held.get("kind", "") == "tile":
		return core.grid.cell_to_world_for_tile(
			_hover_cell,
			_hover_elevation,
			String(held.get("id", ""))
		)
	return core.grid.cell_to_world(_hover_cell, _hover_elevation)


func _resolved_landing_position(world: Vector3) -> Vector3:
	var landing_position := world
	match held.get("kind", ""):
		"tile":
			# Tiles may never be supported by objects, but an invalid preview
			# should still sit visibly above the obstruction instead of slicing
			# through it and hiding the reason placement failed.
			var support_elevation := core.grid.top_elevation(_hover_cell)
			var obstruction_id := _highest_structure_instance_at(
				_hover_cell,
				support_elevation
			)
			if obstruction_id > 0:
				landing_position.y = maxf(
					landing_position.y,
					world_renderer.structure_preview_position(obstruction_id).y
				)
		"structure":
			if _hover_support_instance_id > 0:
				if _hover_support_slot != "":
					landing_position = (
						world_renderer.support_slot_world_transform(
							_hover_support_instance_id,
							_hover_support_slot
						).origin
					)
				else:
					landing_position = world_renderer.structure_preview_position(
						_hover_support_instance_id
					)
			else:
				var socket := _target_socket(_hover_cell, _hover_elevation)
				if socket >= 0:
					var tile_definition := core.grid.tile_def_at(
						_hover_cell,
						_hover_elevation
					)
					if tile_definition != null:
						landing_position.y += maxf(
							0.0,
							tile_definition.walk_surface_height
						)
					landing_position += core.grid.socket_offset(socket)
	return landing_position


## A newly built pickup ghost has the factory's identity rotation for one frame.
## Interpolating from that value made rotated objects visibly whip around on
## selection. The first visible frame must inherit its resolved target rotation
## exactly. Cursor/support resolution changes also snap because they are not a
## rotation command. Only an explicit R press gets a short, rate-limited turn.
func _sync_ghost_yaw(target_yaw: float, delta: float, was_visible: bool) -> void:
	if _ghost == null:
		return
	if not was_visible or not _animate_ghost_rotation:
		_ghost.rotation.y = target_yaw
		return
	_ghost.rotation.y = rotate_toward(
		_ghost.rotation.y,
		target_yaw,
		TAU * 1.6 * delta
	)
	if absf(angle_difference(_ghost.rotation.y, target_yaw)) < 0.002:
		_ghost.rotation.y = target_yaw
		_animate_ghost_rotation = false


func _sync_ghost_stack_seams() -> void:
	if _ghost == null or held.get("kind", "") != "tile":
		return
	var found_stack_children := false
	for child_variant in _ghost.get_children():
		var child := child_variant as Node3D
		if child == null or not child.has_meta("ghost_relative_elevation"):
			continue
		found_stack_children = true
		var relative := int(child.get_meta("ghost_relative_elevation"))
		_tile_visual_factory.set_stack_seam_visible(
			child,
			_hover_elevation + relative > 0
		)
	if not found_stack_children:
		_tile_visual_factory.set_stack_seam_visible(
			_ghost,
			_hover_elevation > 0
		)


func _sync_ghost_water_topology() -> void:
	if (
		_ghost == null
		or held.get("kind", "") != "tile"
		or held.get("id", "") == ""
	):
		return
	var def := core.registries.tile(String(held["id"]))
	if def == null or def.render_profile != "continuous_water":
		return
	var connected: Array[Vector2i] = []
	var visited := {}
	var pending: Array[Vector2i] = []
	for direction: Vector2i in WorldGrid.NEIGHBORS:
		var neighbor := _hover_cell + direction
		if _is_water_cell(neighbor):
			pending.append(neighbor)
	while not pending.is_empty():
		var coord: Vector2i = pending.pop_back()
		if visited.has(coord):
			continue
		visited[coord] = true
		connected.append(coord - _hover_cell)
		for direction: Vector2i in WorldGrid.NEIGHBORS:
			var neighbor := coord + direction
			if not visited.has(neighbor) and _is_water_cell(neighbor):
				pending.append(neighbor)
	_tile_visual_factory.sync_preview_water_topology(_ghost, connected)


func _is_water_cell(coord: Vector2i) -> bool:
	if not core.grid.has_cell(coord):
		return false
	var def := core.grid.tile_def(coord)
	return def != null and def.render_profile == "continuous_water"


## Validity styling belongs to the model and remains readable throughout tall
## stacks; the legacy ground-plane compatibility node stays hidden.
func _sync_indicator_preview(landing_position: Vector3) -> void:
	_preview.sync_indicator(
		landing_position, _ghost != null, _placement_action_valid()
	)


func _update_placeable_hover(screen_position: Variant = null) -> void:
	var pointer := (
		screen_position as Vector2
		if screen_position is Vector2
		else get_viewport().get_mouse_position()
	)
	if _pointer_is_over_ui(pointer):
		world_renderer.clear_structure_hover()
		_emit_hover_info("", "", "")
		return
	var interaction_hover := _interaction_hover_at_screen(pointer)
	if not interaction_hover.is_empty():
		_show_interaction_hover(interaction_hover)
		return
	var hit := world_renderer.pick_placeable_at_screen(
		camera_rig.camera,
		pointer
	)
	if hit.is_empty():
		world_renderer.clear_structure_hover()
		_emit_hover_info("", "", "")
		return
	if hit.get("kind", "") == "structure":
		var instance_id := int(hit["instance_id"])
		var found := core.grid.find_structure(instance_id)
		if found.is_empty():
			world_renderer.clear_structure_hover()
			_emit_hover_info("", "", "")
			return
		var structure: WorldGrid.StructureState = found["structure"]
		var definition := core.registries.structure(structure.structure_id)
		world_renderer.set_hovered_structure(instance_id, true)
		_emit_hover_info(
			"structure:%d" % instance_id,
			definition.display_name if definition != null else structure.structure_id,
			_structure_collection_name(definition)
		)
		return
	var coord: Vector2i = hit["coord"]
	var elevation := int(hit["elevation"])
	var state := core.grid.cell_at(coord, elevation)
	var tile_definition := core.grid.tile_def_at(coord, elevation)
	world_renderer.set_hovered_tile(coord, elevation, true)
	_emit_hover_info(
		"tile:%d:%d:%d" % [coord.x, coord.y, elevation],
		tile_definition.display_name if tile_definition != null else state.tile_id,
		_tile_collection_name(tile_definition)
	)


func _update_controller_placeable_hover() -> void:
	world_renderer.clear_structure_hover()
	var interaction_hover := _interaction_hover_at_cell(_controller_cell)
	if not interaction_hover.is_empty():
		_show_interaction_hover(interaction_hover)
		return
	var elevation := core.grid.top_elevation(_controller_cell)
	if elevation < 0:
		_emit_hover_info(
			"empty:%d:%d" % [_controller_cell.x, _controller_cell.y],
			"Empty ground",
			"Move the cursor onto a placed piece"
		)
		return
	var instance_id := _highest_structure_instance_at(
		_controller_cell,
		elevation
	)
	if instance_id > 0:
		var found := core.grid.find_structure(instance_id)
		if not found.is_empty():
			var structure: WorldGrid.StructureState = found["structure"]
			var definition := core.registries.structure(structure.structure_id)
			world_renderer.set_hovered_structure(instance_id, true)
			_emit_hover_info(
				"structure:%d" % instance_id,
				(
					definition.display_name
					if definition != null
					else structure.structure_id
				),
				_structure_collection_name(definition)
			)
			return
	var state := core.grid.cell_at(_controller_cell, elevation)
	var tile_definition := core.grid.tile_def_at(_controller_cell, elevation)
	if state == null:
		_emit_hover_info("", "", "")
		return
	world_renderer.set_hovered_tile(_controller_cell, elevation, true)
	_emit_hover_info(
		"tile:%d:%d:%d" % [
			_controller_cell.x,
			_controller_cell.y,
			elevation,
		],
		(
			tile_definition.display_name
			if tile_definition != null
			else state.tile_id
		),
		_tile_collection_name(tile_definition)
	)


func _interaction_hover_at_screen(screen_position: Vector2) -> Dictionary:
	for provider: Object in _interaction_hover_providers:
		if (
			provider != null
			and is_instance_valid(provider)
			and provider.has_method("event_at_screen")
		):
			var target: Dictionary = provider.call(
				"event_at_screen", camera_rig.camera, screen_position
			)
			if not target.is_empty():
				return target
	return {}


func _interaction_hover_at_cell(cell: Vector2i) -> Dictionary:
	for provider: Object in _interaction_hover_providers:
		if (
			provider != null
			and is_instance_valid(provider)
			and provider.has_method("event_at_cell")
		):
			var target: Dictionary = provider.call("event_at_cell", cell)
			if not target.is_empty():
				return target
	return {}


func _show_interaction_hover(interaction: Dictionary) -> void:
	var visual := interaction.get("visual") as Node3D
	if visual == null:
		world_renderer.clear_structure_hover()
		_emit_hover_info("", "", "")
		return
	var signature := "interaction:%s:%d" % [
		String(interaction.get("kind", "world")),
		int(interaction.get("event_id", visual.get_instance_id())),
	]
	world_renderer.set_hovered_visual(visual, signature)
	_emit_hover_info(
		signature,
		String(interaction.get("display_name", "World Gift")),
		String(interaction.get("collection_name", "Visitor Collection"))
	)


func _tile_collection_name(definition: Defs.TileDefinition) -> String:
	if definition == null:
		return "Tile Collection"
	return "%s Tiles" % definition.family.replace("_", " ").capitalize()


func _structure_collection_name(definition: Defs.StructureDefinition) -> String:
	if definition == null:
		return "Object Collection"
	match definition.kind:
		"building":
			return "Structures"
		"utility":
			return "Utilities"
		_:
			return "Decorations"


func _emit_hover_info(signature: String, display_name: String, collection_name: String) -> void:
	if signature == _hover_info_signature:
		return
	_hover_info_signature = signature
	hover_changed.emit(display_name, collection_name)


func _slot_under_mouse(screen_position: Variant = null) -> Dictionary:
	var viewport := get_viewport()
	var mouse := (
		screen_position as Vector2
		if screen_position is Vector2
		else viewport.get_mouse_position()
	)
	var camera := camera_rig.camera
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if absf(direction.y) < 0.0001:
		return {"coord": _hover_cell, "elevation": -1}
	for elevation in range(core.grid.highest_elevation(), -1, -1):
		var plane_y := core.grid.cell_to_world(Vector2i.ZERO, elevation).y
		var distance := (plane_y - origin.y) / direction.y
		if distance < 0.0:
			continue
		var point := origin + direction * distance
		var coord := core.grid.world_to_cell(point)
		if core.grid.has_cell_at(coord, elevation):
			return {"coord": coord, "elevation": elevation}
	var ground_distance := -origin.y / direction.y
	var ground_point := origin + direction * ground_distance
	return {"coord": core.grid.world_to_cell(ground_point), "elevation": -1}


func _cell_under_mouse() -> Vector2i:
	return _slot_under_mouse()["coord"]


## The grid coord under a screen point, using the same pick-then-ground-plane
## fallback the build cursor uses. Multi-tile selection needs the identical
## answer the build cursor would give, so it shares the resolver rather than
## raycasting the ground plane on its own and disagreeing at stack edges.
func cell_at_screen(screen_position: Vector2) -> Vector2i:
	return _slot_under_mouse(screen_position)["coord"]


## Every occupied coord whose visible top surface falls inside a SCREEN
## rectangle.
##
## Selection is resolved on screen rather than as a rectangle of grid coords.
## The camera sits at 45 degrees, so screen-right runs along grid (X-Y) and
## screen-down along grid (X+Y): dragging on a screen diagonal moves along a
## single grid axis, and a coord-space rectangle collapses to a one-cell strip.
## Sweeping a box therefore has to mean what it looks like it means.
##
## The candidate range is bounded by unprojecting the box's own corners to the
## ground plane, then padded, because a tall stack is drawn well above the
## ground cell it stands on and would otherwise be missed at the top edge.
func coords_in_screen_rect(screen_rect: Rect2) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var camera := camera_rig.camera
	if camera == null or not is_instance_valid(camera):
		return found
	var corners := [
		screen_rect.position,
		screen_rect.position + Vector2(screen_rect.size.x, 0.0),
		screen_rect.position + Vector2(0.0, screen_rect.size.y),
		screen_rect.end,
	]
	var minimum := Vector2i.ZERO
	var maximum := Vector2i.ZERO
	var seeded := false
	for corner: Vector2 in corners:
		var coord: Vector2i = _slot_under_mouse(corner)["coord"]
		if not seeded:
			minimum = coord
			maximum = coord
			seeded = true
			continue
		minimum = Vector2i(mini(minimum.x, coord.x), mini(minimum.y, coord.y))
		maximum = Vector2i(maxi(maximum.x, coord.x), maxi(maximum.y, coord.y))
	if not seeded:
		return found
	var pad := maxi(2, core.grid.max_stack_elevation + 1)
	minimum -= Vector2i(pad, pad)
	maximum += Vector2i(pad, pad)
	for x in range(minimum.x, maximum.x + 1):
		for y in range(minimum.y, maximum.y + 1):
			var coord := Vector2i(x, y)
			if not core.grid.has_cell_at(coord, 0):
				continue
			var top := maxi(0, core.grid.top_elevation(coord))
			var centre := core.grid.cell_to_world(coord, top)
			if screen_rect.has_point(camera.unproject_position(centre)):
				found.append(coord)
	return found


func _update_hover_target() -> void:
	_hover_support_instance_id = 0
	_hover_support_slot = ""
	if (
		not _transient_pointer_edit
		and _controller_mode
		and _controller_cursor_active
	):
		_update_controller_hover_target()
		return
	var pointer_position := (
		_pointer_screen_position
		if _pointer_down
		else get_viewport().get_mouse_position()
	)
	if held.get("kind", "") == "structure":
		var structure_hit := world_renderer.pick_structure_at_screen(
			camera_rig.camera,
			pointer_position
		)
		if not structure_hit.is_empty():
			_hover_cell = structure_hit["coord"]
			_hover_elevation = core.grid.top_elevation(_hover_cell)
			if _resolve_highest_structure_target(_hover_cell, _hover_elevation):
				return
	var hit := _slot_under_mouse(pointer_position)
	_hover_cell = hit["coord"]
	var support_elevation := int(hit["elevation"])
	match held.get("kind", ""):
		"tile":
			var tile_column_top := core.grid.top_elevation(_hover_cell)
			_hover_elevation = tile_column_top + 1 if tile_column_top >= 0 else 0
		"structure":
			var structure_column_top := core.grid.top_elevation(_hover_cell)
			_hover_elevation = (
				structure_column_top
				if structure_column_top >= 0
				else maxi(0, support_elevation)
			)
			_resolve_highest_structure_target(_hover_cell, _hover_elevation)
		_:
			_hover_elevation = 0


func _update_controller_hover_target() -> void:
	_hover_cell = _controller_cell
	match held.get("kind", ""):
		"tile":
			var tile_column_top := core.grid.top_elevation(_hover_cell)
			_hover_elevation = (
				tile_column_top + 1
				if tile_column_top >= 0
				else 0
			)
		"structure":
			_hover_elevation = maxi(0, core.grid.top_elevation(_hover_cell))
			_resolve_highest_structure_target(
				_hover_cell,
				_hover_elevation
			)
		_:
			_hover_elevation = 0


## A column is resolved from its highest support level, with visual height as a
## same-level tie-breaker, never from whichever lower collider won the ray. If
## that top object cannot accept the held item, validation correctly fails.
func _resolve_highest_structure_target(coord: Vector2i, elevation: int) -> bool:
	var target: Dictionary = _target_resolver.resolve_structure_support(
		coord, elevation, String(held.get("id", ""))
	)
	if target.is_empty():
		return false
	_hover_support_instance_id = int(target["instance_id"])
	_hover_support_slot = String(target["slot_id"])
	return true


func _highest_structure_instance_at(coord: Vector2i, elevation: int) -> int:
	return _target_resolver.highest_structure_instance_at(coord, elevation)


## The cell the held piece is currently aimed at.
func hover_cell() -> Vector2i:
	return _hover_cell


func _validate(cell: Vector2i, elevation: int = 0) -> bool:
	return _rules.validate(
		held, cell, elevation,
		_hover_support_instance_id, _hover_support_slot
	)


func _target_socket(cell: Vector2i, elevation: int = 0) -> int:
	return _rules.target_socket(held, cell, elevation)


## A land tile aimed at authored water is still a valid placement intent. The
## water itself is never replaced: the tile skips to the closest cell where
## the ordinary placement rules (stacking, occupancy, and player safety)
## already say it can settle. Future tiles may opt out with the
## `placeable_on_water` data flag and implement direct floating placement.
func water_skip_target_for(water_cell: Vector2i) -> Dictionary:
	if not _is_water_skip_source(water_cell):
		return {}
	var moving_signature := "new"
	if held.get("moving") != null:
		var moving: Dictionary = held["moving"]
		moving_signature = "%s:%s" % [
			moving.get("coord", Vector2i.ZERO),
			moving.get("elevation", 0),
		]
	var cache_key := "%s|%s|%s|%s|%s" % [
		held.get("id", ""),
		moving_signature,
		water_cell,
		player.current_cell(),
		core.grid.total_tile_count(),
	]
	if cache_key == _water_skip_cache_key:
		return _water_skip_cache_target.duplicate(true)

	var maximum_radius := maxi(1, core.nooks.world.nook_size)
	for raw_coord: Variant in core.grid.cells:
		var coord: Vector2i = raw_coord
		maximum_radius = maxi(
			maximum_radius,
			maxi(
				absi(coord.x - water_cell.x),
				absi(coord.y - water_cell.y)
			) + 1
		)
	var candidates: Array[Dictionary] = []
	var best_distance_squared := 0x7FFFFFFF
	for radius in range(1, maximum_radius + 1):
		var ring_start := candidates.size()
		for dx in range(-radius, radius + 1):
			_append_water_skip_candidate(
				candidates, water_cell + Vector2i(dx, -radius), water_cell
			)
			_append_water_skip_candidate(
				candidates, water_cell + Vector2i(dx, radius), water_cell
			)
		for dy in range(-radius + 1, radius):
			_append_water_skip_candidate(
				candidates, water_cell + Vector2i(-radius, dy), water_cell
			)
			_append_water_skip_candidate(
				candidates, water_cell + Vector2i(radius, dy), water_cell
			)
		for candidate_index in range(ring_start, candidates.size()):
			best_distance_squared = mini(
				best_distance_squared,
				int(candidates[candidate_index]["distance_squared"])
			)
		# Chebyshev rings are cheap to enumerate and this Euclidean lower bound
		# proves no later ring can beat the best result. Unlike stopping at the
		# first non-empty ring, it stays exact when a diagonal is farther away
		# than an axial cell on the following ring.
		var next_radius := radius + 1
		if next_radius * next_radius > best_distance_squared:
			break
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["distance_squared"]) != int(b["distance_squared"]):
			return int(a["distance_squared"]) < int(b["distance_squared"])
		if int(a["elevation"]) != int(b["elevation"]):
			return int(a["elevation"]) < int(b["elevation"])
		var a_coord: Vector2i = a["coord"]
		var b_coord: Vector2i = b["coord"]
		return a_coord.y < b_coord.y or (
			a_coord.y == b_coord.y and a_coord.x < b_coord.x
		)
	)
	var resolved: Dictionary = (
		candidates[0]
		if not candidates.is_empty()
		else {}
	)
	_water_skip_cache_key = cache_key
	_water_skip_cache_target = resolved.duplicate(true)
	return resolved.duplicate(true)


func _append_water_skip_candidate(
	result: Array[Dictionary],
	candidate: Vector2i,
	source: Vector2i
) -> void:
	var elevation := (
		core.grid.top_elevation(candidate) + 1
		if core.grid.has_cell(candidate)
		else 0
	)
	if not _rules.validate(held, candidate, elevation, 0, ""):
		return
	result.append({
		"coord": candidate,
		"elevation": elevation,
		"distance_squared": candidate.distance_squared_to(source),
	})


func _is_water_skip_source(cell: Vector2i) -> bool:
	if held.get("kind", "") != "tile":
		return false
	var held_definition := core.registries.tile(String(held.get("id", "")))
	if (
		held_definition == null
		or held_definition.placeable_on_water
		or held_definition.surface_kind == "water"
		or not held_definition.water_cells.is_empty()
	):
		return false
	var top := core.grid.top_elevation(cell)
	if top < 0:
		return false
	var target_definition := core.grid.tile_def_at(cell, top)
	return (
		target_definition != null
		and (
			target_definition.surface_kind == "water"
			or target_definition.render_profile == "continuous_water"
		)
	)


func _water_skip_impact_position(cell: Vector2i) -> Vector3:
	var point := core.grid.cell_to_world(
		cell, maxi(0, core.grid.top_elevation(cell))
	)
	point.y = core.registries.tunef("water_level_y", -0.14)
	return point


func _placement_action_valid() -> bool:
	return (
		_hover_valid
		or not _water_skip_preview_target.is_empty()
		or not water_skip_target_for(_hover_cell).is_empty()
	)


func _try_water_skip() -> bool:
	var source := _hover_cell
	var target := water_skip_target_for(source)
	if target.is_empty():
		return false
	_pending_water_skip = {
		"source": source,
		"impact_position": _water_skip_impact_position(source),
		"destination": target["coord"],
		"elevation": int(target["elevation"]),
	}
	_hover_cell = target["coord"]
	_hover_elevation = int(target["elevation"])
	_hover_support_instance_id = 0
	_hover_support_slot = ""
	_hover_valid = _validate(_hover_cell, _hover_elevation)
	_water_skip_preview_target = {}
	if not _hover_valid:
		_pending_water_skip = {}
		return false
	return _place_tile()


func _invalidate_water_skip_cache() -> void:
	_water_skip_cache_key = ""
	_water_skip_cache_target = {}
	_water_skip_preview_target = {}


# ------------------------------------------------------------------ clicks

## Programmatic placement at an explicit cell — used by acceptance tests and
## available for future gamepad cursor support. Same path as a mouse click.
func try_place_at(cell: Vector2i) -> bool:
	_hover_support_instance_id = 0
	_hover_support_slot = ""
	_hover_cell = cell
	match held.get("kind", ""):
		"tile":
			_hover_elevation = core.grid.top_elevation(cell) + 1 if core.grid.has_cell(cell) else 0
		"structure":
			_hover_elevation = maxi(0, core.grid.top_elevation(cell))
			_resolve_highest_structure_target(cell, _hover_elevation)
		_:
			_hover_elevation = 0
	_hover_valid = _validate(cell, _hover_elevation)
	if not _hover_valid:
		return _try_water_skip()
	click()
	return true


func try_place_at_layer(cell: Vector2i, elevation: int) -> bool:
	_hover_support_instance_id = 0
	_hover_support_slot = ""
	_hover_cell = cell
	_hover_elevation = elevation
	if (
		held.get("kind", "") == "structure"
		and core.grid.top_elevation(cell) == elevation
	):
		_resolve_highest_structure_target(cell, elevation)
	_hover_valid = _validate(cell, elevation)
	if not _hover_valid:
		return false
	click()
	return true


## Programmatic equivalent of hovering a specific object. Tests and future
## controller navigation use the same typed-slot validation as the mouse path.
func try_place_on_structure(parent_instance_id: int, slot_id: String = "") -> bool:
	if held.get("kind", "") != "structure":
		return false
	var found := core.grid.find_structure(parent_instance_id)
	if found.is_empty():
		return false
	_hover_support_instance_id = parent_instance_id
	_hover_support_slot = core.grid.free_support_slot(
		parent_instance_id,
		String(held["id"]),
		slot_id
	)
	_hover_cell = found["coord"]
	_hover_elevation = int(found["elevation"])
	_hover_valid = _validate(_hover_cell, _hover_elevation)
	if not _hover_valid:
		return false
	click()
	return true


func pick_up_at(cell: Vector2i, elevation: int = -1) -> void:
	var target_elevation := core.grid.top_elevation(cell) if elevation < 0 else elevation
	_pick_up_from(cell, target_elevation)


func pointer_press(
	screen_position: Vector2,
	pick_up_on_drag_only := false,
	require_hold_for_pickup := false,
	allow_deferred_pickup := true
) -> void:
	camera_rig.begin_pointer_edit()
	_pointer_down = true
	_pointer_dragging = false
	_pointer_press_position = screen_position
	_pointer_screen_position = screen_position
	_picked_on_pointer_press = false
	_reset_deferred_pickup_intent()
	if held.is_empty():
		if pick_up_on_drag_only:
			if not _pointer_is_over_ui(screen_position):
				if allow_deferred_pickup:
					_deferred_pickup_hit = _placeable_hit_with_grid_fallback(
						screen_position
					)
				_deferred_pickup_requires_hold = (
					require_hold_for_pickup
					and not _deferred_pickup_hit.is_empty()
				)
		else:
			_try_pick_up(screen_position)
			_picked_on_pointer_press = not held.is_empty()
	else:
		click()


## Starts the same press-drag-release gesture for a piece chosen from the Build
## Bag. GUI buttons consume their own press event, so the world input path
## cannot initialize this state itself.
func begin_pointer_drag_for_held(screen_position: Vector2) -> void:
	if held.is_empty():
		return
	camera_rig.begin_pointer_edit()
	_pointer_down = true
	_pointer_dragging = false
	_pointer_press_position = screen_position
	_pointer_screen_position = screen_position
	_picked_on_pointer_press = true
	_reset_deferred_pickup_intent()


func pointer_motion(screen_position: Vector2) -> void:
	_pointer_screen_position = screen_position
	if not _pointer_down or _pointer_dragging:
		return
	if (
		screen_position.distance_to(_pointer_press_position)
		< POINTER_DRAG_DISTANCE
	):
		return
	if (
		not _picked_on_pointer_press
		and not _deferred_pickup_hit.is_empty()
	):
		if _deferred_pickup_requires_hold:
			return
		_begin_deferred_pickup()
		return
	_pointer_dragging = true


func _tick_actionable_pickup_hold(delta: float) -> void:
	if (
		not _pointer_down
		or _picked_on_pointer_press
		or _deferred_pickup_attempted
		or not _deferred_pickup_requires_hold
		or _deferred_pickup_hit.is_empty()
	):
		return
	_pointer_hold_elapsed += maxf(0.0, delta)
	if _pointer_hold_elapsed >= ACTIONABLE_PICKUP_HOLD_SECONDS:
		_begin_deferred_pickup()


func _begin_deferred_pickup() -> void:
	if _deferred_pickup_attempted or _deferred_pickup_hit.is_empty():
		return
	_deferred_pickup_attempted = true
	_pick_up_placeable_hit(_deferred_pickup_hit)
	_picked_on_pointer_press = not held.is_empty()
	if not _picked_on_pointer_press:
		return
	_pointer_dragging = true
	if not active:
		_transient_pointer_edit = true


func _reset_deferred_pickup_intent() -> void:
	_deferred_pickup_hit = {}
	_deferred_pickup_requires_hold = false
	_deferred_pickup_attempted = false
	_pointer_hold_elapsed = 0.0


func pointer_release(screen_position: Vector2) -> bool:
	_pointer_screen_position = screen_position
	var was_dragging := _pointer_down and _pointer_dragging
	var transient_edit := _transient_pointer_edit
	if _pointer_down and _pointer_dragging and _picked_on_pointer_press and not held.is_empty():
		if _placement_action_valid():
			click()
		else:
			action_result.emit(false, _invalid_message(), "invalid")
			if transient_edit:
				_cancel_held(true)
	_transient_pointer_edit = false
	_pointer_down = false
	_pointer_dragging = false
	_picked_on_pointer_press = false
	_reset_deferred_pickup_intent()
	camera_rig.end_pointer_edit()
	return was_dragging


func pointer_is_down() -> bool:
	return _pointer_down


func pointer_dragging_moved_piece() -> bool:
	return (
		_pointer_down
		and _pointer_dragging
		and _picked_on_pointer_press
		and not held.is_empty()
		and held.get("moving") != null
	)


func pointer_dragging_catalogue_piece() -> bool:
	return (
		_pointer_down
		and _pointer_dragging
		and _picked_on_pointer_press
		and not held.is_empty()
		and held.get("moving") == null
	)


## Ends a catalogue click that never became a world drag. The selected piece
## remains held, preserving the original click-to-select workflow.
func cancel_pointer_gesture() -> void:
	_transient_pointer_edit = false
	camera_rig.end_pointer_edit()
	_pointer_down = false
	_pointer_dragging = false
	_picked_on_pointer_press = false
	_reset_deferred_pickup_intent()


func click() -> void:
	if not active and not _transient_pointer_edit:
		return
	if held.is_empty():
		_try_pick_up()
		return
	if not _hover_valid:
		if _try_water_skip():
			return
		action_result.emit(false, _invalid_message(), "invalid")
		return
	match held["kind"]:
		"tile":
			_place_tile()
		"structure":
			_place_structure()
		"deed":
			_place_deed()


func _invalid_message() -> String:
	if _is_water_skip_source(_hover_cell):
		return "Splosh — this land needs a nearby clear place to settle."
	return _rules.invalid_message(
		held, _hover_cell, _hover_elevation, _hover_support_instance_id
	)


func _place_tile() -> bool:
	var tile_id: String = held["id"]
	var rotation_q: int = held["rotation"]
	var offer_id := String(held.get("offer_id", ""))
	var water_skip := _pending_water_skip.duplicate(true)
	_pending_water_skip = {}
	var skip_relative_elevations: Array[int] = [0]
	if not water_skip.is_empty() and held["moving"] != null:
		skip_relative_elevations.clear()
		for entry: Dictionary in held["moving"]["stack"]:
			skip_relative_elevations.append(int(entry["relative_elevation"]))
	if not water_skip.is_empty():
		for relative: int in skip_relative_elevations:
			world_renderer.prepare_water_skip_placement(
				_hover_cell,
				_hover_elevation + relative,
				relative == 0
			)
	var wish_arrival := (
		String(held.get("arrival", "")) == "wish"
		and held["moving"] == null
	)
	if held["moving"] != null:
		var from: Vector2i = held["moving"]["coord"]
		var from_elevation := int(held["moving"].get("elevation", 0))
		var stack: Array = held["moving"]["stack"]
		var from_rotation := int(held["moving"].get("base_rotation", rotation_q))
		_rotate_tile_stack(stack, rotation_q - from_rotation)
		if not core.grid.restore_tile_stack(_hover_cell, _hover_elevation, stack):
			_rotate_tile_stack(stack, from_rotation - rotation_q)
			_cancel_water_skip_refreshes(
				water_skip,
				skip_relative_elevations
			)
			action_result.emit(false, "That land stack changed before it could settle.", "invalid")
			return false
		_push_undo({
			"type": "move_tile_stack",
			"from": from,
			"from_elevation": from_elevation,
			"to": _hover_cell,
			"to_elevation": _hover_elevation,
			"from_rotation": from_rotation,
			"to_rotation": rotation_q,
			"home_before": held["moving"].get("home_before", core.grid.home_cell),
			"home_after": held["moving"].get("home_after", core.grid.home_cell),
		})
		held = {}
		held_changed.emit(held)
		_build_ghost()
		core.autosave_paused = false
		core.autosave_soon()
	else:
		if wish_arrival:
			world_renderer.prepare_wish_placement(
				_hover_cell,
				_hover_elevation,
				true
			)
		var placed_from_offer := offer_id != ""
		var placed_ok := (
			core.place_tile_from_diorama_offer(
				_hover_cell, tile_id, rotation_q, _hover_elevation, offer_id
			)
			if placed_from_offer
			else core.place_tile_from_stock(
				_hover_cell, tile_id, rotation_q, _hover_elevation
			)
		)
		if not placed_ok:
			if wish_arrival:
				world_renderer.cancel_wish_placement(
					_hover_cell,
					_hover_elevation
				)
			_cancel_water_skip_refreshes(
				water_skip,
				skip_relative_elevations
			)
			action_result.emit(false, "That piece isn't in storage anymore.", "invalid")
			return false
		_push_undo({
			"type": "place_tile",
			"coord": _hover_cell,
			"elevation": _hover_elevation,
			"tile_id": tile_id,
			"rotation": rotation_q,
		})
		var remaining := core.stock.tile_count(tile_id)
		if placed_from_offer or wish_arrival or remaining <= 0:
			held = {}
			held_changed.emit(held)
			_build_ghost()
		if placed_from_offer:
			set_active(false)
	var def := core.registries.tile(tile_id)
	var effect_position := core.grid.cell_to_world(
		_hover_cell,
		_hover_elevation
	)
	var landing_tween: Tween = null
	if not water_skip.is_empty():
		var impact_position: Vector3 = water_skip["impact_position"]
		effects.ripple(impact_position)
		tile_splashed.emit(impact_position, effect_position)
		landing_tween = world_renderer.animate_tile_stack_water_skip(
			_hover_cell,
			_hover_elevation,
			skip_relative_elevations,
			impact_position
		)
	elif wish_arrival:
		landing_tween = world_renderer.animate_tile_wish_landing(
			_hover_cell,
			_hover_elevation
		)
	_finish_placement_feedback(
		effect_position,
		# What the tile is made of, not what it sounds like. Snow tiles carry
		# placement_sound "grass", so passing the sound through scattered leaves
		# over a snowdrift.
		GroundImpactEffects.surface_profile_for_definition(def),
		(
			"Splosh! It bounced onto the nearest clear spot."
			if not water_skip.is_empty()
			else "Stacked at level %d." % _hover_elevation
				if _hover_elevation > 0
				else ""
		),
		landing_tween
	)
	return true


func _cancel_water_skip_refreshes(
	water_skip: Dictionary,
	relative_elevations: Array[int]
) -> void:
	if water_skip.is_empty():
		return
	for relative: int in relative_elevations:
		world_renderer.cancel_water_skip_placement(
			_hover_cell,
			_hover_elevation + relative
		)


func _rotate_tile_stack(stack: Array, quarter_turn_delta: int) -> void:
	if posmod(quarter_turn_delta, 4) == 0:
		return
	for entry: Dictionary in stack:
		var state: WorldGrid.CellState = entry["state"]
		state.rotation = posmod(state.rotation + quarter_turn_delta, 4)
		for structure: WorldGrid.StructureState in state.structures:
			if structure.parent_instance_id == 0:
				structure.rotation = posmod(
					structure.rotation + quarter_turn_delta,
					4
				)


func _place_structure() -> void:
	var structure_id: String = held["id"]
	var offer_id := String(held.get("offer_id", ""))
	var wish_arrival := (
		String(held.get("arrival", "")) == "wish"
		and held["moving"] == null
	)
	var socket := (
		-1
		if _hover_support_instance_id > 0
		else _target_socket(_hover_cell, _hover_elevation)
	)
	var placed: WorldGrid.StructureState = null
	if held["moving"] != null:
		var moving: Dictionary = held["moving"]
		var stack: Array[WorldGrid.StructureState] = moving["stack"]
		if not core.grid.restore_structure_stack(
			_hover_cell,
			_hover_elevation,
			stack,
			_hover_support_instance_id,
			_hover_support_slot,
			socket,
			int(held["rotation"])
		):
			action_result.emit(false, "That support changed before the item could settle.", "invalid")
			return
		placed = stack[0]
		_push_undo({
			"type": "move_structure",
			"iid": placed.instance_id,
			"structure_id": structure_id,
			"stack": stack,
			"from": moving["origin"],
			"to": {
				"coord": _hover_cell,
				"elevation": _hover_elevation,
				"socket": socket,
				"rot": held["rotation"],
				"parent": _hover_support_instance_id,
				"support": _hover_support_slot,
			},
		})
		held = {}
		core.autosave_paused = false
	else:
		if wish_arrival:
			world_renderer.prepare_wish_placement(
				_hover_cell,
				_hover_elevation
			)
		var placed_from_offer := offer_id != ""
		if (
			placed_from_offer
			and not core.can_commit_diorama_offer(
				offer_id, "structure", structure_id
			)
		):
			action_result.emit(false, "That tray offer is no longer available.", "invalid")
			return
		var stock_token := (
			{}
			if placed_from_offer
			else core.stock.take_structure_token(structure_id)
		)
		if not placed_from_offer and stock_token.is_empty():
			if wish_arrival:
				world_renderer.cancel_wish_placement(
					_hover_cell,
					_hover_elevation
				)
			action_result.emit(false, "That piece isn't in storage anymore.", "invalid")
			return
		var stored_state: Dictionary = stock_token.get("state", {})
		if not stored_state.is_empty():
			var restored := WorldGrid.StructureState.from_dict(stored_state)
			var restored_stack: Array[WorldGrid.StructureState] = [restored]
			if core.grid.restore_structure_stack(
				_hover_cell,
				_hover_elevation,
				restored_stack,
				_hover_support_instance_id,
				_hover_support_slot,
				socket,
				int(held["rotation"])
			):
				placed = restored
		elif _hover_support_instance_id > 0:
			placed = core.grid.add_structure_on(
				_hover_support_instance_id, structure_id,
				_hover_support_slot, held["rotation"]
			)
		else:
			placed = core.grid.add_structure(
				_hover_cell,
				structure_id,
				socket,
				held["rotation"],
				_hover_elevation
			)
		if placed == null:
			if not placed_from_offer:
				core.stock.return_structure_token(stock_token)
			if wish_arrival:
				world_renderer.cancel_wish_placement(
					_hover_cell,
					_hover_elevation
				)
			action_result.emit(false, "That support changed before the item could settle.", "invalid")
			return
		if placed_from_offer:
			if core.commit_diorama_offer(
				offer_id, "structure", structure_id
			).is_empty():
				core.grid.remove_structure(
					_hover_cell, placed.instance_id, _hover_elevation
				)
				action_result.emit(false, "That tray offer changed before it settled.", "invalid")
				return
		else:
			core.collection.record_placed("structures", structure_id)
		_push_undo({
			"type": "place_structure",
			"coord": _hover_cell,
			"elevation": _hover_elevation,
			"iid": placed.instance_id,
			"structure_id": structure_id,
			"socket": socket,
			"rot": held["rotation"],
			"parent": _hover_support_instance_id,
			"support": _hover_support_slot,
			"stack": [placed],
		})
		if placed_from_offer or wish_arrival or core.stock.structure_count(structure_id) <= 0:
			held = {}
	held_changed.emit(held)
	_build_ghost()
	if offer_id != "":
		set_active(false)
	var def := core.registries.structure(structure_id)
	var effect_position := (
		world_renderer.support_slot_world_transform(
			_hover_support_instance_id,
			_hover_support_slot
		).origin
		if _hover_support_instance_id > 0
		else core.grid.cell_to_world(_hover_cell, _hover_elevation)
			+ core.grid.socket_offset(socket)
	)
	var landing_tween: Tween = null
	if wish_arrival:
		landing_tween = world_renderer.animate_structure_wish_landing(
			placed.instance_id
		)
	else:
		world_renderer.animate_structure_settle(placed.instance_id)
	core.autosave_soon()
	_finish_placement_feedback(
		effect_position,
		GroundImpactEffects.surface_profile_for_sound(def.placement_sound),
		"",
		landing_tween,
		def.placement_sound
	)


func _finish_placement_feedback(
	effect_position: Vector3,
	effect_sound: String,
	message: String,
	landing_tween: Tween = null,
	action_sound := ""
) -> void:
	var finish := func():
		effects.placement_poof(effect_position, effect_sound)
		action_result.emit(
			true,
			message,
			"place_" + (action_sound if action_sound != "" else effect_sound)
		)
	if landing_tween != null and landing_tween.is_valid():
		landing_tween.finished.connect(finish)
	else:
		finish.call()


func _place_deed() -> void:
	if core.landmarks.place_deed(held["id"], _hover_cell):
		held = {}
		held_changed.emit(held)
		_build_ghost()
		core.autosave_soon()
		action_result.emit(true, "The landmark settles into its new home.", "place_stone")
	else:
		action_result.emit(false, "The landmark needs clear ground beside your world.", "invalid")


## Pick up an existing structure (preferred) or a movable tile under the cursor.
func _try_pick_up(screen_position: Variant = null) -> void:
	if _controller_mode and _controller_cursor_active:
		var controller_elevation := core.grid.top_elevation(_controller_cell)
		if controller_elevation >= 0:
			var controller_instance := _highest_structure_instance_at(
				_controller_cell,
				controller_elevation
			)
			_pick_up_from(
				_controller_cell,
				controller_elevation,
				controller_instance
			)
		return
	var pointer := (
		screen_position as Vector2
		if screen_position is Vector2
		else get_viewport().get_mouse_position()
	)
	if _pointer_is_over_ui(pointer):
		return
	var hit := world_renderer.pick_placeable_at_screen(
		camera_rig.camera,
		pointer
	)
	if not hit.is_empty():
		_pick_up_placeable_hit(hit)
		return
	var slot_hit := _slot_under_mouse(pointer)
	var elevation := int(slot_hit["elevation"])
	if elevation >= 0:
		_pick_up_from(slot_hit["coord"], elevation)


## Renderer refreshes replace physics bodies asynchronously. A click ray is
## normally authoritative, but the deterministic grid ray keeps a just-restored
## object draggable during the one physics frame before its new body registers.
func _placeable_hit_with_grid_fallback(screen_position: Vector2) -> Dictionary:
	var hit := world_renderer.pick_placeable_at_screen(
		camera_rig.camera,
		screen_position
	)
	if not hit.is_empty():
		return hit
	var slot_hit := _slot_under_mouse(screen_position)
	var coord: Vector2i = slot_hit["coord"]
	var elevation := int(slot_hit["elevation"])
	if elevation < 0:
		return {}
	var state := core.grid.cell_at(coord, elevation)
	if state == null:
		return {}
	var instance_id := _highest_structure_instance_at(coord, elevation)
	if instance_id > 0:
		return {
			"kind": "structure",
			"coord": coord,
			"elevation": elevation,
			"instance_id": instance_id,
		}
	return {
		"kind": "tile",
		"coord": coord,
		"elevation": elevation,
	}


func _pick_up_placeable_hit(hit: Dictionary) -> void:
	if world_renderer.placeable_is_wish_falling(
		String(hit.get("kind", "")),
		hit.get("coord", Vector2i.ZERO),
		int(hit.get("elevation", 0)),
		int(hit.get("instance_id", 0))
	):
		return
	if hit.get("kind", "") == "structure":
		_pick_up_from(
			hit["coord"],
			int(hit["elevation"]),
			int(hit["instance_id"])
		)
		return
	if hit.get("kind", "") == "tile":
		var tile_state := core.grid.cell_at(hit["coord"], int(hit["elevation"]))
		if tile_state != null:
			_try_pick_up_tile(hit["coord"], int(hit["elevation"]), tile_state)


func _pick_up_from(cell: Vector2i, elevation: int, preferred_instance_id := -1) -> void:
	var state := core.grid.cell_at(cell, elevation)
	if state == null:
		return
	if not state.structures.is_empty():
		var s: WorldGrid.StructureState = null
		if preferred_instance_id >= 0:
			for candidate: WorldGrid.StructureState in state.structures:
				if candidate.instance_id == preferred_instance_id:
					s = candidate
					break
		else:
			s = state.structures.back()
		if s == null:
			return
		var picked_definition := core.registries.structure(s.structure_id)
		if (
			picked_definition != null
			and picked_definition.has_capability("reward_drop")
		):
			action_result.emit(
				false,
				"Claim this fallen reward in interaction mode first.",
				"invalid"
			)
			return
		var origin := {
			"coord": cell,
			"elevation": elevation,
			"socket": s.socket_index,
			"rot": s.rotation,
			"iid": s.instance_id,
			"parent": s.parent_instance_id,
			"support": s.support_slot_id,
		}
		world_renderer.clear_structure_hover()
		var stack := core.grid.detach_structure_stack(s.instance_id)
		if stack.is_empty():
			return
		core.autosave_paused = true
		held = {
			"kind": "structure",
			"id": s.structure_id,
			"rotation": s.rotation,
			"moving": {
				"stack": stack,
				"origin": origin,
			},
		}
		_build_ghost()
		held_changed.emit(held)
		action_result.emit(true, "Click to move it, Esc to put it back, X to store it.", "pickup")
		return
	_try_pick_up_tile(cell, elevation, state)


func _try_pick_up_tile(cell: Vector2i, elevation: int, state: WorldGrid.CellState) -> void:
	if state.movement_locked:
		action_result.emit(
			false,
			"Move the Worldheart before moving its host tile."
			if core.diorama.enabled and cell == core.diorama.worldheart.worldheart_cell
			else "This tile anchors the opening zone for now.",
			"invalid"
		)
		return
	if elevation == 0 and state.landmark_id != "":
		action_result.emit(false, "Reclaimed landmarks move by packing them from their pedestal.", "invalid")
		return
	var home_before := core.grid.home_cell
	var home_after := home_before
	if elevation == 0 and home_before == cell:
		home_after = core.grid.nearest_walkable(cell, cell)
		if home_after == cell:
			action_result.emit(false, "Place another safe land tile before moving this one.", "invalid")
			return
	if elevation == 0 and player.current_cell() == cell:
		var refuge := core.grid.nearest_walkable(cell, cell)
		if refuge == cell:
			action_result.emit(false, "There's nowhere safe to stand — place more land first.", "invalid")
			return
		player.position = core.grid.cell_to_world(refuge)
	if elevation == 0:
		core.grid.home_cell = home_after
	var stack := core.grid.detach_tile_stack(cell, elevation)
	if stack.is_empty():
		core.grid.home_cell = home_before
		return
	var removed: WorldGrid.CellState = stack[0]["state"]
	core.autosave_paused = true
	held = {
		"kind": "tile",
		"id": removed.tile_id,
		"rotation": removed.rotation,
		"moving": {
			"coord": cell,
			"elevation": elevation,
			"stack": stack,
			"base_rotation": removed.rotation,
			"home_before": home_before,
			"home_after": home_after,
		},
	}
	_build_ghost()
	held_changed.emit(held)
	action_result.emit(
		true,
		"Drag or click it onto a clear edge or flat supporting block. Esc restores it.",
		"pickup"
	)


## X while holding a moved piece stores it instead of replacing it.
func store_held() -> void:
	if held.is_empty() or held["moving"] == null:
		return
	match held["kind"]:
		"structure":
			var moved_stack: Array[WorldGrid.StructureState] = held["moving"]["stack"]
			_return_structure_stack_to_stock(moved_stack)
			_push_undo({
				"type": "store_structure",
				"structure_id": held["id"],
				"stack": moved_stack,
				"from": held["moving"]["origin"],
			})
		"tile":
			var tile_stack: Array = held["moving"]["stack"]
			_return_tile_stack_to_stock(tile_stack)
			_push_undo({
				"type": "store_tile_stack",
				"tile_id": held["id"],
				"stack": tile_stack,
				"from": held["moving"].duplicate(),
			})
		_:
			return
	held = {}
	core.autosave_paused = false
	_transient_pointer_edit = false
	camera_rig.end_pointer_edit()
	_pointer_down = false
	_pointer_dragging = false
	_picked_on_pointer_press = false
	_reset_deferred_pickup_intent()
	held_changed.emit(held)
	_build_ghost()
	core.autosave_soon()
	action_result.emit(true, "Stored.", "store")


func cancel_click() -> void:
	if not held.is_empty():
		var was_tray_offer := String(held.get("offer_id", "")) != ""
		_cancel_held(true)
		if was_tray_offer:
			set_active(false)
	else:
		set_active(false)


## A save is an explicit transaction boundary. A piece being moved is restored
## before serialization so no save can capture it in the transient held state.
func prepare_for_save() -> void:
	if not held.is_empty() and held.get("moving") != null:
		_cancel_held(true)


## Cancelling a move restores the piece to its original position — nothing is
## ever lost to experimentation.
func _cancel_held(restore: bool) -> void:
	if held.is_empty():
		core.autosave_paused = false
		_transient_pointer_edit = false
		cancel_pointer_gesture()
		if _ghost != null:
			_ghost.queue_free()
			_ghost = null
		return
	var cancelled_offer_id := String(held.get("offer_id", ""))
	if cancelled_offer_id != "" and core.diorama != null:
		core.diorama.tray.cancel_hold(cancelled_offer_id)
	if restore and held["moving"] != null:
		match held["kind"]:
			"tile":
				var coord: Vector2i = held["moving"]["coord"]
				var elevation := int(held["moving"].get("elevation", 0))
				core.grid.restore_tile_stack(
					coord,
					elevation,
					held["moving"]["stack"],
					false
				)
				core.grid.home_cell = held["moving"].get("home_before", core.grid.home_cell)
			"structure":
				var moving: Dictionary = held["moving"]
				var origin: Dictionary = moving["origin"]
				core.grid.restore_structure_stack(
					origin["coord"],
					int(origin.get("elevation", 0)),
					moving["stack"],
					int(origin.get("parent", 0)),
					String(origin.get("support", "")),
					int(origin.get("socket", 0)),
					int(origin.get("rot", 0))
				)
	elif restore and held["moving"] == null and held["kind"] == "tile":
		pass  # piece stays in stock — nothing was consumed until placement
	held = {}
	core.autosave_paused = false
	_transient_pointer_edit = false
	camera_rig.end_pointer_edit()
	_pointer_down = false
	_pointer_dragging = false
	_picked_on_pointer_press = false
	_reset_deferred_pickup_intent()
	held_changed.emit(held)
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null


# ------------------------------------------------------------------ undo / redo

func _push_undo(entry: Dictionary) -> void:
	_history.record(entry)


func undo() -> void:
	if _history.undo(_apply):
		action_result.emit(true, "", "undo")


func redo() -> void:
	if _history.redo(_apply):
		action_result.emit(true, "", "redo")


func _apply(entry: Dictionary, reverse: bool) -> bool:
	match entry["type"]:
		"place_tile":
			var elevation := int(entry.get("elevation", 0))
			if reverse:
				var coord: Vector2i = entry["coord"]
				if elevation == 0 and player.current_cell() == coord:
					player.position = core.grid.cell_to_world(core.grid.nearest_walkable(coord, coord))
				var removed := core.grid.remove_tile_at(coord, elevation)
				if removed != null:
					core.stock.add_tile(removed.tile_id)
				return removed != null
			return core.place_tile_from_stock(
				entry["coord"],
				entry["tile_id"],
				int(entry.get("rotation", 0)),
				elevation
			)
		"place_structure":
			var structure_elevation := int(entry.get("elevation", 0))
			if reverse:
				var removed_stack := core.grid.detach_structure_stack(entry["iid"])
				if removed_stack.is_empty():
					return false
				entry["stack"] = removed_stack
				_return_structure_stack_to_stock(removed_stack)
				return true
			var placed_stack: Array[WorldGrid.StructureState] = entry.get("stack", [])
			if placed_stack.is_empty() or not _take_structure_stack_from_stock(placed_stack):
				return false
			if core.grid.restore_structure_stack(
				entry["coord"],
				structure_elevation,
				placed_stack,
				int(entry.get("parent", 0)),
				String(entry.get("support", "")),
				int(entry.get("socket", -1)),
				int(entry.get("rot", 0))
			):
				entry["iid"] = placed_stack[0].instance_id
				return true
			_return_structure_stack_to_stock(placed_stack)
			return false
		"move_tile_stack":
			var from: Vector2i = entry["to"] if reverse else entry["from"]
			var to: Vector2i = entry["from"] if reverse else entry["to"]
			var from_elevation := (
				int(entry.get("to_elevation", 0))
				if reverse
				else int(entry.get("from_elevation", 0))
			)
			var to_elevation := (
				int(entry.get("from_elevation", 0))
				if reverse
				else int(entry.get("to_elevation", 0))
			)
			var moving_stack := core.grid.detach_tile_stack(from, from_elevation)
			if moving_stack.is_empty():
				return false
			var source_rotation := int(
				entry.get("to_rotation", 0)
				if reverse
				else entry.get("from_rotation", 0)
			)
			var destination_rotation := int(
				entry.get("from_rotation", 0)
				if reverse
				else entry.get("to_rotation", 0)
			)
			_rotate_tile_stack(moving_stack, destination_rotation - source_rotation)
			if not core.grid.restore_tile_stack(to, to_elevation, moving_stack):
				_rotate_tile_stack(moving_stack, source_rotation - destination_rotation)
				core.grid.restore_tile_stack(from, from_elevation, moving_stack, false)
				return false
			core.grid.home_cell = (
				entry.get("home_before", core.grid.home_cell)
				if reverse
				else entry.get("home_after", core.grid.home_cell)
			)
			return true
		"move_structure":
			var dst: Dictionary = entry["from"] if reverse else entry["to"]
			var found := core.grid.find_structure(entry["iid"])
			if found.is_empty():
				return false
			var moved_stack := core.grid.detach_structure_stack(entry["iid"])
			if moved_stack.is_empty():
				return false
			if not core.grid.restore_structure_stack(
				dst["coord"],
				int(dst.get("elevation", 0)),
				moved_stack,
				int(dst.get("parent", 0)),
				String(dst.get("support", "")),
				int(dst.get("socket", 0)),
				int(dst.get("rot", 0))
			):
				var src: Dictionary = entry["to"] if reverse else entry["from"]
				core.grid.restore_structure_stack(
					src["coord"],
					int(src.get("elevation", 0)),
					moved_stack,
					int(src.get("parent", 0)),
					String(src.get("support", "")),
					int(src.get("socket", 0)),
					int(src.get("rot", 0))
				)
				return false
			entry["stack"] = moved_stack
			return true
		"rotate_structure":
			world_renderer.clear_structure_hover()
			return core.grid.set_structure_rotation(
				int(entry.get("iid", 0)),
				int(
					entry.get("from_rotation", 0)
					if reverse
					else entry.get("to_rotation", 0)
				)
			)
		"rotate_tile_stack":
			var rotate_coord: Vector2i = entry["coord"]
			var rotate_elevation := int(entry.get("elevation", 0))
			var rotate_state := core.grid.cell_at(
				rotate_coord,
				rotate_elevation
			)
			if rotate_state == null:
				return false
			var target_rotation := int(
				entry.get("from_rotation", 0)
				if reverse
				else entry.get("to_rotation", 0)
			)
			world_renderer.clear_structure_hover()
			return core.grid.rotate_tile_stack_at(
				rotate_coord,
				rotate_elevation,
				target_rotation - rotate_state.rotation
			)
		"store_structure":
			var m: Dictionary = entry["from"]
			var stored_stack: Array[WorldGrid.StructureState] = entry["stack"]
			if reverse:
				if not _take_structure_stack_from_stock(stored_stack):
					return false
				if core.grid.restore_structure_stack(
					m["coord"],
					int(m.get("elevation", 0)),
					stored_stack,
					int(m.get("parent", 0)),
					String(m.get("support", "")),
					int(m.get("socket", 0)),
					int(m.get("rot", 0))
				):
					return true
				_return_structure_stack_to_stock(stored_stack)
				return false
			var removed_again := core.grid.detach_structure_stack(
				int(m.get("iid", -1))
			)
			if not removed_again.is_empty():
				entry["stack"] = removed_again
				_return_structure_stack_to_stock(removed_again)
				return true
			return false
		"store_tile_stack":
			var tile_from: Dictionary = entry["from"]
			var tile_coord: Vector2i = tile_from["coord"]
			var tile_elevation := int(tile_from.get("elevation", 0))
			var stored_tiles: Array = entry["stack"]
			if reverse:
				if not _take_tile_stack_from_stock(stored_tiles):
					return false
				if not core.grid.restore_tile_stack(
					tile_coord,
					tile_elevation,
					stored_tiles
				):
					_return_tile_stack_to_stock(stored_tiles)
					return false
				core.grid.home_cell = tile_from.get("home_before", core.grid.home_cell)
				return true
			var removed_tiles := core.grid.detach_tile_stack(tile_coord, tile_elevation)
			if removed_tiles.is_empty():
				return false
			entry["stack"] = removed_tiles
			core.grid.home_cell = tile_from.get("home_after", core.grid.home_cell)
			_return_tile_stack_to_stock(removed_tiles)
			return true
	return false


func _structure_id_of(entry: Dictionary) -> String:
	return entry.get("structure_id", held.get("id", ""))


func _take_structure_stack_from_stock(stack: Array[WorldGrid.StructureState]) -> bool:
	var taken: Array[Dictionary] = []
	for structure: WorldGrid.StructureState in stack:
		var token := core.stock.take_structure_token(
			structure.structure_id, structure.instance_id
		)
		if token.is_empty():
			for previous_token: Dictionary in taken:
				core.stock.return_structure_token(previous_token)
			return false
		taken.append(token)
	return true


func _return_structure_stack_to_stock(stack: Array[WorldGrid.StructureState]) -> void:
	for structure: WorldGrid.StructureState in stack:
		core.stock.add_structure_instance(structure)


func _take_tile_stack_from_stock(stack: Array) -> bool:
	var taken_tiles: Array[String] = []
	var taken_structures: Array[Dictionary] = []
	for entry: Dictionary in stack:
		var state: WorldGrid.CellState = entry["state"]
		if not core.stock.take_tile(state.tile_id):
			for tile_id: String in taken_tiles:
				core.stock.add_tile(tile_id)
			for token: Dictionary in taken_structures:
				core.stock.return_structure_token(token)
			return false
		taken_tiles.append(state.tile_id)
		for structure: WorldGrid.StructureState in state.structures:
			var token := core.stock.take_structure_token(
				structure.structure_id, structure.instance_id
			)
			if token.is_empty():
				for tile_id: String in taken_tiles:
					core.stock.add_tile(tile_id)
				for previous_token: Dictionary in taken_structures:
					core.stock.return_structure_token(previous_token)
				return false
			taken_structures.append(token)
	return true


func _return_tile_stack_to_stock(stack: Array) -> void:
	for entry: Dictionary in stack:
		var state: WorldGrid.CellState = entry["state"]
		core.stock.add_tile(state.tile_id)
		for structure: WorldGrid.StructureState in state.structures:
			core.stock.add_structure_instance(structure)
