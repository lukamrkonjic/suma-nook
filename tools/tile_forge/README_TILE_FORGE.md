# Suma Tile Forge

Procedural tile authoring for Suma. This document records the **current** state
honestly, including what is not yet approved.

## The correction that matters

The first two attempts rendered **one visible block per logical cell**. A field
of grass therefore read as a grid of dark cubes, and no amount of bevelling or
recolouring could fix it. The architecture is now:

> **A logical tile is not a visible block.**

| Concern | Owner |
|---|---|
| placement, snapping, saving, collision, neighbour detection | the logical 1.35 m cell (invisible) |
| the continuous visible top | `SurfaceCap` — one per cell, reaching the **exact** cell boundary with no perimeter treatment |
| vertical terrain sides | `EdgeSkirt` / `EdgeCorner` — built **only** where a cell has no compatible neighbour |
| readable forms on the surface | `SurfaceDetails` — Blender-authored modules |
| physics | one flat box per cell, independent of all decorative geometry |

Internal side geometry is never built. Two caps meet with zero gap, no bevel,
no border and no seam, so a connected region reads as one continuous surface.
Only the outside perimeter of a region shows vertical terrain.

### Units

Everything is authored in **LIVE metres**: Suma's grid cell is 1.35 m
(`data/tuning.json::tile_size`). The art brief quotes its figures against the
1.70 m authored catalog footprint, so every value is the brief's number scaled
by `1.35 / 1.70 = 0.794`:

| Value | Brief (1.70 m) | Authored (1.35 m) |
|---|---:|---:|
| visible terrain side height | 0.18–0.24 | **0.170** |
| exposed top rounding | 0.035–0.055 | **0.036** |
| exposed lower rounding | 0.015–0.025 | **0.016** |
| bevel segments | 2–3 | **3** |
| internal connected edge | no bevel, no gap | no bevel, no gap |

## Current status

| Master | Gate |
|---|---|
| `master_soft_pavers` | **passes** — warm greige, handcrafted silhouettes, continuous field, clean clay read, attractive island edge |
| `master_wood_planks` | **borderline** — boards fuse across cells and the deck is continuous, but the clay pass is a plain ribbed sheet and tone changes still cluster per cell |
| `master_grass_lush` | **not approved** — no cell grid remains and clumps now read as lit masses, but a 5×5 still reads as a speckled field rather than one lush patch |

Nothing beyond these three exists yet. Sand, snow, straw, water, dirt and
rubble are deliberately not started.

## Building

```bash
C:/Software/Blender/blender.exe --background --factory-startup --python art_source/blender/build_tile_masters.py
```

Exports to `tools/tile_forge/masters/` and `tools/tile_forge/modules/`:

* `master_<family>_<nn>.glb` — complete cap + details for one authored layout
* `master_<family>_skirt.glb` — one straight exposed-edge skirt, authored along +Z
* `master_<family>_corner.glb` — the outside corner for two adjacent exposed edges
* `gf_clump_*`, `gf_paver_*`, `gf_board_*` — the extracted reusable modules
* `master_report.json` — dimensions, triangle counts, and per-module bounds

Then render the validation matrix:

```bash
C:/Dev/Godot/Godot_v4.6.3-stable_win64_console.exe --headless --path . --import
```

```bash
C:/Dev/Godot/Godot_v4.6.3-stable_win64_console.exe --path . --resolution 1400x1000 tools/tile_forge/editor/master_review.tscn -- --shot-dir=<absolute folder>
```

`master_review.gd` assembles a region from caps plus perimeter-only skirts and
captures eight passes per family: single, gameplay camera, 3×3, 5×5, clay,
island edge, interior seam, wireframe. The clay pass exists so geometry is
judged with no colour to hide behind.

## Previewing in-game

The three masters are registered as ordinary layered tiles so the Asset Studio
can show them under a **Tile Forge** group:

| id | base layer | surface layer |
|---|---|---|
| `tile_master_grass` | `tile_layer_base_master_grass` | `tile_layer_surface_master_grass` |
| `tile_master_pavers` | `tile_layer_base_master_pavers` | `tile_layer_surface_master_pavers` |
| `tile_master_wood` | `tile_layer_base_master_wood` | `tile_layer_surface_master_wood` |

They are listed in `data/tuning.json::preview_tile_ids`, **not**
`active_tile_ids`. `Registries.viewable_tile_ids()` returns both and only the
Asset Studio calls it, so this art can be inspected under real lighting without
entering parcel rolls, the Build Bag, or collection totals. Promote a tile by
moving its id between the two lists.

Both layers declare `scale_mode: "none"` because they are authored at the live
1.35 m grid rather than the catalog's 1.70 m. The slot-fill test now reads the
layer's scale mode instead of assuming the authored size.

These game-tile exports carry a perimeter skirt on **all four** sides, because
Suma's `WorldRenderer` has no edge mask yet. That is the interim form — placing
two next to each other still shows an internal side. The master pieces in
`tools/tile_forge/masters/` are the real target and have no such skirt.

## Module rules

Every Blender module is a closed volume with applied transforms and its origin
at the ground-contact centre. Chamfers are built as explicit rings rather than
with the bevel modifier — the modifier tripled triangle counts on an already
rounded outline for no visible gain at tile scale. Shading is declared per
face: barrels smooth, caps and chamfers flat.

Forbidden, because each was tried and rejected on sight: cards, spikes, needle
tips, per-vertex noise, untouched primitive silhouettes, and any tone that puts
a dark outline around a form.

Two rules exist purely to keep repeated regions clean:

* **Board ends are square.** Rounding them put a bright lip at every cell
  boundary and exposed the grid across a deck.
* **Paver irregularity is inward only.** Outward jitter pushed stones into the
  joint and made neighbouring cells overlap.

## Composition

Twelve authored grass layouts live in `GRASS_LAYOUTS`. Each names explicit
`(u, v, module, scale, yaw)` placements with one dominant cluster, supporting
groups and deliberate open space. `master_review.gd` selects one per cell from
the tile coordinate using offsets coprime with the layout count, so the same
arrangement can never land beside itself. There is no uniform random scatter
anywhere in the pipeline.

## What remains

1. Land the grass master (density reads as speckle at region scale; the cap's
   two broad tones are not carrying enough value structure).
2. Move wood tone variation from per-cell to per-plank-run in world space.
3. Only then port the cap/skirt/edge-mask model back into `TileForgeBuilder`
   and re-enable recipe-driven generation.

The generator, resource, validator and baker code under `core/`, `resources/`
and `generators/` still reflects the earlier one-block-per-cell model and must
be reworked against the architecture above before it is used again.
