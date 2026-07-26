# Garden Galaxy visual-match workflow

Repeatable calibration loop that measures the rendered game against the
Garden Galaxy reference targets. Never calibrate from editor thumbnails —
the captured PNG is the acceptance test.

## The loop

1. **Rebuild assets** (only when `art_source/procedural/build_assets.py` changed):

   ```bash
   ./tools/build_assets.sh
   ```

2. **Capture** the Match Lab at native 1920×1080 (a window opens briefly):

   ```bash
   /Applications/Godot.app/Contents/MacOS/Godot --path . scenes/debug/GardenGalaxyMatchLab.tscn \
       -- --shot=docs/visual_match/captures/day --profile=day
   ```

   Profiles: `day` (cream), `mist` (blue-gray gradient), `rain`.
   Each run writes `<base>.png`, `<base>_post.png` (with the 1-tile magenta
   shadow-test post) and `<base>.json` (screen-space sample manifest).

3. **Measure**:

   ```bash
   python3 tools/compare_reference_render.py docs/visual_match/captures/day \
       --old docs/style_comparisons/final_gameplay_day.png \
       --reference docs/style_reference/garden_galaxy/garden_galaxy_day_reference_01.png
   ```

   Writes to `docs/visual_match/reports/`: Delta E 2000 table (md + json),
   swatch card, side-by-side, and (when the reference PNG exists on disk)
   a per-pixel difference heatmap.

## Tuning order — one thing at a time

1. Camera and object framing
2. Background color
3. Exposure
4. Sun direction
5. Shadow length
6. Shadow softness
7. Ambient energy
8. Ambient occlusion
9. Material roughness/specular
10. Raw albedo palette (`assets/palettes/cozy_diorama_palette.tres` +
    the mirror in `art_source/procedural/build_assets.py`)
11. Water
12. Emissive details

## Acceptance criteria (from the rework brief)

- background within dE 2.5 of `#E9E2CF`; lit grass within dE 5; pale stone
  within dE 5; water within dE 6
- shadow direction ≈ 25° down from screen-right (±3°); 1-tile post casts
  0.45–0.65 tile widths; penumbra soft but readable
- cast shadows 25–32 % darker than lit, contact regions up to ~40 %
- no ordinary material at pure black (black floor luma > 10); no ordinary
  highlight clipped to white
- world fills ~65–80 % of viewport width, ~55–75 % of height
- side-by-side reads as the same lighting and palette family

## Where the knobs live

| Knob | File |
|---|---|
| Raw albedos | `assets/palettes/cozy_diorama_palette.tres` (+ Blender mirror) |
| Master material response | `assets/materials/garden_master.gdshader`, `scripts/visuals/material_library.gd` |
| Water | `assets/materials/garden_water.gdshader` |
| Environment/sun/AO | `assets/visual_profiles/garden_galaxy_day.tres`, `garden_galaxy_mist.tres` |
| Rig plumbing | `scripts/visuals/lighting_rig.gd` |
| Mesh shape language | `art_source/procedural/build_assets.py` |
| Gameplay framing | `data/tuning.json` (`camera_default_size`) |
| Lab layout/camera | `scripts/debug/garden_visual_capture.gd` |
