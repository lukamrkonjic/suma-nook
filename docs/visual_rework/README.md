# Garden Galaxy visual reconstruction — workflow and state

The strict reconstruction pass (2026-07-26): rounded authored geometry, a
disciplined GG-derived palette, soft warm sunlight, intentional negative
space, and depth-aware jello-block water.

## Reference hierarchy
- **A (primary art direction)**: bright Garden Galaxy screenshots — modeling
  language, palette, sunlight, proportions, cleanliness.
- **B (water only)**: tropical turquoise island shot — depth color, shallows,
  seabed visibility, foam, caustics.
- **C (future weather preset only)**: rainy GG shot.
- **D (failure reference)**: the pre-rework screenshot — never a target.

Reference PNGs belong in `references/` (copy from chat attachments; the
comparison tool upgrades automatically once present).

## The pipeline in one paragraph

`art_source/blender/build_gg_assets.py` builds every simple visible asset with
the GG modeling standards into `assets/3d/reworked/` (overrides `final/` by
search order). `assets/palettes/gg_material_palette.tres` holds NAMED source
albedos + authoritative render targets; `tools/apply_solved_palette.py`
regenerates the source albedos by inverting the measured tonemap curve
(captured via the Match Lab `--probe` under the day rig). One rig
(`scenes/visual/GGDayLightingRig.tscn` + `gg_day_profile.tres`, Filmic, one
sun #FFF1D2 from upper-left, ambient #D8C5B1, restrained SSAO) lights
everything. Water is one contiguous mesh per region with jello skirt walls
(`scripts/visuals/water_surface.gd` + `gg_water.gdshader`), a dished sand
floor GLB, caustic floor/flora shaders, and shoreline-weighted flora placed by
`world_renderer.gd`.

## Validation loops
- `scenes/debug/GGAssetQualityLab.tscn` — roster + water region;
  `--shot=… [--closeups] [--silhouette]`.
- `scenes/debug/GardenGalaxyMatchLab.tscn` — `--probe` for the transfer curve;
  `tools/compare_reference_render.py` for Delta E and shadow geometry.
- `tools/visual_compare.py` — side-by-side / silhouette / saturation /
  edge-density sheets + `palette_sheet.png`.
- Gameplay acceptance shot: `godot --path . -- --shot=out.png`.

## Current state (see comparisons/)
- `gameplay_final.png` — the reworked start world.
- `lab_final_*.png` — full lab, per-asset close-ups, silhouette pass.
- `final_side_by_side.png` etc. — progression sheets.
- 120 FPS in the start world (target 60).

## Known follow-ups
- Ferry dock points north (gameplay-authored transform) while the start-world
  water sits east — pre-existing data quirk, gameplay-frozen this pass.
- Bench backrest has a small gap to the seat (minor, next asset pass).
- Underwater life extras (fish silhouettes, bubbles, ripple rings at the
  fishing point) are wired for fx but intentionally restrained.
- Hero assets (character, enemies, watchpost, houses) reserved for Luka's
  Modly/Blender route — see ASSET_AUDIT.md.
