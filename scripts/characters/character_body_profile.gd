class_name CharacterBodyProfile
extends Resource
## Describes one mannequin body: its scene, skeleton contract, and socket map.
## Future bodies (female, child, ...) are additional profiles sharing the same
## canonical skeleton contract; CharacterAssembler never branches on a body id.

@export_group("Identity")
@export var profile_id := "body_male"
## Resolved through AssetLibrary when running inside the game so palette
## materials bind; the lab and tools may instantiate body_scene directly.
@export var asset_id := ""
@export var body_scene: PackedScene
@export var compatibility_tags: PackedStringArray = []

@export_group("Skeleton Contract")
## The skeleton and animation naming contract this body implements. Bodies
## sharing an animation_profile_id can reuse each other's animation libraries.
@export var animation_profile_id := "mixamo_34"
@export var skeleton_node_name := "Skeleton3D"
@export var head_bone := "mixamorigHead"

@export_group("Sockets")
## Face sockets in body-scene local space (the glTF import space of
## body_scene, measured with the skeleton at rest). The assembler converts
## these into head-bone-local transforms when it builds the socket tree, so
## they follow head animation exactly. "FaceRoot" must be present; every other
## entry becomes a child socket of FaceRoot.
@export var face_sockets: Dictionary[String, Vector3] = {}
## Rigid non-face sockets: socket name -> skeleton bone name. Reserved names:
## HandSocket_L, HandSocket_R, BackSocket, ChestSocket, HipSocket_L,
## HipSocket_R.
@export var bone_sockets: Dictionary[String, String] = {}

@export_group("Clothing Fit Landmarks")
## Global rest-pose clothing anchors used by Clothing Lab for every garment
## category, from hats to shoes. Keys use "<side>.<joint>" (for example
## "center.crown", "left.shoulder", or "right.ankle") and values are in the
## body scene's local space. An empty dictionary falls back to measured bone
## rests and face sockets. This is fitting metadata only: editing it never
## moves the Skeleton3D.
@export var clothing_landmarks: Dictionary[String, Vector3] = {}

@export_group("Body Regions")
## Region hiding is implemented by the body's shader mask (see
## PlayerArmorRegions); clothing lists region names from that set.
@export var supports_region_mask := true

@export_group("Preview")
@export var preview_camera_height := 0.55
@export var preview_camera_size := 1.35


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if profile_id.is_empty():
		errors.append("profile_id is empty")
	if body_scene == null and asset_id.is_empty():
		errors.append("body profile has neither body_scene nor asset_id")
	if head_bone.is_empty():
		errors.append("head_bone is empty")
	if not face_sockets.has("FaceRoot"):
		errors.append("face_sockets must define FaceRoot")
	return errors
