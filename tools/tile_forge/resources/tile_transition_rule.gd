@tool
class_name TileTransitionRule
extends Resource
## How this tile behaves along one edge when the neighbour is a different
## surface family.
##
## Suma does not blend materials automatically. Two different surfaces meeting
## is a DESIGN event: either they simply butt together (the default, and what
## the reference does), or an explicit transition recipe is placed between
## them. This resource records which, plus the optional edge dressing that
## makes the join deliberate rather than accidental.

## "north" | "east" | "south" | "west" | "any"
@export var edge := "any"
## Which neighbouring surface family this rule answers. Empty matches all.
@export var neighbour_family := ""

@export var policy: TileForgeConstants.EdgePolicy = TileForgeConstants.EdgePolicy.CONNECTED_SAME_SURFACE

@export_group("Geometry")
## Width of the band, normalized, over which this tile's height converges to
## the neighbour's boundary height.
@export_range(0.0, 0.5, 0.01) var blend_width := 0.2
## Boundary height this edge must meet, metres. Only meaningful when the
## neighbour is a different height contract.
@export var edge_height := 0.0

@export_group("Dressing")
## Optional modules scattered along the join (a sod lip, a gravel fringe, a
## line of pebbles). Kept sparse — a decorated seam on every edge reads as a
## grid, which is the exact failure the brief calls out.
@export var edge_modules: TileModuleSet
@export_range(0, 12, 1) var edge_module_count := 0
## Modules used here must be tagged "edge_safe"; the validator enforces it.
@export var require_edge_safe := true


func matches(edge_name: String, family: String) -> bool:
	var edge_ok := edge == "any" or edge == edge_name
	var family_ok := neighbour_family == "" or neighbour_family == family
	return edge_ok and family_ok


## Whether this edge must lock its boundary height to a shared value.
func requires_edge_lock() -> bool:
	return (
		policy == TileForgeConstants.EdgePolicy.CONNECTED_SAME_SURFACE
		or policy == TileForgeConstants.EdgePolicy.CONNECTED_TRANSITION
	)
