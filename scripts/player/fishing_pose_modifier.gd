class_name FishingPoseModifier
extends SkeletonModifier3D
## Post-animation seated pose layer for the current production skeleton. The
## authored fishing clip keeps its relaxed hands/head motion while this layer
## folds the hips and knees onto the dock after AnimationPlayer playback.

@export var hips_bone := "mixamorigHips"
@export var left_up_leg_bone := "mixamorigLeftUpLeg"
@export var left_leg_bone := "mixamorigLeftLeg"
@export var left_foot_bone := "mixamorigLeftFoot"
@export var right_up_leg_bone := "mixamorigRightUpLeg"
@export var right_leg_bone := "mixamorigRightLeg"
@export var right_foot_bone := "mixamorigRightFoot"

var hip_drop := 0.29
var upper_leg_fold_degrees := 72.0
var knee_fold_degrees := -82.0
var foot_relax_degrees := 12.0


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var hips := skeleton.find_bone(hips_bone)
	if hips >= 0:
		skeleton.set_bone_pose_position(
			hips,
			skeleton.get_bone_pose_position(hips)
			+ Vector3.DOWN * hip_drop
		)
	_apply_rotation(
		skeleton,
		left_up_leg_bone,
		Vector3.RIGHT,
		upper_leg_fold_degrees,
		-4.0
	)
	_apply_rotation(
		skeleton,
		right_up_leg_bone,
		Vector3.RIGHT,
		upper_leg_fold_degrees,
		4.0
	)
	_apply_rotation(
		skeleton,
		left_leg_bone,
		Vector3.RIGHT,
		knee_fold_degrees
	)
	_apply_rotation(
		skeleton,
		right_leg_bone,
		Vector3.RIGHT,
		knee_fold_degrees
	)
	_apply_rotation(
		skeleton,
		left_foot_bone,
		Vector3.RIGHT,
		foot_relax_degrees
	)
	_apply_rotation(
		skeleton,
		right_foot_bone,
		Vector3.RIGHT,
		foot_relax_degrees
	)


func _apply_rotation(
	skeleton: Skeleton3D,
	bone_name: String,
	axis: Vector3,
	degrees: float,
	outward_degrees := 0.0
) -> void:
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return
	var offset := Quaternion(axis, deg_to_rad(degrees))
	if not is_zero_approx(outward_degrees):
		offset *= Quaternion(
			Vector3.FORWARD,
			deg_to_rad(outward_degrees)
		)
	skeleton.set_bone_pose_rotation(
		bone,
		skeleton.get_bone_pose_rotation(bone) * offset
	)
