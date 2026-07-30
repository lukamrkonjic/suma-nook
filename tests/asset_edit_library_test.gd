extends Node
## Focused runtime test for Asset Studio's non-destructive mesh/material edits.

const AssetEditLibraryScript := preload(
	"res://scripts/visuals/asset_edit_library.gd"
)
const PROFILE_PATH := "user://asset_edit_library_test.json"

var _failures := 0


func _ready() -> void:
	_remove_test_profile()
	var asset_id := "test_asset"
	var source_mesh := _make_hard_edge_mesh()
	var source_arrays := source_mesh.surface_get_arrays(0)
	var authored_vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
	var authored_normals: PackedVector3Array = source_arrays[Mesh.ARRAY_NORMAL]
	var source_material := StandardMaterial3D.new()
	source_material.resource_name = "wood"
	source_material.albedo_color = Color("806040")
	source_material.roughness = 0.84
	source_material.metallic = 0.05
	source_mesh.surface_set_material(0, source_material)

	var asset_root := Node3D.new()
	asset_root.set_meta(
		AssetEditLibraryScript.SOURCE_ASSET_META,
		asset_id
	)
	add_child(asset_root)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = source_mesh
	asset_root.add_child(mesh_instance)

	var library = AssetEditLibraryScript.new(PROFILE_PATH)
	var edited_profile := {
		"scale": 1.75,
		"smoothing": 1.0,
		"materials": {
			"wood": {
				"color": "4d99cc",
				"roughness": 0.31,
				"metallic": 0.42,
			},
		},
	}
	library.apply_to_tree(asset_root, asset_id, edited_profile)

	_expect(
		asset_root.scale.is_equal_approx(Vector3.ONE * 1.75),
		"model scale is applied uniformly at its semantic asset root"
	)
	library.apply_to_tree(asset_root, asset_id, edited_profile)
	_expect(
		asset_root.scale.is_equal_approx(Vector3.ONE * 1.75),
		"reapplying a live profile never compounds model scale"
	)
	_expect(mesh_instance.mesh != source_mesh, "smoothing creates a runtime mesh")
	var edited_arrays := mesh_instance.mesh.surface_get_arrays(0)
	var edited_vertices: PackedVector3Array = edited_arrays[Mesh.ARRAY_VERTEX]
	var edited_normals: PackedVector3Array = edited_arrays[Mesh.ARRAY_NORMAL]
	_expect(
		_same_positions(authored_vertices, edited_vertices),
		"model smoothing does not move vertices"
	)
	_expect(
		not edited_normals[0].is_equal_approx(authored_normals[0]),
		"smoothing changes duplicated hard-edge normals"
	)
	var expected_normal := (
		authored_normals[0] + authored_normals[3]
	).normalized()
	_expect(
		edited_normals[0].dot(expected_normal) > 0.9999,
		"smoothing averages normals at welded positions"
	)

	var edited_material := (
		mesh_instance.get_active_material(0) as StandardMaterial3D
	)
	_expect(edited_material != source_material, "material edit is per asset")
	_expect(
		edited_material.albedo_color.is_equal_approx(Color("4d99cc")),
		"material color is applied"
	)
	_expect(
		is_equal_approx(edited_material.roughness, 0.31),
		"material roughness is applied"
	)
	_expect(
		is_equal_approx(edited_material.metallic, 0.42),
		"material metallic value is applied"
	)

	library.apply_to_tree(asset_root, asset_id, {
		"scale": 1.0,
		"smoothing": 0.0,
		"materials": {},
	})
	_expect(
		asset_root.scale.is_equal_approx(Vector3.ONE),
		"authored model scale can be restored"
	)
	_expect(mesh_instance.mesh == source_mesh, "authored mesh can be restored")
	_expect(
		mesh_instance.get_active_material(0) == source_material,
		"authored material can be restored"
	)
	_test_layer_material_override(library)

	var tile_root := Node3D.new()
	var tile_asset_id := "tile_test_surface"
	tile_root.set_meta(
		AssetEditLibraryScript.SOURCE_ASSET_META,
		tile_asset_id
	)
	add_child(tile_root)
	var tile_shell := MeshInstance3D.new()
	tile_shell.name = "tile_test_cap"
	tile_shell.mesh = _make_tile_border_mesh()
	tile_root.add_child(tile_shell)
	var fused_detail := MeshInstance3D.new()
	fused_detail.name = "story_rock"
	fused_detail.mesh = _make_hard_edge_mesh()
	tile_root.add_child(fused_detail)
	var shell_source := tile_shell.mesh
	var detail_source := fused_detail.mesh
	library.apply_to_tree(tile_root, tile_asset_id, {
		"scale": 2.0,
		"smoothing": 1.0,
		"materials": {},
	})
	_expect(
		tile_root.scale.is_equal_approx(Vector3.ONE),
		"tile dimensions ignore model-scale profile values"
	)
	var shell_arrays := tile_shell.mesh.surface_get_arrays(0)
	var shell_normals: PackedVector3Array = shell_arrays[Mesh.ARRAY_NORMAL]
	_expect(
		shell_normals[0].dot(Vector3.UP) > 0.9999,
		"tile top normals never fuse into the rectangular border"
	)
	_expect(
		shell_normals[3].dot(Vector3.FORWARD) > 0.9999,
		"tile side and border normals remain rigid"
	)
	_expect(
		tile_shell.mesh != shell_source,
		"tile top uses a protected runtime smoothing mesh"
	)
	_expect(
		fused_detail.mesh != detail_source,
		"small fused tile details still receive complete smoothing"
	)
	var detail_arrays := fused_detail.mesh.surface_get_arrays(0)
	var detail_normals: PackedVector3Array = detail_arrays[Mesh.ARRAY_NORMAL]
	_expect(
		not detail_normals[0].is_equal_approx(authored_normals[0]),
		"fused stones and similar tile details can smooth"
	)

	var base_root := Node3D.new()
	var base_asset_id := "tile_layer_base_standard"
	base_root.set_meta(
		AssetEditLibraryScript.SOURCE_ASSET_META,
		base_asset_id
	)
	add_child(base_root)
	var rigid_base := MeshInstance3D.new()
	rigid_base.mesh = _make_hard_edge_mesh()
	base_root.add_child(rigid_base)
	var rigid_base_source := rigid_base.mesh
	library.apply_to_tree(base_root, base_asset_id, {
		"smoothing": 1.0,
		"materials": {},
	})
	_expect(
		rigid_base.mesh == rigid_base_source,
		"layered rectangular tile bases ignore smoothing entirely"
	)
	_test_real_tile_surface_borders(library)

	_expect(
		library.save_profile(asset_id, edited_profile) == OK,
		"profile saves to JSON"
	)
	var reloaded = AssetEditLibraryScript.new(PROFILE_PATH)
	var imported: Dictionary = reloaded.profile(asset_id)
	_expect(
		is_equal_approx(float(imported.get("scale", 1.0)), 1.75),
		"saved model scale imports exactly"
	)
	_expect(
		is_equal_approx(reloaded.model_scale_for(asset_id), 1.75)
		and is_equal_approx(
			reloaded.model_scale_for("tile_test_surface"),
			1.0
		),
		"runtime scale lookup exposes model size and always locks tiles"
	)
	_expect(
		is_equal_approx(float(imported.get("smoothing", 0.0)), 1.0),
		"saved smoothing value imports exactly"
	)
	var imported_materials: Dictionary = imported.get("materials", {})
	_expect(imported_materials.has("wood"), "saved material slot imports")
	_expect(
		reloaded.save_profile(asset_id, {
			"scale": 1.0,
			"smoothing": 0.0,
			"materials": {},
		}) == OK,
		"authored defaults can remove a saved override"
	)
	_expect(
		not reloaded.has_profile(asset_id),
		"authored profile is absent after removal"
	)

	if _failures == 0:
		print("ASSET EDIT LIBRARY TEST PASSED")
	_remove_test_profile()
	get_tree().quit(_failures)


func _test_layer_material_override(library) -> void:
	var asset_id := "tile_layer_surface_color_test"
	var root := Node3D.new()
	root.set_meta(AssetEditLibraryScript.SOURCE_ASSET_META, asset_id)
	add_child(root)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _make_hard_edge_mesh()
	root.add_child(mesh_instance)

	## AssetLibrary runs before TileVisualFactory assigns its layer-wide
	## semantic material. Reproduce that order to guard the tile-only color bug.
	library.apply_to_tree(root, asset_id, {
		"smoothing": 0.0,
		"materials": {},
	})
	var composed := ShaderMaterial.new()
	composed.resource_name = "sand_top"
	composed.shader = load(
		"res://assets/materials/reworked/gg_prop_surface.gdshader"
	)
	composed.set_shader_parameter("albedo", Color("d1bd9e"))
	composed.set_shader_parameter("roughness_val", 0.88)
	composed.set_shader_parameter("metallic_val", 0.0)
	mesh_instance.material_override = composed
	library.apply_to_tree(root, asset_id, {
		"smoothing": 0.0,
		"materials": {
			"sand_top": {
				"color": "17120d",
				"roughness": 0.33,
				"metallic": 0.12,
			},
		},
	})
	var edited := mesh_instance.material_override as ShaderMaterial
	_expect(edited != composed, "tile layer color gets an asset-local material")
	_expect(
		(edited.get_shader_parameter("albedo") as Color).is_equal_approx(
			Color("17120d")
		),
		"tile layer material_override applies its selected color"
	)
	_expect(
		is_equal_approx(
			float(edited.get_shader_parameter("roughness_val")),
			0.33
		),
		"tile layer material_override applies roughness"
	)
	library.apply_to_tree(root, asset_id, {
		"smoothing": 0.0,
		"materials": {},
	})
	_expect(
		mesh_instance.material_override == composed,
		"tile layer authored material_override can be restored"
	)


func _make_hard_edge_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.BACK,
		Vector3.BACK,
		Vector3.BACK,
		Vector3.RIGHT,
		Vector3.RIGHT,
		Vector3.RIGHT,
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_tile_border_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.7, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.7),
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, -0.5, 0.0),
		Vector3(1.7, 0.0, 0.0),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.UP,
		Vector3.UP,
		Vector3.UP,
		Vector3.FORWARD,
		Vector3.FORWARD,
		Vector3.FORWARD,
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _test_real_tile_surface_borders(library) -> void:
	for asset_id in [
		"tile_layer_surface_snow",
		"tile_layer_surface_sand",
		"tile_layer_surface_flat",
		"tile_layer_surface_concrete_brutalist",
	]:
		var packed := load(
			"res://assets/3d/reworked/%s.glb" % asset_id
		) as PackedScene
		_expect(packed != null, "%s loads for its border contract" % asset_id)
		if packed == null:
			continue
		var root := packed.instantiate() as Node3D
		root.set_meta(
			AssetEditLibraryScript.SOURCE_ASSET_META,
			asset_id
		)
		add_child(root)
		var mesh_instance := root.find_child(
			"*",
			true,
			false
		) as MeshInstance3D
		if mesh_instance == null:
			var meshes := root.find_children(
				"*",
				"MeshInstance3D",
				true,
				false
			)
			mesh_instance = (
				meshes[0] as MeshInstance3D if not meshes.is_empty() else null
			)
		_expect(
			mesh_instance != null,
			"%s exposes its authored mesh" % asset_id
		)
		if mesh_instance == null:
			root.free()
			continue
		var authored_mesh := mesh_instance.mesh
		var authored_surfaces: Array = []
		for surface in mesh_instance.mesh.get_surface_count():
			authored_surfaces.append(
				mesh_instance.mesh.surface_get_arrays(surface)
			)
		_expect(
			_surfaces_are_flat(authored_surfaces),
			"%s imports flat per-face normals at 0%%" % asset_id
		)
		library.apply_to_tree(root, asset_id, {
			"smoothing": 1.0,
			"materials": {},
		})
		var changed_top_normals := 0
		var changed_top_vertices := 0
		var authored_top_min := INF
		var authored_top_max := -INF
		var edited_top_min := INF
		var edited_top_max := -INF
		for surface in authored_surfaces.size():
			var authored_arrays: Array = authored_surfaces[surface]
			var edited_arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var authored_vertices: PackedVector3Array = (
				authored_arrays[Mesh.ARRAY_VERTEX]
			)
			var edited_vertices: PackedVector3Array = (
				edited_arrays[Mesh.ARRAY_VERTEX]
			)
			var authored_normals: PackedVector3Array = (
				authored_arrays[Mesh.ARRAY_NORMAL]
			)
			var edited_normals: PackedVector3Array = (
				edited_arrays[Mesh.ARRAY_NORMAL]
			)
			for index in authored_normals.size():
				_expect(
					is_equal_approx(
						authored_vertices[index].x,
						edited_vertices[index].x
					)
					and is_equal_approx(
						authored_vertices[index].z,
						edited_vertices[index].z
					),
					"%s smoothing preserves X/Z vertex %d"
					% [asset_id, index]
				)
				if (
					authored_normals[index].y
					>= AssetEditLibraryScript.TILE_TOP_NORMAL_MIN
				):
					authored_top_min = minf(
						authored_top_min,
						authored_vertices[index].y
					)
					authored_top_max = maxf(
						authored_top_max,
						authored_vertices[index].y
					)
					edited_top_min = minf(
						edited_top_min,
						edited_vertices[index].y
					)
					edited_top_max = maxf(
						edited_top_max,
						edited_vertices[index].y
					)
					if not is_equal_approx(
						edited_vertices[index].y,
						authored_vertices[index].y
					):
						changed_top_vertices += 1
					if (
						edited_normals[index].dot(
							authored_normals[index]
						) < 0.9999
					):
						changed_top_normals += 1
					continue
				_expect(
					edited_vertices[index].is_equal_approx(
						authored_vertices[index]
					),
					"%s keeps side/border vertex %d rigid"
					% [asset_id, index]
				)
				_expect(
					edited_normals[index].dot(
						authored_normals[index]
					) > 0.9999,
					"%s keeps side/border normal %d rigid"
					% [asset_id, index]
				)
		if asset_id in [
			"tile_layer_surface_snow",
			"tile_layer_surface_sand",
		]:
			_expect(
				changed_top_normals > 0,
				"%s 100%% smoothing changes its flat top normals"
				% asset_id
			)
			_expect(
				changed_top_vertices > 0,
				"%s 100%% smoothing relaxes its top geometry"
				% asset_id
			)
			var authored_relief := authored_top_max - authored_top_min
			var edited_relief := edited_top_max - edited_top_min
			_expect(
				edited_relief <= authored_relief * 0.20,
				"%s 100%% smoothing strongly flattens its relief"
				% asset_id
			)
		library.apply_to_tree(root, asset_id, {
			"smoothing": 0.0,
			"materials": {},
		})
		_expect(
			mesh_instance.mesh == authored_mesh,
			"%s 0%% restores the exact authored mesh" % asset_id
		)
		root.free()


func _surfaces_are_flat(surfaces: Array) -> bool:
	for raw_arrays: Variant in surfaces:
		var arrays: Array = raw_arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var corner_count := indices.size() if not indices.is_empty() else vertices.size()
		if corner_count % 3 != 0:
			return false
		for corner in range(0, corner_count, 3):
			var a := indices[corner] if not indices.is_empty() else corner
			var b := indices[corner + 1] if not indices.is_empty() else corner + 1
			var c := indices[corner + 2] if not indices.is_empty() else corner + 2
			var geometric_normal := (
				vertices[b] - vertices[a]
			).cross(vertices[c] - vertices[a])
			if geometric_normal.length_squared() <= 0.0001:
				continue
			if (
				normals[a].dot(normals[b]) < 0.999
				or normals[a].dot(normals[c]) < 0.999
			):
				return false
	return true


func _same_positions(
	left: PackedVector3Array,
	right: PackedVector3Array
) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if not left[index].is_equal_approx(right[index]):
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Asset edit test failed: %s" % message)


func _remove_test_profile() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
