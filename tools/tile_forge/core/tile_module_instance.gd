@tool
class_name TileModuleInstance
extends RefCounted
## One placed detail module. Deliberately data, not a node: the baker decides
## whether a set of instances becomes a merged mesh, a MultiMesh, or debug
## nodes, and the validator inspects instances before any of that happens.

var module_path := ""
var transform := Transform3D.IDENTITY
var material_slot := TileForgeConstants.SLOT_DETAIL_A
var output: TileForgeConstants.DetailOutput = TileForgeConstants.DetailOutput.MERGED_STATIC_MESH
## Rule that produced it, for debugging and per-rule isolation in the lab.
var rule_name := ""
## Index inside its module set, used by the repetition check.
var module_index := 0
## Cached footprint/height at the placed scale, so validation does not have to
## re-derive them from the mesh.
var footprint_radius := 0.0
var height := 0.0
## Group key for MultiMesh batching: identical geometry + identical material.
var group_key := ""
var wants_collision := false
## Set by a rule whose family legitimately interleaves — a straw mat or a leaf
## litter reads wrong if every strand keeps its distance. Overlap between two
## such instances is not reported as an intersection.
var permits_overlap := false
## Focal tier this placement was composed as. Recorded so a reviewer can see
## whether a tile actually has a subject.
var role: int = TileForgeConstants.Role.SUPPORT


func position() -> Vector3:
	return transform.origin


func uniform_scale() -> float:
	return transform.basis.get_scale().y


func make_group_key() -> String:
	group_key = "%s|%s" % [module_path, material_slot]
	return group_key


## Circle-overlap test in the XZ plane. Two modules whose footprints overlap by
## more than `tolerance` metres are reported as an intersection.
func overlaps(other: TileModuleInstance, tolerance: float) -> bool:
	var a := position()
	var b := other.position()
	var flat_distance := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	return flat_distance + tolerance < footprint_radius + other.footprint_radius


func to_dict() -> Dictionary:
	return {
		"module": module_path.get_file(),
		"rule": rule_name,
		"slot": material_slot,
		"pos": [position().x, position().y, position().z],
		"scale": uniform_scale(),
		"radius": footprint_radius,
		"height": height,
	}
