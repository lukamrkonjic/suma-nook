# Modly tree smoothing experiment — results

Date: 2026-07-26  
Blender: 5.2.0 LTS  
Smoothing: Shade Smooth by Angle, 40°, preserve existing sharp edges

## Result

**Recommendation: pipeline works with minor cleanup.**

The basic import → smooth → GLB export → fresh-scene re-import workflow is
reliable for both supplied trees. Smoothing survives export, materials and
embedded textures remain assigned, geometry counts and bounds are unchanged,
and the re-import renders are pixel-identical to the smoothed renders.

The assets are renderable as-is, but their centered pivots and highly
disconnected/open topology should be addressed before treating them as normal
game-ready placeables. Those issues were recorded and intentionally not
repaired in this surface-level test.

## Source preservation

| Asset | Original SHA-256 | Status |
|---|---|---|
| tree1 | `10D74D3E055181383EB3EF2D3C60F95570983502AF29A1973235B3A95B85BE4E` | unchanged |
| tree2 | `61ED960B9288BA7C7EDEA08BA288C26A6255F4CFD36518621DF4472531C6F90F` | unchanged |

Only copies under `source_copies/` were imported.

## Geometry and import inspection

| Check | tree1 | tree2 |
|---|---:|---:|
| Hierarchy | `world` Empty → `geometry_0` Mesh | `world` Empty → `geometry_0` Mesh |
| Mesh objects | 1 | 1 |
| Vertices | 2,531 | 2,815 |
| Faces / triangles | 2,500 / 2,500 | 2,500 / 2,500 |
| Connected components | 210 | 280 |
| Boundary / non-manifold edges | 2,182 | 2,590 |
| Invalid normals | 0 | 0 |
| Smooth faces before | 0 | 0 |
| Smooth faces after / after re-import | 2,419 / 2,419 | 2,348 / 2,348 |
| Dimensions | 0.560 × 0.509 × 1.000 | 0.755 × 0.418 × 1.000 |
| Object scale / rotation | 1,1,1 / 0,0,0 | 1,1,1 / 0,0,0 |
| Origin to lowest point | 0.500 | 0.500 |

### Materials and textures

Both assets import with:

- one assigned material;
- two embedded 1024×1024 textures;
- one sRGB color texture and one Non-Color data texture;
- no missing image nodes or external texture dependencies;
- material alpha 1.0.

The material imports as `DITHERED` despite being fully opaque. This is not
visibly broken in the test, but opaque mode would be preferable for sorting and
performance if these assets later become production content.

Blender emitted a sampler warning because the material uses more than one image
texture node. The fresh re-import retained both assignments and produced an
identical render, so it is not a blocking export defect in this test.

### Generation defects recorded

- Both tree origins are centered vertically instead of sitting at the base.
- Foliage/trunk geometry is consolidated into one mesh but consists of hundreds
  of disconnected components.
- Thousands of boundary/non-manifold edges indicate many open pieces. This is
  acceptable for simple static rendering, but poor input for remeshing, solid
  collision generation, boolean work, or physics-derived processing.
- No duplicate objects, extreme scales, broken normals, missing geometry,
  missing textures, or unexpected orientation were found.

## Visual assessment

Comparison images are left = original import, right = smoothed.

- **tree1:** noticeable improvement. Faceted noise across the foliage masses
  and trunk is reduced while the strong leaf undersides and silhouette remain.
- **tree2:** clear improvement. The broad foliage clumps and trunk read much
  cleaner; root and branch creases remain appropriately hard.

The experiment did not alter topology, silhouette, UVs, textures, proportions,
or pivot placement.

## Export validation

| Asset | Export | Result |
|---|---|---|
| tree1 | `exports/tree1_smooth_test.glb` | 2,500 triangles; material/textures/bounds preserved; smoothing survived |
| tree2 | `exports/tree2_smooth_test.glb` | 2,500 triangles; material/textures/bounds preserved; smoothing survived |

Both exports were re-imported into fresh scenes. Maximum dimension delta was
`0.0`, and smoothed-versus-re-import render pixel difference was `0.0`.

## Isolated Godot preview

The two smooth-test GLBs were also direct-loaded by
`tests/modly_blender_smoothing/GodotPreview.tscn` under Suma Nook's actual day
lighting:

| Asset | Target height | Uniform scale | Placement |
|---|---:|---:|---|
| tree1 | 2.0 m | ~2.000 | one plain moss tile |
| tree2 | 2.2 m | ~2.200 | one plain moss tile |

The preview compensates for each centered pivot at runtime, so the roots sit on
the tile cap without modifying the exported GLB. Both materials, textures and
shadows render correctly in Godot. Tree2 reads considerably darker/greener
under the game lighting than in Blender's neutral comparison; no material
correction was made, so the screenshots show the genuine imported result.

Screenshots:

- `godot_renders/modly_trees_moss_tiles.png`
- `godot_renders/tree1_moss_tile.png`
- `godot_renders/tree2_moss_tile.png`

## Isolation

No game registry, production asset directory, Godot import setting, build
script, procedural generator, or existing tree asset was changed. The whole
experiment can be removed by deleting `tests/modly_blender_smoothing/`.
