# Suma Nook architecture

## Authoritative game state

`Main` constructs explicit references; there is no global singleton event bus.

- `GridManager` owns connected ground, placed props, occupancy, walkability, and BFS paths.
- `SumaPlayerCharacter` owns character identity, appearance, current cell, and active path.
- `ForestProgression` owns grown-tile count, claimed milestones, deterministic tile choice,
  and the one-light growth transaction.
- `EconomyManager` stores Forest Light in the existing stable `meadow_coin` balance.
- `StorageManager` and `CollectionManager` own unlocked decorations and the field guide.

The initial island uses radius one, yielding exactly nine ground cells. No system blocks the
center cell. Ground placement is valid only when the new cell shares a cardinal edge with an
existing cell, which keeps every player-grown world connected.

## Player and growth flow

The HUD emits a chosen name and three palette indices. The player builds a nearest-filtered
pixel sprite from those indices and can traverse only `GridManager.is_walkable()` cells.
Clicks use the orthographic camera's ground ray and BFS; keyboard input requests one cardinal
step.

Growth is a two-phase transaction:

1. `Main.start_growth()` verifies that one Forest Light exists and asks
   `PlacementController` to hold a deterministic ground definition with source `growth`.
2. Cancel costs nothing. A successful adjacent placement emits `placement_completed`;
   `ForestProgression.complete_growth()` then spends exactly one light, advances the count,
   and grants a milestone decoration when applicable.

This ordering prevents failed or cancelled placements from eating currency.

## Pixel-art renderer

`SumaPixelArt` creates small RGBA images for the hero, wisps, forest frame, props, tile
patterns, and light glyphs. Every texture uses nearest filtering. `VisualFactory` renders
ground as thick square diorama blocks and all props as shadow-casting `Sprite3D` nodes.
There is deliberately no pixelation post-process.

`WorldBuilder` owns the tiled moss backdrop, distant tree and bush frame, hard canopy light,
fireflies, rain, and the Greenwood / Firefly Dusk / Moss Rain palettes. `GridRenderer`
reconciles world nodes only on state changes.

## Wisps

Woodland wisps retain the original visitor state machine and reachable-grid wandering:

`SPAWNING -> ARRIVING -> WANDERING/INTERACTING -> READY_WITH_LIGHT ->
REWARDING_PLAYER -> RELAXING -> LEAVING`.

Each wisp has a generous capsule pick area on its own collision layer. Both direct 3D input
and `Main`'s explicit ray fallback collect it, addressing missed clicks on small sprites.
Collected rewards are normalized to Forest Light.

## Persistence

Schema version 3 saves plain JSON through validated temporary-write, backup-rotation, and
atomic rename. It includes grid, player identity and palette, growth count and milestones,
Forest Light, storage, discoveries, visitors, camera, weather, audio, and held placement.
The save lives at `user://suma-nook-save.json`; the pre-redesign Tilegarden save is
intentionally not migrated.

## Scale path

The current sprite nodes are appropriate for the vertical slice. At hundreds or thousands
of tiles, the state contract stays unchanged while `GridRenderer` can chunk ground into
material-keyed `MultiMeshInstance3D` batches and stream distant decoration sprites by camera
bounds.
