class_name ScreenPick
extends RefCounted
## Screen-space hit testing against a model's own projected silhouette.
##
## Approximations were tried and both failed in opposite directions. A fixed
## radius around an authored anchor puts the hot spot wherever the anchor was
## tuned for -- on the well that is high on the rim, so the body below it, the
## obvious place to point, did nothing. Replacing it with the projected
## bounding box overshot instead: a box drawn around a round model juts past
## the silhouette everywhere except the four points where it touches, so the
## target armed roughly fifteen pixels early.
##
## So the test uses the model itself: project every vertex, take the convex
## hull of those points, and ask whether the pointer is inside it. For the
## rounded props this game places, the hull IS the silhouette. It needs no
## per-model tuning, and a model added later is handled by the same code.
##
## Vertices are read once per mesh and cached; only the projection is redone,
## because that is what changes when the camera or the model moves.

static var _vertex_cache: Dictionary = {}
## Reward miniatures are built and freed constantly, so entries would otherwise
## accumulate for meshes that no longer exist. Dropping the whole cache when it
## grows past this is enough: it refills from the meshes actually on screen.
const CACHE_LIMIT := 96


## Local-space vertices of a mesh, cached by resource id.
static func _mesh_vertices(mesh: Mesh) -> PackedVector3Array:
	var key := mesh.get_instance_id()
	if _vertex_cache.has(key):
		return _vertex_cache[key]
	if _vertex_cache.size() >= CACHE_LIMIT:
		_vertex_cache.clear()
	# get_faces() and not surface_get_arrays(): the surface accessors are
	# ArrayMesh-only, and these visuals mix ArrayMesh with primitives such as
	# the well's CylinderMesh hole. Calling them threw on every primitive, the
	# hull came back empty, and nothing was hittable at all.
	var points := mesh.get_faces()
	_vertex_cache[key] = points
	return points


static func clear_cache() -> void:
	_vertex_cache.clear()


## Convex hull of a visual's vertices in screen space, empty when the visual
## has no geometry or sits behind the camera.
static func visual_screen_hull(
	camera: Camera3D, visual: Node3D
) -> PackedVector2Array:
	if camera == null or visual == null or not is_instance_valid(visual):
		return PackedVector2Array()
	var projected := PackedVector2Array()
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if not mesh_instance.is_visible_in_tree():
			continue
		var to_world := mesh_instance.global_transform
		for vertex in _mesh_vertices(mesh_instance.mesh):
			var world := to_world * vertex
			# A point behind the camera has no valid projection, and
			# unproject_position mirrors it across the screen; including one
			# would stretch the hull across the whole view.
			if camera.is_position_behind(world):
				continue
			projected.append(camera.unproject_position(world))
	if projected.size() < 3:
		return PackedVector2Array()
	return Geometry2D.convex_hull(projected)


## Distance from the pointer to the visual's silhouette, 0.0 when over it.
static func distance_to(
	camera: Camera3D,
	screen_position: Vector2,
	visual: Node3D
) -> float:
	var hull := visual_screen_hull(camera, visual)
	if hull.size() < 3:
		return INF
	if Geometry2D.is_point_in_polygon(screen_position, hull):
		return 0.0
	var nearest := INF
	for index in hull.size():
		var a := hull[index]
		var b := hull[(index + 1) % hull.size()]
		nearest = minf(
			nearest,
			screen_position.distance_to(
				Geometry2D.get_closest_point_to_segment(screen_position, a, b)
			)
		)
	return nearest


## True when the pointer is over the visual's silhouette. `padding` forgives a
## couple of pixels at the edge so a thin model stays comfortable to hit.
static func contains(
	camera: Camera3D,
	screen_position: Vector2,
	visual: Node3D,
	padding := 0.0
) -> bool:
	var distance := distance_to(camera, screen_position, visual)
	return not is_inf(distance) and distance <= padding
