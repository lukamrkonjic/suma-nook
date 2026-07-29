extends SceneTree
## Generates the character system's data resources from the Blender manifest
## (art_source/characters/character_manifest.json): the male body profile, one
## part definition per exported default part, and the default male appearance
## preset. Deterministic — rerun after re-exporting from Blender.
##
## Run:
##   godot --headless --path . --script res://tools/generate_character_resources.gd

const MANIFEST_PATH := "res://art_source/characters/character_manifest.json"
const BODY_PROFILE_PATH := "res://assets/characters/body_profiles/body_male.tres"
const PART_DEF_DIR := "res://assets/characters/parts/defs"
const PRESET_PATH := "res://assets/characters/presets/default_male_appearance.tres"
const MANNEQUIN_SCENE := "res://assets/3d/reworked/player_male_mannequin.glb"

const PART_TABLE := {
	# stem -> [slot, color_channel, display name]
	"hair_swoop_brown": ["HAIR", "hair", "Brown Swoop"],
	"eyes_oval_pair": ["EYES", "eyes", "Warm Ovals"],
	"brows_soft_pair": ["EYEBROWS", "brows", "Soft Brows"],
	"nose_round": ["NOSE", "skin", "Round Nose"],
	"moustache_walrus": ["MOUSTACHE", "moustache", "Friendly Walrus"],
	"mouth_smile": ["MOUTH", "mouth", "Gentle Smile"],
}

## Skinned clothing authored against the canonical skeleton (see
## docs/CLOTHING_GENERATION_GUIDE.md). stem -> [slot, display name, regions].
const CLOTHING_TABLE := {
	"top_jacket_cozy": [
		"TOP_OUTER",
		"Cozy Mustard Jacket",
		[
			"chest", "abdomen", "upper_chest_l", "upper_chest_r",
			"clavicle_l", "clavicle_r", "shoulder_l", "shoulder_r",
			"shoulder_cap_l", "shoulder_cap_r", "armpit_l", "armpit_r",
			"upper_arm_l", "upper_arm_r",
			"upper_arm_inner_l", "upper_arm_inner_r",
			"forearm_l", "forearm_r",
		],
	],
}


func _initialize() -> void:
	var manifest := _load_manifest()
	assert(not manifest.is_empty(), "Could not read %s" % MANIFEST_PATH)
	for directory in [
		BODY_PROFILE_PATH.get_base_dir(), PART_DEF_DIR, PRESET_PATH.get_base_dir()
	]:
		DirAccess.make_dir_recursive_absolute(directory)

	var profile := _build_body_profile(manifest)
	_save(profile, BODY_PROFILE_PATH)

	var parts: Array[CharacterPartDefinition] = []
	for stem in PART_TABLE:
		var part := _build_part(stem, manifest)
		_save(part, "%s/%s.tres" % [PART_DEF_DIR, stem])
		parts.append(part)
	for stem in CLOTHING_TABLE:
		var garment := _build_clothing(stem)
		_save(garment, "%s/%s.tres" % [PART_DEF_DIR, stem])
		parts.append(garment)

	var preset := CharacterAppearancePreset.new()
	preset.preset_id = "default_male"
	preset.body_profile = profile
	preset.parts = parts
	var errors := preset.validation_errors()
	assert(errors.is_empty(), "Generated preset invalid: %s" % errors)
	_save(preset, PRESET_PATH)
	print("CHARACTER_RESOURCES_GENERATED parts=", parts.size())
	quit(0)


func _load_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


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


func _build_part(stem: String, manifest: Dictionary) -> CharacterPartDefinition:
	var table: Array = PART_TABLE[stem]
	var manifest_parts: Dictionary = manifest.get("parts", {})
	assert(manifest_parts.has(stem), "Manifest missing part %s" % stem)
	var entry: Dictionary = manifest_parts[stem]
	var part := CharacterPartDefinition.new()
	part.part_id = stem
	part.display_name = String(table[2])
	part.slot = String(table[0])
	part.color_channel = String(table[1])
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


func _build_clothing(stem: String) -> CharacterPartDefinition:
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
	return part


func _save(resource: Resource, path: String) -> void:
	var error := ResourceSaver.save(resource, path)
	assert(error == OK, "Could not save %s (error %d)" % [path, error])
	print("SAVED ", path)
