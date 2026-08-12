class_name VisitorContainerVisualFactory
extends RefCounted
## One collection-aware vocabulary for every visitor gift container. Closely
## related tile collections intentionally share a silhouette and palette, so
## expanding the catalog does not create a one-off prop for every ground tile.

const STYLE_BY_CATEGORY := {
	"meadow": "garden_crock",
	"garden": "garden_crock",
	"farm": "garden_crock",
	"forest": "grove_jar",
	"swamp": "grove_jar",
	"beach": "desert_amphora",
	"desert": "desert_amphora",
	"tundra": "frosted_urn",
	"winter": "frosted_urn",
	"ruins": "stone_reliquary",
	"urban": "stone_reliquary",
	"stone": "stone_reliquary",
	"market": "festival_vase",
}
const STYLE_BY_FAMILY := {
	"living_grove": "grove_jar",
	"waterside": "grove_jar",
	"beach": "desert_amphora",
	"winter": "frosted_urn",
	"stonebound": "stone_reliquary",
	"woodland": "festival_vase",
}
const STYLES := {
	"garden_crock": {
		"name": "Garden Gift Crock",
		"primary": "terracotta_primary",
		"accent": "warm_white",
		"shadow": "terracotta_shadow",
	},
	"grove_jar": {
		"name": "Grove Gift Jar",
		"primary": "moss_primary",
		"accent": "leaf_soft_sage",
		"shadow": "deep_grass",
	},
	"desert_amphora": {
		"name": "Desert Gift Amphora",
		"primary": "sand_light",
		"accent": "terracotta_orange",
		"shadow": "sand_shadow",
	},
	"frosted_urn": {
		"name": "Frosted Gift Urn",
		"primary": "snow_light",
		"accent": "water_foam",
		"shadow": "snow_shadow",
	},
	"stone_reliquary": {
		"name": "Relic Gift Vessel",
		"primary": "stone_mid_light",
		"accent": "gold_primary",
		"shadow": "stone_shadow",
	},
	"festival_vase": {
		"name": "Market Gift Vase",
		"primary": "burnt_red",
		"accent": "gold_primary",
		"shadow": "terracotta_shadow",
	},
}

var palette: PaletteDefinition


func _init(color_palette: PaletteDefinition = null) -> void:
	palette = color_palette if color_palette != null else PaletteDefinition.shared()


func style_for_tile(definition: Defs.TileDefinition) -> Dictionary:
	var category := "meadow"
	var family := "home_meadow"
	if definition != null:
		category = definition.catalog_category
		family = definition.family
	return style_for_context(category, family)


func style_for_context(category: String, family: String) -> Dictionary:
	if category == "":
		category = "meadow"
	if family == "":
		family = "home_meadow"
	var style_id := String(STYLE_BY_CATEGORY.get(
		category,
		STYLE_BY_FAMILY.get(family, "garden_crock")
	))
	var style: Dictionary = (STYLES[style_id] as Dictionary).duplicate(true)
	style["id"] = style_id
	style["collection_id"] = category
	style["collection_name"] = "%s Collection" % category.capitalize()
	return style


func create_for_context(category: String, family: String) -> Node3D:
	var style := style_for_context(category, family)
	var root := Node3D.new()
	root.name = "VisitorContainer_%s" % String(style["id"]).to_pascal_case()
	root.set_meta("visitor_container_style", style.duplicate(true))
	match String(style["id"]):
		"grove_jar":
			_build_grove_jar(root, style)
		"desert_amphora":
			_build_desert_amphora(root, style)
		"frosted_urn":
			_build_frosted_urn(root, style)
		"stone_reliquary":
			_build_stone_reliquary(root, style)
		"festival_vase":
			_build_festival_vase(root, style)
		_:
			_build_garden_crock(root, style)
	return root


func _build_garden_crock(root: Node3D, style: Dictionary) -> void:
	_add_sphere(root, "CrockBody", Vector3(0.22, 0.19, 0.22), 0.2, style.primary)
	_add_cylinder(root, "CrockNeck", 0.13, 0.095, 0.18, 0.43, style.primary)
	_add_rim_and_opening(root, 0.525, 0.12, style.accent, style.shadow)
	for side in [-1.0, 1.0]:
		_add_box(
			root,
			"PaintedLeaf",
			Vector3(0.07, 0.055, 0.025),
			Vector3(side * 0.145, 0.25, -0.16),
			style.accent,
			Vector3(0.0, 0.0, side * 0.28)
		)


func _build_grove_jar(root: Node3D, style: Dictionary) -> void:
	_add_sphere(root, "MossJarBody", Vector3(0.25, 0.17, 0.25), 0.18, style.primary)
	_add_cylinder(root, "MossJarNeck", 0.145, 0.11, 0.13, 0.365, style.primary)
	_add_rim_and_opening(root, 0.44, 0.14, style.accent, style.shadow)
	for index in 3:
		var angle := -0.7 + float(index) * 0.7
		_add_sphere(
			root,
			"LeafMark",
			Vector3(0.045, 0.09, 0.022),
			0.23,
			style.accent,
			Vector3(sin(angle) * 0.11, 0.0, -0.19),
			Vector3(0.0, 0.0, -angle * 0.55)
		)


func _build_desert_amphora(root: Node3D, style: Dictionary) -> void:
	_add_sphere(root, "AmphoraBody", Vector3(0.2, 0.25, 0.2), 0.235, style.primary)
	_add_cylinder(root, "AmphoraNeck", 0.105, 0.075, 0.24, 0.53, style.primary)
	_add_cylinder(root, "DesertBand", 0.205, 0.205, 0.045, 0.29, style.accent)
	_add_rim_and_opening(root, 0.665, 0.115, style.accent, style.shadow)
	for side in [-1.0, 1.0]:
		_add_torus(
			root,
			"AmphoraHandle",
			0.075,
			0.017,
			Vector3(side * 0.16, 0.49, 0.0),
			style.accent,
			Vector3(PI * 0.5, 0.0, 0.0)
		)


func _build_frosted_urn(root: Node3D, style: Dictionary) -> void:
	_add_sphere(root, "FrostedUrnBody", Vector3(0.245, 0.17, 0.245), 0.19, style.primary)
	_add_cylinder(root, "IceBand", 0.22, 0.22, 0.055, 0.27, style.accent)
	_add_cylinder(root, "UrnNeck", 0.135, 0.105, 0.12, 0.39, style.primary)
	_add_rim_and_opening(root, 0.46, 0.135, style.accent, style.shadow)
	_add_cylinder(root, "SnowCap", 0.09, 0.15, 0.08, 0.51, style.accent)
	_add_sphere(root, "SnowCapFinial", Vector3.ONE * 0.045, 0.58, style.primary)


func _build_stone_reliquary(root: Node3D, style: Dictionary) -> void:
	_add_box(
		root,
		"ReliquaryBody",
		Vector3(0.34, 0.31, 0.3),
		Vector3(0.0, 0.185, 0.0),
		style.primary,
		Vector3(0.0, 0.08, 0.0)
	)
	_add_cylinder(root, "ReliquaryNeck", 0.12, 0.1, 0.14, 0.42, style.primary)
	_add_rim_and_opening(root, 0.5, 0.12, style.accent, style.shadow)
	_add_box(
		root, "GoldRune", Vector3(0.045, 0.19, 0.025),
		Vector3(0.0, 0.22, -0.165), style.accent
	)
	_add_box(
		root, "GoldRune", Vector3(0.17, 0.045, 0.025),
		Vector3(0.0, 0.24, -0.165), style.accent
	)


func _build_festival_vase(root: Node3D, style: Dictionary) -> void:
	_add_sphere(root, "FestivalBody", Vector3(0.22, 0.22, 0.22), 0.225, style.primary)
	_add_cylinder(root, "GoldLowerBand", 0.205, 0.205, 0.035, 0.2, style.accent)
	_add_cylinder(root, "FestivalNeck", 0.115, 0.085, 0.2, 0.48, style.primary)
	_add_cylinder(root, "GoldUpperBand", 0.12, 0.12, 0.035, 0.42, style.accent)
	_add_rim_and_opening(root, 0.595, 0.125, style.accent, style.shadow)


func _add_rim_and_opening(
	root: Node3D,
	y: float,
	radius: float,
	rim_token: String,
	opening_token: String
) -> void:
	_add_cylinder(root, "PaintedRim", radius, radius, 0.035, y, rim_token)
	_add_cylinder(
		root, "VesselOpening", radius * 0.62, radius * 0.62,
		0.008, y + 0.021, opening_token
	)


func _add_sphere(
	root: Node3D,
	name: String,
	scale: Vector3,
	y: float,
	token: String,
	position := Vector3.ZERO,
	rotation := Vector3.ZERO
) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 14
	mesh.rings = 7
	var node := _mesh_node(root, name, mesh, token, position, rotation)
	node.position.y += y
	node.scale = scale
	return node


func _add_cylinder(
	root: Node3D,
	name: String,
	bottom_radius: float,
	top_radius: float,
	height: float,
	y: float,
	token: String
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom_radius
	mesh.top_radius = top_radius
	mesh.height = height
	mesh.radial_segments = 14
	return _mesh_node(root, name, mesh, token, Vector3(0.0, y, 0.0))


func _add_box(
	root: Node3D,
	name: String,
	size: Vector3,
	position: Vector3,
	token: String,
	rotation := Vector3.ZERO
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh_node(root, name, mesh, token, position, rotation)


func _add_torus(
	root: Node3D,
	name: String,
	ring_radius: float,
	pipe_radius: float,
	position: Vector3,
	token: String,
	rotation := Vector3.ZERO
) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.005, ring_radius - pipe_radius)
	mesh.outer_radius = ring_radius + pipe_radius
	mesh.rings = 12
	mesh.ring_segments = 6
	return _mesh_node(root, name, mesh, token, position, rotation)


func _mesh_node(
	root: Node3D,
	name: String,
	mesh: Mesh,
	token: String,
	position := Vector3.ZERO,
	rotation := Vector3.ZERO
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.position = position
	node.rotation = rotation
	var material := StandardMaterial3D.new()
	material.albedo_color = palette.color(token, Color.MAGENTA)
	material.roughness = 0.86
	node.material_override = material
	root.add_child(node)
	return node
