class_name AmbientMotion
extends Node
## Generic, data-configured transform motion for decorative authored assets.
##
## Content opts in through the `ambient_motion` capability and names one node
## inside its GLB hierarchy.  No structure id is hard-coded here, so future
## wheels, signs, ornaments, or other ambient props can reuse the behavior.

var target: Node3D
var local_axis := Vector3.FORWARD
var radians_per_second := 0.0


func configure(authored_root: Node3D, payload: Dictionary) -> bool:
	var node_name := String(payload.get("node", ""))
	var found := authored_root.find_child(node_name, true, false)
	if not found is Node3D:
		push_warning(
			"Ambient motion target '%s' was not found beneath %s."
			% [node_name, authored_root.name]
		)
		set_process(false)
		return false
	target = found as Node3D
	local_axis = _axis_from_name(String(payload.get("axis", "z")))
	radians_per_second = float(payload.get("speed", 0.0))
	set_process(not is_zero_approx(radians_per_second))
	return true


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		set_process(false)
		return
	target.rotate_object_local(local_axis, radians_per_second * delta)


static func _axis_from_name(axis_name: String) -> Vector3:
	match axis_name.to_lower():
		"x":
			return Vector3.RIGHT
		"y":
			return Vector3.UP
		_:
			return Vector3.FORWARD
