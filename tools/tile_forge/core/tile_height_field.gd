@tool
class_name TileHeightField
extends RefCounted
## The shared top surface every heightfield layer writes into, and every detail
## rule samples from.
##
## One field per tile means a detail can never float or sink: it asks the field
## for the height under its anchor and gets the exact value the triangulated
## mesh will have there. It also means edge locking is enforced in ONE place,
## so no generator can accidentally break the seam contract.
##
## Storage is a regular (res x res) grid over normalized tile space -1..1.
## Vertex (0,0) is the corner at (-1,-1); vertex (res-1, res-1) is (+1,+1).
## Boundary vertices therefore land EXACTLY on the tile boundary, which is what
## makes neighbouring copies meet without a hole.

var resolution := 7
var heights := PackedFloat32Array()
## Per-vertex material slot index into `slot_names`.
var slot_ids := PackedInt32Array()
var slot_names := PackedStringArray()
## Per-vertex "this vertex belongs to a hole" flag. Cells with any holed corner
## are skipped by triangulation, which is how a basin cavity is opened.
var holes := PackedByteArray()

var half_extent := TileForgeConstants.LIVE_HALF_EXTENT


func _init(field_resolution := 7, extent := TileForgeConstants.LIVE_HALF_EXTENT) -> void:
	resolution = maxi(2, field_resolution)
	half_extent = extent
	var count := resolution * resolution
	heights.resize(count)
	heights.fill(0.0)
	slot_ids.resize(count)
	slot_ids.fill(0)
	holes.resize(count)
	holes.fill(0)
	slot_names = PackedStringArray([TileForgeConstants.SLOT_TOP_PRIMARY])


func index_of(i: int, j: int) -> int:
	return j * resolution + i


## Normalized coordinate (-1..1) of grid column `i`.
func axis(i: int) -> float:
	return -1.0 + 2.0 * float(i) / float(resolution - 1)


## World X/Z of grid column `i`.
func world_axis(i: int) -> float:
	return axis(i) * half_extent


func slot_index(slot: String) -> int:
	if slot == "":
		return 0
	var found := slot_names.find(slot)
	if found >= 0:
		return found
	slot_names.append(slot)
	return slot_names.size() - 1


func set_slot(i: int, j: int, slot: String) -> void:
	slot_ids[index_of(i, j)] = slot_index(slot)


func slot_at(i: int, j: int) -> String:
	var id := slot_ids[index_of(i, j)]
	return slot_names[id] if id < slot_names.size() else slot_names[0]


func mark_hole(i: int, j: int) -> void:
	holes[index_of(i, j)] = 1


func is_hole(i: int, j: int) -> bool:
	return holes[index_of(i, j)] == 1


## Applies one heightfield layer: evaluates its primitives at every vertex,
## masks, blends, then re-locks the boundary. The lock runs LAST and
## unconditionally for a connected layer, so no blend operation can leave a
## boundary vertex off the shared height.
func apply_layer(layer: TileSurfaceLayer, extra: Callable = Callable()) -> void:
	var lock_height := layer.edge_lock_height
	var lock_width: float = maxf(0.001, layer.edge_lock_width)
	for j in resolution:
		for i in resolution:
			var u := axis(i)
			var v := axis(j)
			var contribution := layer.shape_height(u, v)
			if extra.is_valid():
				contribution += float(extra.call(u, v))
			var mask := layer.mask_weight(u, v)
			if layer.border_policy == TileForgeConstants.BorderPolicy.INSET:
				mask *= _inset_weight(u, v, layer.inset_margin)
			contribution *= mask
			var index := index_of(i, j)
			heights[index] = _blend(
				heights[index],
				contribution,
				layer.blend,
				layer.smooth_radius
			)

	if layer.border_policy == TileForgeConstants.BorderPolicy.EDGE_LOCK:
		lock_edges(lock_height, lock_width)


## Blends every boundary vertex back to `height` over a band `width` wide.
## Distance is measured with the Chebyshev metric, so the band is a square
## ring — corners converge at the same rate as edge midpoints and the four
## corner vertices land exactly on the shared height.
func lock_edges(height: float, width: float) -> void:
	for j in resolution:
		for i in resolution:
			var u := axis(i)
			var v := axis(j)
			var distance_in: float = 1.0 - maxf(absf(u), absf(v))
			if distance_in >= width:
				continue
			var t := smoothstep(0.0, 1.0, clampf(distance_in / width, 0.0, 1.0))
			var index := index_of(i, j)
			heights[index] = lerpf(height, heights[index], t)
			# Snap the outermost ring to remove float drift entirely: two
			# neighbouring tiles must agree bit-for-bit, not approximately.
			if distance_in <= 0.0:
				heights[index] = height


## Paints `slot` wherever the layer's own shape weight exceeds the threshold
## implied by `share`. Regions come out broad because the driver is the macro
## form, not a per-vertex random draw.
func paint_secondary_slot(layer: TileSurfaceLayer, slot: String, share: float) -> void:
	if slot == "" or share <= 0.0:
		return
	var threshold: float = clampf(1.0 - share, 0.0, 0.999)
	for j in resolution:
		for i in resolution:
			var u := axis(i)
			var v := axis(j)
			var strongest := 0.0
			for shape in layer.shapes:
				if shape != null:
					strongest = maxf(strongest, absf(shape.weight(u, v)))
			if strongest >= threshold:
				set_slot(i, j, slot)


## Bilinear height at a normalized coordinate. Detail placement uses this so a
## module sits on the interpolated surface, not on the nearest vertex.
func sample(u: float, v: float) -> float:
	var fu: float = clampf((u + 1.0) * 0.5, 0.0, 1.0) * float(resolution - 1)
	var fv: float = clampf((v + 1.0) * 0.5, 0.0, 1.0) * float(resolution - 1)
	var i0: int = clampi(int(floor(fu)), 0, resolution - 1)
	var j0: int = clampi(int(floor(fv)), 0, resolution - 1)
	var i1: int = mini(i0 + 1, resolution - 1)
	var j1: int = mini(j0 + 1, resolution - 1)
	var tu := fu - float(i0)
	var tv := fv - float(j0)
	var h00 := heights[index_of(i0, j0)]
	var h10 := heights[index_of(i1, j0)]
	var h01 := heights[index_of(i0, j1)]
	var h11 := heights[index_of(i1, j1)]
	return lerpf(lerpf(h00, h10, tu), lerpf(h01, h11, tu), tv)


## Surface normal at a normalized coordinate, in world space.
func normal_at(u: float, v: float) -> Vector3:
	var step: float = 2.0 / float(resolution - 1)
	var dx := sample(u + step, v) - sample(u - step, v)
	var dz := sample(u, v + step) - sample(u, v - step)
	var world_step := step * half_extent * 2.0
	return Vector3(-dx, world_step, -dz).normalized()


func min_height() -> float:
	var result := INF
	for h in heights:
		result = minf(result, h)
	return 0.0 if result == INF else result


func max_height() -> float:
	var result := -INF
	for h in heights:
		result = maxf(result, h)
	return 0.0 if result == -INF else result


## Median top height. Written into the tile definition's walk_surface_height so
## physics agrees with the visual surface instead of with its peak.
func median_height() -> float:
	var sorted := Array(heights)
	sorted.sort()
	if sorted.is_empty():
		return 0.0
	return float(sorted[sorted.size() / 2])


## Exact boundary heights, used by the validator to prove the seam contract.
func boundary_heights() -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for i in resolution:
		result.append(heights[index_of(i, 0)])
		result.append(heights[index_of(i, resolution - 1)])
	for j in range(1, resolution - 1):
		result.append(heights[index_of(0, j)])
		result.append(heights[index_of(resolution - 1, j)])
	return result


func _inset_weight(u: float, v: float, margin: float) -> float:
	var distance_in: float = 1.0 - maxf(absf(u), absf(v))
	return smoothstep(0.0, maxf(0.001, margin), distance_in)


func _blend(current: float, incoming: float, mode: int, radius: float) -> float:
	match mode:
		TileForgeConstants.Blend.ADD:
			return current + incoming
		TileForgeConstants.Blend.SUBTRACT:
			return current - incoming
		TileForgeConstants.Blend.MAX:
			return maxf(current, incoming)
		TileForgeConstants.Blend.MIN:
			return minf(current, incoming)
		TileForgeConstants.Blend.REPLACE:
			return incoming
		TileForgeConstants.Blend.SMOOTH_ADD:
			return _smooth_max(current, current + incoming, radius)
		TileForgeConstants.Blend.SMOOTH_SUBTRACT:
			return _smooth_min(current, current - incoming, radius)
	return current + incoming


## Polynomial smooth-max. Rounds the junction between two forms instead of
## leaving the crease a plain max() produces.
static func _smooth_max(a: float, b: float, radius: float) -> float:
	var k: float = maxf(0.0001, radius)
	var h: float = clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(a, b, h) + k * h * (1.0 - h)


static func _smooth_min(a: float, b: float, radius: float) -> float:
	var k: float = maxf(0.0001, radius)
	var h: float = clampf(0.5 - 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(a, b, h) - k * h * (1.0 - h)
