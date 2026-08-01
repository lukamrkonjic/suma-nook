@tool
class_name GrassClearance3D
extends Marker3D
## Marks a spot where the grass field must open up for something else — a bench
## footing, a path node, a pond rim, a placed prop.
##
## Two failure modes this exists to avoid. First, punching a hole by deleting
## instances leaves a hard circular edge that reads as a stamped cut-out, so the
## clearance is a WEIGHT with a soft rim rather than a boolean test. Second, a
## fully cleared spot exposes bare surface mesh under a prop, which looks like a
## missing asset; retain_dense_carpet keeps a thin plush layer alive right
## through the centre so the ground never goes bald — only the taller flexible
## tufts vacate completely.
##
## Generators query these markers in WORLD space and multiply the result into
## their density field. Nothing here knows about the logical tile grid, so a
## clearance may sit anywhere and straddle any number of cells.

## Radius in metres at which grass is fully restored. Around 0.40 m clears a
## typical prop footing without visibly thinning the field around it.
@export var radius := 0.40
## Fraction of the dense micro-tuft carpet retained at the very centre. Zero
## would expose the surface mesh under whatever sits here.
@export_range(0.0, 1.0, 0.01) var retain_dense_carpet := 0.15
## Fraction of the radius spent fading from cleared to full, so the rim is a
## gradient rather than a cut line. 0.25 puts the inner edge at 0.75 * radius.
@export_range(0.0, 1.0, 0.01) var edge_softness := 0.25


## Grass retention in 0..1 for a world XZ position: 0 inside the clearance,
## 1 outside it, smoothly interpolated across the soft rim.
##
## Static and pure so density passes can evaluate thousands of samples against a
## snapshot of the markers without touching the scene tree — and so the same
## falloff is used by every caller instead of each one inventing its own.
static func clearance_weight(
	world_xz: Vector2,
	clearance_position: Vector2,
	radius_metres: float,
	softness: float
) -> float:
	var outer := maxf(radius_metres, 0.001)
	var inner := outer * (1.0 - clampf(softness, 0.0, 1.0))
	var distance := world_xz.distance_to(clearance_position)
	# smoothstep, not a linear ramp: the eased ends mean the fade has no visible
	# start or finish, which is what keeps the rim from reading as a circle.
	return smoothstep(inner, outer, distance)


## This marker's retention weight for the flexible tuft layer, which clears
## completely.
func weight_at(world_xz: Vector2) -> float:
	var origin := global_position if is_inside_tree() else position
	return clearance_weight(world_xz, Vector2(origin.x, origin.z), radius, edge_softness)


## This marker's retention weight for the dense carpet, floored so the ground
## keeps a plush layer even at the centre.
func dense_weight_at(world_xz: Vector2) -> float:
	return lerpf(clampf(retain_dense_carpet, 0.0, 1.0), 1.0, weight_at(world_xz))
