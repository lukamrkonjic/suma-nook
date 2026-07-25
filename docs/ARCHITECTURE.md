# Architecture

## State flow

`Main` constructs explicit system references; there is no global event-bus singleton.
Authoritative state lives in `GridManager`, `EconomyManager`, `StorageManager`,
`CollectionManager`, and `RewardManager`. The HUD and 3D nodes observe signals and animate
transactions, but never own balances or placement truth.

`GridManager` has three constant-time maps:

- ground: `Vector3i(x, 0, z) -> definition_id`;
- props: `instance_id -> definition_id/coord/rotation`;
- occupancy: every occupied `Vector3i(x, elevation, z) -> instance_id`.

Bloomforge owns a protected center cell. Ground and prop placement use separate validation
paths. Footprints rotate before validation, all cells need support, and upper layers require
a stackable prop below. The placement controller temporarily removes a moved object's
occupancy while retaining its original state; cancel restores that dictionary verbatim.

## Rendering

The main world, HUD, camera, and particles live in a native 1280×720 antialiased
`SubViewport`. `WorldBuilder` owns the three background/light/fog/effect presets.
`VisualFactory` creates cached matte materials and smooth toy-like procedural meshes.
`GridRenderer` syncs only when grid state changes; it does no per-frame world scan.

The orthographic rig computes cursor-to-ground rays through the active camera, so picking
and preview snapping stay coherent across 90-degree rotation, zoom, and pan.

## Visitors

Motes use a focused state machine:

`SPAWNING -> ARRIVING -> WANDERING/INTERACTING -> READY_WITH_COIN ->
REWARDING_PLAYER -> RELAXING -> LEAVING`.

Navigation is a small grid BFS over currently walkable ground. Destinations are reserved,
blocking props are excluded, invalid routes request a replacement, and interaction
destinations are reachable cells adjacent to tagged props. Navigation changes only after a
grid transaction or a new destination request.

## Rewards and persistence

Token and item definitions load from JSON into typed `RefCounted` definitions. The reward
manager selects by themed pool and weight, then applies generic hooks and placed curio
modifiers. Per-pool beginner sequences and expansion pity prevent progression deadlocks.

Saves contain plain data only. The save manager writes JSON to a temporary file, reparses it,
rotates the previous save to a backup, and atomically renames the validated temporary file.
The schema includes grid, unique instance IDs, currency, sale progress, storage, discoveries,
RNG state, visitors, camera, environment, audio levels, timestamps, held-item transaction
state, and a committed pending reward. Missing definitions are skipped and reported rather than
instantiated as broken nodes.

## Scale path

Thousands of definitions require no reward or UI code changes. The current small garden
uses individual MeshInstances and transaction-time render synchronization. The migration
point for a much larger garden is inside `GridRenderer`/`VisualFactory`: repeated static
parts can move to material-keyed `MultiMeshInstance3D` batches without changing persistence,
placement, or reward data.
