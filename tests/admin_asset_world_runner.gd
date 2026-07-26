extends Node
## Structural acceptance test for the exhaustive debug asset gallery.
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
	_validate_decal_isolation()
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
	var production_ids := gallery.assets.catalog_ids()
	var gallery_ids := gallery.catalog_asset_ids()
	var records := gallery.slot_records()
	check(production_ids.size() >= 85, "production resolver discovers the complete current GLB library")
	check(gallery_ids.has("tile_open_water"), "generated open-water block has a gallery slot")
	check(records.size() == gallery_ids.size(), "every manifest entry builds exactly one gallery slot")

	var unique_ids := {}
	for record: Dictionary in records:
		var asset_id := String(record["asset_id"])
		check(not unique_ids.has(asset_id), "asset has only one gallery slot: " + asset_id)
		unique_ids[asset_id] = true
		check(is_instance_valid(record["node"]), "slot node exists for " + asset_id)
	for asset_id: String in production_ids:
		check(gallery_ids.has(asset_id), "gallery includes discovered production asset " + asset_id)


func _validate_sections() -> void:
	var names := gallery.section_names()
	for expected in [
		"Overview",
		"Tiles",
		"Tile Decals",
		"Water Decals",
		"Structures",
		"Landmarks",
		"Creatures",
		"Equipment",
		"Effects",
	]:
		check(names.has(expected), "gallery exposes the %s section" % expected)


func _validate_decal_isolation() -> void:
	var tile_decals := 0
	var water_decals := 0
	var occupied_positions := {}
	for record: Dictionary in gallery.slot_records():
		var category := String(record["category"])
		if category not in ["Tile Decals", "Water Decals"]:
			continue
		var asset_id := String(record["asset_id"])
		var position: Vector3 = record["world_position"]
		check(not occupied_positions.has(position), "decal owns a separate tile: " + asset_id)
		occupied_positions[position] = true
		if category == "Tile Decals":
			tile_decals += 1
			check(record["base_tile"] == "tile_grass", "land decal uses a neutral grass tile: " + asset_id)
		else:
			water_decals += 1
			check(record["base_tile"] == "tile_water_floor", "water decal uses a water-floor tile: " + asset_id)
	check(tile_decals > 0, "land decal section contains assets")
	check(water_decals > 0, "water decal section contains assets")


func _validate_navigation() -> void:
	var before := gallery.camera_target()
	gallery.focus_section("Water Decals", true)
	check(not gallery.camera_target().is_equal_approx(before), "section jump moves the gallery camera")
	check(gallery.find_child("GalleryCamera", true, false) != null, "pan-and-zoom camera exists")
	check(gallery.find_child("GallerySectionPicker", true, false) != null, "section navigator exists")
	check(gallery.find_child("GalleryExitButton", true, false) != null, "return-to-game control exists")
