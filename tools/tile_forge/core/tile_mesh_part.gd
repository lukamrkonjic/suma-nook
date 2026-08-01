@tool
class_name TileMeshPart
extends RefCounted
## One piece of generated geometry, tagged with the material slot it wants and
## the output node it belongs on.
##
## Generators return these instead of finished MeshInstance3D nodes so the
## baker owns every decision about node structure, material binding, merging,
## and naming. That is what keeps a hero custom mesh subject to the same
## pipeline as a procedural heightfield.

## Triangles in LIVE space, already positioned relative to the tile centre.
var mesh: ArrayMesh
## Material slot per mesh surface. Size must equal mesh.get_surface_count().
var slots := PackedStringArray()
## Logical destination: "surface", "detail", "water", "rim", "side".
var part_role := "surface"
## Node name suffix when `separate_render_layer` was requested.
var layer_name := ""
var separate_render_layer := false
var smooth_shading := true
## Set by a generator that wants its part excluded from the merged surface —
## a water plane, for example, must stay its own transparent node.
var never_merge := false


static func make(
	array_mesh: ArrayMesh,
	slot_names: PackedStringArray,
	role := "surface"
) -> TileMeshPart:
	var part := TileMeshPart.new()
	part.mesh = array_mesh
	part.slots = slot_names
	part.part_role = role
	return part


func triangle_count() -> int:
	if mesh == null:
		return 0
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		# An unindexed SurfaceTool commit leaves ARRAY_INDEX null rather than
		# empty, so this cannot be typed straight into a PackedInt32Array.
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices is PackedInt32Array and (indices as PackedInt32Array).size() > 0:
			total += (indices as PackedInt32Array).size() / 3
		else:
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total += vertices.size() / 3
	return total


func slot_for_surface(index: int) -> String:
	if index < slots.size():
		return slots[index]
	return TileForgeConstants.SLOT_TOP_PRIMARY
