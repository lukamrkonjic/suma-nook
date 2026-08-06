class_name ProceduralStoneWall
extends RefCounted
## Deterministic, gap-proof dry-stone wall module.
##
## Two staggered courses form one half-tile module; two stacked modules recover
## the observed four-course Garden Galaxy rhythm. Every vertex and material
## binding is generated in Suma. The recessed core is deliberately opaque and
## every rounded slab is closed on both faces, so joints and reverse views can
## never become holes. Authored dimensions are calibrated for the shared
## 1 / 1.35 structure scale used by StructureVisualFactory.

const MeshUtils := preload("res://tools/tile_kit/tile_kit_mesh_utils.gd")

const AUTHORED_WIDTH := 1.43
const AUTHORED_SUPPORT_HEIGHT := 0.675
const STONE_DEPTH := 0.58
const CORE_WIDTH := AUTHORED_WIDTH - 0.10
const CORE_DEPTH := 0.40
const CORE_HEIGHT := 0.64
## A cell-centred perpendicular wall terminates before the neighbouring wall's
## front face. This recessed span bridges that interval. Collinear modules
## conceal it behind their ordinary face stones, so straight runs keep the
## authored one-cell rhythm without coplanar overlap or z-fighting.
const JUNCTION_SPAN := 2.15
const JUNCTION_DEPTH := 0.50
const HORIZONTAL_JOINT_OVERLAP := 0.024

const COURSE_BASES := [-0.035, 0.300]
const COURSE_HEIGHTS := [0.375, 0.395]
const COURSE_WEIGHTS := [
	[1.10, 0.82, 1.20, 0.88],
	[0.68, 1.08, 0.82, 1.06, 0.60],
]
const STONE_KEYS := [
	"moss_gg_stone_top",
	"moss_gg_stone_bevel",
	"moss_gg_stone_chip",
]


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "ProceduralStoneWall"
	root.set_meta("procedural_asset", true)
	root.set_meta("authored_support_height", AUTHORED_SUPPORT_HEIGHT)
	root.set_meta("authored_width", AUTHORED_WIDTH)
	root.set_meta("authored_junction_span", JUNCTION_SPAN)

	var core := MeshInstance3D.new()
	core.name = "GapProofCore"
	var core_mesh := BoxMesh.new()
	core_mesh.size = Vector3(
		CORE_WIDTH,
		CORE_HEIGHT,
		CORE_DEPTH
	)
	core.mesh = core_mesh
	core.position.y = CORE_HEIGHT * 0.5
	core.material_override = _wall_material("moss_gg_stone_side")
	root.add_child(core)

	var junction_extension := (JUNCTION_SPAN - AUTHORED_WIDTH) * 0.5
	var junction_center := (
		AUTHORED_WIDTH * 0.5 + junction_extension * 0.5
	)
	for side_data: Dictionary in [
		{"name": "JunctionLeft", "sign": -1.0},
		{"name": "JunctionRight", "sign": 1.0},
	]:
		var side := float(side_data["sign"])
		var junction := Node3D.new()
		junction.name = String(side_data["name"])
		junction.visible = false
		# Junction arms are conditional visual closure, not the wall's collider
		# or placement footprint.
		junction.set_meta("exclude_from_structural_bounds", true)
		var junction_core := MeshInstance3D.new()
		junction_core.name = "JunctionCore"
		var junction_core_mesh := BoxMesh.new()
		junction_core_mesh.size = Vector3(
			maxf(0.04, junction_extension - 0.08),
			CORE_HEIGHT,
			CORE_DEPTH
		)
		junction_core.mesh = junction_core_mesh
		junction_core.position = Vector3(
			side * junction_center,
			CORE_HEIGHT * 0.5,
			0.0
		)
		junction_core.material_override = _wall_material(
			"moss_gg_stone_side"
		)
		junction.add_child(junction_core)

		var junction_batch := MeshUtils.MeshBatch.new()
		for course_index in COURSE_BASES.size():
			var course_height := float(COURSE_HEIGHTS[course_index]) + 0.018
			var center_y := (
				float(COURSE_BASES[course_index])
				+ float(COURSE_HEIGHTS[course_index]) * 0.5
			)
			_add_closed_slab(
				junction_batch,
				STONE_KEYS[(course_index + 1) % STONE_KEYS.size()],
				Vector3(
					side * junction_center,
					-JUNCTION_DEPTH * 0.5,
					-center_y
				),
				junction_extension * 0.5,
				course_height * 0.5,
				0.026,
				JUNCTION_DEPTH,
				0.0,
				0.032,
				3
			)
		var junction_courses := MeshInstance3D.new()
		junction_courses.name = "JunctionCourses"
		junction_courses.mesh = _tune_wall_materials(junction_batch.commit())
		junction_courses.rotation.x = PI * 0.5
		junction.add_child(junction_courses)
		root.add_child(junction)

	var batch := MeshUtils.MeshBatch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x51A7E
	for course_index in COURSE_BASES.size():
		_add_course(
			batch,
			rng,
			course_index,
			float(COURSE_BASES[course_index]),
			float(COURSE_HEIGHTS[course_index]),
			COURSE_WEIGHTS[course_index]
		)

	var masonry := MeshInstance3D.new()
	masonry.name = "RoundedMasonryCourses"
	masonry.mesh = _tune_wall_materials(batch.commit())
	# MeshUtils.add_slab creates X/Z-faced horizontal slabs.  This quarter turn
	# maps local Z to wall Y and slab thickness to wall Z without stretching.
	masonry.rotation.x = PI * 0.5
	root.add_child(masonry)

	var top_socket := Marker3D.new()
	top_socket.name = "WallTopSupport"
	top_socket.position.y = AUTHORED_SUPPORT_HEIGHT
	root.add_child(top_socket)
	return root


static func _add_course(
	batch: MeshUtils.MeshBatch,
	rng: RandomNumberGenerator,
	course_index: int,
	base_y: float,
	nominal_height: float,
	weights: Array
) -> void:
	var total_weight := 0.0
	for raw_weight: Variant in weights:
		total_weight += float(raw_weight)
	var total_stone_width := (
		AUTHORED_WIDTH
		+ HORIZONTAL_JOINT_OVERLAP * float(weights.size() - 1)
	)
	var cursor := -AUTHORED_WIDTH * 0.5
	for stone_index in weights.size():
		var width := (
			total_stone_width
			* float(weights[stone_index])
			/ total_weight
		)
		var height_scale := rng.randf_range(0.94, 1.035)
		var stone_height := nominal_height * height_scale
		var center_y := (
			base_y
			+ nominal_height * 0.5
			+ rng.randf_range(-0.010, 0.010)
		)
		var center_x := cursor + width * 0.5
		# Endpoint stones stay axis-aligned so every row obeys the same exact
		# module boundary.  Interior stones can lean very slightly.
		var roll := 0.0
		if stone_index > 0 and stone_index < weights.size() - 1:
			roll = rng.randf_range(-0.018, 0.018)
		var corner := minf(
			width * rng.randf_range(0.16, 0.22),
			stone_height * rng.randf_range(0.19, 0.26)
		)
		var palette_index := posmod(
			course_index * 2 + stone_index + (1 if rng.randf() > 0.72 else 0),
			STONE_KEYS.size()
		)
		_add_closed_slab(
			batch,
			STONE_KEYS[palette_index],
			# After the quarter turn: world Y = -local Z and world Z = local Y.
			Vector3(center_x, -STONE_DEPTH * 0.5, -center_y),
			width * 0.5,
			stone_height * 0.5,
			maxf(0.018, corner),
			STONE_DEPTH,
			roll,
			minf(0.050, STONE_DEPTH * 0.18),
			4
		)
		cursor += width - HORIZONTAL_JOINT_OVERLAP


## TileKit slabs are intentionally open underneath because they normally sit
## on a tile surface. A wall rotates that underside onto its visible back face,
## so the wall closes it with one full-perimeter planar cap. Keeping this cap
## flush avoids the inset lips that protrude between tightly stacked stones.
static func _add_closed_slab(
	batch: MeshUtils.MeshBatch,
	key: String,
	centre: Vector3,
	half_x: float,
	half_z: float,
	corner: float,
	slab_height: float,
	yaw: float,
	bevel: float = 0.016,
	corner_segments: int = 4
) -> void:
	MeshUtils.add_slab(
		batch,
		key,
		centre,
		half_x,
		half_z,
		corner,
		slab_height,
		yaw,
		bevel,
		corner_segments
	)
	var outline := MeshUtils._slab_outline(
		half_x,
		half_z,
		corner,
		corner_segments
	)
	var points: PackedVector2Array = outline[0]
	var rotation := Basis(Vector3.UP, yaw)
	var vertices := PackedVector3Array([centre])
	var normals := PackedVector3Array([Vector3.DOWN])
	var indices := PackedInt32Array()
	for point: Vector2 in points:
		var world := rotation * Vector3(point.x, 0.0, point.y)
		vertices.append(centre + Vector3(world.x, 0.0, world.z))
		normals.append(Vector3.DOWN)
	for index in points.size():
		var next := (index + 1) % points.size()
		indices.append_array([0, 1 + next, 1 + index])
	batch.add(key, vertices, normals, indices)


## Palette materials are shared by every generated tile. The wall gets private
## rough-stone instances so warm point lights produce broad readable gradients
## without mutating grass/moss assets or blooming like polished plastic.
static func _wall_material(key: String) -> StandardMaterial3D:
	var source := TileKitPalette.material(key) as StandardMaterial3D
	var material := source.duplicate() as StandardMaterial3D
	material.resource_name = "procedural_wall_%s" % key
	material.metallic = 0.0
	material.roughness = 0.72
	material.metallic_specular = 0.14
	return material


static func _tune_wall_materials(mesh: ArrayMesh) -> ArrayMesh:
	for surface_index in mesh.get_surface_count():
		var source := mesh.surface_get_material(surface_index)
		if source is StandardMaterial3D:
			var material := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
			material.resource_name = "procedural_wall_surface_%d" % surface_index
			material.metallic = 0.0
			material.roughness = 0.72
			material.metallic_specular = 0.14
			mesh.surface_set_material(surface_index, material)
	return mesh
