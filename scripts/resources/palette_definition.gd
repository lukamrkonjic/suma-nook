class_name PaletteDefinition
extends CozyPalette
## Named palette registry for the Garden Galaxy rework. Extends the legacy
## CozyPalette shape (colors + character arrays, so existing systems keep
## working) and adds authoritative screen-space render targets.
##
## `colors`         — SOURCE albedos authored into materials.
## `render_targets` — what the same named surface should measure on screen
##                    under the GG day rig. When lighting drifts a surface off
##                    target, tune the source albedo and record both here —
##                    never stack color grading on top.

@export var render_targets: Dictionary = {}


func render_target(key: String) -> Color:
	return render_targets.get(key, Color.MAGENTA)
