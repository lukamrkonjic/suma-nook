# Asset replacement manifest

Source of truth: `art_source/blender/build_gg_assets.py` (deterministic,
headless Blender). Output: `assets/3d/reworked/*.glb` — 65 assets.
`AssetLibrary.SEARCH_PATHS` resolves `reworked/` → `final/` → `proxies/`, so a
same-id GLB in `reworked/` silently supersedes the legacy asset.

## Rebuild command

```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
    --python art_source/blender/build_gg_assets.py
/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --import
```

## Materials

All reworked GLBs carry semantic material names from the GG palette
(`assets/palettes/gg_material_palette.tres`). `MaterialLibrary.rebind_materials`
swaps every surface to the shared registry instance at spawn:
- ordinary keys → shared `StandardMaterial3D` (roughness 0.88, specular 0.18)
- `water` → `gg_water.gdshader` (depth absorption, Gerstner waves, refraction,
  foam, jello block sides)
- `uw_*` → `gg_underwater.gdshader` (caustics + absorption) or
  `gg_uw_flora.gdshader` (adds tip-weighted sway)

Source albedos are SOLVED, not guessed: `tools/apply_solved_palette.py` inverts
the measured Filmic transfer curve (Match Lab `--probe`) per face orientation.
Rendered output lands on the authoritative render targets recorded in the same
palette resource. Never hand-stack grading on top.

## Water system

- `scripts/visuals/water_surface.gd` — ONE contiguous ArrayMesh per water
  region (6×6 quads/tile, world-space UVs) + jello skirt walls on every edge
  not continuing into water, down to the block bottom (−0.56).
- `scripts/world/world_renderer.gd` — floor GLB + deterministic
  shoreline-weighted flora clusters per water cell; surface rebuilt only when
  water topology changes.
- Pond tiles reuse the same water material on their embedded surface quad.

## Performance (dev Mac, start world)

- Project FPS: 120 (8.3 ms/frame) — 2× the 60 FPS target.
- One shared water material, one surface mesh per region, no per-tile water
  logic, no per-plant scripts (sway is in-shader), caustics inside the floor
  material (no extra passes/decals).
