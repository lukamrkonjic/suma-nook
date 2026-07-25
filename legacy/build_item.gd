extends Node3D
# legacy-disabled class_name BuildItem

signal hovered(item: BuildItem, active: bool)

const Factory := preload("res://scripts/visual_factory.gd")

var definition: BuildItemDefinition
var instance_id := ""
var grid_coord := Vector3i.ZERO
var rotation_quarters := 0
var is_preview := false
var is_valid_preview := true
var _visual: Node3D
var _area: Area3D
var _special_time := 0.0


func setup(
		item_definition: BuildItemDefinition,
		id: String,
		coord: Vector3i,
		rotation_value: int,
		tile_size: float,
		preview := false
	) -> void:
	definition = item_definition
	instance_id = id
	grid_coord = coord
	rotation_quarters = posmod(rotation_value, 4)
	is_preview = preview
	name = "Item_%s_%s" % [definition.id, instance_id]
	_visual = Factory.build_visual(definition.visual_kind, definition.category)
	add_child(_visual)
	rotation.y = float(rotation_quarters) * PI * 0.5
	if not preview:
		_create_pick_area(tile_size)
	else:
		set_preview_valid(true)
	set_process(definition.visual_kind == &"root_arch" and not preview)


func _process(delta: float) -> void:
	_special_time += delta
	if definition == null or definition.visual_kind != &"root_arch" or _visual == null:
		return
	for child: Node in _visual.find_children("Leaf", "MeshInstance3D", true, false):
		var leaf := child as MeshInstance3D
		var phase := float(leaf.get_index()) * 0.9
		leaf.rotation.z = 0.28 + sin(_special_time * 1.3 + phase) * 0.08


func _create_pick_area(tile_size: float) -> void:
	_area = Area3D.new()
	_area.name = "PickArea"
	_area.collision_layer = 1
	_area.collision_mask = 0
	_area.set_meta("build_item", self)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var fp := definition.rotated_footprint(rotation_quarters)
	var height := 0.36 if definition.is_ground() else 1.7
	box.size = Vector3(float(fp.x) * tile_size * 0.88, height, float(fp.y) * tile_size * 0.88)
	shape.shape = box
	shape.position.y = -0.06 if definition.is_ground() else height * 0.5
	_area.add_child(shape)
	add_child(_area)
	_area.mouse_entered.connect(func() -> void: hovered.emit(self, true))
	_area.mouse_exited.connect(func() -> void: hovered.emit(self, false))


func set_preview_valid(valid: bool) -> void:
	is_valid_preview = valid
	_set_overlay(Factory.overlay_material(valid))
	for child: Node in _visual.find_children("*", "Sprite3D", true, false):
		(child as Sprite3D).modulate = Color("#b9e67b") if valid else Color("#e67373")


func set_hovered(active: bool) -> void:
	if is_preview:
		return
	_set_overlay(Factory.hover_material() if active else null)
	for child: Node in _visual.find_children("*", "Sprite3D", true, false):
		(child as Sprite3D).modulate = Color("#fff0a6") if active else Color.WHITE


func clear_overlay() -> void:
	_set_overlay(null)
	for child: Node in _visual.find_children("*", "Sprite3D", true, false):
		(child as Sprite3D).modulate = Color.WHITE


func _set_overlay(material: Material) -> void:
	if _visual == null:
		return
	for child: Node in _visual.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).material_overlay = material


func animate_placed() -> void:
	scale = Vector3.ONE * 0.96
	position.y += 0.22
	var final_y := position.y - 0.22
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", final_y, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ONE * 1.035, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(self, "scale", Vector3.ONE, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func animate_pickup() -> void:
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y + 0.16, 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
