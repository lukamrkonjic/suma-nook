# Starfishing, Lures, and Settled Spirits — Implementation Plan (historical)

> **Superseded 2026-08-01, never implemented.** The shipped fishing rework
> (`docs/VOID_FISHING.md`) deliberately went the other way: no lures, no
> material consumption, no Echo Throne — Wild Cast plus habitat sampling,
> the five-slot Spirit Pouch, and the physical Catch Basket. Retained only
> for the reasoning history.

Status: retired unimplemented plan.

This plan defines the replacement for the current split between broad Void fishing, direct local skill discoveries, and the three-spare Void Exchange. It translates the decisions from the Garden Galaxy research into a system that keeps the gacha delight, makes ordinary fishing and woodcutting useful, gives players category control, and still converges toward collection completion.

The existing fishing presentation and sky work are paused and intentionally outside this change. During implementation, the constraints at the end of this document are regression requirements.

## 1. Goal

Build one legible progression loop:

1. The player shapes a world and places ordinary skill sources such as trees and ponds.
2. Ordinary skilling produces tangible, thematically sensible lure materials.
3. Persistent spirits sometimes settle at eligible sources, encouraging the player to move around their own world for a special opportunity.
4. The player Starfishes into the void with no lure, a natural lure, a spare collected piece, or a captured spirit.
5. Starfishing always produces a placeable discovery. The chosen input controls its collection and, later, its precision.
6. The player places discoveries, expands the world, unlocks more source contexts, and gradually gains stronger control over future pulls.

The short version is: **shape the world → work the world → choose how much to steer the next pull → Starfish → place something delightful.**

## 2. Product contract

### Locked decisions

- **Starfishing is the only source of placeable collection rewards.** Ordinary pond fishing, woodcutting, and future skills no longer directly award furniture, tiles, structures, or keepsakes.
- **A wild cast is always available.** It costs nothing and uses the broad weighted pool.
- **Natural lure materials guarantee a collection, not an exact item.** Logs, stone, fish, reeds, shells, metal, and later regional materials make ordinary skills useful without turning the game into crafting work.
- **A spare placeable can be used as a lure.** It guarantees that piece's collection, excludes the consumed exact item from that cast, and weights related items within the collection. One keeper copy is protected across Stock plus placed copies.
- **Settled spirits are persistent opportunities, not timed events.** They remain at their source until claimed. There is no expiry, streak loss, or fear of missing out.
- **Claiming a spirit-touched source grants its normal skilling output and captures a special Starfishing input.** This avoids proliferating star-touched variants of every material.
- **The total number of settled spirits is capped.** Building more sources changes where a spirit can settle; it does not inflate the global reward rate.
- **The Echo Throne never consumes its displayed focus.** It biases matching pulls and provides a visible route to an exact known copy.
- **Completion gains explicit control.** Once a collection is substantially complete, the player can choose a visible Seek New mode for that collection.
- **The first-ever Starfishing reward remains Open Water.** The foundational new-player flow must never be left to chance.

### Explicit non-goals

- No crafting tree, recipe grind, XP bar, skill level, tool durability, stamina, failure roll, or required material farming.
- No hidden pity counter, invisible luck stat, rotating daily pool, timed spirit, or monetized roll.
- No finite general inventory. Materials remain compact counted entries, and owned placeables remain in Stock.
- No requirement to optimize a dense source farm. The system should reward wandering through a personally made world.
- No change to Build Bag categories. Build organization and Star collections are separate content axes.

## 3. Current-to-target behavior

| Area | Current behavior | Target behavior |
| --- | --- | --- |
| Void fishing | Broad weighted discovery; first catch is Open Water | Wild Starfishing preserves this behavior; optional inputs steer later casts |
| Pond fishing | Catch-and-release presentation plus a direct local discovery | Catch-and-release plus one ordinary fishing lure roll; no placeable reward |
| Woodcutting | Every chop advances direct local discovery; tree rests after its cycle | One ordinary woodcutting lure roll when the full chop cycle completes; tree rests and regrows offline |
| Future mining | Defined but not active | One ordinary mining lure roll per completed source cycle |
| Duplicate handling | Three true spares are progressively consumed for one related result | One true spare may be consumed as a targeted Starfishing lure; keeper protection remains |
| Context | Nearby biome and structures select a direct local reward pool | Source context selects its ordinary loot table and the collection of a captured settled spirit |
| Rare opportunities | None | A persistent spirit settles at a valid source; claim it through the normal skill action |
| Exact targeting | None | Echo Throne focus, visible runes, and late-collection Seek New mode |
| Progress feel | Broad roll plus deterministic local rewards | Broad surprise early; category choice midgame; family/exact/completion control later |

## 4. Player-facing rules

### 4.1 Wild Starfishing

- The player chooses **Wild** or casts without selecting an input.
- Nothing is consumed.
- The result comes from the authored broad pool.
- The first-ever result is always `tile_open_water`.
- Wild remains useful for surprise, discovery across collections, and players who do not want to manage lures.

### 4.2 Natural lure Starfishing

- The player consumes one counted material from Inventory.
- The UI states the guaranteed collection before the cast, for example: `Softwood → Forest Collection`.
- The result is random inside that collection.
- Natural lures do not guarantee novelty or an exact item.
- A cancelled cast consumes nothing.

Initial mappings should reuse existing materials:

| Material | Initial collection contract |
| --- | --- |
| `softwood`, `hardwood`, `resin`, `seedwood` | Forest |
| `fish_dawnfin`, `fish_mosscarp`, `reeds`, `driftwood` | Water |
| `shell` | Beach |
| `smooth_stone`, `carved_stone` | Stone / Classic construction collection |
| `old_metal` | Urban |
| `relic_fragment` | Curio |

The final identifiers come from the collection content pass. A lure maps to exactly one primary collection in the first release so its promise is easy to understand.

### 4.3 Spare-piece Starfishing

- The player selects a tile or structure with at least one **true spare**.
- True spare count is `owned in Stock + placed in world - 1 protected keeper`.
- One Stock copy is consumed atomically with a successful reward grant. A placed copy is never silently removed.
- The result is guaranteed to be in the selected piece's Star collection.
- The exact consumed content ID is excluded from the candidate pool for that cast.
- Items sharing its authored `family_id` receive a visible weight bonus.
- If filtering produces no valid candidate, the cast does not start and the spare is not consumed.

### 4.4 Settled-spirit Starfishing

- A spirit can settle at an eligible tree, pond tile, and later other skill sources.
- Its visual remains until the relevant ordinary skill cycle is completed.
- Completion grants the normal material roll and adds one captured spirit charge to a small dedicated pouch.
- The source then enters its normal rest/recovery state; it is never deleted.
- Captured spirits are optional Starfishing inputs. The spirit guarantees a collection and adds one explicit boon.
- The pouch starts with a cap of three so spirit opportunities stay special and readable. If full, the spirit remains settled and the player receives clear feedback rather than losing it.

Initial boon vocabulary:

| Spirit | Effect shown to player |
| --- | --- |
| Kindred | Guaranteed collection; related family is more likely |
| Seeking | Guaranteed collection; unowned items only when at least one is valid |
| Generous | Guaranteed collection; grants a second roll from the same collection |
| Ancient | Guaranteed collection; keepsakes receive a visible weight bonus |
| Prismatic | Choose any unlocked collection before casting |

Ship the settling/capture loop with Kindred first. Add the other boons only after content volume and odds can support them without misleading fallbacks.

### 4.5 Echo Throne

- The Throne is a unique structure with the `star_focus` capability.
- Interacting with it opens owned/discovered placeables. Choosing one sets a persistent focus and renders a small non-consumed echo of it on the Throne.
- Only Starfishing results from the focus item's collection advance its visible rune track.
- Matching-category pulls weight the exact focused item at `4x` and its family at `2x` for initial tuning.
- After four matching-category misses, the fifth matching-category pull guarantees the focused known item. The UI shows all five rune positions before the player commits a lure.
- Changing focus resets the rune track only after explicit confirmation. Clearing focus is free.
- At the configured collection-completion threshold, initially 80%, the Throne unlocks **Seek New** for that collection. Seek New filters to unowned valid items. The player may switch back to Echo mode when duplicates are desired.
- If no valid unowned item remains, Seek New is disabled with `Collection complete` rather than silently reverting.

The exact multipliers and threshold are tuning values. The visible behavior and guarantees are product requirements.

## 5. Content model

Do not use `BuildCategoryResolver` for these rules. A Forest bench may live in the Furniture Build Bag category while belonging to the Forest Star collection; both labels are valid and serve different purposes.

### 5.1 `data/star_collections.json`

Each placeable reward belongs to one primary Star collection for clear lure promises. Optional cross-collection tags may be added later, but may not weaken the primary guarantee.

```json
{
  "collections": [
    {
      "id": "forest",
      "name": "Forest",
      "icon": "forest",
      "color": "#6F8E4F",
      "seek_new_threshold": 0.8,
      "rewards": [
        {
          "kind": "structure",
          "id": "example_forest_bench",
          "family_id": "forest_seating",
          "weight": 10.0,
          "rarity": "common",
          "keepsake": false
        }
      ]
    }
  ]
}
```

Required fields per reward are `kind`, `id`, `family_id`, and positive `weight`. `rarity` and `keepsake` make spirit and presentation rules explicit instead of deriving them from names.

### 5.2 `data/star_lures.json`

```json
{
  "lures": [
    {
      "item_id": "softwood",
      "collection_id": "forest",
      "consume_count": 1,
      "display_order": 10
    }
  ]
}
```

Lure quality tiers should not ship initially. One material means one clearly described category pull.

### 5.3 `data/activity_contexts.json`

This replaces local discovery pools as the runtime context contract.

```json
{
  "contexts": [
    {
      "id": "woodcutting_forest",
      "skill_id": "woodcutting",
      "context_tags": ["biome_forest"],
      "priority": 100,
      "loot_table_id": "woodcutting",
      "spirit_collection_id": "forest"
    }
  ]
}
```

The existing bounded context manifest logic should be extracted and reused. It must inspect only the authored nearby area and deterministic world state; it must not scan unbounded scene nodes.

### 5.4 `data/spirit_types.json`

```json
{
  "spirits": [
    {
      "id": "kindred",
      "name": "Kindred Spirit",
      "spawn_weight": 10.0,
      "boon": "family_bias"
    }
  ]
}
```

### 5.5 Typed definitions and validation

Add definitions in `scripts/core/defs.gd`; add definition kinds to `scripts/core/content/content_catalog_snapshot.gd`; load, adopt, and expose them through `scripts/core/registries.gd`; extend the existing content validators.

The validator must fail startup/tests when:

- a lure item does not exist;
- a lure points to a missing collection;
- an activity context references a missing skill, loot table, or collection;
- a reward content ID or kind does not exist;
- an obtainable tile or structure has no primary Star collection unless explicitly marked `wild_only`;
- a family ID is empty;
- a reward weight is non-positive;
- a collection cannot produce a valid result;
- there is not exactly one authored broad Wild contract and first-reward rule;
- a spirit boon is unknown;
- a source type can receive spirits but has no stable save key.

## 6. Runtime architecture

### 6.1 Keep `DiscoverySystem` as the safe grant boundary

Retain the proven responsibilities in `scripts/features/progression/discovery_system.gd`:

- validate a chosen tile/structure reward;
- add it to Stock;
- enqueue its pending reveal before presentation;
- persist and acknowledge pending reveals;
- preserve loss-proof reload behavior.

Remove `record_local_action()`, `resolve_local_pool()`, and direct local reward progress after the v4 cutover. Move broad and targeted candidate policy out of this class.

### 6.2 Add `StarfishingSystem`

Proposed file: `scripts/features/progression/starfishing_system.gd`.

Responsibilities:

- build candidates for Wild, natural lure, spare lure, captured spirit, Throne focus, and Seek New;
- apply filters before weights;
- return a preview contract for UI: cost, guaranteed collection, exclusions, bonuses, and visible exact guarantee state;
- select a reward using the project's injected RNG;
- commit input consumption and `DiscoverySystem` grant as one successful operation;
- maintain `first_starfishing_done`;
- never consume an input when no candidate exists or the action is cancelled.

Recommended request shape:

```gdscript
{
    "mode": "wild|material|spare|spirit",
    "item_id": "",
    "kind": "",
    "content_id": "",
    "spirit_id": ""
}
```

Selection and mutation must be separate internal phases: `preview_request()` is pure; `commit_request()` revalidates current quantities, selects, grants, and only then finalizes consumption.

### 6.3 Add `StarLureSystem`

Proposed file: `scripts/features/progression/star_lure_system.gd`.

Responsibilities:

- enumerate available natural materials from `InventoryManager`;
- enumerate eligible true spares from Stock plus placed counts;
- enumerate captured spirits;
- calculate keeper-safe spare counts using the existing Void Exchange semantics;
- expose stable, UI-ready entries without performing a roll;
- atomically consume the selected input after a valid selection is ready.

Avoid copying reward selection into this class. It owns inputs; `StarfishingSystem` owns output policy.

### 6.4 Add `ActivityContextResolver`

Proposed file: `scripts/features/progression/activity_context_resolver.gd`.

Extract the useful bounded context logic from `DiscoverySystem.context_manifest()` and `resolve_local_pool()`. It resolves an activity context, ordinary loot table, and spirit collection for a given skill/source location.

### 6.5 Add `SpiritSettlingSystem`

Proposed files:

- `scripts/features/progression/spirit_settling_system.gd`
- `scripts/visuals/settled_spirit_presenter.gd`

Stable source keys:

- structures: `structure:<instance_id>`
- tile/pond sources: `tile:<x>:<y>:<elevation>`

Responsibilities:

- maintain a fixed configured number of assignments;
- select only currently valid, eligible, non-resting sources;
- persist `source_key`, spirit type, collection, and seed;
- leave assignments in place until claimed;
- reassign after a successful claim, source removal, or invalidation;
- add a captured charge only when pouch capacity permits;
- provide deterministic render seeds to a procedural presenter.

Assignment should happen on world load after structures and terrain are restored, after a source mutation, and after a claim. It must not depend on real-world elapsed time.

### 6.6 Add `EchoFocusSystem`

Proposed file: `scripts/features/progression/echo_focus_system.gd`.

Responsibilities:

- store focused kind/content ID, mode, matching misses, and collection;
- verify the focus is still owned or discovered;
- provide exact/family modifiers to `StarfishingSystem`;
- advance or reset visible runes only after a committed matching-category reward;
- guarantee the configured matching attempt;
- expose collection completion and Seek New availability.

### 6.7 `ProgressionModule` v4

`scripts/features/progression/progression_module.gd` owns and wires:

- `DiscoverySystem` for safe grants and pending reveals;
- `StarfishingSystem`;
- `StarLureSystem`;
- `ActivityContextResolver`;
- `SpiritSettlingSystem`;
- `EchoFocusSystem`;
- existing milestones and activity action counts where still useful.

Replace the public entry points with explicit operations such as:

- `starfishing_options()`
- `preview_starfishing(request)`
- `commit_starfishing(request)`
- `complete_activity_cycle(skill_id, source_context)`
- `claim_settled_spirit(source_key)`
- `set_echo_focus(kind, content_id)`

Do not make scene/UI code reach directly into Stock, Inventory, or RNG to implement these rules.

## 7. Atomic runtime flows

### Wild cast

1. Player begins a valid void-edge interaction.
2. Lure picker defaults to Wild; player confirms.
3. System validates a broad candidate, including first-water override.
4. Reward is added to Stock and pending reveal state.
5. Presentation begins and later acknowledges the reveal.

### Natural-lure cast

1. UI reads an immutable preview from current Inventory.
2. Player confirms and cast presentation begins.
3. At the current reward-resolution moment, `commit_starfishing()` revalidates one material.
4. It builds a nonempty category pool, selects a reward, grants it to Stock/pending, and consumes the material as one transaction boundary.
5. Autosave is requested immediately; reveal continues even if presentation is interrupted.

If the project cannot provide a true rollback transaction, order operations so the reward is selected first, then input consumption and grant occur synchronously without an `await`; tests must inject a failure at each boundary and verify no loss or duplication.

### Ordinary skill cycle

1. Resolve the source and context once at action start.
2. Run the normal animation/cycle.
3. On pond completion, roll one fishing loot table entry.
4. On the final tree/stone cycle action, roll one relevant loot table entry; intermediate hits grant no lure.
5. If a spirit is assigned and pouch capacity exists, capture it in addition to the ordinary reward.
6. Move the source to its existing rest state, request autosave, and refresh assignments.

### Spare cast

1. Enumerate only entries with a current true spare.
2. Preview collection, exact exclusion, family bonus, and remaining copies.
3. Revalidate at commit, remove exactly one Stock copy, and grant the chosen different reward synchronously.
4. Never remove a placed structure/tile and never reduce total ownership below one.

### Echo focus

1. Player interacts with the Throne and chooses a currently owned/discovered item.
2. Confirmation records the focus; no item count changes.
3. Matching collection casts apply the visible modifiers.
4. A non-focused result advances a rune; focused result clears runes.
5. The configured final rune forces the focused item and then clears.

## 8. Save migration

Increment the progression payload to **version 4** and update the validator in the same commit.

New progression payload shape:

```json
{
  "version": 4,
  "discovery": {
    "pending": []
  },
  "starfishing": {
    "first_starfishing_done": false
  },
  "star_lures": {
    "captured_spirits": []
  },
  "spirit_settling": {
    "assignments": []
  },
  "echo_focus": {
    "kind": "",
    "content_id": "",
    "collection_id": "",
    "mode": "echo",
    "matching_misses": 0
  },
  "milestones": {},
  "activity_actions": {}
}
```

Migration order is important:

1. Archive the full incoming v3 progression payload exactly as the existing migration approach does.
2. Read `void_exchange.offerings`. Those entries represent copies already removed from Stock. Parse each `<kind>:<content_id>` key, validate it, and refund its stored count to the appropriate Stock collection before retiring the exchange.
3. Preserve all valid pending discovery entries unchanged so already granted rewards still reveal safely.
4. Map `first_void_discovery_done` to `first_starfishing_done`.
5. Retire local discovery progress; it is not currency and needs no refund.
6. Preserve Inventory material counts, Stock, placed world state, collection state, milestones, journal, and anchor recovery state.
7. Initialize Echo focus empty and captured spirits empty.
8. Seed settled-spirit assignments only after the migrated world finishes loading successfully.
9. Map onboarding conservatively: new saves use the new stages; existing saves that passed the old local-discovery step are grandfathered to complete rather than regressed.

Migration tests need fixtures for zero, one, and two partially offered copies; pending reveals; a placed keeper with no Stock keeper; completed/incomplete first cast; resting anchors; and older v1/v2 payloads migrating through to v4.

## 9. UI, controls, and presentation

### Lure picker

Replace `Panels.show_void_exchange_picker()` and the HUD `Offer Duplicates` entry with a contextual Starfishing picker shown before the cast:

- **Wild**
- **Materials**
- **Spare Pieces**
- **Captured Spirits**

Each row shows quantity/cost, guaranteed collection, exact exclusions, active Throne effect, and any Seek New rule. It must never show vague text such as `better odds` without the actual rule.

Requirements:

- first actionable entry receives controller focus;
- D-pad/stick navigation and `ui_accept` work throughout;
- `ui_cancel` closes without consuming anything or starting the cast;
- focus is restored to the game cleanly;
- unavailable entries explain why;
- repeated cast may remember the previous input only while its quantity remains; otherwise the picker reopens;
- no raw gameplay key checks are added—use semantic InputMap actions;
- mouse, keyboard, and controller expose the same choices.

### Ordinary reward feedback

Show a compact, non-modal pickup toast such as `Softwood +1 — a Forest lure`. Materials should be visible where the lure picker needs them, without reintroducing a crafting inventory screen or organization chores.

### Spirits

The spirit presenter is procedural and attached to the source node/anchor resolved from its stable key. It should use a restrained orbit, soft emissive core, a few motes, and source-colored accents. The visual must remain visible at ordinary gameplay zoom and clearly survive save/reload.

### Starfishing presentation

Extend the existing `VoidFishingPresentation`; do not rebuild or replace the current character/world setup. The selected lure or spirit appears as a small charm at the hook/shard, dissolves into the lower line glow, and the line still terminates underneath the shard.

Regression requirements:

- no camera translation, zoom, or cinematic framing change;
- no temporary dock or wooden platform spawn;
- no player teleport;
- no forced direction change—the player fishes in their current facing direction;
- line origin tracks the actual rod-tip socket every frame;
- ordinary lakes and void edges share the normal interaction/facing rules;
- weather/sky presentation does not fade the island, player, or placed content.

## 10. Onboarding revision

Replace the current onboarding stages with:

1. `land_choice`
2. `try_wild_starfishing`
3. `place_first_discovery`
4. `harvest_first_lure`
5. `try_lured_starfishing`
6. `place_lured_discovery`
7. `complete`

Teaching copy must make the causal promise explicit:

- Wild Starfishing can find anything.
- Working ordinary places gives lures.
- A lure guarantees its named collection.
- A spirit is a special optional lure and waits for the player.
- The Throne is later mastery, not required onboarding.

The new-player path must author a reachable eligible tree or pond after the first water placement and guarantee an appropriate first lure if ordinary loot randomness would otherwise stall instruction.

## 11. Content rollout across Garden Galaxy-like collections

The system holds up only if collections have believable source fantasy. Not every collection needs a unique skill verb. Reuse a small, understandable verb set—fish, cut/tend, gather, mine/salvage—and let the placed source and material carry the theme.

| Star collection | Believable skill sources | Example lure outputs |
| --- | --- | --- |
| Copper | Copper outcrop, boiler scrap pile | copper shard, warm rivet |
| Silver | Moonstone vein, silver reeds | silver flake, moon reed |
| Gold | Gilded seam, sun blossom | gold flake, sun pollen |
| Farm | Fruit tree, crop patch, farm pond | seed sack, straw, pond feed |
| Water | Pond, fountain basin, water plants | fish, reeds, driftwood |
| Forest | Trees, mushrooms, mossy log | softwood, hardwood, resin |
| Desert | Cactus grove, dry dig spot, oasis | cactus fiber, warm sand, scarab shell |
| Urban | Salvage pile, mailbox route, lamp post | old metal, wire, glass token |
| Curio | Relic dig, oddity cabinet interaction | relic fragment, curious charm |
| Classic | Stone outcrop, clay bank | smooth stone, carved stone, clay |
| Lawn | Flower patch, hedge, lawn clippings | clover, petals, fresh cuttings |
| Rainbow | Prismatic flower, rainbow spring | spectrum pollen, prism droplet |
| Market | Produce crate, market stall task | wrapping, spice packet, trade token |
| Beach | Shore pool, shell bed, palm | shell, sea glass, palm fiber |
| Swamp | Bog fishing, fungus log, reed bed | bog reed, glowcap, peat |
| Harvest | Orchard, pumpkin patch, hay stack | amber seed, pumpkin fiber, wheat charm |
| Frost / Tundra | Ice fishing, frost pine, ice crystal | frost scale, pale wood, ice shard |

This table is a content-production guide, not a requirement to build seventeen bespoke minigames. For the first slice, reuse current ponds, trees, and dormant stone/mining infrastructure, then add collection-specific source models as those collections enter production.

Keepsakes remain rare rewards inside their primary collection. They should have little-life functions—visitors, ambience, utility, playful interactions, collection displays—rather than being required multipliers in the lure economy.

## 12. Phased execution plan

Every phase ends in a runnable, testable state. Do not combine all phases into one risky cutover commit.

### Phase 0 — Lock contract and fixtures

Files:

- this plan;
- `docs/DISCOVERY_PROGRESSION.md` and `docs/NEW_PLAYER_FLOW.md` only after implementation begins;
- new representative v3 save fixtures under `tests/fixtures/`.

Work:

- confirm initial collection IDs and assign every currently obtainable tile/structure;
- confirm initial material-to-collection mappings;
- capture v3 fixtures containing partial exchange offerings and pending reveals;
- record baseline full-loop and fishing-presentation screenshots before code cutover.

Done when: content mappings have no unassigned rewards, migration inputs are reproducible, and current unrelated visual changes are isolated from the gameplay commits.

### Phase 1 — Typed content foundation

Files:

- `data/star_collections.json`
- `data/star_lures.json`
- `data/activity_contexts.json`
- `data/spirit_types.json`
- `scripts/core/defs.gd`
- `scripts/core/registries.gd`
- `scripts/core/content/content_catalog_snapshot.gd`
- existing validation/test files

Work:

- add definitions and registry APIs;
- author current-content membership and lure mappings;
- add all cross-reference/completeness validators;
- leave runtime behavior unchanged behind an inactive feature flag or unused registry API.

Done when: the project boots, all current content validates, malformed fixture tests fail for the intended reason, and no player behavior has changed.

### Phase 2 — Starfishing domain and v4 migration

Files:

- `scripts/features/progression/starfishing_system.gd`
- `scripts/features/progression/star_lure_system.gd`
- `scripts/features/progression/echo_focus_system.gd`
- `scripts/features/progression/discovery_system.gd`
- `scripts/features/progression/progression_module.gd`
- save validator and migration tests

Work:

- implement pure preview/candidate functions with injected RNG;
- implement Wild, natural, and spare modes;
- preserve `DiscoverySystem` as the grant/pending boundary;
- migrate v3 to v4 and refund partial exchange offerings;
- keep current scene entry points temporarily adapting to Wild so the build remains playable;
- retire Void Exchange persistence only after refund tests pass.

Done when: deterministic tests prove collection guarantees, exact exclusion, keeper protection, first water, no-input loss, pending reveal recovery, and all supported save versions reach a valid v4 state.

### Phase 3 — Ordinary skilling and source context

Files:

- `scripts/features/progression/activity_context_resolver.gd`
- `scripts/player/skill_actions.gd`
- `scripts/systems/reward_manager.gd`
- `data/loot_tables.json`
- anchor/tree presentation as required

Work:

- extract bounded activity context resolution;
- route pond completion to one ordinary fishing loot roll;
- route only the final woodcutting action to one ordinary loot roll;
- preserve rest and offline recovery;
- expose the dormant mining path using the same completion contract when mining is enabled;
- remove direct local placeable discoveries;
- show compact material/lure feedback.

Done when: ordinary skills cannot grant placeables, each completed source cycle grants exactly its authored ordinary output, intermediate tree hits do not farm materials, rest/reload works, and all outputs have valid lure uses.

### Phase 4 — Lure picker and integrated casts

Files:

- `scripts/ui/panels.gd`
- `scripts/ui/hud.gd`
- `scripts/player/skill_actions.gd`
- `scripts/visuals/void_fishing_presentation.gd`
- controller/navigation tests

Work:

- replace the duplicate-offer UI with the contextual picker;
- connect Wild, material, and spare requests to the existing cast resolution point;
- display exact guarantees and exclusions;
- show lure/shard integration without changing camera, dock, position, or facing behavior;
- autosave after the atomic commit.

Done when: mouse/keyboard/controller can complete and cancel every path; cancelling costs nothing; the line remains socket-aligned; and a full save/reload loop cannot lose a lure or reward.

### Phase 5 — Settled spirits

Files:

- `scripts/features/progression/spirit_settling_system.gd`
- `scripts/visuals/settled_spirit_presenter.gd`
- progression/world lifecycle integration
- spirit data and tests

Work:

- implement stable eligible-source keys and a fixed assignment cap;
- persist assignments with no expiry;
- claim through normal skill completion;
- implement the three-slot captured-spirit pouch;
- integrate Kindred spirit casts first;
- add procedural visuals and reattachment after load/source rebuild.

Done when: assignments survive reload, cannot duplicate or point at invalid sources, wait indefinitely, respect pouch capacity, do not scale globally with source count, and always produce the described special cast.

### Phase 6 — Echo Throne and completion control

Files:

- `scripts/features/progression/echo_focus_system.gd`
- Throne structure capability/interaction and presenter
- focus picker UI
- collection progress UI

Work:

- author or designate the unique Throne;
- place a non-consumed visual echo;
- implement exact/family modifiers and the visible fifth-pull guarantee;
- implement explicit Seek New at the threshold;
- add confirmation before a focus change resets runes.

Done when: focus never alters ownership, rune progress persists, only matching-category committed casts advance it, exact guarantee is deterministic, and completed collections cannot trap Seek New in an invalid fallback.

### Phase 7 — Onboarding, balance, and cutover

Files:

- `scripts/features/onboarding/onboarding_state.gd`
- onboarding UI/copy
- `docs/DISCOVERY_PROGRESSION.md`
- `docs/NEW_PLAYER_FLOW.md`
- `docs/DESIGN_MASTER_RECORD.md`
- test and visual-capture runners

Work:

- ship the new seven-stage onboarding with a guaranteed first natural lure;
- remove obsolete duplicate-exchange copy and calls;
- remove retired local discovery data/code after migration has test coverage;
- tune weights from simulated pulls, not intuition alone;
- update design authority documents to make this plan the live contract;
- run final full-loop/controller/visual/save acceptance.

Done when: a fresh player understands Wild versus lured Starfishing without external explanation, a migrated player loses nothing, collection completion demonstrably converges, and no obsolete UI or direct-local-discovery path remains.

## 13. Test matrix

### Unit/content

- Every existing obtainable placeable resolves to one primary Star collection.
- Every lure item resolves to an existing collection.
- Wild weighting is deterministic under seeded RNG.
- Natural lure results never leave the promised collection.
- Spare lure excludes the offered exact ID and protects one keeper across Stock plus placed world.
- Family and Echo weights compose without bypassing collection filters.
- Seek New returns only unowned entries and reports complete when empty.
- First Starfishing result is Open Water regardless of selected/default weighting.
- Empty/invalid pools produce a typed error and consume nothing.
- Tree output occurs once on the final cycle action.
- Spirit cap is global/fixed and assignments use unique valid source keys.

### Save/migration

- v3 offerings of zero, one, and two copies are refunded exactly once.
- Pending v3 discoveries remain owned and revealable.
- Reload during a pending lured cast preserves both the granted reward and correct consumed count.
- Resting tree recovery is unchanged.
- Spirit assignment, pouch, Echo focus, runes, and mode round-trip.
- v1/v2 fixtures still migrate through the supported chain to v4.
- Running migration on an already-v4 payload is idempotent.

### Integration/full loop

- Fresh save: land → Wild Open Water → place pond → fish lure → lured collection pull → place reward.
- Wild cast with zero materials remains possible.
- Ordinary pond and tree actions never put placeables directly in Stock.
- Settled spirit: locate → claim → save/reload → use at Starfishing.
- Echo Throne fifth matching pull gives the focus.
- Seek New converges a nearly complete collection.
- Removing a spirit's source safely reassigns it.

### Input/accessibility

- Full fresh onboarding is completable with controller only.
- Picker focus, tabs, confirm, cancel, confirmation dialogs, and focus restoration work by controller.
- No input action is added without InputMap/controller coverage.
- All probabilistic rules needed for a choice are readable without relying on color alone.

### Visual regression

- Current actual player model and current world are used in capture scenes.
- No spawned dock, camera shift, forced facing, or player displacement.
- Line begins at the rod-tip socket and ends under the shard at every tested facing.
- Lure/spirit/shard glow is visible but does not wash out island/player colors.
- Procedural spirit survives ordinary camera distance and does not clip deeply into source geometry.

## 14. Balance telemetry and simulation

Before tuning, add a headless simulation test that performs at least 100,000 seeded pulls per mode and reports:

- result frequency by collection, item, family, rarity, and keepsake;
- median and 90th-percentile pulls to first item in a collection;
- expected pulls to 50%, 80%, 95%, and 100% collection completion for Wild, natural lure, Echo, and Seek New use;
- duplicate rate over progression;
- expected ordinary skill cycles per category pull;
- spirit special-pull cadence under the fixed cap.

Acceptance is based on authored targets added beside tuning data. The test should fail on impossible rewards and large accidental distribution drift, not on harmless small RNG variation.

## 15. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Lures feel like mandatory chores | Wild is always free; one cycle produces a useful counted lure; no crafting chain |
| Category taxonomy becomes confusing | One primary collection per reward and one promised collection per natural lure at launch |
| Players build dense farms for spirit rate | Fixed global assignment cap; added sources only alter eligible destinations |
| Spirits create FOMO | Persistent until claimed; no real-time rotation or expiry |
| Spare lure destroys a cherished copy | True-spare calculation and Stock-only consumption; placed items untouched |
| Targeting removes gacha excitement | Category guarantee preserves item randomness; Wild remains broad; exact control arrives later |
| Completion remains frustrating | Visible Echo guarantee plus explicit Seek New mode |
| Save migration loses consumed offerings | Refund v3 partial offerings before retiring the subsystem; fixture tests at every count |
| Too many bespoke skill objects are needed | Reuse four verbs and themed source/context models; roll collections in by content wave |
| Presentation work reintroduces old mock assets | Extend actual runtime presenter and assert current player/world in visual captures |

## 16. First shippable slice

The recommended first playable slice is deliberately smaller than the full vision:

- Wild, Forest, Water, Beach, Stone/Classic, Urban, and Curio mappings for current content;
- existing fishing and woodcutting sources plus dormant stone/mining when ready;
- natural and spare lures;
- one persistent Kindred spirit type with a three-slot pouch;
- no Echo Throne until the base loop is proven;
- new onboarding through the first lured discovery;
- full v4 save migration and controller support.

This slice proves the central question: **does working a beloved, player-made world make the next gacha pull more meaningful without making it feel like labor?** The Throne and additional spirit boons should build on that answer, not conceal a weak base loop.

## 17. Recommended commit sequence

1. `docs: define Starfishing lure and spirit contract`
2. `data: add validated Star collections and lure mappings`
3. `progression: add Starfishing selection and v4 migration`
4. `skills: convert local discoveries into ordinary lure rewards`
5. `ui: add controller-complete Starfishing lure picker`
6. `spirits: add persistent settled-source opportunities`
7. `progression: add Echo Throne targeting and Seek New`
8. `onboarding: teach wild and lured Starfishing`
9. `tests: harden distributions, migration, full loop, and visuals`
10. `docs: cut over progression and new-player authority`

Each commit must keep the project bootable and should avoid mixing the currently paused sky/fishing-presentation edits into gameplay-system commits.

## 18. Acceptance summary

The redesign is complete only when all of the following are true:

- a player can always Starfish without a lure;
- ordinary skilling always has an understandable purpose but never directly spits out unrelated decor;
- the player can spend a natural output to guarantee a named collection;
- the player can spend a true spare for a more related roll without risking the keeper;
- special sources make the player look around their own world, wait indefinitely, and grant exactly what the UI promises;
- the Echo Throne gives visible, non-destructive exact/completion control;
- first-time and completion progression cannot be blocked by luck;
- saves, pending rewards, placed pieces, partial old offerings, and offline source recovery survive migration;
- all flows work with controller;
- the actual player/world presentation remains stable, with no camera shift, spawned dock, or incorrect facing.
