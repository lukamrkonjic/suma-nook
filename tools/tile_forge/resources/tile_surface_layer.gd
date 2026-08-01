@tool
class_name TileSurfaceLayer
extends Resource
## One ordered contribution to a tile's top assembly.
##
## A layer does not know how it will be turned into geometry. It names a
## generator id; TileGeneratorRegistry resolves that to an implementation. This
## is the seam that lets a programmer add a genuinely new geometry family
## without touching TileRecipe, TileBaker, or any existing generator.

## Registry id, e.g. "flat_surface", "heightfield_surface", "board_pattern".
@export var generator_id := "heightfield_surface"
@export var layer_name := "surface"
@export var enabled := true

@export_group("Material")
## Slot this layer paints. The palette binds it to a semantic key.
@export var material_slot := TileForgeConstants.SLOT_TOP_PRIMARY
## Optional second slot for generators that produce two broad colour regions
## (crests versus hollows, alternate boards, alternate pavers).
@export var secondary_slot := ""
## Fraction of the layer's area that gets `secondary_slot`. Keep the split
## broad — many small patches is exactly the high-frequency colour variation
## the art direction bans.
@export_range(0.0, 1.0, 0.01) var secondary_share := 0.35

@export_group("Height")
@export var blend: TileForgeConstants.Blend = TileForgeConstants.Blend.ADD
## Multiplies every shape primitive's amplitude. Lets one shape set be reused
## at two intensities.
@export_range(-3.0, 3.0, 0.01) var height_scale := 1.0
## Width of the smooth-blend transition band, metres. Only used by SMOOTH_ADD
## and SMOOTH_SUBTRACT.
@export_range(0.001, 0.2, 0.001) var smooth_radius := 0.03
## Constant offset applied across the whole layer before the shapes, metres.
@export var height_bias := 0.0

@export_group("Shape")
## The macro forms. Two to four broad primitives is the normal, healthy count.
@export var shapes: Array[TileShapePrimitive] = []
## Optional mask: where these evaluate above `mask_threshold`, the layer acts;
## elsewhere it is faded out. Empty means "act everywhere".
@export var mask_shapes: Array[TileShapePrimitive] = []
@export_range(0.0, 1.0, 0.01) var mask_threshold := 0.0
@export var mask_invert := false

@export_group("Boundary")
@export var border_policy: TileForgeConstants.BorderPolicy = TileForgeConstants.BorderPolicy.EDGE_LOCK
## Width of the band, in normalized units, over which organic height returns to
## the connected boundary height. Too wide flattens the tile; too narrow puts a
## visible crease at the seam. 0.18–0.3 is the useful range.
@export_range(0.02, 0.6, 0.01) var edge_lock_width := 0.24
## Height the boundary is locked TO, metres. Must match every tile this one
## connects to — normally 0.0, the walk plane.
@export var edge_lock_height := 0.0
## For BorderPolicy.INSET: how far inside the boundary the layer stops.
@export_range(0.0, 0.6, 0.01) var inset_margin := 0.18

@export_group("Mesh")
## Heightfield resolution (vertices per side). Use the SMALLEST value that
## preserves the intended silhouette. 5 and 7 cover almost everything; 13 is
## reserved for a genuinely complex sculpted top.
@export_range(2, 25, 1) var resolution := 7
## Emit the layer on its own node so a caller can isolate, hide, or cull it.
@export var separate_render_layer := false
## Smooth-shade the layer's normals. Off gives the crisp faceted read used by
## constructed surfaces.
@export var smooth_shading := true

@export_group("Generator")
## Free-form parameters consumed by the named generator. Documented per
## generator in README_TILE_FORGE.md. Keeping them here is what lets a new
## generator ship without a new Resource class.
@export var params: Dictionary = {}


func get_param(key: String, fallback: Variant) -> Variant:
	return params.get(key, fallback)


func get_float(key: String, fallback: float) -> float:
	var value: Variant = params.get(key, fallback)
	return float(value) if value is float or value is int else fallback


func get_int(key: String, fallback: int) -> int:
	var value: Variant = params.get(key, fallback)
	return int(value) if value is float or value is int else fallback


func get_bool(key: String, fallback: bool) -> bool:
	var value: Variant = params.get(key, fallback)
	return bool(value) if value is bool else fallback


func get_string(key: String, fallback: String) -> String:
	var value: Variant = params.get(key, fallback)
	return String(value) if value is String else fallback


## Combined mask weight at a normalized coordinate, already thresholded and
## inverted. 1.0 when the layer has no mask.
func mask_weight(u: float, v: float) -> float:
	if mask_shapes.is_empty():
		return 1.0
	var strongest := 0.0
	for shape in mask_shapes:
		if shape != null:
			strongest = maxf(strongest, absf(shape.weight(u, v)))
	var value: float = clampf(
		inverse_lerp(mask_threshold, 1.0, strongest) if mask_threshold < 1.0 else strongest,
		0.0,
		1.0
	)
	return 1.0 - value if mask_invert else value


## Raw height contribution of this layer's primitives, before edge locking.
func shape_height(u: float, v: float) -> float:
	var total := height_bias
	for shape in shapes:
		if shape != null:
			total += shape.evaluate(u, v)
	return total * height_scale
