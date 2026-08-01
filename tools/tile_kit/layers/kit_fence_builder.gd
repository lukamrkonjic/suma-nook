class_name KitFenceBuilder
extends RefCounted
## Perimeter fence — the first brick for the tile schema's EDGE role.
##
## Small wooden posts with a low rail running between them, set just inside
## the footprint along the chosen edges. In the reference game these rail
## fences are what turn a meadow into a paddock or a yard: the tile's
## silhouette changes, not just its surface. Edge-role geometry persists or
## hides by the tile definition's own rule, so a fenced tile can keep its
## border even while a covering tile hides the grass.
##
## `edges` picks sides by compass index (0 = -Z, 1 = +X, 2 = +Z, 3 = -X), so
## presets can fence a single side for path borders once tile connection data
## feeds in; the built-in preset fences all four.

const EDGE_DIRECTIONS := [
	Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0),
]


static func build(layer: TileKitLayer, rng: RandomNumberGenerator,
		context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", 0.85)
	var cap_height: Callable = context.get("cap_height", Callable())
	var edges: Array = layer.value("edges", [0, 1, 2, 3])
	var inset: float = layer.value("inset", 0.055)
	var post_size: float = layer.value("post_size", 0.07)
	var post_height: float = layer.value("post_height", 0.19)
	var rail_height: float = layer.value("rail_height", 0.12)
	var rail_thickness: float = layer.value("rail_thickness", 0.034)
	var spacing: float = layer.value("post_spacing", 0.44)
	var post_key := String(layer.value("post_key", "wood_deep"))
	var rail_key := String(layer.value("rail_key", "wood_medium"))
	var batch := TileKitMeshUtils.MeshBatch.new()

	for edge_index: int in edges:
		var outward: Vector2 = EDGE_DIRECTIONS[edge_index % 4]
		var along := Vector2(-outward.y, outward.x)
		var line := half - inset
		var run := (half - inset) * 2.0
		var posts := maxi(2, int(round(run / spacing)) + 1)
		var previous := Vector2.INF
		for post_index in posts:
			var t := float(post_index) / float(posts - 1)
			var position := outward * line + along * (run * (t - 0.5))
			var ground := 0.0
			if cap_height.is_valid():
				ground = float(cap_height.call(position))
			# Posts wobble a hair in lean-in and height — hand-driven, not
			# machined — while staying on the fence line.
			var height := post_height * rng.randf_range(0.94, 1.06)
			TileKitMeshUtils.add_slab(batch, post_key,
				Vector3(position.x, ground - 0.01, position.y),
				post_size * 0.5, post_size * 0.5, post_size * 0.22,
				height + 0.01, rng.randf_range(-0.06, 0.06), 0.014)
			if previous != Vector2.INF:
				var centre := (previous + position) * 0.5
				var rail_ground := 0.0
				if cap_height.is_valid():
					rail_ground = float(cap_height.call(centre))
				var length := previous.distance_to(position)
				var yaw := atan2(position.y - previous.y,
					position.x - previous.x)
				TileKitMeshUtils.add_slab(batch, rail_key,
					Vector3(centre.x, rail_ground + rail_height, centre.y),
					length * 0.5 - post_size * 0.28, rail_thickness * 0.5,
					rail_thickness * 0.3, rail_thickness, yaw, 0.008)
			previous = position

	return {
		"meshes": [{"role": "edge", "name": "tile_fence",
			"mesh": batch.commit()}],
	}
