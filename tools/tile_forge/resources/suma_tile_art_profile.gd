@tool
class_name SumaTileArtProfile
extends Resource
## The single art-direction contract every Tile Forge generator obeys.
##
## Before this existed each generator carried its own idea of how thick a bevel
## should be and how large a detail had to read, and the result was ten tiles
## that shared no visual language. Nothing may hard-code a bevel width, a relief
## amplitude, or a detail size again: it comes from here, so changing the look
## of the whole collection is one resource edit.
##
## UNITS. Every value is in LIVE metres — the space the game renders, where a
## tile is 1.35 m across. The art brief was written against the 1.70 m authored
## footprint, so each field notes its authored equivalent; the conversion factor
## is LIVE_TILE_SIZE / AUTHORED_TILE_SIZE = 0.794.
##
## The target is a small handcrafted collectible object: broad closed volumes,
## real chamfers that catch a highlight, restrained palettes, and composed
## negative space. Not a coloured cube with objects sprinkled on it.

@export var profile_id := "suma_diorama"

@export_group("Structural block")
## Chamfer along the top perimeter. This is the single most important value in
## the profile: without it every tile reads as an untreated cube, and with too
## much of it neighbouring tiles form a dark trench instead of a soft seam.
## Authored 0.035–0.055 m.
@export_range(0.0, 0.08, 0.001) var top_bevel := 0.034
@export_range(1, 4, 1) var top_bevel_segments := 2
## Chamfer along the bottom perimeter, so a tile lifts off its neighbour
## instead of welding to it. Authored 0.015–0.025 m.
@export_range(0.0, 0.05, 0.001) var bottom_bevel := 0.016
@export_range(1, 3, 1) var bottom_bevel_segments := 1
## How far the side wall descends from the walk plane before the shared block
## takes over.
@export var block_depth := TileForgeConstants.BLOCK_DEPTH

@export_group("Organic relief")
## Peak-to-trough amplitude a broad organic top should aim for. Authored
## 0.025–0.10 m. Below the minimum a tile is a flat slab; above the maximum it
## stops reading as one clean block.
@export_range(0.005, 0.12, 0.001) var relief_min := 0.022
@export_range(0.01, 0.14, 0.001) var relief_max := 0.075
## How many macro forms a healthy organic top uses. More than four and they
## stop being readable as deliberate shapes.
@export_range(1, 6, 1) var macro_forms_min := 2
@export_range(1, 8, 1) var macro_forms_max := 4
## Each macro form must span at least this fraction of the tile. A primitive
## smaller than this is a bump, not a form.
@export_range(0.1, 1.0, 0.01) var macro_form_min_span := 0.42

@export_group("Detail scale")
## Readable detail footprint at the gameplay camera. Authored 0.16–0.42 m.
@export_range(0.05, 0.5, 0.005) var detail_width_min := 0.13
@export_range(0.05, 0.6, 0.005) var detail_width_max := 0.33
## Authored 0.07–0.22 m.
@export_range(0.02, 0.3, 0.005) var detail_height_min := 0.055
@export_range(0.02, 0.4, 0.005) var detail_height_max := 0.175
## Anything narrower than this becomes a dot at gameplay distance and must be
## removed, merged into a larger clump, or scaled up. The validator enforces it.
@export_range(0.02, 0.25, 0.005) var detail_readable_minimum := 0.085

@export_group("Detail rounding")
## Chamfer on a detail module. Authored 0.012–0.03 m.
@export_range(0.0, 0.05, 0.001) var detail_bevel := 0.016
@export_range(1, 3, 1) var detail_bevel_segments := 2
## Faces meeting below this angle are smoothed; above it the edge stays hard.
## This is what gives a chunky form soft barrel shading without melting its
## silhouette.
@export_range(10.0, 80.0, 1.0) var smooth_angle_deg := 46.0

@export_group("Composition")
## Fraction of the tile that should carry visible broad form, per density band.
## Coverage means broad form, not object count: five large clumps beat thirty
## small ones at the same number.
@export var coverage_smooth := Vector2(0.0, 0.10)
@export var coverage_sparse := Vector2(0.15, 0.25)
@export var coverage_ordinary := Vector2(0.25, 0.40)
@export var coverage_lush := Vector2(0.40, 0.60)
@export var coverage_dense := Vector2(0.55, 0.75)
## Every composition needs one dominant form. This is how much larger the hero
## should be than its supporting pieces.
@export_range(1.0, 2.5, 0.05) var hero_scale := 1.35
@export_range(0.4, 1.0, 0.05) var support_scale := 0.92
@export_range(0.3, 0.9, 0.05) var accent_scale := 0.68

@export_group("Material language")
## How much darker a side wall is than the top it belongs to. Authored guidance
## is 10–18%: past that the block gains a black outline and stops reading as one
## object.
@export_range(0.04, 0.30, 0.01) var side_darken := 0.14
## Inset and cavity interiors sit a little deeper still.
@export_range(0.05, 0.40, 0.01) var inset_darken := 0.22
@export_range(0.4, 1.0, 0.01) var roughness := 0.95
@export_range(0.0, 0.5, 0.01) var specular := 0.16
## Terrain is never metallic.
@export_range(0.0, 1.0, 0.01) var metallic := 0.0


static func default() -> SumaTileArtProfile:
	var path := "res://tools/tile_forge/materials/suma_tile_art_profile.tres"
	if ResourceLoader.exists(path):
		var loaded: Variant = ResourceLoader.load(path)
		if loaded is SumaTileArtProfile:
			return loaded
	return SumaTileArtProfile.new()


## Clamps a requested relief amplitude into the approved band, so a recipe
## cannot quietly flatten a tile or turn it into a hill.
func clamp_relief(value: float) -> float:
	var magnitude: float = clampf(absf(value), relief_min, relief_max)
	return magnitude if value >= 0.0 else -magnitude


func is_detail_readable(width: float) -> bool:
	return width >= detail_readable_minimum


func coverage_for(band: String) -> Vector2:
	match band:
		"smooth": return coverage_smooth
		"sparse": return coverage_sparse
		"lush": return coverage_lush
		"dense": return coverage_dense
	return coverage_ordinary


## Side-wall colour derived from the top it belongs to, rather than picked from
## an unrelated part of the palette. A green tile gets a green wall; the earthy
## brown wall under a green top is what made every tile read as two objects.
func side_colour(top: Color) -> Color:
	return _shade(top, side_darken)


func inset_colour(top: Color) -> Color:
	return _shade(top, inset_darken)


## Darkens towards a warm neutral rather than towards black, so a shaded face
## keeps its hue and never turns into an outline.
func _shade(colour: Color, amount: float) -> Color:
	var target := Color(colour.r * 0.55, colour.g * 0.52, colour.b * 0.46)
	return colour.lerp(target, clampf(amount / 0.5, 0.0, 1.0))
