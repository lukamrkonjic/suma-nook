@tool
extends SceneTree


func _init() -> void:
	_probe_basin("rounded", 0.62, 0.14, 0.0, 0.12, 0, 9)
	_probe_basin("circle", 0.62, 0.14, 0.0, 0.12, 0, 11)
	_probe_basin("rect", 0.70, 0.10, 0.05, 0.14, 1, 13)
	_probe_custom()
	quit()


func _make_recipe(resolution: int, layer: TileSurfaceLayer) -> TileRecipe:
	var recipe := TileRecipe.new()
	recipe.tile_id = "probe"
	recipe.collision_mode = TileForgeConstants.CollisionMode.RIM_BOX
	recipe.edge_policy = TileForgeConstants.EdgePolicy.INSET_SURFACE
	layer.resolution = resolution
	recipe.surface_layers = [layer]
	return recipe


func _probe_basin(
	shape: String,
	inner: float,
	depth: float,
	rim: float,
	band: float,
	steps: int,
	resolution: int
) -> void:
	var layer := TileSurfaceLayer.new()
	layer.generator_id = "basin"
	layer.layer_name = "basin_%s" % shape
	layer.border_policy = TileForgeConstants.BorderPolicy.EDGE_LOCK
	layer.edge_lock_width = 0.24
	layer.smooth_shading = false
	layer.params = {
		"shape": shape,
		"inner": inner,
		"depth": depth,
		"rim_height": rim,
		"wall_softness": band,
		"step_count": steps,
	}
	var recipe := _make_recipe(resolution, layer)
	var result := TileForgeBuilder.build(recipe)
	var report := TileValidator.validate(result)
	var field := result.context.field
	var worst := 0.0
	for h in field.boundary_heights():
		worst = maxf(worst, absf(h - 0.0))
	var box := result.bounds()
	var water_parts := result.water_parts()
	print("--- basin %s res=%d steps=%d" % [shape, resolution, steps])
	print("   ctx errors: ", result.context.errors)
	print("   ctx messages: ", result.context.messages)
	print("   boundary drift: %.7f" % worst)
	print("   min/max height: %.4f / %.4f" % [field.min_height(), field.max_height()])
	print("   median: %.4f" % field.median_height())
	print("   bounds x %.5f..%.5f  z %.5f..%.5f (limit %.5f)" % [
		box.position.x, box.end.x, box.position.z, box.end.z, recipe.half_extent()
	])
	print("   triangles: ", result.triangle_count())
	print("   water parts: %d  never_merge: %s  slots: %s" % [
		water_parts.size(),
		str(water_parts[0].never_merge) if water_parts.size() > 0 else "n/a",
		str(water_parts[0].slots) if water_parts.size() > 0 else "n/a",
	])
	if water_parts.size() > 0:
		var wbox := water_parts[0].mesh.get_aabb()
		print("   water aabb x %.4f..%.4f y %.4f tris %d" % [
			wbox.position.x, wbox.end.x, wbox.position.y, water_parts[0].triangle_count()
		])
	print("   slots used: ", result.slots_used())
	print("   collision shapes: ", result.collision.size())
	print("   validator: ", report.text().replace("\n", " | "))
	print("   debug: ", result.debug)

	# Slot painting spot checks.
	var centre_slot := field.slot_at(field.resolution / 2, field.resolution / 2)
	var corner_slot := field.slot_at(0, 0)
	print("   centre slot=%s  corner slot=%s" % [centre_slot, corner_slot])

	# Rejection cases.
	var bad := TileSurfaceLayer.new()
	bad.generator_id = "basin"
	bad.layer_name = "bad"
	bad.resolution = 5
	bad.params = {"shape": "blob", "inner": 0.99, "depth": -0.2, "water_level": 0.5}
	var ctx := TileGenerationContext.new(_make_recipe(5, bad))
	print("   rejects: ", Array(BasinGenerator.new().validate(bad, ctx)))


func _probe_custom() -> void:
	# Bake a throwaway source mesh so the loader path is exercised for real.
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 0.4, 1.0)
	var source := ArrayMesh.new()
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.surface_get_arrays(0))
	source.surface_set_name(0, "accent")
	var path := "res://tools/tile_forge/_tmp_probe_mesh.res"
	ResourceSaver.save(source, path)

	var layer := TileSurfaceLayer.new()
	layer.generator_id = "custom_mesh"
	layer.layer_name = "hero"
	layer.material_slot = TileForgeConstants.SLOT_TOP_PRIMARY
	layer.params = {"mesh_path": path, "scale": 1.0}
	var recipe := TileRecipe.new()
	recipe.tile_id = "probe_custom"
	recipe.edge_policy = TileForgeConstants.EdgePolicy.CUSTOM
	recipe.collision_mode = TileForgeConstants.CollisionMode.FLAT_BOX
	recipe.surface_layers = [layer]

	print("--- custom_mesh oversized (expect rejection)")
	var result := TileForgeBuilder.build(recipe)
	print("   ctx errors: ", result.context.errors)
	print("   ctx messages: ", result.context.messages)

	print("--- custom_mesh fit_to_tile + yaw + slot override")
	layer.params = {
		"mesh_path": path,
		"scale": 1.0,
		"yaw_deg": 30.0,
		"fit_to_tile": true,
		"offset_y": 0.05,
		"slot_overrides": {"accent": TileForgeConstants.SLOT_SIDE},
	}
	var fitted := TileForgeBuilder.build(recipe)
	print("   ctx errors: ", fitted.context.errors)
	var fbox := fitted.bounds()
	print("   bounds x %.5f..%.5f  z %.5f..%.5f  y %.4f..%.4f (limit %.5f)" % [
		fbox.position.x, fbox.end.x, fbox.position.z, fbox.end.z,
		fbox.position.y, fbox.end.y, recipe.half_extent()
	])
	print("   slots used: ", fitted.slots_used())
	print("   triangles: ", fitted.triangle_count())
	print("   debug: ", fitted.debug)
	var generator := CustomMeshGenerator.new()
	print("   get_bounds: ", generator.get_bounds(layer, fitted.context))

	print("--- custom_mesh rejections")
	var bad := TileSurfaceLayer.new()
	bad.generator_id = "custom_mesh"
	bad.layer_name = "bad"
	var ctx := TileGenerationContext.new(recipe)
	bad.params = {}
	print("   missing: ", Array(generator.validate(bad, ctx)))
	bad.params = {"mesh_path": "res://nope/missing.glb"}
	print("   absent: ", Array(generator.validate(bad, ctx)))
	bad.params = {"mesh_path": path, "scale": 0.0}
	print("   zero scale: ", Array(generator.validate(bad, ctx)))
	bad.params = {"mesh_path": path, "scale": 0.5, "slot_overrides": {"accent": "not_a_slot"}}
	print("   bad slot: ", Array(generator.validate(bad, ctx)))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
