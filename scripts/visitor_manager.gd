extends Node3D
class_name VisitorManager

signal seed_launch_requested(mote: Mote, token_id: StringName, world_position: Vector3)
signal mote_spawned(mote: Mote)
signal mote_clicked(mote: Mote)

const MoteScene := preload("res://scenes/mote.tscn")

var grid: GridManager
var data: GameData
var rng := RandomNumberGenerator.new()
var motes: Array[Mote] = []
var reserved: Dictionary = {}
var spawn_timer := 2.0
var cap := 6
var interval_min := 8.0
var interval_max := 14.0
var variant_cursor := 0


func setup(grid_manager: GridManager, game_data: GameData, world_seed: int) -> void:
	grid = grid_manager
	data = game_data
	rng.seed = world_seed ^ 0x5A17
	spawn_timer = float(data.tuning.get("first_visitor_delay", 2.0))
	cap = int(data.tuning.get("visitor_cap", 6))
	interval_min = float(data.tuning.get("visitor_interval_min", 8.0))
	interval_max = float(data.tuning.get("visitor_interval_max", 14.0))


func _process(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		if motes.size() < cap:
			spawn_mote()
		spawn_timer = rng.randf_range(interval_min, interval_max)


func spawn_mote(forced_token: StringName = &"", forced_coord := Vector3i(99999, 1, 99999)) -> Mote:
	if motes.size() >= cap:
		return null
	var start := forced_coord
	if start.x == 99999:
		start = _edge_cell()
	if not grid.is_walkable(start):
		var cells := grid.walkable_cells()
		if cells.is_empty():
			return null
		start = cells[0]
	var token_id := forced_token if forced_token != &"" else _draw_token()
	var mote := MoteScene.instantiate() as Mote
	add_child(mote)
	mote.setup(variant_cursor, token_id, grid, start)
	variant_cursor = posmod(variant_cursor + 1, 3)
	motes.append(mote)
	mote.path_requested.connect(_on_path_requested)
	mote.clicked.connect(func(source: Mote) -> void:
		if collect(source):
			mote_clicked.emit(source))
	mote.seed_launch_requested.connect(func(source: Mote, id: StringName, world_position: Vector3) -> void:
		seed_launch_requested.emit(source, id, world_position))
	mote.departure_requested.connect(_on_departure_requested)
	mote.departed.connect(_on_departed)
	mote_spawned.emit(mote)
	return mote


func collect(mote: Mote) -> bool:
	return mote != null and mote.collect_seed()


func _on_path_requested(mote: Mote) -> void:
	if not is_instance_valid(mote):
		return
	_release_reservation(mote)
	var interaction := _interaction_destination(mote.grid_coord) if rng.randf() < 0.45 else {}
	var destination: Vector3i = interaction.get(
		"coord", grid.random_reachable_destination(mote.grid_coord, rng, reserved))
	if not interaction.is_empty():
		mote.plan_interaction(StringName(str(interaction.get("tag", "inspect"))))
	reserved[destination] = mote
	var path := grid.reachable_path(mote.grid_coord, destination)
	mote.assign_path(path)


func _interaction_destination(start: Vector3i) -> Dictionary:
	var options: Array[Dictionary] = []
	for state: Dictionary in grid.props.values():
		var definition := data.item(StringName(str(state.get("definition_id", ""))))
		if definition == null or definition.visitor_interaction_tags.is_empty():
			continue
		var origin := GridManager.array_to_coord(state.get("coord", [0, 1, 0]))
		for direction: Vector3i in GridManager.CARDINALS:
			var candidate := Vector3i(origin.x + direction.x, 1, origin.z + direction.z)
			if reserved.has(candidate) or not grid.is_walkable(candidate):
				continue
			if grid.reachable_path(start, candidate).is_empty():
				continue
			options.append({
				"coord": candidate,
				"tag": definition.visitor_interaction_tags[
					rng.randi_range(0, definition.visitor_interaction_tags.size() - 1)],
			})
	if options.is_empty():
		return {}
	return options[rng.randi_range(0, options.size() - 1)]


func _on_departure_requested(mote: Mote) -> void:
	if not is_instance_valid(mote):
		return
	_release_reservation(mote)
	var edge := _edge_cell(mote.grid_coord)
	reserved[edge] = mote
	var path := grid.reachable_path(mote.grid_coord, edge)
	if path.is_empty():
		_on_departed(mote)
	else:
		mote.set_leaving(path)


func _on_departed(mote: Mote) -> void:
	_release_reservation(mote)
	motes.erase(mote)
	if is_instance_valid(mote):
		mote.queue_free()


func _release_reservation(mote: Mote) -> void:
	for coord: Vector3i in reserved.keys():
		if reserved[coord] == mote:
			reserved.erase(coord)


func _edge_cell(near := Vector3i.ZERO) -> Vector3i:
	var candidates := grid.walkable_cells()
	if candidates.is_empty():
		return Vector3i.ZERO
	var best: Array[Vector3i] = []
	var max_edge := -99999
	for cell: Vector3i in candidates:
		var edge_score: int = absi(cell.x) + absi(cell.z)
		if edge_score > max_edge:
			max_edge = edge_score
			best = [cell]
		elif edge_score == max_edge:
			best.append(cell)
	if near != Vector3i.ZERO:
		best.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			return a.distance_squared_to(near) < b.distance_squared_to(near))
		return best[0]
	return best[rng.randi_range(0, best.size() - 1)]


func _draw_token() -> StringName:
	var total := 0.0
	for id: StringName in data.tokens:
		total += data.token(id).default_weight
	var roll := rng.randf() * total
	for id: StringName in data.tokens:
		roll -= data.token(id).default_weight
		if roll <= 0.0:
			return id
	return &"meadow_coin"


func snapshot() -> Array:
	var result: Array = []
	for mote: Mote in motes:
		if not is_instance_valid(mote):
			continue
		result.append({
			"variant": mote.variant,
			"token_id": String(mote.token_id),
			"coord": [mote.grid_coord.x, 1, mote.grid_coord.z],
			"has_seed": mote.has_seed,
		})
	return result


func restore_snapshot(rows: Array) -> void:
	for mote: Mote in motes.duplicate():
		_on_departed(mote)
	var saved_cap := cap
	cap = maxi(cap, rows.size())
	for row: Variant in rows:
		if not bool(row.get("has_seed", true)):
			continue
		var mote := spawn_mote(
			StringName(str(row.get("token_id", "meadow_coin"))),
			GridManager.array_to_coord(row.get("coord", [0, 1, 0])))
		if mote != null:
			mote.variant = int(row.get("variant", mote.variant))
	cap = saved_cap


func add_offline_visitors(count: int) -> void:
	for _i: int in mini(count, cap - motes.size()):
		spawn_mote()
