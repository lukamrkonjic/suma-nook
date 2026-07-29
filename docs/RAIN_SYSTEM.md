# Rain Surface and Interaction

## Previous limitation

Rain used one `GPUParticles3D` emitter containing 900 identical box streaks.
The emitter stayed near world origin, did not wet the ground, created no
impacts, and did not react to the player. Large worlds could therefore leave
the rain field behind as the player travelled.

## Shipping design

Rain now has three fixed-budget parts:

1. **Falling field** — 720 varied, softly emissive streaks in a box centered
   over the current camera focus. The emitter follows horizontally, while its
   already emitted particles remain in world space.
2. **Wet surface** — one two-triangle plane follows the visible world area at
   settled ground height. A world-space noise texture produces irregular
   pooled patches and a faint moving film.
3. **Walking interaction** — one 28-particle foot emitter and four reusable
   footstep-ring slots. Grounded movement leaves alternating expanding rings
   and tiny droplets behind each foot.

The surface samples opaque depth once to reject empty backdrop, characters,
and distant geometry. It never samples the screen color, uses temporal
reprojection, or performs raymarching. The texture and all ripple coordinates
are anchored in world XZ, so scrolling does not slide the effect.

## Raindrop ripples

Two procedural impact fields divide visible ground into world-space cells.
Each cell derives a deterministic impact point and phase from a hash. The
shader expands and fades the corresponding ring over time.

This creates many apparent drops without allocating a particle, node, timer,
or texture update for every impact. The pattern continues through a world of
any size with constant work.

## Player behavior

Walking speed is read from `CharacterBody3D.velocity`, rather than only from
render-frame displacement. This matters when rendering faster than the physics
tick: in-between render frames still know the player is walking, so splashes
do not pulse or disappear.

Ground contact accepts a small settled-height tolerance for seams between
chunk colliders. A jump is rejected by both vertical speed and height, keeping
the rain surface on the ground.

- idle: no aura and no foot emitter;
- walking: calm alternating rings and small droplets;
- sprinting/dodging: stronger wake and denser droplets;
- jumping: no airborne splashes and no lifted surface.

## Fixed budgets

- 1 wet-surface draw call;
- 1 foot-splash draw call, only while moving;
- 720 falling streak particles at high weather quality;
- 28 reused foot droplets;
- 4 reused footstep-ring uniforms;
- 2 procedural rain-impact fields;
- 1 shared 192 px seamless, mipmapped noise texture;
- 0 per-tile rain nodes;
- 0 per-impact CPU objects;
- 0 screen-color samples or temporal history.

Low and medium particle-quality modes reduce both falling rain and foot
splashes.

## Art tuning

The rain profile and debug lighting cockpit expose:

- `rain_surface_wetness`
- `rain_puddle_amount`
- `rain_ripple_amount`
- `rain_walk_splash_amount`

The authored Garden Rain values are 0.82, 0.72, 0.88, and 0.82 respectively.

## Regression tools

Visual and behavioral capture:

```powershell
& "C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe" `
  --path "C:\Dev\suma-nook" `
  "res://tests/rain_capture.tscn"
```

Maximum-world benchmark:

```powershell
& "C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe" `
  --path "C:\Dev\suma-nook" `
  "res://tests/rain_performance_runner.tscn" -- --maxed-world
```

`rain_capture` uses the real movement input path and fails if walking produces
no live footstep ripples. It also raises the player three units with upward
velocity and fails if the wet surface follows the jump.

## Measured maxed-world result

On the RTX 3090 development machine at 1920x1080 with Godot 4.6.3 Forward+,
the test world contains 10,000 tiles, 10,000 models, 20,000 render instances,
and 581 authored warm lights.

| State | Average | p95 | p99 |
| --- | ---: | ---: | ---: |
| Falling streaks only | 144.0 FPS / 6.945 ms | 7.309 ms | 7.402 ms |
| Complete wet surface and impacts | 144.0 FPS / 6.945 ms | 7.311 ms | 7.385 ms |
| Complete rain, repeated 20-42 scrolling | 144.0 FPS / 6.943 ms | 7.326 ms | 7.422 ms |

The complete surface adds exactly one idle draw call and no measurable average
frame-time cost at the 144 FPS cap. The scrolling test changes zoom four times
and shows no spike attributable to the rain overlay.
