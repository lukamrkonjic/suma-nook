class_name KitSpriteTuftsBuilder
extends RefCounted
## The audited-reference tuft carpet: crossed textured cards on an offset grid.
##
## This is the construction the reference ground tiles actually use — the
## clean-room GLB census shows a plain 24-vertex cube with tufts that exist
## only as tinted white gradient sprites, not as modelled leaves. Two quads
## cross at 90° per tuft; every vertex normal points STRAIGHT UP so a card
## takes exactly the flat top plane's lighting (uniform, never a dark back
## face), and the sprite's baked top-to-base gradient supplies all the form
## shading. The result reads as dozens of soft clay sprouts at a handful of
## triangles per tuft.
##
## The grid is deliberately regular: offset rows with small jitter, repeating
## identically across neighbouring tiles — a coherent carpet, not clutter.
## Outer-row cards may cross the rim slightly, which is what keeps the tile's
## silhouette organic at thumbnail size.


static func build(layer: TileKitLayer, rng: RandomNumberGenerator,
		context: Dictionary) -> Dictionary:
	var half: float = context.get("surface_half", KitBaseBuilder.HALF)
	var cap_height: Callable = context.get("cap_height", Callable())
	var sprite := String(layer.value("sprite", "tuft_sprout"))
	var tint_key := String(layer.value("tint_key", "grass_gg_tuft"))
	var spacing := maxf(0.12, float(layer.value("grid_spacing", 0.365)))
	var row_offset := float(layer.value("row_offset_fraction", 0.5))
	var card_size: Array = layer.value("card_size", [0.44, 0.50])
	var height_ratio := float(layer.value("height_ratio", 1.06))
	var jitter := float(layer.value("position_jitter", 0.045))
	var yaw_base: float = deg_to_rad(float(layer.value("yaw_degrees", 45.0)))
	var yaw_jitter: float = deg_to_rad(
		float(layer.value("yaw_jitter_degrees", 10.0)))
	var margin := float(layer.value("edge_margin", 0.055))
	var sink := float(layer.value("root_sink", 0.02))
	var skip := float(layer.value("skip_fraction", 0.0))
	var cards := clampi(int(layer.value("cards_per_tuft", 1)), 1, 2)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var limit := half - margin
	var rows := int(floor((limit * 2.0) / spacing)) + 1
	var start := -spacing * float(rows - 1) * 0.5
	var tufts := 0
	for row in rows:
		var z := start + spacing * float(row)
		var shift := spacing * row_offset * float(row % 2)
		# Column walk covers the shifted row fully, then clamps to the rim.
		var col := 0
		while true:
			var x := start + spacing * float(col) + shift
			if x > limit + 0.001:
				break
			col += 1
			# Every grid slot rolls the same RNG sequence regardless of skip,
			# so one parameter tweak never rearranges the whole carpet.
			var roll_skip := rng.randf()
			var size: float = rng.randf_range(
				float(card_size[0]), float(card_size[1]))
			var yaw := yaw_base + rng.randf_range(-yaw_jitter, yaw_jitter)
			var dx := rng.randf_range(-jitter, jitter)
			var dz := rng.randf_range(-jitter, jitter)
			var mirror := rng.randf() < 0.5
			if roll_skip < skip:
				continue
			var centre := Vector2(x + dx, z + dz)
			var ground := 0.0
			if cap_height.is_valid():
				ground = float(cap_height.call(centre))
			_add_tuft(vertices, normals, uvs, indices,
				Vector3(centre.x, ground - sink, centre.y),
				size, size * height_ratio, yaw, mirror, cards)
			tufts += 1

	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(
			0, TileKitPalette.sprite_material(sprite, tint_key))
	return {
		"meshes": [{
			"role": "detail",
			"name": "sprite_tufts",
			"mesh": mesh,
			"cast_shadow": false,
		}],
	}


## One tuft: `cards` vertical quads (a single camera-facing card by default —
## the audited reference renders tufts as static speed-zero billboard
## particles, so at Suma's fixed diagonal camera a face-on card at yaw 45°
## is the faithful equivalent; 2 gives a crossed pair for free-angle tiles).
## Every quad is emitted as a wound pair (front + back copy) so backface
## culling stays ON. That detail is load-bearing: with culling off, Godot
## flips the shading normal on back faces, which lit cards as if from below
## and split tufts into one bright and one murky rosette.
## UVs are full-rect (v = 0 at the sprite's tips); `mirror` flips U so the
## sprite's authored asymmetry alternates across the carpet.
static func _add_tuft(vertices: PackedVector3Array,
		normals: PackedVector3Array, uvs: PackedVector2Array,
		indices: PackedInt32Array, base: Vector3, width: float,
		height: float, yaw: float, mirror: bool, cards: int) -> void:
	for card in cards:
		var angle := yaw + PI * 0.5 * float(card)
		var along := Vector3(cos(angle), 0.0, sin(angle)) * width * 0.5
		var top := Vector3(0.0, height, 0.0)
		# The back copy sits a hair behind the front along the plane normal;
		# perfectly coplanar copies z-fight into thin bright streaks.
		var lift := Vector3(sin(angle), 0.0, -cos(angle)) * 0.0008
		var u0 := 1.0 if mirror != (card == 1) else 0.0
		var u1 := 1.0 - u0
		for side in 2:
			var offset := vertices.size()
			var push := Vector3.ZERO if side == 0 else lift
			vertices.append(base - along + push)
			vertices.append(base + along + push)
			vertices.append(base + along + top + push)
			vertices.append(base - along + top + push)
			for _corner in 4:
				normals.append(Vector3.UP)
			uvs.append(Vector2(u0, 1.0))
			uvs.append(Vector2(u1, 1.0))
			uvs.append(Vector2(u1, 0.0))
			uvs.append(Vector2(u0, 0.0))
			# Godot front faces wind CLOCKWISE; the second copy reverses the
			# winding so the pair is visible from both sides under CULL_BACK.
			if side == 0:
				indices.append(offset)
				indices.append(offset + 2)
				indices.append(offset + 1)
				indices.append(offset)
				indices.append(offset + 3)
				indices.append(offset + 2)
			else:
				indices.append(offset)
				indices.append(offset + 1)
				indices.append(offset + 2)
				indices.append(offset)
				indices.append(offset + 2)
				indices.append(offset + 3)
