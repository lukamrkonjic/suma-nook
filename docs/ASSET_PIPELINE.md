# Asset pipeline

One shared technical contract for every 3D asset; three creation tiers; one
import recipe for external/generated models. Tile composition, top extraction,
and future grass/fern/snow/sand GLB intake are specified in
[`TILE_AUTHORING.md`](TILE_AUTHORING.md).

## Technical contract

- 1 Godot unit = 1 m. Tile sources retain the 1.70 m authoring frame and are
  normalized in X/Z to the exact 1.00 m Garden Galaxy logical cell at runtime.
  The land block top sits at y = 0.0 and extends to y = -0.50. Every elevation
  step is exactly 0.50 m so stacked visuals and collision touch without a gap.
- New tiles are layered, not fused: one required `base`, one required
  `surface`, and optional `detail`/`edge` GLBs form one logical tile at
  runtime. The base owns the exact -0.50 m structural depth; the surface owns
  flat, recessed, or raised top geometry. Layer role and `cover_behavior`
  explicitly control stacking visibility—bounds/name guessing remains only
  for legacy fused assets.
- Readable plants and props remain independent geometry. Small tile-specific
  grass, ferns, leaves, pebbles, or tracks may be `detail` layers, but never
  belong to the structural `base`.
- Y-up, forward = -Z, origin at bottom-center (pivot exceptions documented per asset).
- Rotation/scale applied; clean object and material names; no embedded lights/cameras;
  no hidden high-poly duplicates; simplified collision authored in Godot, not Blender.
- Source `.blend`/`.py` in `art_source/`; game-ready `.glb` under `assets/3d/`.
  `AssetLibrary` resolves an `asset_id` by searching **`reworked/` → `final/` →
  `proxies/`** in that order, so dropping `assets/3d/reworked/<asset_id>.glb`
  overrides an older asset with zero code changes. New work ships to
  `reworked/`.
- Materials: semantic slot names (`grass`, `soil`, `wood`, `pale_stone`, `dark_foliage`,
  `bright_foliage`, `terracotta`, `water`, `metal`, `fabric`, `fire_core`, `fire_outer`,
  `magic`); Godot rebinds every slot to the shared `MaterialLibrary` at import via the
  glb import script, so palette changes never require re-export.
- Animation names are semantic: idle, walk, fish_cast, fish_wait, fish_catch, chop,
  attack, dodge, hit, interact. (MVP proxy character is animated procedurally in Godot
  with these state names; a rigged Tier C character must expose the same names.)
- Authored player rigs are configured through
  `assets/player/current_player_profile.tres`; see
  `docs/PLAYER_ASSET_PIPELINE.md`. The current Mixamo model is testing-only and
  is replaceable without changing controllers, skills, or save data.

## Tier A — generated headlessly by the coding agent (this repo, now)

`art_source/procedural/build_assets.py` runs under
`/Applications/Blender.app/Contents/MacOS/Blender --background --python ...` and writes
every Tier A GLB (tiles, vegetation, props, effects meshes, character proxy parts).
Deterministic (fixed seeds), re-runnable, idempotent. Regenerate with:

```bash
./tools/build_assets.sh
```

Bevel + weighted normals are applied in Blender so silhouettes match the style breakdown.

## Tier B — agent-built with the same Blender scripts, only after Style Lab approval

Cottage, arch, bridge-scale pieces, enemies, tools/weapons — same script family
(`art_source/procedural/build_assets_tier_b.py` section), same contract.

## Tier C — Luka via Modly → Blender (docs/asset_briefs/*.md)

1. Brief in `docs/asset_briefs/<asset_id>.md` (template: `_TEMPLATE.md`).
2. Modly output → `art_source/modly/<asset_id>/` (never overwritten).
3. Blender cleanup (normals, retopo, bevels, palette materials, pivot, sockets) →
   `art_source/blender/<asset_id>/<asset_id>.blend`.
4. Export `assets/3d/final/<asset_id>.glb` using the SAME asset id as the shipped proxy.
5. Validate in the production world under day and rain profiles, then run the
   full-loop acceptance suite.
6. Nothing else changes: gameplay references definitions (`data/*.json` →
   `scene_path`), never proxy filenames. Swapping the file at the definition's
   `scene_path` (or editing that one JSON string) completes the replacement.

## Layered two-form tiles (exposed top vs covered block)

Every land tile has two visual forms, swapped by the runtime
(`tile_visual_factory.set_surface_covered`) when a tile is stacked above:

- **Exposed** (nothing above): `base` + `surface` + optional `detail`/`edge`
  layers. The surface may be flush, recessed, or raised; declare
  `exposed_top: "flush" | "recessed" | "raised"`.
- **Covered** (a tile above): `base` and any `persist` layers remain;
  `hide` layers cross-fade out. A generated base-material lid fills from the
  base top to y = 0 so every stacked band is structurally complete.

Authoring rule: whatever the exposed top does, the `base` must remain the exact
full-footprint filler to y = -0.50. Meaningful plank/slab/snow/sand depth is
mesh geometry, not a height-map illusion. See `TILE_AUTHORING.md` for the
schema and role-by-role bounds.

## Importing a generated model (tiles, props, characters)

The reproducible pattern for turning an external/AI-generated GLB into a Suma
asset. For a tile source, first classify it as `surface`, `detail`, or `edge`
using `TILE_AUTHORING.md`; discard its generated lower block and export only
the useful layer. For props, use the nearest existing processor.

1. **Archive + pin.** Copy the source to
   `art_source/imported/<asset_id>/<asset_id>_source.glb` (never overwritten,
   never shipped). The processor script hard-pins its sha256 and refuses to run
   on a changed source — imports stay reproducible.
2. **One processor script per asset** in `art_source/blender/process_<asset_id>.py`,
   run headless:
   `C:/Software/Blender/blender.exe --background --factory-startup --python art_source/blender/process_<asset_id>.py`
   It should print a JSON report (bounds, counts, material assignments) so a
   re-run is verifiable at a glance.
3. **Clean generated topology** (AI meshes arrive fully triangulated):
   `remove_doubles` (weld ~0.001 of the source scale) → `tris_convert_to_quads`
   → `dissolve_limited` (5–8°, delimit MATERIAL) → recalc normals →
   `shade_auto_smooth` (~35–40°). This removes visible scanline triangles while
   keeping intentional facets and seams.
4. **Replace textures with palette materials.** Never ship baked textures.
   Map each source material to a semantic palette name (flat Principled BSDF,
   roughness 0.78, metallic 0) — the full palette lives in
   `art_source/blender/build_gg_assets.py::PALETTE` and mirrors
   `assets/palettes/gg_material_palette.tres`. `MaterialLibrary.rebind_materials`
   swaps every surface by material NAME at load, so palette edits re-skin
   shipped GLBs without re-export. For a textured source, quantise instead of
   guessing: sample the base-colour texture per face (or per mesh shell — one
   plank/board/panel per shell) and snap each to the nearest ramp tone, as the
   planks processor does. Multi-material meshes are fine — rebinding handles
   every surface.
5. **Normalise to the contract.**
   - *Tile layer*: keep the authored cell frame at exactly 1.70 × 1.70 and the
     surface contact plane at z = 0 (Blender) / y = 0 (Godot). Do not add or
     copy a 0.50 m body. The shared base supplies it. Use
     `tile_layer_surface_*`, `tile_layer_detail_*`, or `tile_layer_edge_*`.
   - *Prop/structure*: ground at z = 0, footprint inside ~1.5 m. Keep source
     models at their established authored scale; the complete runtime model
     catalog is calibrated by `world_model_scale = 1.00 / 1.35`. This shared
     factor also drives support slots, blockers, lights, and effects. Structures
     with `grid_fit_profile: "tile_span"` remain auto-fitted in X/Z and receive
     the catalog calibration vertically (a 10 cm authored inset per edge reads
     best). Name animated subtrees explicitly (e.g. the water wheel's
     `WaterWheelRotor` targeted by the `ambient_motion` capability).
   - *Character*: follow `docs/PLAYER_ASSET_PIPELINE.md` (rig via
     `assets/player/current_player_profile.tres`; semantic animation names) —
     do not route characters through this tile/prop recipe.
6. **Export** with the standard flags:
   `use_selection, export_apply, export_yup, no animations/skins/lights/cameras`
   to `assets/3d/reworked/<asset_id>.glb`.
7. **Wire the data.** New tile → one entry in `data/tiles.json` with
   `render_profile: "layered"` and its layer array. Add it to
   `data/tuning.json::active_tile_ids` only after review. New structure →
   `data/structures.json`.
8. **Validate and review.** `godot --headless --path . --import` first —
   **without a reimport Godot renders the stale cached mesh**, then
   `godot --headless --path . --script tests/test_runner.gd` (must print ALL
   TESTS PASSED). For interactive review, launch the normal game and press
   **F8** (or Pause → Admin Controls → Asset Viewer). The viewer lists active
   tiles and all registered models, renders tiles as a 3×3 seam patch, uses
   the production material/lighting/weather stack, and can capture PNGs.
   The automated viewer proof is:

   ```powershell
   godot --path . tests/asset_viewer_review.tscn -- --shot-dir=res://artifacts/asset_viewer
   ```
9. **Record provenance** in `docs/ASSET_PROVENANCE.md` (source, tool, pin).

### Blender scripting gotchas (cost us real debugging time)

- `bpy.ops.object.transform_apply(scale=True)` also applies **location and
  rotation** (operator defaults are True). `build_gg_assets.rbox/lobe/uv_sphere`
  bake world positions into vertices this way — setting `rotation_euler` on
  those objects afterwards orbits the **scene origin**, not the object. Rotate
  their vertices instead (`orient()` in `build_catalog_expansion.py`), or use
  origin-carrying builders (`rcyl`, `rock`, lathe/pydata meshes,
  `suma_surface_kit` lobes) when you need post-creation transforms.
- Per-face random material scatter on chunky low-poly facets reads as pinwheel
  patchwork. Cover deterministically per object/shell
  (`suma_surface_kit.dust`) — a stone is either moss-capped or bare.

## Provenance

Every shipped asset is recorded in `docs/ASSET_PROVENANCE.md`. Queue state lives in
`docs/ASSET_QUEUE.md`.
