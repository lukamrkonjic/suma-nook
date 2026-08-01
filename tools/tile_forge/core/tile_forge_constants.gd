@tool
class_name TileForgeConstants
extends RefCounted
## The single source of truth for every dimension, enum, and slot name the
## Tile Forge uses. Values are taken from the shipped Suma contract documented
## in docs/TILE_AUTHORING.md; nothing here invents a new tile size.
##
## Two spaces exist and must never be confused:
##
##   LIVE space     the space the game actually renders. Half extent 0.675 m
##                  (tile_size 1.35). Every generator works here, because this
##                  is the scale at which readability is judged.
##   AUTHORED space the 1.70 m space the shipped GLB catalog was built in.
##                  `TileVisualFactory` multiplies X/Z of a `tile_xz` layer by
##                  live/authored. TileBaker converts a surface layer into this
##                  space exactly once so the runtime scale lands on 1.35.
##
## Detail layers are baked in LIVE space and declared `scale_mode: "none"`, so
## modules are never non-uniformly squashed by the runtime X/Z scale.

## Authored footprint of the shipped GLB catalog (docs/TILE_AUTHORING.md).
const AUTHORED_TILE_SIZE := 1.70
## Live grid size (data/tuning.json::tile_size).
const LIVE_TILE_SIZE := 1.35
const LIVE_HALF_EXTENT := LIVE_TILE_SIZE * 0.5
## Universal stacking step (data/tuning.json::block_depth).
const BLOCK_DEPTH := 0.5

## Shared structural bases already shipped by Suma.
const BASE_STANDARD_ASSET := "tile_layer_base_standard"
const BASE_DEEP_RECESS_ASSET := "tile_layer_base_deep_recess"
## Seam where a standard base ends and a surface skin begins.
const SEAM_STANDARD := -0.055
## Seam for constructed caps with readable thickness.
const SEAM_DEEP_RECESS := -0.18
## Walk/support plane.
const GROUND_PLANE := 0.0
## Hard ceiling for `exposed_top: "raised"` relief (docs/TILE_AUTHORING.md).
const MAX_RAISED_TOP := 0.35
## Floor for `exposed_top: "recessed"` tops.
const MIN_RECESSED_TOP := -0.18

## Gameplay camera, mirrored from data/tuning.json so the lab is honest.
const CAMERA_FOV_DEG := 15.0
const CAMERA_PITCH_DEG := -40.0
const CAMERA_YAW_DEG := 45.0
const CAMERA_DEFAULT_SIZE := 37.0

## Where baked output lands. Registered into AssetLibrary.SEARCH_PATHS so a
## baked tile is addressable by plain asset id from data/tiles.json.
const BAKED_DIR := "res://tools/tile_forge/baked"
const MODULE_DIR := "res://tools/tile_forge/modules"
const RECIPE_DIR := "res://tools/tile_forge/recipes"


## Canonical material slot names. A recipe names slots; a TilePalette binds
## each slot to a semantic key in assets/palettes/gg_material_palette.tres.
## Adding a slot here is additive and never breaks an existing palette.
const SLOT_TOP_PRIMARY := "top_primary"
const SLOT_TOP_SECONDARY := "top_secondary"
const SLOT_ACCENT := "accent"
const SLOT_SHADOW := "shadow"
const SLOT_SIDE := "side"
const SLOT_UNDERSIDE := "underside"
const SLOT_INSET := "inset"
const SLOT_WATER := "water"
const SLOT_DETAIL_A := "detail_a"
const SLOT_DETAIL_B := "detail_b"
const SLOT_DETAIL_C := "detail_c"

const ALL_SLOTS: PackedStringArray = [
	SLOT_TOP_PRIMARY,
	SLOT_TOP_SECONDARY,
	SLOT_ACCENT,
	SLOT_SHADOW,
	SLOT_SIDE,
	SLOT_UNDERSIDE,
	SLOT_INSET,
	SLOT_WATER,
	SLOT_DETAIL_A,
	SLOT_DETAIL_B,
	SLOT_DETAIL_C,
]


## Recipe categories.
enum Category {
	ORGANIC_SURFACE,
	CONSTRUCTED_SURFACE,
	SURFACE_WITH_DETAILS,
	DETAIL_ONLY,
	RECESSED_SURFACE,
	WATER_SURFACE,
	CUSTOM_STRUCTURAL,
}

## How a surface layer's height contribution combines with what is beneath it.
enum Blend {
	ADD,
	SUBTRACT,
	MAX,
	MIN,
	REPLACE,
	SMOOTH_ADD,
	SMOOTH_SUBTRACT,
}

## Analytic macro-shape families. These, not noise, are the shape source.
enum Shape {
	MOUND,
	BROAD_MOUND,
	RIDGE,
	WAVE,
	DRIFT,
	PLATEAU,
	BOWL,
	DEPRESSION,
	TRENCH,
	STEP,
	CORNER_RISE,
	EDGE_RISE,
	FLATTEN_REGION,
}

enum Falloff { SMOOTHSTEP, LINEAR, GAUSSIAN, COSINE, PLATEAU_EDGE }

## How a layer treats the shared tile boundary.
enum BorderPolicy {
	## Height returns to the connected boundary height inside the edge-lock
	## band. This is the default for anything that tiles with a neighbour.
	EDGE_LOCK,
	## No boundary constraint. Only legal on an isolated/inset surface.
	FREE,
	## Layer is confined inside an inset region and never reaches the border.
	INSET,
}

## Neighbour edge behaviour.
enum EdgePolicy {
	CONNECTED_SAME_SURFACE,
	CONNECTED_TRANSITION,
	HARD_STRUCTURAL_EDGE,
	INSET_SURFACE,
	CLIFF_OR_DROP,
	CUSTOM,
}

## Authored placement compositions. Never plain uniform scatter.
##
## Every template names a focal region, supporting regions, and deliberate empty
## regions, and assigns each anchor a ROLE so the placer can size it. That is
## what makes a generated arrangement look manually composed: not the positions,
## but the fact that one form is clearly the subject and the rest defer to it.
enum Composition {
	CENTRAL_FOCUS,
	THREE_CLUSTERS,
	FOUR_CORNERS_WITH_GAPS,
	DIAGONAL_FLOW,
	EDGE_BIASED,
	PATCHES,
	RING,
	SPARSE_ACCENTS,
	DENSE_FIELD_WITH_CLEARINGS,
	CUSTOM_ANCHORS,
	## The seven authored templates the art direction calls for.
	ONE_HERO_TWO_SUPPORT,
	THREE_ASYMMETRIC_CLUSTERS,
	EDGE_CLUSTER_WITH_OPEN_CENTRE,
	DENSE_CORNER_SPARSE_OPPOSITE,
	FOUR_LARGE_PATCHES,
	BROAD_FIELD_WITH_TWO_CLEARINGS,
}

## Size and prominence tier of one placed form.
enum Role { HERO, SUPPORT, ACCENT }

enum DetailOutput {
	## One node per module. Debug only — never ship this.
	INDIVIDUAL_DEBUG_NODES,
	## All modules of one slot merged into one MeshInstance3D. The production
	## default for Suma: WorldRenderer already batches whole tiles into chunk
	## MultiMeshes, and `AssetLibrary.flatten_static_visual` only walks
	## MeshInstance3D, so merged static detail is what actually reaches the
	## world batcher.
	MERGED_STATIC_MESH,
	## Per-tile MultiMesh. Correct for standalone/large-field use; it is NOT
	## picked up by Suma's chunk batcher or cover-fade, so the validator warns.
	MULTIMESH,
	## Kept on its own node so a caller can render or cull it separately.
	SEPARATE_RENDER_LAYER,
}

enum RotationMode { FREE_YAW, QUARTER_TURNS, FIXED, YAW_FROM_FLOW }

enum CollisionMode { FLAT_BOX, NONE, RIM_BOX, FROM_HEIGHTFIELD_MEDIAN }

enum BaseMode { SHARED_STANDARD, SHARED_DEEP_RECESS, GENERATED, NONE }

## What a generator contributes. A generator may declare more than one.
enum Kind { HEIGHTFIELD, MESH, INSTANCE }


static func category_name(value: int) -> String:
	return Category.keys()[clampi(value, 0, Category.size() - 1)]


static func exposed_top_for(min_y: float, max_y: float) -> String:
	## Mirrors the docs/TILE_AUTHORING.md rule: `exposed_top` describes the
	## highest usable surface, not the lowest groove.
	if max_y > 0.004:
		return "raised"
	if max_y < -0.004 and min_y < -0.004:
		return "recessed"
	return "flush"
