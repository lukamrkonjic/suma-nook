@tool
class_name TileKitGenerator
extends Node3D
## Deterministic layered tile generator — the Tile Kit runtime.
##
## Holds one TileKitPreset and renders it as one MeshInstance3D per layer.
## Layers rebuild independently: randomizing the grass never moves a dressing
## blob, because every layer draws from its own seed stream derived from
## (master_seed, kind, seed_offset), and rebuilds run in preset order with a
## shared context so downstream layers can READ upstream results (clutter
## leaning toward dressing blobs) without ever mutating them.
##
## The same class is the editing preview and the bake source: baking simply
## collects the already-built layer meshes into plain scenes, so what ships is
## byte-identical to what was approved on screen.

## The layer-kind registry. A new brick = a new builder class and one entry
## here; presets can then stack it into any tile.
static func builder_for(kind: String) -> Object:
	match kind:
		"base":
			return KitBaseBuilder
		"liquid":
			return KitLiquidBuilder
		"dressing":
			return KitDressingBuilder
		"clutter":
			return KitClutterBuilder
		"grass_clusters":
			return KitClusterBuilder
		"pavers":
			return KitPaversBuilder
		"fence":
			return KitFenceBuilder
		"fringe":
			return KitFringeBuilder
	return null

var preset: TileKitPreset:
	set(value):
		preset = value
		if is_inside_tree():
			rebuild()

## Which cardinal edges have a same-family neighbour: bit 1 = -Z, 2 = +X,
## 4 = +Z, 8 = -X. Fused edges drop their bevel and side wall so adjacent
## tiles read as ONE surface; 0 keeps the standalone block look.
var neighbour_mask := 0:
	set(value):
		neighbour_mask = value
		if is_inside_tree():
			rebuild()

## The tile's cell in the logical grid. World-anchored layers (relief noise)
## sample at world coordinates derived from this, which is what makes ground
## texture continue seamlessly across fused tiles.
var world_cell := Vector2i.ZERO:
	set(value):
		world_cell = value
		if is_inside_tree():
			rebuild()

## Presentation-only: hide the deep structural body (the stacking contract's
## below-seam block) so ground-level previews show the tile as the thin floor
## piece the player actually reads. Gameplay stacking is untouched — this
## only filters meshes with role "base" in THIS preview instance.
var show_structural_base := true:
	set(value):
		show_structural_base = value
		for kind: String in _layer_nodes:
			for child in (_layer_nodes[kind] as Node3D).get_children():
				if child is MeshInstance3D \
						and String(child.get_meta("role", "")) == "base":
					(child as MeshInstance3D).visible = value

## kind -> MeshInstance3D
var _layer_nodes: Dictionary = {}
## kind -> Array of mesh entries (role/name/mesh) from the last build.
var _layer_results: Dictionary = {}
var _context: Dictionary = {}


func _ready() -> void:
	if preset == null:
		preset = TileKitPreset.reference_clean_grass()
	rebuild()


## Deterministic per-layer RNG. The stream key includes the kind so two layers
## with the same offset still decorrelate, and the offset so "randomize just
## this layer" is one integer bump. A locked layer's frozen snapshot wins over
## everything: its geometry is pinned no matter what the master seed does.
static func layer_stream(master_seed: int, layer: TileKitLayer) -> int:
	if layer.locked and layer.stream_snapshot != 0:
		return layer.stream_snapshot
	return hash("%d|%s|%d" % [master_seed, layer.kind, layer.seed_offset])


static func layer_rng(master_seed: int, layer: TileKitLayer) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = layer_stream(master_seed, layer)
	return rng


func rebuild() -> void:
	if preset == null:
		return
	# The world/preview always supplies real topology. The preset decides
	# whether same-preset neighbours consume it: organic tiles fuse their shared
	# edges, while authored path/slab tiles deliberately retain each cell's rim.
	var effective_neighbour_mask := (
		0 if preset.separate_tiles else neighbour_mask
	)
	_context = {
		"neighbour_mask": effective_neighbour_mask,
		"world_origin": Vector2(world_cell) * KitBaseBuilder.TILE,
	}
	_layer_results.clear()
	for layer in preset.layers:
		_build_layer(layer)
	# Remove nodes for layers no longer in the preset.
	for kind: String in _layer_nodes.keys():
		if preset.layer_of_kind(kind) == null:
			(_layer_nodes[kind] as Node).queue_free()
			_layer_nodes.erase(kind)


func _build_layer(layer: TileKitLayer) -> void:
	var builder := builder_for(layer.kind)
	if builder == null:
		push_warning("TileKit: no builder for layer kind %s" % layer.kind)
		return
	if not layer.enabled:
		_layer_results.erase(layer.kind)
		_set_layer_meshes(layer.kind, [])
		return
	var rng := layer_rng(preset.master_seed, layer)
	var result: Dictionary = builder.call("build", layer, rng, _context)
	var meshes: Array = result.get("meshes", [])
	_layer_results[layer.kind] = meshes
	_set_layer_meshes(layer.kind, meshes)


func _set_layer_meshes(kind: String, meshes: Array) -> void:
	var holder: Node3D = _layer_nodes.get(kind)
	if holder == null:
		holder = Node3D.new()
		holder.name = "Layer_%s" % kind
		add_child(holder)
		_layer_nodes[kind] = holder
	for child in holder.get_children():
		child.free()
	for entry: Dictionary in meshes:
		var instance := MeshInstance3D.new()
		instance.name = entry.get("name", kind)
		instance.mesh = entry["mesh"]
		instance.set_meta("role", entry.get("role", "detail"))
		if not bool(entry.get("cast_shadow", true)):
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if String(entry.get("role", "")) == "base" and not show_structural_base:
			instance.visible = false
		holder.add_child(instance)


func set_layer_visible(kind: String, layer_visible: bool) -> void:
	var holder: Node3D = _layer_nodes.get(kind)
	if holder != null:
		holder.visible = layer_visible


# --- randomization -----------------------------------------------------------


## Rerolls one layer by bumping its seed offset, then rebuilds the whole
## pipeline — cheap at tile scale, and it keeps downstream layers honest
## about context they read from this one. Locked layers refuse.
func randomize_layer(kind: String) -> void:
	var layer := preset.layer_of_kind(kind)
	if layer == null or layer.locked:
		return
	layer.seed_offset += 1
	rebuild()


## New master seed for every unlocked layer. Locked layers are pinned by their
## stream snapshot (see set_layer_locked), so the full rebuild reproduces them
## bit-for-bit while everything else rerolls.
func randomize_all(new_master_seed: int) -> void:
	preset.master_seed = new_master_seed
	rebuild()


## Locking captures the layer's CURRENT stream so later master-seed changes
## cannot move it; unlocking releases it back to the derived stream.
func set_layer_locked(kind: String, locked: bool) -> void:
	var layer := preset.layer_of_kind(kind)
	if layer == null:
		return
	if locked:
		layer.stream_snapshot = layer_stream(preset.master_seed, layer)
	else:
		layer.stream_snapshot = 0
	layer.locked = locked


# --- reporting and baking ----------------------------------------------------


func statistics() -> Dictionary:
	var triangles := 0
	var vertices := 0
	var materials: Dictionary = {}
	for kind: String in _layer_results:
		for entry: Dictionary in _layer_results[kind]:
			var mesh: ArrayMesh = entry["mesh"]
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
				if index_data is PackedInt32Array:
					triangles += (index_data as PackedInt32Array).size() / 3
				vertices += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				var material := mesh.surface_get_material(surface)
				if material != null:
					materials[material.resource_name] = true
	return {
		"triangles": triangles,
		"vertices": vertices,
		"materials": materials.size(),
		"layers": _layer_results.size(),
	}


## Collects the built meshes into role scenes for the layered tile pipeline:
## base (persists when covered), surface (cap), detail (dressing + clutter +
## grass, hides when covered). Returns {role: PackedScene}.
func bake_role_scenes() -> Dictionary:
	var by_role: Dictionary = {}
	for layer in preset.layers:
		for entry: Dictionary in _layer_results.get(layer.kind, []):
			var role: String = entry.get("role", "detail")
			if not by_role.has(role):
				by_role[role] = []
			(by_role[role] as Array).append(entry)
	var scenes: Dictionary = {}
	for role: String in by_role:
		var root := Node3D.new()
		root.name = "tile_kit_%s" % role
		for entry: Dictionary in by_role[role]:
			var instance := MeshInstance3D.new()
			instance.name = entry.get("name", role)
			instance.mesh = entry["mesh"]
			if not bool(entry.get("cast_shadow", true)):
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(instance)
			instance.owner = root
		var packed := PackedScene.new()
		packed.pack(root)
		scenes[role] = packed
		root.free()
	return scenes


## Exports the whole tile as one GLB through Godot's runtime glTF writer.
func export_glb(path: String) -> Error:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_scene(self, state)
	if error != OK:
		return error
	return document.write_to_filesystem(state, path)
