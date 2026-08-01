# Tile Forge bake report

Generated 2026-07-31T19:54:18 by Tile Forge 1.0.0.

## Registered generators

| id | kinds | purpose |
|---|---|---|
| `basin` | HEIGHTFIELD, MESH | Carves a well, pool, or framed inset into the shared top and emits its water plane separately. |
| `board_pattern` | MESH | Plank decking that tiles seamlessly: docks, bridges, boardwalks, wooden floors. |
| `clump_field` | INSTANCE | Upright vegetation clumps with a sunlit-crown accent bias. |
| `custom_mesh` | MESH | Bakes a hand-modelled mesh into the tile, policed by the same footprint and slot rules as procedural geometry. |
| `drift` | HEIGHTFIELD | Synthesised dune field: unevenly spaced asymmetric crests with hollows between. |
| `flat_surface` | HEIGHTFIELD | Constant-height top with an optional two-region colour split. |
| `heightfield_surface` | HEIGHTFIELD | Organic top from broad shape primitives, with optional sub-centimetre softening. |
| `module_layout` | MESH | Constructed surface assembled from curated Blender modules at authored positions. |
| `paver_pattern` | MESH | Authored paving templates — quad slabs, running bond, basketweave, grid, or mixed — extruded as chunky stone with restrained edges. |
| `pebble_field` | INSTANCE | Resting pebbles and gravel, size-graded outwards from each cluster. |
| `rubble_field` | INSTANCE | Angular debris at readable settle angles, culled to legible clusters. |

## Baked tiles

| tile | tris | surface | detail | mats | nodes | modules | walk y | exposed top | result |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| `golden_grass_lush` | 2382 | 336 | 2046 | 5 | 7 | 11 | 0.000 | raised | PASS |
| `golden_soft_pavers` | 202 | 202 | 0 | 4 | 6 | 0 | 0.030 | flush | PASS |
| `golden_wood_planks` | 158 | 158 | 0 | 3 | 6 | 0 | 0.028 | flush | PASS |

### golden_grass_lush

- warning 2382 triangles is heavy for one tile

## data/tiles.json fragments

```json
{
  "id": "tile_golden_grass_lush",
  "name": "Lush Meadow",
  "asset_id": "golden_grass_lush",
  "render_profile": "layered",
  "layers": [
    {
      "role": "surface",
      "asset_id": "golden_grass_lush",
      "scale_mode": "none",
      "cover_behavior": "hide"
    }
  ],
  "connection_mode": "full_flush",
  "exposed_top": "raised",
  "walk_surface_height": 0.000
}
```
```json
{
  "id": "tile_golden_soft_pavers",
  "name": "Soft Pavers",
  "asset_id": "golden_soft_pavers",
  "render_profile": "layered",
  "layers": [
    {
      "role": "surface",
      "asset_id": "golden_soft_pavers",
      "scale_mode": "none",
      "cover_behavior": "hide"
    }
  ],
  "connection_mode": "tiny_individual_seam",
  "exposed_top": "flush",
  "walk_surface_height": 0.030
}
```

```json
{
  "id": "tile_golden_wood_planks",
  "name": "Plank Deck",
  "asset_id": "golden_wood_planks",
  "render_profile": "layered",
  "layers": [
    {
      "role": "surface",
      "asset_id": "golden_wood_planks",
      "scale_mode": "none",
      "cover_behavior": "hide"
    }
  ],
  "connection_mode": "tiny_individual_seam",
  "exposed_top": "flush",
  "walk_surface_height": 0.028
}
```
