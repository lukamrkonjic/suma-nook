extends Node
## Structural acceptance test for the curated tile + large-placeable gallery.
## Run:
##   godot --headless --path . tests/admin_asset_world_runner.tscn

var failures: PackedStringArray = []
var checks := 0
var gallery: AdminAssetWorld


func _ready() -> void:
	gallery = (load("res://scenes/debug/AdminAssetWorld.tscn") as PackedScene).instantiate()
	add_child(gallery)
	await get_tree().process_frame
	_validate_catalog()
	_validate_sections()
	_validate_placeable_isolation()
	_validate_navigation()
	if failures.is_empty():
		print("ADMIN ASSET WORLD PASSED — %d checks" % checks)
	else:
		for failure in failures:
			printerr("ADMIN ASSET WORLD FAIL: " + failure)
		print("ADMIN ASSET WORLD FAILED — %d/%d failed" % [failures.size(), checks])
	get_tree().quit(0 if failures.is_empty() else 1)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _validate_catalog() -> void:
	var gallery_ids := gallery.catalog_asset_ids()
	var records := gallery.slot_records()
	check(gallery_ids.has("tile_open_water"), "generated open-water block has a gallery slot")
	check(gallery_ids.has("prop_bench"), "large placeables include the bench")
	check(gallery_ids.has("prop_pine_a"), "large placeables include a tree")
	check(gallery_ids.has("prop_pot"), "large placeables include the pot")
	check(not gallery_ids.has("prop_grass_tuft"), "small grass scatter is hidden")
	check(not gallery_ids.has("prop_rock_cluster"), "small rock scatter is hidden")
	check(not gallery_ids.has("prop_flowers_pink"), "small flower scatter is hidden")
	check(not gallery_ids.has("prop_uw_rocks_a"), "small underwater scatter is hidden")
	check(records.size() == gallery_ids.size(), "every manifest entry builds exactly one gallery slot")

	var unique_ids := {}
	for record: Dictionary in records:
		var asset_id := String(record["asset_id"])
		check(not unique_ids.has(asset_id), "asset has only one gallery slot: " + asset_id)
		unique_ids[asset_id] = true
		check(is_instance_valid(record["node"]), "slot node exists for " + asset_id)
		if asset_id == "tile_grass":
			check(
				record["node"].find_child(
					"surface_detail_speckles_light",
					true,
					false
				) != null,
				"Open Meadow gallery preview uses its runtime surface-detail profile"
			)
func _validate_sections() -> void:
	var names := gallery.section_names()
	for expected in [
		"Overview",
		"Tiles",
		"Large Decor",
		"Structures",
	]:
		check(names.has(expected), "gallery exposes the %s section" % expected)
	check(names.size() == 4, "gallery is limited to tiles and substantial placeables")


func _validate_placeable_isolation() -> void:
	var large_decor := 0
	var occupied_positions := {}
	for record: Dictionary in gallery.slot_records():
		var category := String(record["category"])
		if category != "Large Decor":
			continue
		var asset_id := String(record["asset_id"])
		var position: Vector3 = record["world_position"]
		check(not occupied_positions.has(position), "placeable owns a separate tile: " + asset_id)
		occupied_positions[position] = true
		large_decor += 1
		check(record["base_tile"] == "tile_grass", "large decor uses a neutral grass tile: " + asset_id)
	check(large_decor >= 10, "large decor section contains the substantial placeables")


func _validate_navigation() -> void:
	var before := gallery.camera_target()
	gallery.focus_section("Large Decor", true)
	check(not gallery.camera_target().is_equal_approx(before), "section jump moves the gallery camera")
	check(gallery.find_child("GalleryCamera", true, false) != null, "pan-and-zoom camera exists")
	check(gallery.find_child("GallerySectionPicker", true, false) != null, "section navigator exists")
	check(gallery.find_child("GalleryExitButton", true, false) != null, "return-to-game control exists")
