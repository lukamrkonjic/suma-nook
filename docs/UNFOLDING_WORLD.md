# The Unfolding World

Suma is a god-view creative world builder: the world grows as permanent,
generated nature Nooks that the player reshapes and builds into from above.
Creative expression is the purpose; every system below serves it.

## Design pillars (locked)

1. World grows as connected chunk-Nooks, revealed via the falling-tile wave.
2. Only nature generates. All civilization is player-placed.
3. Trees/stones are terrain-with-resistance (chop, crack, pry, plant) — not
   an economy.
4. Discovery = buried treasures, transformation Firsts, one dormant mystery
   per Nook, keepsake moments. Never visible requests.
5. Progressive breadth, unlimited depth: unlocks gate *kinds*, never
   quantities (saplings are literally unlimited in the Build Bag).
6. The opening chooses 1-of-3 seeds. Later growth chooses any open frontier
   slot; the procedural pools surprise you with the Nook itself.

## Architecture

Honors the repo rule "no global event bus" by scoping the hub: `GameCore`
owns one `WorldEvents` instance and injects it explicitly. There is no
autoload and no service locator.

```
content registry (data/*.json, typed NookDefs, validated at boot)
        │
NookModule ──> NookGenerator (pure, deterministic)  ──> NookPlan
   │                │
   │           WorldCommandService (single mutation choke point + log)
   │                │ mutates WorldGrid, publishes events
   ▼                ▼
NookWorld      WorldEvents (scoped hub; typed + world_signal mirror)
 (chunk meta)       │
        ┌───────────┼──────────────┬─────────────┐
   TreasureSystem  FirstsSystem  DormantSystem  KeepsakeSystem
        └───────────┴─────┬────────┴─────────────┘
                   DiscoveryJournal (entries + unlock sets)
```

Every discovery system is a pure listener behind its own feature flag
(`nook_treasures_enabled`, `nook_firsts_enabled`, `nook_dormants_enabled`,
`nook_keepsakes_enabled`; `nooks_enabled` gates the whole feature). Flip any
flag off and the game keeps running — you just find less.

## Content families

All validated by `NookDefinitionValidator` with hard errors on dangling
references:

| File | Kind | What it declares |
| --- | --- | --- |
| `data/nook_biomes.json` | `nook_biomes` | slot→pool palettes, densities, moods, treasure tables, drift weights |
| `data/nook_stamps.json` | `nook_stamps` | hand-authored landform grids in palette slots, edges, dormant sockets |
| `data/nook_moods.json` | `nook_moods` | descriptive procedural mood metadata; expansion never changes global weather or time |
| `data/treasure_tables.json` | `treasure_tables` | host-tag slots rolled at generation |
| `data/firsts.json` | `firsts` | world-signal triggers, chunk-lacked conditions, unlocks, journal text |
| `data/dormants.json` | `dormants` | dormant structure, wake score, reward, journal page |
| `data/moments.json` | `moments` | keepsake counters and chunk co-occurrences |
| `data/nook_config.json` | object | compact chunk size (4), silhouette cuts, origin, offer rules, growth lines, dormant scoring |
| `data/reveal.json` | object | the entire reveal wave timing surface |

Stamps reference palette *slots* ("ground", "water", "tree"); each biome
resolves slots to concrete tile/structure IDs at generation. Author a stamp
once, it reads correctly in every biome.

## Key behaviors

- **Generation is deterministic**: same seed card → same Nook, including
  treasure assignment (stored in chunk meta, so re-rolling can't farm).
  New Nooks are compact 4×4 slates with one or two cut-away corners and a
  guaranteed readable knoll; rocky Nooks may form a two-level shoulder.
  Pre-4×4 saves keep their original 8×8 coordinate spacing.
- **Frontier glows**: every unrevealed Nook slot beside the world gets one
  small dot, including concave gaps between two branches. Clicking one, or
  targeting it with the build cursor and confirming, immediately rolls a Nook
  from the authored biome/density/mood/stamp pools. Neighboring biomes still
  multiply their own weight, but growth has no activity or inventory cost.
- **Clearing**: harvest profiles gained `on_final: "clear"` and `leaves`.
  Trees chop down to a pryable stump; stones crack to nothing; the
  `source_cleared` signal routes through `NookModule` into the
  `clear_feature` command. Save state gained the `cleared` harvest state.
- **Planting**: first-stage sapling structures are unlimited in stock
  (`StockManager.set_unlimited_structure`); placing one through the normal
  build flow is adopted as a growing plant (`NookModule.adopt_planted`) —
  the build flow *is* the planting flow. Growth advances by unix deadline
  (offline catch-up free) via the `advance_growth` command.
- **Dormants**: wake score accumulates from nearby life (placements,
  plantings, maturities, Firsts, presence minutes). Crossing the threshold
  defers the wake to the next session (`apply_pending_wakes` on load) — you
  arrive and it has changed. No marker, no bar, ever.
- **Firsts/keepsakes rule (enforced)**: no discovery system renders any UI
  before it fires. Journal entries appear only afterwards.
- **Reveal wave**: `NookRevealTimeline` (pure math, tested headless) +
  `NookRevealPresenter` (falling tiles from the connecting seam, feature
  pops behind the wavefront). State commits before presentation starts;
  expansion never changes the selected weather or time, and interrupting the
  animation cannot lose anything.

## UI

- The resting world is god view. There is no character-placement dock.
  Pointer users drag any tile or model directly; controller users target the
  same pieces with the build cursor and the named `move_piece` action.
- `NookOfferPanel`: opening-only 3-card seed ritual with deterministic focus.
- `NookFrontierMarkers`: pointer hit targets plus build-cursor cells for every
  open neighboring slot; `build_confirm` unfolds the selected Nook.
- Atlas v1 lives in the map panel: pending-offer entry, world map, named
  Nook registry (biome/mood/finds), the name-the-Nook ritual, and journal
  excerpts.

## Known follow-ups

- Reveal wave in scalable (MultiMesh) worlds: per-cell holders don't exist
  there; the presenter degrades to an instant reveal.
- Treasure unfold uses a toast + journal entry; the GG-style flat→bloom
  unfold animation is still to be built on the reward reveal presenter.
- Seam edge contracts are conservative (stamps keep a margin from chunk
  borders); cross-chunk river/path continuation is Phase 4+ polish.
- Camera pullback/seam drift during reveal is not yet implemented.
- Mood lighting is global; per-Nook local moods would need light volumes.

## Tests

`tests/test_runner.gd` suites: `_test_unfolding_world_generation`,
`_offers_and_reveal`, `_clearing_and_treasure`, `_firsts`,
`_growth_and_keepsakes`, `_dormants`, `_save_round_trip`, `_flags_off`,
`_reveal_timeline`, `_planting_flow`.
