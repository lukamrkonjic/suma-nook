@tool
class_name TileModuleEntry
extends Resource
## One reusable detail module: a grass clump, a pebble, a board, a rubble
## fragment. The mesh itself lives in tools/tile_forge/modules/<family>/ and is
## authored by art_source/blender/build_tile_forge_modules.py.
##
## Everything a placer needs to avoid floating, burying, or overlapping the
## module is declared here rather than measured from the mesh at bake time, so
## a recipe stays readable and a bad module is caught by validation instead of
## quietly producing a bad tile.

## res:// path to a .glb, .tscn, or .res holding one clean closed object.
@export_file("*.glb", "*.tscn", "*.res") var mesh_path := ""
## Relative selection weight inside its TileModuleSet.
@export_range(0.0, 8.0, 0.05) var weight := 1.0
## Semantic tags: "grass", "tall", "wide", "edge_safe", "flat"…
@export var tags: PackedStringArray = []

@export_group("Measured footprint")
## Radius of the module's ground contact, in LIVE metres at scale 1.0. Used for
## minimum separation and for keeping the module clear of the tile boundary.
@export var footprint_radius := 0.09
## Height above its ground-contact plane, in LIVE metres at scale 1.0.
@export var height := 0.08
## The module's origin must sit at its ground-contact centre. Set false only
## for a module that deliberately hangs (an overhang lip), and give it a
## negative `sink`.
@export var pivot_at_ground := true
## Push the module into the surface by this many metres, hiding the seam where
## a rounded base meets an uneven top. Small positive values only.
@export_range(-0.05, 0.06, 0.001) var sink := 0.006

@export_group("Allowed variation")
@export var scale_range := Vector2(0.85, 1.15)
@export var rotation_mode: TileForgeConstants.RotationMode = TileForgeConstants.RotationMode.FREE_YAW
## Maximum tilt away from vertical, degrees. Kept small: a leaning clump reads
## as a bug, not as character.
@export_range(0.0, 25.0, 0.5) var max_tilt_deg := 6.0

@export_group("Material")
## Slot this module's geometry is painted with. Overridden per placement when
## the detail rule declares material variant weights.
@export var material_slot := TileForgeConstants.SLOT_DETAIL_A


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func is_edge_safe() -> bool:
	return tags.has("edge_safe")


static func make(path: String, radius: float, tall: float, weight_value := 1.0) -> TileModuleEntry:
	var entry := TileModuleEntry.new()
	entry.mesh_path = path
	entry.footprint_radius = radius
	entry.height = tall
	entry.weight = weight_value
	return entry
