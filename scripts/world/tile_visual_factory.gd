class_name TileVisualFactory
extends RefCounted
## Converts data-defined tile behavior profiles into scene presentation.
## Renderers depend on profiles, never on particular content IDs.

const GROUND_LAYER := 1
const BLOCKER_LAYER := 1

var assets: AssetLibrary
var grid: WorldGrid


func _init(asset_library: AssetLibrary, world_grid: WorldGrid) -> void:
	assets = asset_library
	grid = world_grid


func instantiate_visual(def: Defs.TileDefinition) -> Node3D:
	if def.render_profile == "continuous_water":
		var root := Node3D.new()
		root.name = def.id
		root.add_child(assets.instantiate("tile_water_floor"))
		return root
	return assets.instantiate(def.asset_id)


func add_collision(
	holder: Node3D,
	def: Defs.TileDefinition,
	rotation_quarters: int
) -> void:
	match def.collision_profile:
		"flat":
			if def.walkable:
				_add_box(
					holder,
					Vector3(grid.tile_size, 0.9, grid.tile_size),
					Vector3(0.0, -0.45, 0.0),
					GROUND_LAYER
				)
		"pond_basin":
			if def.walkable:
				_add_box(
					holder,
					Vector3(grid.tile_size, 0.9, grid.tile_size),
					Vector3(0.0, -0.45, 0.0),
					GROUND_LAYER
				)
			var offset := Vector3(0.14, 0.4, 0.14).rotated(
				Vector3.UP,
				rotation_quarters * PI * 0.5
			)
			_add_box(holder, Vector3(1.35, 0.8, 1.35), offset, BLOCKER_LAYER)
		"none":
			pass


func _add_box(
	holder: Node3D,
	size: Vector3,
	position: Vector3,
	layer: int
) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = position
	body.add_child(shape)
	holder.add_child(body)
