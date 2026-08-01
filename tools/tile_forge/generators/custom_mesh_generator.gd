@tool
class_name CustomMeshGenerator
extends TileLayerGenerator
## The escape hatch for a hero tile — and the proof that the escape hatch is
## still inside the fence.
##
## A hand-modelled mesh enters through the same door as everything else: loaded
## through the shared module cache, baked into LIVE space by transforming its
## vertices, mapped onto the same material slots, measured against the same
## footprint, and reported through the same debug channel. The artist keeps
## their exact silhouette; the pipeline keeps every guarantee.
##
## The transform is baked into the geometry rather than set on a node because
## TileBaker owns node structure — it merges parts into one MeshInstance3D per
## role, so a node-level scale set here would simply be discarded on the way
## through.
##
## Source normals and smoothing groups are carried through untouched. A hero
## mesh's shading is authored, and regenerating normals over it is how a crisp
## hand-modelled form turns into a soft one.
##
## ## Params:
##   mesh_path       String      res:// path to a .glb / .gltf / .tscn / .scn /
##                               .res / .tres holding a mesh
##   scale           float       uniform scale applied to the source (default 1.0)
##   offset_x        float       LIVE metres, applied after scale, yaw, and fit
##   offset_y        float       LIVE metres
##   offset_z        float       LIVE metres
##   yaw_deg         float       rotation about +Y in degrees (default 0.0)
##   fit_to_tile     bool        uniformly rescale and centre in XZ so the mesh
##                               footprint fills the tile exactly (default false)
##   slot_overrides  Dictionary  source surface or material name -> a
##                               TileForgeConstants slot name

## Containers `TileGenerationContext.module_mesh` knows how to open.
const SUPPORTED_EXTENSIONS: PackedStringArray = [
	"glb", "gltf", "tscn", "scn", "res", "tres"
]
## Matches TileValidator.BOUNDARY_EPSILON: "exactly on the boundary" has to mean
## the same thing here as it does when the build is finally judged.
const FOOTPRINT_EPSILON := 0.0005
## A whole tile should land in the low hundreds of triangles. Past this the
## custom mesh alone has eaten the budget.
const TRIANGLE_ADVICE_LIMIT := 800


func generator_id() -> String:
	return "custom_mesh"


func kinds() -> Array:
	return [TileForgeConstants.Kind.MESH]


func description() -> String:
	return "Bakes a hand-modelled mesh into the tile, policed by the same footprint and slot rules as procedural geometry."


func validate(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> PackedStringArray:
	var problems := PackedStringArray()

	var path := layer.get_string("mesh_path", "")
	if path == "":
		problems.append("mesh_path is required — a custom_mesh layer with no mesh contributes nothing")
		return problems
	if not ResourceLoader.exists(path):
		problems.append("mesh_path does not exist: %s" % path)
		return problems
	var extension := path.get_extension().to_lower()
	if not SUPPORTED_EXTENSIONS.has(extension):
		problems.append(
			"mesh_path '%s' is not a readable mesh container; expected one of %s"
			% [path, ", ".join(SUPPORTED_EXTENSIONS)]
		)
		return problems

	var scale := layer.get_float("scale", 1.0)
	if scale <= 0.0:
		problems.append(
			"scale %.3f must be greater than zero — a zero or mirrored scale inverts the winding"
			% scale
		)

	var raw: Variant = layer.get_param("slot_overrides", {})
	if raw is Dictionary:
		for key in (raw as Dictionary):
			var target := String((raw as Dictionary)[key])
			if not TileForgeConstants.ALL_SLOTS.has(target):
				problems.append(
					"slot_overrides maps '%s' to '%s', which is not a material slot; use one of %s"
					% [String(key), target, ", ".join(TileForgeConstants.ALL_SLOTS)]
				)
	else:
		problems.append("slot_overrides must be a Dictionary of source name -> slot name")

	if scale <= 0.0:
		# Every measurement below would be meaningless at a non-positive scale.
		return problems

	var source := ctx.module_mesh(path)
	if source == null or source.get_surface_count() == 0:
		problems.append("mesh_path '%s' holds no mesh surfaces the forge can read" % path)
		return problems

	_check_footprint(layer, ctx, source, scale, problems)
	_advise(layer, ctx, source)
	return problems


func generate_mesh(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> Array[TileMeshPart]:
	var parts: Array[TileMeshPart] = []
	var path := layer.get_string("mesh_path", "")
	if path == "":
		return parts
	var source := ctx.module_mesh(path)
	if source == null or source.get_surface_count() == 0:
		return parts

	var placement := _placement(layer, ctx, source)
	var transform: Transform3D = placement["transform"]
	var overrides := _overrides(layer)
	var fallback := _fallback_slot(layer)

	# One SurfaceTool per slot, so two source surfaces that resolve to the same
	# slot become one surface and the baked tile does not carry a duplicate
	# material binding for no reason.
	var tools: Dictionary = {}
	var slot_order := PackedStringArray()
	for surface in source.get_surface_count():
		var slot := _slot_for(source, surface, overrides, fallback)
		if not tools.has(slot):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[slot] = tool
			slot_order.append(slot)
		(tools[slot] as SurfaceTool).append_from(source, surface, transform)

	if slot_order.is_empty():
		return parts
	var mesh := ArrayMesh.new()
	for slot in slot_order:
		var tool: SurfaceTool = tools[slot]
		tool.commit(mesh)
		mesh.surface_set_name(mesh.get_surface_count() - 1, slot)

	# Role "surface" on purpose: it puts the hero mesh under the same footprint
	# and boundary checks the procedural top answers to.
	parts.append(TileMeshPart.make(mesh, slot_order, "surface"))
	return parts


func get_bounds(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> AABB:
	var source := _source(layer, ctx)
	if source == null:
		return super(layer, ctx)
	var placement := _placement(layer, ctx, source)
	var box: AABB = placement["aabb"]
	return box


func get_debug_info(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> Dictionary:
	var info := {
		"generator": generator_id(),
		"mesh_path": layer.get_string("mesh_path", ""),
	}
	var source := _source(layer, ctx)
	if source == null:
		info["loaded"] = false
		return info

	var placement := _placement(layer, ctx, source)
	var box: AABB = placement["aabb"]
	var overrides := _overrides(layer)
	var fallback := _fallback_slot(layer)
	var mapping: Dictionary = {}
	for surface in source.get_surface_count():
		mapping[_source_key(source, surface)] = _slot_for(source, surface, overrides, fallback)

	info["loaded"] = true
	info["surfaces"] = source.get_surface_count()
	info["triangles"] = _triangle_count(source)
	info["applied_scale"] = placement["scale"]
	info["fit_factor"] = placement["fit"]
	info["footprint_m"] = Vector2(box.size.x, box.size.z)
	info["bounds_min"] = box.position
	info["bounds_max"] = box.end
	info["slots"] = mapping
	return info


# --- placement ----------------------------------------------------------------

## Everything the transform params add up to: the baked Transform3D, the extra
## uniform factor `fit_to_tile` contributed, and the AABB the mesh will really
## occupy once it is in the tile.
static func _placement(
	layer: TileSurfaceLayer,
	ctx: TileGenerationContext,
	source: ArrayMesh
) -> Dictionary:
	var user_scale: float = maxf(0.00001, layer.get_float("scale", 1.0))
	var yaw := deg_to_rad(layer.get_float("yaw_deg", 0.0))
	var source_box := source.get_aabb()
	var oriented := _transformed_aabb(
		source_box,
		Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * user_scale), Vector3.ZERO)
	)

	var fit := 1.0
	var centring := Vector3.ZERO
	if layer.get_bool("fit_to_tile", false):
		# Fit on the LONGER of the two footprint axes and apply that one factor
		# to all three, so the model keeps its proportions. Scaling Y to match
		# would squash a hero silhouette, which is the whole thing being bought.
		var span: float = maxf(oriented.size.x, oriented.size.z)
		if span > 0.00001:
			fit = (ctx.half_extent * 2.0) / span
		# "Fits the footprint" is only true if the mesh is centred on it. Y is
		# left alone: a tile's height above the walk plane is authored, not
		# derived from its bounding box.
		var centre := oriented.get_center() * fit
		centring = Vector3(-centre.x, 0.0, -centre.z)

	var transform := Transform3D(
		Basis(Vector3.UP, yaw).scaled(Vector3.ONE * (user_scale * fit)),
		centring + Vector3(
			layer.get_float("offset_x", 0.0),
			layer.get_float("offset_y", 0.0),
			layer.get_float("offset_z", 0.0)
		)
	)
	return {
		"transform": transform,
		"fit": fit,
		"scale": user_scale * fit,
		"oriented": oriented,
		"aabb": _transformed_aabb(source_box, transform),
	}


## Explicit eight-corner transform. A yawed box cannot be re-bounded by moving
## its two extremes, and a hero mesh is routinely placed at an angle.
static func _transformed_aabb(box: AABB, transform: Transform3D) -> AABB:
	var result := AABB(transform * box.get_endpoint(0), Vector3.ZERO)
	for index in range(1, 8):
		result = result.expand(transform * box.get_endpoint(index))
	return result


## Reports the measured overflow in metres, plus the scale that would have fit,
## so the artist knows exactly how much to trim instead of guessing.
static func _check_footprint(
	layer: TileSurfaceLayer,
	ctx: TileGenerationContext,
	source: ArrayMesh,
	scale: float,
	problems: PackedStringArray
) -> void:
	var extent := ctx.half_extent
	var placement := _placement(layer, ctx, source)
	var box: AABB = placement["aabb"]
	var over_x: float = maxf(0.0, maxf(-extent - box.position.x, box.end.x - extent))
	var over_z: float = maxf(0.0, maxf(-extent - box.position.z, box.end.z - extent))
	if over_x <= FOOTPRINT_EPSILON and over_z <= FOOTPRINT_EPSILON:
		return

	if layer.get_bool("fit_to_tile", false):
		# The fit itself cannot overflow, so the offsets are the only culprit.
		problems.append(
			"offset_x/offset_z push the fitted mesh %.4f m past the footprint on X and %.4f m on Z; a fitted mesh is already centred, so the XZ offsets must stay at zero"
			% [over_x, over_z]
		)
		return

	var oriented: AABB = placement["oriented"]
	var reach: float = maxf(
		maxf(absf(oriented.position.x), absf(oriented.end.x)),
		maxf(absf(oriented.position.z), absf(oriented.end.z))
	)
	problems.append(
		"mesh overflows the tile footprint by %.4f m on X and %.4f m on Z (measured span %.3f x %.3f m, limit %.3f m); trim the model, drop scale to %.4f, or set fit_to_tile"
		% [
			over_x,
			over_z,
			box.size.x,
			box.size.z,
			extent * 2.0,
			scale * extent / maxf(0.0001, reach),
		]
	)


# --- slots --------------------------------------------------------------------

## slot_overrides wins, then a source name that is already a slot name, then the
## layer's own slot. The middle rule is what lets a GLB authored with Suma's
## slot names as its material names drop in with no override table at all.
static func _slot_for(
	source: ArrayMesh,
	surface: int,
	overrides: Dictionary,
	fallback: String
) -> String:
	var names := _source_names(source, surface)
	for key in names:
		if overrides.has(key):
			return String(overrides[key])
	for key in names:
		if TileForgeConstants.ALL_SLOTS.has(key):
			return key
	return fallback


## Both handles a surface answers to. `TileGenerationContext._flatten` already
## names a flattened surface after its material, so a GLB arrives with the
## artist's material name in reach either way.
static func _source_names(source: ArrayMesh, surface: int) -> PackedStringArray:
	var names := PackedStringArray()
	var surface_name := source.surface_get_name(surface)
	if surface_name != "":
		names.append(surface_name)
	var material := source.surface_get_material(surface)
	if material != null and material.resource_name != "":
		names.append(material.resource_name)
	return names


static func _source_key(source: ArrayMesh, surface: int) -> String:
	var names := _source_names(source, surface)
	return names[0] if names.size() > 0 else "surface_%d" % surface


static func _fallback_slot(layer: TileSurfaceLayer) -> String:
	if layer.material_slot != "":
		return layer.material_slot
	return TileForgeConstants.SLOT_TOP_PRIMARY


static func _overrides(layer: TileSurfaceLayer) -> Dictionary:
	var raw: Variant = layer.get_param("slot_overrides", {})
	if raw is Dictionary:
		return raw as Dictionary
	return {}


# --- helpers ------------------------------------------------------------------

static func _source(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> ArrayMesh:
	var path := layer.get_string("mesh_path", "")
	if path == "":
		return null
	var source := ctx.module_mesh(path)
	if source == null or source.get_surface_count() == 0:
		return null
	return source


static func _triangle_count(mesh: ArrayMesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var indices := mesh.surface_get_array_index_len(surface)
		total += (indices / 3) if indices > 0 else (mesh.surface_get_array_len(surface) / 3)
	return total


## Non-fatal notes. `validate` may only return blockers — the builder turns every
## returned string into a hard failure — so guidance goes through the context's
## message channel instead.
static func _advise(
	layer: TileSurfaceLayer,
	ctx: TileGenerationContext,
	source: ArrayMesh
) -> void:
	var triangles := _triangle_count(source)
	if triangles > TRIANGLE_ADVICE_LIMIT:
		ctx.report(
			"[%s] custom mesh carries %d triangles; a whole tile should land in the low hundreds"
			% [layer.layer_name, triangles]
		)
	if source.get_surface_count() > 4:
		ctx.report(
			"[%s] custom mesh has %d surfaces; the collection reads best at 2–4 material regions"
			% [layer.layer_name, source.get_surface_count()]
		)
