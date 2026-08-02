class_name BuildThumbnailRenderer
extends Node

var _color_system := PaletteDefinition.shared()
## Renders owned build pieces through the production visual factories.
##
## One small viewport services a lazy queue and then switches itself off. The
## resulting ImageTextures are cached, so opening a large collection does not
## leave dozens of live 3D viewports consuming render time.

const PREVIEW_SIZE := 180
const CAMERA_DIRECTION := Vector3(3.4, 2.8, 4.2)

var core: GameCore
var assets: AssetLibrary
var _tile_factory: TileVisualFactory
var _structure_factory: StructureVisualFactory
var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _queue: Array[Dictionary] = []
var _callbacks: Dictionary = {}
var _cache: Dictionary = {}
var _active_key := ""
var _active_visual: Node3D
var _render_frames := 0


func setup(game_core: GameCore, asset_library: AssetLibrary) -> void:
	core = game_core
	assets = asset_library
	_tile_factory = TileVisualFactory.new(assets, core.grid)
	_structure_factory = StructureVisualFactory.new(assets, core.grid)
	_build_viewport()
	set_process(true)


func request(kind: String, content_id: String, receiver: Callable) -> void:
	if DisplayServer.get_name() == "headless":
		receiver.call_deferred(null)
		return
	var key := "%s:%s" % [kind, content_id]
	if _cache.has(key):
		receiver.call_deferred(_cache[key])
		return
	if not _callbacks.has(key):
		_callbacks[key] = []
		_queue.append({"key": key, "kind": kind, "id": content_id})
	(_callbacks[key] as Array).append(receiver)


func cached(kind: String, content_id: String) -> Texture2D:
	return _cache.get("%s:%s" % [kind, content_id])


func discard_pending() -> void:
	_queue.clear()
	for key: String in _callbacks.keys():
		if key != _active_key:
			_callbacks.erase(key)


func _process(_delta: float) -> void:
	if _viewport == null:
		return
	if _active_visual == null:
		if not _queue.is_empty():
			_begin_next()
		return
	_render_frames += 1
	if _render_frames < 4:
		return
	var image := _viewport.get_texture().get_image()
	var texture: ImageTexture
	if image != null and not image.is_empty():
		texture = ImageTexture.create_from_image(image)
	_cache[_active_key] = texture
	for receiver: Callable in _callbacks.get(_active_key, []):
		if receiver.is_valid():
			receiver.call(texture)
	_callbacks.erase(_active_key)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_active_visual.queue_free()
	_active_visual = null
	_active_key = ""


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "BuildThumbnailViewport"
	_viewport.size = Vector2i(PREVIEW_SIZE, PREVIEW_SIZE)
	# A SubViewport inherits its parent's World3D unless explicitly isolated.
	# Without this, its thumbnail camera also sees the live island, player, and
	# weather—producing a crop of gameplay instead of the requested build piece.
	# Godot 4.6's Windows dummy renderer crashes while constructing an isolated
	# World3D, and thumbnail requests already no-op in headless tests.
	if DisplayServer.get_name() != "headless":
		_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _color_system.color("ui_transparent")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _color_system.color("thumbnail_ambient")
	env.ambient_light_energy = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	_viewport.add_child(environment)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48, -32, 0)
	key_light.light_color = _color_system.color("thumbnail_key")
	key_light.light_energy = 1.35
	key_light.shadow_enabled = false
	_viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-28, 148, 0)
	fill_light.light_color = _color_system.color("thumbnail_fill")
	fill_light.light_energy = 0.42
	fill_light.shadow_enabled = false
	_viewport.add_child(fill_light)

	_stage = Node3D.new()
	_stage.name = "PreviewStage"
	_viewport.add_child(_stage)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_camera.near = 0.02
	_camera.far = 40.0
	_viewport.add_child(_camera)


func _begin_next() -> void:
	var entry: Dictionary = _queue.pop_front()
	_active_key = String(entry["key"])
	_active_visual = _instantiate(
		String(entry["kind"]),
		String(entry["id"])
	)
	if _active_visual == null:
		_finish_missing()
		return
	_stage.add_child(_active_visual)
	_frame_visual(_active_visual)
	_render_frames = 0
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _instantiate(kind: String, content_id: String) -> Node3D:
	match kind:
		"tile":
			var tile := core.registries.tile(content_id)
			return _tile_factory.instantiate_visual(tile, true) if tile != null else null
		"starter_island":
			return _starter_island_visual(content_id)
		"structure":
			var structure := core.registries.structure(content_id)
			return (
				_structure_factory.instantiate_visual(structure)
				if structure != null
				else null
			)
		"deed":
			var landmark := core.registries.landmark(content_id)
			return assets.instantiate(landmark.asset_id) if landmark != null else null
	return null


func _starter_island_visual(land_tile_id: String) -> Node3D:
	var land := core.registries.tile(land_tile_id)
	var water := core.registries.tile("tile_open_water")
	var tree := core.registries.structure("struct_pine")
	if land == null or water == null or tree == null:
		return null
	var island := Node3D.new()
	var tile_size := core.grid.tile_size
	for x in range(-2, 3):
		for z in range(-2, 3):
			var is_water_ring := absi(x) == 2 or absi(z) == 2
			var definition := water if is_water_ring else land
			var tile_visual := _tile_factory.instantiate_visual(definition, true)
			if tile_visual == null:
				continue
			tile_visual.position = Vector3(
				float(x) * tile_size,
				0.0,
				float(z) * tile_size
			)
			island.add_child(tile_visual)
	var tree_visual := _structure_factory.instantiate_visual(tree)
	if tree_visual != null:
		tree_visual.position = Vector3(-tile_size, 0.0, -tile_size)
		island.add_child(tree_visual)
	return island


func _frame_visual(visual: Node3D) -> void:
	var bounds_data := StructureVisualFactory.local_mesh_bounds(visual)
	var bounds := AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
	if bool(bounds_data.get("found", false)):
		bounds = bounds_data["bounds"]
	var center := bounds.get_center()
	var span := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	span = maxf(span, 0.35)
	visual.position = -center
	var direction := CAMERA_DIRECTION.normalized()
	_camera.position = direction * maxf(3.0, span * 3.1)
	_camera.size = span * 1.34
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _finish_missing() -> void:
	for receiver: Callable in _callbacks.get(_active_key, []):
		if receiver.is_valid():
			receiver.call(null)
	_callbacks.erase(_active_key)
	_active_key = ""
