class_name TileVisualFactory
extends RefCounted
## Converts data-defined tile behavior profiles into scene presentation.
## Renderers depend on profiles, never on particular content IDs.

const GROUND_LAYER := 1
const BLOCKER_LAYER := 1
const AUTHORED_TILE_SIZE := 1.7
const COVERED_INFILL_NAME := "CoveredSurfaceInfill"
const STACK_SEAM_NAME := "StackSeamCollar"
const PREVIEW_WATER_SURFACE_NAME := "PreviewWaterSurface"
const SURFACE_DETAIL_META := "tile_surface_detail"
const LAYER_ROLE_META := "tile_layer_role"
const LAYER_COVER_BEHAVIOR_META := "tile_layer_cover_behavior"
const COVER_FADE_DELAY := 0.075
const COVER_FADE_SECONDS := 0.105
const COVER_TWEEN_META := "covered_surface_tween"
const COVER_STATE_META := "covered_surface_state"
const STACK_SEAM_HEIGHT := 0.028
const STACK_SEAM_OVERLAP := 0.003

var assets: AssetLibrary
var grid: WorldGrid
var _batch_mesh_cache: Dictionary = {}


func _init(asset_library: AssetLibrary, world_grid: WorldGrid) -> void:
	assets = asset_library
	grid = world_grid


func instantiate_visual(def: Defs.TileDefinition, preview := false) -> Node3D:
	# Production GLBs were authored to the former 1.70 m footprint. Keep their
	# vertical profile intact while normalizing only X/Z to the live grid size.
	# The wrapper lets generated surface detail remain in live-grid units.
	var visual := Node3D.new()
	visual.name = def.id
	var authored_visual: Node3D
	if def.render_profile == "continuous_water":
		authored_visual = _continuous_water_bed()
	elif def.uses_layered_visual():
		authored_visual = _instantiate_layered_visual(def)
	else:
		authored_visual = assets.instantiate(def.asset_id)
	if not def.uses_layered_visual():
		var horizontal_scale := grid.tile_size / AUTHORED_TILE_SIZE
		authored_visual.scale = Vector3(horizontal_scale, 1.0, horizontal_scale)
	visual.add_child(authored_visual)
	if def.render_profile == "standard":
		_mark_authored_surface_details(authored_visual)
	_add_surface_detail(visual, def.surface_detail_profile)
	if preview and def.render_profile == "continuous_water":
		_add_preview_water_surface(visual)
	return visual


## Static scalable-world variant of instantiate_visual(). The complete
## layered/generated presentation is resolved once for each cover/seam state,
## flattened by material, then reused by chunk MultiMeshes.
func batch_mesh(
	def: Defs.TileDefinition,
	covered: bool,
	stack_seam: bool
) -> ArrayMesh:
	var key := "%s|%d|%d" % [def.id, int(covered), int(stack_seam)]
	if _batch_mesh_cache.has(key):
		return _batch_mesh_cache[key]
	var visual := instantiate_visual(def)
	set_stack_seam_visible(visual, stack_seam)
	if def.supports_tiles:
		set_surface_covered(visual, covered, false)
	var combined := assets.flatten_static_visual(visual, key)
	visual.free()
	if combined != null:
		_batch_mesh_cache[key] = combined
	return combined


func _instantiate_layered_visual(def: Defs.TileDefinition) -> Node3D:
	var root := Node3D.new()
	root.name = "LayeredTileVisual"
	var horizontal_scale := grid.tile_size / AUTHORED_TILE_SIZE
	for index in def.visual_layers.size():
		var layer: Defs.TileVisualLayerDefinition = def.visual_layers[index]
		var layer_visual := assets.instantiate(layer.asset_id)
		layer_visual.name = "%02d_%s_%s" % [index, layer.role, layer.asset_id]
		layer_visual.set_meta(LAYER_ROLE_META, layer.role)
		layer_visual.set_meta(LAYER_COVER_BEHAVIOR_META, layer.cover_behavior)
		if layer.scale_mode == "tile_xz":
			layer_visual.scale = Vector3(horizontal_scale, 1.0, horizontal_scale)
		layer_visual.position = layer.offset
		root.add_child(layer_visual)
		for child in layer_visual.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			mesh.set_meta(LAYER_ROLE_META, layer.role)
			mesh.set_meta(LAYER_COVER_BEHAVIOR_META, layer.cover_behavior)
			if layer.material_key != "":
				mesh.material_override = assets.materials.material(layer.material_key)
			if layer.role == "detail":
				mesh.set_meta(SURFACE_DETAIL_META, true)
	return root


func _mark_authored_surface_details(authored_visual: Node3D) -> void:
	# Classify by the shared geometric contract rather than content-specific
	# names: coverable relief lives wholly above the structural top plane and
	# remains within the gameplay-safe relief budget. This applies equally to
	# future authored tracks, cobbles, snow, puddles, and similar tile detail,
	# while excluding recessed pond shells and other structural geometry.
	for child in authored_visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var lower := mesh.name.to_lower()
		if lower.ends_with("_body") or lower.ends_with("_cap"):
			continue
		var relative := Transform3D.IDENTITY
		var cursor: Node3D = mesh
		while cursor != null and cursor != authored_visual:
			relative = cursor.transform * relative
			cursor = cursor.get_parent() as Node3D
		var bounds: AABB = relative * mesh.get_aabb()
		if bounds.position.y >= -0.002 and bounds.end.y <= 0.05:
			mesh.set_meta(SURFACE_DETAIL_META, true)


## A sculpted bowl repeated once per water cell made a connected region read as
## separate puddles through the transparent surface. Exact level planes meet
## without a visible edge; their underwater shader projects one world-space
## caustic field across the complete region.
func _continuous_water_bed() -> Node3D:
	var root := Node3D.new()
	root.name = "continuous_water_bed"
	var bed := MeshInstance3D.new()
	bed.name = "wf_bed"
	var plane := PlaneMesh.new()
	plane.size = Vector2(AUTHORED_TILE_SIZE, AUTHORED_TILE_SIZE)
	bed.mesh = plane
	bed.position.y = -0.43
	bed.material_override = assets.materials.material("uw_sand_light")
	root.add_child(bed)
	return root


## Imported block bodies retain a small bottom bevel. When an upper block uses
## that bevel directly, a hairline of the supporting tile is visible around the
## joint even though both transforms are exactly 0.50 m apart. Elevated tiles
## receive a thin collar in their own body material that bridges the bevel and
## overlaps the support by 3 mm. This is presentation-only; gameplay elevation
## and collision remain on the exact block-depth grid.
func set_stack_seam_visible(visual: Node3D, visible: bool) -> void:
	var collar := visual.find_child(STACK_SEAM_NAME, true, false) as MeshInstance3D
	if not visible:
		if collar != null:
			collar.visible = false
		return
	if collar == null:
		collar = _stack_seam_collar(visual)
		if collar == null:
			return
		visual.add_child(collar)
	collar.visible = true


## A covered tile keeps its structural body but loses its authored top cap and
## any raised surface dressing. During live placement the old surface remains
## until the incoming tile is nearly touching it, then cross-fades into a
## body-coloured infill. Static rebuilds and held stack ghosts resolve instantly.
func set_surface_covered(
	visual: Node3D,
	covered: bool,
	animate := false
) -> void:
	var had_cover_state := visual.has_meta(COVER_STATE_META)
	var previous_cover_state := (
		bool(visual.get_meta(COVER_STATE_META))
		if had_cover_state
		else not covered
	)
	visual.set_meta(COVER_STATE_META, covered)
	# Rebuilding or adding an object on the already-covered upper tile emits a
	# slot refresh too. Do not replay the lower grass fade and flash it through.
	if animate and had_cover_state and previous_cover_state == covered:
		return

	var body_mesh: MeshInstance3D
	var infill := visual.find_child(COVERED_INFILL_NAME, true, false) as MeshInstance3D
	var surface_meshes: Array[MeshInstance3D] = []
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh == infill or mesh.name == STACK_SEAM_NAME:
			continue
		var layer_role := String(mesh.get_meta(LAYER_ROLE_META, ""))
		var cover_behavior := String(mesh.get_meta(LAYER_COVER_BEHAVIOR_META, ""))
		var is_body := (
			layer_role == "base"
			or (
				layer_role == ""
				and mesh.name.to_lower().ends_with("_body")
			)
		)
		if is_body:
			if body_mesh == null:
				body_mesh = mesh
			mesh.visible = true
		elif cover_behavior == "persist":
			mesh.visible = true
		else:
			# Caps, imported relief, and generated speckles all belong to one
			# removable top presentation layer.
			surface_meshes.append(mesh)
	if covered and infill == null and body_mesh != null:
		infill = _covered_surface_infill(body_mesh)
		visual.add_child(infill)

	var previous_tween: Tween
	if visual.has_meta(COVER_TWEEN_META):
		previous_tween = visual.get_meta(COVER_TWEEN_META) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()
	if visual.has_meta(COVER_TWEEN_META):
		visual.remove_meta(COVER_TWEEN_META)

	if not animate:
		for mesh in surface_meshes:
			mesh.visible = not covered
			mesh.transparency = 0.0
		if infill != null:
			infill.visible = covered
			infill.transparency = 0.0
		return

	for mesh in surface_meshes:
		mesh.visible = true
	if infill != null:
		infill.visible = true

	var tween := visual.create_tween()
	visual.set_meta(COVER_TWEEN_META, tween)
	if covered:
		# Let the incoming block visibly descend first. The short cross-fade
		# overlaps the latter part of the renderer's measured settle.
		if infill != null and not infill.visible:
			infill.visible = true
		if infill != null and is_zero_approx(infill.transparency):
			infill.transparency = 1.0
		tween.tween_interval(COVER_FADE_DELAY)
		tween.set_parallel(true)
		for mesh in surface_meshes:
			tween.tween_property(
				mesh,
				"transparency",
				1.0,
				COVER_FADE_SECONDS
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if infill != null:
			tween.tween_property(
				infill,
				"transparency",
				0.0,
				COVER_FADE_SECONDS
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.set_parallel(false)
		tween.tween_callback(
			_finish_cover_transition.bind(visual, surface_meshes, infill)
		)
	else:
		for mesh in surface_meshes:
			mesh.transparency = 1.0
		if infill != null:
			infill.transparency = 0.0
		tween.set_parallel(true)
		for mesh in surface_meshes:
			tween.tween_property(
				mesh,
				"transparency",
				0.0,
				COVER_FADE_SECONDS
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if infill != null:
			tween.tween_property(
				infill,
				"transparency",
				1.0,
				COVER_FADE_SECONDS
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.set_parallel(false)
		tween.tween_callback(
			_finish_reveal_transition.bind(visual, surface_meshes, infill)
		)


func _finish_cover_transition(
	visual: Node3D,
	surface_meshes: Array[MeshInstance3D],
	infill: MeshInstance3D
) -> void:
	if not is_instance_valid(visual):
		return
	for mesh in surface_meshes:
		if mesh != null and is_instance_valid(mesh):
			mesh.visible = false
			mesh.transparency = 0.0
	if infill != null and is_instance_valid(infill):
		infill.visible = true
		infill.transparency = 0.0
	if visual.has_meta(COVER_TWEEN_META):
		visual.remove_meta(COVER_TWEEN_META)


func _finish_reveal_transition(
	visual: Node3D,
	surface_meshes: Array[MeshInstance3D],
	infill: MeshInstance3D
) -> void:
	if not is_instance_valid(visual):
		return
	for mesh in surface_meshes:
		if mesh != null and is_instance_valid(mesh):
			mesh.visible = true
			mesh.transparency = 0.0
	if infill != null and is_instance_valid(infill):
		infill.visible = false
		infill.transparency = 0.0
	if visual.has_meta(COVER_TWEEN_META):
		visual.remove_meta(COVER_TWEEN_META)


func _add_surface_detail(root: Node3D, profile: String) -> void:
	match profile:
		"grass_speckles":
			var detail_root := Node3D.new()
			detail_root.name = "TileSurfaceDetails"
			detail_root.set_meta(SURFACE_DETAIL_META, true)
			detail_root.set_meta(LAYER_ROLE_META, "detail")
			detail_root.set_meta(LAYER_COVER_BEHAVIOR_META, "hide")
			root.add_child(detail_root)
			_add_speckle_layer(
				detail_root,
				"surface_detail_speckles_light",
				"grass_lush",
				0x51A7,
				13,
				0.012,
				0.030
			)
			_add_speckle_layer(
				detail_root,
				"surface_detail_speckles_dark",
				"grass_tuft",
				0xC029,
				9,
				0.010,
				0.024
			)


func _add_speckle_layer(
	root: Node3D,
	node_name: String,
	material_key: String,
	seed_value: int,
	count: int,
	min_height: float,
	max_height: float
) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.set_meta(SURFACE_DETAIL_META, true)
	mesh_instance.set_meta(LAYER_ROLE_META, "detail")
	mesh_instance.set_meta(LAYER_COVER_BEHAVIOR_META, "hide")
	mesh_instance.mesh = _speckle_mesh(seed_value, count, min_height, max_height)
	mesh_instance.material_override = assets.materials.material(material_key)
	root.add_child(mesh_instance)


func _speckle_mesh(
	seed_value: int,
	count: int,
	min_height: float,
	max_height: float
) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var safe_half_extent := grid.tile_size * 0.39
	for _index in count:
		var center := Vector3(
			rng.randf_range(-safe_half_extent, safe_half_extent),
			rng.randf_range(min_height, max_height),
			rng.randf_range(-safe_half_extent, safe_half_extent)
		)
		var radius_x := rng.randf_range(0.026, 0.065)
		var radius_z := rng.randf_range(0.012, 0.035)
		var yaw := rng.randf_range(0.0, TAU)
		var rim: Array[Vector3] = []
		for corner in 4:
			var angle := yaw + corner * TAU * 0.25
			rim.append(
				Vector3(
					center.x + cos(angle) * radius_x,
					0.0015,
					center.z + sin(angle) * radius_z
				)
			)
		for corner in 4:
			# Winding faces upward. Each low four-sided shard catches a little
			# directional light without reading as a separate placeable tuft.
			surface.add_vertex(center)
			surface.add_vertex(rim[(corner + 1) % 4])
			surface.add_vertex(rim[corner])
	surface.generate_normals()
	var result := surface.commit()
	result.resource_name = "tile_surface_speckles"
	return result


func _covered_surface_infill(body_mesh: MeshInstance3D) -> MeshInstance3D:
	## The covered form's lid: while another tile sits above, the exposed top
	## presentation (cap, planks, debris — recessed or raised, any shape) is
	## hidden and this plain filler completes the body to EXACTLY one slot —
	## full tile_size footprint, flush to the walkable plane — so a stack
	## reads as clean full blocks with only the topmost tile carrying detail.
	var infill := MeshInstance3D.new()
	infill.name = COVERED_INFILL_NAME
	var box := BoxMesh.new()
	var body_top := -0.12
	if body_mesh.mesh != null:
		body_top = clampf(body_mesh.get_aabb().end.y, -0.3, -0.02)
	var height := -body_top
	box.size = Vector3(grid.tile_size, height, grid.tile_size)
	infill.mesh = box
	infill.position.y = -height * 0.5
	if body_mesh.mesh != null and body_mesh.mesh.get_surface_count() > 0:
		infill.material_override = body_mesh.get_active_material(0)
	return infill


func _stack_seam_collar(visual: Node3D) -> MeshInstance3D:
	var body_mesh: MeshInstance3D
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var candidate := child as MeshInstance3D
		if (
			String(candidate.get_meta(LAYER_ROLE_META, "")) == "base"
			or candidate.name.to_lower().ends_with("_body")
		):
			body_mesh = candidate
			break
	if body_mesh == null:
		return null
	var collar := MeshInstance3D.new()
	collar.name = STACK_SEAM_NAME
	var box := BoxMesh.new()
	box.size = Vector3(
		grid.tile_size - 0.004,
		STACK_SEAM_HEIGHT,
		grid.tile_size - 0.004
	)
	collar.mesh = box
	collar.position.y = (
		-grid.block_depth
		+ STACK_SEAM_HEIGHT * 0.5
		- STACK_SEAM_OVERLAP
	)
	if body_mesh.mesh != null and body_mesh.mesh.get_surface_count() > 0:
		collar.material_override = body_mesh.get_active_material(0)
	return collar


## Continuous world water is normally rendered by WorldRenderer as one joined
## mesh. A detached tile is no longer part of that topology, so its normal
## visual contains only the underwater bed. Give held water a one-cell local
## WaterSurface: it keeps the same shader and world-space wave phase while the
## tile moves, without producing the pale "empty puddle" preview.
func _add_preview_water_surface(visual: Node3D) -> void:
	var water_material := assets.materials.material("water")
	var water_level := -0.14
	if water_material is ShaderMaterial:
		var configured_level: Variant = (
			water_material as ShaderMaterial
		).get_shader_parameter("water_level")
		if configured_level is float or configured_level is int:
			water_level = float(configured_level)
	var surface := WaterSurface.new()
	surface.name = PREVIEW_WATER_SURFACE_NAME
	surface.set_meta("placement_water_surface", true)
	surface.rebuild(
		[Vector2i.ZERO],
		func(_coord: Vector2i) -> Vector3: return Vector3.ZERO,
		grid.tile_size,
		water_level,
		water_material
	)
	visual.add_child(surface)


## Makes a held water tile render as the missing piece of the region beneath
## the cursor instead of as an isolated one-cell pond. Offsets are relative to
## the ghost, so the complete preview can keep moving as one node.
func sync_preview_water_topology(
	visual: Node3D,
	connected_offsets: Array[Vector2i]
) -> void:
	if visual == null:
		return
	var surface := visual.find_child(
		PREVIEW_WATER_SURFACE_NAME,
		true,
		false
	) as WaterSurface
	if surface == null:
		return
	var topology: Array = [Vector2i.ZERO]
	for offset: Vector2i in connected_offsets:
		if offset != Vector2i.ZERO and not topology.has(offset):
			topology.append(offset)
	var active_material := surface.material_override
	if active_material == null:
		active_material = assets.materials.material("water")
	surface.rebuild_with_topology(
		[Vector2i.ZERO],
		topology,
		func(offset: Vector2i) -> Vector3:
			return Vector3(
				offset.x * grid.tile_size,
				0.0,
				offset.y * grid.tile_size
			),
		grid.tile_size,
		-0.14,
		active_material
	)


func add_collision(
	holder: Node3D,
	def: Defs.TileDefinition,
	rotation_quarters: int
) -> void:
	match def.collision_profile:
		"flat":
			if def.walkable:
				_add_box(
					holder,
					Vector3(grid.tile_size, grid.block_depth, grid.tile_size),
					Vector3(0.0, -grid.block_depth * 0.5, 0.0),
					GROUND_LAYER
				)
		"pond_basin":
			if def.walkable:
				_add_box(
					holder,
					Vector3(grid.tile_size, grid.block_depth, grid.tile_size),
					Vector3(0.0, -grid.block_depth * 0.5, 0.0),
					GROUND_LAYER
				)
			var authored_scale := grid.tile_size / AUTHORED_TILE_SIZE
			var offset := Vector3(
				0.14 * authored_scale,
				0.4,
				0.14 * authored_scale
			).rotated(
				Vector3.UP,
				rotation_quarters * PI * 0.5
			)
			var basin_width := grid.tile_size * 0.68
			_add_box(holder, Vector3(basin_width, 0.8, basin_width), offset, BLOCKER_LAYER)
		"none":
			pass


func _add_box(
	holder: Node3D,
	size: Vector3,
	position: Vector3,
	layer: int
) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = position
	body.add_child(shape)
	holder.add_child(body)
