extends Node3D
class_name GridRenderer

const ItemScene := preload("res://scenes/build_item.tscn")

signal item_hovered(item: BuildItem, active: bool)

var grid: GridManager
var data: GameData
var nodes_by_key: Dictionary = {}
var signatures: Dictionary = {}


func setup(grid_manager: GridManager, game_data: GameData) -> void:
	grid = grid_manager
	data = game_data
	grid.grid_changed.connect(sync_from_grid)
	sync_from_grid()


func sync_from_grid() -> void:
	var wanted: Dictionary = {}
	for coord: Vector3i in grid.ground:
		var key := "ground:%d:%d" % [coord.x, coord.z]
		var definition_id: StringName = grid.ground[coord]
		var signature := "%s:%s" % [definition_id, coord]
		wanted[key] = true
		if signatures.get(key, "") != signature:
			_replace_node(key, definition_id, key, coord, 0)
			signatures[key] = signature
	for instance_id: String in grid.props:
		var state: Dictionary = grid.props[instance_id]
		var coord := GridManager.array_to_coord(state.get("coord", [0, 1, 0]))
		var definition_id := StringName(str(state.get("definition_id", "")))
		var rotation_value := int(state.get("rotation", 0))
		var key := "prop:%s" % instance_id
		var signature := "%s:%s:%d" % [definition_id, coord, rotation_value]
		wanted[key] = true
		if signatures.get(key, "") != signature:
			_replace_node(key, definition_id, instance_id, coord, rotation_value)
			signatures[key] = signature
	for key: String in nodes_by_key.keys():
		if not wanted.has(key):
			(nodes_by_key[key] as Node).queue_free()
			nodes_by_key.erase(key)
			signatures.erase(key)


func _replace_node(
		key: String,
		definition_id: StringName,
		instance_id: String,
		coord: Vector3i,
		rotation_value: int
	) -> void:
	if nodes_by_key.has(key):
		(nodes_by_key[key] as Node).queue_free()
	var definition := data.item(definition_id)
	if definition == null:
		return
	var item := ItemScene.instantiate() as BuildItem
	add_child(item)
	item.setup(definition, instance_id, coord, rotation_value, grid.tile_size)
	item.position = grid.world_position(coord)
	item.hovered.connect(func(target: BuildItem, active: bool) -> void:
		item_hovered.emit(target, active))
	nodes_by_key[key] = item


func node_for_instance(instance_id: String) -> BuildItem:
	return nodes_by_key.get("prop:%s" % instance_id) as BuildItem


func node_for_ground(coord: Vector3i) -> BuildItem:
	return nodes_by_key.get("ground:%d:%d" % [coord.x, coord.z]) as BuildItem

