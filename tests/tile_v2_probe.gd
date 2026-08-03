extends SceneTree
## Numeric transect probe: prints field heights across the moss tile so
## flatness can be diagnosed as data, not argued from renders.


func _init() -> void:
	var recipe := TileV2Library.recipe("tile_v2_moss_cushion")
	var composed := TileV2Library.compose(recipe)
	var field: TileV2Field = composed["field"]
	print("ops:")
	for op in field.ops:
		print("  kind=%d merge=%d at=%s h=%s base=%s carry=%s" % [
			op["kind"], op["merge"], op["at"],
			op.get("height", "-"), op.get("base", "-"),
			op.get("edge_carry", 0.0)])
	print("diagonal transect (x = z), x from -0.85..0.85:")
	for step in 35:
		var t := -0.85 + 1.70 * float(step) / 34.0
		field.sample_into(t, t)
		print("  x=%.3f h=%.4f color=%s" % [t, field.out_height,
			field.out_color.to_html(false)])
	print("anti-diagonal transect (x = -z):")
	for step in 35:
		var t := -0.85 + 1.70 * float(step) / 34.0
		field.sample_into(t, -t)
		print("  x=%.3f h=%.4f color=%s" % [t, field.out_height,
			field.out_color.to_html(false)])
	quit(0)
