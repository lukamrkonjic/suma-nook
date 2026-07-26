extends Node
## Runs the real Main scene and adds the two palette-repainted experimental GLBs
## to disposable moss-tile extensions. Main's own deterministic --shot harness
## captures the result and exits; this script never writes gameplay data.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const REPAINT_ADAPTER := preload(
	"res://tests/modly_blender_smoothing/palette_repaint_adapter.gd"
)
const TREE_SPECS := [
	{
		"id": "tree1",
		"path": "res://tests/modly_blender_smoothing/exports/tree1_smooth_test.glb",
		"coord": Vector2i(-2, 0),
		"target_height": 3.0,
		"yaw_degrees": 16.0,
		"foliage_profile": "pine",
	},
	{
		"id": "tree2",
		"path": "res://tests/modly_blender_smoothing/exports/tree2_smooth_test.glb",
		"coord": Vector2i(2, 0),
		"target_height": 3.3,
		"yaw_degrees": -20.0,
		"foliage_profile": "leaf",
	},
]


func _ready() -> void:
	DisplayServer.window_set_title("Suma Nook — Palette-Repainted Modly Trees (EXPERIMENT)")
	var main := MAIN_SCENE.instantiate() as Main
	add_child(main)

	# Main has now built a fresh throwaway world through its existing --shot
	# path. Extend that real world by one quiet moss tile on each side.
	for spec: Dictionary in TREE_SPECS:
		main.core.grid.place_tile(
			spec["coord"] as Vector2i,
			"tile_stone_mossy",
			0,
			true
		)
	main.renderer.rebuild_all()

	for spec: Dictionary in TREE_SPECS:
		_add_repainted_tree(main, spec)

	# Keep the avatar readable near the center of the actual starter world.
	main.player.position = main.core.grid.cell_to_world(Vector2i.ZERO)


func _add_repainted_tree(main: Main, spec: Dictionary) -> void:
	var packed := load(String(spec["path"])) as PackedScene
	if packed == null:
		push_error("Could not load experimental tree: " + String(spec["path"]))
		return
	var tree := packed.instantiate() as Node3D
	tree.name = "%s_PaletteRepaint_Experiment" % spec["id"]
	main.world_root.add_child(tree)

	var bounds := _combined_local_bounds(tree)
	if bounds.size.y <= 0.0001:
		push_error("Experimental tree has empty bounds: " + String(spec["id"]))
		tree.queue_free()
		return
	var target_height := float(spec["target_height"])
	var uniform_scale := target_height / bounds.size.y
	tree.scale = Vector3.ONE * uniform_scale
	tree.rotation.y = deg_to_rad(float(spec["yaw_degrees"]))
	tree.position = (
		main.core.grid.cell_to_world(spec["coord"] as Vector2i)
		+ Vector3(0.0, -bounds.position.y * uniform_scale + 0.025, 0.0)
	)

	var repaint_report: Dictionary = REPAINT_ADAPTER.apply_to_tree(
		tree,
		main.materials,
		String(spec["foliage_profile"])
	)
	print(
		"MODLY PALETTE TREE %s — %.2fm, profile=%s, meshes=%d, surfaces=%d, albedo=%d, normals=%d"
		% [
			spec["id"],
			target_height,
			repaint_report["profile"],
			repaint_report["mesh_count"],
			repaint_report["surface_count"],
			repaint_report["albedo_textures_retained"],
			repaint_report["normal_maps_retained"],
		]
	)


func _combined_local_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var has_bounds := false
	var to_root := root.global_transform.affine_inverse()
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var transform_to_root := to_root * mesh_instance.global_transform
		var local_bounds: AABB = transform_to_root * mesh_instance.get_aabb()
		if has_bounds:
			result = result.merge(local_bounds)
		else:
			result = local_bounds
			has_bounds = true
	return result
