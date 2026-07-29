extends SceneTree
## Repeatable real-renderer scaling benchmark for the authoritative project.
## Direct dictionary population models loading an already-large save; edits
## then use the normal public WorldGrid API.
##
## Run:
##   Godot --path . --disable-vsync --script tests/performance_runner.gd \
##     -- --sizes=100,400,900 --structures=0.2

const DEFAULT_SIZES := [100, 400, 900]
const SETTLE_FRAMES := 8
const SAMPLE_FRAMES := 60
const DebugWorldBuilderScript := preload(
	"res://scripts/debug/debug_world_builder.gd"
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sizes := _requested_sizes()
	var structure_density := _requested_structure_density()
	print("PERF_CONFIG ", JSON.stringify({
		"engine": Engine.get_version_info().get("string", "unknown"),
		"renderer": RenderingServer.get_current_rendering_method(),
		"sizes": sizes,
		"structure_density": structure_density,
	}))
	if "--mixed" in OS.get_cmdline_user_args():
		for cell_count: int in sizes:
			await _benchmark(
				cell_count,
				"__mixed__",
				maxf(0.25, structure_density),
				"PERF_MIXED"
			)
		quit(0)
		return
	for cell_count: int in sizes:
		await _benchmark(cell_count, "tile_grass", structure_density, "PERF_LAND")
	for cell_count: int in sizes:
		await _benchmark(cell_count, "tile_open_water", 0.0, "PERF_WATER")
	quit(0)


func _benchmark(
	cell_count: int,
	tile_id: String,
	structure_density: float,
	label: String
) -> void:
	var fixture := _make_fixture(cell_count, tile_id, structure_density)
	var stage: Node3D = fixture["stage"]
	var core: GameCore = fixture["core"]
	var renderer: WorldRenderer = fixture["renderer"]
	var camera: Camera3D = fixture["camera"]

	var started := Time.get_ticks_usec()
	renderer.setup(core, fixture["assets"])
	var build_ms := (Time.get_ticks_usec() - started) / 1000.0
	await _settle()
	var full_world_frame := await _sample_frames()
	var counts := _node_counts(stage)
	var initial_occupancy := _world_occupancy(core)
	var full_draws := int(Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
	))
	var full_objects := int(Performance.get_monitor(
		Performance.RENDER_TOTAL_OBJECTS_IN_FRAME
	))
	var full_primitives := int(Performance.get_monitor(
		Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME
	))

	var side := ceili(sqrt(float(cell_count)))
	var add_coord := Vector2i(side / 2, side / 2 + 1)
	while core.grid.has_cell(add_coord):
		add_coord.y += 1
	started = Time.get_ticks_usec()
	core.grid.place_tile(add_coord, tile_id)
	var edit_ms := (Time.get_ticks_usec() - started) / 1000.0
	await process_frame

	camera.size = 28.0
	await _settle()
	var gameplay_frame := await _sample_frames()
	var autosave_stats := {}
	if "--autosave" in OS.get_cmdline_user_args():
		core.save_manager.save_path = (
			"user://performance_autosave_%d.json" % cell_count
		)
		core.save_manager.backup_path = core.save_manager.save_path + ".backup"
		core.autosave_soon()
		var autosave_started := Time.get_ticks_usec()
		core.tick(0.0)
		var main_thread_ms := (
			Time.get_ticks_usec() - autosave_started
		) / 1000.0
		while core._autosave_in_flight:
			await process_frame
			core.tick(0.0)
		autosave_stats = {
			"snapshot_main_thread_ms": main_thread_ms,
			"total_ms": (
				Time.get_ticks_usec() - autosave_started
			) / 1000.0,
		}
		core.save_manager.delete_save()
	print(label, " ", JSON.stringify({
		"cells": cell_count,
		"build_ms": build_ms,
		"edit_ms": edit_ms,
		"full_world_frame_ms": full_world_frame,
		"gameplay_frame_ms": gameplay_frame,
		"nodes": counts,
		"full_world_draw_calls": full_draws,
		"full_world_objects": full_objects,
		"full_world_primitives": full_primitives,
		"gameplay_draw_calls": int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
		)),
		"gameplay_objects": int(Performance.get_monitor(
			Performance.RENDER_TOTAL_OBJECTS_IN_FRAME
		)),
		"gameplay_primitives": int(Performance.get_monitor(
			Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME
		)),
		"world": renderer.debug_stats(),
		"occupancy": initial_occupancy,
		"autosave": autosave_stats,
	}))
	stage.queue_free()
	await process_frame


func _make_fixture(
	cell_count: int,
	tile_id: String,
	structure_density: float
) -> Dictionary:
	var core := GameCore.new()
	core.setup("res://data", 8675309)
	_populate(core, cell_count, tile_id, structure_density)

	var palette: CozyPalette = load("res://assets/palettes/gg_material_palette.tres")
	var materials := MaterialLibrary.new(palette)
	var assets := AssetLibrary.new(materials)
	var stage := Node3D.new()
	stage.name = "PerformanceFixture"
	root.add_child(stage)

	var lighting := (
		load("res://scenes/visual/SumaSoftDaylight.tscn") as PackedScene
	).instantiate()
	stage.add_child(lighting)

	var side := ceili(sqrt(float(cell_count)))
	var extent := maxf(12.0, side * core.grid.tile_size * 0.62)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = extent * 2.0
	camera.near = 0.1
	camera.far = extent * 8.0
	camera.position = Vector3(extent * 1.3, extent * 1.5, extent * 1.3)
	stage.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true

	var renderer := WorldRenderer.new()
	stage.add_child(renderer)
	return {
		"core": core,
		"assets": assets,
		"renderer": renderer,
		"stage": stage,
		"camera": camera,
	}


func _populate(
	core: GameCore,
	cell_count: int,
	tile_id: String,
	structure_density: float
) -> void:
	if tile_id == "__mixed__":
		DebugWorldBuilderScript.populate(
			core,
			cell_count,
			roundi(cell_count * structure_density),
			8675309
		)
		return
	core.grid.cells.clear()
	core.grid.stacked_cells.clear()
	var structure_ids: Array[String] = []
	for structure_id: String in core.registries.structures:
		structure_ids.append(structure_id)
	structure_ids.sort()
	var side := ceili(sqrt(float(cell_count)))
	var start := -side / 2
	var structure_stride := (
		maxi(1, roundi(1.0 / structure_density))
		if structure_density > 0.0
		else 0
	)
	for index in cell_count:
		var x := index % side
		var y := index / side
		var state := WorldGrid.CellState.new()
		state.tile_id = tile_id
		if structure_stride > 0 and index % structure_stride == 0:
			var structure := WorldGrid.StructureState.new()
			structure.instance_id = core.grid.next_instance_id
			core.grid.next_instance_id += 1
			structure.structure_id = structure_ids[index % structure_ids.size()]
			var definition := core.registries.structure(structure.structure_id)
			structure.socket_index = (
				0 if definition != null and definition.socket_type == "structure" else 1
			)
			structure.rotation = index % 4
			state.structures.append(structure)
		core.grid.cells[Vector2i(start + x, start + y)] = state


func _requested_sizes() -> Array[int]:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--sizes="):
			continue
		var result: Array[int] = []
		for raw in arg.trim_prefix("--sizes=").split(","):
			var value := int(raw)
			if value > 0:
				result.append(value)
		if not result.is_empty():
			return result
	return DEFAULT_SIZES.duplicate()


func _requested_structure_density() -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--structures="):
			return clampf(float(arg.trim_prefix("--structures=")), 0.0, 1.0)
	return 0.2


func _settle() -> void:
	for _index in SETTLE_FRAMES:
		await process_frame


func _sample_frames() -> float:
	var started := Time.get_ticks_usec()
	for _index in SAMPLE_FRAMES:
		await process_frame
	return (Time.get_ticks_usec() - started) / 1000.0 / SAMPLE_FRAMES


func _node_counts(root_node: Node) -> Dictionary:
	var result := {
		"total": 0,
		"mesh_instances": 0,
		"multimesh_instances": 0,
		"static_bodies": 0,
		"collision_shapes": 0,
		"omni_lights": 0,
	}
	var pending: Array[Node] = [root_node]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		result["total"] += 1
		if node is MultiMeshInstance3D:
			result["multimesh_instances"] += 1
		elif node is MeshInstance3D:
			result["mesh_instances"] += 1
		elif node is StaticBody3D:
			result["static_bodies"] += 1
		elif node is CollisionShape3D:
			result["collision_shapes"] += 1
		elif node is OmniLight3D:
			result["omni_lights"] += 1
		for child in node.get_children():
			pending.append(child)
	return result


func _world_occupancy(core: GameCore) -> Dictionary:
	var occupied_tiles := 0
	var placed_models := 0
	var maximum_on_one_tile := 0
	for state: WorldGrid.CellState in core.grid.cells.values():
		var count := state.structures.size()
		if count > 0:
			occupied_tiles += 1
		placed_models += count
		maximum_on_one_tile = maxi(maximum_on_one_tile, count)
	return {
		"occupied_tiles": occupied_tiles,
		"placed_models": placed_models,
		"maximum_on_one_tile": maximum_on_one_tile,
		"one_model_on_every_tile": (
			occupied_tiles == core.grid.total_tile_count()
			and placed_models == core.grid.total_tile_count()
			and maximum_on_one_tile == 1
		),
	}
