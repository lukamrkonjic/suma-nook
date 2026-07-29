class_name ClothingFitSettings
extends Resource
## Editable, serializable inputs for the standalone Clothing Lab.
##
## These are deliberate fitting controls, not an automatic-fit result.  The
## deterministic Blender processor consumes the same values saved here.

@export_group("Source")
@export_file("*.glb") var source_file := ""
@export var body_profile_id := "body_male"

@export_group("Whole Garment")
@export var position := Vector3.ZERO
@export var rotation_degrees := Vector3.ZERO
@export var scale := Vector3(0.528005, 0.597675, 0.504159)
@export var symmetric := true

@export_group("Simple Fit")
@export_range(0.85, 1.25, 0.005) var torso_width := 1.0
@export_range(0.85, 1.25, 0.005) var torso_depth := 1.0
@export_range(-0.08, 0.08, 0.001, "suffix:m") var sleeve_lift := 0.0
@export_range(0.75, 1.20, 0.005) var sleeve_length := 1.0
@export_range(0.90, 1.80, 0.005) var sleeve_room := 1.0
@export_range(-0.04, 0.10, 0.001, "suffix:m") var shoulder_lift := 0.0
@export_range(0.85, 1.30, 0.005) var cuff_radius := 1.08
@export_range(-0.04, 0.04, 0.001, "suffix:m") var cuff_forward := 0.0

@export_group("Coverage")
@export var hidden_regions := PackedStringArray()


func reset_fit() -> void:
	position = Vector3.ZERO
	rotation_degrees = Vector3.ZERO
	scale = Vector3(0.528005, 0.597675, 0.504159)
	symmetric = true
	torso_width = 1.0
	torso_depth = 1.0
	sleeve_lift = 0.0
	sleeve_length = 1.0
	sleeve_room = 1.0
	shoulder_lift = 0.0
	cuff_radius = 1.08
	cuff_forward = 0.0


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if source_file.is_empty():
		errors.append("No source GLB selected.")
	if body_profile_id.is_empty():
		errors.append("No body profile selected.")
	if minf(scale.x, minf(scale.y, scale.z)) <= 0.0:
		errors.append("Garment scale must be positive.")
	if cuff_radius <= 0.0:
		errors.append("Cuff radius must be positive.")
	return errors


func to_json_data() -> Dictionary:
	return {
		"source_file": source_file,
		"body_profile_id": body_profile_id,
		"position": [position.x, position.y, position.z],
		"rotation_degrees": [
			rotation_degrees.x,
			rotation_degrees.y,
			rotation_degrees.z,
		],
		"scale": [scale.x, scale.y, scale.z],
		"symmetric": symmetric,
		"torso_width": torso_width,
		"torso_depth": torso_depth,
		"sleeve_lift": sleeve_lift,
		"sleeve_length": sleeve_length,
		"sleeve_room": sleeve_room,
		"shoulder_lift": shoulder_lift,
		"cuff_radius": cuff_radius,
		"cuff_forward": cuff_forward,
		"hidden_regions": Array(hidden_regions),
	}
