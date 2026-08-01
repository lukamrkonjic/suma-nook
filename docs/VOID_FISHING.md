# Suma — void fishing and the Catch Basket

Status: current implementation authority, 2026-08-01.

This document supersedes `docs/DISCOVERY_PROGRESSION.md` (the broad
void-discovery pool, local biome pools, and the three-spare Void Exchange)
and the unimplemented `docs/STARFISHING_LURES_AND_SPIRITS_PLAN.md`. Those
files remain as historical records.

## The design rule

**Tiles and models are the game. Building is the main activity. Fishing
exists to provide a cozy, repeatable, surprising stream of physical building
content.** Fishing is not an RPG, a survival system, or a collection subgame;
it is the magical funnel through which the world grows.

```
BUILD A WORLD → THE BUILT ENVIRONMENT SHAPES NEARBY FISHING → FISH FROM AN
EDGE → RECEIVE TILE BUNDLES, MODELS, OR RARE KEEPSAKES → PLACE THEM →
CREATE NEW FISHING HABITATS → REPEAT
```

## Player gameplay

- **Wild Cast, always.** Walk to any exposed edge and press interact. The
  magical rod appears; no bait, no inventory, no workshop, no preparation.
  Wild Cast is the permanent default and stays valuable forever.
- **The world you built decides.** Every cast samples the 3×3 block of land
  around the keeper's cell and reduces it to broad themes (GROVE, STONE,
  WILD, ODDITY). Grassy groves lean grove; stone terraces lean stone; mixed
  ground stays wild. Nearby placed models season the sample (a couple of
  distinct pieces at most, always as broad themes, never as exact items).
  Building a themed cove for better themed catches is intended play.
- **A catch always lands in 10–30 seconds.** Cast → a bounded wait → a clear
  bite. Press the fishing input at the bite to reel in faster; do nothing and
  the rod retrieves the same catch automatically a few seconds later.
  Attention changes speed only — never the reward. Fishing cannot fail, and
  the rod recasts by itself until you walk away or the basket fills.
- **Hauls are physical.** Every catch is staged in the three-slot Catch
  Basket beside the keeper. Most catches are one reward (~80%); Rich catches
  carry two (~17%) and Bountiful catches three (~3%), always presented as
  one dramatic haul in one basket slot.
- **Tile bundles carry real volume.** Common bundles hold 4–8 copies,
  uncommon 2–4, rare 1–2. Taking a bundle enters ordinary tile placement;
  unplaced copies return to the basket when you leave build mode. Models are
  caught individually and go to the Build Library for placement.
- **Keepsakes are separate bonuses.** A rare independent roll can append a
  glowing Keepsake charm to any haul — it never replaces a normal reward.
  The first Keepsake is the Growth Keepsake: once activated, placed pines
  can be shifted between their young, mature, and tall forms.
- **The Spirit Pouch (five charms).** Finishing a full tree-tending cycle
  can settle a Grove Spirit into the pouch; working stone (when mining
  ships) settles a Stone Spirit. Arming a Spirit strongly leans exactly one
  catch toward its theme — never rarity, haul size, quantities, or Keepsake
  odds. Selecting Wild Cast clears the armed charm without losing it. A full
  pouch politely refuses new charms.
- **A full basket pauses fishing.** Three waiting hauls stop the recast with
  gentle feedback; nothing is discarded. Take a haul into placement — or
  return it to the void, with no compensation — and fishing resumes.
- **Invisible kindness.** Long dry streaks quietly raise rare and Keepsake
  odds. There is no visible pity meter and there never will be.

## Architecture

`scripts/features/fishing/` follows a strict layering. Presentation never
rolls rewards; the domain never touches the scene tree.

```
domain/        pure rules & data (RefCounted, headless)
  fishing_balance.gd         typed façade over data/fishing_balance.json
  fishing_session_states.gd  IDLE·CASTING·WAITING·BITE·MANUAL_REELING·
                             AUTO_REELING·REVEALING·PAUSED_BASKET_FULL
  fishing_habitat_sample.gd  immutable 3×3 theme snapshot
  fishing_roll_context.gd    per-cast context (habitat, spirit theme, unlocks)
  fishing_reward.gd          TILE_BUNDLE | MODEL | KEEPSAKE entry
  fishing_haul.gd            1–3 entries + optional keepsake, one basket slot
  spirit_pouch_state.gd      5 slots, arm/reserve/consume/release rules
  hidden_luck_state.gd       invisible protection counters
application/
  fishing_session_service.gd tick-driven state machine (GameCore.tick drives
                             it; no Godot timers, fully deterministic)
  fishing_reward_generator.gd pool → candidates → habitat/Spirit weights →
                             luck → pick; haul at the bite so manual and
                             auto retrieval provably share one reward
  haul_composer.gd           single/rich/bountiful and form sequences
  spirit_pouch_service.gd    pouch rules + presentation signals
  hidden_luck_service.gd     pity math, resets only on committed rewards
ports/
  world_habitat_query.gd     anchor → HabitatSample
  loot_catalog_port.gd       (form, pool, unlock groups) → candidates
  reward_delivery_port.gd    commit(haul), is_full, slot_freed
adapters/
  grid_habitat_adapter.gd    WorldGrid 3×3 read, revision-keyed cache
  build_catalog_adapter.gd   indexed loot with invalid-reference exclusion
  catch_basket_adapter.gd    3 hauls, bundle checkout/reclaim into Stock
  activity_spirit_adapter.gd activity_cycle_completed → pouch request
  fishing_keepsake_service.gd applies keepsake effects outside the generator
fishing_module.gd            composition root, versioned save payload,
                             debug/simulation surface
fishing_definition_validator.gd content contract (registered in
                             GameContentCatalog)
```

Boundaries that hold:

- Fishing hands rewards to the existing pipelines by **stable id only**:
  bundles/models check into `StockManager` and place through
  `PlacementController`; it never knows how a piece renders or validates.
- Woodcutting/mining publish `ProgressionModule.activity_cycle_completed`;
  the Spirit adapter maps skill → Spirit through `SpiritDefinition` data.
  Fishing never calls activity code and vice versa.
- Ambient fish are visual water animals only. The fishing module cannot
  express a creature reward (validated at load, tested mechanically).
- RNG is `RngService` named streams — seeded, serialized, deterministic.
- The ferry gift kept the old `DiscoverySystem` pending-reveal path; it is
  a separate feature and no longer part of fishing.

### Data

- `data/fishing_loot.json` — `FishingLootDefinition`: reward form, the
  referenced building id, theme tags, pool tags (local/global/wildcard),
  rarity, weight, bundle range, `unlock_group` (default `core`). Adding a
  tile or model to fishing is data-only; the generator never changes.
- `data/fishing_spirits.json` — Spirit charms (theme + source skill).
- `data/fishing_keepsakes.json` — Keepsake charms (effect id).
- `data/fishing_balance.json` — every timing, probability, bundle range,
  pity threshold, pool weight, and the habitat theme-mapping tables.

### Save schema

`features.fishing` (schema_version 1): `first_catch_done`, pouch slots +
armed index, basket hauls + `next_haul_id` + any bundle checkout, luck
counters, activated keepsakes. Progression is now **version 4**; the v3→v4
migration refunds partial Void Exchange offerings to Stock (deterministic
key order), retires local discovery progress, moves the first-catch flag,
scrubs released-fish journal records (archived under
`progression.archived_v3`), and completes retired onboarding stages. Loading
cancels an in-flight cast; a reserved-but-unconsumed Spirit stays armed.
Saves that reference removed content keep every valid basket entry and
replace a missing bundle tile with the safe fallback.

### Adding a Spirit theme later

Add the theme to loot `theme_tags` and the habitat mapping tables, author a
`SpiritDefinition` with `source_skill` set to the activity that should grant
it, and have that activity call
`progression.on_activity_cycle_completed(skill_id)` when a full source cycle
ends. No reward-generator changes.

### Debug & balancing

Development-only (pause-menu admin page + `FishingModule` API): habitat
inspection, forced single/rich/bountiful catches, forced Keepsakes, pouch
and basket fill/clear, seeded simulations. CLI:
`Godot --headless --path . --script tools/fishing_simulation.gd`
(≥100,000 virtual catches through the live services; `seed=`, `catches=`,
`spirit=` args). Tests: `tests/fishing_test_runner.gd`.

## Postponed features (documented, not implemented)

- **Exploration / hidden islands** — future islands activate additional
  loot `unlock_group`s; the field exists today, only `core` is active.
- **Special fishing edges** — a future edge-modifier provider may add
  unique pools or visuals; the current provider returns no modifiers.
- **Tide Spirit** — waits for a meaningful water activity; uses the same
  SpiritDefinition/theme architecture when it lands.
- **Crab pots / passive collectors** — may later call the same reward
  generator through a different catch source and balance profile.
- **Visitors** — may later grant Spirits or gifts through the same narrow
  event interfaces.
- **Cosmetic rods** — presentation swaps only; never stats or loadouts.
- **Discovery Book** — may listen to haul-committed events; the fishing
  domain will never depend on it.
- **Duplicate handling** — only if playtesting proves duplicates
  frustrating; no currency pre-emptively. Returning a haul to the void
  already exists and pays nothing.
- **Bait Workshop** — decoration or future display space only; never
  mandatory infrastructure.
- **Collectible fish** — deliberately removed. Swimming fish remain
  ambient; pond fishing is catch-and-release presentation only.
