class_name CharacterPartFit
extends Resource
## One body profile's placement correction for one part. Parts are authored
## with their origin at the canonical socket, so a fit should stay very small
## (millimeters and a few degrees); a large fit means the part or socket data
## is wrong and should be fixed in the source instead.

@export var body_profile_id := ""
@export var position := Vector3.ZERO
@export var rotation_degrees := Vector3.ZERO
## Uniform only. Non-uniform scaling of rigid attachments distorts silhouettes
## when the head animates and is deliberately unsupported.
@export var uniform_scale := 1.0
@export var notes := ""
@export var validated := false


func to_transform() -> Transform3D:
	var basis := Basis.from_euler(
		Vector3(
			deg_to_rad(rotation_degrees.x),
			deg_to_rad(rotation_degrees.y),
			deg_to_rad(rotation_degrees.z)
		)
	).scaled(Vector3.ONE * uniform_scale)
	return Transform3D(basis, position)


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if body_profile_id.is_empty():
		errors.append("fit has no body_profile_id")
	if uniform_scale <= 0.0:
		errors.append("fit scale must be positive")
	return errors
