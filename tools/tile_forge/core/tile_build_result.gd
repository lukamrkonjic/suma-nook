@tool
class_name TileBuildResult
extends RefCounted
## Everything one generation pass produced, before it becomes nodes or files.
##
## The lab renders this, the validator inspects it, and the baker serialises
## it. Keeping the three consumers behind one plain data object is why preview
## and bake cannot drift apart: they are looking at the identical result.

var recipe: TileRecipe
var context: TileGenerationContext
var parts: Array[TileMeshPart] = []
var instances: Array[TileModuleInstance] = []
var collision: Array = []
var debug: Array[Dictionary] = []
var build_msec := 0


func surface_parts() -> Array[TileMeshPart]:
	return _parts_with_role(["surface", "side", "rim"])


func water_parts() -> Array[TileMeshPart]:
	return _parts_with_role(["water"])


func detail_parts() -> Array[TileMeshPart]:
	return _parts_with_role(["detail"])


func _parts_with_role(roles: Array) -> Array[TileMeshPart]:
	var result: Array[TileMeshPart] = []
	for part in parts:
		if part != null and roles.has(part.part_role):
			result.append(part)
	return result


func triangle_count() -> int:
	var total := 0
	for part in parts:
		if part != null:
			total += part.triangle_count()
	return total


func slots_used() -> PackedStringArray:
	var result := PackedStringArray()
	for part in parts:
		if part == null:
			continue
		for slot in part.slots:
			if not result.has(slot):
				result.append(slot)
	for instance in instances:
		if not result.has(instance.material_slot):
			result.append(instance.material_slot)
	return result


func bounds() -> AABB:
	var box := AABB()
	var started := false
	for part in parts:
		if part == null or part.mesh == null:
			continue
		var part_box := part.mesh.get_aabb()
		box = part_box if not started else box.merge(part_box)
		started = true
	for instance in instances:
		var pos := instance.position()
		var radius := instance.footprint_radius
		var instance_box := AABB(
			pos - Vector3(radius, 0.0, radius),
			Vector3(radius * 2.0, instance.height, radius * 2.0)
		)
		box = instance_box if not started else box.merge(instance_box)
		started = true
	return box


func instance_groups() -> Dictionary:
	var groups: Dictionary = {}
	for instance in instances:
		var key := instance.group_key
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(instance)
	return groups


func has_errors() -> bool:
	return context != null and not context.errors.is_empty()
