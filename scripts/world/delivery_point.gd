class_name DeliveryPoint
extends Node3D
## World-authored transforms for interchangeable arrival presentations.
## The active ferry contains no hard-coded world coordinates.

var approach: Marker3D
var arrival: Marker3D
var package_drop: Marker3D
var departure: Marker3D
var player_interaction: Marker3D
var camera_interest: Marker3D

var _materials: MaterialLibrary
var _assets: AssetLibrary
var _package_visual: Node3D
var _grid: WorldGrid
var _dock_instance_id := 0
var _dock_coord := Vector2i.ZERO
var _dock_elevation := 0


func setup(
	material_library: MaterialLibrary,
	tile_size: float,
	water_direction := Vector3(0, 0, -1),
	asset_library: AssetLibrary = null,
	world_grid: WorldGrid = null
) -> void:
	name = "NorthernDeliveryPoint"
	_materials = material_library
	_assets = asset_library if asset_library else AssetLibrary.new(material_library)
	_grid = world_grid
	var direction := water_direction.normalized()
	approach = _marker("Approach", direction * tile_size * 4.8)
	arrival = _marker("Arrival", direction * tile_size * 1.35)
	# Parcel rests on the landward half of the water-centered dock so the
	# keeper can reach it without stepping into water.
	package_drop = _marker("PackageDrop", -direction * tile_size * 0.38 + Vector3(0, 0.18, 0))
	departure = _marker("Departure", direction * tile_size * 5.3 + Vector3(tile_size * 0.65, 0, 0))
	player_interaction = _marker("PlayerInteraction", -direction * tile_size * 0.3)
	camera_interest = _marker("CameraInterest", direction * tile_size * 0.9 + Vector3(0, 0.6, 0))
	_package_visual = _build_package()
	_package_visual.position = package_drop.position
	_package_visual.visible = false
	_package_visual.add_to_group("delivery_packages")
	add_child(_package_visual)
	if _grid != null:
		_grid.slot_changed.connect(_on_slot_changed)
		_sync_to_dock()


func _on_slot_changed(coord: Vector2i, elevation: int) -> void:
	if (
		_dock_instance_id == 0
		or (coord == _dock_coord and elevation == _dock_elevation)
	):
		_sync_to_dock()


func _sync_to_dock() -> void:
	if _grid == null:
		return
	if _dock_instance_id > 0:
		var cached_state := _grid.cell_at(_dock_coord, _dock_elevation)
		if cached_state != null:
			for structure: WorldGrid.StructureState in cached_state.structures:
				if structure.instance_id == _dock_instance_id:
					_apply_dock_transform(
						_dock_coord,
						_dock_elevation,
						cached_state,
						structure
					)
					return
		_dock_instance_id = 0
	for slot: Dictionary in _grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			if structure.structure_id != "struct_dock":
				continue
			_dock_instance_id = structure.instance_id
			_dock_coord = slot["coord"]
			_dock_elevation = int(slot["elevation"])
			_apply_dock_transform(
				_dock_coord,
				_dock_elevation,
				state,
				structure
			)
			return


func _apply_dock_transform(
	coord: Vector2i,
	elevation: int,
	state: WorldGrid.CellState,
	structure: WorldGrid.StructureState
) -> void:
	position = (
		_grid.cell_to_world(coord, elevation)
		+ _grid.structure_local_transform_in_cell(
			state,
			structure.instance_id
		).origin
	)
	# Marker transforms were authored for the dock's default outward rotation
	# (2). Preserve that alignment when the object is rotated.
	rotation.y = (structure.rotation - 2) * PI * 0.5


func show_package(payload: LandParcelPayload) -> void:
	_package_visual.set_meta("payload", payload)
	_package_visual.visible = true
	var base_scale := Vector3.ONE
	_package_visual.scale = Vector3(0.25, 0.25, 0.25)
	var tween := _package_visual.create_tween()
	tween.tween_property(_package_visual, "scale", base_scale * 1.08, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_package_visual, "scale", base_scale, 0.12)


func hide_package() -> void:
	_package_visual.visible = false
	_package_visual.remove_meta("payload")


func package_is_visible() -> bool:
	return _package_visual != null and _package_visual.visible


func package_node() -> Node3D:
	return _package_visual


func _marker(marker_name: String, marker_position: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = marker_position
	add_child(marker)
	return marker


## Rounded GLB dock and parcel (assets/3d/reworked) — no runtime primitives.
func _build_package() -> Node3D:
	var root := _assets.instantiate("prop_present")
	root.name = "LandParcelPackage"
	return root
