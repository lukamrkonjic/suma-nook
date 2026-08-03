# Tile Art System V2 — architecture

Status: authority doc for the V2 tile art rework (branch `codex/tile-art-v2`).
Scope: the sculpt-first tile generator, the five vertical-slice prototypes,
editor + review tooling, catalogue/migration policy, and tests.

Guiding rule: **sculpt the material — do not decorate a cube.**

## 1. Diagnosis of V1 (Tile Kit)

V1 (`tools/tile_kit/`) is a layered decorator: one universal base slab
(`KitBaseBuilder`, stacking contract 1.70 m footprint, body −0.50..−0.18,
cap −0.18..0, flat walk plane y=0) plus dressing/clutter/grass layers
scattered across it. Every preset in `tile_kit_preset.gd` is
`reference_clean_grass()` with parameter merges — same silhouette, different
sprinkles. Structural reasons the look cannot get past "decorated slab":

- `KitBaseBuilder._relief_function` **feathers all relief to dead flat at the
  bevel rim** — every tile shares one authored slab silhouette by design.
- Relief renders as a *blanket* mesh floating a hair above a still-flat cap;
  the sculpt is never the surface itself.
- Detail layers place via Poisson-ish scatter with per-piece random colour
  weights; composition is a density knob, not an arrangement.
- The palette leans on `tilekit_tile_top_bevel` lime and a red-orange
  `tilekit_sand_side` seam — the exact "fluorescent lime / harsh red seam"
  failures.

## 2. Reusable infrastructure (kept)

- `TileKitMeshUtils.MeshBatch` / `SurfacePool` — per-palette-key surface
  accumulation, one ArrayMesh, documented clockwise-front-face winding.
- The layered runtime contract: `base` (persists covered) / `surface` /
  `detail` roles, `bake_role_scenes()` shape, `AssetLibrary.SEARCH_PATHS`
  resolution of `tools/tile_kit/baked/*.tscn`, X/Z-only runtime scaling from
  the authored 1.70 m (`TileVisualFactory.AUTHORED_TILE_SIZE`).
- `WorldGrid` (pure data), `Registries` atomic snapshot + validators,
  `ScalableWorldBackend` chunked MultiMesh batching, profile-driven collision.
- Library lifecycle: `tile_library_manifest.gd`, `tile_catalog_compiler.gd`,
  `tile_library_service.gd` (stable IDs, provenance, release guard).
- Review rig pattern (`tools/tile_kit/review/tile_kit_review.gd`): root
  viewport ortho 45°/−35.264°, `_calibrate_width`, hdr_2d-safe `_shoot`
  (convert RGBA8 → `linear_to_srgb` before save).
- `PaletteDefinition` design system: all colours are semantic tokens in
  `assets/palettes/gg_material_palette.tres`; builders never construct RGB.
- `BuildThumbnailRenderer` — thumbnails always render the production visual.

## 3. Parts that enforced the old look (replaced in V2)

- The universal slab + relief-blanket construction (see §1).
- Clutter/dressing scatter as the identity of a material.
- 16-topology `_n%02d` bake as a hard requirement (V2 prototypes are
  authored blocks — `connection_mode: ""` — and the runtime already falls
  back gracefully when no topology variant exists).
- Lime/red palette relationships (V2 tokens are `tilev2_*`).

## 4. V2 architecture (`tools/tile_kit/v2/`)

Separation of responsibilities, one module each:

| Module | File | Responsibility |
| --- | --- | --- |
| Recipe data | `tile_v2_recipe.gd` | versioned Resource (`recipe_version = 2`): body profile, macro ops, structure templates, accents, edge behaviour, palette roles, finish, variants |
| Field engine | `tile_v2_field.gd` | deterministic 2.5D sculpt field: authored primitives (dome, dune ridge, plateau, basin, ramp, swell) composed with smooth-max/min; paint field resolves a palette key everywhere |
| Mesher | `tile_v2_mesher.gd` | samples the field on a clipped grid, welds a per-material side skirt (body bands, lip, overhang, substrate reveal), buckets triangles per palette key, splits base/surface at the −0.18 seam, computes stats |
| Structures | `tile_v2_structures.gd` | discrete chunky pieces (bark chips…) placed by curated cluster templates, settled *into* the field surface |
| Palette | `tile_v2_palette.gd` | semantic V2 roles → `tilev2_*` tokens; matte clay materials; preview override hook |
| Library | `tile_v2_library.gd` | the five authored prototype recipes + their curated variants |
| Generator | `tile_v2_generator.gd` | `@tool` Node3D preview/bake host, parallel to `TileKitGenerator`; `bake_role_scenes()` compatible |
| Review | `review/tile_v2_review.gd` | acceptance renders: contact sheet, 128 px thumbnails, silhouette, grayscale, 3×3 adjacency, variants, before/after |

### Key construction ideas

- **The sculpt is the surface.** One height field `h(x, z)` per tile composed
  from authored primitives; the top mesh *is* that field. No flat cap, no
  blanket.
- **Silhouette freedom with seam safety.** The rim height varies along the
  plan outline. Ops flagged `edge_carry` may break the rim (a dune exiting,
  a moss lobe rounding over); everywhere else the field eases to the
  material's `rim_level` across `edge_band`. The full side skirt always
  drops to the structural body, so adjacent tiles never show gaps — the
  visible groove between blocks is the diorama read, as in the reference.
- **Per-material body.** The skirt profile (wall inset, lip bulge/overhang,
  substrate band, chamfer) and plan corner radius are recipe data: sand gets
  a soft dune lip on a warm ochre body, snow a thick overhanging cap over a
  muted earth body, rock a heavier darker side, moss an earthy substrate
  reveal.
- **Paint field, not per-piece random colour.** Each op can own a colour;
  substrate colour comes from height/crest bands. 3–5 hue-shifted colours
  per tile, bucketed into per-key surfaces (existing MeshBatch pattern).
- **Curated determinism.** A recipe carries authored layouts; the seed
  selects a variant and applies bounded jitter (position/rotation/scale/
  omission) — it can never invent a new composition.
- **Normals.** Top normals are central differences of the sampled grid
  (smooth by construction); skirt normals analytic; deliberate soft creases
  only at authored lips.

### Stacking / gameplay contract (unchanged)

Footprint 1.70 m authored; body −0.50..−0.18 persists when covered (V2
skirt splits there); walk plane y = 0 remains the placement datum; runtime
scales X/Z only. Collision stays profile-driven (`flat` box +
`walk_surface_height`); sculpt amplitude above y = 0 is visual, kept within
the 0..0.15 schema budget for the walk height. `WorldGrid`, saves, and
placement APIs are untouched.

## 5. The five prototypes

Different generator family + macro-topology each; distinct silhouettes:

1. **Forest Floor** — low compact soil body, one broad diagonal soil rise,
   three embedded bark-chip clusters (discrete chunky pieces, sunken), one
   quiet exposed-soil patch. Corner-weighted diagonal composition.
2. **Sculpted Sand** — one broad diagonal dune crossing the tile with
   asymmetric shoulders, secondary shallow ridge, soft spill lip at one
   edge, ≤3 subtle impressions. Clean elsewhere.
3. **Pillowy Snow** — thick white cap of three fused lobes with irregular
   overhung perimeter, one compression hollow, muted earth body visible
   along part of one edge.
4. **Rounded Rock Ground** — five to six fitted slab plateaus with soft
   deep grooves, subtly domed centres, one step of height change, one small
   gravel pocket (<8%), heavier darker body.
5. **Moss Cushion** — two fused cushion masses (dominant + counterweight)
   of scalloped merged lobes over a dark substrate (15–25% visible), one
   hollow, lobes rounding over one edge.

## 6. Catalogue + migration policy

- V2 tiles register through the existing manifest → compiler → `tiles.json`
  pipeline with stable IDs (`tile_v2_*`), `source_kind: "procedural"`.
- Old tile IDs are **never deleted** (saves hard-fail on unknown IDs —
  `current_save_validator.gd`). Deprecation = removal from the
  `tuning.json::active_tile_ids` roster (and build-bag visibility), while
  definitions, recipes, manifests, and baked scenes remain loadable.
- Near-duplicate clusters documented for later consolidation (not migrated
  now): grass (`tile_grass`/`tile_kit_grass`/`tile_master_grass`/
  `tile_grass_flower`/`tile_proc_flower_meadow`), cobble
  (`tile_cobblestone`/`tile_proc_cobblestone_paving`), concrete
  (`tile_concrete_brutalist`/`tile_proc_concrete_slabs`), snow
  (`tile_snowfield`/`tile_proc_snow_field`/`tile_snow_drift`/
  `tile_proc_snow_drifts_study`), sand (`tile_sand`/
  `tile_proc_sandy_ground`/`tile_proc_sand_dunes_study`), path
  (`tile_path`/`tile_proc_garden_path`), mud (`tile_mud`/
  `tile_proc_mud_bed`), planks (`tile_wooden_planks`/
  `tile_proc_wood_plank_deck`/`tile_master_wood`).
  Known drift: `tile_proc_fenced_meadow` exists in `tiles.json` + manifests
  but not in the taxonomy or active roster.
- `test_runner.gd::_test_tile_library_contract` pins the official manifest
  count; it is updated deliberately when V2 tiles land.

## 7. Verification

Headless (console binary `C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe`):

```
godot --headless --path . --script tests/test_runner.gd            # ALL TESTS PASSED
godot --headless --path . --script tools/validate_content.gd
godot --headless --path . --script tests/tile_v2_contract_test.gd  # V2 suite
```

Windowed renders (root-viewport rig, like V1 review):

```
godot --path . tools/tile_kit/v2/review/tile_v2_review.tscn -- --shot-dir=<abs>
```

Acceptance sheets: contact sheet, per-tile 128 px thumbnails, grey
silhouettes, grayscale values, standard iso views, mixed 3×3 adjacency,
three deterministic variants per tile, before/after against the V1
equivalents.
