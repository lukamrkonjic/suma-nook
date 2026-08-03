extends SceneTree
## Numeric probe: prints the V2 lower-shell shape uniforms and pose anchors.

const ProceduralCreatureScript := preload(
	"res://scripts/creatures/procedural_creature.gd"
)


func _init() -> void:
	var definition: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/creatures/islander.json")
	)
	var creature := ProceduralCreatureScript.new() as Node3D
	root.add_child(creature)
	creature.call("build", definition as Dictionary)
	var state := ProceduralCreatureScript.MotionState.new()
	state.grounded = true
	for _frame in 90:
		creature.call("advance", 1.0 / 60.0, state)
	var anchors: Dictionary = creature.call("pose_anchors")
	print("legs anchors: ", anchors.get("legs"))
	print("arms anchors: ", anchors.get("arms"))
	print("body: ", anchors.get("body"))
	print("head: ", anchors.get("head"))
	var body := creature.get_node("HumanBodyParts") as Node3D
	print("creature global: ", creature.global_position)
	print("body global: ", body.global_position)
	print("shoe left global: ", (body.get_node("ShoeLeft") as Node3D).global_position)
	print("blob global: ", (body.get_node("ContactShadow") as Node3D).global_position)
	var shin := body.get_node("ShinLeft") as MeshInstance3D
	if shin.mesh != null:
		print("shin aabb: ", shin.mesh.get_aabb())
	var leg := body.get_node("LegLeft") as MeshInstance3D
	if leg.mesh != null:
		print("naked leg aabb: ", leg.mesh.get_aabb())
	var measurements: Dictionary = body.call("measurements")
	print("measurements: ", measurements)
	print("missing tokens: ", body.call("missing_palette_tokens"))
	quit(0)
