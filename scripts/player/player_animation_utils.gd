class_name PlayerAnimationUtils
extends RefCounted
## Shared, model-agnostic cleanup for authored player animations.
##
## The gameplay controller owns world travel. Authored clips may retain vertical
## gait and cyclic horizontal sway, but their first and last horizontal root
## positions must close so looping never moves or teleports the character.


static func normalize_in_place(
	animation: Animation,
	hips_bone := ""
) -> int:
	var changed_tracks := 0
	for track_index in animation.get_track_count():
		if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		if not is_root_motion_track(animation, track_index, hips_bone):
			continue
		var key_count := animation.track_get_key_count(track_index)
		if key_count < 2:
			continue
		var first := animation.track_get_key_value(track_index, 0) as Vector3
		var last := animation.track_get_key_value(
			track_index,
			key_count - 1
		) as Vector3
		var horizontal_travel := Vector2(last.x - first.x, last.z - first.z)
		if horizontal_travel.length_squared() <= 0.00000001:
			continue
		var first_time := animation.track_get_key_time(track_index, 0)
		var last_time := animation.track_get_key_time(track_index, key_count - 1)
		var duration := maxf(last_time - first_time, 0.000001)
		for key_index in key_count:
			var key_time := animation.track_get_key_time(track_index, key_index)
			var ratio := clampf((key_time - first_time) / duration, 0.0, 1.0)
			var value := animation.track_get_key_value(track_index, key_index) as Vector3
			value.x -= horizontal_travel.x * ratio
			value.z -= horizontal_travel.y * ratio
			animation.track_set_key_value(track_index, key_index, value)
		changed_tracks += 1
	return changed_tracks


static func is_root_motion_track(
	animation: Animation,
	track_index: int,
	hips_bone := ""
) -> bool:
	var path := String(animation.track_get_path(track_index))
	if not path.contains(":"):
		return true
	var target := path.get_slice(":", 1)
	var normalized_target := target.to_lower()
	return (
		(not hips_bone.is_empty() and target == hips_bone)
		or normalized_target.contains("hips")
		or normalized_target.contains("pelvis")
		or normalized_target == "root"
		or normalized_target.ends_with("root")
	)
