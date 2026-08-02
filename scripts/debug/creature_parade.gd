class_name DebugCreatureParade
extends Node3D
## TEST-ONLY creature showcase: spawns every creature definition in rings
## around the world center and lets them wander idly so the whole cast can
## be inspected in-game.
##
## To remove: set "debug_creature_parade_enabled" to false in
## data/features.json — that is the only switch. (The hookup lives in
## Main._build_world; this file can then be deleted wholesale.)

const ProceduralCreatureScript := preload(
	"res://scripts/creatures/procedural_creature.gd"
)
const CREATURE_DIRECTORY := "res://data/creatures"
const PLAYER_DEFINITION := "islander.json"
const WALK_SPEED := 0.55

var _grid: WorldGrid
var _entries: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func setup(world_grid: WorldGrid, center: Vector3) -> void:
	_grid = world_grid
	_rng.seed = 20260802
	var paths: Array[String] = []
	var directory := DirAccess.open(CREATURE_DIRECTORY)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and file_name != PLAYER_DEFINITION:
			paths.append(CREATURE_DIRECTORY.path_join(file_name))
		file_name = directory.get_next()
	directory.list_dir_end()
	paths.sort()

	for path_index in paths.size():
		var creature := ProceduralCreatureScript.new() as Node3D
		add_child(creature)
		creature.call("build_from_path", paths[path_index])
		var angle := TAU * float(path_index) / float(paths.size())
		var ring := 2.4 + float(path_index % 3) * 0.85
		var home := center + Vector3(cos(angle) * ring, 0.0, sin(angle) * ring)
		home.y = _ground_height(home)
		creature.global_position = home
		creature.rotation.y = _rng.randf_range(0.0, TAU)
		_entries.append({
			"creature": creature,
			"home": home,
			"target": home,
			"pause": _rng.randf_range(0.4, 3.5),
		})


func _physics_process(delta: float) -> void:
	for entry in _entries:
		var creature := entry["creature"] as Node3D
		if not is_instance_valid(creature):
			continue
		var state := ProceduralCreatureScript.MotionState.new()
		state.grounded = true
		var offset := (entry["target"] as Vector3) - creature.global_position
		offset.y = 0.0
		if float(entry["pause"]) > 0.0:
			entry["pause"] = float(entry["pause"]) - delta
		elif offset.length() < 0.06:
			entry["pause"] = _rng.randf_range(1.2, 4.5)
			var home := entry["home"] as Vector3
			var next := home + Vector3(
				_rng.randf_range(-0.9, 0.9), 0.0, _rng.randf_range(-0.9, 0.9)
			)
			next.y = _ground_height(next)
			entry["target"] = next
		else:
			var direction := offset.normalized()
			creature.global_position += direction * WALK_SPEED * delta
			creature.rotation.y = lerp_angle(
				creature.rotation.y,
				atan2(-direction.x, -direction.z),
				minf(1.0, 6.0 * delta)
			)
			state.local_velocity = (
				creature.global_basis.inverse() * (direction * WALK_SPEED)
			)
		creature.call("advance", delta, state)


func _ground_height(world: Vector3) -> float:
	if _grid == null:
		return world.y
	return _grid.cell_to_world(_grid.world_to_cell(world)).y + 0.02
