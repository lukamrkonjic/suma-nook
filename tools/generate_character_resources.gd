extends SceneTree
## Generates the character system's data resources from the Blender manifest
## (art_source/characters/character_manifest.json): the male body profile, one
## part definition per exported part, the selectable face/hair catalog, and
## the default male appearance preset. Deterministic — rerun after
## re-exporting from Blender.
##
## Run:
##   godot --headless --path . --script res://tools/generate_character_resources.gd

const MANIFEST_PATH := "res://art_source/characters/character_manifest.json"
const BODY_PROFILE_PATH := "res://assets/characters/body_profiles/body_male.tres"
const PART_DEF_DIR := "res://assets/characters/parts/defs"
const CATALOG_PATH := "res://assets/characters/parts/catalog_male.tres"
const PRESET_PATH := "res://assets/characters/presets/default_male_appearance.tres"
const MANNEQUIN_SCENE := "res://assets/3d/reworked/player_male_mannequin.glb"
const CLOTHING_FIT_SNAPSHOT := (
	"res://art_source/imported/jacket_default/clothing_lab_fit.json"
)

## Fixed parts that are not player-selectable (yet); the selectable slots come
## from the manifest's "catalog" section.
const PART_TABLE := {
	# stem -> [slot, color_channel, display name]
	"brows_soft_pair": ["EYEBROWS", "brows", "Soft Brows"],
	"moustache_walrus": ["MOUSTACHE", "moustache", "Friendly Walrus"],
}

const CATALOG_COLOR_CHANNELS := {
	"HAIR": "hair",
	"EYES": "eyes",
	"MOUTH": "mouth",
	"NOSE": "skin",
}

## Skinned clothing definitions are owned by the Clothing Lab pipeline; the
## generator only makes sure the default outfit stays in the preset. An
## existing def on disk (with its lab-authored fit and regions) is preserved.
const CLOTHING_TABLE := {
	"top_jacket_cozy": [
		"TOP_OUTER",
		"Cozy Mustard Jacket",
		[
			"chest", "abdomen", "hips", "upper_chest_l", "upper_chest_r",
			"clavicle_l", "clavicle_r", "shoulder_l", "shoulder_r",
			"shoulder_cap_l", "shoulder_cap_r", "armpit_l", "armpit_r",
			"upper_arm_l", "upper_arm_r",
			"upper_arm_inner_l", "upper_arm_inner_r",
			"forearm_l", "forearm_r",
		],
	],
	"shoes_sneakers": [
		"SHOES",
		"Sneakers",
		["foot_l", "foot_r"],
	],
}


func _initialize() -> void:
	var manifest := _load_manifest()
	assert(not manifest.is_empty(), "Could not read %s" % MANIFEST_PATH)
	if not _validate_imported_assets(manifest):
		quit(1)
		return
	for directory in [
		BODY_PROFILE_PATH.get_base_dir(), PART_DEF_DIR, PRESET_PATH.get_base_dir()
	]:
		DirAccess.make_dir_recursive_absolute(directory)

	var preserved_landmarks := _load_preserved_clothing_landmarks()
	var profile := _build_body_profile(manifest)
	profile.clothing_landmarks = preserved_landmarks
	_save(profile, BODY_PROFILE_PATH)

	var defs: Dictionary = {}
	for stem in PART_TABLE:
		var table: Array = PART_TABLE[stem]
		defs[stem] = _save_part(_build_part(
			stem, manifest, String(table[0]), String(table[1]), String(table[2])
		))

	var catalog := CharacterPartCatalog.new()
	var manifest_catalog: Dictionary = manifest.get("catalog", {})
	assert(not manifest_catalog.is_empty(), "Manifest has no catalog section")
	for slot in ["HAIR", "EYES", "MOUTH", "NOSE"]:
		var entries: Array = manifest_catalog.get(slot, [])
		assert(not entries.is_empty(), "Manifest catalog missing slot %s" % slot)
		var options: Array[CharacterPartDefinition] = []
		for entry in entries:
			var stem := String(entry["stem"])
			var part := _save_part(_build_part(
				stem,
				manifest,
				slot,
				String(CATALOG_COLOR_CHANNELS[slot]),
				String(entry["display"])
			))
			defs[stem] = part
			options.append(part)
		match slot:
			"HAIR":
				catalog.hair = options
			"EYES":
				catalog.eyes = options
			"MOUTH":
				catalog.mouths = options
			"NOSE":
				catalog.noses = options
	_save(catalog, CATALOG_PATH)

	for stem in CLOTHING_TABLE:
		defs[stem] = _load_or_build_clothing(stem)

	var preset := CharacterAppearancePreset.new()
	preset.preset_id = "default_male"
	preset.body_profile = profile
	var parts: Array[CharacterPartDefinition] = [
		catalog.hair[0],
		catalog.eyes[0],
		defs["brows_soft_pair"],
		catalog.noses[0],
		catalog.mouths[0],
		defs["top_jacket_cozy"],
		defs["shoes_sneakers"],
	]
	preset.parts = parts
	var errors := preset.validation_errors()
	assert(errors.is_empty(), "Generated preset invalid: %s" % errors)
	_save(preset, PRESET_PATH)
	print("CHARACTER_RESOURCES_GENERATED parts=", defs.size())
	quit(0)


## ResourceLoader cannot load a freshly exported GLB until Godot's import pass
## has completed. Fail before writing anything instead of producing a partial
## catalog full of null definitions.
func _validate_imported_assets(manifest: Dictionary) -> bool:
	var missing: PackedStringArray = []
	var manifest_parts: Dictionary = manifest.get("parts", {})
	for stem in manifest_parts:
		var entry: Dictionary = manifest_parts[stem]
		var scene_path := (
			"res://%s" % String(entry.get("glb", "")).replace("\\", "/")
		)
		if (
			scene_path == "res://"
			or not ResourceLoader.exists(scene_path, "PackedScene")
		):
			missing.append("%s (%s)" % [stem, scene_path])
	if not ResourceLoader.exists(MANNEQUIN_SCENE, "PackedScene"):
		missing.append("mannequin (%s)" % MANNEQUIN_SCENE)
	if missing.is_empty():
		return true
	printerr(
		"Character assets are not imported. Run Godot with --import first: ",
		", ".join(missing)
	)
	return false


func _load_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


## Clothing Lab owns these artist-adjustable markers. Regenerating face parts
## must never erase them. Prefer the live profile; the deterministic fit JSON
## snapshot recovers them when an older generator has already cleared it.
func _load_preserved_clothing_landmarks() -> Dictionary[String, Vector3]:
	if ResourceLoader.exists(BODY_PROFILE_PATH):
		var existing := load(BODY_PROFILE_PATH) as CharacterBodyProfile
		if existing != null and not existing.clothing_landmarks.is_empty():
			return existing.clothing_landmarks.duplicate()
	var result: Dictionary[String, Vector3] = {}
	var file := FileAccess.open(CLOTHING_FIT_SNAPSHOT, FileAccess.READ)
	if file == null:
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return result
	var groups: Dictionary = (parsed as Dictionary).get("landmarks", {})
	for group_name in groups:
		var group: Dictionary = groups[group_name]
		for landmark_name in group:
			var values: Array = group[landmark_name]
			if values.size() != 3:
				continue
			result["%s.%s" % [group_name, landmark_name]] = Vector3(
				float(values[0]), float(values[1]), float(values[2])
			)
	return result


## Blender authoring space is Z-up with the face toward -Y; the glTF import is
## Y-up with the face toward +Z: (x, y, z) -> (x, z, -y).
func _to_godot(blender: Array) -> Vector3:
	return Vector3(
		float(blender[0]), float(blender[2]), -float(blender[1])
	)


func _build_body_profile(manifest: Dictionary) -> CharacterBodyProfile:
	var profile := CharacterBodyProfile.new()
	profile.profile_id = "body_male"
	profile.asset_id = "player_male_mannequin"
	profile.body_scene = load(MANNEQUIN_SCENE) as PackedScene
	assert(profile.body_scene != null, "Mannequin scene missing")
	profile.animation_profile_id = "mixamo_34"
	profile.head_bone = "mixamorigHead"
	profile.compatibility_tags = PackedStringArray(["male", "human"])
	var sockets: Dictionary[String, Vector3] = {}
	var manifest_sockets: Dictionary = manifest.get("sockets_model_space", {})
	for socket_name in manifest_sockets:
		sockets[String(socket_name)] = _to_godot(manifest_sockets[socket_name])
	profile.face_sockets = sockets
	# Rigid accessory socket naming convention, established now, used as
	# accessories are authored.
	var bone_sockets: Dictionary[String, String] = {
		"HandSocket_L": "mixamorigLeftHand",
		"HandSocket_R": "mixamorigRightHand",
		"BackSocket": "mixamorigSpine2",
		"ChestSocket": "mixamorigSpine2",
		"HipSocket_L": "mixamorigLeftUpLeg",
		"HipSocket_R": "mixamorigRightUpLeg",
	}
	profile.bone_sockets = bone_sockets
	var errors := profile.validation_errors()
	assert(errors.is_empty(), "Generated body profile invalid: %s" % errors)
	return profile


func _build_part(
	stem: String,
	manifest: Dictionary,
	slot: String,
	color_channel: String,
	display_name: String
) -> CharacterPartDefinition:
	var manifest_parts: Dictionary = manifest.get("parts", {})
	assert(manifest_parts.has(stem), "Manifest missing part %s" % stem)
	var entry: Dictionary = manifest_parts[stem]
	var part := CharacterPartDefinition.new()
	part.part_id = stem
	part.display_name = display_name
	part.slot = slot
	part.color_channel = color_channel
	part.attachment_type = CharacterPartDefinition.ATTACHMENT_RIGID
	part.socket = String(entry.get("socket", ""))
	var scene_path := "res://%s" % String(entry["glb"]).replace("\\", "/")
	part.scene = load(scene_path) as PackedScene
	assert(part.scene != null, "Part scene missing: %s" % scene_path)
	var fit := CharacterPartFit.new()
	fit.body_profile_id = "body_male"
	fit.notes = "Authored directly against body_male; identity fit."
	fit.validated = true
	part.fits = [fit]
	var errors := part.validation_errors()
	assert(errors.is_empty(), "Generated part '%s' invalid: %s" % [stem, errors])
	return part


## Saving with take_over_path makes later resources (catalog, preset) reference
## the def files externally instead of embedding duplicate subresources.
func _save_part(part: CharacterPartDefinition) -> CharacterPartDefinition:
	var path := "%s/%s.tres" % [PART_DEF_DIR, part.part_id]
	_save(part, path)
	part.take_over_path(path)
	return part


func _load_or_build_clothing(stem: String) -> CharacterPartDefinition:
	var path := "%s/%s.tres" % [PART_DEF_DIR, stem]
	if ResourceLoader.exists(path):
		var existing := load(path) as CharacterPartDefinition
		if existing != null:
			print("KEPT ", path)
			return existing
	var table: Array = CLOTHING_TABLE[stem]
	var part := CharacterPartDefinition.new()
	part.part_id = stem
	part.slot = String(table[0])
	part.display_name = String(table[1])
	part.attachment_type = CharacterPartDefinition.ATTACHMENT_SKINNED
	var scene_path := "res://assets/characters/parts/%s.glb" % stem
	part.scene = load(scene_path) as PackedScene
	assert(part.scene != null, "Clothing scene missing: %s" % scene_path)
	part.compatible_body_profiles = PackedStringArray(["body_male"])
	var regions: PackedStringArray = []
	for region in table[2]:
		regions.append(String(region))
	part.hidden_regions = regions
	var errors := part.validation_errors()
	assert(
		errors.is_empty(), "Generated clothing '%s' invalid: %s" % [stem, errors]
	)
	_save(part, path)
	part.take_over_path(path)
	return part


func _save(resource: Resource, path: String) -> void:
	var error := ResourceSaver.save(resource, path)
	assert(error == OK, "Could not save %s (error %d)" % [path, error])
	print("SAVED ", path)
