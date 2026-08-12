# Endless Diorama progression transformation

Status: approved product direction, implementation plan
Replaces: Projects, contribution gathering, token boxes, visitor cadence, and
timer-led Wish progression
Preserves: the persistent world, free building, Nook generation, the falling
wave, skyfall spectacle, reward rarity, collections, and the Build Bag

## 1. Product contract

Suma is a calm, endless collectible diorama builder. The only repeatable
activity is making and remaking the world.

The loop is:

> Choose a miniature -> place it -> own it -> reveal the next miniature ->
> decorate -> receive a rare World Gift -> expand -> discover or break
> something unusual -> add its pieces to the collection.

There are no points, adjacency puzzles, production chains, resource chores,
visitor chores, finite runs, failure states, or offline progress. Normal
building never requires currency. The game progresses while the player builds,
not while the player waits.

### Non-negotiable rules

1. The player starts with one attractive, useful world, not a tiny empty cell.
2. Three visible miniature offers provide choice without a catalogue dump.
3. Placing an offered piece is the only action that replaces that offer.
4. Once placed, every ordinary tile, model, or attachment is a permanent copy.
5. A placed copy can always be moved or stored in the Build Bag and placed
   again later.
6. Moving, rotating, storing, or replacing an owned copy never produces a new
   offer and cannot farm progression.
7. Ordinary terrain reshapes unlocked land; only an Expansion Ripple unlocks
   a new build area.
8. Skyfalls and breakables are uncommon bonus moments, never a click tax.
9. Loot from one breakable is collected in one interaction. Burst pieces fly
   to storage automatically; individual coins are never clicked.
10. Everything is save-safe, deterministic after it has been rolled, and fully
    usable with a controller.

## 2. The complete player flow

### Starting session

- Load into a generous, already pleasant starter world.
- The Discovery Tray contains three persistent offers:
  - terrain or surface;
  - a substantial model or building part;
  - a small detail or attachment.
- Choose one and place it anywhere valid in the unlocked build area.
- The piece becomes an ordinary owned world object, its first discovery is
  stamped in the Collection Book, and a replacement miniature falls into that
  tray slot.
- The player may continue the tray loop or freely rearrange anything already
  owned through the Build Bag.

### Rare rhythm

New-offer placements advance an invisible, randomized event cadence. This is
not a displayed meter and real time does not advance it. When due, the next
safe moment can produce a World Gift:

- an Expansion Ripple;
- a terrain phenomenon such as Rising Ground, Spring Burst, or Falling Star;
- a collection-themed breakable;
- a rare model, attachment, or landmark;
- a bonus bundle of ordinary but useful duplicate pieces.

The current falling-from-the-sky presentation remains. Some gifts fall into a
small persistent Gift Pocket; physical curiosities can land in the world and
wait indefinitely for the player.

### Expansion

- Use an Expansion Ripple when desired; it never activates automatically.
- The boundary cursor highlights deterministic adjacent Nook locations.
- Confirm one edge and the existing procedural generator prepares a small,
  irregular patch.
- The existing radial falling-tile wave reveals terrain, water, and models.
- The new land is immediately editable. Ordinary generated scenery is owned
  and can later be moved or stored in the Build Bag.
- Generation can include a rare scene, landmark, or persisted breakable.

### Breakable gacha

Vases remain possible, but only where ceramics fit. The same gameplay contract
can be presented as a seed pod, hollow log, washed-up crate, frozen parcel,
meteor, fossil shell, ceramic pot, or other collection-specific curiosity.

- The container and all of its loot are pre-rolled once and saved before it is
  shown.
- One Interact action plays the break animation and grants the full bundle.
- Loot miniatures burst outward, reveal rarity, and then fly automatically to
  the Build Bag/Collection Book.
- A container grants at least one placeable. Additional pieces and World Gifts
  are rarity rolls.
- Duplicate pieces are useful building copies. Undiscovered weighting, recent
  memory, and saved rare pity prevent the gacha from becoming hostile.
- A claimed container can never grant twice, including across interruption or
  reload.

### Collections

The Build Bag and Collection Book are deliberately different views:

- **Build Bag:** functional storage for unplaced physical copies, organized by
  building use such as Ground, Nature, Furniture, Borders, and Buildings.
- **Collection Book:** permanent discovery knowledge, organized by authored
  series such as Cottage, Woodland, Waterside, Garden, Stone, Winter, Seaside,
  Market, and Curiosities.

Collection milestones add creative vocabulary rather than score:

- early discoveries add related pieces to future offer pools;
- family rows unlock attachments such as shutters, chimneys, docks, reeds, or
  flower boxes;
- major page milestones grant a World Gift or landmark;
- page completion can unlock an unusual generated-land variant.

A collected design remains recorded even when every physical copy is placed.

## 3. Ownership and anti-exploit transaction

The Discovery Tray owns an offer until that exact offer is placed once.

Each tray slot has one of these persisted states:

- `available`: a pre-rolled offer is waiting;
- `held`: that offer is temporarily attached to the placement cursor;
- `committing`: a placement transaction is in progress;
- `refill_pending`: placement succeeded and the next offer is being rolled.

Selecting an offer does not first add an anonymous copy to Stock. It creates a
held offer carrying a stable `offer_id`. Cancel returns it to the same tray
slot. A successful placement atomically:

1. validates and creates the world piece;
2. consumes the exact `offer_id`;
3. records its collection discovery;
4. rolls and persists the replacement;
5. emits presentation events only after state is committed.

After this first placement, the object has no special progression identity. It
uses the existing placement path. Picking it up and choosing Store returns its
exact copy to `StockManager`, so it appears in the Build Bag. Stateful models
continue to use the existing preserved-instance token path.

This means:

- cancel cannot generate free bag copies;
- placing an old duplicate cannot consume a new offer;
- move/store/undo cannot refill the tray;
- a crash cannot lose or duplicate the offered piece;
- the player can immediately place, pick up, and store a newly earned object
  if they only wanted to collect it.

## 4. Architecture: keep, adapt, retire

### Keep as foundations

- `StockManager` and the current Build Bag UI.
- `PlacementController`, placement rules, grid cursor, undo/redo, and the
  state-preserving Store path.
- `BuildRewardService` rarity, novelty weighting, recent memory, and pity
  concepts.
- `CollectionManager` as the low-level discovery ledger.
- `NookModule`, `NookGenerator`, `NookWorld`, and async generation.
- `NookRevealPresenter` and its falling terrain/water/model wave.
- `RewardDropService` guarantees around persisted landed objects.
- `WorldBudRewardPresenter` miniature reveal and automatic collection motion.
- the data-first content catalogue, validators, stable IDs, and save contract.

### Add or reshape

1. **DiscoveryTrayService**
   - owns three persisted offers, slot roles, offer history, and replacement;
   - rolls from unlocked content with duplicate/novelty balance;
   - accepts only a first-placement receipt carrying the matching `offer_id`.

2. **WorldGiftService**
   - owns saved one-use powers and the small Gift Pocket;
   - validates targets and consumes a gift only after its effect commits;
   - first power is `expansion_ripple`; later powers reuse the same contract.

3. **BuildCadenceService**
   - observes successful new-offer placements only;
   - schedules the next skyfall using a persisted randomized placement range;
   - never advances from elapsed real time or rearranging old pieces.

4. **WorldCuriosityService**
   - owns collection-themed landed/generated breakables;
   - persists container presentation ID, loot bundle, claim state, roll history,
     and pity receipt;
   - grants a complete bundle atomically through the shared reward boundary.

5. **CreativeCollectionService**
   - maps every placeable to one primary authored collection;
   - evaluates discovery milestones and exposes unlocked offer/gift/land pools;
   - does not replace Build Bag categories.

6. **Offer placement bridge**
   - extends held placement metadata with `offer_id` and `tray_slot`;
   - creates the first world copy without routing through anonymous Stock;
   - emits an explicit committed receipt for the tray service.

7. **Modular attachment capability**
   - authored building shells expose compatible attachment sockets;
   - roofs, balconies, stairs, signs, chimneys, lamps, windows, and flower
     boxes use normal owned-copy placement;
   - compatibility highlights help placement but never grade a build.

### Retire from the live loop

- Project selection, contribution routing, Project HUD, and Frontier Projects.
- token pouch and token boxes.
- SDF visitors and visitor arrival cadence.
- timer-led three-category Wishes.
- harvesting, fishing, combat, crafting, and practice milestones as sources of
  build progression.
- resource-production UI and onboarding.

Retirement should be feature-flagged during development. Old systems remain
loadable long enough to migrate saves, but only the new loop is exposed in a
new game.

## 5. Data contracts

Add validated data files rather than hardcoding content relationships:

- `data/creative_collections.json`
  - pages, families, member IDs, milestones, unlocks, icons, and presentation;
- `data/discovery_tray.json`
  - slot roles, eligible pools, rarity, duplicate policy, recent memory,
    onboarding sequence, and refill presentation;
- `data/world_gifts.json`
  - gift kind, target rules, consumption policy, effect parameters, and icon;
- `data/world_curiosities.json`
  - container presentation, collection, biome tags, loot table, rarity, and
    generation/skyfall eligibility;
- `data/build_cadence.json`
  - placement ranges, event weights, active caps, and pity thresholds.

Existing tile and structure definitions gain stable collection/family metadata
or reference a validated membership table. Build Bag category resolution stays
unchanged.

## 6. Implementation sequence

Each phase should be a shippable, tested commit. Do not begin with broad code
deletion.

### Phase 1 - domain and save skeleton

- Add typed definitions, validators, and the five new services with save
  round-trips.
- Seed three deterministic tray offers for a new world.
- Add collection membership for a small vertical-slice set.
- Keep all new presentation hidden behind a feature flag.

Exit: headless tests prove stable rolls, save restoration, no duplicate IDs,
and deterministic collection unlocks.

### Phase 2 - tray-to-world vertical slice

- Build the three-slot Discovery Tray and controller focus path.
- Implement held-offer placement and exact first-placement receipts.
- Refill a slot with the falling miniature presentation.
- Preserve unrestricted rearrangement and existing Build Bag placement.
- Prove that a placed offer can be picked up, stored in the Build Bag, loaded,
  and placed again.

Exit: a new game can play the endless choose/place/refill loop with keyboard,
mouse, or controller and without Projects, resources, or waiting.

### Phase 3 - Expansion Ripple

- Add the Gift Pocket and guarantee an Expansion Ripple during onboarding.
- Reuse the existing frontier cursor to select an adjacent Nook directly.
- Route confirmation through async Nook generation and the current reveal wave.
- Tune new-world Nooks toward small irregular footprints; preserve the saved
  Nook size and coordinates of existing worlds.
- Record generated editable scenery as owned discoveries.

Exit: the power is saved, targetable, consumed exactly once, and cannot lose
state if saved or exited during generation/presentation.

### Phase 4 - curiosities and gacha bundles

- Replace visitor-specific vases with data-driven Curiosities.
- Spawn pre-rolled curiosities from new-land plans and rare skyfalls.
- Adapt reward reveal to fan out a small bundle and auto-collect it.
- Persist recent-drop memory and rare pity by curiosity collection.
- Keep an active cap so the world never fills with unopened chores.

Exit: one controller Interact breaks a curiosity, grants all loot exactly once,
and requires no follow-up clicks.

### Phase 5 - collection-driven vocabulary

- Build thematic Collection Book pages and silhouette states.
- Add family and page milestone evaluation.
- Gate authored offer entries, gifts, landmarks, and rare land variants through
  collection unlocks.
- Surface concise discovery/unlock reveals without blocking building.

Exit: completing a collection row visibly changes future creative
possibilities; no number or score is required to understand the reward.

### Phase 6 - ShantyTown-style modular buildings

- Author the first building shell and attachment socket families.
- Add compatible-surface highlighting to pointer and controller placement.
- Ensure attachments detach, move, store, and preserve parent relationships.
- Expand tray role balancing so detail offers include newly unlocked families.

Exit: one cottage can be freely personalized with multiple valid combinations,
with no recipe, score, or production advantage.

### Phase 7 - cutover, migration, and balancing

- Make the new loop the default and remove retired HUD/input routes.
- Replace old onboarding with: place offer -> rearrange/store -> use guaranteed
  Ripple -> open guaranteed first-land Curiosity.
- Migrate or archive old feature state without touching the world or Build Bag.
- Run long deterministic simulations for duplicate rate, collection completion,
  expansion pace, skyfall cadence, and active curiosity cap.
- Update README, architecture, controls, screenshots, and acceptance flow.

Exit: the full game boots, saves, loads, and progresses without any retired
system being needed.

## 7. Save migration policy

The creative world is more important than retired progression state.

- Preserve the grid, all placed objects, Stock/Build Bag counts, preserved
  structure instances, camera/home state, and collection discoveries.
- Convert an unclaimed landed Wish into a Curiosity or direct persisted loot
  bundle without rerolling its reward.
- Convert an existing visitor vase into the corresponding themed Curiosity at
  the same safe cell. Remove an active visitor while preserving its pre-rolled
  gift this way.
- Convert a completed, unspent Frontier Project into one Expansion Ripple.
- Grant any already-completed but ungranted Project reward before archiving
  Project state.
- Convert positive token balances deterministically into their authored box
  rolls, grant the resulting pieces to the Build Bag, then archive the pouch.
- Archive incomplete Projects, contribution receipts, timers, and visitor
  history for diagnostics; they do not enter the new loop.
- Preserve old Nook sizes exactly. New tuning applies only to newly created
  worlds or newly generated compatible content.

The migration must be idempotent and versioned. Loading the migrated save
twice cannot grant any conversion reward twice.

## 8. Controller and input definition of done

The transformation follows `docs/CONTROLLER_SUPPORT.md` in every phase.

- Add a semantic `discovery_tray` action with keyboard and controller access;
  register it in `InputDeviceService.REQUIRED_CONTROLLER_ACTIONS`.
- Tray focus starts on the last selected available slot, has a visible state,
  focused tooltips, `ui_accept`, and `cancel` back to the world.
- Offer placement uses the existing build grid cursor and `build_confirm`.
- Expansion targeting uses the deterministic frontier cursor, not a virtual
  mouse.
- Curiosities use the shared `interact` action and contextual prompts from
  `InputService`.
- The Gift Pocket is fully focusable and every power exposes valid target,
  confirm, and cancel behavior.
- Retired `wish_menu` and `project_menu` actions are removed only after their
  scenes, prompts, and tests are gone.

Headless input-contract tests and the scene acceptance runner must cover every
controller path in the same phase that introduces it.

## 9. Initial tuning targets

These are prototype values, not final economy promises:

- Three offers always available, one per broad creative role.
- Tray rolls strongly avoid the last six exact pieces and modestly favor
  undiscovered designs while retaining useful duplicates.
- First Expansion Ripple guaranteed after the short onboarding sequence.
- Later expansion gifts should initially target roughly 20-35 new-offer
  placements apart, randomized and saved.
- Bonus skyfalls should initially target roughly 8-16 new-offer placements
  apart and pause while another landed event is active.
- A generated Nook has at most one Curiosity. Early tuning can target roughly
  one in four expansions, with a saved dry-streak guarantee.
- A Curiosity grants one guaranteed placeable, a moderate chance of a second,
  and a small chance of a rare piece or World Gift.
- No cadence advances while paused, idle, moving old pieces, or opening UI.

The correct pace is measured in meaningful world changes per relaxed building
session, not minutes waited or land conquered.

## 10. Vertical-slice acceptance story

A fresh player can, entirely with a controller:

1. choose one of three miniatures;
2. place it and watch a replacement fall into the tray;
3. pick the placed piece back up, store it in the Build Bag, and place it again;
4. continue building until receiving the guaranteed Expansion Ripple;
5. choose an edge and reveal generated land through the falling wave;
6. discover a guaranteed onboarding Curiosity on that land;
7. break it once and watch all gacha loot fly automatically into ownership;
8. open the Collection Book and see the new family progress/unlock;
9. save and reload with the tray, Gift Pocket, Build Bag, generated land,
   Curiosity claim, collection progress, and pity state unchanged.

If this story is delightful before broader content is added, the transformation
has the right foundation.
