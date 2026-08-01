class_name KitFringeBuilder
extends RefCounted
## Connection-aware segmented rim for soil beds, ponds, banks, and borders.
##
## A fringe is topology, not a named tile: selected edges receive a broken
## course of soft pieces, and connected edges may suppress it automatically.
## That is the reusable rule behind GG's soil-bed and pond corner variants.

const EDGE_DIRECTIONS := [
	Vector2(0.0, -1.0), Vector2(1.0, 0.0),
	Vector2(0.0, 1.0), Vector2(-1.0, 0.0),
]


static func build(layer: TileKitLayer, rng: RandomNumberGenerator,
		context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", KitBaseBuilder.HALF)
	var cap_height: Callable = context.get("cap_height", Callable())
	var mask := int(context.get("neighbour_mask", 0))
	var edges: Array = layer.value("edges", [0, 1, 2, 3])
	var exposed_only: bool = layer.value("exposed_only", true)
	var inset: float = layer.value("inset", 0.045)
	var width: float = layer.value("width", 0.085)
	var height: float = layer.value("height", 0.045)
	var pieces: int = layer.value("pieces_per_edge", 7)
	var gap: float = layer.value("gap", 0.018)
	var jitter: float = layer.value("jitter", 0.16)
	var key := String(layer.value("material_key", "earth_clump"))
	var batch := TileKitMeshUtils.MeshBatch.new()
	for raw_edge: Variant in edges:
		var edge_index := posmod(int(raw_edge), 4)
		if exposed_only and (mask & (1 << edge_index)) != 0:
			continue
		var outward: Vector2 = EDGE_DIRECTIONS[edge_index]
		var along := Vector2(-outward.y, outward.x)
		var line := half - inset
		var run := (half - inset) * 2.0
		var segment_length := run / float(maxi(pieces, 1))
		for piece_index in maxi(pieces, 1):
			var offset := -run * 0.5 + (float(piece_index) + 0.5) * segment_length
			offset += rng.randf_range(-jitter, jitter) * segment_length
			var centre2 := outward * line + along * offset
			var ground := float(cap_height.call(centre2)) if cap_height.is_valid() else 0.0
			var yaw := atan2(along.y, along.x) + rng.randf_range(-0.05, 0.05)
			TileKitMeshUtils.add_slab(
				batch, key, Vector3(centre2.x, ground - height * 0.35, centre2.y),
				maxf(0.01, (segment_length - gap) * 0.5), width * 0.5,
				minf(width * 0.35, 0.035), height * rng.randf_range(0.84, 1.12),
				yaw, minf(0.012, height * 0.25)
			)
	return {
		"meshes": [{"role": "edge", "name": "tile_fringe", "mesh": batch.commit()}],
	}
