@tool
class_name TileGenerationContext
extends RefCounted
## Everything a generator is allowed to know, and the only place it may write
## shared state.
##
## Generators receive a context and their own layer. They must not reach for
## globals, load files by hard-coded path, or call an unseeded RNG. That
## discipline is what makes a bake reproducible and a variant set trustworthy.

var recipe: TileRecipe
var palette: TilePalette
var base_profile: TileBaseProfile
## Shared art direction. Never null: generators may read it unconditionally.
var art: SumaTileArtProfile

## LIVE metres.
var tile_size := TileForgeConstants.LIVE_TILE_SIZE
var half_extent := TileForgeConstants.LIVE_HALF_EXTENT
## Tile coordinate, when generating in place. Zero for a lab/bake build.
var tile_coord := Vector2i.ZERO

## The shared top. Heightfield generators write it; everyone else reads it.
var field: TileHeightField

## Neighbour surface families keyed "north"/"east"/"south"/"west" plus the four
## diagonals. Empty string means "unknown / same".
var neighbours: Dictionary = {}

## Loaded module meshes, keyed by res:// path. Shared across a whole bake run
## so 10 recipes do not reload the same pebble 60 times.
var module_library: Dictionary = {}

var preview_mode := false
var messages: PackedStringArray = []
var errors: PackedStringArray = []

## Footprints already claimed on this tile, as (x, z, radius). Shared across
## EVERY detail rule: two rules that each look tidy on their own will otherwise
## drop a stone through a grass clump, because neither can see the other.
var occupied: PackedVector3Array = PackedVector3Array()

var _base_seed := 0


func _init(source: TileRecipe) -> void:
	recipe = source
	if source != null:
		tile_size = source.tile_size
		half_extent = source.half_extent()
		palette = source.palette
		base_profile = source.base_profile
		art = source.art_profile
		_base_seed = source.effective_seed()
	if palette == null:
		palette = TilePalette.new()
	if base_profile == null:
		base_profile = TileBaseProfile.new()
	if art == null:
		art = SumaTileArtProfile.default()


func base_seed() -> int:
	return _base_seed


## The only way a generator may obtain randomness.
func rng(channel: String, offset := 0) -> RandomNumberGenerator:
	return TileSeedUtil.rng_for(_base_seed, channel, offset)


func report(message: String) -> void:
	messages.append(message)


func fail(message: String) -> void:
	errors.append(message)


## Normalized (-1..1) to LIVE world XZ.
func to_world(u: float, v: float) -> Vector2:
	return Vector2(u * half_extent, v * half_extent)


func to_normalized(x: float, z: float) -> Vector2:
	return Vector2(x / half_extent, z / half_extent)


## Height of the shared top at a normalized coordinate, or the flat plane when
## no heightfield layer ran.
func surface_height(u: float, v: float) -> float:
	if field == null:
		return 0.0
	return field.sample(u, v)


func surface_normal(u: float, v: float) -> Vector3:
	if field == null:
		return Vector3.UP
	return field.normal_at(u, v)


## Loads and caches a module mesh. Accepts .glb/.tscn (instantiated then
## flattened) and .res/.tres holding a Mesh directly.
func module_mesh(path: String) -> ArrayMesh:
	if path == "":
		return null
	if module_library.has(path):
		return module_library[path]
	var mesh := _load_module_mesh(path)
	module_library[path] = mesh
	if mesh == null:
		fail("module mesh missing or unreadable: %s" % path)
	return mesh


func _load_module_mesh(path: String) -> ArrayMesh:
	if not ResourceLoader.exists(path):
		return null
	var resource := ResourceLoader.load(path)
	if resource is ArrayMesh:
		return resource
	if resource is Mesh:
		return _to_array_mesh(resource)
	if resource is PackedScene:
		var instance := (resource as PackedScene).instantiate()
		var merged := _flatten(instance)
		instance.free()
		return merged
	return null


static func _to_array_mesh(source: Mesh) -> ArrayMesh:
	if source is ArrayMesh:
		return source
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		result.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			source.surface_get_arrays(surface)
		)
	return result


## Merges every MeshInstance3D under `root` into one ArrayMesh, preserving one
## surface per distinct source material NAME. Module GLBs use semantic material
## slot names, so this is how a two-tone clump keeps its two regions.
static func _flatten(root: Node) -> ArrayMesh:
	var tools: Dictionary = {}
	var order: PackedStringArray = []
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.mesh == null:
			continue
		var relative := Transform3D.IDENTITY
		var cursor: Node = instance
		while cursor != null and cursor != root:
			if cursor is Node3D:
				relative = (cursor as Node3D).transform * relative
			cursor = cursor.get_parent()
		for surface in instance.mesh.get_surface_count():
			var material := instance.mesh.surface_get_material(surface)
			var key := "surface_%d" % surface
			if material != null and material.resource_name != "":
				key = material.resource_name
			elif instance.mesh.surface_get_name(surface) != "":
				key = instance.mesh.surface_get_name(surface)
			if not tools.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = tool
				order.append(key)
			(tools[key] as SurfaceTool).append_from(instance.mesh, surface, relative)
	if order.is_empty():
		return null
	var combined := ArrayMesh.new()
	for key in order:
		var tool: SurfaceTool = tools[key]
		tool.commit(combined)
		combined.surface_set_name(combined.get_surface_count() - 1, key)
	return combined


func debug_summary() -> Dictionary:
	return {
		"tile_id": recipe.tile_id if recipe != null else "",
		"seed": _base_seed,
		"variant": recipe.variant if recipe != null else 0,
		"tile_size": tile_size,
		"resolution": field.resolution if field != null else 0,
		"messages": Array(messages),
		"errors": Array(errors),
	}
