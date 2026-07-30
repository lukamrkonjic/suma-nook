extends Node
## Regression for live top/middle/bottom garment shaping.

const LAB := preload("res://characters/lab/clothing_lab.tscn")


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)


func _flatten_preview_vertices(lab: Node) -> PackedVector3Array:
	var result := PackedVector3Array()
	var surfaces: Array = lab.get("_raw_deformed_vertices")
	for surface in surfaces:
		result.append_array(surface as PackedVector3Array)
	return result


func _height_bounds(vertices: PackedVector3Array) -> Vector2:
	var minimum := INF
	var maximum := -INF
	for point in vertices:
		minimum = minf(minimum, point.y)
		maximum = maxf(maximum, point.y)
	return Vector2(minimum, maximum)


func _ready() -> void:
	var lab := LAB.instantiate()
	add_child(lab)
	for _frame in 8:
		await get_tree().process_frame

	var fit := lab.get("_fit") as ClothingFitSettings
	var controls: Dictionary = lab.get("_fit_controls")
	for property_name in [
		"top_section_scale",
		"middle_section_scale",
		"bottom_section_scale",
	]:
		if not controls.has(property_name):
			_fail("Missing live %s control." % property_name)
			return
	if fit == null:
		_fail("Clothing fit is unavailable.")
		return

	fit.top_section_scale = 1.0
	fit.middle_section_scale = 1.0
	fit.bottom_section_scale = 1.0
	lab.call("_preview_fit")
	var before := _flatten_preview_vertices(lab)
	var bounds := _height_bounds(before)
	if before.is_empty() or bounds.y - bounds.x <= 0.000001:
		_fail("Raw garment has no measurable height.")
		return

	var bottom_control := controls["bottom_section_scale"] as SpinBox
	bottom_control.value = 1.25
	for _frame in 2:
		await get_tree().process_frame
	var after := _flatten_preview_vertices(lab)
	if after.size() != before.size():
		_fail("Section shaping changed garment topology.")
		return

	var bottom_displacement := 0.0
	var top_displacement := 0.0
	for index in before.size():
		var normalized_height := (
			(before[index].y - bounds.x) / (bounds.y - bounds.x)
		)
		# The jacket's central vertices are torso, not sleeve, samples.
		if absf(before[index].x) > 0.09:
			continue
		var radial_displacement := Vector2(
			after[index].x - before[index].x,
			after[index].z - before[index].z,
		).length()
		if normalized_height <= 0.20:
			bottom_displacement = maxf(
				bottom_displacement,
				radial_displacement,
			)
		elif normalized_height >= 0.80:
			top_displacement = maxf(top_displacement, radial_displacement)
	if bottom_displacement <= 0.001:
		_fail("Bottom section scale did not reshape the garment.")
		return
	if top_displacement > 0.00001:
		_fail("Bottom section scale unexpectedly moved the top section.")
		return

	fit.top_section_scale = 0.85
	fit.middle_section_scale = 1.10
	fit.bottom_section_scale = 1.25
	var section_json := fit.to_json_data()
	if (
		not is_equal_approx(
			float(section_json.get("top_section_scale", 0.0)),
			0.85,
		)
		or not is_equal_approx(
			float(section_json.get("middle_section_scale", 0.0)),
			1.10,
		)
		or not is_equal_approx(
			float(section_json.get("bottom_section_scale", 0.0)),
			1.25,
		)
	):
		_fail("Section scales were not serialized into the fit.")
		return

	var midpoint := (bounds.x + bounds.y) * 0.5
	if (
		not is_equal_approx(
			float(lab.call(
				"_section_scale_at_height",
				bounds.x,
				bounds.x,
				bounds.y,
			)),
			1.25,
		)
		or not is_equal_approx(
			float(lab.call(
				"_section_scale_at_height",
				midpoint,
				bounds.x,
				bounds.y,
			)),
			1.10,
		)
		or not is_equal_approx(
			float(lab.call(
				"_section_scale_at_height",
				bounds.y,
				bounds.x,
				bounds.y,
			)),
			0.85,
		)
	):
		_fail("Section interpolation does not reach its authored anchors.")
		return

	fit.reset_fit()
	lab.call("_preview_fit")
	print("CLOTHING SECTION SCALE TEST PASSED")
	get_tree().quit(0)
