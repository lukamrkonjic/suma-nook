@tool
class_name ModuleLayoutGenerator
extends TileLayerGenerator
## Builds a constructed surface from CURATED MESHES placed at AUTHORED
## POSITIONS.
##
## This is the generator the hybrid pipeline rests on. Pavers and boards are not
## invented in code from primitives — they are modelled in Blender at their
## exact placed size, with real chamfers and correct normals, and this generator
## only decides which piece goes where. A paver therefore looks like a paver
## rather than like an extruded rectangle, and the seams are exact because the
## layout arithmetic and the module dimensions were authored together.
##
## Layouts are explicit tables, readable and reviewable by an artist. There is
## no scatter here and no procedural subdivision: a designer picks a template
## name and a seam width, and gets a surface that repeats cleanly.
##
## ## Params:
##   layout        (String) template name — see LAYOUTS below.
##   seam          (float)  gap between pieces, metres. The layouts were
##                          authored against 0.030; changing it shifts pieces
##                          symmetrically and keeps the outer edge exact.
##   lift          (float)  height of the piece tops above the tile plane.
##   height_variation (float) per-piece vertical wobble, metres. Tiny by design.
##   colour_variation (float) fraction of WHOLE pieces taking secondary_slot.
##   yaw_variation (float)  per-piece yaw wobble in degrees. Keep under ~1.5:
##                          constructed pieces are laid, not dropped.
##   module_dir    (String) folder the pieces are loaded from.

const PAVER_DIR := "res://tools/tile_forge/modules/pavers"
const BOARD_DIR := "res://tools/tile_forge/modules/boards"

## Each entry is [module id, centre x, centre z, yaw quarter-turns].
## Positions are in LIVE metres relative to the tile centre and were computed
## from the module sizes the Blender library exports, so the outer edges land on
## the tile boundary exactly.
const LAYOUTS := {
	# Four broad slabs. (1.35 - 0.03) / 2 = 0.66 per piece; centres at ±0.345.
	"paver_quad": {
		"dir": PAVER_DIR,
		"pieces": [
			["gf_paver_large", -0.345, -0.345, 0],
			["gf_paver_large_alt", 0.345, -0.345, 1],
			["gf_paver_large_alt", -0.345, 0.345, 3],
			["gf_paver_large", 0.345, 0.345, 2],
		],
	},
	# Nine mid slabs. (1.35 - 0.06) / 3 = 0.43; centres at 0 and ±0.46.
	"paver_grid": {
		"dir": PAVER_DIR,
		"pieces": [
			["gf_paver_mid", -0.46, -0.46, 0], ["gf_paver_mid_alt", 0.0, -0.46, 1],
			["gf_paver_mid", 0.46, -0.46, 2],
			["gf_paver_mid_alt", -0.46, 0.0, 3], ["gf_paver_mid", 0.0, 0.0, 0],
			["gf_paver_mid_alt", 0.46, 0.0, 1],
			["gf_paver_mid", -0.46, 0.46, 2], ["gf_paver_mid_alt", 0.0, 0.46, 3],
			["gf_paver_mid", 0.46, 0.46, 0],
		],
	},
	# One hero slab, a wide filler, and two mid pieces: the composition the art
	# direction asks for, applied to a constructed surface.
	"paver_mixed": {
		"dir": PAVER_DIR,
		"pieces": [
			["gf_paver_large", -0.345, -0.345, 0],
			["gf_paver_tall", 0.46, 0.0, 0],
			["gf_paver_mid", -0.46, 0.46, 1],
			["gf_paver_mid_alt", 0.0, 0.46, 2],
			["gf_paver_mid", 0.0, -0.46, 3],
		],
	},
	# Three broad boards. (1.35 - 0.052) / 3 = 0.4326; centres at 0 and ±0.4589.
	"board_three": {
		"dir": BOARD_DIR,
		"pieces": [
			["gf_board_a", 0.0, -0.4589, 0],
			["gf_board_b", 0.0, 0.0, 0],
			["gf_board_c", 0.0, 0.4589, 0],
		],
	},
	# Four narrower boards. (1.35 - 0.078) / 4 = 0.318; centres at ±0.174, ±0.522.
	"board_four": {
		"dir": BOARD_DIR,
		"pieces": [
			["gf_board_narrow_a", 0.0, -0.522, 0],
			["gf_board_narrow_b", 0.0, -0.174, 0],
			["gf_board_narrow_a", 0.0, 0.174, 0],
			["gf_board_narrow_b", 0.0, 0.522, 0],
		],
	},
	# Three boards with the middle run split, so a repeat shows a staggered
	# joint instead of one unbroken line across every tile.
	"board_staggered": {
		"dir": BOARD_DIR,
		"pieces": [
			["gf_board_a", 0.0, -0.4589, 0],
			["gf_board_half", -0.339, 0.0, 0],
			["gf_board_half", 0.339, 0.0, 0],
			["gf_board_c", 0.0, 0.4589, 0],
		],
	},
}


func generator_id() -> String:
	return "module_layout"


func kinds() -> Array:
	return [TileForgeConstants.Kind.MESH]


func description() -> String:
	return "Constructed surface assembled from curated Blender modules at authored positions."


func validate(layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> PackedStringArray:
	var problems := PackedStringArray()
	var name := layer.get_string("layout", "paver_quad")
	if not LAYOUTS.has(name):
		problems.append(
			"unknown layout '%s'; available: %s" % [name, ", ".join(LAYOUTS.keys())]
		)
		return problems
	var table: Dictionary = LAYOUTS[name]
	var directory := layer.get_string("module_dir", String(table["dir"]))
	for piece in table["pieces"]:
		var path := "%s/%s.glb" % [directory, String(piece[0])]
		if not ResourceLoader.exists(path):
			problems.append("missing module '%s' — rebuild the Blender library" % path)
	if layer.get_float("seam", 0.03) < 0.0:
		problems.append("seam cannot be negative")
	return problems


func generate_mesh(layer: TileSurfaceLayer, ctx: TileGenerationContext) -> Array[TileMeshPart]:
	var parts: Array[TileMeshPart] = []
	var name := layer.get_string("layout", "paver_quad")
	if not LAYOUTS.has(name):
		return parts
	var table: Dictionary = LAYOUTS[name]
	var directory := layer.get_string("module_dir", String(table["dir"]))
	var pieces: Array = table["pieces"]

	var seam := layer.get_float("seam", 0.030)
	var lift := layer.get_float("lift", 0.0)
	var wobble := layer.get_float("height_variation", 0.003)
	var yaw_wobble := layer.get_float("yaw_variation", 0.8)
	var colour_share: float = clampf(layer.get_float("colour_variation", 0.35), 0.0, 1.0)
	# Layout positions were authored against a 0.030 seam. A different seam moves
	# every piece proportionally towards or away from the centre, which keeps the
	# outer edges of the field on the tile boundary.
	var seam_scale: float = 1.0 + (seam - 0.030) * 0.5 / maxf(0.001, ctx.half_extent)

	var rng := ctx.rng("module_layout|" + layer.layer_name)
	var tools: Dictionary = {}
	var slot_order := PackedStringArray()

	for index in pieces.size():
		var piece: Array = pieces[index]
		var mesh := ctx.module_mesh("%s/%s.glb" % [directory, String(piece[0])])
		if mesh == null:
			continue
		var slot := layer.material_slot
		if layer.secondary_slot != "" and rng.randf() < colour_share:
			slot = layer.secondary_slot
		if not tools.has(slot):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[slot] = tool
			slot_order.append(slot)

		var basis := Basis(Vector3.UP, float(int(piece[3])) * PI * 0.5)
		if yaw_wobble > 0.01:
			basis = Basis(Vector3.UP, deg_to_rad(rng.randf_range(-yaw_wobble, yaw_wobble))) * basis
		var transform := Transform3D(
			basis,
			Vector3(
				float(piece[1]) * seam_scale,
				lift + rng.randf_range(-wobble, wobble),
				float(piece[2]) * seam_scale
			)
		)
		(tools[slot] as SurfaceTool).append_from(mesh, 0, transform)
		for surface in range(1, mesh.get_surface_count()):
			# A module's own second tone (its chamfer band or shaded side) is
			# pinned by name; only its primary follows the layout's colour roll.
			var surface_name := mesh.surface_get_name(surface)
			var target := slot
			if TileForgeConstants.ALL_SLOTS.has(surface_name):
				target = surface_name
			if not tools.has(target):
				var extra := SurfaceTool.new()
				extra.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[target] = extra
				slot_order.append(target)
			(tools[target] as SurfaceTool).append_from(mesh, surface, transform)

	if slot_order.is_empty():
		return parts
	var combined := ArrayMesh.new()
	for slot in slot_order:
		var tool: SurfaceTool = tools[slot]
		tool.commit(combined)
		combined.surface_set_name(combined.get_surface_count() - 1, slot)
	var part := TileMeshPart.make(combined, slot_order, "surface")
	part.smooth_shading = false
	part.layer_name = layer.layer_name
	parts.append(part)
	return parts


func generate_collision(_layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> Array:
	# A constructed deck is walked on its top plane; the recipe's flat box covers
	# it, and per-piece collision would be far heavier than the render mesh.
	return []


func get_bounds(_layer: TileSurfaceLayer, ctx: TileGenerationContext) -> AABB:
	var extent := ctx.half_extent
	return AABB(Vector3(-extent, -0.2, -extent), Vector3(extent * 2.0, 0.4, extent * 2.0))


func get_debug_info(layer: TileSurfaceLayer, _ctx: TileGenerationContext) -> Dictionary:
	var name := layer.get_string("layout", "paver_quad")
	var count := 0
	if LAYOUTS.has(name):
		count = (LAYOUTS[name]["pieces"] as Array).size()
	return {"generator": generator_id(), "layout": name, "pieces": count}
