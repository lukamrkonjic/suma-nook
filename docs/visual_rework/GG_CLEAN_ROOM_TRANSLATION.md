# GG clean-room visual translation

Updated: 2026-07-26

This pass is an original Suma Nook implementation informed by observable,
high-level behaviour and the supplied reference images. It does not contain
Garden Galaxy source code, meshes, textures, shaders, sounds, icons, animation
curves, or exported proprietary assets.

## Result

The game now has one coherent runtime visual system covering:

- the measured 15-degree perspective camera, 5/100 clipping planes, 40–70
  distance envelope, five-unit zoom steps, 40-degree pitch, and quarter-turn
  orbit;
- a realtime directional-light and reflection-probe rig;
- ambient gradient, background presets, fog, SSAO, glow/bloom, exposure,
  tonemapping, brightness, contrast, and saturation;
- a crisp native-resolution path: 1920×1080, 8× MSAA, non-temporal FXAA,
  debanding, 16× anisotropic filtering, no automatic mesh LOD, and an 8192
  directional shadow map;
- semantic painted-matte, foliage, earth, stone, wood, ceramic, cloth/skin,
  metal, emissive, water, and underwater material families;
- six complete weather profiles: day, mist, rain, falling leaves, snow, and
  blossom breeze;
- rain, motes, leaves, snow, petals, and warm-spore particle families with
  quality scaling and original lifecycle curves;
- noon, afternoon, sunset, night, and background overrides;
- original Suma player, placement, foliage, water, light, and parcel-reveal
  animation state machines;
- persistent weather, time, background, particle-quality, and camera state;
- an Admin Debug Controls card for granting all content and switching every
  visual state at runtime.

## Image calibration

The supplied GG references consistently place the neutral background near
`#E4E0CF`–`#E6E2CB`. The garden reference's dominant grass and water families
are close to `#9DC248` and `#79A69B`. The final day capture deliberately keeps
the palette's selective saturation rather than applying a global grey wash.
Calmness comes from the warm neutral surround, matte material response, soft
ambient fill, and controlled shadows.

The last crispness pass removes TAA. TAA was visibly softening the fishing rod,
reeds, grass tips, tile bevels, and animated water silhouettes. The selected
path preserves 8× geometry MSAA and adds only non-temporal final edge cleanup.
The live audit reports:

```text
viewport_render_target_size=(1920, 1080)
scaling_3d_scale=1.0
msaa_3d=3 (8x)
screen_space_aa=1 (FXAA)
use_taa=false
anisotropic_filtering_level=4 (16x)
directional_shadow_size=8192
mesh_lod_threshold=0.0
```

## Runtime evidence

The generated runtime manifest records instantiated values, not only resource
defaults:

- 411 live scene nodes;
- 141 material parameter records;
- six weather profiles and six particle families;
- ten player animation states plus world and parcel-reveal animation records;
- camera, light, ambient, fog, reflection, post-processing, saved-state, and
  instantiated-prefab values.

The complete manifest and the seven final captures are saved under:

`C:\Users\Luka\Documents\dev\garden-galaxy-technical-audit\game_diagnostics\gg_full_translation`

## Verification

```text
Godot import: passed
Core suite: ALL TESTS PASSED — 98 assertions
Real-scene suite: FULL LOOP PASSED — 80 checks
Runtime manifest: generated successfully
Weather captures: day, mist, rain, leaves, snow, blossom, admin night
```

The short-lived screenshot and test processes report Godot shutdown-time
resource-retention warnings after their explicit quit. They do not occur as
test failures and do not affect the running game.

## Clean-room limit

A literal pixel-identical guarantee is not technically or legally supportable:
the games use different original assets and engines, and GG's proprietary
material blocks, shader code, meshes, textures, and animation keyframe curves
were neither copied nor imported. Animation names, broad durations, events,
transitions, camera values, and visible behaviour can guide original Suma
equivalents; proprietary keyframes and curves remain out of scope.
