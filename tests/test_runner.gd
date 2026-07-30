extends SceneTree
## Headless validation suite. Run:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/test_runner.gd
## Must print "ALL TESTS PASSED".

var failures: PackedStringArray = []
var assertions := 0
const GameContentCatalogScript := preload("res://scripts/core/game_content_catalog.gd")
const CurrentSaveValidatorScript := preload(
	"res://scripts/systems/current_save_validator.gd"
)
const DebugWorldBuilderScript := preload(
	"res://scripts/debug/debug_world_builder.gd"
)
const InputDeviceServiceScript := preload(
	"res://scripts/input/input_device_service.gd"
)
const GroundImpactEffectsScript := preload(
	"res://scripts/visuals/ground_impact_effects.gd"
)


func _init() -> void:
	_run()
	if failures.is_empty():
		print("ALL TESTS PASSED — %d assertions" % assertions)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		print("TESTS FAILED — %d failures / %d assertions" % [failures.size(), assertions])
		quit(1)


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func fresh_core(seed_value := 12345) -> GameCore:
	var core := GameCore.new()
	core.setup("res://data", seed_value)
	core.save_manager.save_path = "user://test_save.json"
	core.save_manager.backup_path = "user://test_save.json.backup"
	var profile := PlayerProfile.new()
	profile.display_name = "Testkeeper"
	core.new_game(profile)
	return core


func _test_character_appearance_catalog() -> void:
	var catalog := load(
		"res://assets/characters/parts/catalog_male.tres"
	) as CharacterPartCatalog
	check(catalog != null, "character appearance catalog loads")
	if catalog == null:
		return
	var minimum_counts := {
		CharacterSlots.HAIR: 9,
		CharacterSlots.EYES: 10,
		CharacterSlots.MOUTH: 10,
		CharacterSlots.NOSE: 5,
	}
	var all_ids: Dictionary = {}
	for slot_value in minimum_counts:
		var slot := String(slot_value)
		var options := catalog.options_for(slot)
		check(
			options.size() >= int(minimum_counts[slot]),
			"%s catalog exposes the expanded option set" % slot
		)
		if options.is_empty():
			continue
		for part in options:
			var valid_part := (
				part != null
				and part.slot == slot
				and part.scene != null
				and not all_ids.has(part.part_id)
			)
			check(valid_part, "%s catalog entry is valid and unique" % slot)
			if part != null:
				all_ids[part.part_id] = true
		check(
			catalog.part_for(slot, -1) == options[0]
				and catalog.part_for(slot, 9999) == options[0],
			"%s invalid save indices fall back to its default" % slot
		)

	var profile := PlayerProfile.new()
	profile.hair_style = catalog.hair.size() - 1
	profile.eye_index = catalog.eyes.size() - 1
	profile.mouth_index = catalog.mouths.size() - 1
	profile.nose_index = catalog.noses.size() - 1
	var restored := PlayerProfile.new()
	restored.from_save_dict(profile.to_save_dict())
	check(
		restored.hair_style == profile.hair_style
			and restored.eye_index == profile.eye_index
			and restored.mouth_index == profile.mouth_index
			and restored.nose_index == profile.nose_index,
		"expanded appearance selections survive a save round trip"
	)

	var preset := load(
		"res://assets/characters/presets/default_male_appearance.tres"
	) as CharacterAppearancePreset
	var assembler := CharacterAssembler.new()
	var body := assembler.assemble(preset)
	check(body != null, "appearance catalog preset assembles")
	if body != null:
		var replacement := catalog.eyes[catalog.eyes.size() - 1]
		check(
			assembler.replace_rigid_part(replacement, preset)
				and assembler.equipped_part(CharacterSlots.EYES) == replacement,
			"runtime can replace a face option without rebuilding the body"
		)
		body.free()


func _run() -> void:
	_test_input_bindings()
	_test_clothing_lab_contract()
	_test_imported_clothing_bundle()
	_test_character_appearance_catalog()
	_test_registries()
	_test_ground_impact_surface_profiles()
	_test_content_catalog_architecture()
	_test_build_library_categories()
	_test_content_assets()
	_test_tile_slot_fill()
	_test_catalog_expansion()
	_test_gg_render_contract()
	_test_game_preferences()
	_test_starting_world()
	_test_streamed_water_tile_world_contract()
	_test_authored_onboarding_flow()
	_test_maxed_debug_world_spawn()
	_test_inspiration_hobbies()
	_test_vision_bank_cap_blocks_earning()
	_test_hobby_journal_and_direct_rewards()
	_test_out_of_scope_systems_disabled()
	_test_arrival_and_gift_loop()
	_test_arrival_queue_invariants()
	_test_practice_milestones()
	_test_journal_milestones()
	_test_deterministic_rng()
	_test_vision_choice_and_honest_duplicates()
	_test_refund_meter_and_coins()
	_test_shrine_bias_and_land_insurance()
	_test_tile_adjacency_overlap_rotation()
	_test_elevation_stacking()
	_test_connectivity_and_relocation()
	_test_sockets_and_overlap_prevention()
	_test_object_support_graph()
	_test_camping_feature_contract()
	_test_fire_interaction_contract()
	_test_anchor_cycle_and_regen()
	_test_crafting_transactions()
	_test_equipment()
	_test_landmark_lifecycle()
	_test_guardian_idempotency()
	_test_pack_and_salvage()
	_test_deed_replacement()
	_test_rework_save_round_trip()
	_test_current_save_policy()
	_test_interrupted_reveal_recovery()
	_test_progression_v1_migration()
	_test_player_defeat_safety()


func _test_imported_clothing_bundle() -> void:
	var definition_paths := {
		CharacterSlots.TOP_INNER:
			"res://assets/characters/parts/defs/top_yellow_shirt.tres",
		CharacterSlots.TOP_OUTER:
			"res://assets/characters/parts/defs/top_tweed_vest.tres",
		CharacterSlots.BOTTOM:
			"res://assets/characters/parts/defs/bottom_tweed_trousers.tres",
		CharacterSlots.HEADWEAR:
			"res://assets/characters/parts/defs/headwear_service_cap.tres",
	}
	var imported_parts: Array[CharacterPartDefinition] = []
	for expected_slot in definition_paths:
		var part := load(
			String(definition_paths[expected_slot])
		) as CharacterPartDefinition
		check(
			part != null
				and part.slot == expected_slot
				and part.scene != null
				and part.validation_errors().is_empty(),
			"imported %s clothing definition is runtime-ready"
			% expected_slot,
		)
		if part != null:
			imported_parts.append(part)

	var shirt_fit := load(
		"res://assets/characters/parts/fits/top_yellow_shirt_fit.tres"
	) as ClothingFitSettings
	var vest_fit := load(
		"res://assets/characters/parts/fits/top_tweed_vest_fit.tres"
	) as ClothingFitSettings
	var trousers_fit := load(
		"res://assets/characters/parts/fits/bottom_tweed_trousers_fit.tres"
	) as ClothingFitSettings
	check(
		shirt_fit != null
			and shirt_fit.garment_class == "upper_body"
			and vest_fit != null
			and vest_fit.garment_class == "upper_body_sleeveless"
			and trousers_fit != null
			and trousers_fit.garment_class == "lower_body",
		"imported clothes retain the correct deformation class",
	)

	var base := load(
		"res://assets/characters/presets/default_male_appearance.tres"
	) as CharacterAppearancePreset
	check(base != null, "base appearance loads for imported clothing test")
	if base == null or imported_parts.size() != definition_paths.size():
		return
	var preset := CharacterAppearancePreset.new()
	preset.preset_id = "test_imported_clothing_bundle"
	preset.body_profile = base.body_profile
	for existing in base.parts:
		if (
			existing != null
			and existing.slot != CharacterSlots.TOP_INNER
			and existing.slot != CharacterSlots.TOP_OUTER
			and existing.slot != CharacterSlots.BOTTOM
			and existing.slot != CharacterSlots.HEADWEAR
		):
			preset.parts.append(existing)
	preset.parts.append_array(imported_parts)

	var assembler := CharacterAssembler.new()
	var body := assembler.assemble(preset)
	check(body != null, "all four imported clothing items assemble together")
	if body == null:
		return
	var skeletons := body.find_children("*", "Skeleton3D", true, false)
	check(
		skeletons.size() == 1,
		"imported outfit keeps one shared runtime Skeleton3D",
	)
	if skeletons.size() == 1:
		for slot in [
			CharacterSlots.TOP_INNER,
			CharacterSlots.TOP_OUTER,
			CharacterSlots.BOTTOM,
		]:
			var garment := assembler.equipped_node(slot)
			check(
				garment is MeshInstance3D
					and garment.get_parent() == skeletons[0],
				"imported %s garment binds to the live body skeleton" % slot,
			)
			if garment is MeshInstance3D:
				check(
					(garment as MeshInstance3D).get_active_material(0) != null,
					"imported %s garment preserves its authored material"
					% slot,
				)
	var cap := assembler.equipped_node(CharacterSlots.HEADWEAR)
	check(
		cap != null
			and cap.get_parent() != null
			and cap.get_parent().name == "HatSocket",
		"service cap follows the dedicated animated head socket",
	)
	check(
		assembler.equipped_node(CharacterSlots.HAIR) == null,
		"service cap suppresses hair while equipped",
	)
	body.free()


func _test_clothing_lab_contract() -> void:
	var fit := load(
		"res://assets/characters/parts/fits/top_jacket_cozy_fit.tres"
	) as ClothingFitSettings
	check(fit != null, "Clothing Lab fit resource loads")
	if fit == null:
		return
	var fit_json := fit.to_json_data()
	check(
		String(fit_json.get("body_profile_id", "")) == "body_male"
		and String(fit_json.get("source_file", "")).ends_with(".glb"),
		"Clothing Lab fit generates deterministic source/body JSON"
	)
	var round_trip := fit.duplicate(true) as ClothingFitSettings
	round_trip.position = Vector3(0.012, -0.004, 0.008)
	round_trip.sleeve_length = 1.075
	round_trip.sleeve_room = 1.12
	round_trip.top_section_scale = 0.93
	round_trip.middle_section_scale = 1.08
	round_trip.bottom_section_scale = 1.17
	round_trip.surface_smoothing = 0.37
	round_trip.detail_erase_strokes.append({
		"version": 2,
		"selection": "small_source_components",
		"center": [0.0, 0.1, 0.02],
		"normal": [0.0, 0.0, 1.0],
		"radius": 0.04,
		"strength": 1.0,
		"target_offset": -0.01,
		"sample_uv": [0.42, 0.58],
	})
	var round_trip_path := "user://clothing_lab_fit_round_trip.tres"
	var save_error := ResourceSaver.save(round_trip, round_trip_path)
	var loaded_round_trip := load(round_trip_path) as ClothingFitSettings
	check(
		save_error == OK
		and loaded_round_trip != null
		and loaded_round_trip.position == round_trip.position
		and is_equal_approx(
			loaded_round_trip.sleeve_length, round_trip.sleeve_length
		)
		and is_equal_approx(
			loaded_round_trip.sleeve_room, round_trip.sleeve_room
		)
		and is_equal_approx(
			loaded_round_trip.top_section_scale,
			round_trip.top_section_scale
		)
		and is_equal_approx(
			loaded_round_trip.middle_section_scale,
			round_trip.middle_section_scale
		)
		and is_equal_approx(
			loaded_round_trip.bottom_section_scale,
			round_trip.bottom_section_scale
		)
		and is_equal_approx(
			loaded_round_trip.surface_smoothing,
			round_trip.surface_smoothing
		)
		and loaded_round_trip.detail_erase_strokes
		== round_trip.detail_erase_strokes,
		"Clothing Lab fit settings save/load without losing authored values"
	)
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(round_trip_path)
	)
	var body_landmark_round_trip := CharacterBodyProfile.new()
	body_landmark_round_trip.clothing_landmarks["left.shoulder"] = Vector3(
		0.13, 0.10, -0.024
	)
	var body_landmark_path := "user://clothing_lab_body_landmarks.tres"
	var body_landmark_save := ResourceSaver.save(
		body_landmark_round_trip, body_landmark_path
	)
	var loaded_body_landmarks := load(
		body_landmark_path
	) as CharacterBodyProfile
	check(
		body_landmark_save == OK
		and loaded_body_landmarks != null
		and loaded_body_landmarks.clothing_landmarks.get(
			"left.shoulder", Vector3.ZERO
		) == body_landmark_round_trip.clothing_landmarks["left.shoulder"],
		"Clothing Lab body-profile rig markers persist exactly"
	)
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(body_landmark_path)
	)
	var male_body_profile := load(
		"res://assets/characters/body_profiles/body_male.tres"
	) as CharacterBodyProfile
	var male_landmarks := (
		male_body_profile.clothing_landmarks
		if male_body_profile != null
		else {}
	)
	var crown_marker: Vector3 = male_landmarks.get(
		"center.crown", Vector3.ZERO
	)
	var face_marker: Vector3 = male_landmarks.get(
		"center.face", Vector3.ZERO
	)
	var hip_marker: Vector3 = male_landmarks.get(
		"center.hips", Vector3.ZERO
	)
	var ankle_marker: Vector3 = male_landmarks.get(
		"left.ankle", Vector3.ZERO
	)
	check(
		male_body_profile != null
		and crown_marker.y > face_marker.y
		and face_marker.y > hip_marker.y
		and ankle_marker.y < hip_marker.y
		and absf(crown_marker.z) < 0.08
		and absf(face_marker.z) < 0.08,
		"Clothing Lab body markers are persisted in Godot Y-up character space"
	)
	var landmark_lab := ClothingLab.new()
	landmark_lab.set("_default_landmarks", {
		"center": {
			"crown": Vector3(0.0, 0.44, -0.003),
			"face": Vector3(0.0, 0.25, -0.013),
			"hips": Vector3(0.0, -0.15, -0.018),
		},
		"left": {},
		"right": {},
	})
	var legacy_landmark_profile := CharacterBodyProfile.new()
	legacy_landmark_profile.clothing_landmarks.assign({
		"center.crown": Vector3(0.0, 0.003, 0.44),
		"center.face": Vector3(0.0, 0.013, 0.25),
		"center.hips": Vector3(0.0, 0.018, -0.15),
	})
	var detected_legacy_axes := bool(
		landmark_lab.call(
			"_profile_landmarks_use_blender_axes",
			legacy_landmark_profile,
		)
	)
	landmark_lab.call(
		"_migrate_profile_landmarks_to_character_space",
		legacy_landmark_profile,
	)
	check(
		detected_legacy_axes
		and legacy_landmark_profile.clothing_landmarks[
			"center.crown"
		].is_equal_approx(Vector3(0.0, 0.44, -0.003))
		and legacy_landmark_profile.clothing_landmarks[
			"center.face"
		].is_equal_approx(Vector3(0.0, 0.25, -0.013))
		and legacy_landmark_profile.clothing_landmarks[
			"center.hips"
		].is_equal_approx(Vector3(0.0, -0.15, -0.018)),
		"Clothing Lab automatically migrates legacy Blender-axis marker profiles"
	)
	landmark_lab.free()
	var fit_regions_are_known := not fit.hidden_regions.is_empty()
	for hidden_region in fit.hidden_regions:
		if not PlayerArmorRegions.names().has(hidden_region):
			fit_regions_are_known = false
	check(
		fit_regions_are_known,
		"jacket draft preserves the artist's explicit known body regions"
	)
	var part := load(
		"res://assets/characters/parts/defs/top_jacket_cozy.tres"
	) as CharacterPartDefinition
	check(
		part != null
		and part.clothing_fit != null
		and part.clothing_fit.resource_path == fit.resource_path,
		"CharacterPartDefinition references the editable fit while draft coverage remains unpublished"
	)
	var preset := load(
		"res://assets/characters/presets/default_male_appearance.tres"
	) as CharacterAppearancePreset
	var assembler := CharacterAssembler.new()
	var body := assembler.assemble(preset)
	check(body != null, "Clothing Lab preset assembles for runtime validation")
	if body != null:
		var skeletons := body.find_children(
			"*", "Skeleton3D", true, false
		)
		var garment := assembler.equipped_node(CharacterSlots.TOP_OUTER)
		check(
			skeletons.size() == 1
			and garment is MeshInstance3D
			and garment.get_parent() == skeletons[0],
			"skinned clothing uses the one live body Skeleton3D at runtime"
		)
		check(
			garment.find_children(
				"*", "AnimationPlayer", true, false
			).is_empty(),
			"runtime garment adds no AnimationPlayer"
		)
		var body_mesh := body.find_child(
			"PlayerMaleBody", true, false
		) as MeshInstance3D
		var underlayer := body.find_child(
			"ClothingUnderlayer_top_jacket_cozy", true, false
		) as MeshInstance3D
		var underlayer_is_skinned := (
			underlayer != null
			and body_mesh != null
			and underlayer.get_parent() == skeletons[0]
			and underlayer.skin == body_mesh.skin
			and underlayer.mesh != null
			and underlayer.mesh.get_surface_count() > 0
		)
		check(
			underlayer_is_skinned,
			"animated clothing generates a body-weighted fabric underlayer"
		)
		if underlayer_is_skinned:
			var garment_material := (
				garment as MeshInstance3D
			).get_active_material(0)
			var underlayer_material := underlayer.get_active_material(0)
			var underlayer_arrays := underlayer.mesh.surface_get_arrays(0)
			var underlayer_vertices: PackedVector3Array = (
				underlayer_arrays[Mesh.ARRAY_VERTEX]
			)
			var underlayer_bones: PackedInt32Array = (
				underlayer_arrays[Mesh.ARRAY_BONES]
			)
			var underlayer_weights: PackedFloat32Array = (
				underlayer_arrays[Mesh.ARRAY_WEIGHTS]
			)
			var underlayer_uvs: PackedVector2Array = (
				underlayer_arrays[Mesh.ARRAY_TEX_UV]
			)
			check(
				underlayer_material == garment_material
				and not underlayer_vertices.is_empty()
				and underlayer_bones.size() == underlayer_vertices.size() * 4
				and underlayer_weights.size() == underlayer_vertices.size() * 4
				and underlayer_uvs.size() == underlayer_vertices.size(),
				"fabric underlayer keeps garment visuals and body skin data"
			)
			assembler.set_slot_visible(CharacterSlots.TOP_OUTER, false)
			check(
				not garment.visible and not underlayer.visible,
				"garment visibility also controls its generated underlayer"
			)
			assembler.set_slot_visible(CharacterSlots.TOP_OUTER, true)
		body.free()
	var processor := FileAccess.get_file_as_string(
		"res://tools/clothing_lab/process_clothing.py"
	)
	check(
		"POLYINTERP_NEAREST" in processor
		and "LimitedBodyClearanceShrinkwrap" in processor
		and "correct_arm_chain_weights(garment)" in processor
		and "synchronize_coincident_vertex_weights" in processor
		and "remove_degenerate_faces" in processor
		and "audit_animated_deformation" in processor
		and "MAX_ANIMATED_SEAM_GAP" in processor
		and "MAX_ANIMATED_EDGE_STRETCH" in processor
		and "surface_geometry_smoothed" in processor
		and "def apply_surface_smoothing" in processor
		and "def section_scale_at_height" in processor
		and "top_section_scale" in processor
		and "middle_section_scale" in processor
		and "bottom_section_scale" in processor
		and "def source_detail_components" in processor
		and "def apply_detail_erase_strokes" in processor
		and "small_source_components" in processor
		and "anchored local surface smoothing" in processor
		and "tangent_cap = radius * 0.15 * strength" in processor
		and "\"protected_large_source_components\"" in processor
		and "\"detail_erase_vertices_smoothed\"" in processor
		and "\"inside_shell_protected\": True" in processor
		and "\"topology_changed\": False" in processor
		and "normals_split_custom_set" in processor
		and "def garment_topology_signature" in processor
		and "def assert_topology_contract" in processor
		and "\"boundary_edges\"" in processor
		and "\"euler_characteristic\"" in processor
		and "Source garment must be a closed manifold shell" in processor
		and "\"manifold_topology_contracts\"" in processor
		and "\"geometry_changed\": False" in processor
		and "export_animations=False" in processor
		and "source_normals_smoothed\": False" in processor,
		"Clothing Lab prevents open shells, repairs animated seams, audits deformation, and preserves source normals"
	)
	var lab_scene_text := FileAccess.get_file_as_string(
		"res://characters/lab/clothing_lab.tscn"
	)
	var lab_script_text := FileAccess.get_file_as_string(
		"res://characters/lab/clothing_lab.gd"
	)
	check(
		"play_idle = false" in lab_scene_text
		and "REST / T-POSE" in lab_script_text
		and "GLTFDocument.new()" in lab_script_text
		and "Auto Clear Body" in lab_script_text
		and "Editable Raw Fit" in lab_script_text
		and "Bound / Animated Garment" in lab_script_text
		and "Bound Final Output" in lab_script_text
		and "Pose / animation" in lab_script_text
		and "Animation speed" in lab_script_text
		and "Live smooth shading" in lab_script_text
		and "Surface detail eraser" in lab_script_text
		and "_pick_raw_garment" in lab_script_text
		and "_detail_source_component_data" in lab_script_text
		and "small_source_components" in lab_script_text
		and "var tangent_cap := radius * 0.15 * strength" in lab_script_text
		and "_detail_erased_source_arrays" in lab_script_text
		and "_calculate_preview_smoothing_normals" in lab_script_text
		and "_ground_preview_character" in lab_script_text
		and "Idle — relaxed" in lab_script_text
		and "Walk — loop" in lab_script_text
		and "_sync_final_output_pose" in lab_script_text
		and "_final_output_revision" in lab_script_text
		and "1. Save Fit + Rig Draft" in lab_script_text
		and "2. Build Final Output · Copy Weights + Bind" in lab_script_text
		and "4. Publish Final Output to Game" in lab_script_text
		and "_current_staging_output_path" in lab_script_text
		and "_fit_diagnostic_warnings" in lab_script_text
		and "ADVISORY ONLY — NEVER BLOCKING" in lab_script_text
		and "\"BLOCKED" not in lab_script_text,
		"Clothing Lab has non-blocking diagnostics, animation previews, and an ordered publish flow"
	)
	check(
		"MOUSE_BUTTON_MIDDLE" in lab_script_text
		and "func _input(event: InputEvent)" in lab_script_text
		and "_orbit_preview" in lab_script_text
		and "_snap_axis_view" in lab_script_text
		and "look_up" in lab_script_text
		and "look_down" in lab_script_text
		and "\"+X\"" in lab_script_text
		and "\"-X\"" in lab_script_text
		and "\"+Y\"" in lab_script_text
		and "\"-Y\"" in lab_script_text
		and "\"+Z\"" in lab_script_text
		and "\"-Z\"" in lab_script_text,
		"Clothing Lab supports MMB/controller 3D orbit and six axis snaps"
	)
	check(
		"_numeric_drag_handle" in lab_script_text
		and "_revert_numeric_field" in lab_script_text
		and "Lock XYZ scale proportions" in lab_script_text
		and "_proportional_scale_for_axis" in lab_script_text
		and "event.is_action_pressed(\"undo\"" in lab_script_text
		and "event.is_action_pressed(\"redo\"" in lab_script_text
		and "_begin_history_batch" in lab_script_text
		and "One continuous handle drag" in FileAccess.get_file_as_string(
			"res://tools/clothing_lab/README.md"
		),
		"Clothing Lab exposes draggable fields, per-field revert, and grouped undo/redo"
	)
	check(
		"sphere.radius = 0.018" in lab_script_text
		and "material.no_depth_test = true" in lab_script_text
		and "material.render_priority = 127" in lab_script_text,
		"Clothing Lab landmarks are large depth-independent overlays"
	)
	check(
		"Edit rig markers" in lab_script_text
		and "_pick_landmark_marker" in lab_script_text
		and "_drag_marker" in lab_script_text
		and "_store_landmarks_in_body_profile" in lab_script_text
		and "_set_marker_clothing_isolation" in lab_script_text
		and "Show equipped clothing" in lab_script_text
		and "_apply_garment_preview_visibility" in lab_script_text
		and "Full-body clothing rig markers" in lab_script_text
		and "\"center.crown\"" in lab_script_text
		and "\"center.hips\"" in lab_script_text
		and "\"left.knee\"" in lab_script_text
		and "\"right.toe\"" in lab_script_text
		and "LANDMARK_BONES" in lab_script_text
		and "Head pivot (base of skull)" in lab_script_text
		and "Pelvis center (body root)" in lab_script_text
		and "_axis_constrained_marker_position" in lab_script_text
		and "Input.is_key_pressed(KEY_X)" in lab_script_text
		and "Input.is_key_pressed(KEY_Y)" in lab_script_text
		and "Input.is_key_pressed(KEY_Z)" in lab_script_text
		and "_migrate_profile_landmarks_to_character_space" in lab_script_text
		and "_profile_landmarks_use_blender_axes" in lab_script_text
		and "processor_point.z" in lab_script_text,
		(
			"Clothing Lab provides explicit anatomical rig labels, persistent "
			+ "Y-up global markers, XYZ-constrained dragging, and garment isolation"
		)
	)
	check(
		"ORBIT_MOUSE_SENSITIVITY := 0.004" in lab_script_text
		and "-mouse_motion.relative * ORBIT_MOUSE_SENSITIVITY"
		in lab_script_text,
		"Clothing Lab MMB orbit is inverted and uses reduced sensitivity"
	)
	check(
		"Live Preview Hidden Regions" in lab_script_text
		and "_preview_hidden_regions.button_pressed = true"
		in lab_script_text
		and "_enable_live_hide_preview()" in lab_script_text,
		"Clothing Lab coverage checkboxes preview body hiding immediately"
	)
	var character_builder := FileAccess.get_file_as_string(
		"res://art_source/characters/build_character_master.py"
	)
	check(
		"dominant_group == \"mixamorigHead\"" in character_builder
		and "dominant_group == \"mixamorigNeck\"" in character_builder
		and "if z > 0.120:" in character_builder
		and "if z > 0.075:" in character_builder
		and "if ax > 0.245 and z < 0.15:" in character_builder,
		"body masks follow head/neck anatomy and stay beneath collars/cuffs"
	)


func _test_ground_impact_surface_profiles() -> void:
	var core := fresh_core()
	var expected := {
		"tile_grass": "grass",
		"tile_sand": "sand",
		"tile_snowfield": "snow",
		"tile_concrete_brutalist": "stone",
		"tile_wooden_planks": "wood",
		"tile_dirt": "earth",
		"tile_mud": "mud",
		"tile_open_water": "water",
	}
	for tile_id: String in expected:
		check(
			GroundImpactEffectsScript.surface_profile_for_definition(
				core.registries.tile(tile_id)
			) == expected[tile_id],
			"%s resolves to its authored %s jump/landing effect"
			% [tile_id, expected[tile_id]]
		)


func _test_maxed_debug_world_spawn() -> void:
	var core := fresh_core(8675309)
	var report: Dictionary = DebugWorldBuilderScript.populate(
		core,
		DebugWorldBuilderScript.MAXED_TILE_COUNT,
		DebugWorldBuilderScript.MAXED_MODEL_COUNT,
		8675309
	)
	var models := 0
	var spawn_clear := true
	for state: WorldGrid.CellState in core.grid.cells.values():
		models += state.structures.size()
	for y in range(
		-DebugWorldBuilderScript.SPAWN_CLEAR_RADIUS,
		DebugWorldBuilderScript.SPAWN_CLEAR_RADIUS + 1
	):
		for x in range(
			-DebugWorldBuilderScript.SPAWN_CLEAR_RADIUS,
			DebugWorldBuilderScript.SPAWN_CLEAR_RADIUS + 1
		):
			var state := core.grid.cell(Vector2i(x, y))
			if state != null and not state.structures.is_empty():
				spawn_clear = false
	check(
		spawn_clear,
		"maxed debug world keeps the complete spawn clearing model-free"
	)
	check(
		models == DebugWorldBuilderScript.MAXED_MODEL_COUNT,
		"maxed debug world relocates spawn models without reducing stress count"
	)
	check(
		int(report["spawn_models"]) == 0
		and int(report["spawn_clear_cell_count"]) == 25,
		"debug report records the zero-model 5x5 spawn clearing"
	)
	check(
		core.grid.tile_def(Vector2i.ZERO).id == "tile_grass"
		and core.profile.position == core.grid.cell_to_world(Vector2i.ZERO),
		"maxed debug player starts on the reserved grass center"
	)


func _test_input_bindings() -> void:
	var input_service := InputDeviceServiceScript.new()
	check(_action_has_key("move_up", KEY_W), "W remains bound to character movement")
	check(_action_has_key("move_left", KEY_A), "A remains bound to character movement")
	check(not _action_has_key("move_up", KEY_UP), "up arrow no longer moves the character")
	check(not _action_has_key("move_left", KEY_LEFT), "left arrow no longer moves the character")
	check(_action_has_key("camera_rotate_right", KEY_LEFT), "left arrow uses the reversed camera spin")
	check(_action_has_key("camera_rotate_left", KEY_RIGHT), "right arrow uses the reversed camera spin")
	check(_action_has_key("camera_zoom_in", KEY_UP), "up arrow zooms the camera in")
	check(_action_has_key("camera_zoom_out", KEY_DOWN), "down arrow zooms the camera out")
	check(_action_has_key("cancel", KEY_ESCAPE), "Escape opens and closes the pause flow")
	check(_action_has_key("toggle_hud", KEY_H), "H hides and restores the HUD")
	check(
		not _action_has_key("interact", KEY_E)
		and _action_has_mouse_button("interact", MOUSE_BUTTON_LEFT),
		"world interaction is left-click driven with no E-key binding"
	)
	check(
		not _action_has_key("return_home", KEY_H)
		and _action_has_key("return_home", KEY_HOME),
		"Home returns the player home without conflicting with the HUD shortcut"
	)
	check(
		_action_has_joypad_button("toggle_hud", JOY_BUTTON_RIGHT_STICK)
		and _action_has_joypad_button(
			"return_home", JOY_BUTTON_RIGHT_STICK
		),
		"R3 supports tap-to-hide and hold-to-return-home"
	)
	for action: StringName in InputDeviceService.REQUIRED_CONTROLLER_ACTIONS:
		check(
			InputMap.has_action(action)
			and input_service.action_has_controller_binding(action),
			"%s has a controller binding" % action
		)
	check(
		_action_has_joypad_button("interact", JOY_BUTTON_X),
		"west face button is contextual interact"
	)
	check(
		_action_has_joypad_button("jump", JOY_BUTTON_A),
		"south face button is jump and UI confirm"
	)
	check(
		_action_has_joypad_button("build_mode", JOY_BUTTON_Y),
		"north face button enters the build context"
	)
	check(
		_action_has_joypad_button("cancel", JOY_BUTTON_B),
		"east face button is contextual back"
	)
	check(
		_action_has_joypad_axis("undo", JOY_AXIS_TRIGGER_LEFT, 1.0)
		and _action_has_joypad_axis(
			"camera_zoom_in", JOY_AXIS_TRIGGER_LEFT, 1.0
		),
		"left trigger is contextually undo in build mode and zoom elsewhere"
	)
	check(
		input_service.prompt_for_action(
			&"interact",
			InputDeviceService.InputMethod.CONTROLLER
		) == "X",
		"controller prompts are resolved from InputMap"
	)
	check(
		input_service.prompt_for_action(
			&"interact",
			InputDeviceService.InputMethod.KEYBOARD_MOUSE
		) == "Left Click",
		"keyboard and mouse interaction prompts advertise the click path"
	)
	check(
		input_service.prompt_for_action(
			&"build_confirm",
			InputDeviceService.InputMethod.KEYBOARD_MOUSE
		) == "Left Click",
		"the build confirm prompt retains its mouse path"
	)
	check(
		InputDeviceService.controller_family_for_name("DualSense Wireless")
			== InputDeviceService.ControllerFamily.PLAYSTATION
		and InputDeviceService.controller_family_for_name(
			"Nintendo Switch Pro Controller"
		) == InputDeviceService.ControllerFamily.NINTENDO,
		"controller family detection supports PlayStation and Nintendo names"
	)
	var joy_button := InputEventJoypadButton.new()
	joy_button.pressed = true
	var quiet_axis := InputEventJoypadMotion.new()
	quiet_axis.axis_value = 0.2
	var deliberate_axis := InputEventJoypadMotion.new()
	deliberate_axis.axis_value = 0.8
	check(
		InputDeviceService.classify_event(joy_button)
			== InputDeviceService.InputMethod.CONTROLLER
		and InputDeviceService.classify_event(quiet_axis) == -1
		and InputDeviceService.classify_event(deliberate_axis)
			== InputDeviceService.InputMethod.CONTROLLER,
		"device switching ignores stick drift and accepts deliberate input"
	)
	check(
		PlacementController.controller_grid_direction(
			Vector2i.UP, 0
		) == Vector2i.UP
		and PlacementController.controller_grid_direction(
			Vector2i.UP, 1
		) == Vector2i.LEFT
		and PlacementController.controller_grid_direction(
			Vector2i.UP, 2
		) == Vector2i.DOWN
		and PlacementController.controller_grid_direction(
			Vector2i.UP, 3
		) == Vector2i.RIGHT,
		"build cursor directions remain camera-relative through every orbit"
	)
	input_service.free()


func _action_has_key(action: StringName, physical_keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event != null and key_event.physical_keycode == physical_keycode:
			return true
	return false


func _action_has_mouse_button(
	action: StringName,
	button_index: MouseButton
) -> bool:
	for event in InputMap.action_get_events(action):
		var mouse_event := event as InputEventMouseButton
		if (
			mouse_event != null
			and mouse_event.button_index == button_index
		):
			return true
	return false


func _action_has_joypad_button(
	action: StringName,
	button_index: JoyButton
) -> bool:
	for event in InputMap.action_get_events(action):
		var button_event := event as InputEventJoypadButton
		if (
			button_event != null
			and button_event.button_index == button_index
		):
			return true
	return false


func _action_has_joypad_axis(
	action: StringName,
	axis: JoyAxis,
	axis_value: float
) -> bool:
	for event in InputMap.action_get_events(action):
		var motion_event := event as InputEventJoypadMotion
		if (
			motion_event != null
			and motion_event.axis == axis
			and is_equal_approx(motion_event.axis_value, axis_value)
		):
			return true
	return false


func _test_registries() -> void:
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "all data files load and cross-validate: " + ", ".join(regs.load_errors))
	check(regs.skills.size() == 3, "three skills defined")
	check(regs.tiles.size() >= 15, "at least 15 tile variants")
	check(regs.skill("mining").future, "mining is a future (data-only) skill")
	check(not regs.feature("combat_enabled"), "combat is disabled")
	check(regs.feature("ferry_arrivals_enabled"), "periodic arrivals are enabled")
	check(
		is_equal_approx(regs.tunef("tile_size", 0.0), 1.35)
		and is_equal_approx(regs.tunef("block_depth", 0.0), 0.5),
		"tile dimensions use the GG-like 1.35 m footprint and audited 0.50 m stacking step"
	)
	check(
		regs.tile("tile_open_water").render_profile == "continuous_water"
		and regs.tile("tile_open_water").collision_profile == "none",
		"open water presentation is selected by behavior profiles"
	)
	check(
		regs.tile("tile_grass_pond_edge").collision_profile == "pond_basin",
		"pond collision is selected by its definition instead of a renderer id check"
	)
	check(
		regs.active_tile_ids() == [
			"tile_grass", "tile_sand", "tile_grove_mature",
			"tile_concrete_brutalist", "tile_snowfield"
		]
		and regs.tile("tile_grass").uses_layered_visual()
		and regs.tile("tile_grass").visual_layers.size() == 2
		and regs.tile("tile_grass").visual_layer("base").asset_id
			== "tile_layer_base_standard"
		and regs.tile("tile_grass").visual_layer("surface").asset_id
			== "tile_layer_surface_flat"
		and regs.tile("tile_concrete_brutalist").visual_layer("base").asset_id
			== "tile_layer_base_deep_recess"
		and regs.tile("tile_grass").surface_detail_profile == "",
		"the active roster uses the deep constructed base for concrete and a clean meadow surface"
	)
	check(
		regs.structure("struct_dock").collision_profile == "walkable_surface",
		"the dock is classified as a walkable surface rather than a solid object blocker"
	)
	check(
		regs.structure("struct_dock").grid_fit_profile == "tile_span",
		"the dock opts into live-grid footprint fitting"
	)
	var fishing := regs.skill("fishing")
	check(
		fishing.domain_id == "domain_waterside"
		and regs.inspiration_domain("domain_waterside") != null
		and regs.domain_for_activity("fishing").id == "domain_waterside"
		and regs.domain_for_family("living_grove").id == "domain_grove",
		"activities and tile families resolve to their inspiration domains"
	)
	var wildcard_count := 0
	for domain_id: String in regs.inspiration_domains:
		if regs.inspiration_domain(domain_id).wildcard:
			wildcard_count += 1
	check(wildcard_count == 1, "exactly one wildcard (Drift) domain ships")


func _test_content_catalog_architecture() -> void:
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "catalog snapshot loads before atomic reload test")
	var expected_kinds := [
		"skills", "items", "tiles", "structures", "recipes", "loot_tables",
		"inspiration_domains", "milestones", "anchors", "capabilities",
		"enemies", "landmarks",
	]
	check(
		regs.definition_kinds() == expected_kinds,
		"one global catalog lifecycle covers every current definition family"
	)
	var global_count := 0
	for kind: String in regs.definition_kinds():
		var family: Dictionary = regs.definitions(kind)
		check(not family.is_empty(), "%s participates in the global catalog" % kind)
		for content_id: String in family:
			global_count += 1
			check(
				regs.definition(kind, content_id) == family[content_id]
				and regs.definition_source(kind, content_id) != null
				and regs.definition_traits(kind, content_id) != null,
				"%s/%s has typed data, provenance, and common traits"
				% [kind, content_id]
			)
	check(global_count > 0, "every shipped definition uses the global contract")
	check(
		regs.definition_has_tag("items", "fish_dawnfin", "fish"),
		"item tags are available through the global definition API"
	)
	check(
		regs.definition_has_capability(
			"structures", "struct_high_tent", "shelter"
		)
		and int(regs.definition_capability(
			"structures", "struct_high_tent", "shelter"
		).get("capacity", 0)) == 2,
		"capabilities use the same global API rather than a tent-only registry"
	)
	var original_snapshot: Variant = regs.snapshot
	var original_tile_count := regs.tiles.size()
	var source: Variant = regs.definition_source("structures", "struct_bench")
	check(source != null, "definitions retain source provenance")
	check(
		source.path.ends_with("structures.json") and source.content_id == "struct_bench",
		"definition provenance identifies its exact file and stable id"
	)
	check(
		not regs.reload_all_atomic("user://definitely_missing_suma_catalog", false),
		"invalid development reload is rejected"
	)
	check(
		regs.snapshot == original_snapshot and regs.tiles.size() == original_tile_count,
		"failed reload preserves the previously published immutable catalog"
	)
	check(
		not regs.load_issues.is_empty()
		and String(regs.load_errors[0]).contains("definitely_missing_suma_catalog"),
		"structured reload failures report the source path"
	)


func _test_build_library_categories() -> void:
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "build-library category registry loads")
	var expected_tiles := {
		"tile_open_water": "ground",
		"tile_grass": "ground",
		"tile_plain_ground": "ground",
		"tile_grass_flower": "ground",
		"tile_grass_pond_edge": "ground",
		"tile_path": "ground",
		"tile_garden": "ground",
		"tile_courtyard": "ground",
		"tile_dirt": "ground",
		"tile_dirt_road": "ground",
		"tile_dirt_crossroad": "ground",
		"tile_mud": "ground",
		"tile_sand": "ground",
		"tile_clay": "ground",
		"tile_grove_mature": "woodland",
		"tile_grove_birch": "woodland",
		"tile_grove_mossy": "woodland",
		"tile_grove_autumn": "woodland",
		"tile_grove_flowering": "woodland",
		"tile_stone_clearing": "stone",
		"tile_stone_mossy": "stone",
		"tile_stone_ruin": "stone",
		"tile_stone_crystal": "stone",
		"tile_stone_road": "stone",
		"tile_cobblestone": "stone",
		"tile_flagstone": "stone",
		"tile_concrete_brutalist": "stone",
		"tile_snowfield": "winter",
		"tile_snow_drift": "winter",
		"tile_snow_path": "winter",
		"tile_frosted_stone": "winter",
	}
	for tile_id: String in expected_tiles:
		check(
			Hud.category_for_tile(regs.tile(tile_id)) == expected_tiles[tile_id],
			"%s appears in the expected build-library terrain category" % tile_id
		)

	var expected_structures := {
		"struct_bench": "furniture",
		"struct_stool": "furniture",
		"struct_table": "furniture",
		"struct_fence": "boundaries",
		"struct_gate": "boundaries",
		"struct_lantern": "utilities",
		"struct_campfire": "utilities",
		"struct_firepit_polished": "utilities",
		"struct_high_tent": "buildings",
		"struct_planter": "nature",
		"struct_pot": "nature",
		"struct_chest": "storage",
		"struct_box": "storage",
		"struct_dock": "buildings",
		"struct_sign": "boundaries",
		"struct_ruin_arch": "buildings",
		"struct_stone_wall": "boundaries",
		"struct_stone_wall_polished": "boundaries",
		"struct_fishing_marker": "utilities",
		"struct_pine": "nature",
		"struct_pine_tall": "nature",
		"struct_pine_young": "nature",
		"struct_bush": "nature",
		"struct_stone_wall_low": "boundaries",
		"struct_stone_wall_corner": "boundaries",
		"struct_stone_pillar": "boundaries",
		"struct_stone_well": "utilities",
		"struct_stone_bench": "furniture",
		"struct_birdbath": "nature",
		"struct_watering_can": "utilities",
		"struct_barrel": "storage",
		"struct_crate": "storage",
		"struct_wheelbarrow": "utilities",
		"struct_log_pile": "storage",
		"struct_wooden_arch": "buildings",
		"struct_milk_churn": "storage",
		"struct_garden_trellis": "boundaries",
		"struct_snowman": "nature",
		"struct_water_wheel": "buildings",
	}
	for structure_id: String in expected_structures:
		check(
			Hud.category_for_structure(regs.structure(structure_id))
			== expected_structures[structure_id],
			"%s appears in the expected build-library object category" % structure_id
		)


## The slot-fill contract — the root guarantee behind "no seams ever": every
## land tile's structural shell (its `*_body`/`*_cap` meshes) fills EXACTLY
## one tile slot — precisely TILE wide on both axes, from the -0.50 block
## bottom to the y=0 walkable plane, with a full-footprint, full-depth body.
## Anything narrower opens see-through cracks to water or sky behind;
## anything wider or deeper bleeds into neighbouring slots. Decorative
## relief may float inside the slot, but the shell must fill it.
func _test_tile_slot_fill() -> void:
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "slot-fill contract registry loads")
	const HALF := 0.85
	const EPS := 0.005
	const GEOMETRY_PROFILES := [
		"hard_square", "micro_bevel_square", "soft_recessed_top",
		"rounded_corner_slab", "stepped_platform", "constructed_material",
		"organic_overlay_square", "connected_water",
	]
	const CONNECTION_MODES := [
		"full_flush", "tiny_individual_seam", "soft_isolated", "merged_surface",
	]
	for tile_id in regs.tiles:
		var def: Defs.TileDefinition = regs.tiles[tile_id]
		check(
			def.geometry_profile in GEOMETRY_PROFILES,
			"tile %s declares a known geometry profile (got '%s')" % [tile_id, def.geometry_profile]
		)
		check(
			def.connection_mode in CONNECTION_MODES,
			"tile %s declares a known connection mode (got '%s')" % [tile_id, def.connection_mode]
		)
		check(
			def.geometry_profile != "connected_water" or def.surface_kind == "water",
			"tile %s only uses the connected water profile on a water surface" % tile_id
		)
		check(
			def.exposed_top in ["flush", "recessed", "raised"],
			"tile %s declares a known exposed-top kind (got '%s')" % [tile_id, def.exposed_top]
		)
		if def.surface_kind == "water":
			continue
		var asset_ids: Array[String] = [def.asset_id] as Array[String]
		if def.uses_layered_visual():
			asset_ids.clear()
			for layer: Defs.TileVisualLayerDefinition in def.visual_layers:
				if layer.role in ["base", "surface"]:
					asset_ids.append(layer.asset_id)
		var shell := AABB()
		var has_shell := false
		var has_filler := false
		for asset_id: String in asset_ids:
			var scene := _tile_scene(asset_id)
			check(
				scene != null,
				"tile %s layer asset %s resolves for slot validation"
				% [tile_id, asset_id]
			)
			if scene == null:
				continue
			var root := scene.instantiate()
			for found in root.find_children("*", "MeshInstance3D", true, false):
				var mesh_instance := found as MeshInstance3D
				var lower := String(mesh_instance.name).to_lower()
				if not (lower.ends_with("_body") or lower.ends_with("_cap")):
					continue
				var relative := Transform3D.IDENTITY
				var cursor: Node3D = mesh_instance
				while cursor != null and cursor != root:
					relative = cursor.transform * relative
					cursor = cursor.get_parent() as Node3D
				var bounds: AABB = relative * mesh_instance.get_aabb()
				shell = bounds if not has_shell else shell.merge(bounds)
				has_shell = true
				# The shared base itself must fill the structural slot; the
				# merged AABB of multiple narrower pieces is not sufficient.
				if (
					bounds.size.x >= TILE_SLOT - EPS
					and bounds.size.z >= TILE_SLOT - EPS
					and bounds.position.y <= -0.5 + EPS
				):
					has_filler = true
			root.free()
		check(has_shell, "tile %s has structural _body/_cap meshes" % tile_id)
		if not has_shell:
			continue
		check(
			absf(shell.position.x + HALF) <= EPS and absf(shell.end.x - HALF) <= EPS
			and absf(shell.position.z + HALF) <= EPS and absf(shell.end.z - HALF) <= EPS,
			"tile %s shell spans exactly one slot footprint (got x %.3f..%.3f, z %.3f..%.3f)"
			% [tile_id, shell.position.x, shell.end.x, shell.position.z, shell.end.z]
		)
		# The exposed top's vertical freedom depends on its declared kind; the
		# COVERED form is always exact because the runtime swaps the whole top
		# layer for a flush infill lid over the (validated) full-depth filler.
		var top_ok := false
		match def.exposed_top:
			"recessed":
				top_ok = shell.end.y >= -0.12 - EPS and shell.end.y <= EPS
			"raised":
				top_ok = shell.end.y >= -EPS and shell.end.y <= 0.35 + EPS
			_:
				top_ok = absf(shell.end.y) <= EPS
		check(
			absf(shell.position.y + 0.5) <= EPS and top_ok,
			"tile %s shell spans block bottom to its declared %s top (got y %.3f..%.3f)"
			% [tile_id, def.exposed_top, shell.position.y, shell.end.y]
		)
		check(
			has_filler,
			"tile %s has a full-footprint structural mesh flush to the block bottom" % tile_id
		)

	var core := fresh_core(303)
	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	var factory := TileVisualFactory.new(assets, core.grid)
	for tile_id: String in core.registries.active_tile_ids():
		var visual := factory.instantiate_visual(core.registries.tile(tile_id))
		var base_meshes: Array[MeshInstance3D] = []
		var surface_meshes: Array[MeshInstance3D] = []
		for found in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh := found as MeshInstance3D
			match String(mesh.get_meta(TileVisualFactory.LAYER_ROLE_META, "")):
				"base":
					base_meshes.append(mesh)
				"surface":
					surface_meshes.append(mesh)
		check(
			not base_meshes.is_empty() and not surface_meshes.is_empty(),
			"active tile %s assembles explicit base and surface render layers" % tile_id
		)
		if tile_id == "tile_concrete_brutalist":
			var concrete_base_top := -INF
			var concrete_surface_bottom := INF
			for mesh in base_meshes + surface_meshes:
				var relative := Transform3D.IDENTITY
				var cursor: Node3D = mesh
				while cursor != null and cursor != visual:
					relative = cursor.transform * relative
					cursor = cursor.get_parent() as Node3D
				var bounds: AABB = relative * mesh.get_aabb()
				if base_meshes.has(mesh):
					concrete_base_top = maxf(concrete_base_top, bounds.end.y)
				else:
					concrete_surface_bottom = minf(
						concrete_surface_bottom, bounds.position.y
					)
			check(
				absf(concrete_base_top + 0.20) <= EPS
				and absf(concrete_surface_bottom + 0.20) <= EPS,
				"concrete base and hard-shaded cap meet at the 20 cm deep constructed seam"
			)
		factory.set_surface_covered(visual, true, false)
		check(
			base_meshes.all(func(mesh: MeshInstance3D): return mesh.visible)
			and surface_meshes.all(func(mesh: MeshInstance3D): return not mesh.visible),
			"covering %s persists its base and hides its complete surface layer" % tile_id
		)
		if tile_id == "tile_concrete_brutalist":
			var infill := visual.find_child(
				TileVisualFactory.COVERED_INFILL_NAME, true, false
			) as MeshInstance3D
			check(
				infill != null
				and absf(infill.position.y + 0.10) <= EPS
				and absf(infill.get_aabb().size.y - 0.20) <= EPS,
				"covered concrete replaces its deep cap with an exact 20 cm flush infill"
			)
		factory.set_surface_covered(visual, false, false)
		check(
			surface_meshes.all(func(mesh: MeshInstance3D): return mesh.visible),
			"uncovering %s restores its surface layer" % tile_id
		)
		visual.free()


const TILE_SLOT := 1.70
const _TILE_GLB_PATHS := [
	"res://assets/3d/reworked/%s.glb",
	"res://assets/3d/final/%s.glb",
	"res://assets/3d/proxies/%s.glb",
]


func _tile_scene(asset_id: String) -> PackedScene:
	for path_template in _TILE_GLB_PATHS:
		var path: String = String(path_template) % asset_id
		if ResourceLoader.exists(path):
			return load(path) as PackedScene
	return null


func _test_content_assets() -> void:
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "content asset validation registry loads")
	var errors := ContentValidator.validate(regs)
	check(errors.is_empty(), "every production definition resolves its visual asset: " + ", ".join(errors))


func _test_catalog_expansion() -> void:
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "expanded catalog loads before focused contract checks")
	var winter_tiles := [
		"tile_snowfield",
		"tile_snow_drift",
		"tile_snow_path",
		"tile_frosted_stone",
	]
	for tile_id: String in winter_tiles:
		var tile := regs.tile(tile_id)
		check(
			tile != null and tile.family == "winter"
			and tile.stackable and tile.supports_tiles and tile.surface_kind == "flat",
			"%s remains a modular flat winter tile" % tile_id
		)
	var earth_and_stone_tiles := [
		"tile_dirt",
		"tile_dirt_road",
		"tile_dirt_crossroad",
		"tile_mud",
		"tile_sand",
		"tile_clay",
		"tile_cobblestone",
		"tile_flagstone",
	]
	for tile_id: String in earth_and_stone_tiles:
		var tile := regs.tile(tile_id)
		check(
			tile != null and tile.stackable and tile.supports_tiles,
			"%s participates in the global tile stacking contract" % tile_id
		)
	check(
		regs.inspiration_domain("domain_winter") != null
		and regs.inspiration_domain("domain_winter").tile_families.has("winter")
		and not regs.tiles_in_family("winter").is_empty(),
		"winter terrain is obtainable through its inspiration domain pool"
	)
	var watering_can := regs.structure("struct_watering_can")
	check(
		watering_can.can_be_stacked
		and watering_can.placement_tags.has("small_surface_item")
		and watering_can.placement_tags.has("tabletop_item"),
		"watering can can sit on compatible stools, benches, tables, and containers"
	)
	for structure_id in [
		"struct_stone_wall_low",
		"struct_stone_wall_corner",
		"struct_stone_pillar",
	]:
		check(
			regs.structure(structure_id).blocks_movement,
			"%s participates in object collision" % structure_id
		)
	var wheel := regs.structure("struct_water_wheel")
	check(
		wheel.allowed_surface_kinds == ["water"]
		and wheel.has_capability("ambient_motion")
		and wheel.grid_fit_profile == "tile_span",
		"waterside wheel is water-only, grid-fitted, and data-animated"
	)
	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var assets := AssetLibrary.new(MaterialLibrary.new(palette))
	var wheel_visual := assets.instantiate("prop_water_wheel")
	check(
		wheel_visual.find_child("WaterWheelRotor", true, false) is Node3D,
		"water-wheel GLB preserves the named runtime rotor hierarchy"
	)
	var motion_root := Node3D.new()
	var rotor := Node3D.new()
	rotor.name = "Rotor"
	motion_root.add_child(rotor)
	var motion := AmbientMotion.new()
	check(
		motion.configure(motion_root, {"node": "Rotor", "axis": "z", "speed": 1.0}),
		"generic ambient motion resolves a data-named authored node"
	)
	var before := rotor.quaternion
	motion._process(0.5)
	check(
		not rotor.quaternion.is_equal_approx(before),
		"generic ambient motion advances the target transform"
	)
	wheel_visual.free()
	motion.free()
	motion_root.free()


func _test_gg_render_contract() -> void:
	var profile := load("res://assets/visual_profiles/suma_soft_daylight_warm.tres") as VisualStyleProfile
	check(profile != null, "Suma soft-daylight visual profile loads")
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "render-contract tuning registry loads")
	check(
		regs.tunef("camera_min_size", 40.0) <= 14.0
		and regs.tunef("camera_default_size", 40.0) == 32.0
		and regs.tunef("camera_wheel_zoom_step", 1.0) == 5.0,
		"camera supports a deep close-up with the closer default composition"
	)
	check(
		profile.shadow_max_distance >= 75.0,
		"Soft-daylight shadow range covers the complete gameplay camera envelope"
	)
	check(
		profile.shadow_opacity >= 0.65 and profile.shadow_opacity <= 0.75
		and profile.shadow_normal_bias >= 1.0
		and profile.shadow_cascade_mode == "pssm_4",
		"Soft-daylight shadows keep the miniature grounded with GG-like plane separation"
	)
	check(
		profile.ssao_enabled and profile.ssao_intensity >= 0.8 and profile.ssao_radius <= 0.3,
		"Soft-daylight SSAO is tight and contact-focused"
	)
	check(
		profile.tonemap == "agx"
		and profile.agx_white >= 12.0
		and profile.agx_white <= 16.0
		and profile.contrast <= 1.06
		and profile.glow_enabled
		and profile.glow_hdr_threshold >= 1.6,
		"Soft-daylight uses a restrained pop grade and emissive-only bloom"
	)
	check(
		ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d") == 2
		and ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa") == 1
		and not ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa")
		and ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size") == 4096,
		"Soft-daylight uses balanced 4x MSAA and a bounded shadow map"
	)


func _test_game_preferences() -> void:
	var preferences := GamePreferences.new()
	preferences.from_dict({
		"fullscreen": true,
		"vsync": false,
		"anti_aliasing": GamePreferences.AA_BALANCED,
		"ssao": false,
		"bloom": false,
		"cloud_shadows": false,
		"master_volume": 0.35,
		"music_volume": 0.2,
		"tutorial_hints": false,
	})
	var saved := preferences.to_dict()
	check(
		saved["fullscreen"] and not saved["vsync"]
		and saved["anti_aliasing"] == GamePreferences.AA_BALANCED,
		"display and anti-aliasing preferences round-trip"
	)
	check(
		not saved["ssao"] and not saved["bloom"]
		and not saved["cloud_shadows"]
		and is_equal_approx(saved["master_volume"], 0.35)
		and is_equal_approx(saved["music_volume"], 0.2),
		"post-processing and audio preferences round-trip"
	)
	check(not saved["tutorial_hints"], "tutorial visibility preference round-trips")
	preferences.from_dict({"anti_aliasing": "not-a-quality", "master_volume": 4.0})
	check(
		preferences.anti_aliasing == GamePreferences.AA_BALANCED
		and preferences.master_volume == 1.0,
		"invalid preference values fall back safely"
	)


func _test_starting_world() -> void:
	var core := fresh_core()
	check(core.grid.cells.size() == 9, "fresh save starts with exactly nine cells")
	var water: Array[Vector2i] = []
	var walkable := 0
	for coord: Vector2i in core.grid.cells:
		if core.grid.tile_def(coord).id == "tile_open_water":
			water.append(coord)
		if core.grid.is_walkable(coord):
			walkable += 1
	check(water.size() == 3, "starting world has exactly three water cells")
	check(water.has(Vector2i(-1, -1)) and water.has(Vector2i(0, -1)) and water.has(Vector2i(1, -1)), "water occupies the northern/top row")
	check(walkable == 6, "the other six starting cells are walkable land")
	check(water[0].distance_squared_to(water[1]) <= 4 and water[1].distance_squared_to(water[2]) <= 4, "the water cells form one connected edge")
	for y in [0, 1]:
		check(
			core.grid.tile_def(Vector2i(-1, y)).id == "tile_grass"
			and core.grid.tile_def(Vector2i(0, y)).id == "tile_grass"
			and core.grid.tile_def(Vector2i(1, y)).id == "tile_grass",
			"opening land row %d uses the default starter land" % y
		)
	check(
		core.stock.structure_count("struct_wishing_well") == 1,
		"the wishing well waits in the build library for guided placement"
	)
	# The arrival pick personalizes the six land cells.
	var picked := GameCore.new()
	picked.setup("res://data", 999)
	picked.save_manager.save_path = "user://test_save_pick.json"
	picked.save_manager.backup_path = "user://test_save_pick.json.backup"
	var picked_profile := PlayerProfile.new()
	picked_profile.display_name = "Sandkeeper"
	picked_profile.starter_land_id = "tile_sand"
	picked.new_game(picked_profile)
	check(
		picked.grid.tile_def(Vector2i(0, 0)).id == "tile_sand",
		"the chosen starter land shapes the opening island"
	)
	var locked: Array[Vector2i] = []
	for coord: Vector2i in core.grid.cells:
		if core.grid.cell(coord).movement_locked:
			locked.append(coord)
	check(
		locked == [GameCore.FIRST_WATER_COORD],
		"only the first water tile is movement-locked"
	)
	for coord: Vector2i in core.grid.cells:
		check(
			core.grid.cell(coord).structures.size() <= 1,
			"opening tile %s has at most one independently placeable object" % coord
		)
	var placed_tree_count := 0
	var chest_count := 0
	for slot: Dictionary in core.grid.all_cell_slots():
		var state: WorldGrid.CellState = slot["state"]
		for structure: WorldGrid.StructureState in state.structures:
			var definition := core.registries.structure(structure.structure_id)
			if definition != null and definition.anchor_id == "grove_anchor":
				placed_tree_count += 1
			if (
				definition != null
				and definition.has_capability("storage_access")
				and slot["coord"] == Vector2i(1, 0)
			):
				chest_count += 1
	check(placed_tree_count == 0, "fresh worlds do not pre-place any trees")
	check(chest_count == 1, "the inventory chest starts as one independent object")
	check(core.stock.structure_count("struct_pine") == 1, "the starter tree waits in build stock")
	check(
		core.stock.structure_count("struct_stone_wall_polished") == 1,
		"the polished stone wall is immediately discoverable in build stock"
	)
	check(
		core.stock.structure_count("struct_firepit_polished") == 1,
		"the polished firepit is immediately discoverable in build stock"
	)
	for tile_id: String in [
		"tile_grove_mature",
		"tile_grove_birch",
		"tile_grove_mossy",
		"tile_grove_autumn",
		"tile_grove_flowering",
	]:
		check(core.registries.tile(tile_id).anchor_id == "", "%s is cosmetic terrain only" % tile_id)
	for tree_id: String in ["struct_pine", "struct_pine_tall", "struct_pine_young"]:
		check(
			core.registries.structure(tree_id).anchor_id == "grove_anchor",
			"%s independently owns Woodland Tending" % tree_id
		)
	check(core.grid.is_walkable(Vector2i.ZERO), "home cell walkable")
	check(core.grid.world_to_cell(core.profile.position) == Vector2i.ZERO, "player spawns safely on central land")
	check(core.equipment.owns("tool_rod_basic"), "starter rod owned")


func _test_streamed_water_tile_world_contract() -> void:
	var core := fresh_core(8080)
	var envelope := core.world_envelope
	var water_field = core.water_field
	var initial_constructed := envelope.constructed_bounds()
	var initial_envelope := envelope.bounds()
	check(
		initial_envelope == initial_constructed.grow(
			core.registries.tunei("ocean_margin_cells", 20)
		),
		"world envelope is derived from sparse constructed bounds plus margin"
	)
	var generated_corner := initial_envelope.position
	check(
		water_field.is_generated_water(generated_corner)
			and water_field.tile_id_at(generated_corner)
				== "tile_open_water"
			and water_field.tile_definition_at(generated_corner)
				== core.registries.tile("tile_open_water")
			and water_field.tile_definition_at(generated_corner).anchor_id
				== "pond_anchor"
			and not core.grid.has_cell(generated_corner),
		"unconstructed coordinates resolve to the real fishable water tile"
	)
	var hidden_coord := initial_envelope.end + Vector2i.ONE
	check(
		water_field.tile_id_at(hidden_coord) == ""
			and water_field.tile_id_at(hidden_coord, true)
				== "tile_open_water",
		"hidden coordinates retain deterministic water tiles without revealing them"
	)
	check(
		core.grid.to_save_dict()["cells"].size()
			== core.grid.total_tile_count(),
		"generated water tiles never bloat sparse grid persistence"
	)
	var bucket_record: Dictionary = water_field.remove_water_tile(
		generated_corner
	)
	check(
		bucket_record.get("source", "") == "generated"
			and water_field.tile_id_at(generated_corner) == ""
			and water_field.to_save_dict()[
				"removed_generated_cells"
			].size() == 1,
		"future bucket removal records one sparse generated-water tombstone"
	)
	check(
		water_field.restore_water_tile(
			generated_corner,
			bucket_record
		)
			and water_field.is_generated_water(generated_corner),
		"a moved generated water tile can be restored without materializing the ocean"
	)
	water_field.remove_water_tile(generated_corner)
	var persisted_water: Dictionary = water_field.to_save_dict()
	var restored_core := fresh_core(8083)
	restored_core.water_field.from_save_dict(persisted_water)
	check(
		restored_core.water_field.source_at(generated_corner) == "removed"
			and restored_core.water_field.tile_id_at(generated_corner) == "",
		"generated-water bucket tombstones survive a save-data round trip"
	)
	restored_core.water_field.reset()
	check(
		restored_core.water_field.is_generated_water(generated_corner),
		"a new-world reset clears prior generated-water mutations"
	)

	var dock_core := fresh_core(8082)
	var generated_dock_coord := Vector2i(2, 0)
	check(
		dock_core.water_field.is_generated_water(generated_dock_coord),
		"an unbuilt dock target begins as generated water"
	)
	var promoted: WorldGrid.CellState = dock_core.water_field.materialize(
		generated_dock_coord
	)
	var generated_dock := dock_core.grid.add_structure(
		generated_dock_coord,
		"struct_dock",
		0
	)
	check(
		promoted != null
			and promoted.tile_id == "tile_open_water"
			and generated_dock != null,
		"generated water promotes to the same mutable tile state when a dock needs it"
	)

	var clear_water := GameCore.FIRST_WATER_COORD
	var water_stock_before := core.stock.tile_count("tile_open_water")
	var tile_count_before := core.grid.total_tile_count()
	core.stock.add_tile("tile_grass")
	check(
		core.grid.can_replace_open_water(clear_water, "tile_grass"),
		"clear authored water accepts an ordinary replacement tile"
	)
	check(
		core.place_tile_from_stock(clear_water, "tile_grass", 2),
		"placing from stock atomically replaces authored water"
	)
	check(
		core.grid.tile_def(clear_water).id == "tile_grass"
			and core.grid.total_tile_count() == tile_count_before
			and core.stock.tile_count("tile_open_water") == water_stock_before,
		"water replacement keeps cell count stable and never refunds water"
	)
	check(
		not core.grid.can_replace_open_water(
			GameCore.STARTER_DOCK_COORD,
			"tile_grass"
		),
		"water supporting a placed object must be cleared before replacement"
	)

	var bounds_before_growth := envelope.bounds()
	var constructed := envelope.constructed_bounds()
	var east_anchor := Vector2i(
		constructed.end.x - 1,
		constructed.position.y
	)
	while not core.grid.has_cell(east_anchor):
		east_anchor.y += 1
	var east_frontier := east_anchor + Vector2i.RIGHT
	check(
		water_field.replacement_record(
			east_frontier,
			"tile_sand"
		).get("source", "") == "generated",
		"edge land targets one generated water tile"
	)
	core.stock.add_tile("tile_sand")
	check(
		core.place_tile_from_stock(east_frontier, "tile_sand", 0),
		"normal edge placement replaces a generated water tile"
	)
	check(
		not water_field.is_open_water(east_frontier)
			and core.grid.tile_def(east_frontier).id == "tile_sand",
		"the explicit land override replaces water at that coordinate"
	)
	var bounds_after_growth := envelope.bounds()
	check(
		bounds_after_growth.end.x == bounds_before_growth.end.x + 1
			and bounds_after_growth.position == bounds_before_growth.position,
		"eastward construction pushes only the east distance limit outward"
	)
	var removed_land := core.grid.remove_tile(east_frontier)
	check(
		removed_land != null
			and removed_land.tile_id == "tile_sand"
			and water_field.is_generated_water(east_frontier),
		"removing a land override reveals its generated water tile again"
	)

	var moving := fresh_core(8081)
	var source := Vector2i(0, 1)
	var target_water := GameCore.FIRST_WATER_COORD
	var stack := moving.grid.detach_tile_stack(source, 0)
	var displaced := moving.grid.replace_open_water_with_stack(
		target_water,
		stack
	)
	check(
		displaced != null
			and displaced.tile_id == "tile_open_water"
			and moving.grid.tile_def(target_water).id == "tile_grass"
			and not moving.grid.has_cell(source),
		"moved tile stacks can atomically displace clear authored water"
	)


func _test_authored_onboarding_flow() -> void:
	var core := GameCore.new()
	check(core.setup("res://data", 1717), "onboarding core loads")
	core.save_manager.save_path = "user://test_onboarding_save.json"
	core.save_manager.backup_path = "user://test_onboarding_save.json.backup"
	var profile := PlayerProfile.new()
	profile.display_name = "New Keeper"
	core.begin_onboarding_game(profile)
	check(
		core.grid.placed_tile_count() == 0
			and core.onboarding.stage == OnboardingState.LAND_CHOICE,
		"onboarding begins in an empty world at the saved land choice"
	)
	check(
		core.registries.tune("starter_land_options", []) == [
			"tile_grove_mature", "tile_sand", "tile_snowfield"
		],
		"the first landing offers forest, sand, and snow"
	)
	check(
		not core.choose_onboarding_land("tile_concrete_brutalist")
			and core.grid.placed_tile_count() == 0,
		"the arrival picker rejects land outside its curated three choices"
	)
	check(
		core.choose_onboarding_land("tile_grove_mature"),
		"a valid first land materializes"
	)
	check(
		core.grid.tile_def(Vector2i.ZERO).id == "tile_grove_mature"
			and core.grid.cells.size() == 25
			and core._placed_tile_count("tile_grove_mature") == 9
			and core._placed_tile_count("tile_open_water") == 16
			and core._is_structure_placed("struct_pine")
			and core.stock.tile_count("tile_open_water") == 1
			and core.onboarding.stage == OnboardingState.PLACE_WATER,
		"choosing land raises a 3x3 grove, complete water ring, one tree, and the guided water shape"
	)

	check(
		core.place_tile_from_stock(Vector2i(3, 0), "tile_open_water", 0),
		"guided water can extend the authored water ring"
	)
	var next := core.advance_onboarding_after_placement()
	check(
		core.onboarding.stage == OnboardingState.PLACE_WELL
			and next.get("id") == "struct_wishing_well"
			and core.stock.structure_count("struct_wishing_well") == 1,
		"extending the water ring guarantees the wishing well"
	)

	var restored := OnboardingState.new()
	restored.from_save_dict(core.onboarding.to_save_dict())
	check(
		restored.stage == OnboardingState.PLACE_WELL
			and restored.guided_id == "struct_wishing_well",
		"an interrupted guided step restores its exact required piece"
	)
	var well_token := core.stock.take_structure_token("struct_wishing_well")
	var well := core.grid.add_structure(
		Vector2i.ZERO,
		"struct_wishing_well",
		0
	)
	check(not well_token.is_empty() and well != null, "the guaranteed well places on the first land")
	next = core.advance_onboarding_after_placement()
	check(
		core.onboarding.stage == OnboardingState.TEND_TREE,
		"placing the well points to the tree that arrived with the island"
	)
	check(
		core.onboarding_vision_banked()
			and core.onboarding.stage == OnboardingState.CLAIM_VISION,
		"the first banked Inspiration becomes a well-claim objective"
	)
	check(
		core.onboarding_vision_chosen(VisionSystem.KIND_TILE, "tile_grass"),
		"choosing a Vision records the exact placement reward"
	)
	var guided := core.ensure_onboarding_guided_piece()
	check(
		guided.get("id") == "tile_grass"
			and core.stock.tile_count("tile_grass") == 1,
		"an interrupted Vision placement repairs its selected reward"
	)
	check(
		core.place_tile_from_stock(Vector2i(0, 3), "tile_grass", 0),
		"the first claimed Vision can grow the authored world"
	)
	core.advance_onboarding_after_placement()
	check(
		core.onboarding.stage == OnboardingState.TRY_FISHING,
		"placing the first Vision hands off to fishing on player-placed water"
	)
	check(
		core.onboarding_fished()
			and core.onboarding.stage == OnboardingState.COMPLETE,
		"one fishing catch completes onboarding without leaving a progression gate"
	)


func _test_inspiration_hobbies() -> void:
	var core := fresh_core(404)
	var inventory_before := core.inventory.counts.duplicate()
	for hobby_id in ["fishing", "woodcutting"]:
		var skill := core.registries.skill(hobby_id)
		var domain := core.registries.domain_for_activity(hobby_id)
		var old_chance := skill.direct_tile_reward_chance
		skill.direct_tile_reward_chance = 0.0
		var meter_before: float = core.progression.inspiration.meter_progress(domain.id)["current"]
		var result := core.rewards.resolve_hobby_action(skill)
		var feedback := core.progression.on_activity_action(hobby_id)
		check(String(feedback["domain_id"]) == domain.id, "%s pays into its own domain" % hobby_id)
		check(bool(feedback["added"]), "%s action emits inspiration" % hobby_id)
		var meter_after: float = core.progression.inspiration.meter_progress(domain.id)["current"]
		check(
			meter_after > meter_before or bool(feedback["banked"]),
			"%s inspiration reaches the domain meter or banks a Vision" % hobby_id
		)
		check(core.progression.actions_done(hobby_id) == 1, "%s lifetime action recorded" % hobby_id)
		check(not result.has_world_reward(), "ordinary %s action has no forced world reward" % hobby_id)
		skill.direct_tile_reward_chance = old_chance
	check(str(core.inventory.counts) == str(inventory_before), "Fishing and Woodland Tending add no common inventory items")


func _test_vision_bank_cap_blocks_earning() -> void:
	var core := fresh_core(405)
	var inspiration := core.progression.inspiration
	var cap := inspiration.bank_cap()
	check(cap == 3, "the well banks at most three Visions")
	var blocked_signals := [0]
	inspiration.earning_blocked.connect(func(_domain): blocked_signals[0] += 1)
	# Overfill: enough inspiration to bank far past the cap in one domain.
	for i in 40:
		inspiration.add("domain_grove", 240.0)
		if not inspiration.can_earn():
			break
	check(inspiration.banked.size() == cap, "banked Visions stop exactly at the cap")
	check(not inspiration.can_earn(), "earning refuses while the well is full")
	var refused := inspiration.add("domain_grove", 12.0)
	check(bool(refused["blocked"]) and blocked_signals[0] >= 1, "a full well refuses new inspiration with a signal")
	check(
		is_equal_approx(inspiration.speed_multiplier(), 1.0 + cap * core.registries.tunef("vision_speed_bonus_per_stack", 0.12)),
		"each banked Vision stacks the walk-back speed bonus"
	)
	var claimed := inspiration.claim_next()
	check(claimed == "domain_grove", "claiming pops the oldest banked Vision")
	check(inspiration.can_earn(), "claiming reopens earning")


func _test_hobby_journal_and_direct_rewards() -> void:
	var core := fresh_core(505)
	var fishing := core.registries.skill("fishing")
	core.registries.tuning["fishing_collection_chance"] = 1.0
	var old_entries := fishing.collection_entries.duplicate()
	fishing.collection_entries = ["test_sunfish"] as Array[String]
	var first := core.rewards.resolve_hobby_action(fishing)
	check(first.collection_discovery_id == "test_sunfish", "first-time fish resolves a journal entry")
	check(first.was_new_discovery, "first journal catch is marked new")
	check(core.collection.is_discovered("fish", "test_sunfish"), "journal metadata is recorded")
	check(core.inventory.counts.is_empty(), "journal discovery creates no fish item stack")
	var before_tiles := core.stock.tile_count("tile_sand")
	var old_chance := fishing.direct_tile_reward_chance
	var old_pool := fishing.direct_tile_reward_pool.duplicate()
	fishing.direct_tile_reward_chance = 1.0
	fishing.direct_tile_reward_pool = ["tile_sand"] as Array[String]
	var rare := core.rewards.resolve_hobby_action(fishing)
	check(rare.optional_tile_reward_id == "tile_sand", "rare hobby reward is already a finished active tile")
	check(core.stock.tile_count("tile_sand") == before_tiles + 1, "rare active tile enters the Tile Library directly")
	check(core.inventory.counts.is_empty(), "rare world reward bypasses material inventory")
	fishing.collection_entries = old_entries
	fishing.direct_tile_reward_chance = old_chance
	fishing.direct_tile_reward_pool = old_pool


func _test_out_of_scope_systems_disabled() -> void:
	var core := fresh_core()
	check(core.crafting.available_recipes().is_empty(), "material crafting recipes are hidden")
	check(not core.crafting.craft("recipe_bench"), "material crafting stays disabled")
	for i in 20:
		core.stock.add_tile("tile_grass")
		var coord := Vector2i(2 + i, 0)
		core.place_tile_from_stock(coord, "tile_grass", 0)
	check(core.landmarks.active.is_empty(), "world growth creates no hostile landmarks")
	check(not core.registries.feature("monsters_enabled"), "monster spawning flag remains disabled")
	check(not core.registries.feature("hostile_landmarks_enabled"), "hostile landmark flag remains disabled")


func _test_arrival_and_gift_loop() -> void:
	var core := fresh_core(606)
	var requested: Array = []
	core.arrivals.arrival_requested.connect(func(payload): requested.append(payload))
	core.arrivals.time_until_next = 0.01
	core.tick(0.02)
	check(requested.size() == 1, "arrival timer requests exactly one presentation")
	check(core.arrivals.state == ArrivalScheduler.ARRIVING, "arrival enters presentation state")
	var payload := requested[0] as LandParcelPayload
	check(payload.gift_kind == "vision", "ferry payload is a gift Vision")
	core.arrivals.mark_delivery_ready(payload)
	check(core.arrivals.has_waiting_package(), "ferry unloads one waiting package")
	var options := core.arrivals.open_waiting(core.progression)
	check(options.size() == 3, "dock gift reveals three choices")
	check(core.arrivals.state == ArrivalScheduler.OPENED, "scheduler pauses while the gift choice is open")
	var stock_before := _entry_stock_count(core, options[0])
	var result := core.progression.visions.choose(0)
	check(str(result["entry"]) == str(options[0]), "selected gift option is authoritative")
	check(
		_entry_stock_count(core, options[0]) == stock_before + 1,
		"selected piece enters the build library"
	)
	core.arrivals.resolve_delivery()
	check(core.arrivals.state == ArrivalScheduler.IDLE, "next timer begins after the choice is stored")
	check(core.arrivals.time_until_next >= 300.0, "later arrival uses configured relaxed timing")


func _entry_stock_count(core: GameCore, entry: Dictionary) -> int:
	match String(entry.get("kind", "")):
		"tile": return core.stock.tile_count(String(entry["id"]))
		"structure": return core.stock.structure_count(String(entry["id"]))
	return 0


func _test_arrival_queue_invariants() -> void:
	var core := fresh_core(707)
	var requests := [0]
	core.arrivals.arrival_requested.connect(func(_payload): requests[0] += 1)
	check(core.arrivals.trigger_arrival(), "arrival uses the shared scheduler")
	check(requests[0] == 1, "presentation receives one generic request")
	var payload := core.arrivals.current_payload
	core.arrivals.mark_delivery_ready(payload)
	check(not core.arrivals.trigger_arrival(), "unopened package blocks delivery accumulation")
	var fishing := core.registries.skill("fishing")
	fishing.direct_tile_reward_chance = 0.0
	core.rewards.resolve_hobby_action(fishing)
	check(core.arrivals.has_waiting_package(), "player can perform a hobby while ferry package waits")
	check(core.arrivals.deliveries_created == 0, "waiting never creates unattended delivery stacks")


func _test_practice_milestones() -> void:
	var core := fresh_core()
	var reached: Array = []
	core.progression.milestones.milestone_reached.connect(func(id, _rewards): reached.append(id))
	var fishing := core.registries.skill("fishing")
	var old_chance := fishing.direct_tile_reward_chance
	fishing.direct_tile_reward_chance = 0.0
	for i in 5:
		core.progression.on_activity_action("fishing")
	check(reached.has("ms_fishing_first_casts"), "five casts reach the first practice milestone")
	check(core.stock.structure_count("struct_bench") == 0, "a note-only milestone creates no inventory")
	check(
		not core.progression.is_recipe_unlocked(core.registries.recipe("recipe_bench")),
		"the bench recipe stays locked before its milestone"
	)
	for i in 7:
		core.progression.on_activity_action("fishing")
	check(reached.has("ms_fishing_settled_in"), "twelve casts reach the bench milestone")
	check(core.stock.structure_count("struct_bench") == 1, "the milestone grants its data-defined bench reward")
	check(
		core.progression.is_recipe_unlocked(core.registries.recipe("recipe_bench")),
		"the bench recipe unlocks with its milestone"
	)
	var reached_before := reached.size()
	core.progression.milestones.check_all(core.progression.activity_actions)
	check(reached.size() == reached_before, "milestones grant exactly once")
	fishing.direct_tile_reward_chance = old_chance


func _test_journal_milestones() -> void:
	var core := fresh_core()
	var reached: Array = []
	core.progression.milestones.milestone_reached.connect(func(id, _rewards): reached.append(id))
	core.collection.record("fish", "sunny_minnow")
	core.collection.record("fish", "pond_darter")
	check(not reached.has("ms_journal_fish_page"), "an incomplete journal page stays unclaimed")
	core.collection.record("fish", "silver_leaf_fish")
	check(reached.has("ms_journal_fish_page"), "completing every entry claims the journal milestone")


func _test_deterministic_rng() -> void:
	var a := fresh_core(777)
	var b := fresh_core(777)
	var seq_a: Array = []
	var seq_b: Array = []
	for i in 12:
		seq_a.append(a.rng.randi_range("determinism_probe", 0, 1_000_000))
		seq_b.append(b.rng.randi_range("determinism_probe", 0, 1_000_000))
	check(str(seq_a) == str(seq_b), "identical seeds produce identical loot sequences")
	var c := fresh_core(778)
	var differs := false
	for i in 12:
		if c.rng.randi_range("determinism_probe", 0, 1_000_000) != seq_a[i]:
			differs = true
	check(differs, "different seeds diverge")


func _test_vision_choice_and_honest_duplicates() -> void:
	var core := fresh_core()
	var visions := core.progression.visions
	core.progression.inspiration.banked.append("domain_grove")
	var options := visions.claim_from_well(core.progression.inspiration)
	check(options.size() == 3, "a claimed Vision reveals three options")
	var first_trio: Array = core.registries.tune("first_vision_options", [])
	var matches_trio := options.size() == first_trio.size()
	for index in options.size():
		if String(options[index]["id"]) != String(first_trio[index]):
			matches_trio = false
	check(matches_trio, "the first-ever Vision offers the guaranteed starter trio")
	var result := visions.choose(1)
	var chosen: Dictionary = result["entry"]
	check(str(chosen) == str(options[1]), "choose returns the picked entry")
	check(core.stock.tile_count(String(chosen["id"])) == 1, "chosen tile lands in build stock")
	check(core.collection.is_discovered("tiles", String(chosen["id"])), "choice recorded in collection")
	# Duplicates are honest outcomes: choosing an owned piece simply grants
	# another copy — no dust, no hidden conversion.
	visions.pending_options = [chosen.duplicate(), chosen.duplicate(), chosen.duplicate()] as Array[Dictionary]
	visions.choose(0)
	check(core.stock.tile_count(String(chosen["id"])) == 2, "a duplicate choice grants a real second copy")
	check(core.inventory.counts.is_empty(), "duplicates convert into no currency")


func _test_refund_meter_and_coins() -> void:
	var core := fresh_core()
	var refunds := core.progression.refunds
	var minted: Array = []
	refunds.coin_minted.connect(func(domain_id, _coins): minted.append(domain_id))
	core.stock.add_tile("tile_grass", 3)
	check(refunds.can_refund("tile", "tile_grass"), "an owned meadow tile is refundable")
	check(refunds.domain_of("tile", "tile_grass").id == "domain_meadow", "refund domain comes from the tile family")
	for i in 3:
		check(refunds.refund("tile", "tile_grass"), "refund %d consumes an owned copy" % (i + 1))
	check(core.stock.tile_count("tile_grass") == 0, "the well keeps what it is given")
	check(minted == ["domain_meadow"], "three refunds of a kind mint that domain's coin")
	check(refunds.coin_count("domain_meadow") == 1, "the coin waits at the well")
	check(refunds.meter("domain_meadow") == 0, "the carving meter resets after minting")
	check(refunds.spend_coin("domain_meadow"), "a coin releases a promised Vision")
	check(refunds.coin_count("domain_meadow") == 0, "the released coin is spent")
	var options := core.progression.visions.pending_options
	check(options.size() == 3, "the coin Vision offers three options")
	for entry: Dictionary in options:
		var tile := core.registries.tile(String(entry["id"]))
		check(
			String(entry["kind"]) == "tile" and tile != null and tile.family == "home_meadow",
			"every coin option belongs to the promised domain"
		)
	core.progression.visions.choose(0)


func _test_shrine_bias_and_land_insurance() -> void:
	var core := fresh_core()
	var visions := core.progression.visions
	visions.claims_total = 1   # past the first-vision guarantee
	# Land insurance: while the world is small, slot 0 is always plain land.
	check(
		visions.owned_tile_count() < core.registries.tunei("land_insurance_owned_tiles", 25),
		"a fresh save is under the insurance threshold"
	)
	core.progression.inspiration.banked.append("domain_grove")
	var options := visions.claim_from_well(core.progression.inspiration)
	var insurance_pool: Array = core.registries.tune("land_insurance_pool", [])
	check(
		String(options[0]["kind"]) == "tile" and insurance_pool.has(String(options[0]["id"])),
		"small worlds always see a plain land option in slot 0"
	)
	visions.choose(0)
	# Shrine bias: the focused entry's draw weight is visibly multiplied.
	core.collection.record("tiles", "tile_snowfield")
	check(core.progression.shrine.set_focus("tile", "tile_snowfield"), "a discovered tile can be shrined")
	var biased_weight := 0.0
	var base_weight := 0.0
	for entry: Dictionary in visions._full_pool():
		if String(entry["id"]) == "tile_snowfield":
			biased_weight = float(entry["weight"])
	core.progression.shrine.clear_focus()
	for entry: Dictionary in visions._full_pool():
		if String(entry["id"]) == "tile_snowfield":
			base_weight = float(entry["weight"])
	check(
		base_weight > 0.0
		and is_equal_approx(
			biased_weight,
			base_weight * core.registries.tunef("shrine_bias_multiplier", 4.0)
		),
		"the shrined piece draws at the tuned bias multiplier"
	)


func _test_tile_adjacency_overlap_rotation() -> void:
	var core := fresh_core()
	check(not core.grid.can_place_tile(Vector2i(5, 5)), "detached placement rejected")
	check(not core.grid.can_place_tile(Vector2i.ZERO), "overlap rejected")
	check(core.grid.can_place_tile(Vector2i(2, 0)), "edge-adjacent placement accepted")
	core.stock.add_tile("tile_grass")
	check(core.place_tile_from_stock(Vector2i(2, 0), "tile_grass", 3), "placement from stock succeeds")
	check(core.grid.cell(Vector2i(2, 0)).rotation == 3, "rotation persists on the placed cell")
	check(not core.place_tile_from_stock(Vector2i(2, 0), "tile_grass", 0), "double placement rejected")
	check(core.stock.tile_count("tile_grass") == 0, "stock consumed exactly once")


func _test_elevation_stacking() -> void:
	var core := fresh_core()
	var coord := Vector2i.ZERO
	var initial_count := core.grid.total_tile_count()
	core.stock.add_tile("tile_grass", 2)
	check(
		core.grid.can_place_tile_at(coord, 1, "tile_grass"),
		"a clear flat tile supports an upper land block"
	)
	check(
		core.place_tile_from_stock(coord, "tile_grass", 1, 1),
		"tile stock can be placed into elevation one"
	)
	check(
		core.grid.top_elevation(coord) == 1
		and core.grid.cell_at(coord, 1).rotation == 1,
		"elevated tile owns an independent layer and rotation"
	)
	check(
		is_equal_approx(core.grid.cell_to_world(coord, 1).y, core.grid.block_depth),
		"elevated holder aligns exactly one authored block depth above its support"
	)
	check(
		core.grid.total_tile_count() == initial_count + 1,
		"placed tile totals include upper layers"
	)
	check(not core.grid.is_walkable(coord), "an unconnected raised column is not used as a ground route")
	check(
		core.grid.has_walkable_top_surface(coord),
		"a raised column still exposes its top to physical jump traversal"
	)
	check(
		core.grid.remove_tile_at(coord, 0) == null,
		"a supporting block cannot be removed from beneath an upper block"
	)

	check(
		core.place_tile_from_stock(coord, "tile_grass", 0, 2),
		"flat upper blocks can form a taller contiguous column"
	)
	check(core.grid.top_elevation(coord) == 2, "column reports its highest occupied level")
	check(
		not core.grid.can_place_structure_at(coord, 0, "struct_lantern")
		and core.grid.free_socket(coord, "decor", 0) < 0
		and core.grid.add_structure(coord, "struct_lantern", 1, 0, 0) == null,
		"covered lower elevations cannot receive objects through any grid API"
	)
	check(
		core.grid.can_place_structure_at(coord, 2, "struct_pot"),
		"small decorations can sit on an elevated block"
	)
	var pot_socket := core.grid.free_socket(coord, "decor", 2)
	var elevated_pot := core.grid.add_structure(coord, "struct_pot", pot_socket, 0, 2)
	check(elevated_pot != null, "elevated decoration receives independent saved state")
	check(
		not core.grid.can_place_tile_at(coord, 3, "tile_grass"),
		"a decorated support rejects a land block that would overlap it"
	)
	check(
		core.registries.tile("tile_grass_flower").stackable
		and core.registries.tile("tile_grass_flower").supports_tiles,
		"ordinary flat tile definitions inherit modular stacking defaults"
	)
	var moved_column := core.grid.detach_tile_stack(coord, 1)
	var column_destination := Vector2i(2, 1)
	core.grid.place_tile(column_destination, "tile_path")
	check(
		moved_column.size() == 2
		and core.grid.restore_tile_stack(column_destination, 1, moved_column),
		"a selected middle tile moves itself and every upper layer atomically"
	)
	check(
		core.grid.top_elevation(column_destination) == 2
		and core.grid.cell_at(column_destination, 2).structures.has(elevated_pot),
		"an atomic tile move retains the complete supported object hierarchy"
	)
	moved_column = core.grid.detach_tile_stack(column_destination, 1)
	check(
		core.grid.restore_tile_stack(coord, 1, moved_column),
		"an atomic tile column can return to its original support"
	)
	core.grid.remove_tile(column_destination)

	var stairs := Defs.TileDefinition.from_dict({
		"id": "tile_test_stairs",
		"name": "Test Stairs",
		"asset_id": "tile_path",
		"stackable": true,
		"supports_tiles": false,
		"supports_decor": true,
		"surface_kind": "stairs",
		"decor_sockets": 2,
	})
	var penny_pig := Defs.StructureDefinition.from_dict({
		"id": "struct_test_penny_pig",
		"name": "Penny Pig",
		"asset_id": "prop_pot",
		"socket_type": "decor",
		"allow_elevated": true,
	})
	core.registries.tiles[stairs.id] = stairs
	core.registries.structures[penny_pig.id] = penny_pig
	var stair_coord := Vector2i(2, 0)
	core.grid.place_tile(stair_coord, stairs.id)
	check(
		not core.grid.can_place_tile_at(stair_coord, 1, "tile_grass"),
		"stairs explicitly reject a tile stacked on their uneven top"
	)
	check(
		core.grid.can_place_structure_at(stair_coord, 0, penny_pig.id),
		"stairs still accept compatible decor such as the penny pig"
	)

	core.registries.tiles.erase(stairs.id)
	core.registries.structures.erase(penny_pig.id)
	core.grid.remove_tile(stair_coord)
	check(core.save(), "elevated world state saves")
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	check(restored.load_game(), "elevated world state loads")
	check(
		restored.grid.top_elevation(coord) == 2
		and restored.grid.cell_at(coord, 2).structures.size() == 1,
		"upper blocks and their decorations round-trip together"
	)


func _test_connectivity_and_relocation() -> void:
	var core := fresh_core()
	core.stock.add_tile("tile_grass")
	core.stock.add_tile("tile_grass")
	core.place_tile_from_stock(Vector2i(2, 0), "tile_grass", 0)
	core.place_tile_from_stock(Vector2i(3, 0), "tile_grass", 0)
	check(not core.grid.connected_without(Vector2i(2, 0), core.grid.home_cell), "removing a bridge tile is detected as a split")
	check(core.grid.connected_without(Vector2i(3, 0), core.grid.home_cell), "removing a leaf tile keeps the world whole")
	var refuge := core.grid.nearest_walkable(Vector2i(3, 0), Vector2i(3, 0))
	check(refuge != Vector2i(3, 0) and core.grid.is_walkable(refuge), "safe relocation finds a nearby walkable cell")


func _test_sockets_and_overlap_prevention() -> void:
	var core := fresh_core()
	var coord := Vector2i(0, 0)
	var def := core.grid.tile_def(coord)
	var placed := 0
	while core.grid.free_socket(coord, "decor") >= 0:
		core.grid.add_structure(coord, "struct_pot", core.grid.free_socket(coord, "decor"))
		placed += 1
	check(
		placed == 1,
		"one direct object occupies the tile even when its visual definition exposes %d sockets"
		% def.decor_sockets
	)
	check(core.grid.free_socket(coord, "decor") == -1, "a second direct object cannot use the tile")
	var major := core.grid.free_socket(coord, "structure")
	check(major == -1, "major and decoration types share the one tile-root position")
	check(
		core.grid.add_structure(coord, "struct_campfire", 0) == null,
		"a major structure cannot overlap a direct decoration"
	)
	var pot: WorldGrid.StructureState = core.grid.cell(coord).structures[0]
	check(
		core.grid.structure_local_transform(pot.instance_id).origin.is_equal_approx(Vector3.ZERO),
		"direct objects use the exact center of their tile"
	)

	var starter_dock := core.grid.cell(Vector2i(0, -1)).structures[0]
	check(
		starter_dock.structure_id == "struct_dock"
		and starter_dock.rotation == 2,
		"the opening dock is a movable world object on the middle water tile"
	)
	check(
		core.registries.structure(starter_dock.structure_id).collision_profile
		== "walkable_surface",
		"the opening dock keeps its walkable collision contract"
	)
	check(
		not core.grid.is_walkable(Vector2i(0, -1))
		and core.grid.is_traversable(Vector2i(0, -1)),
		"a dock makes its water cell traversable without reclassifying it as land"
	)
	var water := Vector2i(1, -1)
	check(
		core.grid.can_place_structure_at(water, 0, "struct_dock"),
		"the dock accepts the water surface type"
	)
	check(
		not core.grid.can_place_structure_at(coord, 0, "struct_dock"),
		"the dock rejects solid terrain"
	)
	check(
		not core.grid.can_place_structure_at(water, 0, "struct_bench"),
		"ordinary furniture rejects water surfaces"
	)
	var dock := core.grid.add_structure(water, "struct_dock", 0)
	check(
		dock != null
		and core.grid.structure_local_transform(dock.instance_id).origin.is_equal_approx(Vector3.ZERO),
		"water-only docks are centered on their water tile"
	)
	check(
		core.grid.is_traversable(water),
		"a newly placed dock makes its destination water cell traversable"
	)
	core.grid.remove_structure(water, dock.instance_id)
	check(
		not core.grid.is_traversable(water),
		"removing a dock removes the temporary traversal surface from that water cell"
	)


func _test_object_support_graph() -> void:
	var core := fresh_core()
	var first := Vector2i(7, 7)
	var second := Vector2i(8, 7)
	core.grid.place_tile(first, "tile_grass")
	core.grid.place_tile(second, "tile_grass")
	var expected_stackable := {
		"struct_chest": true,
		"struct_planter": true,
		"struct_pot": true,
		"struct_watering_can": true,
		"struct_milk_churn": true,
	}
	var expected_supports := {
		"struct_bench": {
			"seat_left": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
			"seat_right": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
		},
		"struct_stool": {
			"top": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
		},
		"struct_table": {
			"top_center": [
				"struct_chest",
				"struct_planter",
				"struct_pot",
				"struct_watering_can",
				"struct_milk_churn",
			],
		},
		"struct_chest": {
			"lid": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
		},
		"struct_box": {
			"top": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
		},
		"struct_stone_bench": {
			"seat_left": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
			"seat_right": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
		},
		"struct_barrel": {
			"top": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
		},
		"struct_crate": {
			"top": ["struct_pot", "struct_watering_can", "struct_milk_churn"],
		},
	}
	for definition: Defs.StructureDefinition in core.registries.structures.values():
		check(
			definition.placement_policy_explicit,
			"every structure explicitly declares its scalable support policy: " + definition.id
		)
		check(
			definition.can_be_stacked == expected_stackable.has(definition.id),
			"catalog classifies whether %s can sit on another object" % definition.id
		)
		var expected_slots: Dictionary = expected_supports.get(definition.id, {})
		check(
			definition.support_slots.size() == expected_slots.size(),
			"catalog classifies every support surface exposed by %s" % definition.id
		)
		for slot: Defs.SupportSlotDefinition in definition.support_slots:
			check(
				expected_slots.has(slot.id),
				"%s exposes only its audited support slots" % definition.id
			)
			var accepted_ids: Array = expected_slots.get(slot.id, [])
			for candidate: Defs.StructureDefinition in core.registries.structures.values():
				check(
					slot.accepts_definition(candidate) == accepted_ids.has(candidate.id),
					"%s:%s classifies %s consistently"
						% [definition.id, slot.id, candidate.id]
				)

	var table := core.grid.add_structure(first, "struct_table", 1)
	check(table != null, "a table can be rooted directly on a tile")
	check(
		not core.grid.can_place_structure_at(first, 0, "struct_pot"),
		"one direct object per tile elevation remains enforced"
	)
	var chest := core.grid.add_structure_on(
		table.instance_id,
		"struct_chest",
		"top_center"
	)
	check(
		chest != null
		and chest.parent_instance_id == table.instance_id
		and chest.support_slot_id == "top_center",
		"a storage chest fits the round table's audited tabletop surface"
	)
	check(
		core.grid.add_structure_on(table.instance_id, "struct_planter", "top_center") == null,
		"a named support slot accepts exactly one child"
	)
	var pot := core.grid.add_structure_on(chest.instance_id, "struct_pot", "lid")
	check(
		pot != null and pot.parent_instance_id == chest.instance_id,
		"the chest lid accepts a genuinely small surface item"
	)
	check(
		core.grid.add_structure_on(pot.instance_id, "struct_chest") == null,
		"a terminal object cannot hold another item"
	)
	check(
		not core.grid.can_place_tile_at(first, 1, "tile_grass"),
		"a land tile can never be placed on an object graph"
	)
	var table_transform := core.grid.structure_local_transform(table.instance_id)
	var chest_transform := core.grid.structure_local_transform(chest.instance_id)
	var pot_transform := core.grid.structure_local_transform(pot.instance_id)
	check(
		chest_transform.origin.y > table_transform.origin.y
		and pot_transform.origin.y > chest_transform.origin.y,
		"support transforms compose upward without floating gaps from tile elevation"
	)

	var detached := core.grid.detach_structure_stack(table.instance_id)
	check(
		detached.size() == 3
		and core.grid.find_structure(table.instance_id).is_empty(),
		"moving a supporter detaches its complete descendant stack atomically"
	)
	check(
		core.grid.restore_structure_stack(second, 0, detached, 0, "", 1, 1),
		"a detached object stack restores intact at a new tile root"
	)
	check(
		core.grid.find_structure(chest.instance_id)["structure"].parent_instance_id
			== table.instance_id,
		"moving a base preserves every internal support edge"
	)

	var snapshot := core.grid.to_save_dict()
	var restored_grid := WorldGrid.new(core.registries)
	restored_grid.from_save_dict(snapshot)
	var restored_chest := restored_grid.find_structure(chest.instance_id)
	var restored_pot := restored_grid.find_structure(pot.instance_id)
	check(
		not restored_chest.is_empty()
		and restored_chest["structure"].parent_instance_id == table.instance_id
		and restored_chest["structure"].support_slot_id == "top_center"
		and restored_pot["structure"].parent_instance_id == chest.instance_id,
		"support graph ids and named slots round-trip through save data"
	)


func _test_anchor_cycle_and_regen() -> void:
	var core := fresh_core()
	core.grid.place_tile(Vector2i(2, 0), "tile_grass", 0)
	var tree := core.grid.add_structure(Vector2i(2, 0), "struct_pine", 1)
	var anchor := core.registries.anchor("grove_anchor")
	check(tree != null, "a tree can be placed independently on ordinary terrain")
	tree.anchor_actions_done = anchor.cycle_actions
	tree.anchor_resting = true
	tree.anchor_regen_left = 2.0
	core.track_resting_structure(tree.instance_id)
	core.tick(1.0)
	check(tree.anchor_resting, "tree still resting mid-regen")
	var restored_grid := WorldGrid.new(core.registries)
	restored_grid.from_save_dict(core.grid.to_save_dict())
	var restored_tree: WorldGrid.StructureState = restored_grid.find_structure(
		tree.instance_id
	).get("structure")
	check(
		restored_tree != null
		and restored_tree.anchor_resting
		and restored_tree.anchor_actions_done == anchor.cycle_actions
		and is_equal_approx(restored_tree.anchor_regen_left, 1.0),
		"tree resource state round-trips on the movable object instance"
	)
	core.tick(1.5)
	check(
		not tree.anchor_resting and tree.anchor_actions_done == 0,
		"tree regenerates and resets independently from its tile"
	)


func _test_crafting_transactions() -> void:
	var core := fresh_core()
	core.registries.features["material_crafting_enabled"] = true
	check(not core.crafting.craft("recipe_bench"), "crafting without milestone/materials fails")
	core.progression.milestones.claimed["ms_fishing_settled_in"] = true   # bench milestone
	check(not core.crafting.craft("recipe_bench"), "crafting without materials fails")
	var inv_before := core.inventory.count("softwood")
	var benches_before := core.stock.structure_count("struct_bench")
	core.inventory.grant("softwood", 2, false, true)
	core.inventory.grant("reeds", 2, false, true)
	check(core.crafting.craft("recipe_bench"), "crafting with everything succeeds")
	check(core.inventory.count("softwood") == inv_before and core.inventory.count("reeds") == 0, "materials consumed atomically")
	check(core.stock.structure_count("struct_bench") == benches_before + 1, "crafted structure lands in stock")
	core.inventory.grant("hardwood", 2, false, true)
	core.inventory.grant("old_metal", 2, false, true)
	core.inventory.grant("resin", 1, false, true)
	core.progression.milestones.claimed["ms_wood_master_tender"] = true   # fine axe milestone
	check(core.crafting.craft("recipe_axe_fine"), "tool recipe crafts")
	check(core.equipment.owns("tool_axe_fine"), "crafted tool is owned equipment")
	check(core.equipment.best_tool("axe").id == "tool_axe_fine", "best tool resolves to the higher tier")


func _test_equipment() -> void:
	var core := fresh_core()
	check(
		core.equipment.owns("cosmetic_cowboy_vest"),
		"starter wardrobe grants the cowboy vest"
	)
	check(
		core.equipment.equipped_in("body").id == "cosmetic_cowboy_vest",
		"cowboy vest starts equipped in the body slot"
	)
	var vest_definition := core.registries.item("cosmetic_cowboy_vest")
	check(
		vest_definition != null
		and vest_definition.asset_id == "cowboy_vest",
		"cowboy vest item resolves the production GLB asset id"
	)
	var vest_scene := load(
		"res://assets/3d/reworked/cowboy_vest.glb"
	) as PackedScene
	check(vest_scene != null, "cowboy vest GLB imports as a PackedScene")
	if vest_scene != null:
		var vest_root := vest_scene.instantiate()
		var vest_mesh := vest_root.find_child(
			"CowboyVest", true, false
		) as MeshInstance3D
		var exposed_body := vest_root.find_child(
			"BodyExposedForCowboyVest", true, false
		) as MeshInstance3D
		check(
			vest_root.find_children("*", "Skeleton3D", true, false).size() == 1,
			"cowboy vest bundle exports one helper skeleton"
		)
		check(
			vest_mesh != null and vest_mesh.skin != null,
			"cowboy vest mesh keeps its skin after GLB import"
		)
		check(
			exposed_body != null and exposed_body.skin != null,
			"covered-body replacement keeps its skin after GLB import"
		)
		vest_root.free()
	core.equipment.equipped.erase("body")
	core.equipment.owned.erase("cosmetic_cowboy_vest")
	core.equipment.appearance_unlocked.erase("cosmetic_cowboy_vest")
	check(core.save(), "pre-wardrobe development save fixture writes")
	var migrated_core := GameCore.new()
	check(migrated_core.setup(), "migration core loads content")
	migrated_core.save_manager.save_path = "user://test_save.json"
	migrated_core.save_manager.backup_path = "user://test_save.json.backup"
	check(migrated_core.load_game(), "pre-wardrobe development save loads")
	check(
		migrated_core.equipment.owns("cosmetic_cowboy_vest")
		and (
			migrated_core.equipment.equipped_in("body").id
			== "cosmetic_cowboy_vest"
		),
		"existing saves gain and equip the vest when their body slot is empty"
	)
	core.equipment.acquire("cape_watchpost")
	check(core.equipment.equip("cape_watchpost"), "owned equipment can be equipped")
	check(core.equipment.equipped_in("back").id == "cape_watchpost", "slot query returns equipped item")
	check(core.equipment.appearance_unlocked.has("cape_watchpost"), "appearance unlock recorded separately from ownership")
	check(core.combat.defense() >= 1, "equipment stats aggregate")
	check(not core.equipment.equip("weapon_thorn_sword"), "unowned equipment cannot be equipped")


func _make_revealed_landmark(core: GameCore) -> LandmarkManager.LandmarkState:
	# Grow east until the watchpost spawns, then bridge to it.
	for i in range(2, 12):
		core.stock.add_tile("tile_grass")
		core.place_tile_from_stock(Vector2i(i, 0), "tile_grass", 0)
		if not core.landmarks.active.is_empty():
			break
	if core.landmarks.active.is_empty():
		return null
	var state: LandmarkManager.LandmarkState = core.landmarks.active[0]
	var guard := 0
	while state.phase == LandmarkManager.PHASE_SILHOUETTE and guard < 24:
		guard += 1
		var target := core.landmarks.footprint_cells(state)[0]
		var frontier := _frontier_toward(core, target)
		if frontier == Vector2i(9999, 9999):
			break
		core.stock.add_tile("tile_grass")
		core.place_tile_from_stock(frontier, "tile_grass", 0)
	return state


func _frontier_toward(core: GameCore, target: Vector2i) -> Vector2i:
	var best := Vector2i(9999, 9999)
	var best_distance := 999999
	for coord: Vector2i in core.grid.cells:
		for offset: Vector2i in WorldGrid.NEIGHBORS:
			var candidate: Vector2i = coord + offset
			if core.grid.has_cell(candidate) or not core.grid.can_place_tile(candidate):
				continue
			var distance := absi(candidate.x - target.x) + absi(candidate.y - target.y)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best


func _test_landmark_lifecycle() -> void:
	var core := fresh_core()
	core.registries.features["hostile_landmarks_enabled"] = true
	var state := _make_revealed_landmark(core)
	check(state != null, "a horizon opportunity spawns as the world grows")
	if state == null:
		return
	var def := core.registries.landmark(state.landmark_id)
	for cell in core.landmarks.footprint_cells(state):
		check(not core.grid.has_cell(cell) or state.phase != LandmarkManager.PHASE_SILHOUETTE, "silhouette never overlaps placed land")
	check(state.phase == LandmarkManager.PHASE_REVEALED, "connecting land reveals the landmark")
	check(core.grid.has_cell(core.landmarks.footprint_cells(state)[0]), "revealed footprint becomes real ground")
	check(state.enemies_alive.size() == 3, "enemy roster spawned from definition")


func _test_guardian_idempotency() -> void:
	var core := fresh_core()
	core.registries.features["hostile_landmarks_enabled"] = true
	var state := _make_revealed_landmark(core)
	if state == null:
		failures.append("guardian test could not build landmark")
		return
	var def := core.registries.landmark(state.landmark_id)
	var grants_a := core.landmarks.on_enemy_defeated(state, def.guardian_id + ":g", true)
	check(core.equipment.owns(def.guardian_reward), "guardian reward granted")
	check(state.phase == LandmarkManager.PHASE_RECLAIMED, "guardian defeat reclaims the landmark")
	var grants_b := core.landmarks.on_enemy_defeated(state, def.guardian_id + ":g", true)
	check(grants_b.is_empty(), "guardian reward is idempotent — no double grant")


func _test_pack_and_salvage() -> void:
	var core := fresh_core()
	core.registries.features["hostile_landmarks_enabled"] = true
	var state := _make_revealed_landmark(core)
	if state == null:
		failures.append("pack test could not build landmark")
		return
	var def := core.registries.landmark(state.landmark_id)
	core.landmarks.on_enemy_defeated(state, def.guardian_id + ":g", true)
	var cells := core.landmarks.footprint_cells(state)
	core.landmarks.resolve(state, "packed")
	check(core.stock.landmark_deeds.has(state.landmark_id), "packing yields a deed")
	check(not core.grid.has_cell(cells[0]), "packed landmark releases its cells")
	# salvage path on a fresh core
	var core2 := fresh_core(999)
	core2.registries.features["hostile_landmarks_enabled"] = true
	var state2 := _make_revealed_landmark(core2)
	if state2 != null:
		var def2 := core2.registries.landmark(state2.landmark_id)
		core2.landmarks.on_enemy_defeated(state2, def2.guardian_id + ":g", true)
		var before := core2.inventory.count("carved_stone")
		core2.landmarks.resolve(state2, "salvaged")
		check(core2.inventory.count("carved_stone") > before, "salvage grants materials")


func _test_deed_replacement() -> void:
	var core := fresh_core()
	core.registries.features["hostile_landmarks_enabled"] = true
	var state := _make_revealed_landmark(core)
	if state == null:
		return
	var def := core.registries.landmark(state.landmark_id)
	core.landmarks.on_enemy_defeated(state, def.guardian_id + ":g", true)
	core.landmarks.resolve(state, "packed")
	var placed_ok := false
	for y in range(-8, 9):
		for x in range(-8, 9):
			if core.landmarks.place_deed(state.landmark_id, Vector2i(x, y)):
				placed_ok = true
				break
		if placed_ok:
			break
	check(placed_ok, "deed re-places beside the world")
	var placed := core.landmarks.state_for(state.landmark_id)
	check(placed != null and placed.phase == LandmarkManager.PHASE_RECLAIMED, "re-placed landmark is peaceful")


func _test_rework_save_round_trip() -> void:
	var core := fresh_core(31415)
	core.progression.inspiration.add("domain_waterside", 20.0)
	core.progression.on_activity_action("fishing")
	core.stock.add_tile("tile_grove_birch")
	core.profile.position = Vector3(0.234, 0.0, 0.345)   # continuous, between tile centers
	core.profile.facing = 1.11
	core.view_state = {"yaw": 135.0, "distance": 55.0}
	core.visual_state = {
		"weather": "snow",
		"time_of_day": "night",
		"background": "dusk",
		"particle_quality": "medium",
	}
	core.arrivals.trigger_arrival()
	core.arrivals.mark_delivery_ready(core.arrivals.current_payload)
	var rng_next := core.rng.randi_range("probe", 0, 999999)
	check(core.save(), "save writes")
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	check(restored.load_game(), "save loads")
	check(
		is_equal_approx(
			restored.progression.inspiration.meter_progress("domain_waterside")["current"],
			core.progression.inspiration.meter_progress("domain_waterside")["current"]
		),
		"inspiration meters round-trip"
	)
	check(
		restored.progression.actions_done("fishing") == core.progression.actions_done("fishing"),
		"lifetime activity actions round-trip"
	)
	check(restored.inventory.counts.is_empty(), "active material inventory stays empty")
	check(restored.stock.tile_count("tile_grove_birch") == 1, "stock round-trips")
	check(restored.grid.cells.size() == core.grid.cells.size(), "grid round-trips")
	check(restored.profile.position.is_equal_approx(Vector3(0.234, 0.0, 0.345)), "exact float player position round-trips")
	check(absf(restored.profile.facing - 1.11) < 0.0001, "facing round-trips")
	check(restored.view_state == core.view_state, "camera orbit and distance round-trip")
	check(restored.visual_state == core.visual_state, "weather, time, background, and particle quality round-trip")
	check(restored.arrivals.has_waiting_package(), "unopened ferry gift survives restart")
	check(restored.arrivals.current_payload.gift_kind == "vision", "delivery payload survives restart")
	# RNG stream continues identically after reload (probe stream was consumed once pre-save)
	var loaded_next := restored.rng.randi_range("probe", 0, 999999)
	var fresh_again := GameCore.new()
	fresh_again.setup("res://data", 31415)
	fresh_again.rng.randi_range("probe", 0, 999999)
	check(loaded_next == fresh_again.rng.randi_range("probe", 0, 999999), "rng stream state round-trips")


func _test_camping_feature_contract() -> void:
	var core := fresh_core(451)
	var tent := core.grid.add_structure(Vector2i(-1, 0), "struct_high_tent", 0)
	check(tent != null, "High Tent places through the generic structure API")
	if tent == null:
		return
	var definition = core.camping.definitions.structure("struct_high_tent")
	check(definition != null, "camping module discovers the High Tent through capabilities")
	check(definition.shelter.capacity == 2, "shelter capacity comes from definition data")
	check(definition.sleep.comfort == 6, "sleep comfort comes from definition data")
	check(definition.storage.slots == 6, "camping storage capacity comes from definition data")
	var options: Array = core.camping.interactions.options_for("keeper", tent.instance_id)
	check(options.size() == 1 and options[0].id == "sleep", "sleep interaction is capability-driven")
	check(
		options[0].feature_id == "camping" and options[0].disabled_reason == "",
		"feature interaction uses the shared presentation-neutral option contract"
	)
	check(core.camping.interactions.execute("sleep", "keeper", tent.instance_id), "keeper can occupy the tent")
	check(core.camping.shelters.damage(tent.instance_id, 17.5), "placed shelter owns mutable durability")
	var state = core.camping.shelters.state_for(tent.instance_id)
	check(is_equal_approx(state.durability, 82.5), "durability mutates independently of static definition")
	check(state.occupants == ["keeper"], "shelter occupants are instance state")
	check(core.save(), "camping feature state saves")
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	check(restored.load_game(), "camping feature state loads")
	var restored_state = restored.camping.shelters.state_for(tent.instance_id, false)
	check(restored_state != null, "saved tent state reconnects by stable instance id")
	if restored_state != null:
		check(is_equal_approx(restored_state.durability, 82.5), "tent durability round-trips")
		check(restored_state.occupants == ["keeper"], "tent occupants round-trip")
	var stored_stack := restored.grid.detach_structure_stack(tent.instance_id)
	check(stored_stack.size() == 1, "stateful tent detaches as one inventory piece")
	if not stored_stack.is_empty():
		restored.stock.add_structure_instance(stored_stack[0])
	check(
		restored.stock.has_structure_instance(tent.instance_id),
		"stateful stock keeps the tent's stable instance id"
	)
	check(restored.save(), "stored stateful tent saves")
	var stored_reload := GameCore.new()
	stored_reload.setup("res://data", 1)
	stored_reload.save_manager.save_path = core.save_manager.save_path
	stored_reload.save_manager.backup_path = core.save_manager.backup_path
	check(stored_reload.load_game(), "stored stateful tent loads")
	check(
		stored_reload.stock.has_structure_instance(tent.instance_id),
		"stored tent identity survives restart"
	)
	var token := stored_reload.stock.take_structure_token(
		"struct_high_tent", tent.instance_id
	)
	var stored_state: Dictionary = token.get("state", {})
	var returned_tent := WorldGrid.StructureState.from_dict(stored_state)
	var returned_stack: Array[WorldGrid.StructureState] = [returned_tent]
	check(
		stored_reload.grid.restore_structure_stack(
			Vector2i(1, 1), 0, returned_stack, 0, "", 0, 0
		),
		"stored tent places again through the generic support API"
	)
	var returned_state = stored_reload.camping.shelters.state_for(tent.instance_id, false)
	check(returned_state != null, "re-placed tent reconnects to its feature state")
	if returned_state != null:
		check(
			is_equal_approx(returned_state.durability, 82.5),
			"store and re-place does not heal or replace the tent"
		)


func _test_fire_interaction_contract() -> void:
	var core := fresh_core(907)
	var coord := Vector2i(8, 8)
	core.grid.place_tile(coord, "tile_grass")
	var campfire := core.grid.add_structure(
		coord,
		"struct_campfire",
		0
	)
	check(campfire != null, "campfire places through the generic structure API")
	if campfire == null:
		return
	check(
		not core.fire.is_burning(campfire.instance_id),
		"new fire-enabled structures begin unlit"
	)
	var option = core.interactions.primary_for(
		"keeper",
		campfire.instance_id
	)
	check(
		option != null
		and option.feature_id == "fire"
		and option.label == "Light fire",
		"shared interaction registry discovers the unlit campfire"
	)
	var transitions: Array[bool] = []
	core.fire.burning_changed.connect(func(_instance_id: int, active: bool):
		transitions.append(active)
	)
	check(
		core.interactions.execute(option, "keeper"),
		"shared interaction execution lights the selected campfire"
	)
	check(
		core.fire.is_burning(campfire.instance_id)
		and transitions == [true],
		"lighting commits state and emits one presentation event"
	)
	option = core.interactions.primary_for("keeper", campfire.instance_id)
	check(
		option != null and option.label == "Extinguish fire",
		"the same interaction becomes Extinguish while burning"
	)
	check(
		core.interactions.execute(option, "keeper")
		and not core.fire.is_burning(campfire.instance_id)
		and transitions == [true, false],
		"clicking the burning fire toggles it off"
	)
	check(
		core.fire.set_burning(campfire.instance_id, true),
		"fire state can be restored explicitly"
	)
	var encoded := campfire.to_dict()
	check(
		bool((encoded.get("runtime", {}) as Dictionary).get("fire_lit", false)),
		"burning state is stored on the stable structure instance"
	)
	check(core.save(), "burning structure state saves")
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	check(restored.load_game(), "burning structure state loads")
	check(
		restored.fire.is_burning(campfire.instance_id),
		"campfire remains lit after a save round trip"
	)
	var tent := restored.grid.add_structure(
		Vector2i(-1, 0),
		"struct_high_tent",
		0
	)
	if tent != null:
		var camping_option = restored.interactions.primary_for(
			"keeper",
			tent.instance_id
		)
		check(
			camping_option != null
			and camping_option.feature_id == "camping",
			"the shared registry also retains existing camping interactions"
		)


func _test_current_save_policy() -> void:
	var core := fresh_core(7001)
	check(core.save(), "current-format development save writes")
	var current := core.save_manager.read()
	check(
		int(current.get("format", 0)) == SaveManager.CURRENT_FORMAT,
		"save records the single current pre-release format"
	)
	var stale := current.duplicate(true)
	stale["format"] = 0
	var stale_path := "user://stale_format_test.json"
	var file := FileAccess.open(stale_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(stale))
	file.close()
	var reader := SaveManager.new(core.registries)
	reader.save_path = stale_path
	reader.backup_path = stale_path + ".backup"
	check(
		reader.read().is_empty(),
		"stale pre-release format is rejected instead of migrated"
	)
	DirAccess.remove_absolute(stale_path)
	var retired := current.duplicate(true)
	retired["stock"] = {
		"tiles": {"retired_tile": 1},
		"structures": {},
		"structure_instances": [],
		"deeds": [],
	}
	var errors: PackedStringArray = CurrentSaveValidatorScript.validate(
		retired, core.registries
	)
	check(
		not errors.is_empty(),
		"retired content is reported before any world state mutates"
	)
	var retired_reference_cases := [
		{
			"label": "inspiration state",
			"mutate": func(save: Dictionary) -> void:
				save["progression"]["inspiration"]["meters"]["retired_domain"] = 5,
		},
		{
			"label": "vision state",
			"mutate": func(save: Dictionary) -> void:
				save["progression"]["visions"]["pending"] = [
					{"kind": "tile", "id": "retired_tile"}
				],
		},
		{
			"label": "milestone state",
			"mutate": func(save: Dictionary) -> void:
				save["progression"]["milestones"]["claimed"] = ["retired_milestone"],
		},
		{
			"label": "equipment state",
			"mutate": func(save: Dictionary) -> void:
				save["equipment"]["owned"].append("retired_item"),
		},
		{
			"label": "landmark state",
			"mutate": func(save: Dictionary) -> void:
				save["landmarks"]["active"].append({
					"id": "retired_landmark",
					"x": 0,
					"y": 0,
					"phase": "silhouette",
					"enemies": [],
				}),
		},
		{
			"label": "collection state",
			"mutate": func(save: Dictionary) -> void:
				save["collection"]["entries"]["gear/retired_item"] = {"count": 1},
		},
		{
			"label": "feature instance state",
			"mutate": func(save: Dictionary) -> void:
				save["features"]["camping"]["shelters"].append({
					"iid": 999999,
					"durability": 1.0,
					"occupants": [],
					"construction_progress": 1.0,
				}),
		},
	]
	for case: Dictionary in retired_reference_cases:
		var invalid := current.duplicate(true)
		(case["mutate"] as Callable).call(invalid)
		check(
			not CurrentSaveValidatorScript.validate(
				invalid, core.registries
			).is_empty(),
			"current-save validation rejects retired %s before hydration"
			% case["label"]
		)


func _test_interrupted_reveal_recovery() -> void:
	var core := fresh_core()
	core.progression.inspiration.banked.append("domain_grove")
	core.progression.visions.claim_from_well(core.progression.inspiration)
	check(core.progression.visions.has_pending(), "reveal pending")
	core.save()   # player closes the game mid-reveal
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	restored.load_game()
	check(restored.progression.visions.has_pending(), "pending reveal survives restart")
	check(restored.progression.visions.pending_options.size() == 3, "all three options intact")
	var result := restored.progression.visions.choose(1)
	var entry: Dictionary = result.get("entry", {})
	check(
		not entry.is_empty() and _entry_stock_count(restored, entry) == 1,
		"resumed reveal completes; nothing lost or duplicated"
	)


func _test_progression_v1_migration() -> void:
	var core := fresh_core()
	var v1_save := {
		"skills": {"xp": {"fishing": 55}, "levels": {"fishing": 3}, "actions": {"fishing": 20}},
		"parcels": {"pending_parcel": "parcel_wild", "pending_options": ["tile_grass", "tile_sand", "tile_snowfield"], "opened": 4, "dup_streak": 1},
		"inventory": {"counts": {"pattern_dust": 5, "parcel_wild": 1, "softwood": 2}},
		"arrivals": {"state": "waiting", "payload": {"parcel_id": "parcel_wild", "delivery_id": 2}},
	}
	var migrated := ProgressionModule.migrate_save_payload(v1_save)
	check(not migrated.has("skills") and not migrated.has("parcels"), "v1 keys are absorbed")
	var progression: Dictionary = migrated["progression"]
	var archived: Dictionary = progression["archived_v1"]
	check(int(archived["skills"]["levels"]["fishing"]) == 3, "v1 levels are preserved verbatim for a future revival")
	check(int(archived["inventory_counts"]["pattern_dust"]) == 5, "retired currencies are preserved in the archive")
	check(
		not migrated["inventory"]["counts"].has("pattern_dust")
		and not migrated["inventory"]["counts"].has("parcel_wild")
		and int(migrated["inventory"]["counts"]["softwood"]) == 2,
		"retired items leave the live inventory; real materials stay"
	)
	var pending: Array = progression["visions"]["pending"]
	check(pending.size() == 3 and String(pending[0]["kind"]) == "tile", "a pending v1 reveal becomes a pending Vision")
	check(int(progression["activity_actions"]["fishing"]) == 20, "lifetime actions continue live")
	check(String(migrated["arrivals"]["state"]) == "idle", "a mid-delivery ferry re-schedules cleanly")
	var progression_errors := PackedStringArray()
	CurrentSaveValidatorScript._validate_progression(progression_errors, progression, core.registries)
	check(progression_errors.is_empty(), "migrated progression state passes strict validation: " + ", ".join(progression_errors))
	# Idempotence: migrating an already-migrated payload changes nothing.
	check(str(ProgressionModule.migrate_save_payload(migrated)) == str(migrated), "migration is idempotent")


func _test_player_defeat_safety() -> void:
	var core := fresh_core()
	core.inventory.grant("softwood", 3, false, true)
	var defeated := [false]   # lambdas capture locals by value; use a container
	core.combat.player_defeated.connect(func(): defeated[0] = true)
	var guard := 0
	while not defeated[0] and guard < 10:
		guard += 1
		core.combat.damage_player(2)
	check(defeated[0], "defeat fires")
	check(core.combat.health == core.combat.max_health, "defeat restores full health (no corpse run)")
	check(core.inventory.count("softwood") == 3, "nothing is lost on defeat")
