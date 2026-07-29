extends SceneTree
## Headless import/runtime probe for the authored cowboy-vest wardrobe bundle.

var _failures: PackedStringArray = []
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player_scene := load(
		"res://assets/3d/reworked/suma_player.glb"
	) as PackedScene
	_check(player_scene != null, "canonical player GLB imports")
	if player_scene != null:
		var player_root := player_scene.instantiate()
		var player_mesh := player_root.find_child(
			"geometry_0", true, false
		) as MeshInstance3D
		_check(player_mesh != null, "canonical player mesh survives region bake")
		if player_mesh != null:
			var player_format: int = player_mesh.mesh.surface_get_format(0)
			_check(
				(player_format & Mesh.ARRAY_FORMAT_TEX_UV2) != 0,
				"canonical player carries semantic armor IDs in UV2"
			)
			var arrays := player_mesh.mesh.surface_get_arrays(0)
			var armor_uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
			var found_region_ids: Dictionary = {}
			for armor_sample in armor_uv2:
				found_region_ids[roundi(armor_sample.x)] = true
			_check(
				found_region_ids.size()
					== PlayerArmorRegions.REGION_IDS.size(),
				"all semantic armor regions own body triangles"
			)
			for region_name in PlayerArmorRegions.names():
				_check(
					found_region_ids.has(
						int(PlayerArmorRegions.REGION_IDS[region_name])
					),
					"body UV2 contains region '%s'" % region_name
				)
		player_root.free()

	var scene := load("res://assets/3d/reworked/cowboy_vest.glb") as PackedScene
	_check(scene != null, "cowboy_vest.glb imports as a PackedScene")
	if scene == null:
		_finish()
		return
	var root := scene.instantiate()
	get_root().add_child(root)
	_print_tree(root)
	var imported_skeletons := root.find_children(
		"*", "Skeleton3D", true, false
	)
	_check(imported_skeletons.size() == 1, "bundle contains one helper skeleton")
	var imported_skeleton := imported_skeletons[0] as Skeleton3D
	_check(imported_skeleton.get_bone_count() == 34, "bundle preserves all 34 player bones")
	for mesh_name in ["BodyExposedForCowboyVest", "CowboyVest"]:
		var mesh := root.find_child(mesh_name, true, false) as MeshInstance3D
		_check(mesh != null, "%s survives GLB export" % mesh_name)
		if mesh != null:
			_check(mesh.mesh != null, "%s has mesh geometry" % mesh_name)
			_check(mesh.skin != null, "%s preserves skin data" % mesh_name)
			_check(
				mesh.skeleton == NodePath(".."),
				"%s targets its sibling skeleton" % mesh_name
			)
			if mesh_name.begins_with("BodyExposedFor"):
				var surface_format: int = mesh.mesh.surface_get_format(0)
				_check(
					(surface_format & Mesh.ARRAY_FORMAT_TEX_UV2) != 0,
					"%s preserves semantic armor IDs in UV2" % mesh_name
				)
	root.free()

	var palette: CozyPalette = load(
		"res://assets/palettes/gg_material_palette.tres"
	)
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	var visual := PlayerVisual.new()
	get_root().add_child(visual)
	visual.build(assets, palette)
	_check(
		visual._armor_anchors.size() == PlayerArmorRegions.names().size(),
		"every semantic armor region has a runtime anchor"
	)
	for region_name in PlayerArmorRegions.names():
		var anchor := visual.armor_anchor(region_name)
		_check(anchor != null, "armor anchor '%s' exists" % region_name)
		if anchor != null:
			var attachment := anchor.get_parent() as BoneAttachment3D
			_check(
				attachment != null
				and attachment.bone_name == String(
					visual._asset_profile.armor_region_bones[region_name]
				),
				"armor anchor '%s' targets its profile bone" % region_name
			)
	var core := GameCore.new()
	_check(core.setup(), "content loads for wardrobe runtime test")
	core.equipment.acquire("cosmetic_cowboy_vest")
	_check(
		core.equipment.equip("cosmetic_cowboy_vest"),
		"cowboy vest equips in the body slot"
	)
	visual.apply_equipment(core.equipment)

	var live_skeletons := visual.find_children("*", "Skeleton3D", true, false)
	_check(live_skeletons.size() == 1, "equipped player keeps exactly one live skeleton")
	var vest := visual.find_child("CowboyVest", true, false) as MeshInstance3D
	var exposed := visual.find_child(
		"BodyExposedForCowboyVest", true, false
	) as MeshInstance3D
	_check(
		vest == null and exposed == null,
		"modular player skips the incompatible legacy vest bundle"
	)
	_check(
		visual._base_body_meshes.size() == 1
		and visual._base_body_meshes[0].visible,
		"modular body remains visible when legacy clothing is equipped"
	)
	var body_item := core.equipment.equipped_in("body")
	var expected_mask := PlayerArmorRegions.mask_for(body_item.hide_regions)
	_check(
		body_item.hide_regions.is_empty(),
		"fitted body derivative needs no coarse runtime shoulder mask"
	)
	_check(
		exposed == null,
		"legacy exposed-body clone cannot restore the retired player"
	)
	_check(
		visual._body_region_mask == expected_mask,
		"skipped legacy clothing leaves the canonical body mask unchanged"
	)

	core.equipment.unequip("body")
	visual.apply_equipment(core.equipment)
	_check(
		visual.find_child("CowboyVest", true, false) == null,
		"unequipping removes the garment mesh"
	)
	_check(
		visual._base_body_meshes[0].visible,
		"unequipping restores the untouched canonical body"
	)
	_check(
		visual._body_region_mask == 0,
		"unequipping clears the canonical body's armor mask"
	)
	await process_frame
	await process_frame
	_finish()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok - " + message)
	else:
		_failures.append(message)
		printerr("VEST PROBE FAIL: " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("COWBOY VEST PROBE PASSED - %d checks" % _checks)
		quit(0)
	else:
		print(
			"COWBOY VEST PROBE FAILED - %d/%d failed"
			% [_failures.size(), _checks]
		)
		quit(1)


func _print_tree(node: Node, depth := 0) -> void:
	var details := ""
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		details = " surfaces=%d skin=%s skeleton=%s" % [
			mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0,
			str(mesh_instance.skin != null),
			str(mesh_instance.skeleton),
		]
	elif node is Skeleton3D:
		details = " bones=%d" % (node as Skeleton3D).get_bone_count()
	print("%s%s <%s>%s" % [
		"  ".repeat(depth),
		node.name,
		node.get_class(),
		details,
	])
	for child in node.get_children():
		_print_tree(child, depth + 1)
