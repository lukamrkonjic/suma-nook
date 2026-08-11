class_name FrontierProjectService
extends RefCounted
## Owns the durable boundary between Project completion and Nook generation.
## Clicking only creates/tracks state; the scene generates after expansion_ready.

signal frontier_opened(frontier: Dictionary, project: Dictionary)
signal expansion_ready(coord: Vector2i, project_id: String, seed_card: Dictionary)
signal frontier_generated(coord: Vector2i, project_id: String)

var registries: Registries
var rng: RngService
var nooks: NookModule
var projects: ProjectService
var finds: FindsReserveService
var frontiers: Dictionary = {}


func _init(
	content: Registries,
	rng_service: RngService,
	nook_module: NookModule,
	project_service: ProjectService,
	finds_reserve: FindsReserveService
) -> void:
	registries = content
	rng = rng_service
	nooks = nook_module
	projects = project_service
	finds = finds_reserve
	var self_ref: WeakRef = weakref(self)
	projects.project_completed.connect(func(project: Dictionary):
		var service := self_ref.get_ref() as FrontierProjectService
		if service != null:
			service._on_project_completed(project)
	)


func open(coord: Vector2i) -> Dictionary:
	var frontier := ensure_frontier(coord)
	if frontier.is_empty():
		return {}
	var project_id := String(frontier.get("project_id", ""))
	projects.track(project_id)
	var project := projects.project(project_id)
	frontier_opened.emit(frontier.duplicate(true), project.duplicate(true))
	if bool(project.get("complete", false)) and not bool(frontier.get("generated", false)):
		_request_expansion(frontier)
	return project


func ensure_frontier(coord: Vector2i) -> Dictionary:
	if nooks.world.has_nook(coord) or not nooks.world.frontier_coords().has(coord):
		return {}
	var frontier_id := id_for_coord(coord)
	if frontiers.has(frontier_id):
		return (frontiers[frontier_id] as Dictionary).duplicate(true)
	var reserved := nooks.offers.roll_direct(coord)
	if reserved.is_empty():
		return {}
	var seed_card: Dictionary = reserved.get("card", {})
	var definition_id := _definition_for(coord)
	var project_id := "frontier:%d:%d" % [coord.x, coord.y]
	var seed_value := int(seed_card.get("seed", _stable_seed(coord)))
	var frontier := {
		"id": frontier_id,
		"coord": [coord.x, coord.y],
		"project_id": project_id,
		"definition_id": definition_id,
		"seed": seed_value,
		"seed_card": seed_card.duplicate(true),
		"generated": false,
		"generation_requested": false,
		"special": definition_id != "project_frontier_standard",
	}
	frontiers[frontier_id] = frontier
	projects.create_frontier(
		project_id,
		definition_id,
		seed_value,
		frontier_id,
		{"frontier_metadata": {
			"preview": _preview_for_card(seed_card),
			"special": frontier["special"],
		}}
	)
	return frontier.duplicate(true)


func frontier_for_coord(coord: Vector2i) -> Dictionary:
	var frontier_id := id_for_coord(coord)
	return (
		(frontiers[frontier_id] as Dictionary).duplicate(true)
		if frontiers.has(frontier_id)
		else {}
	)


func pending_expansions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for frontier: Dictionary in frontiers.values():
		if bool(frontier.get("generated", false)):
			continue
		var project := projects.project(String(frontier.get("project_id", "")))
		if bool(project.get("complete", false)):
			result.append(frontier.duplicate(true))
	return result


func mark_generated(coord: Vector2i) -> bool:
	var frontier_id := id_for_coord(coord)
	if not frontiers.has(frontier_id):
		return false
	var frontier: Dictionary = frontiers[frontier_id]
	if bool(frontier.get("generated", false)):
		return false
	frontier["generated"] = true
	frontier["generation_requested"] = false
	var project_id := String(frontier.get("project_id", ""))
	projects.mark_frontier_rewarded(project_id)
	frontier_generated.emit(coord, project_id)
	return true


func mark_generation_failed(coord: Vector2i) -> void:
	var frontier_id := id_for_coord(coord)
	if frontiers.has(frontier_id):
		frontiers[frontier_id]["generation_requested"] = false


func to_save_dict() -> Dictionary:
	return {"frontiers": frontiers.duplicate(true)}


func from_save_dict(data: Dictionary) -> void:
	frontiers = (data.get("frontiers", {}) as Dictionary).duplicate(true)
	# Existing expanded worlds remain truth even if an interrupted older save
	# did not carry the new generated bit yet.
	for frontier: Dictionary in frontiers.values():
		var coord := _coord_from(frontier.get("coord", []))
		if nooks.world.has_nook(coord):
			frontier["generated"] = true
		# Async scene work cannot survive a process restart. Completed Projects
		# become pending again and Main resumes them after loading.
		frontier["generation_requested"] = false


func migrate_existing_points() -> void:
	var coordinates: Array[Vector2i] = nooks.world.frontier_coords()
	coordinates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	for coord: Vector2i in coordinates:
		ensure_frontier(coord)


static func id_for_coord(coord: Vector2i) -> String:
	return "frontier:%d:%d" % [coord.x, coord.y]


func _on_project_completed(project: Dictionary) -> void:
	if String(project.get("type", "")) != ProjectService.TYPE_FRONTIER:
		return
	var frontier_id := String(project.get("expansion_point_id", ""))
	if not frontiers.has(frontier_id):
		return
	_request_expansion(frontiers[frontier_id])


func _request_expansion(frontier: Dictionary) -> void:
	if (
		bool(frontier.get("generated", false))
		or bool(frontier.get("generation_requested", false))
	):
		return
	frontier["generation_requested"] = true
	expansion_ready.emit(
		_coord_from(frontier.get("coord", [])),
		String(frontier.get("project_id", "")),
		(frontier.get("seed_card", {}) as Dictionary).duplicate(true)
	)


func _definition_for(coord: Vector2i) -> String:
	# Special frontiers only enter the deck after at least one ordinary reveal.
	# Coordinate + world seed determines the result forever; node count and
	# menu openings are irrelevant.
	if nooks.world.nooks.size() <= 1:
		return "project_frontier_standard"
	var roll := posmod(hash("special-frontier|%d|%d|%d" % [
		rng.world_seed, coord.x, coord.y,
	]), 7)
	if roll != 0:
		return "project_frontier_standard"
	return (
		"project_frontier_mountain"
		if posmod(hash("special-kind|%d|%d" % [coord.x, coord.y]), 2) == 0
		else "project_frontier_ancient"
	)


func _preview_for_card(card: Dictionary) -> String:
	var biome := String(card.get("biome_name", "Unknown land"))
	var density := String(card.get("density", "seeded"))
	return "%s · %s" % [biome, density.capitalize()]


func _stable_seed(coord: Vector2i) -> int:
	return absi(hash("frontier|%d|%d|%d" % [rng.world_seed, coord.x, coord.y]))


func _coord_from(raw: Variant) -> Vector2i:
	if raw is Array and raw.size() >= 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i.ZERO
