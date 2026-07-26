# Garden Galaxy visual-match workflow (corrective baseline)

Repeatable calibration loop that measures the rendered game against the
Garden Galaxy references. Never calibrate from editor thumbnails — the
captured PNG is the acceptance test.

## Current baseline (corrective pass)

- **Neutral pipeline**: linear tone mapper, no color adjustments, no glow,
  no fog, no custom material shaders. Raw albedos render predictably:
  `albedo x (ambient + sun)` and nothing else.
- **Materials**: plain `StandardMaterial3D` (roughness 0.88, specular 0.18),
  shared per palette key via `MaterialLibrary.rebind_materials()`.
- **One sun**: `#FFF5E6`, from screen upper-left (pitch −62°, yaw −65°),
  soft shadows toward lower-right, opacity per profile.
- **Ambient**: `#DDD8CB`, energy per profile.
- **Background**: flat `#EAE4D0` (renders exact under the linear pipeline).
- **Selected profile**: `garden_galaxy_day.tres` = **candidate B (balanced)**.
  Candidates A (soft) and C (defined) are kept for review:
  `garden_galaxy_candidate_a.tres`, `garden_galaxy_candidate_c.tres`.
- Grass tops are clean: a few authored tufts/clods/flowers, no procedural
  micro-noise.

## The loop

1. **Rebuild assets** (only when `art_source/procedural/build_assets.py` changed):

   ```bash
   ./tools/build_assets.sh
   ```

2. **Capture** the Match Lab at native 1920×1080 (a window opens briefly):

   ```bash
   /Applications/Godot.app/Contents/MacOS/Godot --path . scenes/debug/GardenGalaxyMatchLab.tscn \
       -- --shot=docs/visual_match/captures/candidate_b --profile=day
   ```

   Profiles: `day` (candidate B), `a`, `c`, `mist`, `rain`.
   Each run writes `<base>.png`, `<base>_post.png` (adds the 1-tile magenta
   shadow-test post) and `<base>.json` (screen-space sample manifest).
   `--probe` captures an unshaded swatch wall instead (tonemap transfer curve).

3. **Measure**:

   ```bash
   python3 tools/compare_reference_render.py docs/visual_match/captures/candidate_b --label candidate_b
   ```

   Writes Delta E table (md+json), swatch card, side-by-side, and — when a
   reference PNG exists on disk — a difference heatmap, to
   `docs/visual_match/reports/`.

## Hard-won Godot rendering facts (do not re-learn these)

- **Directional shadows follow the ROOT viewport's current camera.** A
  SubViewport camera alone leaves the shadow fit collapsed around the world
  origin: most casters silently drop out. The Match Lab keeps a twin "fit
  camera" in the root viewport.
- **Tight camera near/far is load-bearing for ortho shadows.** 0.05..4000
  dilutes the directional shadow map until shadows disappear. Gameplay uses
  10..95; the lab uses 25..58.
- **Depth bias eats thin-caster shadows.** `shadow_bias 0.1` (default) plus
  wide fits removed shadows from posts, characters, benches. Baseline:
  `shadow_bias 0.015`, `shadow_normal_bias 0.6`.
- The environment background color and BG_CANVAS content go through the 3D
  tonemap; with the linear mapper this is identity, so authored values render
  exact. If ACES is ever retried, use the lab `--probe` +
  `tools/solve_albedos.py` to invert the transfer curve.

## Acceptance state

`candidate_b` report: **ALL PASS** — background dE 0.8, grass dE 2.9, shadow
angle 10° down-right, post shadow 0.53 tiles, framing 60% × 65%, black floor
luma 62, no white clip. Comparison sheet:
`docs/visual_match/corrective_pass_comparison.png`.

The Garden Galaxy reference PNGs belong in
`docs/style_reference/garden_galaxy/` (see README there) — the comparison
sheet upgrades automatically once they exist on disk.

## Where the knobs live

| Knob | File |
|---|---|
| Raw albedos | `assets/palettes/cozy_diorama_palette.tres` (+ Blender mirror in `art_source/procedural/build_assets.py`) |
| Material response | `scripts/visuals/material_library.gd` |
| Environment/sun/AO profiles | `assets/visual_profiles/garden_galaxy_day.tres` (B), `_candidate_a/_c.tres`, `_mist.tres` |
| Rig plumbing | `scripts/visuals/lighting_rig.gd` |
| Mesh shape language | `art_source/procedural/build_assets.py` |
| Gameplay framing | `data/tuning.json` (`camera_default_size`) |
| Lab layout/camera/markers | `scripts/debug/garden_visual_capture.gd` |
