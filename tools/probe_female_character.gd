extends SceneTree
## Focused contract probe for the female mannequin and player-facing body
## selection. Run after a Godot import pass:
##
##   godot --headless --path . --script res://tools/probe_female_character.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := load(
		"res://assets/characters/body_catalog.tres"
	) as CharacterBodyCatalog
	assert(catalog != null, "body catalog failed to load")
	assert(
		catalog.validation_errors().is_empty(),
		str(catalog.validation_errors())
	)
	assert(catalog.options.size() == 2, "expected male and female body options")
	assert(
		Array(catalog.display_names()) == ["Male", "Female"],
		"body option display order changed"
	)

	var female := catalog.option_for(1)
	assert(female != null and female.option_id == "female")
	assert(female.appearance.parts.size() == 5)
	assert(
		female.appearance.part_in_slot(CharacterSlots.TOP_OUTER) == null,
		"female first-pass preset must not use male-fitted clothing"
	)
	var direct_body := female.appearance.body_profile.body_scene.instantiate()
	var direct_skeleton := direct_body.find_child(
		"Skeleton3D", true, false
	) as Skeleton3D
	var direct_mesh := direct_body.find_child(
		"PlayerFemaleBody", true, false
	) as MeshInstance3D
	var direct_player := direct_body.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	assert(direct_skeleton != null, "female body has no Skeleton3D")
	assert(direct_skeleton.get_bone_count() == 34, "female rig bone count changed")
	var bone_count := direct_skeleton.get_bone_count()
	assert(direct_mesh != null and direct_mesh.skin != null, "female body is not skinned")
	assert(
		direct_player != null
		and direct_player.has_animation("idle_relaxed"),
		"female body has no idle_relaxed animation"
	)
	direct_body.free()

	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	var visual := PlayerVisual.new()
	root.add_child(visual)
	visual.build(assets, palette)
	var profile := PlayerProfile.new()
	profile.body_index = 1
	profile.hair_style = 3
	profile.eye_index = 2
	profile.mouth_index = 1
	profile.nose_index = 1
	visual.apply_profile(profile)
	await process_frame
	var live_body := visual.find_child(
		"player_female_mannequin", true, false
	)
	assert(live_body != null, "PlayerVisual did not switch to the female body")
	assert(
		live_body.find_child("Part_hair_bun", true, false) != null,
		"female body did not receive catalog hair"
	)

	var saved := profile.to_save_dict()
	var restored := PlayerProfile.new()
	restored.from_save_dict(saved)
	assert(restored.body_index == 1, "female body choice did not round-trip")

	var kit := UiKit.new(palette)
	var creator := CharacterCreator.new()
	root.add_child(creator)
	creator.setup(kit, palette, func(_preview): pass)
	await process_frame
	var body_selector: OptionButton
	for candidate in creator.find_children("*", "OptionButton", true, false):
		var selector := candidate as OptionButton
		if (
			selector.item_count == 2
			and selector.get_item_text(0) == "Male"
			and selector.get_item_text(1) == "Female"
		):
			body_selector = selector
			break
	assert(body_selector != null, "creator exposes no Male/Female selector")
	InputDeviceService.shared().input_method = (
		InputDeviceService.InputMethod.CONTROLLER
	)
	creator.focus_default()
	await process_frame
	await process_frame
	assert(
		root.get_viewport().gui_get_focus_owner() != null,
		"creator body flow has no deterministic controller focus"
	)

	print(
		"FEMALE_CHARACTER_PROBE_OK ",
		{
			"body_options": catalog.display_names(),
			"bones": bone_count,
			"live_body": live_body.name,
			"saved_body_index": restored.body_index,
		}
	)
	quit(0)
