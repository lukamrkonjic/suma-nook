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

`WorldGrid` maps `Vector2i` → `CellState` (tile id, rotation, starter flag,
anchor runtime, structures with stable instance ids, landmark tag). It owns
adjacency/overlap/connectivity rules, socket allocation (1 major + N decor
per tile), safe-relocation queries, and serialization.

The player is a `CharacterBody3D` with a continuous float transform —
camera-relative acceleration, `move_and_slide` every tick, dodge impulses.
Grid coordinates are only ever *derived* from the position for placement and
interaction queries. The save stores the exact float position and facing.
Colliders: every tile contributes an identical-height ground box (zero seams);
open edges get invisible boundary walls rebuilt on grid changes; pond basins
carry a local blocker so the shore is walkable but the deep middle is not.

## Reward generosity contract

`RewardManager` + `ParcelManager` implement the anti-frustration rules:
- named seeded RNG streams, serialized in the save (`RngService`);
- tutorial guarantees (fragment by catch N; first parcel at Fishing 2; first
  reveal is the grove trio so Woodcutting can never be luck-blocked);
- rare pity ramps to certainty at a tuned dry-streak cap, per skill, saved;
- duplicates → Pattern Dust + a new-discovery pity that forces an
  undiscovered tile into a reveal after N duplicate choices;
- every essential recipe unlocks deterministically from skill levels;
- pending parcel reveals persist in the save (parcel consumption is atomic at
  open; closing mid-reveal loses nothing).

## Landmark lifecycle

`LandmarkManager`: silhouette (beyond the world, in fog, footprint reserved,
never overlapping land) → revealed (world touches footprint; cells become real
ground; `LandmarkEncounter` spawns enemies from the saved roster) → reclaimed
(guardian falls; idempotent reward via `reward_claimed`) → kept / packed into
a deed (cells released, re-placeable) / salvaged (materials). Defeat is
gentle: full heal at home, wounded enemies recover, defeated ones stay dead
for the claim.

## Rendering & style

One `LightingRig` (scene: `GardenStyleLightingRig.tscn`) drives environment,
key light, SSAO, glow, fog, and rain from `VisualStyleProfile` resources
(day/rain). `MaterialLibrary` builds shared flat matte materials from the
`CozyPalette` resource; `AssetLibrary` instantiates GLBs by stable asset id
and rebinds semantic material names to the library — palette edits reskin the
whole game with no re-export. Assets come from the headless Blender pipeline
(`art_source/procedural/build_assets.py`); Tier C hero swaps are file
replacements at the same asset id. `WorldRenderer` reconciles grid state into
nodes on change signals — no per-frame world scans.

## Persistence

`SaveManager`: versioned JSON at `user://suma_nook_world.json`, temp-write →
parse-validate → atomic rename, rotating `.backup`, refuses future versions,
tolerates missing definitions (dropped with warnings). Autosave on meaningful
events (placement, level-up, claims) with a periodic dirty-flag timer.
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

## Testing

- `tests/test_runner.gd` — 100-assertion headless core suite (must print
  ALL TESTS PASSED).
- `tests/full_loop_runner.tscn` — drives the real scene through the complete
  MVP acceptance loop (57+ checks, captures the docs screenshots).
