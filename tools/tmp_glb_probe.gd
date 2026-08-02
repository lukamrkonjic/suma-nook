extends SceneTree
## Temporary clean-room measurement probe: prints construction statistics for
## reference GLBs (bounds, counts, flat-vs-smooth shading, part structure).
## Measurements only — no geometry is imported into the project.

const FILES := [
	"Ground_base__sharedassets0__1295.glb",
	"Ground_base_low__sharedassets0__1285.glb",
	"Cobble__sharedassets0__1277.glb",
	"Cobble base__sharedassets0__1654.glb",
	"Snow_Full__sharedassets0__1358.glb",
	"Soil Bits round__sharedassets0__1534.glb",
	"Soil_round__sharedassets0__1623.glb",
	"DryGrass_leaf__sharedassets0__1565.glb",
	"Reed_leaf__sharedassets0__1732.glb",
	"Leaf Pile__sharedassets0__1550.glb",
	"Pond_water_straight__sharedassets0__1553.glb",
	"Solid Water surface__sharedassets0__1792.glb",
	"SteppingStone__sharedassets0__1484.glb",
	"Snowball_pile__sharedassets0__1576.glb",
]
const ROOT := "C:/Users/Luka/Documents/dev/garden-galaxy-technical-audit/private_evidence/garden_galaxy_glb_export_20260726/meshes"


func _init() -> void:
	for file in FILES:
		_probe("%s/%s" % [ROOT, file])
	quit(0)


func _probe(path: String) -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		print("FAILED: %s" % path)
		return
	var scene := document.generate_scene(state)
	print("\n=== %s" % path.get_file())
	_walk(scene, 0)
	scene.free()


func _walk(node: Node, depth: int) -> void:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		var aabb := (node as MeshInstance3D).get_aabb()
		print("  mesh '%s' scale=%s aabb pos=%s size=%s" % [
			node.name, (node as Node3D).scale, aabb.position, aabb.size])
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals_data: Variant = arrays[Mesh.ARRAY_NORMAL]
			var indices_data: Variant = arrays[Mesh.ARRAY_INDEX]
			var triangles := 0
			if indices_data is PackedInt32Array:
				triangles = (indices_data as PackedInt32Array).size() / 3
			else:
				triangles = vertices.size() / 3
			# Unique position count vs vertex count: high duplication with
			# distinct normals = flat/faceted shading; low duplication = smooth.
			var unique_positions: Dictionary = {}
			for vertex in vertices:
				unique_positions[Vector3i(vertex * 2000.0)] = true
			var unique_normals: Dictionary = {}
			if normals_data is PackedVector3Array:
				for normal: Vector3 in normals_data:
					unique_normals[Vector3i(normal * 100.0)] = true
			var material := mesh.surface_get_material(surface)
			var color := "?"
			if material is BaseMaterial3D:
				color = "#" + (material as BaseMaterial3D).albedo_color.to_html(false)
				color += " rough=%.2f metal=%.2f alpha=%.2f" % [
					(material as BaseMaterial3D).roughness,
					(material as BaseMaterial3D).metallic,
					(material as BaseMaterial3D).albedo_color.a]
			print("    surf%d: verts=%d uniquePos=%d tris=%d uniqueNormals=%d mat=%s (%s)" % [
				surface, vertices.size(), unique_positions.size(), triangles,
				unique_normals.size(),
				material.resource_name if material != null else "none", color])
	for child in node.get_children():
		_walk(child, depth + 1)
