@tool
class_name TileV2Generator
extends Node3D
## Preview/bake host for one V2 tile — the V2 sibling of TileKitGenerator.
##
## Holds a TileV2Recipe, rebuilds two MeshInstance3D children (surface =
## sculpt + skirt + structures, base = the persistent below-seam body), and
## exposes the same bake_role_scenes()/statistics() contract the layered
## runtime pipeline consumes. Meshes are cached per recipe fingerprint so a
## 3×3 sheet of one recipe builds once.

static var _mesh_cache: Dictionary = {}

var recipe: TileV2Recipe:
	set(value):
		recipe = value
		if is_inside_tree():
			rebuild()

## Presentation-only: hide the deep structural body in ground-level previews.
var show_structural_base := true:
	set(value):
		show_structural_base = value
		if _base_instance != null:
			_base_instance.visible = value

var _surface_instance: MeshInstance3D
var _base_instance: MeshInstance3D
var _stats: Dictionary = {}


func _ready() -> void:
	if recipe == null:
		recipe = TileV2Library.recipe("tile_v2_moss_cushion")
	rebuild()


func rebuild() -> void:
	if recipe == null:
		return
	var built := build_meshes(recipe)
	if _surface_instance == null:
		_surface_instance = MeshInstance3D.new()
		_surface_instance.name = "Surface"
		add_child(_surface_instance)
	if _base_instance == null:
		_base_instance = MeshInstance3D.new()
		_base_instance.name = "Base"
		add_child(_base_instance)
	_surface_instance.mesh = built["surface"]
	_base_instance.mesh = built["base"]
	_base_instance.visible = show_structural_base
	_stats = built["stats"]


## Builds (or fetches) the meshes for a recipe. Deterministic: fingerprint →
## identical ArrayMeshes.
static func build_meshes(for_recipe: TileV2Recipe) -> Dictionary:
	var fingerprint := for_recipe.fingerprint()
	if _mesh_cache.has(fingerprint):
		return _mesh_cache[fingerprint]
	var composed := TileV2Library.compose(for_recipe)
	var field: TileV2Field = composed["field"]
	var result := TileV2Mesher.build(field, composed["body"], for_recipe.resolution)
	# Structure pieces settle into the finished field.
	var piece_rng := RandomNumberGenerator.new()
	piece_rng.seed = hash("tilev2_pieces|%s|%d" % [for_recipe.family, for_recipe.seed])
	for piece: Dictionary in composed["pieces"]:
		match String(piece["type"]):
			"chip":
				TileV2Structures.add_chip(result.surface_batch,
					TileV2Palette.color(String(piece["key"])), field,
					piece["at"], float(piece["length"]), float(piece["width"]),
					float(piece["height"]), float(piece["yaw"]), piece_rng,
					float(piece.get("sink", 0.38)))
			"pebble":
				TileV2Structures.add_pebble(result.surface_batch,
					TileV2Palette.color(String(piece["key"])), field,
					piece["at"], float(piece["radius"]), float(piece["height"]),
					float(piece["yaw"]), piece_rng)
			"solid":
				TileV2Pieces.add_solid(result.surface_batch, field,
					piece["at"], float(piece.get("yaw", 0.0)),
					piece["spec"], piece_rng)
			"stroke":
				TileV2Pieces.add_stroke(result.surface_batch, field,
					piece["start"], piece["end"], float(piece["bow"]),
					float(piece["width"]), float(piece["height"]),
					piece["color"], piece["color_high"])
	var surface_triangles := result.surface_batch.triangle_count()
	var base_triangles := result.base_batch.triangle_count()
	var material := TileV2Palette.tile_material()
	var built := {
		"surface": result.surface_batch.commit(material),
		"base": result.base_batch.commit(material),
		"stats": {
			"triangles": surface_triangles + base_triangles,
			"surface_triangles": surface_triangles,
			"base_triangles": base_triangles,
			"max_height": result.max_height,
			"min_height": result.min_height,
			"pieces": (composed["pieces"] as Array).size(),
		},
	}
	_mesh_cache[fingerprint] = built
	return built


static func clear_cache() -> void:
	_mesh_cache.clear()


func statistics() -> Dictionary:
	var stats := _stats.duplicate()
	var materials: Dictionary = {}
	var vertices := 0
	for instance in [_surface_instance, _base_instance]:
		if instance == null or instance.mesh == null:
			continue
		var mesh: ArrayMesh = instance.mesh
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var material := mesh.surface_get_material(surface)
			if material != null:
				materials[material.resource_name] = true
	stats["vertices"] = vertices
	stats["materials"] = materials.size()
	return stats


## Same role-scene contract as TileKitGenerator: base persists when covered,
## surface hides. V2 needs no separate detail role — structure is material.
func bake_role_scenes() -> Dictionary:
	var scenes: Dictionary = {}
	for entry: Array in [
		["base", _base_instance], ["surface", _surface_instance],
	]:
		var role := String(entry[0])
		var instance: MeshInstance3D = entry[1]
		if instance == null or instance.mesh == null:
			continue
		var root := Node3D.new()
		root.name = "tile_v2_%s" % role
		var copy := MeshInstance3D.new()
		copy.name = role
		copy.mesh = instance.mesh
		root.add_child(copy)
		copy.owner = root
		var packed := PackedScene.new()
		packed.pack(root)
		scenes[role] = packed
		root.free()
	return scenes
