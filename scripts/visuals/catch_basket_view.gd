class_name CatchBasketView
extends Node3D
## The physical Catch Basket beside the fishing keeper. Pure presentation: it
## renders the basket and a miniature per haul (tied tile stacks, model
## minis, a glowing keepsake charm) and never makes gameplay decisions.

var _basket: CatchBasketAdapter
var _registries: Registries
var _tray_root: Node3D
var _bob_time := 0.0


func setup(basket: CatchBasketAdapter, registries: Registries) -> void:
	_basket = basket
	_registries = registries
	_build_shell()
	_tray_root = Node3D.new()
	_tray_root.name = "Trays"
	add_child(_tray_root)
	_basket.basket_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	_bob_time += delta
	# Keepsake charms hover gently; everything else stays put.
	for charm: Node3D in get_tree().get_nodes_in_group("basket_keepsake_charm"):
		if charm.is_inside_tree() and is_ancestor_of(charm):
			charm.position.y = 0.34 + sin(_bob_time * 2.2) * 0.03


func _build_shell() -> void:
	var body := MeshInstance3D.new()
	body.name = "BasketBody"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.62, 0.2, 0.44)
	body.mesh = mesh
	body.position.y = 0.1
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.52, 0.38, 0.24)
	wood.roughness = 0.92
	body.material_override = wood
	add_child(body)
	var rim := MeshInstance3D.new()
	rim.name = "BasketRim"
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(0.68, 0.05, 0.5)
	rim.mesh = rim_mesh
	rim.position.y = 0.21
	var rim_material := StandardMaterial3D.new()
	rim_material.albedo_color = Color(0.62, 0.47, 0.3)
	rim_material.roughness = 0.9
	rim.material_override = rim_material
	add_child(rim)


func _refresh() -> void:
	if _tray_root == null:
		return
	for child in _tray_root.get_children():
		child.queue_free()
	var slot_offsets := [
		Vector3(-0.19, 0.24, 0.0),
		Vector3(0.0, 0.24, 0.0),
		Vector3(0.19, 0.24, 0.0),
	]
	for haul_index in _basket.hauls.size():
		if haul_index >= slot_offsets.size():
			break
		var haul: FishingHaul = _basket.hauls[haul_index]
		var tray := Node3D.new()
		tray.name = "Haul%d" % haul.haul_id
		tray.position = slot_offsets[haul_index]
		_tray_root.add_child(tray)
		_fill_tray(tray, haul)


func _fill_tray(tray: Node3D, haul: FishingHaul) -> void:
	var entry_offset := 0.0
	for entry: FishingReward in haul.entries:
		var mini := (
			_tile_stack_mini(entry)
			if entry.form == FishingReward.FORM_TILE_BUNDLE
			else _model_mini(entry)
		)
		mini.position.y = entry_offset
		tray.add_child(mini)
		entry_offset += 0.075
	if haul.keepsake != null:
		tray.add_child(_keepsake_charm())


## A tied miniature stack of tiles — taller stacks read as bigger bundles.
func _tile_stack_mini(entry: FishingReward) -> Node3D:
	var mini := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var layers := clampi(entry.quantity, 1, 8)
	mesh.size = Vector3(0.12, 0.02 + 0.012 * layers, 0.12)
	mini.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = _rarity_tint(entry.rarity, Color(0.55, 0.66, 0.42))
	material.roughness = 0.85
	mini.material_override = material
	return mini


## A neutral little monument for a caught model — presentation only ever
## hints at the piece; the real scene appears when it is placed.
func _model_mini(entry: FishingReward) -> Node3D:
	var mini := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.045
	mesh.bottom_radius = 0.06
	mesh.height = 0.11
	mini.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = _rarity_tint(entry.rarity, Color(0.72, 0.65, 0.5))
	material.roughness = 0.8
	mini.material_override = material
	return mini


func _keepsake_charm() -> Node3D:
	var charm := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	charm.mesh = mesh
	charm.position.y = 0.34
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.9, 0.55)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.85, 0.45)
	material.emission_energy_multiplier = 1.6
	charm.material_override = material
	charm.add_to_group("basket_keepsake_charm")
	return charm


func _rarity_tint(rarity: String, base: Color) -> Color:
	match rarity:
		"uncommon":
			return base.lerp(Color(0.5, 0.7, 0.95), 0.35)
		"rare":
			return base.lerp(Color(0.85, 0.6, 0.95), 0.45)
	return base
