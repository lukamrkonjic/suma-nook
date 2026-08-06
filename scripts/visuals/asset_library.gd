class_name AssetLibrary
extends RefCounted
## Resolves game-ready scenes and approved procedural models by stable asset id,
## then instantiates them with library materials bound. Gameplay code never
## touches file paths: definitions carry asset ids and this class owns the
## implementation route.

## Tile Forge bakes finished tile layers as PackedScenes rather than GLBs, so
## the baked directory joins the search order. A baked tile is then an ordinary
## asset id in data/tiles.json and needs no other integration.
const SEARCH_PATHS := [
	"res://assets/3d/reworked/%s.glb",
	"res://assets/3d/final/%s.glb",
	"res://assets/3d/proxies/%s.glb",
	"res://tools/tile_forge/baked/%s.tscn",
	"res://tools/tile_kit/baked/%s.tscn",
]
const AssetEditLibraryScript := preload(
	"res://scripts/visuals/asset_edit_library.gd"
)
const ProceduralStoneWallScript := preload(
	"res://scripts/visuals/procedural_stone_wall.gd"
)
const PROCEDURAL_ASSET_IDS := {
	"prop_stone_wall_polished": true,
}

var materials: MaterialLibrary
var edits: AssetEditLibrary
var _cache: Dictionary = {}
var _batch_mesh_cache: Dictionary = {}


func _init(material_library: MaterialLibrary) -> void:
	materials = material_library
	edits = AssetEditLibraryScript.new()


func exists(asset_id: String) -> bool:
	return PROCEDURAL_ASSET_IDS.has(asset_id) or resolve_path(asset_id) != ""


static func resolve_path(asset_id: String) -> String:
	for pattern: String in SEARCH_PATHS:
		var path: String = pattern % asset_id
		if ResourceLoader.exists(path):
			return path
	return ""


func instantiate(asset_id: String) -> Node3D:
	if PROCEDURAL_ASSET_IDS.has(asset_id):
		var procedural := ProceduralStoneWallScript.build()
		procedural.name = asset_id
		procedural.set_meta(AssetEditLibrary.SOURCE_ASSET_META, asset_id)
		edits.apply_to_instance(procedural, asset_id)
		return procedural
	var packed := _packed(asset_id)
	if packed == null:
		push_warning("AssetLibrary: missing asset '%s' — using fallback marker" % asset_id)
		return _missing_marker(asset_id)
	var node := packed.instantiate() as Node3D
	node.name = asset_id
	node.set_meta(AssetEditLibrary.SOURCE_ASSET_META, asset_id)
	materials.rebind_materials(node)
	edits.apply_to_instance(node, asset_id)
	return node


## Asset Studio streams large procedural topology scenes off the main thread,
## then hands the completed PackedScene to the ordinary asset cache. Runtime
## consumers still resolve assets by stable ID; this only avoids repeating a
## synchronous text-scene parse at the moment the designer changes selection.
func prime_packed_scene(asset_id: String, packed: PackedScene) -> void:
	if not asset_id.is_empty() and packed != null:
		_cache[asset_id] = packed


func has_cached_scene(asset_id: String) -> bool:
	return _cache.has(asset_id) and _cache[asset_id] is PackedScene


func save_asset_profile(asset_id: String, profile: Dictionary) -> Error:
	var error := edits.save_profile(asset_id, profile)
	if error == OK:
		_batch_mesh_cache.erase(asset_id)
	return error


func clear_edit_caches() -> void:
	## Presentation profiles can be consumed by more than the direct asset
	## batch (layered tiles and structures flatten several assets together).
	## WorldRenderer calls this before rebuilding its dependent caches.
	_batch_mesh_cache.clear()


func apply_asset_profile_to_tree(
	root: Node,
	asset_id: String,
	profile: Dictionary
) -> void:
	edits.apply_to_tree(root, asset_id, profile)


## Flattens a static GLB once and reuses the resulting material-preserving
## ArrayMesh in chunk MultiMeshes. Dynamic/player assets keep the ordinary
## instantiate path.
func batch_mesh(asset_id: String) -> ArrayMesh:
	if _batch_mesh_cache.has(asset_id):
		return _batch_mesh_cache[asset_id]
	var template: Node3D
	if PROCEDURAL_ASSET_IDS.has(asset_id):
		template = ProceduralStoneWallScript.build()
	else:
		var packed := _packed(asset_id)
		if packed == null:
			return null
		template = packed.instantiate() as Node3D
	template.set_meta(AssetEditLibrary.SOURCE_ASSET_META, asset_id)
	if not PROCEDURAL_ASSET_IDS.has(asset_id):
		materials.rebind_materials(template)
	edits.apply_to_instance(template, asset_id)
	var combined := flatten_static_visual(template, asset_id)
	template.free()
	if combined != null:
		_batch_mesh_cache[asset_id] = combined
	return combined


## Combines every visible triangle mesh below `root`, retaining one surface
## per active material. This also supports generated/layered tile visuals.
func flatten_static_visual(root: Node3D, resource_name := "") -> ArrayMesh:
	var by_material: Dictionary = {}
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if not _locally_visible(mesh_instance, root):
			continue
		var source_mesh := mesh_instance.mesh
		if source_mesh == null:
			continue
		var relative := _transform_below_root(mesh_instance, root)
		for surface in source_mesh.get_surface_count():
			var active_material := mesh_instance.get_active_material(surface)
			var material_key := (
				"none"
				if active_material == null
				else str(active_material.get_instance_id())
			)
			if not by_material.has(material_key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tool.set_material(active_material)
				by_material[material_key] = tool
			(by_material[material_key] as SurfaceTool).append_from(
				source_mesh,
				surface,
				relative
			)
	var combined := ArrayMesh.new()
	combined.resource_name = resource_name
	for surface_tool: SurfaceTool in by_material.values():
		surface_tool.commit(combined)
	return combined if combined.get_surface_count() > 0 else null


func _locally_visible(node: Node3D, root: Node3D) -> bool:
	var current: Node = node
	while current != null and current != root:
		if current is VisualInstance3D and not (current as VisualInstance3D).visible:
			return false
		current = current.get_parent()
	return true


func _transform_below_root(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func catalog_ids() -> Array[String]:
	## Returns every unique production GLB id visible to the resolver. The
	## asset and content validation tools use this instead of a hand-maintained
	## roster, so new models are discovered as soon as they enter an asset tier.
	var unique := {}
	for pattern: String in SEARCH_PATHS:
		var directory_path: String = pattern.get_base_dir()
		var directory := DirAccess.open(directory_path)
		if directory == null:
			continue
		for filename in directory.get_files():
			if filename.get_extension().to_lower() == "glb":
				unique[filename.get_basename()] = true
	for asset_id: String in PROCEDURAL_ASSET_IDS:
		unique[asset_id] = true
	var result: Array[String] = []
	for asset_id: String in unique:
		result.append(asset_id)
	result.sort()
	return result


func _packed(asset_id: String) -> PackedScene:
	if _cache.has(asset_id):
		return _cache[asset_id]
	var path := resolve_path(asset_id)
	var packed: PackedScene = load(path) if path != "" else null
	_cache[asset_id] = packed
	return packed


func _missing_marker(asset_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "missing_%s" % asset_id
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	mesh.mesh = box
	mesh.position.y = 0.2
	mesh.material_override = materials.material("magic")
	root.add_child(mesh)
	return root
