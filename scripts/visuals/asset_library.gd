class_name AssetLibrary
extends RefCounted
## Loads game-ready GLB scenes by stable asset id and instantiates them with
## library materials bound. Gameplay code never touches file paths: definitions
## carry asset ids, this class resolves them. Tier C swaps (proxy -> hero) are
## file replacements at the same id — zero code changes.

const SEARCH_PATHS := ["res://assets/3d/reworked/%s.glb", "res://assets/3d/final/%s.glb", "res://assets/3d/proxies/%s.glb"]

var materials: MaterialLibrary
var _cache: Dictionary = {}


func _init(material_library: MaterialLibrary) -> void:
	materials = material_library


func exists(asset_id: String) -> bool:
	return _resolve(asset_id) != ""


func instantiate(asset_id: String) -> Node3D:
	var packed := _packed(asset_id)
	if packed == null:
		push_warning("AssetLibrary: missing asset '%s' — using fallback marker" % asset_id)
		return _missing_marker(asset_id)
	var node := packed.instantiate() as Node3D
	node.name = asset_id
	materials.rebind_materials(node)
	return node


func catalog_ids() -> Array[String]:
	## Returns every unique production GLB id visible to the resolver. The
	## admin asset world uses this instead of a hand-maintained roster, so new
	## models appear there as soon as they are added to an asset tier.
	var unique := {}
	for pattern: String in SEARCH_PATHS:
		var directory_path: String = pattern.get_base_dir()
		var directory := DirAccess.open(directory_path)
		if directory == null:
			continue
		for filename in directory.get_files():
			if filename.get_extension().to_lower() == "glb":
				unique[filename.get_basename()] = true
	var result: Array[String] = []
	for asset_id: String in unique:
		result.append(asset_id)
	result.sort()
	return result


func _packed(asset_id: String) -> PackedScene:
	if _cache.has(asset_id):
		return _cache[asset_id]
	var path := _resolve(asset_id)
	var packed: PackedScene = load(path) if path != "" else null
	_cache[asset_id] = packed
	return packed


func _resolve(asset_id: String) -> String:
	for pattern in SEARCH_PATHS:
		var path: String = pattern % asset_id
		if ResourceLoader.exists(path):
			return path
	return ""


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
