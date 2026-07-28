# Asset pipeline

One shared technical contract for every 3D asset; three creation tiers; one
import recipe for external/generated models (see "Importing a generated
model" below).

## Technical contract

- 1 Godot unit = 1 m. Tiles use a compact 1.70 m horizontal footprint; the land
  block top sits at y = 0.0 and extends to y = -0.50. Every elevation step is
  exactly 0.50 m so stacked visuals and collision touch without a gap.
- Tile GLBs may use recessed seams or basins below y = 0. Ordinary structural
  tile geometry must never extend above y = 0, with one exception: **coverable
  surface relief** (cobbles, clods, drifts, lane lenses) may rise into
  y ∈ [0, 0.05]. `tile_visual_factory.gd` classifies any mesh whose bounds sit
  wholly inside that band as fade-when-covered detail — meshes named `*_body`
  or `*_cap` are exempt (structural). So: name the walkable block `<x>_cap` /
  `<x>_body`, keep every decoration inside the 0–0.05 budget, and never exceed
  it (taller relief clips through a tile stacked on top). Trees, planters,
  crystals, ruins and other readable silhouettes are independent placeables.
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

## Two-form tiles (exposed top vs covered block)

Every land tile has two visual forms, swapped by the runtime
(`tile_visual_factory.set_surface_covered`) when a tile is stacked above:

- **Exposed** (nothing above): `<x>_body` + `<x>_cap` + relief. The top may sit
  flush with the walkable plane, dip below it (recessed plank beds, carved
  tops) or rise above it (debris piles, mounds). Declare the kind on the tile
  definition as `exposed_top: "flush" | "recessed" | "raised"` — the slot-fill
  test grants recessed tops down to -0.12 and raised tops up to +0.35.
- **Covered** (a tile above): the entire top layer hides and a generated
  flush infill lid (full `tile_size` footprint, body-top to y=0, body
  material) completes the block — so a stack always reads as clean, exactly
  slot-sized bands, with only the topmost tile carrying its detail.

Authoring rule: whatever the exposed top does, the `_body` must still be the
full-footprint filler to -0.50 (validated), because it plus the lid IS the
covered block. New "constructed" blocks (recessed planks, paver patterns,
rubble tops) need nothing beyond correct `_body`/`_cap` naming and the
`exposed_top` declaration.

## Importing a generated model (tiles, props, characters)

The reproducible pattern for turning an external/AI-generated GLB into a Suma
asset. Precedents: `art_source/blender/process_stylized_pyramid_tent.py`
(prop) and `art_source/blender/process_wooden_planks_tile.py` (tile, with
palette quantisation). Copy the nearest one and adjust.

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
   - *Tile*: scale to exactly 1.70 × 1.70 × 0.50 with the walkable top at
     z = 0 (Blender) / y = 0 (Godot), and rename the mesh `<x>_cap` (plus a
     `<x>_body` filler block if the model doesn't reach z = -0.50). Baked
     surface decoration must respect the 0–0.05 relief budget above.
   - *Prop/structure*: ground at z = 0, footprint inside ~1.5 m (structures
     with `grid_fit_profile: "tile_span"` are auto-fitted; a 10 cm inset per
     edge reads best). Name animated subtrees explicitly (e.g. the water
     wheel's `WaterWheelRotor` targeted by the `ambient_motion` capability).
   - *Character*: follow `docs/PLAYER_ASSET_PIPELINE.md` (rig via
     `assets/player/current_player_profile.tres`; semantic animation names) —
     do not route characters through this tile/prop recipe.
6. **Export** with the standard flags:
   `use_selection, export_apply, export_yup, no animations/skins/lights/cameras`
   to `assets/3d/reworked/<asset_id>.glb`.
7. **Wire the data.** New tile → one entry in `data/tiles.json` (id, name,
   family, asset_id, weight/rarity, stackable/supports_tiles,
   `surface_kind: "flat"`, placement_sound — `"wood"` is a registered sound).
   New structure → `data/structures.json`. No code changes; definitions load
   by id.
8. **Validate and review.** `godot --headless --path . --import` first —
   **without a reimport Godot renders the stale cached mesh**, then
   `godot --headless --path . --script tests/test_runner.gd` (must print ALL
   TESTS PASSED). For interactive review, launch the normal game and press
   **F8** (or Pause → Admin Controls → Asset Viewer). The viewer discovers
   every registered tile and model, renders tiles as a 3×3 seam patch, uses
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
