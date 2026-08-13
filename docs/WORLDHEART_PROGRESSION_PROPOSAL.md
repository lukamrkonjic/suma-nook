# Worldheart progression proposal

Status: core loop implemented; later social layers remain a roadmap  
Working name: **Worldheart**; the final in-world name is undecided  
Would replace: the three-offer Discovery Tray and placement-led refill cadence  
Would preserve: Build Bag ownership, the Collection Book, rarity and novelty
weighting, free rearrangement, Nook expansion technology, reward miniatures,
save-safe transactions, and controller support

## Implemented foundation

The current branch now ships the first coherent slice of this proposal:

- new saves remain an empty backdrop until the vibe choice, then compose
  exactly nine themed land tiles in a 3 x 3 garden;
- the Worldheart sits on its center tile, stays small and matte black at rest,
  and can be moved onto another clear garden tile in Build mode;
- the permanent portal reuses the rescue-hole shader, always renders above
  its host tile, and begins without the old keeper or pigeon actors;
- deterministic 15-25 second pulses, four visible slots, and a twelve-item
  saved reserve replace the choice tray;
- each pulse makes the portal squash, wobble, and open like a cartoon mouth
  before throwing the saved miniature into the world;
- rewards are committed to the save before their arrival animation, can be
  clicked individually even while editing, receive their own hover outline,
  and can be swept up together by interacting with the hole;
- new saves ask which collection vibe the player wants to begin with, biasing
  early gifts without locking any collection;
- true spares can be dropped into the hole or offered from the Build Bag. Each
  same-collection piece fills half a visible circle; the second completes the
  ritual and returns a different member of that collection;
- Collection Book attunement unlocks after familiarity and biases later
  pulses; near-complete sets enter convergence weighting;
- old tray saves migrate their waiting offers into the Worldheart and gain the
  new garden without overwriting authored pieces;
- mouse, keyboard, and controller paths share the same interaction and focus
  contracts.

Autonomous visitors, authored visitor behaviors, and optional offline
accumulation remain later layers. None of them requires replacing the saved
Worldheart queue or collection vocabulary.

## Product promise

Suma begins as a tiny, complete place rather than an already-expanded canvas.
After the player chooses a collection vibe, exactly nine matching tiles appear.
At the center is the same matte black portal used for the old void rescue. No
keeper or pigeon arrives with it: the Worldheart itself is the world's steady
source of new pieces and the place where spare pieces can be exchanged.

The repeatable loop is:

> Watch the worldheart stir -> collect one surprising piece -> build or store
> it -> exchange unwanted spares -> complete collections -> attract life and
> gain more control over future discoveries.

Randomness should create surprise. Progression should steadily turn surprise
into authorship. The player never chooses from three offers, farms a separate
currency, drags coins into a pot, or depends on rolling a special banishment
item.

## The starting world

- A new save starts on an exact **3 x 3 footprint: nine real land tiles**.
- Before the vibe selection, there is no provisional Meadow, character,
  mascot, or Worldheart visible behind the question.
- The worldheart rests on top of the center tile and can be dragged to another
  clear tile. Its current host is protected from ordinary moving or building.
- The selected collection determines all nine starting surfaces; Winter, for
  example, creates nine Snowfield tiles rather than repainting a hidden Meadow.
- The nine starting tiles make the first composition legible and intentional.
- The portal is permanent world infrastructure, not a stock object that
  can be lost, sold, covered, or used to softlock progression.
- Reward miniatures use a small radial presentation ring around the hole. They
  do not occupy grid cells, block walking, or reserve a 3 x 3 no-build plaza.
- Basic foundation terrain remains readily available. Special surfaces and
  themed tiles remain collectible pieces; the game must never starve a player
  of ordinary floor.
- Later expansion may reuse the current Nook reveal wave, but the opening 3 x
  3 world is already viable. Expansion is an opportunity, not emergency floor
  relief.

## The steady discovery rhythm

After a short first-use beat, the worldheart draws a saved interval between
**15 and 25 seconds**. It visibly breathes for a moment, opens, and spits out
one miniature onto its presentation ring.

Rules:

1. The reward is rolled and saved before the animation starts. Reloading can
   never reroll it.
2. A miniature persists until collected. Nothing expires or litters the real
   build grid.
3. Clicking a miniature, or using Interact while it is targeted, sends it
   directly to the Build Bag and records it in the Collection Book. No drag is
   required.
4. Interacting with the hole itself collects every waiting miniature in one
   sweep. A summary reveal replaces repeated modal cards.
5. The worldheart can show a small number of miniatures at once and bank the
   rest in a saved reserve. Initial prototype target: 4 visible and 12 total.
6. When the reserve is full, the clock pauses. The player loses nothing and
   returning from work does not create a cleanup chore.
7. Pulses accrue while the game is running, unfocused, or in a future Rest
   mode. Offline accumulation is not required for the first prototype.
8. The roll sequence uses an internal role bag rather than unrestricted RNG:
   early cycles guarantee a healthy mixture of terrain, substantial models,
   and details. This directly protects floor supply without exposing another
   choice UI.

The target is a pleasant background fountain: frequent enough to notice,
safe to ignore, and cheap to clear in one action.

## Exchanging pieces

The Build Bag exposes **Offer to Worldheart** on eligible tiles and models.
The player may also carry a piece to the portal for the physical ritual; this
must be an alternative, never mandatory dragging.

The initial contribution contract is:

- only a true spare copy may be offered; one copy is protected across placed
  and stored ownership;
- one eligible piece fills half of its collection circle;
- a second piece from that collection completes the circle and returns one
  different piece from the same authored collection;
- tile and model may contribute to the same circle and the returned member may
  cross kind when it belongs to that collection;
- the exact offered item is excluded, recent returns are suppressed, and an
  undiscovered eligible item is strongly preferred;
- if no valid different result exists, the original item is returned with a
  clear explanation;
- the input reservation and output are saved as one recoverable transaction,
  so a crash can neither delete nor duplicate a piece.

This is a useful reroll from the beginning, not a late random item the player
must first acquire. Near collection completion, the rule becomes explicit
convergence: a mastered collection seeks missing eligible designs rather than
allowing last-item purgatory.

## Progression is progression of control

The production rate should not accelerate until the world becomes stressful.
Progression instead changes how much say the player has:

1. **Wonder** - the worldheart produces balanced surprises from the starting
   collection vocabulary.
2. **Familiarity** - early collection milestones unlock the next authored
   tier and let the player favor that collection.
3. **Steering** - the player can attune the worldheart toward one collection;
   the active rule and odds are shown honestly in the Collection Book.
4. **Exchange** - spare pieces reroll within their collection without loss of
   tier or last-copy risk.
5. **Convergence** - a near-complete collection guarantees progress toward
   its remaining eligible designs.
6. **Authorship** - a mastered collection permits deterministic reacquisition
   of already discovered designs, providing an earned creative mode for that
   vocabulary.

Collection milestones grant creative consequences rather than score:

- new families and higher tiers entering the portal pool;
- collection-specific portal colors, sounds, and spit animations;
- attachments, landmarks, atmosphere options, and expansion gifts;
- new visitor species and behaviors;
- deterministic reacquisition tools at mastery.

Discovery count may unlock these rules. The game should not judge layout,
adjacency, symmetry, or aesthetic quality.

## Visitors and inhabitants later

Visitors are the long-term living-world layer, but they should answer the
review complaints instead of reproducing Garden Galaxy's chores.

- Visitors arrive near the worldheart and wander toward compatible placed
  objects: benches, ponds, gardens, stalls, toys, shelters, and landmarks.
- The collections present in the world influence **which** visitors appear,
  never whether the baseline reward cadence runs. Creativity cannot reduce
  spawn rate or block progression.
- Visitors use the world autonomously. Greeting, petting, or posing with them
  is optional flavor, not the way to extract currency.
- A completed visit deposits a typed gift into the worldheart reserve
  automatically. There are no visitor coins to click and no coins to drag.
- Every visitor and waiting gift is findable from the Collection Book or map.
- Build/Photo/Rest modes may calmly pause visitor movement without deleting a
  visit or reward.
- Repeated visits may allow a creature to become an inhabitant with a home and
  daily routines. Inhabitants add animation, interactions, and secrets, not
  hunger meters, schedules, or mandatory requests.
- Visitor type filters and collection favoring live in the Collection Book.
  They never depend on obtaining a banishment table or other random tool.

This keeps the beloved connection between collection identity, little lives,
surprise, and building while removing the attention tax.

## Feedback coverage

| Review problem | Worldheart answer |
| --- | --- |
| Too much clicking and dragging | One-click pickup, controller Interact, and one-action Collect All; no currency drag |
| Must constantly watch the game | Saved reserve with a cap; safe background accrual and no expiring rewards |
| World overrun by unwanted items | Rewards occupy presentation anchors, not build cells; Build Bag is abstract and unlimited |
| Tiny start and floor starvation | Nine intentional themed tiles plus balanced terrain cadence and readily available foundation terrain |
| RNG prevents a planned build | Collection attunement, same-collection exchange, convergence, then earned catalog reacquisition |
| Same item returns after recycling | Exact input is excluded and tier value is preserved |
| Banishment tool must be rolled | Pool controls are permanent Collection Book abilities, never random objects |
| Last pieces take tens of hours | Explicit near-completion guarantee rather than an endless probability tail |
| No goals or progression | Collection tiers, control mastery, world expansion, landmarks, visitors, and inhabitants |
| World feels lifeless | Autonomous visitors use placed objects and can later settle as inhabitants |
| Creativity harms visitor income | Decoration changes visitor identity and behavior, never the baseline rate |
| Storage causes hoarding anxiety | Physical verbs, abstract storage, global search/filter, batch operations, protected last copies |
| A single object can softlock progress | The worldheart is permanent world infrastructure and every transaction is recoverable |

This progression rework does not replace the separate quality-of-life ledger.
Undo, multi-select, group move/rotate/store, drag-to-place runs, camera freedom,
rebindable input, named saves, backups, brightness controls, and performance at
large-world scale remain definition-of-done requirements.

## Recommended architecture

Keep and extend:

- `StockManager` and the Build Bag as the ownership authority;
- `CollectionManager` and `CreativeCollectionService`;
- `BuildRewardService` concepts for novelty, recent memory, and rarity;
- miniature reveal and fly-to-bag presentation;
- Nook generation/reveal for later expansion;
- stable IDs, validated data, save migration, and controller contracts.

Replace or reshape:

- replace `DiscoveryTrayService` with a saved `WorldheartService` that owns the
  timer, reward queue, reserve cap, role sequence, and claims;
- replace placement-led `BuildCadenceService` with the saved 15-25 second pulse
  cadence;
- add `WorldheartExchangeService` for last-copy protection and atomic swaps;
- extract the rescue-hole visual from `PlayerController` into a reusable
  presenter shared by player rescue, arrival, and the permanent worldheart;
- replace `DiscoveryTrayPanel` with small world prompts plus Collection Book
  controls; ordinary collection occurs in the world;
- reuse visitor creature presentation later, but replace click/vase/reward
  behavior with autonomous visits and automatic typed gifts.

The worldheart must expose semantic input actions and a deterministic
controller target. Every mouse flow needs a controller-complete equivalent in
the same phase.

## Implementation sequence

### Phase 1 - playable core

- Create the exact nine-tile (3 x 3) start and movable tile-hosted portal presenter.
- Give the portal a saved 15-25 second queue with guaranteed opening rewards.
- Spawn miniatures around it and support individual collect plus Collect All.
- Grant directly through the existing Build Bag and collection boundary.
- Hide the three-offer tray in new games.

Exit: the selected nine-tile world appears without an avatar, the player
collects and builds, ignores the game for several minutes, returns, clears the
reserve once, saves, and reloads without loss or rerolls using mouse/keyboard
or controller.

### Phase 2 - exchange and protection

- Add bag and physical-world Offer actions.
- Count placed plus stored ownership and protect the last copy.
- Implement persisted two-contribution collection exchange and recovery tests.
- Add exact-input exclusion and impossible-exchange return behavior.

Exit: no exchange can lose a unique item, downgrade value, reroll through
reload, or grant twice.

### Phase 3 - collection control

- Adapt creative collection milestones to Wonder, Familiarity, Steering,
  Convergence, and Authorship.
- Add honest collection attunement and pool filters to the Collection Book.
- Tune the role bag, duplicate memory, terrain supply, and completion curve
  through long deterministic simulations.

Exit: both a surprise-led player and a player pursuing one exact build have a
clear path forward without a three-choice screen.

### Phase 4 - living world

- Convert visitor presentation assets to autonomous world users.
- Route visitor gifts directly into the portal reserve.
- Let world composition steer visitor identity without affecting cadence.
- Add the first inhabitant and several object interactions.

Exit: the world is visibly more alive, but ignoring every visitor cannot block
or slow collection progression.

### Phase 5 - expansion, migration, and breadth

- Reintroduce optional Nook expansion rewards after the 3 x 3 home is proven.
- Convert saved tray offers into worldheart queue entries without rerolling.
- Preserve all existing placed pieces, Build Bag counts, and discoveries.
- Add collections, visitor species, interactions, landmarks, and modular
  building vocabulary through data.

Exit: the new spine supports years of content without adding another currency
or mandatory maintenance loop.

## Prototype decisions to validate

The first playtest should answer these rather than locking them on paper:

1. Is a 20-second average pulse calming or does it become visual noise?
2. Is 4 visible / 12 banked the right reserve, and is one sweep satisfying?
3. How quickly must guaranteed terrain cadence grow the nine-tile start before
   a deliberate build begins to feel constrained?
4. Does the two-piece collection circle feel legible and generous without
   flattening discovery?
5. At what visible collection threshold should guaranteed convergence begin?
6. Should background accrual stop at the reserve cap or convert overflow into
   a single saved bundle?
7. Does the central portal need player-controlled quiet hours for photo/build
   sessions?

The vertical slice should be judged on hand comfort, ignored-game recovery,
time-to-first-intentional-build, useful tile supply, duplicate frustration,
and whether the world feels inviting before visitors are added.
