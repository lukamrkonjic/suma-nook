extends SceneTree
## Focused contract test for source-inspired procedural sand/snow dunes.

const HALF := KitBaseBuilder.HALF

var _failures: Array[String] = []
var _checks := 0


func _init() -> void:
	_run()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _dune_relief(preset: TileKitPreset) -> Callable:
	var rng := RandomNumberGenerator.new()
	rng.seed = TileKitGenerator.layer_stream(
		preset.master_seed,
		preset.layer_of_kind("base")
	)
	return KitBaseBuilder._relief_function(
		preset.layer_of_kind("base"), rng, 0.075, false
	)


func _sample_range(relief: Callable) -> Vector2:
	var low := INF
	var high := -INF
	for z in 25:
		for x in 25:
			var point := Vector2(
				lerpf(-HALF, HALF, float(x) / 24.0),
				lerpf(-HALF, HALF, float(z) / 24.0)
			)
			var height := float(relief.call(point))
			low = minf(low, height)
			high = maxf(high, height)
	return Vector2(low, high)


func _run() -> void:
	var original_sand := TileKitPreset.sandy_ground()
	var original_snow := TileKitPreset.snow_field()
	var sand := TileKitPreset.sand_dune_study()
	var snow := TileKitPreset.snow_drift_study()
	_check(
		String(original_sand.layer_of_kind("base").value("relief_style", "none")) == "dunes",
		"the original Sandy Ground preset remains unchanged"
	)
	_check(
		String(original_snow.layer_of_kind("base").value("relief_style", "none")) == "dunes",
		"the original Snow Field preset remains unchanged"
	)
	_check(
		String(sand.layer_of_kind("base").value("relief_style", "none")) == "sculpted_dunes",
		"the sand duplicate opts into sculpted dunes"
	)
	_check(
		String(snow.layer_of_kind("base").value("relief_style", "none")) == "sculpted_dunes",
		"the snow duplicate opts into sculpted dunes"
	)
	_check(
		is_equal_approx(float(sand.layer_of_kind("base").value("relief_amplitude", 0.0)), 0.060),
		"sand study inherits the shipped six-centimetre relief range"
	)
	_check(
		is_equal_approx(float(snow.layer_of_kind("base").value("relief_amplitude", 0.0)), 0.105),
		"snow study inherits the shipped 10.5-centimetre relief range"
	)

	var relief := _dune_relief(sand)
	for index in 17:
		var coordinate := lerpf(-HALF, HALF, float(index) / 16.0)
		_check(
			is_equal_approx(
				float(relief.call(Vector2(-HALF, coordinate))),
				float(relief.call(Vector2(HALF, coordinate)))
			),
			"east/west periodic seam agrees at sample %d" % index
		)
		_check(
			is_equal_approx(
				float(relief.call(Vector2(coordinate, -HALF))),
				float(relief.call(Vector2(coordinate, HALF)))
			),
			"north/south periodic seam agrees at sample %d" % index
		)

	var shallow := sand.duplicate_preset()
	shallow.layer_of_kind("base").params["relief_amplitude"] = 0.005
	var dramatic := sand.duplicate_preset()
	dramatic.layer_of_kind("base").params["relief_amplitude"] = 0.180
	var shallow_range := _sample_range(_dune_relief(shallow))
	var dramatic_range := _sample_range(_dune_relief(dramatic))
	_check(
		shallow_range.y <= 0.0051,
		"minimum strength stays shallow (%.4f m)" % shallow_range.y
	)
	_check(
		dramatic_range.y > shallow_range.y * 25.0,
		"maximum strength is visibly dramatic (%.4f m vs %.4f m)" % [
			dramatic_range.y, shallow_range.y
		]
	)

	var changed_pattern := sand.duplicate_preset()
	changed_pattern.layer_of_kind("base").params["dune_seed_offset"] = 1
	var changed_relief := _dune_relief(changed_pattern)
	var difference := 0.0
	for index in 12:
		var point := Vector2(
			lerpf(-0.72, 0.72, float(index) / 11.0),
			lerpf(0.68, -0.68, float(index) / 11.0)
		)
		difference += absf(float(relief.call(point)) - float(changed_relief.call(point)))
	_check(difference > 0.01, "dune seed offset produces a new sculpt")

	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var panel := TileKitPanel.new()
	panel.setup(UiKit.new(palette))
	get_root().add_child(panel)
	panel.preset = sand
	panel.call("_sync_bound_controls")
	panel.call("_sync_dune_controls")
	var strength_slider := panel.find_child(
		"TileKitSlider_base_relief_amplitude", true, false
	) as HSlider
	var strength_row := panel.find_child(
		"TileKitSliderRow_base_relief_amplitude", true, false
	) as HBoxContainer
	var randomize_button := panel.find_child(
		"TileKitRandomizeDunes", true, false
	) as Button
	_check(
		strength_slider != null and strength_row != null and strength_row.visible,
		"tile editor exposes dune strength for study presets"
	)
	_check(
		randomize_button != null and randomize_button.visible,
		"tile editor exposes Randomize Dunes for study presets"
	)
	var previous_pattern := int(sand.layer_of_kind("base").value("dune_seed_offset", 0))
	panel.call("_randomize_dunes")
	_check(
		int(sand.layer_of_kind("base").value("dune_seed_offset", 0)) == previous_pattern + 1,
		"Randomize Dunes advances the deterministic pattern"
	)
	_check(
		float(sand.layer_of_kind("base").value("dune_amount", 0.0)) >= 0.20
			and float(sand.layer_of_kind("base").value("dune_amount", 0.0)) <= 0.92,
		"Randomize Dunes also varies the amount within its authored range"
	)
	panel.preset = TileKitPreset.reference_clean_grass()
	panel.call("_sync_dune_controls")
	var clean_strength_row := panel.find_child(
		"TileKitSliderRow_base_relief_amplitude", true, false
	) as HBoxContainer
	_check(
		clean_strength_row == null or not clean_strength_row.is_visible_in_tree(),
		"dune controls stay hidden for non-dune tiles"
	)
	panel.free()

	if _failures.is_empty():
		print("TILE KIT DUNE TEST PASSED — %d checks" % _checks)
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: %s" % failure)
	printerr("TILE KIT DUNE TEST FAILED — %d/%d" % [
		_failures.size(),
		_checks,
	])
	quit(1)
