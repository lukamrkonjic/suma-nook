class_name NookFrontierMarkers
extends Node3D
## Clear world-space glows in every open Nook slot touching revealed land.
## Pointer hit testing projects the dots to screen space; controllers use the
## existing deterministic Shape Land grid cursor and build_confirm action.

const DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
]
const SCREEN_HIT_RADIUS := 34.0
const DOT_RADIUS := 0.11
const RIM_RADIUS := 0.16
const HALO_RADIUS := 0.25

var core: GameCore
var camera: Camera3D
var placement: PlacementController
var palette: CozyPalette
var interaction_enabled := true

## Chunk coord -> {"root", "cell", "direction", "inner", "halo"}.
var _markers: Dictionary = {}
var _elapsed := 0.0


func setup(
	game_core: GameCore,
	world_camera: Camera3D,
	placement_controller: PlacementController,
	color_palette: CozyPalette
) -> void:
	core = game_core
	camera = world_camera
	placement = placement_controller
	palette = color_palette
	core.nooks.world.nook_added.connect(func(_coord): rebuild())
	rebuild()


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	visible = enabled and not _markers.is_empty()


func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_markers.clear()
	if core == null or not core.nooks.enabled:
		visible = false
		return
	for target: Dictionary in frontier_targets(core.nooks.world):
		var nook_coord: Vector2i = target["nook"]
		var direction: Vector2i = target["direction"]
		var cell := marker_cell(core.nooks.world, nook_coord, direction)
		var root := _build_marker(nook_coord)
		root.position = core.grid.cell_to_world(cell) + Vector3.UP * 0.28
		add_child(root)
		_markers[nook_coord] = {
			"root": root,
			"cell": cell,
			"direction": direction,
			"inner": root.get_node("Dot"),
			"halo": root.get_node("Halo"),
		}
	visible = interaction_enabled and not _markers.is_empty()


func _process(delta: float) -> void:
	_elapsed += delta
	if not visible or camera == null:
		return
	var selected := Vector2i(2147483647, 2147483647)
	if placement != null and placement.controller_cursor_active():
		selected = placement.controller_cursor_cell()
	elif get_viewport() != null:
		var hit := marker_at_screen(get_viewport().get_mouse_position())
		if not hit.is_empty():
			selected = hit["cell"]
	for marker: Dictionary in _markers.values():
		var root := marker["root"] as Node3D
		var is_selected: bool = marker["cell"] == selected
		var pulse := 1.0 + sin(_elapsed * 3.0) * 0.16
		var target_scale := 1.52 if is_selected else pulse
		root.scale = root.scale.lerp(
			Vector3.ONE * target_scale,
			minf(1.0, delta * 10.0)
		)


## Returns the target Nook and deterministic controller cell beneath a dot.
func marker_at_screen(screen_position: Vector2) -> Dictionary:
	if not interaction_enabled or camera == null:
		return {}
	var closest := SCREEN_HIT_RADIUS
	var result: Dictionary = {}
	for nook_coord: Vector2i in _markers:
		var marker: Dictionary = _markers[nook_coord]
		var root := marker["root"] as Node3D
		if not is_instance_valid(root) or camera.is_position_behind(root.global_position):
			continue
		var distance := screen_position.distance_to(
			camera.unproject_position(root.global_position)
		)
		if distance <= closest:
			closest = distance
			result = {
				"nook": nook_coord,
				"cell": marker["cell"],
				"direction": marker["direction"],
			}
	return result


func marker_at_cell(cell: Vector2i) -> Dictionary:
	if not interaction_enabled:
		return {}
	for nook_coord: Vector2i in _markers:
		var marker: Dictionary = _markers[nook_coord]
		if marker["cell"] == cell:
			return {
				"nook": nook_coord,
				"cell": cell,
				"direction": marker["direction"],
			}
	return {}


func marker_count() -> int:
	return _markers.size()


func marker_screen_position(nook_coord: Vector2i) -> Vector2:
	var marker: Dictionary = _markers.get(nook_coord, {})
	if marker.is_empty() or camera == null:
		return Vector2(-1.0, -1.0)
	return camera.unproject_position((marker["root"] as Node3D).global_position)


## Every unrevealed Nook coordinate beside revealed land gets one marker.
## NookWorld deduplicates coordinates, so a gap between two branches reads as
## one inviting dot instead of competing edge markers.
static func frontier_targets(world: NookWorld) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world == null or world.nooks.is_empty():
		return result
	for coord: Vector2i in world.frontier_coords():
		var direction := Vector2i.ZERO
		for candidate_direction in DIRECTIONS:
			if world.has_nook(coord - candidate_direction):
				direction = candidate_direction
				break
		if direction != Vector2i.ZERO:
			result.append({"nook": coord, "direction": direction})
	return result


static func marker_cell(
	world: NookWorld,
	nook_coord: Vector2i,
	direction: Vector2i
) -> Vector2i:
	var origin := world.chunk_origin(nook_coord)
	var middle := world.nook_size / 2
	var seam_points: Array[Vector2i] = []
	for neighbor_offset in DIRECTIONS:
		if not world.has_nook(nook_coord + neighbor_offset):
			continue
		if neighbor_offset == Vector2i.LEFT:
			seam_points.append(Vector2i(0, middle))
		elif neighbor_offset == Vector2i.RIGHT:
			seam_points.append(Vector2i(world.nook_size - 1, middle))
		elif neighbor_offset == Vector2i.UP:
			seam_points.append(Vector2i(middle, 0))
		else:
			seam_points.append(Vector2i(middle, world.nook_size - 1))
	if seam_points.is_empty():
		# Defensive fallback for a caller holding a stale frontier snapshot.
		if direction == Vector2i.RIGHT:
			return origin + Vector2i(0, middle)
		if direction == Vector2i.LEFT:
			return origin + Vector2i(world.nook_size - 1, middle)
		if direction == Vector2i.DOWN:
			return origin + Vector2i(middle, 0)
		return origin + Vector2i(middle, world.nook_size - 1)
	var sum := Vector2i.ZERO
	for point in seam_points:
		sum += point
	return origin + Vector2i(
		roundi(float(sum.x) / float(seam_points.size())),
		roundi(float(sum.y) / float(seam_points.size()))
	)


func _build_marker(nook_coord: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "Frontier_%d_%d" % [nook_coord.x, nook_coord.y]

	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = HALO_RADIUS
	halo_mesh.height = HALO_RADIUS * 2.0
	halo.mesh = halo_mesh
	halo.material_override = _glow_material(
		palette.color("environment_centre_glow"), 0.46, 4.2, 6
	)
	root.add_child(halo)

	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var rim_mesh := SphereMesh.new()
	rim_mesh.radius = RIM_RADIUS
	rim_mesh.height = RIM_RADIUS * 2.0
	rim.mesh = rim_mesh
	rim.material_override = _glow_material(
		palette.color("gold_highlight"), 0.96, 5.0, 7
	)
	root.add_child(rim)

	var dot := MeshInstance3D.new()
	dot.name = "Dot"
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = DOT_RADIUS
	dot_mesh.height = DOT_RADIUS * 2.0
	dot.mesh = dot_mesh
	dot.material_override = _glow_material(
		palette.color("gold_primary"), 1.0, 6.0, 8
	)
	root.add_child(dot)
	return root


static func _glow_material(
	color: Color,
	alpha: float,
	emission_energy: float,
	priority: int
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	material.no_depth_test = true
	material.render_priority = priority
	return material
