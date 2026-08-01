# Garden Galaxy tile capability audit

This is a derived implementation inventory, not an asset dump. No meshes,
textures, serialized prefabs, or other private evidence are copied into Suma.

## Scope

The local technical-audit export contains 44 ground/tile definitions backed by
36 unique ground meshes. Across those definitions, the recurring authoring
signals are:

- 23 custom stacking-rule components
- 20 plant-base components
- 17 variation cyclers
- 15 surface togglers
- 8 grass-particle systems (30 pieces each)
- 7 water-base components
- 6 ground-surface-object components
- 6 solid-water components
- 4 general ground-particle systems (30–40 pieces each)
- 3 tile-side togglers
- 3 waterfall case/fall systems
- 2 connection-aware fringe systems

The hierarchy scan covered 439 nodes, 1,522 components, 110 mesh
filter/renderers, and 252 particle systems. The important result is qualitative:
the complex tiles are compositions of small reusable systems, not uniquely
modeled snow, leaf, pond, and path editors.

## Reusable construction families

| Observed family | Tile Kit capability | Generic authoring surface |
|---|---|---|
| Flat terrain, soft relief, dunes, heaps, furrows | Foundation & Relief | profile, amount, scale, resolution, edge blend, direction |
| Depressed pond/wet ground | Foundation basin | depth, rim width, water level |
| Grass and moss carpets | Organic Carpet | density, gaps, placement jitter, leaves per sprout, size, splay, bend |
| Chips, leaves, stones, snow lumps, flowers | Surface Scatter | multi-shape content, amount range, size range, height, spacing, attraction |
| Soil/mud/moss colour breakup | Surface Patches | amount by size, region count/spread, overlap, irregularity |
| Paving, brick, cobble, decking, stepping stones | Patterned Surface | pattern, cell/board dimensions, joints, jitter, height, roundness |
| Soil-bed, bank, and pond perimeter pieces | Connection Fringe | edges, adjacency suppression, amount, size, gaps, jitter |
| Ponds, solid water, waterfalls | Liquid Surface | top level/inset plus selected fall edges, width, and distance |
| Fenced/bordered ground | Edge Border | selected edges, inset, post/rail spacing and dimensions |

## Editor design rule

Tile recipes contain an ordered stack of those capabilities. The inspector is
generated from each capability's declarative parameter schema. It may offer
generic templates, but it must never branch on a stable tile ID or display name.
That keeps a leaf-covered snow tile, a mossy waterfall, or a post-launch content
family possible without adding another special-case panel.

Layout randomization and parameter variation are separate operations. Content
selection (for example leaves + twigs) is preserved when numeric settings are
varied, so the randomizer cannot silently turn one authored family into another.
