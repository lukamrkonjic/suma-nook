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
const SoftTerrainDeformationScript := preload(
	"res://scripts/visuals/soft_terrain_deformation.gd"
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
	_test_soft_terrain_contract()
	_test_content_catalog_architecture()
	_test_build_library_categories()
	_test_content_assets()
	_test_tile_slot_fill()
	_test_catalog_expansion()
	_test_gg_render_contract()
	_test_game_preferences()
	_test_starting_world()
	_test_authored_onboarding_flow()
	_test_maxed_debug_world_spawn()
	_test_local_biome_discovery()
	_test_uncapped_void_discovery()
	_test_hobby_journal_and_direct_rewards()
	_test_out_of_scope_systems_disabled()
	_test_arrival_and_gift_loop()
	_test_arrival_queue_invariants()
	_test_practice_milestones()
	_test_journal_milestones()
	_test_deterministic_rng()
	_test_void_discovery_and_honest_duplicates()
	_test_void_duplicate_exchange()
	_test_biome_pool_resolution()
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


func _test_soft_terrain_contract() -> void:
	var core := fresh_core()
	var sand := core.registries.tile("tile_sand")
	var snow := core.registries.tile("tile_snowfield")
	check(
		sand.soft_surface_profile == "sand"
			and is_equal_approx(sand.walk_surface_height, 0.025),
		"sand authors its responsive profile and measured walk plane"
	)
	check(
		snow.soft_surface_profile == "snow"
			and is_equal_approx(snow.walk_surface_height, 0.052),
		"snow authors its responsive profile and measured walk plane"
	)

	var palette := load(
		"res://assets/palettes/gg_material_palette.tres"
	) as CozyPalette
	var materials := MaterialLibrary.new(palette)
	var material_manifest := materials.material_parameter_manifest()
	for material_key in ["sand_top", "snow_top"]:
		var record: Dictionary = material_manifest[material_key]
		check(
			record["family"] == "responsive_soft_terrain"
				and record["imprint_capacity"] == 12
				and String(record["shader_path"]).ends_with(
					"gg_soft_terrain.gdshader"
				),
			"%s uses the bounded responsive terrain shader" % material_key
		)
	check(
		material_manifest["grass"]["family"] == "gg_diorama_surface",
		"ordinary opaque terrain stays on the cheaper diorama shader"
	)

	var assets := AssetLibrary.new(materials)
	var factory := TileVisualFactory.new(assets, core.grid)
	for definition: Defs.TileDefinition in [sand, snow]:
		var holder := Node3D.new()
		factory.add_collision(holder, definition, 0)
		var collisions := holder.find_children(
			"*", "CollisionShape3D", true, false
		)
		var collision := (
			collisions[0] as CollisionShape3D
			if not collisions.is_empty()
			else null
		)
		var box := collision.shape as BoxShape3D if collision != null else null
		check(
			box != null
				and is_equal_approx(
					collision.position.y + box.size.y * 0.5,
					definition.walk_surface_height
				)
				and is_equal_approx(
					collision.position.y - box.size.y * 0.5,
					-core.grid.block_depth
				),
			"%s raises only its walk plane and preserves the exact block bottom"
			% definition.id
		)
		holder.free()

	var deformation := SoftTerrainDeformationScript.new()
	get_root().add_child(deformation)
	var runtime := deformation.runtime_manifest()
	check(
		runtime["architecture"] == "shared_material_fixed_imprint_field"
			and runtime["draw_calls"] == 0
			and runtime["imprint_capacity_per_material"] == 12
			and runtime["live_foot_slots"] == 2
			and runtime["trail_slots"] == 10,
		"soft terrain has fixed shared-material cost and no per-tile nodes"
	)
	deformation.free()


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
		_action_has_key("interact", KEY_F)
		and not _action_has_key("interact", KEY_E)
		and _action_has_mouse_button("interact", MOUSE_BUTTON_LEFT),
		"F is universal world interact while left-click remains available"
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
		) == "F",
		"keyboard and mouse interaction prompts advertise universal F interact"
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
	check(regs.load_all(), "registry loads every current definition")
	check(regs.load_errors.is_empty(), "registry reports no content errors")
	check(
		is_equal_approx(regs.tunef("tile_size", 0.0), 1.35)
		and is_equal_approx(regs.tunef("block_depth", 0.0), 0.5),
		"tile dimensions use the audited footprint and stacking step"
	)
	check(
		regs.tile("tile_open_water").render_profile == "continuous_water"
		and regs.tile("tile_open_water").collision_profile == "none",
		"open water remains a real continuous-water tile"
	)
	check(
		regs.active_tile_ids() == [
			"tile_grass", "tile_sand", "tile_grove_mature",
			"tile_concrete_brutalist", "tile_snowfield"
		],
		"the active land roster remains explicit"
	)
	check(
		regs.discovery_pool("void_unknown") != null
		and regs.discovery_pool("pond_beach") != null
		and regs.discovery_pool("tree_forest") != null,
		"broad and biome-shaped discovery pools load"
	)
	var void_pools := 0
	var local_fallbacks := {}
	for pool: Defs.DiscoveryPoolDefinition in regs.discovery_pools.values():
		if pool.source == "void":
			void_pools += 1
		if pool.source == "local" and pool.fallback:
			local_fallbacks[pool.skill_id] = true
	check(void_pools == 1, "exactly one broad void discovery pool ships")
	check(
		local_fallbacks.has("fishing") and local_fallbacks.has("woodcutting"),
		"every playable local skill has a fallback discovery pool"
	)
	check(
		regs.structure("struct_wishing_well") == null
		and regs.structure("struct_shrine") == null,
		"the wishing well and focus shrine are retired from live content"
	)

func _test_content_catalog_architecture() -> void:
	var regs := GameContentCatalogScript.create()
	check(regs.load_all(), "catalog snapshot loads before atomic reload test")
	var expected_kinds := [
		"skills", "items", "tiles", "structures", "recipes", "loot_tables",
		"discovery_pools", "milestones", "anchors", "capabilities",
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
		not regs.tiles_in_family("winter").is_empty()
		and regs.discovery_pool("tree_winter") != null,
		"winter terrain is obtainable through its biome-shaped discovery pool"
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
		and regs.tunef("camera_default_size", 40.0) == 37.0
		and regs.tunef("camera_wheel_zoom_step", 1.0) == 5.0,
		"camera supports a deep close-up with a one-step wider default composition"
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
	check(
		preferences.fullscreen
		and int(ProjectSettings.get_setting("display/window/size/mode")) == 3
		and bool(ProjectSettings.get_setting(
			"display/window/size/borderless"
		)),
		"fresh installs default to borderless fullscreen"
	)
	preferences.from_dict({
		"fullscreen": true,
		"vsync": false,
		"anti_aliasing": GamePreferences.AA_BALANCED,
		"ssao": false,
		"bloom": false,
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
		and not saved.has("cloud_shadows")
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
	var walkable := 0
	var water := 0
	for coord: Vector2i in core.grid.cells:
		if core.grid.is_walkable(coord):
			walkable += 1
		if core.grid.tile_def(coord).id == "tile_open_water":
			water += 1
		check(not core.grid.cell(coord).movement_locked, "starter land stays movable")
	check(walkable == 9 and water == 0, "the starting island is land surrounded by void")
	check(
		core.stock.structure_count("struct_wishing_well") == 0
		and core.stock.structure_count("struct_shrine") == 0,
		"retired progression structures never enter starter stock"
	)
	check(core.stock.structure_count("struct_pine") == 1, "the starter tree waits in build stock")
	check(core.grid.is_walkable(Vector2i.ZERO), "home cell is safely walkable")
	check(core.equipment.owns("tool_rod_basic"), "starter rod is owned for void fishing")

func _test_authored_onboarding_flow() -> void:
	var core := GameCore.new()
	check(core.setup("res://data", 1717), "onboarding core loads")
	core.save_manager.save_path = "user://test_onboarding_save.json"
	core.save_manager.backup_path = "user://test_onboarding_save.json.backup"
	var profile := PlayerProfile.new()
	profile.display_name = "New Keeper"
	core.begin_onboarding_game(profile)
	check(
		core.grid.cells.is_empty()
		and core.onboarding.stage == OnboardingState.LAND_CHOICE,
		"onboarding begins with a saved land choice"
	)
	check(core.choose_onboarding_land("tile_grove_mature"), "valid first land materializes")
	check(
		core.grid.cells.size() == 9
		and core._placed_tile_count("tile_grove_mature") == 9
		and core._placed_tile_count("tile_open_water") == 0
		and core._is_structure_placed("struct_pine")
		and core.onboarding.stage == OnboardingState.TRY_VOID_FISHING,
		"arrival raises a 3x3 biome island, one tree, and an exposed void edge"
	)
	var first := core.progression.on_void_fishing_catch()
	var first_reward: Dictionary = first["reward"]
	check(
		first_reward.get("id") == "tile_open_water"
		and core.onboarding.stage == OnboardingState.PLACE_DISCOVERY,
		"the first void catch guarantees buildable water and guides its placement"
	)
	core.progression.discovery.acknowledge_next()
	check(
		core.place_tile_from_stock(Vector2i(0, 2), "tile_open_water", 0),
		"discovered water places as an ordinary real tile"
	)
	core.advance_onboarding_after_placement()
	check(
		core.onboarding.stage == OnboardingState.TEND_TREE,
		"placing the void discovery introduces local biome-shaped skilling"
	)
	var local_feedback: Dictionary = {}
	for _index in 4:
		local_feedback = core.progression.on_activity_action(
			"woodcutting", Vector2i(-1, -1), "struct_pine"
		)
	check(
		local_feedback.get("pool_id") == "tree_forest"
		and not (local_feedback.get("reward", {}) as Dictionary).is_empty()
		and core.onboarding.stage == OnboardingState.PLACE_BIOME_DISCOVERY,
		"a full tree cycle uses the surrounding forest pool"
	)
	var local_entry := core.progression.discovery.acknowledge_next()
	if String(local_entry.get("kind", "")) == "tile":
		check(
			core.place_tile_from_stock(
				Vector2i(1, 2), String(local_entry["id"]), 0
			),
			"the biome-shaped tile can be placed"
		)
	else:
		var structure_id := String(local_entry.get("id", ""))
		var definition := core.registries.structure(structure_id)
		var token := core.stock.take_structure_token(structure_id)
		var placed := core.grid.add_structure(
			Vector2i(1, 1),
			structure_id,
			0 if definition.socket_type == "structure" else 1
		)
		check(not token.is_empty() and placed != null, "the biome-shaped structure can be placed")
	core.advance_onboarding_after_placement()
	check(core.onboarding.stage == OnboardingState.COMPLETE, "placing the local discovery completes onboarding")

func _test_local_biome_discovery() -> void:
	var core := fresh_core(404)
	var inventory_before := core.inventory.counts.duplicate()
	var forest := core.progression.discovery.resolve_local_pool(
		"woodcutting", Vector2i.ZERO, "struct_pine"
	)
	check(forest != null and forest.id == "tree_meadow", "a tree on meadow uses the meadow fallback")
	core.grid.place_tile(Vector2i(20, 20), "tile_sand")
	var beach := core.progression.discovery.resolve_local_pool(
		"woodcutting", Vector2i(20, 20), "struct_pine"
	)
	check(beach != null and beach.id == "tree_beach", "sand changes the same tree into the beach pool")
	var feedback := core.progression.on_activity_action(
		"woodcutting", Vector2i(20, 20), "struct_pine"
	)
	check(feedback.get("pool_id") == "tree_beach", "activity feedback names its resolved pool")
	check(core.progression.actions_done("woodcutting") == 1, "lifetime practice is still recorded")
	check(str(core.inventory.counts) == str(inventory_before), "skills add no common material stacks")

func _test_uncapped_void_discovery() -> void:
	var core := fresh_core(405)
	var before := core.stock.total_tiles()
	for _index in 8:
		core.progression.on_void_fishing_catch()
	check(core.progression.discovery.pending.size() == 8, "every successful void catch queues one owned discovery")
	check(core.stock.total_tiles() >= before, "repeated catches keep granting real build pieces")

func _test_hobby_journal_and_direct_rewards() -> void:
	var core := fresh_core(505)
	var fishing := core.registries.skill("fishing")
	core.registries.tuning["fishing_collection_chance"] = 1.0
	var old_entries := fishing.collection_entries.duplicate()
	fishing.collection_entries = ["test_sunfish"] as Array[String]
	var first := core.rewards.resolve_hobby_action(fishing)
	check(first.collection_discovery_id == "test_sunfish", "fishing can still fill the journal")
	check(first.was_new_discovery, "first journal catch is marked new")
	check(not first.has_world_reward(), "the side-journal resolver never bypasses discovery progression")
	var reward := core.progression.on_void_fishing_catch()["reward"] as Dictionary
	check(not reward.is_empty(), "world pieces arrive through the unified discovery system")
	check(_entry_stock_count(core, reward) >= 1, "a discovery immediately enters the Build Bag")
	fishing.collection_entries = old_entries

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
	var payload := requested[0] as LandParcelPayload
	check(payload.gift_kind == "discovery", "ferry payload carries a discovery")
	core.arrivals.mark_delivery_ready(payload)
	var reward := core.arrivals.open_waiting(core.progression)
	check(not reward.is_empty(), "dock gift reveals one broad discovery")
	check(core.arrivals.state == ArrivalScheduler.OPENED, "scheduler pauses until the discovery is acknowledged")
	check(_entry_stock_count(core, reward) >= 1, "ferry discovery is already safe in the Build Bag")
	var acknowledged := core.progression.discovery.acknowledge_next()
	check(acknowledged.get("id") == reward.get("id"), "the queued ferry reward is authoritative")
	core.arrivals.resolve_delivery()
	check(core.arrivals.state == ArrivalScheduler.IDLE, "next timer begins after acknowledgement")

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
	check(not core.arrivals.trigger_arrival(), "an unopened package blocks accumulation")
	core.rewards.resolve_hobby_action(core.registries.skill("fishing"))
	check(core.arrivals.has_waiting_package(), "local hobbies do not disturb a waiting ferry gift")
	check(core.arrivals.deliveries_created == 0, "waiting never creates unattended stacks")

func _test_practice_milestones() -> void:
	var core := fresh_core()
	var reached: Array = []
	core.progression.milestones.milestone_reached.connect(func(id, _rewards): reached.append(id))
	core.progression.activity_actions["fishing"] = 5
	core.progression.milestones.check_all(core.progression.activity_actions)
	check(reached.has("ms_fishing_first_casts"), "five casts reach the first practice milestone")
	check(not core.progression.is_recipe_unlocked(core.registries.recipe("recipe_bench")), "bench recipe stays locked early")
	core.progression.activity_actions["fishing"] = 12
	core.progression.milestones.check_all(core.progression.activity_actions)
	check(reached.has("ms_fishing_settled_in"), "twelve casts reach the bench milestone")
	check(core.progression.is_recipe_unlocked(core.registries.recipe("recipe_bench")), "bench recipe unlocks with its milestone")
	var reached_before := reached.size()
	core.progression.milestones.check_all(core.progression.activity_actions)
	check(reached.size() == reached_before, "milestones grant exactly once")

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


func _test_void_discovery_and_honest_duplicates() -> void:
	var core := fresh_core(808)
	var first := core.progression.on_void_fishing_catch()["reward"] as Dictionary
	check(first.get("id") == "tile_open_water", "the authored first void discovery is useful water")
	check(core.progression.discovery.has_pending(), "discovery presentation is save-safe and pending")
	var accepted := core.progression.discovery.acknowledge_next()
	check(accepted.get("id") == first.get("id"), "acknowledgement returns the exact granted piece")
	var before := _entry_stock_count(core, first)
	var second := core.progression.on_void_fishing_catch()["reward"] as Dictionary
	check(not second.is_empty(), "later void catches use the broad gacha pool")
	check(_entry_stock_count(core, second) >= 1, "duplicates remain honest owned copies")
	check(_entry_stock_count(core, first) == before or second.get("id") == first.get("id"), "no hidden duplicate currency conversion exists")

func _test_void_duplicate_exchange() -> void:
	var core := fresh_core(909)
	core.stock.add_tile("tile_grass", 3)
	check(core.progression.void_exchange.offerable_count("tile", "tile_grass") == 3, "placed keeper copies protect all three stored grass spares")
	for index in 3:
		var result := core.progression.void_exchange.offer("tile", "tile_grass")
		check(bool(result.get("ok", false)), "spare offer %d succeeds" % (index + 1))
		if index < 2:
			check((result.get("reward", {}) as Dictionary).is_empty(), "the void waits for exactly three matching spares")
		else:
			var reward: Dictionary = result["reward"]
			check(
				reward.get("kind") == "tile"
				and reward.get("id") == "tile_sand",
				"three grass spares return a different Ground-category tile"
			)
	check(core.stock.tile_count("tile_grass") == 0, "exactly the three stored spares are consumed")
	check(core._placed_tile_count("tile_grass") == 9, "placed keeper copies remain untouched")
	core.stock.add_structure("struct_snowman")
	check(core.progression.void_exchange.offerable_count("structure", "struct_snowman") == 0, "an unplaced only copy is protected")
	core.stock.add_structure("struct_snowman")
	core.progression.void_exchange.offer("structure", "struct_snowman")
	check(
		core.progression.void_exchange.has_offerable_duplicates()
		and core.progression.void_exchange.offered_count(
			"structure", "struct_snowman"
		) == 1,
		"a partial offering remains visible while it waits for another spare"
	)
	core.stock.add_tile("tile_snowfield", 4)
	core.progression.void_exchange.offer("tile", "tile_snowfield")
	core.progression.void_exchange.offer("tile", "tile_snowfield")
	var impossible := core.progression.void_exchange.offer(
		"tile", "tile_snowfield"
	)
	check(
		not bool(impossible.get("ok", true))
		and impossible.get("reason") == "no_alternative"
		and core.stock.tile_count("tile_snowfield") == 4
		and core.progression.void_exchange.offered_count(
			"tile", "tile_snowfield"
		) == 0,
		"an unfinished one-item category returns all offers without loss"
	)

func _test_biome_pool_resolution() -> void:
	var core := fresh_core(1010)
	core.grid.place_tile(Vector2i(20, 20), "tile_grove_mature")
	core.grid.place_tile(Vector2i(30, 30), "tile_snowfield")
	core.grid.place_tile(Vector2i(40, 40), "tile_sand")
	var forest := core.progression.discovery.resolve_local_pool("woodcutting", Vector2i(20, 20), "struct_pine")
	var winter := core.progression.discovery.resolve_local_pool("woodcutting", Vector2i(30, 30), "struct_pine")
	var beach := core.progression.discovery.resolve_local_pool("woodcutting", Vector2i(40, 40), "struct_pine")
	check(forest.id == "tree_forest", "forest-built trees resolve the forest reward theme")
	check(winter.id == "tree_winter", "snow-built trees resolve the winter reward theme")
	check(beach.id == "tree_beach", "sand-built trees resolve the sunset/beach reward theme")
	var pond := Vector2i(60, 60)
	core.grid.place_tile(pond, "tile_open_water")
	for offset: Vector2i in WorldGrid.NEIGHBORS:
		var tree_coord := pond + offset
		core.grid.place_tile(tree_coord, "tile_grass")
		core.grid.add_structure(tree_coord, "struct_pine", 1)
	var planted_forest := core.progression.discovery.resolve_local_pool(
		"fishing", pond
	)
	check(
		planted_forest != null and planted_forest.id == "pond_forest",
		"player-placed pines turn an ordinary meadow pond into a forest pond"
	)
	check(
		core.registries.structure("struct_shrine") == null
		and not core.registries.capabilities.has("focus_shrine"),
		"manual shrine bias and land insurance are fully retired"
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

	var water := Vector2i(4, 4)
	core.grid.place_tile(water, "tile_open_water")
	check(
		core.grid.can_place_structure_at(water, 0, "struct_dock"),
		"a discovered water tile accepts docks"
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
	core.progression.on_void_fishing_catch()
	core.progression.on_activity_action("fishing", Vector2i.ZERO)
	core.stock.add_tile("tile_grove_birch")
	core.profile.position = Vector3(0.234, 0.0, 0.345)
	core.profile.facing = 1.11
	core.view_state = {"yaw": 135.0, "distance": 55.0}
	core.visual_state = {
		"weather": "snow", "time_of_day": "night",
		"background": "dusk", "particle_quality": "medium",
	}
	core.arrivals.trigger_arrival()
	core.arrivals.mark_delivery_ready(core.arrivals.current_payload)
	core.rng.randi_range("probe", 0, 999999)
	check(core.save(), "save writes")
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	check(restored.load_game(), "save loads")
	check(restored.progression.discovery.first_void_discovery_done, "first-discovery guarantee state round-trips")
	check(restored.progression.discovery.pending.size() == 2, "all pending discoveries round-trip")
	check(restored.progression.actions_done("fishing") == core.progression.actions_done("fishing"), "lifetime actions round-trip")
	check(restored.stock.tile_count("tile_grove_birch") == 1, "stock round-trips")
	check(restored.grid.cells.size() == core.grid.cells.size(), "grid round-trips")
	check(restored.profile.position.is_equal_approx(Vector3(0.234, 0.0, 0.345)), "exact player position round-trips")
	check(restored.view_state == core.view_state and restored.visual_state == core.visual_state, "view and atmosphere round-trip")
	check(restored.arrivals.has_waiting_package(), "unopened ferry gift survives restart")
	check(restored.arrivals.current_payload.gift_kind == "discovery", "delivery payload survives restart")
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
			"label": "discovery progress",
			"mutate": func(save: Dictionary) -> void:
				save["progression"]["discovery"]["progress"]["retired_pool"] = 1,
		},
		{
			"label": "discovery state",
			"mutate": func(save: Dictionary) -> void:
				save["progression"]["discovery"]["pending"] = [
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
	var entry := core.progression.on_void_fishing_catch()["reward"] as Dictionary
	check(core.progression.discovery.has_pending(), "discovery reveal is pending")
	var stock_before := _entry_stock_count(core, entry)
	core.save()
	var restored := GameCore.new()
	restored.setup("res://data", 1)
	restored.save_manager.save_path = core.save_manager.save_path
	restored.save_manager.backup_path = core.save_manager.backup_path
	check(restored.load_game(), "interrupted discovery save loads")
	check(restored.progression.discovery.pending.size() == 1, "the exact pending reveal survives restart")
	var acknowledged := restored.progression.discovery.acknowledge_next()
	check(acknowledged.get("id") == entry.get("id"), "resumed reveal keeps its exact reward")
	check(_entry_stock_count(restored, entry) == stock_before, "acknowledging never duplicates the already-safe reward")

func _test_progression_v1_migration() -> void:
	var core := fresh_core()
	var v1_save := {
		"skills": {"xp": {"fishing": 55}, "levels": {"fishing": 3}, "actions": {"fishing": 20}},
		"parcels": {"pending_options": ["tile_grass", "tile_sand", "tile_snowfield"]},
		"inventory": {"counts": {"pattern_dust": 5, "parcel_wild": 1, "softwood": 2}},
		"stock": {"tiles": {}, "structures": {}, "structure_instances": [], "deeds": []},
		"collection": {"entries": {
			"structures/struct_wishing_well": {
				"count": 2,
				"first_time": "legacy",
				"placed": 1,
			},
		}},
		"arrivals": {"state": "waiting", "payload": {"parcel_id": "parcel_wild", "delivery_id": 2}},
	}
	var migrated := ProgressionModule.migrate_save_payload(v1_save)
	check(not migrated.has("skills") and not migrated.has("parcels"), "v1 keys are absorbed")
	var progression: Dictionary = migrated["progression"]
	var archived: Dictionary = progression["archived_v1"]
	check(int(archived["skills"]["levels"]["fishing"]) == 3, "v1 levels are preserved verbatim")
	check(int(archived["inventory_counts"]["pattern_dust"]) == 5, "retired currency is archived")
	check(
		not migrated["inventory"]["counts"].has("pattern_dust")
		and int(migrated["inventory"]["counts"]["softwood"]) == 2,
		"retired items leave live inventory while real materials stay"
	)
	var pending: Array = progression["discovery"]["pending"]
	check(pending.size() == 1 and pending[0].get("id") == "tile_grass", "a promised v1 choice becomes one safe pending discovery")
	check(int(migrated["stock"]["tiles"]["tile_grass"]) == 1, "the migrated pending reward is granted before presentation")
	check(int(progression["activity_actions"]["fishing"]) == 20, "lifetime actions continue live")
	check(
		not migrated["collection"]["entries"].has(
			"structures/struct_wishing_well"
		)
		and int(
			migrated["collection"]["entries"][
				"structures/struct_stone_well"
			]["placed"]
		) == 1,
		"retired ritual objects become ordinary collection records"
	)
	check(String(migrated["arrivals"]["state"]) == "idle", "an obsolete mid-delivery parcel reschedules cleanly")
	var progression_errors := PackedStringArray()
	CurrentSaveValidatorScript._validate_progression(progression_errors, progression, core.registries)
	check(progression_errors.is_empty(), "migrated progression passes strict validation: " + ", ".join(progression_errors))
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
