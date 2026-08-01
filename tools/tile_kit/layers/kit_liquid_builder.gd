class_name KitLiquidBuilder
extends RefCounted
## Reusable liquid surface with optional falling sheets on cardinal edges.
##
## GG's pond, solid-water, and waterfall tiles are compositions of the same
## small vocabulary: a level top plane, selected visible sides, and (for falls)
## a vertical sheet. Keeping that vocabulary in one capability lets any tile
## become water-like without a PondTile or WaterfallTile special case.

const EDGE_DIRECTIONS := [
	Vector2(0.0, -1.0), Vector2(1.0, 0.0),
	Vector2(0.0, 1.0), Vector2(-1.0, 0.0),
]


static func build(layer: TileKitLayer, _rng: RandomNumberGenerator,
		context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", KitBaseBuilder.HALF)
	var level: float = layer.value("level", 0.012)
	var inset: float = layer.value("inset", 0.018)
	var corner: float = layer.value("corner_radius", 0.06)
	var surface_key := String(layer.value("surface_key", "water_blue"))
	var batch := TileKitMeshUtils.MeshBatch.new()
	TileKitMeshUtils.add_rect_cap(
		batch, surface_key, half, corner, 6, inset, level, true
	)

	var fall_edges: Array = layer.value("fall_edges", [])
	var fall_depth: float = layer.value("fall_depth", 0.65)
	var fall_width: float = clampf(layer.value("fall_width", 0.72), 0.08, 1.0)
	for raw_edge: Variant in fall_edges:
		_add_fall_sheet(
			batch, surface_key, int(raw_edge), half - inset, level,
			fall_depth, fall_width
		)

	# Downstream lily pads and scatter now settle on the liquid plane. This is
	# deliberately a pipeline context effect rather than a LilyPadTile rule.
	context["surface_top"] = level
	context["cap_height"] = func(_local: Vector2) -> float: return 0.0
	context["liquid_level"] = level
	return {
		"meshes": [{"role": "surface", "name": "tile_liquid",
			"mesh": batch.commit(), "cast_shadow": false}],
	}


static func _add_fall_sheet(batch: TileKitMeshUtils.MeshBatch, key: String,
		edge_index: int, line: float, top: float, depth: float,
		width_fraction: float) -> void:
	var outward: Vector2 = EDGE_DIRECTIONS[posmod(edge_index, 4)]
	var along := Vector2(-outward.y, outward.x)
	var half_width := KitBaseBuilder.HALF * width_fraction
	var centre := outward * line
	var a2 := centre - along * half_width
	var b2 := centre + along * half_width
	var vertices := PackedVector3Array([
		Vector3(a2.x, top, a2.y), Vector3(b2.x, top, b2.y),
		Vector3(b2.x, top - depth, b2.y), Vector3(a2.x, top - depth, a2.y),
	])
	var normal := Vector3(outward.x, 0.0, outward.y)
	var normals := PackedVector3Array([normal, normal, normal, normal])
	# Double-sided: a falling sheet is deliberately thin and must remain legible
	# from both the platform and the void side.
	var indices := PackedInt32Array([
		0, 1, 2, 0, 2, 3,
		2, 1, 0, 3, 2, 0,
	])
	batch.add(key, vertices, normals, indices)
