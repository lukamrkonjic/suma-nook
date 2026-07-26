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


func setup(material_library: MaterialLibrary, tile_size: float, water_direction := Vector3(0, 0, -1), asset_library: AssetLibrary = null) -> void:
	name = "NorthernDeliveryPoint"
	_materials = material_library
	_assets = asset_library if asset_library else AssetLibrary.new(material_library)
	var direction := water_direction.normalized()
	approach = _marker("Approach", direction * tile_size * 4.8)
	arrival = _marker("Arrival", direction * tile_size * 1.35)
	package_drop = _marker("PackageDrop", direction * tile_size * 0.38 + Vector3(0, 0.18, 0))
	departure = _marker("Departure", direction * tile_size * 5.3 + Vector3(tile_size * 0.65, 0, 0))
	player_interaction = _marker("PlayerInteraction", direction * tile_size * 0.3)
	camera_interest = _marker("CameraInterest", direction * tile_size * 0.9 + Vector3(0, 0.6, 0))
	add_child(_build_dock(direction, tile_size))
	_package_visual = _build_package()
	_package_visual.position = package_drop.position
	_package_visual.visible = false
	_package_visual.add_to_group("delivery_packages")
	add_child(_package_visual)


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
func _build_dock(direction: Vector3, _tile_size: float) -> Node3D:
	var dock := _assets.instantiate("prop_dock_ferry")
	dock.name = "NorthernFerryDock"
	dock.rotation.y = atan2(direction.x, direction.z)
	return dock


func _build_package() -> Node3D:
	var root := _assets.instantiate("prop_present")
	root.name = "LandParcelPackage"
	return root
