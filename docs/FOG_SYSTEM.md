# World-Space Mist

## Why the old approaches failed

The original mist weather used Godot's traditional exponential fog. That is a
distance fade over the complete camera image, so it looked like a transparent
grey layer rather than fog occupying the garden.

The first localized replacement used a `FogVolume`. It had depth intersection
and light scattering, but Godot reconstructs volumetric fog on a low-resolution
camera-relative froxel grid. Isometric zooming and scrolling moved geometry
through that grid, producing visible shimmer and temporal-reprojection
flicker. Increasing its quality would have made the 10,000-model stress world
more expensive without removing the underlying instability.

Both built-in fog paths are now disabled.

## Shipping design

Mist is rendered by three large horizontal planes centered on the visible
world area. They occupy slightly different heights above the ground and share
one seamless 256 px noise texture. The shader combines broad, crossing, and
fine samples into soft patches and ribbons.

The important stability rule is that every noise lookup uses absolute world
XZ coordinates. The planes may follow the camera focus to provide finite
coverage, but their texture field does not move with them. Camera scrolling,
zooming, and orbiting only reveal a different part of the same field; they do
not re-voxelize, reproject, or regenerate it.

Wind advances the world-space texture continuously, so the mist visibly flows
through the garden even while the player is still. The three layers use
different scale, phase, height, opacity, and drift response. This supplies
parallax and depth without raymarching.

Opaque geometry writes depth before the transparent mist pass. Ground, walls,
trees, characters, and models therefore cut through each layer naturally.
Layer edges sit beyond a radial alpha fade and are not visible.

## Interaction and cozy lighting

The player contributes one current swept capsule plus three slowly closing
trail segments. The two closest enemies can contribute one swept capsule each.
Fast movement is represented from previous to current position, so dashes do
not leave gaps. Each sweep clears the center and raises a subtle rim at its
sides, approximating displaced low fog without a fluid texture or compute
shader.

The four nearest warm lights are evaluated analytically in the mist shader.
This produces small amber pools around lamps and fires while avoiding
clustered-light work across three screen-sized transparent meshes. All Godot
volumetric-scattering energy remains zero.

## Fixed performance budgets

- 3 planes and therefore at most 3 mist draw calls;
- 3 noise samples per layer;
- 6 swept interaction segments total;
- 2 enemy interactors, selected at 4 Hz;
- 4 warm lights, selected at 2 Hz;
- interaction history updated at 30 Hz;
- no raymarch, screen/depth texture sample, compute dispatch, simulation
  texture, per-tile node, or temporal history;
- cost depends on visible pixels, never world tile/model count.

The planes contain only two triangles each. Their source noise texture is
generated once, is seamless and mipmapped, and is reused by all layers.

## Art tuning

The mist profile and debug lighting cockpit expose:

- `ground_fog_density`
- `ground_fog_height`
- `ground_fog_noise_scale`
- `ground_fog_wind`
- `ground_fog_disturbance_radius`
- `ground_fog_close_seconds`
- `fog_color`

`ground_fog_wind` controls the direction and speed of the live world flow.
Keep `fog_color` fairly neutral; the fixed local-light budget supplies the
cozy warmth around lamps and fires.

## Debugging and regression checks

Run the exact development engine with mist forced on:

```powershell
& "C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe" --path "C:\Dev\suma-nook" -- --weather=mist --perf-overlay
```

Combine it with `--maxed-world` for the 10,000-tile/10,000-model stress world.
`tests/fog_capture.tscn` saves mist-on, mist-off control, and night actor-wake
frames. `tests/fog_performance_runner.tscn` measures day, moving mist, and
repeated 20-42 distance scrolling in the same process.

`LightingRig.runtime_manifest().fog` confirms:

- legacy fog disabled;
- volumetric fog and temporal reprojection disabled;
- full-resolution world-space renderer active;
- no screen-space sampling;
- fixed layer, sweep, enemy, and light budgets.

## Measured maxed-world result

`tests/fog_performance_runner.tscn` holds the complete mist weather profile
constant and toggles only the layer density. On the RTX 3090 development
machine at 1920x1080 with Godot 4.6.3 Forward+, the
10,000-tile/10,000-model world contains 20,000 render instances and 581
authored warm lights.

| State | Average | p95 frame |
| --- | ---: | ---: |
| Mist profile, layers disabled | 143.9 FPS / 6.948 ms | 7.672 ms |
| Moving world-space layers enabled | 144.0 FPS / 6.942 ms | 7.569 ms |
| Layers enabled, repeated 20-42 scrolling | 144.0 FPS / 6.944 ms | 7.657 ms |

All samples sustained the 144 FPS cap. The scrolling run changed zoom four
times and recorded a 7.883 ms p99 frame. The measured average delta was
-0.006 ms, which is cap/timing noise rather than a claim that the effect has
negative cost. The useful result is that the fixed three-layer renderer adds
no observable frame-time regression or scroll spike in the maximum debug
world.

Refresh these figures from `FOG_PERFORMANCE_RESULT` whenever the renderer
changes; never carry results forward from the retired froxel implementation.
