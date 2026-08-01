@tool
class_name TileBakeManifest
extends Resource
## The receipt for one baked tile: what was built, from what, and whether it
## passed. Written next to the baked scene so a future agent can reproduce or
## audit any shipped asset without re-running the editor.

@export var tile_id := ""
@export var display_name := ""
@export var recipe_path := ""
@export var seed_value := 0
@export var variant := 0
## FNV-1a of the recipe's meaningful fields at bake time. A mismatch means the
## baked asset is stale.
@export var recipe_hash := ""
@export var baked_at := ""
@export var forge_version := "1.0.0"

@export_group("Geometry report")
@export var triangle_count := 0
@export var vertex_count := 0
@export var surface_triangle_count := 0
@export var detail_triangle_count := 0
@export var material_count := 0
@export var node_count := 0
@export var module_instance_count := 0
@export var materials_used: PackedStringArray = []
@export var bounds_min := Vector3.ZERO
@export var bounds_max := Vector3.ZERO
@export var measured_walk_height := 0.0
@export var exposed_top := "flush"

@export_group("Integration")
## What data/tiles.json should reference for the structural block.
@export var shared_base_asset := ""
@export var connection_mode := "full_flush"
@export var collision_mode := ""
@export var scale_mode := "none"

@export_group("Validation")
@export var passed := false
@export var errors: PackedStringArray = []
@export var warnings: PackedStringArray = []
@export var checks_run := 0


func summary_line() -> String:
	return "%s  tris=%d  mats=%d  nodes=%d  modules=%d  %s" % [
		tile_id,
		triangle_count,
		material_count,
		node_count,
		module_instance_count,
		"PASS" if passed else "FAIL",
	]


## The `layers` fragment a designer pastes into data/tiles.json.
func tiles_json_fragment() -> String:
	var lines: Array[String] = []
	lines.append("{")
	lines.append('  "id": "tile_%s",' % tile_id.trim_prefix("tf_"))
	lines.append('  "name": "%s",' % display_name)
	lines.append('  "asset_id": "%s",' % tile_id)
	lines.append('  "render_profile": "layered",')
	lines.append('  "layers": [')
	if shared_base_asset != "":
		lines.append("    {")
		lines.append('      "role": "base",')
		lines.append('      "asset_id": "%s",' % shared_base_asset)
		lines.append('      "material": "earth_mid",')
		lines.append('      "cover_behavior": "persist"')
		lines.append("    },")
	lines.append("    {")
	lines.append('      "role": "surface",')
	lines.append('      "asset_id": "%s",' % tile_id)
	lines.append('      "scale_mode": "%s",' % scale_mode)
	lines.append('      "cover_behavior": "hide"')
	lines.append("    }")
	lines.append("  ],")
	lines.append('  "connection_mode": "%s",' % connection_mode)
	lines.append('  "exposed_top": "%s",' % exposed_top)
	lines.append('  "walk_surface_height": %.3f' % measured_walk_height)
	lines.append("}")
	return "\n".join(lines)


func to_dict() -> Dictionary:
	return {
		"tile_id": tile_id,
		"display_name": display_name,
		"recipe_path": recipe_path,
		"seed": seed_value,
		"variant": variant,
		"recipe_hash": recipe_hash,
		"baked_at": baked_at,
		"forge_version": forge_version,
		"triangles": triangle_count,
		"vertices": vertex_count,
		"surface_triangles": surface_triangle_count,
		"detail_triangles": detail_triangle_count,
		"materials": material_count,
		"materials_used": Array(materials_used),
		"nodes": node_count,
		"module_instances": module_instance_count,
		"bounds_min": [bounds_min.x, bounds_min.y, bounds_min.z],
		"bounds_max": [bounds_max.x, bounds_max.y, bounds_max.z],
		"walk_surface_height": measured_walk_height,
		"exposed_top": exposed_top,
		"shared_base_asset": shared_base_asset,
		"connection_mode": connection_mode,
		"collision_mode": collision_mode,
		"scale_mode": scale_mode,
		"passed": passed,
		"checks_run": checks_run,
		"errors": Array(errors),
		"warnings": Array(warnings),
	}
