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
var _package_visual: Node3D


func setup(material_library: MaterialLibrary, tile_size: float, water_direction := Vector3(0, 0, -1)) -> void:
	name = "NorthernDeliveryPoint"
	_materials = material_library
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


func _build_dock(direction: Vector3, tile_size: float) -> Node3D:
	var dock := Node3D.new()
	dock.name = "NorthernFerryDock"
	var yaw := atan2(direction.x, direction.z)
	dock.rotation.y = yaw
	for index in 4:
		var plank := _box(
			Vector3(1.05, 0.12, 0.42),
			_materials.material("wood")
		)
		plank.position = Vector3(0, 0.08, 0.72 + index * 0.38)
		dock.add_child(plank)
	for side in [-1.0, 1.0]:
		var post := _cylinder(0.075, 0.075, 0.72, _materials.material("dark_wood"))
		post.position = Vector3(side * 0.45, 0.31, 1.52)
		dock.add_child(post)
	return dock


func _build_package() -> Node3D:
	var root := Node3D.new()
	root.name = "LandParcelPackage"
	var box := _box(Vector3(0.48, 0.34, 0.42), _materials.material("pale_stone"))
	box.position.y = 0.17
	root.add_child(box)
	var ribbon_x := _box(Vector3(0.1, 0.355, 0.44), _materials.material("fabric"))
	ribbon_x.position.y = 0.18
	root.add_child(ribbon_x)
	var ribbon_z := _box(Vector3(0.5, 0.355, 0.09), _materials.material("fabric"))
	ribbon_z.position.y = 0.18
	root.add_child(ribbon_z)
	return root


func _box(size: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	return mesh_instance


func _cylinder(top_radius: float, bottom_radius: float, height: float, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	return mesh_instance
