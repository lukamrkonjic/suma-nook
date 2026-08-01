@tool
class_name TileBaker
extends RefCounted
## Turns a TileBuildResult into nodes, and nodes into shipped files.
##
## Two entry points, one code path:
##   `assemble()` builds the node tree used by the lab preview;
##   `bake()`     saves that same tree, plus its meshes and manifest.
##
## Preview and shipped asset can therefore never disagree. Runtime generation
## stays available for debugging, but production tiles go through `bake()` and
## are loaded by the existing world placement system as ordinary assets.
##
## MATERIAL BINDING. Baked surfaces carry a placeholder StandardMaterial3D
## whose `resource_name` is a semantic palette key. That is the same convention
## the shipped GLB catalog uses, so `MaterialLibrary.rebind_materials()` swaps
## in the one shared game material on instantiate and a palette edit re-skins
## generated tiles along with everything else. No per-tile material is created.
##
## SPACE. Everything is baked in LIVE metres and the manifest declares
## `scale_mode: "none"`, so `TileVisualFactory` applies no X/Z scale to it. The
## shared structural base keeps its authored 1.70 m footprint and its own
## `tile_xz` scaling; both land on exactly the same 1.35 m boundary.

const MESH_SUBDIR := "meshes"


## Builds the runtime node tree. `material_library` may be null in a headless
## context; the placeholder materials still carry correct colours.
static func assemble(
	result: TileBuildResult,
	material_library: MaterialLibrary = null,
	cozy_palette: CozyPalette = null
) -> Node3D:
	var root := Node3D.new()
	root.name = "GeneratedTile"
	if result == null or result.recipe == null:
		return root

	var recipe := result.recipe
	root.set_meta("tile_forge_id", recipe.tile_id)
	root.set_meta("tile_forge_seed", recipe.effective_seed())
	root.set_meta("tile_forge_variant", recipe.variant)

	var surface_parts: Array[TileMeshPart] = []
	var water_parts: Array[TileMeshPart] = []
	var detail_parts: Array[TileMeshPart] = []
	var separate_parts: Array[TileMeshPart] = []
	# The structural body is kept apart from the top so a covered tile can hide
	# its surface and dressing while the block itself persists — the same
	# contract the shipped layered tiles use.
	var base_parts: Array[TileMeshPart] = []
	for part in result.parts:
		if part == null or part.mesh == null:
			continue
		if part.separate_render_layer:
			separate_parts.append(part)
		elif part.never_merge or part.part_role == "water":
			water_parts.append(part)
		elif part.part_role == "detail":
			detail_parts.append(part)
		elif part.part_role == "base":
			base_parts.append(part)
		else:
			surface_parts.append(part)

	var art := result.context.art
	_add_mesh_node(
		root, "StructuralBase", base_parts, recipe, material_library, cozy_palette, art
	)
	_add_mesh_node(
		root, "Surface", surface_parts, recipe, material_library, cozy_palette, art
	)
	_add_mesh_node(
		root, "DetailStatic", detail_parts, recipe, material_library, cozy_palette, art
	)
	_add_mesh_node(
		root, "Water", water_parts, recipe, material_library, cozy_palette, art
	)
	for part in separate_parts:
		var node_name := "Layer_%s" % part.layer_name.capitalize().replace(" ", "")
		_add_mesh_node(
			root, node_name, [part], recipe, material_library, cozy_palette, art
		)

	_add_multimesh_nodes(root, result, recipe, material_library, cozy_palette, art)
	_add_debug_nodes(root, result)
	_add_collision(root, result)
	_add_metadata(root, result)
	return root


## Builds, validates, and writes every artefact for one recipe.
static func bake(
	recipe: TileRecipe,
	output_dir := TileForgeConstants.BAKED_DIR,
	material_library: MaterialLibrary = null,
	cozy_palette: CozyPalette = null,
	shared_modules: Dictionary = {}
) -> TileBakeManifest:
	var manifest := TileBakeManifest.new()
	manifest.tile_id = recipe.baked_asset_id()
	manifest.display_name = recipe.display_name
	manifest.recipe_path = recipe.resource_path
	manifest.seed_value = recipe.seed_value
	manifest.variant = recipe.variant
	manifest.recipe_hash = "%016x" % TileSeedUtil.hash_string(_recipe_signature(recipe))
	manifest.baked_at = Time.get_datetime_string_from_system(true)
	manifest.forge_version = TileForgeBuilder.FORGE_VERSION
	manifest.connection_mode = recipe.connection_mode
	manifest.collision_mode = TileForgeConstants.CollisionMode.keys()[recipe.collision_mode]
	manifest.scale_mode = "none"
	if recipe.base_profile != null:
		manifest.shared_base_asset = recipe.base_profile.shared_base_asset()

	var result := TileForgeBuilder.build(recipe, {}, false, shared_modules)
	var report := TileValidator.validate(result)
	manifest.errors = report.errors
	manifest.warnings = report.warnings
	manifest.checks_run = report.checks
	manifest.passed = report.ok()

	var field := result.context.field
	if field != null:
		manifest.measured_walk_height = (
			recipe.walk_surface_height
			if recipe.walk_surface_height >= 0.0
			else snappedf(field.median_height(), 0.005)
		)
		manifest.exposed_top = TileForgeConstants.exposed_top_for(
			field.min_height(), field.max_height()
		)

	var box := result.bounds()
	manifest.bounds_min = box.position
	manifest.bounds_max = box.end
	manifest.module_instance_count = result.instances.size()

	if not manifest.passed:
		# A failing recipe is never written. Silently shipping a tile that the
		# validator rejected is how a bad asset reaches a screenshot review.
		return manifest

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(output_dir.path_join(MESH_SUBDIR))
	)

	var root := assemble(result, material_library, cozy_palette)
	_save_meshes(root, output_dir, manifest.tile_id)

	var counts := _count_geometry(root)
	manifest.triangle_count = counts.get("triangles", 0)
	manifest.vertex_count = counts.get("vertices", 0)
	manifest.surface_triangle_count = counts.get("surface_triangles", 0)
	manifest.detail_triangle_count = counts.get("detail_triangles", 0)
	manifest.material_count = counts.get("materials", 0)
	manifest.materials_used = counts.get("materials_used", PackedStringArray())
	manifest.node_count = counts.get("nodes", 0)

	var packed := PackedScene.new()
	_claim_ownership(root, root)
	var pack_error := packed.pack(root)
	if pack_error != OK:
		manifest.passed = false
		manifest.errors.append("PackedScene.pack failed: %d" % pack_error)
		root.free()
		return manifest

	var scene_path := output_dir.path_join("%s.tscn" % manifest.tile_id)
	var save_error := ResourceSaver.save(packed, scene_path)
	if save_error != OK:
		manifest.passed = false
		manifest.errors.append("could not save %s: %d" % [scene_path, save_error])
		root.free()
		return manifest

	var manifest_path := output_dir.path_join("%s_manifest.tres" % manifest.tile_id)
	ResourceSaver.save(manifest, manifest_path)
	_write_report(output_dir, manifest, report)
	root.free()
	return manifest


## Bakes a curated variant set, discarding seeds the validator rejects.
static func bake_variant_set(
	recipe: TileRecipe,
	count: int,
	output_dir := TileForgeConstants.BAKED_DIR,
	material_library: MaterialLibrary = null,
	cozy_palette: CozyPalette = null
) -> Array[TileBakeManifest]:
	var results: Array[TileBakeManifest] = []
	var shared_modules: Dictionary = {}
	for index in count:
		var variant := recipe.with_variant(index)
		results.append(
			bake(variant, output_dir, material_library, cozy_palette, shared_modules)
		)
	return results


# --- node construction -------------------------------------------------------

static func _add_mesh_node(
	root: Node3D,
	node_name: String,
	parts: Array,
	recipe: TileRecipe,
	material_library: MaterialLibrary,
	cozy_palette: CozyPalette,
	art: SumaTileArtProfile = null
) -> void:
	if parts.is_empty():
		return
	var combined := ArrayMesh.new()
	combined.resource_name = "%s_%s" % [recipe.tile_id, node_name.to_snake_case()]
	var slots := PackedStringArray()
	for part in parts:
		var typed := part as TileMeshPart
		for surface in typed.mesh.get_surface_count():
			combined.add_surface_from_arrays(
				Mesh.PRIMITIVE_TRIANGLES,
				typed.mesh.surface_get_arrays(surface)
			)
			var slot := typed.slot_for_surface(surface)
			combined.surface_set_name(combined.get_surface_count() - 1, slot)
			slots.append(slot)
	if combined.get_surface_count() == 0:
		return

	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = combined
	for index in slots.size():
		var material := _placeholder_material(
			slots[index], recipe.palette, material_library, cozy_palette, art
		)
		if material != null:
			combined.surface_set_material(index, material)
	root.add_child(instance)


## MultiMesh path. Kept because the brief requires it and because a standalone
## consumer of the Forge may want it; Suma's own recipes use merged static
## detail, and the validator says so.
static func _add_multimesh_nodes(
	root: Node3D,
	result: TileBuildResult,
	recipe: TileRecipe,
	material_library: MaterialLibrary,
	cozy_palette: CozyPalette,
	art: SumaTileArtProfile = null
) -> void:
	var groups: Dictionary = {}
	for instance in result.instances:
		if instance.output != TileForgeConstants.DetailOutput.MULTIMESH \
			and instance.output != TileForgeConstants.DetailOutput.SEPARATE_RENDER_LAYER:
			continue
		if not groups.has(instance.group_key):
			groups[instance.group_key] = []
		(groups[instance.group_key] as Array).append(instance)

	var keys := groups.keys()
	keys.sort()
	for key: String in keys:
		var members: Array = groups[key]
		if members.is_empty():
			continue
		var first: TileModuleInstance = members[0]
		var source := result.context.module_mesh(first.module_path)
		if source == null:
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = source
		multi.instance_count = members.size()
		for index in members.size():
			multi.set_instance_transform(index, (members[index] as TileModuleInstance).transform)
		var node := MultiMeshInstance3D.new()
		node.name = "DetailMultiMesh_%s" % first.module_path.get_file().get_basename()
		node.multimesh = multi
		var material := _placeholder_material(
			first.material_slot, recipe.palette, material_library, cozy_palette, art
		)
		if material != null:
			node.material_override = material
		root.add_child(node)


static func _add_debug_nodes(root: Node3D, result: TileBuildResult) -> void:
	var debug_instances: Array[TileModuleInstance] = []
	for instance in result.instances:
		if instance.output == TileForgeConstants.DetailOutput.INDIVIDUAL_DEBUG_NODES:
			debug_instances.append(instance)
	if debug_instances.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "DetailNodes"
	root.add_child(holder)
	for index in debug_instances.size():
		var instance := debug_instances[index]
		var mesh := result.context.module_mesh(instance.module_path)
		if mesh == null:
			continue
		var node := MeshInstance3D.new()
		node.name = "%s_%02d" % [instance.module_path.get_file().get_basename(), index]
		node.mesh = mesh
		node.transform = instance.transform
		holder.add_child(node)


static func _add_collision(root: Node3D, result: TileBuildResult) -> void:
	if result.collision.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	root.add_child(body)
	for entry: Dictionary in result.collision:
		var shape_resource: Variant = entry.get("shape")
		if shape_resource == null:
			continue
		var shape := CollisionShape3D.new()
		shape.name = String(entry.get("name", "Shape"))
		shape.shape = shape_resource
		shape.transform = entry.get("transform", Transform3D.IDENTITY)
		body.add_child(shape)


static func _add_metadata(root: Node3D, result: TileBuildResult) -> void:
	var node := Node.new()
	node.name = "Metadata"
	var recipe := result.recipe
	node.set_meta("tile_id", recipe.tile_id)
	node.set_meta("recipe_path", recipe.resource_path)
	node.set_meta("seed", recipe.seed_value)
	node.set_meta("variant", recipe.variant)
	node.set_meta("forge_version", TileForgeBuilder.FORGE_VERSION)
	node.set_meta("connection_mode", recipe.connection_mode)
	node.set_meta("category", TileForgeConstants.category_name(recipe.category))
	if recipe.base_profile != null:
		node.set_meta("shared_base_asset", recipe.base_profile.shared_base_asset())
	root.add_child(node)


## Placeholder material named after a semantic palette key. The name is the
## contract; the colour only makes the baked scene readable on its own.
static func _placeholder_material(
	slot: String,
	palette: TilePalette,
	material_library: MaterialLibrary,
	cozy_palette: CozyPalette,
	art: SumaTileArtProfile = null
) -> StandardMaterial3D:
	if palette == null:
		return null
	var key := palette.key_for_slot(slot)
	if key == "":
		return null
	if art == null:
		art = SumaTileArtProfile.default()

	var material := StandardMaterial3D.new()
	material.roughness = art.roughness
	material.metallic_specular = art.specular
	material.metallic = art.metallic

	var top := _palette_colour(
		palette.key_for_slot(TileForgeConstants.SLOT_TOP_PRIMARY),
		material_library,
		cozy_palette
	)
	var derived := false
	var colour := _palette_colour(key, material_library, cozy_palette)

	# Derived tones are named OUTSIDE the semantic palette on purpose, so
	# MaterialLibrary.rebind_materials leaves them alone and the tile keeps the
	# exact value relationship the art profile specifies.
	if palette.derive_side_from_top:
		match slot:
			TileForgeConstants.SLOT_SIDE:
				colour = art.side_colour(top)
				derived = true
			TileForgeConstants.SLOT_UNDERSIDE:
				colour = art.inset_colour(top)
				derived = true
			TileForgeConstants.SLOT_INSET:
				colour = art.inset_colour(top)
				derived = true
	if palette.derive_rim_from_top and slot == TileForgeConstants.SLOT_ACCENT:
		colour = top.lightened(palette.rim_lighten)
		derived = true

	material.resource_name = (
		"tf_%s_%s" % [palette.palette_id, slot] if derived else key
	)
	material.albedo_color = colour
	return material


static func _palette_colour(
	key: String,
	material_library: MaterialLibrary,
	cozy_palette: CozyPalette
) -> Color:
	if key == "":
		return Color(0.7, 0.7, 0.7)
	if cozy_palette != null and cozy_palette.colors.has(key):
		return cozy_palette.color(key)
	if material_library != null and material_library.palette != null \
		and material_library.palette.colors.has(key):
		return material_library.palette.color(key)
	return Color(0.7, 0.7, 0.7)


# --- saving ------------------------------------------------------------------

## Writes each generated mesh as its own .res so the .tscn stays small and a
## mesh can be inspected or reused independently.
static func _save_meshes(root: Node3D, output_dir: String, tile_id: String) -> void:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null:
			continue
		var path := output_dir.path_join(
			"%s/%s_%s.res" % [MESH_SUBDIR, tile_id, instance.name.to_snake_case()]
		)
		var error := ResourceSaver.save(instance.mesh, path)
		if error == OK:
			instance.mesh = ResourceLoader.load(path)


static func _claim_ownership(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_claim_ownership(child, owner_node)


static func _count_geometry(root: Node3D) -> Dictionary:
	var triangles := 0
	var surface_triangles := 0
	var detail_triangles := 0
	var vertices := 0
	var materials := PackedStringArray()
	var nodes := 1
	for child in root.find_children("*", "", true, false):
		nodes += 1
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null:
			continue
		var local := 0
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var index_count := (
				(indices as PackedInt32Array).size()
				if indices is PackedInt32Array
				else 0
			)
			vertices += verts.size()
			local += (index_count / 3) if index_count > 0 else (verts.size() / 3)
			var material := instance.mesh.surface_get_material(surface)
			if material != null and not materials.has(material.resource_name):
				materials.append(material.resource_name)
		triangles += local
		if instance.name.begins_with("Detail"):
			detail_triangles += local
		else:
			surface_triangles += local
	return {
		"triangles": triangles,
		"vertices": vertices,
		"surface_triangles": surface_triangles,
		"detail_triangles": detail_triangles,
		"materials": materials.size(),
		"materials_used": materials,
		"nodes": nodes,
	}


static func _write_report(
	output_dir: String,
	manifest: TileBakeManifest,
	report: TileValidator.Report
) -> void:
	var path := output_dir.path_join("%s_report.txt" % manifest.tile_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_line("# %s" % manifest.tile_id)
	file.store_line(manifest.summary_line())
	file.store_line("")
	file.store_line(report.text())
	file.store_line("")
	file.store_line("# data/tiles.json fragment")
	file.store_line(manifest.tiles_json_fragment())
	file.close()


## Stable text signature of the fields that change a bake. Used for the staleness
## hash in the manifest.
static func _recipe_signature(recipe: TileRecipe) -> String:
	var parts: Array[String] = [
		recipe.tile_id,
		str(recipe.seed_value),
		str(recipe.variant),
		str(recipe.tile_size),
		str(recipe.category),
		str(recipe.connected_edge_height),
	]
	for layer in recipe.enabled_surface_layers():
		parts.append("L:%s:%s:%d:%d:%.4f" % [
			layer.generator_id,
			layer.material_slot,
			layer.blend,
			layer.resolution,
			layer.height_scale,
		])
		for shape in layer.shapes:
			if shape != null:
				parts.append("S:%d:%.3f:%.3f:%.3f:%.3f:%.4f" % [
					shape.shape,
					shape.center.x,
					shape.center.y,
					shape.extents.x,
					shape.extents.y,
					shape.height,
				])
	for rule in recipe.enabled_detail_rules():
		parts.append("D:%s:%s:%d:%d:%d" % [
			rule.rule_name,
			rule.generator_id,
			rule.min_count,
			rule.max_count,
			rule.seed_offset,
		])
	return "|".join(parts)
