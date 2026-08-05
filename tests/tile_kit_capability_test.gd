extends SceneTree
## Focused contracts for the schema-driven capability editor and GG-derived
## liquid/fringe composition systems. No file publishing occurs in this test.

var _failures: Array[String] = []
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _run() -> void:
	_check_schema()
	_check_panel()
	_check_template("liquid_surface", "liquid")
	_check_template("fringed_ground", "fringe")
	if _failures.is_empty():
		print("TILE KIT CAPABILITY TEST PASSED — %d checks" % _checks)
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: %s" % failure)
	printerr("TILE KIT CAPABILITY TEST FAILED — %d/%d" % [
		_failures.size(), _checks,
	])
	quit(1)


func _check_schema() -> void:
	_check(TileLayerParameterSchema.KIND_ORDER.size() == 12,
		"all twelve reusable capability families are registered")
	var scatter := TileLayerParameterSchema.new_layer("clutter")
	scatter.params["shapes"] = ["leaf_litter", "twig"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 260801
	TileLayerParameterSchema.randomize_parameters(scatter, rng)
	_check(scatter.params["shapes"] == ["leaf_litter", "twig"],
		"numeric variation preserves selected scatter content")
	var count: Array = scatter.params["count"]
	_check(count.size() == 2 and count[0] <= count[1] and count[1] <= 80,
		"scatter amount is a valid authorable range")
	_check("leaf_litter" in TileLayerParameterSchema.SHAPES
		and "wood_chip" in TileLayerParameterSchema.SHAPES
		and "snow_lump" in TileLayerParameterSchema.SHAPES,
		"one generic vocabulary spans leaf, chip, and snow families")
	_check(TileKitGenerator.builder_for("liquid") == KitLiquidBuilder
		and TileKitGenerator.builder_for("fringe") == KitFringeBuilder,
		"complex water and connection-fringe families use reusable builders")


func _check_panel() -> void:
	var palette := load("res://assets/palettes/gg_material_palette.tres") as CozyPalette
	var panel := TileKitPanel.new()
	panel.setup(UiKit.new(palette))
	get_root().add_child(panel)
	_check(panel.find_child("TileKitMulti_clutter_shapes", true, false) is MenuButton,
		"inspector exposes reusable scatter content selection")
	_check(panel.find_child("TileKitSlider_clutter_count_min", true, false) is HSlider
		and panel.find_child("TileKitSlider_clutter_diameter_max", true, false) is HSlider,
		"inspector exposes generic scatter amount and size ranges")
	_check(panel.find_child(
		"TileKitOption_grass_clusters_coverage_mode", true, false
	) is OptionButton, "organic carpet exposes its composition mode")
	var add_select := panel.find_child("TileKitAddCapability", true, false) as OptionButton
	var paver_index := -1
	for index in add_select.item_count:
		if String(add_select.get_item_metadata(index)) == "pavers":
			paver_index = index
			break
	_check(paver_index >= 0, "missing capabilities appear in the generic Add menu")
	if paver_index >= 0:
		add_select.select(paver_index)
		panel._add_selected_layer()
		_check(panel.preset.layer_of_kind("pavers") != null
			and panel.find_child("TileKitOption_pavers_pattern", true, false) is OptionButton,
			"adding a capability creates its recipe data and generated controls")
		panel._remove_layer("pavers")
		_check(panel.preset.layer_of_kind("pavers") == null,
			"removing a capability removes it cleanly")
	panel.free()


func _check_template(template_id: String, expected_kind: String) -> void:
	var preset := TileTemplateLibrary.instantiate(template_id)
	_check(preset != null, "%s template instantiates" % template_id)
	if preset == null:
		return
	_check(preset.layer_of_kind(expected_kind) != null,
		"%s template contains %s capability" % [template_id, expected_kind])
	var generator := TileKitGenerator.new()
	get_root().add_child(generator)
	generator.preset = preset
	generator.rebuild()
	var stats := generator.statistics()
	_check(int(stats.get("triangles", 0)) > 0,
		"%s capability generates non-empty geometry" % expected_kind)
	_check(int(stats.get("layers", 0)) >= 2,
		"%s composes with the structural foundation" % expected_kind)
	generator.free()
