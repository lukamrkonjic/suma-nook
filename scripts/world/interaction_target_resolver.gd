class_name InteractionTargetResolver
extends RefCounted
## Converts a screen position into the closest gameplay interaction. The scene
## owns nodes; this service owns targeting priority and capability discovery.

var scene_root: Node
var core: GameCore
var camera: Camera3D
var delivery_point: DeliveryPoint


func _init(
	root: Node,
	game_core: GameCore,
	game_camera: Camera3D,
	delivery: DeliveryPoint
) -> void:
	scene_root = root
	core = game_core
	camera = game_camera
	delivery_point = delivery


func ground_point(screen_position: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001:
		return null
	var distance := -origin.y / direction.y
	if distance < 0.0:
		return null
	var point := origin + direction * distance
	point.y = 0.0
	return point


func interaction_at(screen_position: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	var base_radius := core.registries.tunef("click_target_screen_radius", 54.0)

	for enemy in scene_root.get_tree().get_nodes_in_group("enemies"):
		if not core.registries.feature("combat_enabled", false):
			break
		var enemy_node := enemy as Node3D
		if not is_instance_valid(enemy_node):
			continue
		var point := enemy_node.global_position
		var candidate := _candidate(
			screen_position, point + Vector3(0, 0.55, 0), base_radius,
			{"kind": "enemy", "node": enemy_node, "point": point}
		)
		if not candidate.is_empty() and candidate["_distance"] < best_distance:
			best = candidate
			best_distance = candidate["_distance"]

	for marker in scene_root.get_tree().get_nodes_in_group("landmark_prompts"):
		if not core.registries.feature("hostile_landmarks_enabled", false):
			break
		var marker_node := marker as Node3D
		if not is_instance_valid(marker_node):
			continue
		var point := marker_node.global_position
		var candidate := _candidate(
			screen_position, point + Vector3(0, 1.05, 0), base_radius,
			{"kind": "landmark_prompt", "node": marker_node, "point": point}
		)
		if not candidate.is_empty() and candidate["_distance"] < best_distance:
			best = candidate
			best_distance = candidate["_distance"]

	for package in scene_root.get_tree().get_nodes_in_group("delivery_packages"):
		var package_node := package as Node3D
		if not is_instance_valid(package_node) or not package_node.visible:
			continue
		var candidate := _candidate(
			screen_position,
			package_node.global_position + Vector3(0, 0.25, 0),
			base_radius * 1.2,
			{
				"kind": "delivery_package",
				"node": package_node,
				"point": delivery_point.player_interaction.global_position,
			}
		)
		if not candidate.is_empty():
			candidate["_distance"] -= base_radius
		if not candidate.is_empty() and candidate["_distance"] < best_distance:
			best = candidate
			best_distance = candidate["_distance"]

	# Screen-space targeting only needs cells near the projected pointer. The
	# previous implementation rebuilt and sorted every slot in the world for
	# each click, making interaction cost grow linearly with world size.
	var projected: Variant = ground_point(screen_position)
	var pointer_coord := (
		core.grid.world_to_cell(projected)
		if projected is Vector3
		else core.grid.home_cell
	)
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var coord := pointer_coord + Vector2i(dx, dy)
			var ground_state := core.grid.cell(coord)
			var tile_definition := core.grid.tile_def(coord)
			var ground_center := core.grid.cell_to_world(coord)
			if (
				ground_state != null
				and tile_definition != null
				and tile_definition.anchor_id != ""
				and not ground_state.anchor_resting
			):
				var anchor := core.registries.anchor(tile_definition.anchor_id)
				if anchor != null and core.skills.is_playable(anchor.skill_id):
					var interaction_point := ground_center
					if (
						not tile_definition.walkable
						and tile_definition.water_cells.has("open_water")
					):
						interaction_point += Vector3(0, 0, 1.25)
					var candidate := _candidate(
						screen_position,
						ground_center + Vector3(0, 0.55, 0),
						base_radius * 1.35,
						{
							"kind": "anchor",
							"coord": coord,
							"anchor": anchor,
							"point": interaction_point,
						}
					)
					if not candidate.is_empty() and candidate["_distance"] < best_distance:
						best = candidate
						best_distance = candidate["_distance"]

			var top := core.grid.top_elevation(coord)
			for elevation in range(0, top + 1):
				var state := core.grid.cell_at(coord, elevation)
				if state == null:
					continue
				var center := core.grid.cell_to_world(coord, elevation)
				for structure: WorldGrid.StructureState in state.structures:
					var definition := core.registries.structure(structure.structure_id)
					if definition == null:
						continue
					var point := (
						center
						+ core.grid.structure_local_transform_in_cell(
							state,
							structure.instance_id
						).origin
					)
					if definition.anchor_id != "" and not structure.anchor_resting:
						var anchor := core.registries.anchor(definition.anchor_id)
						if anchor != null and core.skills.is_playable(anchor.skill_id):
							var candidate := _candidate(
								screen_position,
								point + Vector3(0, 0.8, 0),
								base_radius * 1.35,
								{
									"kind": "anchor",
									"coord": coord,
									"elevation": elevation,
									"instance_id": structure.instance_id,
									"anchor": anchor,
									"point": point,
								}
							)
							if (
								not candidate.is_empty()
								and candidate["_distance"] < best_distance
							):
								best = candidate
								best_distance = candidate["_distance"]
					if definition.has_capability("storage_access"):
						var candidate := _candidate(
							screen_position,
							point + Vector3(0, 0.45, 0),
							base_radius,
							{
								"kind": "storage",
								"coord": coord,
								"elevation": elevation,
								"instance_id": structure.instance_id,
								"point": point,
							}
						)
						if (
							not candidate.is_empty()
							and candidate["_distance"] < best_distance
						):
							best = candidate
							best_distance = candidate["_distance"]
					var feature_options: Array = core.interactions.options_for(
						"player",
						structure.instance_id
					)
					if not feature_options.is_empty():
						var option = feature_options[0]
						var candidate := _candidate(
							screen_position,
							point + Vector3(0, 0.65, 0),
							base_radius,
							{
								"kind": "feature_interaction",
								"feature": option.feature_id,
								"option": option,
								"instance_id": structure.instance_id,
								"point": point,
							}
						)
						if (
							not candidate.is_empty()
							and candidate["_distance"] < best_distance
						):
							best = candidate
							best_distance = candidate["_distance"]

	best.erase("_distance")
	return best


func _candidate(
	screen_position: Vector2,
	visual_point: Vector3,
	radius: float,
	interaction: Dictionary
) -> Dictionary:
	if camera.is_position_behind(visual_point):
		return {}
	var distance := screen_position.distance_to(camera.unproject_position(visual_point))
	if distance > radius:
		return {}
	var candidate := interaction.duplicate()
	candidate["_distance"] = distance
	return candidate
