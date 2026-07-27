class_name PlacementTargetResolver
extends RefCounted
## Resolves a structure column from gameplay hierarchy first and visual height
## second. Lower colliders can never steal priority from the top support.

var grid: WorldGrid
var renderer: WorldRenderer


func _init(world_grid: WorldGrid, world_renderer: WorldRenderer) -> void:
	grid = world_grid
	renderer = world_renderer


func highest_structure_instance_at(coord: Vector2i, elevation: int) -> int:
	var state := grid.cell_at(coord, elevation)
	if state == null or state.structures.is_empty():
		return -1
	var best_instance_id := -1
	var best_height := -1.0e20
	var best_depth := -1
	for structure: WorldGrid.StructureState in state.structures:
		var depth := grid.structure_depth(structure.instance_id)
		var visual := renderer.structure_node(structure.instance_id)
		var height := (
			renderer.structure_preview_position(structure.instance_id).y
			if visual != null
			else (
				grid.cell_to_world(coord, elevation).y
				+ grid.structure_local_transform(structure.instance_id).origin.y
			)
		)
		if (
			depth > best_depth
			or (
				depth == best_depth
				and (
					height > best_height + 0.0001
					or (
						is_equal_approx(height, best_height)
						and structure.instance_id > best_instance_id
					)
				)
			)
		):
			best_instance_id = structure.instance_id
			best_height = height
			best_depth = depth
	return best_instance_id


func resolve_structure_support(
	coord: Vector2i,
	elevation: int,
	structure_id: String
) -> Dictionary:
	var instance_id := highest_structure_instance_at(coord, elevation)
	if instance_id <= 0:
		return {}
	return {
		"instance_id": instance_id,
		"slot_id": grid.free_support_slot(instance_id, structure_id),
	}
