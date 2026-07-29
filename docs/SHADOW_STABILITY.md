# Zoom-Stable Directional Shadows

## Root cause

Camera zoom is a dolly with render-frame damping:

```gdscript
camera.position.z = lerpf(camera.position.z, _size_target, 8.0 * delta)
```

The old lighting path listened to the target-distance signal and immediately
changed `DirectionalLight3D.directional_shadow_max_distance` to
`target + 20`. A mouse-wheel gesture could update that target several times
while the camera was still easing.

Changing the maximum distance changes the directional shadow projection. The
shadow texel grid was therefore resized and re-snapped multiple times during
one visible zoom, which appeared as intermittent shadow flicker.

## Fix

Directional shadows now use one fixed full-zoom envelope:

- maximum authored camera distance: 70 units;
- required caster padding: 20 units;
- stable envelope: 90 units;
- profile `shadow_max_distance` may lower the envelope, but zoom cannot change
  it.

Weather/profile changes still apply their authored cascade layout, bias,
softness, and maximum-distance cap. Fog and rain coverage continue responding
to zoom because resizing those bounded effects does not re-project the shadow
atlas.

The project uses a 4096 px directional shadow map. At the fixed envelope this
retains clean contact shadows at close zoom while providing complete coverage
at the farthest view.

## Regression coverage

`tests/shadow_zoom_regression.tscn`:

- checks day, mist, and rain;
- sends distances 14, 20, 32, 42, 70, and 14;
- performs actual damped 20-to-70-to-20 zoom motion;
- fails if the live shadow envelope changes on any frame;
- captures close and far visual references.

`tests/shadow_zoom_performance_runner.tscn` performs repeated extreme 20-70
zooming in the 10,000-tile/10,000-model world.

## Measured maximum-world result

Godot 4.6.3 Forward+, 1920x1080, RTX 3090:

| Metric | Result |
| --- | ---: |
| Average | 144.0 FPS / 6.945 ms |
| p95 frame | 7.309 ms |
| p99 frame | 7.395 ms |
| Zoom changes | 5 |
| Zoom range | 20-70 |
| Shadow envelope range | 90.0-90.0 |

The full stress world contains 10,000 tiles, 10,000 models, 20,000 render
instances, and 581 authored warm lights. It sustained the 144 FPS cap with no
shadow-envelope mutation.
