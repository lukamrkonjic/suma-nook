# Rework audit — ferry and XP-only hobbies

## Current iteration (2026-08-07): The Unfolding World

Suma's progression now grows as permanent generated nature Nooks (8x8
chunks) revealed through a falling-tile wave, cleared by hand (chop/crack/
pry leave real absence: stumps, clean ground), replanted with unlimited
saplings, and mined for invisible generation-time discoveries (buried
treasures, transformation Firsts, one dormant mystery per Nook, keepsake
moments). See docs/UNFOLDING_WORLD.md for architecture, content families,
flags, and follow-ups. Headless suites cover generation determinism,
offers/reveal, clearing/treasure, firsts, growth/keepsakes, dormants, save
round trip, flags-off, reveal timeline, and the planting flow.

---


## Current iteration (2026-07-25)

### Project-selection correction

The ferry/XP-only audit was first implemented in
`/Users/luka/Documents/dev/imota-tilegarden-mvp` because the brief described
that as the likely project. The visual game Luka intended is this repository:
`/Users/luka/Documents/dev/suma-nook`.

The Tilegarden work remains intact on its own
`rework/ferry-and-xp-only-hobbies` branch. This Suma Nook branch adapts the
same design to Suma Nook's existing architecture; it does not copy or replace
Suma Nook's renderer, lighting, camera, character, props, or presentation.

### Retained

- Original low-poly diorama renderer, palette, lighting rig, assets, camera,
  continuous character movement, click-to-move, click feedback, and character
  creator.
- The nine-cell authored home composition, rearranged only as required to make
  its northern row water.
- `StockManager` as the counted Tile/Build Library.
- `ParcelManager` and its three-card randomized tile reveal.
- Existing collection journal, hobby XP/levels, placement, and atomic save
  systems.

### Replaced in active play

- Fishing and Woodland Tending now create `HobbyActionResult` values: XP,
  journal/record metadata, and an optional direct finished tile. They do not
  create fish, logs, reeds, resin, driftwood, or other material stacks.
- Fishing displays and automatically releases the catch.
- Land growth no longer depends on material crafting. Periodic deliveries are
  the primary source of Land Parcels.
- The generic material inventory UI is replaced by explicit Tile and Build
  Libraries.
- Fresh worlds use six land cells plus three connected open-water cells on the
  **northern/top row** (`y = -1`), with a dock facing outward into the fog.

### Modular arrival architecture

- `ArrivalScheduler` owns saved timing, pause/queue rules, presentation ID, and
  the current payload.
- `LandParcelPayload` describes the delivered reward.
- `DeliveryPoint` owns the approach, berth, package, departure, interaction,
  and camera-interest transforms.
- `FerryArrivalPresentation` owns only the ferry animation.
- `InstantPostcardArrivalPresentation` proves that presentation can change
  without changing schedule, parcel, Tile Library, or save logic.
- Only one delivery can wait. The next timer begins after the chosen tile is
  safely added to the Tile Library.

### Disabled behind `data/features.json`

- `legacy_material_loot_enabled = false`
- `material_crafting_enabled = false`
- `combat_enabled = false`
- `monsters_enabled = false`
- `hostile_landmarks_enabled = false`

The older systems remain parseable and recoverable, but are not instantiated
or surfaced in current play.

### Save behavior

Save schema v2 persists hobby progression, exact continuous player position,
world/stock state, arrival timer and presentation, waiting delivery, and
pending parcel options. Loading a v1 development save:

- backs it up on the next atomic save;
- preserves its former inventory under hidden `legacy_inventory`;
- converts the original three northern starter cells into connected water;
- relocates signature starter dressing to land where needed;
- safely relocates the player if their saved position is now water.

This is a pre-release schema change. The first load changes the three northern
starter cells; a clean save reset is optional, not required.

---

## Historical living-world rework

## Selected repository

- Path: `/Users/luka/Documents/dev/suma-nook` (chosen explicitly by Luka; the
  `imota-tilegarden-mvp` path named earlier in the brief does not exist).
- Godot: 4.6.3.stable.official (`/Applications/Godot.app/Contents/MacOS/Godot`).
- Blender for the asset pipeline: 5.1.2 (`/Applications/Blender.app/Contents/MacOS/Blender`).
- Starting branch/commit: `main` @ `6c42625` ("feat: grow a walkable pixel forest world"),
  clean working tree — no backup commit needed.
- Rework branch: `rework/living-world-progression-mvp`.
- The original Imota repository (`/Users/luka/Documents/dev/imota-idle`) is not touched.

## What existed before this rework

A pixel-art tile-hop prototype ("Suma Nook v3"): 9-tile isometric diorama, wisp visitors
delivering Forest Light, one-light-per-tile growth, milestone decoration unlocks,
runtime-generated pixel sprites (`pixel_art.gd`), Sprite3D props, JSON save v3,
gl_compatibility renderer, generated audio.

## Existing systems retained (as ideas/contracts, reimplemented)

- **Two-phase growth transaction** (validate → place → charge) → generalized into the
  parcel/placement transaction so cancelled placements never consume rewards.
- **Atomic save writes** (temp file → validate → rename → backup rotation) → kept and
  extended in the new `SaveManager`.
- **Deterministic milestone unlocks** → generalized into data-driven skill level unlocks.
- **Reconciling renderer** (state-diff, not per-frame rebuild) → kept as the pattern for
  `WorldRenderer`.
- **Generated audio** (`tools/generate_audio.py`) → pipeline retained, event set rebuilt.
- **Explicit dependency wiring, no global event bus** → kept and strengthened via
  `GameServices`.

## Existing systems removed or deprecated

- **Tile-hop player locomotion** (`player_character.gd`: `current_cell`, BFS `active
  path`, one-cardinal-step keyboard input, tween between cell centers) — violates the
  continuous-movement hard requirement. Replaced by a `CharacterBody3D` free-move
  controller; no grid quantization of the player transform remains active.
- **Pixel-art presentation** (`pixel_art.gd`, Sprite3D props, nearest filtering,
  gl_compatibility) — replaced by low-poly 3D meshes, Forward+ renderer, MSAA, SSAO.
- **Visitor/wisp economy** (`visitor_manager.gd`, `mote.gd`, click-to-collect currency) —
  explicit anti-pillar (click-tax visitor loop). Removed from the loop; extension-point
  metadata tags are kept on world objects for future visitors.
- **Forest Light single currency** — replaced by the XP/materials/discoveries economy.
- Old scripts are preserved unmodified under `legacy/` for reference until the MVP is
  validated; nothing references them at runtime. Old save
  (`user://suma-nook-save.json`) is not migrated (pre-release policy; new save file name).

## New systems created

See `docs/ARCHITECTURE.md` (rewritten) — GameServices wiring, RngService (named seeded
streams, saved state), definition registries loading typed Resources from `data/*.json`,
WorldGrid + WorldRenderer, PlacementController (ghost/rotate/move/undo/redo/connectivity
safety), SkillManager, RewardManager (loot + pity + tutorial guarantees), ParcelManager
(three-choice reveal, Pattern Dust), CraftingManager, InventoryManager, EquipmentManager
(visible attachments), LandmarkManager (horizon ring), CombatManager, CollectionManager,
SaveManager v1 (new schema), AudioManager (event API), player state machine, camera rig,
lighting rig + visual profiles, Blender headless Tier A asset pipeline.

## Assets

- Reused from Imota: none (different visual target). Fonts in `assets/fonts` retained.
- All 3D assets are original, generated by `art_source/procedural/build_assets.py`
  (headless Blender) into `assets/3d/final/`. Provenance in `docs/ASSET_PROVENANCE.md`.
- Garden Galaxy screenshots are read-only references; none of their data is present.

## Migration decisions & compatibility risks

- No save migration from schema 3 — the game concept changed; old saves describe a
  different game. New save: `user://suma_nook_world.json`, `save_version: 1`.
- gl_compatibility → Forward+ is a hard renderer switch; if Forward+ misbehaves on some
  target hardware, `mobile` is the documented fallback (SSAO lost, style degrades
  gracefully to shadow-only grounding).
- Old tests replaced wholesale by `tests/test_runner.gd` (new suites); the old
  full-loop runner is superseded by `tests/full_loop_runner.gd` (new acceptance flow).
