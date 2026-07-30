# Water interaction system

The playable water response is a fixed-budget extension of Suma Nook's joined
and streamed water-tile renderer. It deliberately avoids a per-tile fluid simulation: a
10,000-tile debugging world uses exactly the same interaction state and particle
budget as a nine-tile pond.

## What is rendered

- A real water entry emits one impact whose strength comes from the player's
  downward velocity before buoyancy clears it.
- Six reusable world-space impulses produce expanding crests, a small settling
  wave, foam, and actual vertex displacement across water tile and chunk seams.
- Movement in swimming state drives a narrow bow wave and two trailing wake
  arms. Alternating low-strength impulses make the disturbed water settle
  naturally behind the character.
- Jumping out emits a separate low-strength kick-off ripple without replaying
  the landing splash.
- One pooled, one-shot GPU emitter supplies the larger entry crown and droplets.
  A second pooled emitter supplies restrained movement spray.
- The permanent block-edge foam is intentionally near-invisible. Connected
  water tops render before the boundary skirts, preventing per-cell depth order
  from exposing diagonal joins along the continuous outer wall.

All interactions are pinned to the registry water level (`-0.14` by default).
They follow only the player's XZ position, so jumping and buoyancy bob cannot
drag the water effect vertically.

## Cost envelope

| Resource | Fixed budget |
| --- | ---: |
| Water impulse slots | 6 |
| Entry particles | 18 |
| Movement particles | 8 |
| Particle simulation rate | 60 Hz |
| Additional particle draw calls | 2 maximum |
| Per-tile interaction nodes | 0 |
| CPU mesh deformation | None |
| Screen-texture samples | None |

Authored fallback water meshes use eight subdivisions per tile; the endless
field's bounded stream window uses the tuned lower subdivision count. Their
shared shader performs deformation on the GPU, while the CPU uploads only the
six impulses and current wake. Streaming changes which real water-tile
coordinates own geometry, never the fixed interaction-state budget.

## Regression checks

`tests/water_interaction_capture.tscn` creates a controlled lake, drops the real
player into it, drives real movement input, captures entry and wake images, and
asserts that the effect remains on the authored waterline during a swim hop.

`tests/water_interaction_performance_runner.tscn --maxed-world` measures idle and
fully active interaction states in the 10,000-tile / 10,000-model stress world.
