# Suma Nook architecture (living world progression MVP)

## Shape of the program

`GameCore` (RefCounted) is the composition root for ALL gameplay state — it
owns the registries, the seeded RNG service, the `WorldGrid`, and one manager
per concern. It has no scene-tree dependency, which is why the entire game
logic runs under `tests/test_runner.gd` headlessly.

`main.gd` builds the scene side around a GameCore: lighting rig, world
renderer, effects, player, camera, placement controller, HUD/panels/reveal,
audio. Scene controllers subscribe to manager signals; they never own state.
There is no global event bus and no autoload: every dependency is passed
explicitly in `setup()` calls, so ownership is traceable from `main.gd`.

## The grid is for construction, never locomotion

`WorldGrid` maps ground `Vector2i` and raised `Vector3i` slots to `CellState`
(tile id, rotation, starter flag, anchor runtime, structures with stable
instance ids, landmark tag). It owns adjacency/overlap/connectivity/elevation
rules, data-defined socket allocation (0–1 major + N decor per tile),
safe-relocation queries, and serialization.

The player is a `CharacterBody3D` with a continuous float transform —
camera-relative acceleration, `move_and_slide` every tick, dodge impulses.
Grid coordinates are only ever *derived* from the position for placement and
interaction queries. The save stores the exact float position and facing.
`TileVisualFactory` interprets each tile's `render_profile` and
`collision_profile`; adding a water-like tile no longer requires an ID check
inside `WorldRenderer`. Open edges get invisible boundary walls rebuilt on
grid changes.

## Reward generosity contract

`RewardManager` + `ParcelManager` implement the current peaceful loop:

- named seeded RNG streams, serialized in the save (`RngService`);
- hobbies award XP, journal discoveries, and rare finished world pieces;
- ferry parcels reveal three complete tiles; duplicates become Pattern Dust;
- new-discovery pity forces an undiscovered tile after repeated duplicates;
- pending parcel reveals persist atomically through restart.

Legacy material loot and crafting remain data-compatible but are disabled by
feature flags and are covered as dormant paths in tests.

## Landmark lifecycle

`LandmarkManager` and combat retain their isolated, tested lifecycle behind
disabled feature flags. Ordinary world growth cannot spawn hostiles in the
current product configuration.

## Rendering & style

One `LightingRig` (scene: `GardenStyleLightingRig.tscn`) drives environment,
key light, SSAO, glow, fog, and rain from `VisualStyleProfile` resources
(day/rain). `MaterialLibrary` builds shared flat matte materials from the
`CozyPalette` resource; `AssetLibrary` instantiates GLBs by stable asset id
and rebinds semantic material names to the library — palette edits reskin the
whole game with no re-export. `ContentValidator` checks every referenced GLB
at startup. Assets come from the headless Blender pipeline
(`art_source/procedural/build_assets.py`); Tier C hero swaps are file
replacements at the same asset id. `WorldRenderer` reconciles grid state into
nodes on change signals — no per-frame world scans.

## Persistence

`SaveManager`: versioned JSON at `user://suma_nook_world.json`, temp-write →
parse-validate → atomic rename, rotating `.backup`, and refusal of future
versions. `SaveMigrator` owns all schema upgrades before manager hydration.
`content_compat.json` separately owns stable content-ID aliases and retirement
policies. Missing historical definitions receive non-obtainable compatibility
visuals, so player-owned content is never silently deleted.

`WorldStateReconciler` repairs relationships after hydration: unsupported
elevation gaps and invalid socket occupants return to storage, duplicate
instance IDs are repaired, and an invalid home cell moves to the nearest safe
land. Moving a placed piece is a transaction: autosave pauses while it is
held, and any explicit save first restores the piece.

Autosave runs on meaningful events with a periodic dirty-flag timer.
Everything round-trips: grid, anchors, structures (instance ids), inventory,
stock, equipment + appearance unlocks, collection, skills, pity, pending
reveals, landmark states, RNG stream states, and the float player transform.

## Scale path

Cell storage is dictionary-keyed by coordinate; renderer updates are
per-changed-cell; edge walls rebuild per grid change (O(cells)); anchors tick
only while resting. For much larger worlds the WorldRenderer can partition
holders into chunk parents and stream by camera bounds without touching the
state contract. Visitor hooks (seating/viewing/social tags on structures)
exist as metadata only — deliberately unimplemented.

## Safe content CRUD

- Add: create the JSON definition and referenced GLB; startup validation fails
  loudly for bad references or behavior profiles.
- Rename: add `old_id: new_id` under the matching kind in
  `data/content_compat.json`, then increment its revision and
  `tuning.json`'s `content_revision`.
- Retire: keep the definition, or add a retired policy. Retired fallback tiles
  are preserved in saves but excluded from new parcel rolls.
- Delete: only remove an old definition after an alias or retirement policy
  has shipped. The load path still preserves truly unknown historical IDs.

## Testing

- `tests/test_runner.gd` — complete headless core suite (must print
  ALL TESTS PASSED).
- `tests/full_loop_runner.tscn` — drives the real scene through creation,
  movement, hobbies, ferry, placement, stacking, save-during-move, reload,
  pause UI, and admin controls.
- `tests/admin_asset_world_runner.tscn` — validates the curated asset gallery.
