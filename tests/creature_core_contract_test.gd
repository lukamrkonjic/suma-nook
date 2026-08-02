extends SceneTree
## Builds every creature definition headless and asserts the core contract:
## a valid parse, one ArrayMesh surface, and a shape count within the
## 16-shape mobile budget. Guards the "any body plan from JSON" promise.

const ProceduralCreatureScript := preload(
	"res://scripts/creatures/procedural_creature.gd"
)
const CREATURE_DIRECTORY := "res://data/creatures"


func _init() -> void:
	var directory := DirAccess.open(CREATURE_DIRECTORY)
	assert(directory != null, "Creature directory must exist")
	var built := 0
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			_check_creature(CREATURE_DIRECTORY.path_join(file_name))
			built += 1
		file_name = directory.get_next()
	directory.list_dir_end()
	assert(built >= 30, "Expected the full menagerie, found %d creatures" % built)
	_check_action_engine("res://data/creatures/sprout_scout.json")
	_check_action_engine("res://data/creatures/meadow_pup.json")
	print("CREATURE CORE CONTRACT PASSED — %d creatures built" % built)
	quit(0)


## Every library action must run to completion (or loop) headless and fire
## its authored events — on armed AND armless creatures alike.
func _check_action_engine(creature_path: String) -> void:
	var creature := ProceduralCreatureScript.new() as Node3D
	creature.call("build_from_path", creature_path)
	var actions_source := FileAccess.get_file_as_string(
		"res://data/creature_actions.json"
	)
	var library: Variant = JSON.parse_string(actions_source)
	assert(library is Dictionary, "Action library must parse")
	var events: Array[String] = []
	creature.connect(
		"action_event",
		func(_action_name: String, event_name: String) -> void:
			events.append(event_name)
	)
	var idle := ProceduralCreatureScript.MotionState.new()
	for action_name: String in (library as Dictionary):
		var definition := (library as Dictionary)[action_name] as Dictionary
		events.clear()
		creature.call("play_action", action_name)
		# Two authored cycles at 60 Hz covers loop wraps and completion.
		var ticks := int(float(definition.get("seconds", 0.8)) * 120.0) + 8
		for _tick in ticks:
			creature.call("advance", 1.0 / 60.0, idle)
		var expects_events := false
		for phase_value in definition.get("phases", []) as Array:
			if (phase_value as Dictionary).has("event"):
				expects_events = true
		if expects_events:
			assert(
				not events.is_empty(),
				"%s: action '%s' fired no events" % [creature_path, action_name]
			)
		if not bool(definition.get("loop", false)):
			assert(
				events.has("finished"),
				"%s: action '%s' never finished" % [creature_path, action_name]
			)
		creature.call("stop_action")
	creature.free()


func _check_creature(path: String) -> void:
	var creature := ProceduralCreatureScript.new() as Node3D
	creature.call("build_from_path", path)
	var budget := int(creature.call("shape_budget"))
	assert(
		budget >= 2 and budget <= 16,
		"%s: shape budget %d outside [2, 16]" % [path, budget]
	)
	var shell := creature.get_node("CreatureSdfShell") as MeshInstance3D
	assert(shell != null, "%s: creature must build its SDF shell" % path)
	var shell_mesh := shell.mesh as ArrayMesh
	assert(shell_mesh != null, "%s: shell must be an ArrayMesh" % path)
	assert(
		shell_mesh.get_surface_count() == 1,
		"%s: shell must stay one draw surface" % path
	)
	var identifier := String(creature.call("definition_id"))
	assert(not identifier.is_empty(), "%s: definition needs an id" % path)
	# Every outfit must dress every creature without erroring: hats/shirts
	# seat on anchors that exist for all body plans, pants/shoes/held skip
	# gracefully when a plan lacks legs or arms.
	for outfit_path in [
		"res://data/outfits/angler_set.json",
		"res://data/outfits/cozy_scout.json",
		"res://data/outfits/party_puff.json",
	]:
		creature.call("set_outfit", outfit_path)
		assert(
			creature.call("outfit") != null,
			"%s: outfit %s failed to build" % [path, outfit_path]
		)
	creature.call("clear_outfit")
	creature.free()
