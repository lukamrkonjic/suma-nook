extends RefCounted
class_name VisualFactory

# A bright, original toy-diorama palette. Geometry stays deliberately simple, while
# higher segment counts and native-resolution rendering keep the silhouettes soft.
const COLORS := {
	"lime": Color("#93a92d"),
	"lime_light": Color("#b6c43b"),
	"leaf": Color("#718d35"),
	"leaf_dark": Color("#486328"),
	"mint": Color("#91bd79"),
	"soil": Color("#805333"),
	"soil_dark": Color("#5d3826"),
	"honey": Color("#d99632"),
	"honey_light": Color("#edb94f"),
	"terracotta": Color("#c85b2c"),
	"terracotta_dark": Color("#923b27"),
	"stone": Color("#c9bca9"),
	"stone_light": Color("#e3d8c7"),
	"stone_dark": Color("#93877c"),
	"water": Color("#74beb4"),
	"water_light": Color("#bce2d4"),
	"cream": Color("#f2ead3"),
	"ink": Color("#4c3c32"),
	"pink": Color("#d77ca1"),
	"violet": Color("#9e75be"),
	"gold": Color("#f2ae26"),
	"ember": Color("#f17a2b"),
}

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}


static func build_visual(kind: StringName, category: StringName = &"decor") -> Node3D:
	var root := Node3D.new()
	root.name = "ToyVisual"
	match String(kind):
		"ground_grass": _ground_grass(root)
		"ground_loam": _ground_planks(root)
		"ground_stone": _ground_stone(root)
		"ground_water": _ground_water(root)
		"sapling": _tree(root)
		"berry_bush": _bush(root)
		"moonflowers": _flowers(root)
		"moss_rock": _rock(root)
		"root_bench": _bench(root)
		"glow_lantern": _lantern(root)
		"twig_fence": _fence(root)
		"seed_crate": _crate(root)
		"old_stump": _stump(root)
		"mushroom_ring": _mushrooms(root)
		"way_sign": _sign(root)
		"root_arch": _arch(root)
		"tea_table": _table(root)
		"stone_planter": _planter(root)
		"wish_lantern": _beacon(root)
		"still_bell": _hushbell(root)
		_: _unknown(root, category)
	return root


static func coin_color(token_id: StringName) -> Color:
	match token_id:
		&"hearth_coin": return COLORS.ember
		&"tide_coin": return COLORS.water
		_: return COLORS.lime_light


static func material(key: String, color: Color, emission := Color.TRANSPARENT) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.82
	mat.metallic = 0.0
	if emission.a > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = 0.55
	_materials[key] = mat
	return mat


static func transparent_material(key: String, color: Color) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.roughness = 0.28
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	_materials[key] = mat
	return mat


static func overlay_material(valid: bool, alpha := 0.32) -> StandardMaterial3D:
	var key := "preview_good" if valid else "preview_bad"
	if _materials.has(key):
		return _materials[key]
	var color := Color(0.56, 0.78, 0.34, alpha) if valid else Color(0.95, 0.32, 0.28, alpha)
	var mat := transparent_material(key, color)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.35
	return mat


static func hover_material() -> StandardMaterial3D:
	var mat := transparent_material("hover", Color(1.0, 0.86, 0.32, 0.20))
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color("#ffe267")
	mat.emission_energy_multiplier = 0.28
	return mat


static func _part(
		parent: Node3D,
		mesh: Mesh,
		mat: Material,
		pos: Vector3,
		rot := Vector3.ZERO,
		scale := Vector3.ONE,
		part_name := "Part"
	) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	instance.rotation = rot
	instance.scale = scale
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	return instance


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _beveled_box(size: Vector3, bevel := 0.05) -> ArrayMesh:
	var safe_bevel := minf(bevel, minf(size.x, minf(size.y, size.z)) * 0.42)
	var key := "bevel:%.3f:%.3f:%.3f:%.3f" % [size.x, size.y, size.z, safe_bevel]
	if _meshes.has(key):
		return _meshes[key]
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var bx := hx - safe_bevel
	var by := hy - safe_bevel
	var bz := hz - safe_bevel
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Six inset faces.
	_add_quad(surface, [Vector3(-bx, hy, -bz), Vector3(bx, hy, -bz), Vector3(bx, hy, bz), Vector3(-bx, hy, bz)])
	_add_quad(surface, [Vector3(-bx, -hy, bz), Vector3(bx, -hy, bz), Vector3(bx, -hy, -bz), Vector3(-bx, -hy, -bz)])
	_add_quad(surface, [Vector3(hx, -by, -bz), Vector3(hx, -by, bz), Vector3(hx, by, bz), Vector3(hx, by, -bz)])
	_add_quad(surface, [Vector3(-hx, -by, bz), Vector3(-hx, -by, -bz), Vector3(-hx, by, -bz), Vector3(-hx, by, bz)])
	_add_quad(surface, [Vector3(-bx, -by, hz), Vector3(-bx, by, hz), Vector3(bx, by, hz), Vector3(bx, -by, hz)])
	_add_quad(surface, [Vector3(bx, -by, -hz), Vector3(bx, by, -hz), Vector3(-bx, by, -hz), Vector3(-bx, -by, -hz)])

	# Twelve chamfered edges.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			_add_quad(surface, [
				Vector3(sx * hx, sy * by, -bz), Vector3(sx * hx, sy * by, bz),
				Vector3(sx * bx, sy * hy, bz), Vector3(sx * bx, sy * hy, -bz),
			])
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_quad(surface, [
				Vector3(sx * hx, -by, sz * bz), Vector3(sx * bx, -by, sz * hz),
				Vector3(sx * bx, by, sz * hz), Vector3(sx * hx, by, sz * bz),
			])
	for sy: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_quad(surface, [
				Vector3(-bx, sy * hy, sz * bz), Vector3(-bx, sy * by, sz * hz),
				Vector3(bx, sy * by, sz * hz), Vector3(bx, sy * hy, sz * bz),
			])

	# Eight tiny corner facets complete the silhouette.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				_add_triangle(surface, [
					Vector3(sx * hx, sy * by, sz * bz),
					Vector3(sx * bx, sy * hy, sz * bz),
					Vector3(sx * bx, sy * by, sz * hz),
				])
	surface.generate_normals()
	var result := surface.commit()
	_meshes[key] = result
	return result


static func _add_quad(surface: SurfaceTool, raw_vertices: Array[Vector3]) -> void:
	var vertices: Array[Vector3] = raw_vertices.duplicate()
	var center: Vector3 = (vertices[0] + vertices[1] + vertices[2] + vertices[3]) * 0.25
	var normal: Vector3 = (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0])
	if normal.dot(center) < 0.0:
		vertices.reverse()
	for index: int in [0, 1, 2, 0, 2, 3]:
		surface.add_vertex(vertices[index])


static func _add_triangle(surface: SurfaceTool, raw_vertices: Array[Vector3]) -> void:
	var vertices: Array[Vector3] = raw_vertices.duplicate()
	var center: Vector3 = (vertices[0] + vertices[1] + vertices[2]) / 3.0
	var normal: Vector3 = (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0])
	if normal.dot(center) < 0.0:
		vertices.reverse()
	for vertex: Vector3 in vertices:
		surface.add_vertex(vertex)


static func _cylinder(top: float, bottom: float, height: float, segments := 12) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh


static func _sphere(radius: float, height_scale := 1.0, segments := 12) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0 * height_scale
	mesh.radial_segments = segments
	mesh.rings = 6
	return mesh


static func _tile_base(root: Node3D, side: Color, top: Color) -> void:
	_part(root, _beveled_box(Vector3(1.78, 0.46, 1.78), 0.075), material("side_%s" % side.to_html(), side),
		Vector3(0, -0.23, 0), Vector3.ZERO, Vector3.ONE, "BlockSide")
	_part(root, _beveled_box(Vector3(1.80, 0.09, 1.80), 0.025), material("top_%s" % top.to_html(), top),
		Vector3(0, 0.025, 0), Vector3.ZERO, Vector3.ONE, "BlockTop")


static func _ground_grass(root: Node3D) -> void:
	_tile_base(root, Color("#7d8c22"), COLORS.lime)
	var tuft_positions := [Vector2(-0.48, -0.36), Vector2(0.43, 0.28), Vector2(-0.12, 0.52)]
	for i: int in tuft_positions.size():
		var x: float = tuft_positions[i].x
		var z: float = tuft_positions[i].y
		var tuft := Node3D.new()
		tuft.position = Vector3(x, 0.10, z)
		root.add_child(tuft)
		for blade: int in 3:
			_part(tuft, _cylinder(0.0, 0.065, 0.24 + blade * 0.035, 7),
				material("grass_blade", COLORS.lime_light),
				Vector3((blade - 1) * 0.075, 0.12, 0),
				Vector3(0.0, float(blade) * 0.8, (blade - 1) * 0.16), Vector3.ONE, "Grass")


static func _ground_planks(root: Node3D) -> void:
	_part(root, _beveled_box(Vector3(1.78, 0.46, 1.78), 0.075), material("plank_side", Color("#a65d1e")),
		Vector3(0, -0.23, 0), Vector3.ZERO, Vector3.ONE, "BlockSide")
	for i: int in 3:
		_part(root, _beveled_box(Vector3(1.75, 0.10, 0.55), 0.025), material("plank_top_%d" % (i % 2),
			COLORS.honey_light if i % 2 == 0 else COLORS.honey),
			Vector3(0, 0.025, -0.59 + i * 0.59), Vector3.ZERO, Vector3.ONE, "Plank")


static func _ground_stone(root: Node3D) -> void:
	_tile_base(root, Color("#9c8978"), COLORS.stone_light)
	_part(root, _box(Vector3(0.025, 0.016, 1.70)), material("stone_seam", Color("#b1a392")),
		Vector3(0.18, 0.078, 0), Vector3.ZERO, Vector3.ONE, "Seam")
	_part(root, _box(Vector3(1.70, 0.016, 0.025)), material("stone_seam", Color("#b1a392")),
		Vector3(0, 0.078, -0.24), Vector3.ZERO, Vector3.ONE, "Seam")


static func _ground_water(root: Node3D) -> void:
	_tile_base(root, Color("#498b84"), Color("#6eb7ad"))
	var water := _part(root, _box(Vector3(1.78, 0.15, 1.78)),
		transparent_material("water_surface", Color(0.56, 0.84, 0.79, 0.68)),
		Vector3(0, 0.10, 0), Vector3.ZERO, Vector3.ONE, "Water")
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_part(root, _cylinder(0.20, 0.20, 0.025, 12), material("lily", Color("#779e3e")),
		Vector3(-0.38, 0.195, 0.30), Vector3.ZERO, Vector3.ONE, "LilyPad")


static func _tree(root: Node3D) -> void:
	_part(root, _cylinder(0.11, 0.19, 1.16, 10), material("wood", Color("#8d5c34")),
		Vector3(0, 0.58, 0), Vector3(0.05, 0, -0.06), Vector3.ONE, "Trunk")
	var clumps := [
		Vector3(0, 1.25, 0), Vector3(-0.30, 1.10, 0.08),
		Vector3(0.29, 1.08, -0.05), Vector3(-0.04, 1.53, 0.04),
	]
	for i: int in clumps.size():
		_part(root, _sphere(0.36 - i * 0.018, 0.82, 12),
			material("canopy_%d" % (i % 3), [COLORS.leaf_dark, COLORS.leaf, COLORS.mint][i % 3]),
			clumps[i], Vector3.ZERO, Vector3(1.12, 0.92, 1.02), "Canopy")


static func _bush(root: Node3D) -> void:
	for i: int in 6:
		var angle := float(i) * TAU / 6.0
		_part(root, _sphere(0.30, 0.76, 12),
			material("bush_%d" % (i % 2), COLORS.leaf if i % 2 == 0 else Color("#829a45")),
			Vector3(cos(angle) * 0.25, 0.34 + (i % 2) * 0.06, sin(angle) * 0.25),
			Vector3.ZERO, Vector3(1.10, 0.90, 1.0), "Bush")
	for i: int in 5:
		var angle := float(i) * 1.31
		_part(root, _sphere(0.055, 0.95, 8), material("pomberry", Color("#d87852")),
			Vector3(cos(angle) * 0.34, 0.48 + (i % 2) * 0.10, sin(angle) * 0.30),
			Vector3.ZERO, Vector3.ONE, "Berry")


static func _flowers(root: Node3D) -> void:
	for i: int in 3:
		var x := -0.28 + i * 0.28
		var z := 0.10 if i % 2 == 0 else -0.08
		var height := 0.48 + i * 0.05
		_part(root, _cylinder(0.014, 0.021, height, 7), material("stem", COLORS.leaf),
			Vector3(x, height * 0.5, z), Vector3.ZERO, Vector3.ONE, "Stem")
		for petal: int in 5:
			var angle := float(petal) * TAU / 5.0
			_part(root, _sphere(0.105, 0.40, 10), material("petal_%d" % i,
				[Color("#f1a2bd"), COLORS.violet, Color("#f5d36d")][i]),
				Vector3(x + cos(angle) * 0.095, height + 0.025, z + sin(angle) * 0.095),
				Vector3.ZERO, Vector3(0.78, 0.42, 1.0), "Petal")
		_part(root, _sphere(0.065, 0.50, 9), material("flower_center", Color("#f0b12f")),
			Vector3(x, height + 0.035, z), Vector3.ZERO, Vector3.ONE, "Center")


static func _rock(root: Node3D) -> void:
	_part(root, _sphere(0.44, 0.70, 10), material("rock", COLORS.stone),
		Vector3(0, 0.30, 0), Vector3(0.08, 0.32, -0.08), Vector3(1.25, 0.84, 1.0), "Rock")
	_part(root, _sphere(0.23, 0.42, 10), material("rock_moss", COLORS.mint),
		Vector3(-0.10, 0.54, 0), Vector3.ZERO, Vector3(1.50, 0.46, 1.12), "Moss")


static func _bench(root: Node3D) -> void:
	var wood := material("honeywood", Color("#c37d32"))
	var dark := material("honeywood_dark", Color("#8c5227"))
	_part(root, _box(Vector3(1.38, 0.16, 0.48)), wood, Vector3(0, 0.54, 0), Vector3.ZERO, Vector3.ONE, "Seat")
	_part(root, _box(Vector3(1.38, 0.48, 0.12)), wood, Vector3(0, 0.84, 0.19),
		Vector3(-0.06, 0, 0), Vector3.ONE, "Back")
	for x: float in [-0.50, 0.50]:
		_part(root, _box(Vector3(0.14, 0.54, 0.32)), dark, Vector3(x, 0.27, 0), Vector3.ZERO, Vector3.ONE, "Leg")


static func _lantern(root: Node3D) -> void:
	var frame := material("lantern_frame", Color("#5a4938"))
	_part(root, _box(Vector3(0.50, 0.50, 0.50)), frame, Vector3(0, 0.45, 0), Vector3.ZERO, Vector3.ONE, "Frame")
	_part(root, _box(Vector3(0.37, 0.37, 0.37)), material("lantern_glass", Color("#ffc44d"), Color("#ffb62f")),
		Vector3(0, 0.46, 0), Vector3.ZERO, Vector3.ONE, "Glow")
	_part(root, _cylinder(0.10, 0.30, 0.20, 8), frame, Vector3(0, 0.80, 0), Vector3.ZERO, Vector3.ONE, "Roof")
	_add_light(root, Color("#ffbe49"), Vector3(0, 0.48, 0), 1.25, 3.2)


static func _fence(root: Node3D) -> void:
	var wood := material("rail_wood", Color("#b66c2d"))
	for x: float in [-0.58, 0.58]:
		_part(root, _cylinder(0.055, 0.085, 0.92, 9), wood, Vector3(x, 0.46, 0), Vector3.ZERO, Vector3.ONE, "Post")
		_part(root, _sphere(0.10, 0.70, 9), wood, Vector3(x, 0.94, 0), Vector3.ZERO, Vector3.ONE, "Cap")
	for y: float in [0.34, 0.68]:
		_part(root, _box(Vector3(1.28, 0.12, 0.12)), wood, Vector3(0, y, 0), Vector3.ZERO, Vector3.ONE, "Rail")


static func _crate(root: Node3D) -> void:
	var wood := material("crate_wood", Color("#c88738"))
	var trim := material("crate_trim", Color("#8e5126"))
	_part(root, _box(Vector3(0.82, 0.66, 0.82)), wood, Vector3(0, 0.33, 0), Vector3.ZERO, Vector3.ONE, "Crate")
	for y: float in [0.08, 0.58]:
		_part(root, _box(Vector3(0.88, 0.09, 0.88)), trim, Vector3(0, y, 0), Vector3.ZERO, Vector3.ONE, "Band")
	for angle: float in [PI * 0.25, -PI * 0.25]:
		_part(root, _box(Vector3(0.08, 0.74, 0.05)), trim, Vector3(0, 0.33, -0.421),
			Vector3(0, 0, angle), Vector3.ONE, "Brace")


static func _stump(root: Node3D) -> void:
	_part(root, _cylinder(0.38, 0.48, 0.60, 12), material("stump_bark", Color("#98552c")),
		Vector3(0, 0.30, 0), Vector3.ZERO, Vector3.ONE, "Stump")
	_part(root, _cylinder(0.35, 0.35, 0.035, 12), material("stump_top", Color("#ddb26f")),
		Vector3(0, 0.615, 0), Vector3.ZERO, Vector3.ONE, "CutTop")
	for i: int in 4:
		var angle := float(i) * PI * 0.5
		_part(root, _box(Vector3(0.42, 0.11, 0.15)), material("stump_bark", Color("#98552c")),
			Vector3(cos(angle) * 0.36, 0.07, sin(angle) * 0.36), Vector3(0, -angle, 0), Vector3.ONE, "Root")


static func _mushrooms(root: Node3D) -> void:
	for i: int in 7:
		var angle := float(i) * TAU / 7.0
		var height := 0.24 + 0.06 * float(i % 3)
		var at := Vector3(cos(angle) * 0.38, 0, sin(angle) * 0.38)
		_part(root, _cylinder(0.025, 0.04, height, 8), material("mush_stem", COLORS.cream),
			at + Vector3(0, height * 0.5, 0), Vector3.ZERO, Vector3.ONE, "Stem")
		_part(root, _cylinder(0.035, 0.14, 0.10, 11), material("mush_cap_%d" % (i % 2),
			Color("#e18c4a") if i % 2 == 0 else COLORS.violet),
			at + Vector3(0, height + 0.02, 0), Vector3.ZERO, Vector3.ONE, "Cap")


static func _sign(root: Node3D) -> void:
	var wood := material("sign_post", Color("#89502b"))
	_part(root, _cylinder(0.05, 0.085, 1.08, 9), wood, Vector3(0, 0.54, 0), Vector3.ZERO, Vector3.ONE, "Post")
	_part(root, _box(Vector3(0.98, 0.38, 0.12)), material("sign_face", Color("#d59443")),
		Vector3(0.10, 0.87, 0), Vector3(0, 0, -0.035), Vector3.ONE, "Sign")
	_part(root, _sphere(0.10, 0.48, 10), material("sign_mark", COLORS.cream),
		Vector3(0.10, 0.87, -0.075), Vector3.ZERO, Vector3(1.35, 0.50, 1.0), "Mark")


static func _arch(root: Node3D) -> void:
	var wood := material("arch_wood", Color("#8c522c"))
	for x: float in [-0.65, 0.65]:
		_part(root, _cylinder(0.11, 0.18, 1.72, 10), wood, Vector3(x, 0.86, 0),
			Vector3(0.03, 0, 0.06 * sign(x)), Vector3.ONE, "ArchRoot")
	_part(root, _cylinder(0.11, 0.14, 1.34, 10), wood, Vector3(0, 1.63, 0),
		Vector3(0, 0, PI * 0.5), Vector3.ONE, "ArchCrown")
	for i: int in 7:
		var x := -0.60 + 0.20 * i
		_part(root, _sphere(0.15, 0.60, 10), material("arch_leaf_%d" % (i % 2),
			COLORS.leaf if i % 2 == 0 else COLORS.lime),
			Vector3(x, 1.76 + 0.08 * sin(float(i)), 0.02), Vector3.ZERO, Vector3(1.40, 0.68, 0.78), "Leaf")


static func _table(root: Node3D) -> void:
	var wood := material("table_wood", Color("#bd7431"))
	_part(root, _cylinder(0.57, 0.57, 0.14, 14), wood, Vector3(0, 0.64, 0), Vector3.ZERO, Vector3.ONE, "TableTop")
	_part(root, _cylinder(0.10, 0.17, 0.58, 10), material("table_leg", Color("#86502a")),
		Vector3(0, 0.30, 0), Vector3.ZERO, Vector3.ONE, "TableLeg")
	_part(root, _cylinder(0.11, 0.16, 0.14, 12), material("teacup", Color("#89b8aa")),
		Vector3(0.17, 0.77, -0.08), Vector3.ZERO, Vector3.ONE, "Cup")


static func _planter(root: Node3D) -> void:
	_part(root, _cylinder(0.46, 0.34, 0.46, 12), material("planter", COLORS.stone),
		Vector3(0, 0.23, 0), Vector3.ZERO, Vector3.ONE, "Planter")
	_part(root, _cylinder(0.38, 0.38, 0.05, 12), material("planter_soil", COLORS.soil_dark),
		Vector3(0, 0.48, 0), Vector3.ZERO, Vector3.ONE, "Soil")
	for i: int in 7:
		var angle := float(i) * TAU / 7.0
		_part(root, _sphere(0.16, 0.38, 10), material("mint_%d" % (i % 2),
			COLORS.mint if i % 2 == 0 else COLORS.leaf),
			Vector3(cos(angle) * 0.19, 0.65, sin(angle) * 0.19),
			Vector3(0, -angle, 0.5), Vector3(0.60, 0.34, 1.35), "Fern")


static func _beacon(root: Node3D) -> void:
	var stone := material("beacon_stone", Color("#8a8278"))
	_part(root, _cylinder(0.34, 0.44, 0.28, 12), stone, Vector3(0, 0.14, 0), Vector3.ZERO, Vector3.ONE, "Base")
	_part(root, _cylinder(0.12, 0.16, 0.52, 10), stone, Vector3(0, 0.54, 0), Vector3.ZERO, Vector3.ONE, "Stem")
	var bloom := Node3D.new()
	bloom.position.y = 0.90
	root.add_child(bloom)
	for i: int in 6:
		var angle := float(i) * TAU / 6.0
		_part(bloom, _sphere(0.16, 0.38, 10), material("beacon_petal", Color("#f7cf62"), Color("#f3a328")),
			Vector3(cos(angle) * 0.16, 0, sin(angle) * 0.16), Vector3.ZERO, Vector3(0.72, 0.45, 1.0), "Petal")
	_part(bloom, _sphere(0.12, 0.80, 10), material("beacon_core", Color("#fff0a6"), Color("#ffc94e")),
		Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "Core")
	_add_light(root, Color("#f3c54e"), Vector3(0, 0.92, 0), 1.1, 2.8)


static func _hushbell(root: Node3D) -> void:
	var frame := material("bell_frame", Color("#66564b"))
	_part(root, _box(Vector3(0.74, 0.11, 0.52)), frame, Vector3(0, 0.08, 0), Vector3.ZERO, Vector3.ONE, "Base")
	_part(root, _cylinder(0.05, 0.07, 0.85, 9), frame, Vector3(-0.26, 0.49, 0), Vector3.ZERO, Vector3.ONE, "Post")
	_part(root, _box(Vector3(0.55, 0.08, 0.08)), frame, Vector3(0, 0.88, 0), Vector3.ZERO, Vector3.ONE, "Arm")
	_part(root, _cylinder(0.08, 0.24, 0.32, 12), material("bell", Color("#d99538")),
		Vector3(0.20, 0.70, 0), Vector3.ZERO, Vector3.ONE, "Bell")
	_part(root, _sphere(0.055, 0.90, 9), frame, Vector3(0.20, 0.50, 0), Vector3.ZERO, Vector3.ONE, "Clapper")


static func _unknown(root: Node3D, category: StringName) -> void:
	var color := COLORS.stone if category == &"stone" else COLORS.honey
	_part(root, _sphere(0.38, 0.82, 10), material("unknown_%s" % category, color),
		Vector3(0, 0.34, 0), Vector3.ZERO, Vector3.ONE, "Unknown")


static func _add_light(root: Node3D, color: Color, pos: Vector3, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = false
	light.position = pos
	root.add_child(light)
