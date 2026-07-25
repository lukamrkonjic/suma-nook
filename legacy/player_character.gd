extends Node3D
# legacy-disabled class_name SumaPlayerCharacter

signal tile_entered(coord: Vector3i)
signal path_changed(active: bool)

const PixelArt := preload("res://scripts/pixel_art.gd")

var grid: GridManager
var grid_coord := Vector3i(0, 1, 0)
var display_name := "Fern"
var appearance := {"skin": 1, "hair": 0, "outfit": 0}
var can_control := false
var move_speed := 4.8
var sprite: Sprite3D
var shadow: MeshInstance3D
var nameplate: Label3D
var _path: Array[Vector3i] = []
var _walk_time := 0.0
var _step_frame := 0


func setup(
		grid_manager: GridManager,
		player_name: String,
		player_appearance: Dictionary,
		start: Vector3i = Vector3i(0, 1, 0)
	) -> void:
	grid = grid_manager
	display_name = player_name.strip_edges() if not player_name.strip_edges().is_empty() else "Fern"
	appearance = player_appearance.duplicate(true)
	grid_coord = start if grid.is_walkable(start) else Vector3i(0, 1, 0)
	name = "Player_%s" % display_name.validate_node_name()
	_build_visual()
	position = _world_for(grid_coord)


func _process(delta: float) -> void:
	if _path.is_empty():
		_walk_time = 0.0
		if sprite != null:
			sprite.position.y = 0.67
		return
	_walk_time += delta
	var next: Vector3i = _path[0]
	var destination := _world_for(next)
	var before := position
	position = position.move_toward(destination, move_speed * delta)
	var travel := position - before
	if sprite != null:
		sprite.flip_h = travel.x + travel.z > 0.015
		sprite.position.y = 0.67 + absf(sin(_walk_time * 13.0)) * 0.055
		var frame := int(floor(_walk_time * 7.0)) % 2
		if frame != _step_frame:
			_step_frame = frame
			sprite.texture = PixelArt.character_texture(appearance, _step_frame)
	if position.distance_to(destination) <= 0.01:
		position = destination
		grid_coord = next
		_path.pop_front()
		tile_entered.emit(grid_coord)
		if _path.is_empty():
			path_changed.emit(false)


func move_to(target: Vector3i) -> bool:
	if not can_control or grid == null:
		return false
	var goal := Vector3i(target.x, 1, target.z)
	var path := grid.reachable_path(grid_coord, goal)
	if path.is_empty() and goal != grid_coord:
		return false
	_path = path
	if not _path.is_empty() and _path[0] == grid_coord:
		_path.pop_front()
	path_changed.emit(not _path.is_empty())
	return goal == grid_coord or not _path.is_empty()


func try_step(direction: Vector3i) -> bool:
	if not _path.is_empty():
		return false
	var goal := Vector3i(grid_coord.x + direction.x, 1, grid_coord.z + direction.z)
	return move_to(goal)


func stop() -> void:
	_path.clear()
	path_changed.emit(false)


func set_appearance(player_name: String, player_appearance: Dictionary) -> void:
	display_name = player_name.strip_edges() if not player_name.strip_edges().is_empty() else "Fern"
	appearance = player_appearance.duplicate(true)
	if sprite != null:
		sprite.texture = PixelArt.character_texture(appearance)
	if nameplate != null:
		nameplate.text = display_name


func snapshot() -> Dictionary:
	return {
		"name": display_name,
		"appearance": appearance.duplicate(true),
		"coord": [grid_coord.x, grid_coord.y, grid_coord.z],
	}


func restore_snapshot(state: Dictionary) -> void:
	if state.is_empty():
		return
	var coord: Array = state.get("coord", [0, 1, 0])
	var restored := Vector3i(
		int(coord[0]) if coord.size() > 0 else 0,
		1,
		int(coord[2]) if coord.size() > 2 else 0
	)
	grid_coord = restored if grid.is_walkable(restored) else Vector3i(0, 1, 0)
	position = _world_for(grid_coord)
	set_appearance(str(state.get("name", "Fern")), state.get("appearance", appearance))


func _world_for(coord: Vector3i) -> Vector3:
	return grid.world_position(Vector3i(coord.x, 1, coord.z)) + Vector3(0, 0.08, 0)


func _build_visual() -> void:
	sprite = Sprite3D.new()
	sprite.name = "PixelHero"
	sprite.texture = PixelArt.character_texture(appearance)
	sprite.pixel_size = 0.043
	sprite.position.y = 0.67
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(sprite)

	shadow = MeshInstance3D.new()
	shadow.name = "HeroShadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.62, 0.32)
	shadow.mesh = quad
	shadow.rotation.x = -PI * 0.5
	shadow.position.y = 0.015
	var shadow_material := StandardMaterial3D.new()
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.albedo_color = Color(0.03, 0.10, 0.06, 0.34)
	shadow_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	shadow.material_override = shadow_material
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)

	nameplate = Label3D.new()
	nameplate.name = "Name"
	nameplate.text = display_name
	nameplate.position.y = 1.52
	nameplate.font_size = 22
	nameplate.outline_size = 6
	nameplate.modulate = Color("#f3e9c8")
	nameplate.outline_modulate = Color("#172b24")
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.no_depth_test = false
	add_child(nameplate)
