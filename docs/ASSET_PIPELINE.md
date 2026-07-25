# Asset pipeline

One shared technical contract for every 3D asset; three creation tiers.

## Technical contract

- 1 Godot unit = 1 m. Tile size is `WorldGrid.TILE_SIZE` = 2.0 m; land block top sits at
  y = 0.0, block extends down to y = -0.9. Assets stand on y = 0.
- Y-up, forward = -Z, origin at bottom-center (pivot exceptions documented per asset).
- Rotation/scale applied; clean object and material names; no embedded lights/cameras;
  no hidden high-poly duplicates; simplified collision authored in Godot, not Blender.
- Source `.blend`/`.py` in `art_source/`; game-ready `.glb` in `assets/3d/final/`
  (Tier A/B) or `assets/3d/proxies/` (Tier C stand-ins).
- Materials: semantic slot names (`grass`, `soil`, `wood`, `pale_stone`, `dark_foliage`,
  `bright_foliage`, `terracotta`, `water`, `metal`, `fabric`, `fire_core`, `fire_outer`,
  `magic`); Godot rebinds every slot to the shared `MaterialLibrary` at import via the
  glb import script, so palette changes never require re-export.
- Animation names are semantic: idle, walk, fish_cast, fish_wait, fish_catch, chop,
  attack, dodge, hit, interact. (MVP proxy character is animated procedurally in Godot
  with these state names; a rigged Tier C character must expose the same names.)

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
5. Validate in `scenes/debug/VisualStyleLab.tscn` under both profiles.
6. Nothing else changes: gameplay references definitions (`data/*.json` →
   `scene_path`), never proxy filenames. Swapping the file at the definition's
   `scene_path` (or editing that one JSON string) completes the replacement.

## Provenance

Every shipped asset is recorded in `docs/ASSET_PROVENANCE.md`. Queue state lives in
`docs/ASSET_QUEUE.md`.
