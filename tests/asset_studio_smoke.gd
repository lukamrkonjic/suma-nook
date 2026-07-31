extends Node
## Opens Asset Studio from a real Main scene and exercises its live controls.

const SAVE_PATH := "user://asset_studio_smoke_save.json"
const PROFILE_PATH := "user://asset_studio_smoke_profile.json"
const AssetEditLibraryScript := preload(
	"res://scripts/visuals/asset_edit_library.gd"
)

var _main: Main
var _failures := 0


func _ready() -> void:
	_remove_test_saves()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.save_path_override = SAVE_PATH
	add_child(_main)
	await get_tree().create_timer(0.5).timeout
	await _enter_gameplay()
	_main.assets.edits = AssetEditLibraryScript.new(PROFILE_PATH)

	_main.pause_menu.open("admin")
	await _settle(2)
	_expect(
		_main.pause_menu.find_child(
			"AdminRowAssetViewer",
			true,
			false
		) != null,
		"Admin Controls exposes Asset Studio"
	)
	_main.pause_menu.close()
	await _settle(2)
	_main.open_asset_viewer()
	await _settle(8)
	var studio := _main.asset_viewer
	_expect(studio != null and studio.is_open(), "Asset Studio opens in game")
	_expect(
		studio.find_child("AssetViewerBrowser", true, false) != null,
		"catalog sidebar exists"
	)
	_expect(
		studio.find_child("AssetViewerInspector", true, false) != null,
		"editing inspector exists"
	)
	_expect(
		studio.find_child("AssetStudioSave", true, false) != null,
		"save-to-game action exists"
	)

	studio.select_content("tile_grass")
	await _settle(4)
	_expect(
		not studio.selected_asset_id().is_empty(),
		"registered tile resolves to a production asset"
	)
	studio.set_surface_smoothing(0.37)
	_expect(
		is_equal_approx(studio.working_surface_smoothing(), 0.37),
		"smoothing slider edits the live working profile"
	)
	_expect(studio.has_unsaved_asset_edits(), "live edits become dirty")
	studio.save_asset_edits()
	await _settle(4)
	_expect(
		not studio.has_unsaved_asset_edits(),
		"Save publishes the working profile"
	)
	_expect(
		is_equal_approx(
			float(
				_main.assets.edits.profile(
					"tile_layer_surface_grass_tufts"
				).get("smoothing", 0.0)
			),
			0.37
		),
		"Save persists the smoothing value and rebuilds the running world"
	)
	var edit_target := studio.find_child(
		"AssetStudioEditTarget",
		true,
		false
	) as OptionButton
	var smoothing_slider := studio.find_child(
		"AssetStudioSmoothing",
		true,
		false
	) as HSlider
	var model_scale_slider := studio.find_child(
		"AssetStudioModelScale",
		true,
		false
	) as HSlider
	_expect(
		model_scale_slider != null
		and not model_scale_slider.visible
		and not model_scale_slider.editable,
		"tile editing keeps model size unavailable"
	)
	studio.set_model_scale(1.8)
	_expect(
		is_equal_approx(studio.working_model_scale(), 1.0),
		"tile assets reject programmatic model scaling"
	)
	_expect(
		edit_target != null and edit_target.item_count >= 2,
		"layered tiles expose surface and structural base targets"
	)
	if edit_target != null and edit_target.item_count >= 2:
		edit_target.select(1)
		edit_target.item_selected.emit(1)
		await _settle(2)
		_expect(
			smoothing_slider != null and not smoothing_slider.editable,
			"structural tile bases lock the smoothing control"
		)
		studio.set_surface_smoothing(0.9)
		_expect(
			is_equal_approx(studio.working_surface_smoothing(), 0.0),
			"structural tile bases reject programmatic smoothing too"
		)

	studio.select_content("tile_sand")
	await _settle(4)
	var sand_mesh := _find_asset_mesh(
		studio,
		"tile_layer_surface_sand"
	)
	_expect(sand_mesh != null, "sand preview exposes its surface asset")
	var authored_relief := _top_relief(sand_mesh)
	studio.set_surface_smoothing(1.0)
	await _settle(2)
	sand_mesh = _find_asset_mesh(studio, "tile_layer_surface_sand")
	_expect(
		_top_relief(sand_mesh) <= authored_relief * 0.20,
		"100% live tile smoothing strongly flattens the sand relief"
	)
	var color_picker := studio.find_child(
		"AssetStudioMaterialColor",
		true,
		false
	) as ColorPickerButton
	var chosen_sand_color := Color("17120d")
	_expect(color_picker != null, "tile material color picker exists")
	if color_picker != null:
		var picker := color_picker.get_picker()
		_expect(
			not color_picker.edit_alpha
			and not color_picker.edit_intensity
			and not picker.edit_alpha
			and not picker.edit_intensity,
			"material color editing exposes neither alpha nor HDR intensity"
		)
		_expect(
			not color_picker.get_popup().transparent_bg,
			"color picker popup is rendered on an opaque panel"
		)
		var palette_family := studio.find_child(
			"AssetStudioPaletteFamily",
			true,
			false
		) as OptionButton
		var palette_search := studio.find_child(
			"AssetStudioPaletteSearch",
			true,
			false
		) as LineEdit
		_expect(
			palette_family != null
			and palette_family.item_count >= 24
			and palette_search != null,
			"palette shades are separated into searchable color families"
		)
		var palette_grid := studio.find_child(
			"AssetStudioPaletteGrid",
			true,
			false
		) as GridContainer
		_expect(
			palette_grid != null and palette_grid.columns == 3,
			"palette catalogue uses a dense three-column swatch grid"
		)
		if palette_family != null:
			var all_index := palette_family.item_count - 1
			_expect(
				palette_family.get_item_text(all_index).contains(
					"114 tokens"
				),
				"the complete curated palette exposes all 114 design tokens"
			)
			palette_family.select(all_index)
			palette_family.item_selected.emit(all_index)
			await _settle(2)
		var swatches := studio.find_children(
			"AssetStudioPalette_*",
			"Button",
			true,
			false
		)
		_expect(
			swatches.size() >= 110,
			"Suma's full named design-system palette is available"
		)
		for token in [
			"sand_highlight", "sand_light", "sand_top", "sand_shadow",
			"sand_deep",
		]:
			_expect(
				studio.find_child(
					"AssetStudioPalette_%s" % token,
					true,
					false
				) != null,
				"Sand exposes the %s palette step" % token
			)
		swatches.clear()
		if palette_search != null:
			palette_search.text = "pine"
			palette_search.text_changed.emit("pine")
			await _settle(2)
			var filtered_swatches := studio.find_children(
				"AssetStudioPalette_*",
				"Button",
				true,
				false
			)
			_expect(
				not filtered_swatches.is_empty()
				and filtered_swatches.size() < 20,
				"palette search narrows the full system to a useful family"
			)
			filtered_swatches.clear()
			palette_search.text = ""
			palette_search.text_changed.emit("")
			await _settle(2)
		color_picker.color = chosen_sand_color
		color_picker.color_changed.emit(chosen_sand_color)
		await _settle(2)
		sand_mesh = _find_asset_mesh(studio, "tile_layer_surface_sand")
		_expect(
			_material_color(sand_mesh).is_equal_approx(chosen_sand_color),
			"tile color edit changes the live composed surface material"
		)
		var terracotta := studio.find_child(
			"AssetStudioPalette_terracotta_primary",
			true,
			false
		) as Button
		_expect(terracotta != null, "named palette tokens are selectable")
		if terracotta != null:
			var palette_values := _main.assets.edits.material_values(
				_main.assets.materials.material("terracotta_primary")
			)
			chosen_sand_color = Color.from_string(
				String(palette_values.get("color", "ffffff")),
				Color.WHITE
			)
			terracotta.pressed.emit()
			await _settle(2)
			sand_mesh = _find_asset_mesh(
				studio,
				"tile_layer_surface_sand"
			)
			_expect(
				color_picker.color.a == 1.0
				and _material_color(sand_mesh).is_equal_approx(
					chosen_sand_color
				),
				"palette token applies an opaque cohesive color live"
			)
		studio.save_asset_edits()
		await _settle(3)
		var sand_profile: Dictionary = _main.assets.edits.profile(
			"tile_layer_surface_sand"
		)
		var sand_materials: Dictionary = sand_profile.get("materials", {})
		_expect(
			sand_materials.has("sand_top")
			and String(sand_materials["sand_top"].get("color", ""))
			== chosen_sand_color.to_html(false),
			"Save persists the tile color in the in-game asset profile"
		)
		var fresh_sand: Node3D = studio.get(
			"_tile_factory"
		).instantiate_visual(
			_main.core.registries.tile("tile_sand"),
			false
		)
		add_child(fresh_sand)
		var fresh_sand_mesh := _find_asset_mesh_in(
			fresh_sand,
			"tile_layer_surface_sand"
		)
		_expect(
			_material_color(fresh_sand_mesh).is_equal_approx(
				chosen_sand_color
			),
			"new in-game tile instances consume the saved color"
		)
		fresh_sand.free()

	studio.select_content("struct_firepit_polished")
	studio.set_weather_preset("rain")
	studio.set_light_preset("sunset")
	await _settle(4)
	_expect(
		studio.selected_asset_id() == "prop_firepit_polished",
		"registered model resolves to its production GLB"
	)
	_expect(
		model_scale_slider != null
		and model_scale_slider.visible
		and model_scale_slider.editable
		and is_equal_approx(model_scale_slider.min_value, 0.25)
		and is_equal_approx(model_scale_slider.max_value, 3.0),
		"models expose the 25%-to-300% uniform size slider"
	)
	studio.set_model_scale(1.65)
	await _settle(2)
	_expect(
		is_equal_approx(studio.working_model_scale(), 1.65),
		"model size slider edits the live working profile"
	)
	var preview_model_root := _find_asset_root(
		studio.get("_content_root"),
		"prop_firepit_polished"
	)
	_expect(
		preview_model_root != null
		and preview_model_root.scale.is_equal_approx(Vector3.ONE * 1.65),
		"model size changes the live production preview"
	)
	studio.save_asset_edits()
	await _settle(4)
	_expect(
		is_equal_approx(
			float(
				_main.assets.edits.profile(
					"prop_firepit_polished"
				).get("scale", 1.0)
			),
			1.65
		),
		"Save persists model size in the game asset profile"
	)
	var fresh_model := _main.assets.instantiate(
		"prop_firepit_polished"
	)
	add_child(fresh_model)
	_expect(
		fresh_model.scale.is_equal_approx(Vector3.ONE * 1.65),
		"new world model instances consume the saved size"
	)
	fresh_model.free()

	studio.close()
	await _settle(2)
	_expect(not studio.is_open(), "Asset Studio returns to gameplay")
	_expect(not get_tree().paused, "game pause state is restored")
	if _failures == 0:
		print("ASSET STUDIO SMOKE TEST PASSED")
	await _finish(_failures)


func _enter_gameplay() -> void:
	var creator := _main.find_child("Creator", false, false) as CharacterCreator
	if creator == null:
		_expect(false, "character creator is available")
		return
	creator.profile.skin_index = 2
	creator.profile.hair_style = 2
	creator.profile.hair_color_index = 3
	creator.profile.outfit_index = 1
	creator._preview()
	creator._name_edit.text = "Asset Keeper"
	creator._finish()
	await get_tree().create_timer(0.7).timeout


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await get_tree().process_frame


func _find_asset_mesh(studio: Node, asset_id: String) -> MeshInstance3D:
	var preview := studio.get("_content_root") as Node
	if preview == null:
		return null
	return _find_asset_mesh_in(preview, asset_id)


func _find_asset_mesh_in(root: Node, asset_id: String) -> MeshInstance3D:
	for descendant in root.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	):
		var mesh := descendant as MeshInstance3D
		var current: Node = mesh
		while current != null:
			if (
				current.has_meta(AssetEditLibraryScript.SOURCE_ASSET_META)
				and String(
					current.get_meta(
						AssetEditLibraryScript.SOURCE_ASSET_META
					)
				) == asset_id
			):
				return mesh
			current = current.get_parent()
	return null


func _find_asset_root(root: Node, asset_id: String) -> Node3D:
	if (
		root is Node3D
		and root.has_meta(AssetEditLibraryScript.SOURCE_ASSET_META)
		and String(
			root.get_meta(AssetEditLibraryScript.SOURCE_ASSET_META)
		) == asset_id
	):
		return root as Node3D
	for descendant in root.find_children("*", "Node3D", true, false):
		var candidate := descendant as Node3D
		if (
			candidate.has_meta(AssetEditLibraryScript.SOURCE_ASSET_META)
			and String(
				candidate.get_meta(
					AssetEditLibraryScript.SOURCE_ASSET_META
				)
			) == asset_id
		):
			return candidate
	return null


func _top_relief(mesh_instance: MeshInstance3D) -> float:
	## Interior flatness only: the perimeter ring is locked for seams and
	## keeps its authored height, so it is excluded from the measurement.
	if mesh_instance == null or mesh_instance.mesh == null:
		return INF
	var bounds := mesh_instance.get_aabb()
	var epsilon := maxf(
		0.002,
		maxf(bounds.size.x, bounds.size.z) * 0.002
	)
	var lower := INF
	var upper := -INF
	for surface in mesh_instance.mesh.get_surface_count():
		var arrays := mesh_instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index in mini(vertices.size(), normals.size()):
			if (
				normals[index].y
				< AssetEditLibraryScript.TILE_TOP_NORMAL_MIN
			):
				continue
			if (
				absf(vertices[index].x - bounds.position.x) <= epsilon
				or absf(
					vertices[index].x - bounds.position.x - bounds.size.x
				) <= epsilon
				or absf(vertices[index].z - bounds.position.z) <= epsilon
				or absf(
					vertices[index].z - bounds.position.z - bounds.size.z
				) <= epsilon
			):
				continue
			lower = minf(lower, vertices[index].y)
			upper = maxf(upper, vertices[index].y)
	return upper - lower if lower != INF else INF


func _material_color(mesh_instance: MeshInstance3D) -> Color:
	if mesh_instance == null:
		return Color.TRANSPARENT
	var material := mesh_instance.get_active_material(0)
	if material is StandardMaterial3D:
		return (material as StandardMaterial3D).albedo_color
	if material is ShaderMaterial:
		var value = (material as ShaderMaterial).get_shader_parameter("albedo")
		return value if value is Color else Color.TRANSPARENT
	return Color.TRANSPARENT


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Asset Studio smoke test failed: %s" % message)


func _finish(exit_code: int) -> void:
	if is_instance_valid(_main):
		_main.queue_free()
		_main = null
	for _frame in 5:
		await get_tree().process_frame
	_remove_test_saves()
	get_tree().paused = false
	get_tree().quit(exit_code)


func _remove_test_saves() -> void:
	for path in [SAVE_PATH, SAVE_PATH + ".backup", PROFILE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
