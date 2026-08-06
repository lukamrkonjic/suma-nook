# Harvesting and world visitors

Status: current implementation contract.

This replaces the retired Inspiration/Well/Ferry progression as Suma's first
repeatable collection loop.

## Player promise

Anything marked harvestable follows the same visible rules wherever it came
from and wherever the player places it:

1. A newly created source matures.
2. Every deliberate click/confirm produces one strong hit.
3. The final hit grants one themed world piece and starts regrowth.
4. The exact placed instance returns: same stable instance id, position,
   rotation, scale, model, visual seed, timers, and future upgrade state.

Moving or storing an instance never refreshes it. Stateful structure tokens
preserve its deadline and hit progress. Storage does not create a second
source or turn a regrowing source into a ready one.

## Three progression channels

- **Harvest sources** are targeted gacha. A source has a home subcollection,
  with a smaller chance of another reward from its broad biome.
- **World visitors** are global gacha. They can introduce pieces from a biome
  the player does not yet own and therefore keep a forest start from becoming
  a forest-only save.
- **Milestones** remain the deterministic safety rail for future guarantees,
  unlock choices, and bad-luck protection.

Fishing can later return as a more active, partly steerable global channel;
none of these modules depends on it.

## Content and module boundaries

The generic content catalog owns five typed, atomically validated definition
families for this loop:

- `RewardPoolDefinition`: weighted tile/model entries and bundle quantities.
- `RewardRollPolicyDefinition`: novelty weighting, recent-result suppression,
  and bounded rare pity without changing pool membership or quantities.
- `RewardRevealProfileDefinition`: replaceable presenter type, semantic clay
  materials, shape, timings, and miniature fit.
- `HarvestProfileDefinition`: verb, hit count, maturation, regrowth, home
  collection, source presentation, roll/reveal policies, presenter settings,
  and normal/first reward pools.
- `VisitorPresentationDefinition` and `VisitorProgramDefinition`: replaceable
  presentation adapters plus cadence and reward-pool policy.

A structure opts in only through:

```json
"capabilities": {
  "harvest_source": {"profile_id": "harvest_tree_evergreen"}
}
```

There are no structure-id branches. Adding, updating, or removing a source is
the ordinary content CRUD workflow: edit definitions, let atomic validation
reject dangling references, and run the headless suite.

The host model is deliberately replaceable. The stable structure id owns its
capability and saved runtime; `asset_id` owns only the authored visual. Swapping
a tree or bush GLB therefore preserves timers, rewards, placement, and saves.
Generated yield presenters derive placement from the resolved model bounds
instead of depending on authored mesh or bone names.

Berry growth is the first reusable yield presenter. A profile selects
`berry_cluster` and supplies semantic palette material, fruit count, size,
spread, height envelope, and bounded ready-nudge tuning. Fruit is absent while
the source matures or regrows, appears directly inside the resolved host-model
canopy when ready, and uses a sparse tween-only pulse/shiver as its harvest
prompt. Any future shrub, planter, trellis, or fantasy plant can reuse the same
presenter with a different lifecycle and reward pool; it does not inherit
bush-specific code or spawn detached fruit objects.

`HarvestingModule` owns lifecycle state, deadlines, hit validation, reward
transactions, persistence, and signals. Presentation subscribes to those
signals; it does not decide rewards or readiness.

`VisitorModule` owns the global heartbeat, pre-rolled pending event, selected
presentation id, collection transaction, and persistence. The initial
`sdf_creature` scene adapter is selected through data. It can be deleted and
replaced by another registered adapter without changing scheduling, rewards,
or saves.

Both modules use the shared `BuildRewardService`. A final reward transaction
is:

1. validate source/event;
2. roll with the serialized `RngService` stream (visitors pre-roll on spawn);
3. mark the source regrowing or visitor collected;
4. grant tile/model copies to `StockManager`;
5. record the collection entry;
6. request an immediate save;
7. play presentation.

The reveal never owns or delays the grant. Closing the game, accelerating an
animation, or replacing a presenter cannot lose or reroll a piece.

## Reward variety without biome dilution

Harvest profiles keep their existing subcollection-specific reward pools. A
separate roll policy adjusts only the weights inside that pool:

- undiscovered pieces receive a moderate boost;
- the last six results in that subcollection are strongly de-weighted;
- consecutive non-rare results gradually boost rare entry weights after a
  threshold, capped at a fixed multiplier; and
- every roll still grants exactly the amount authored by the pool.

The owning `HarvestingModule` stores a short history and rare-miss counter per
`home_collection`. The generic reward service remains stateless: visitors,
events, and future sources may opt into their own policy and history owner.
This increases surprise without letting a Forest source cross into global
reward pools or accelerating the economy.

## Runtime state

Harvest state is stored under `StructureState.runtime_state["harvest"]`:

```gdscript
{
  "profile_id": "harvest_tree_evergreen",
  "state": "maturing", # maturing | ready | regrowing
  "hits": 0,
  "deadline_unix": 0.0,
  "cycles": 0,
  "visual_seed": 12345,
}
```

Deadlines are absolute and offline-inclusive. A sorted scheduler wakes only
for the next due source; there is no per-source `_process` work.

Harvest feature save data also stores bounded reward-selection history by
subcollection. This history affects only future weights; ownership and source
runtime remain independent.

The visitor save stores the complete pending event, including presentation id,
world cell, and pre-rolled reward. Visitors never expire. A save can therefore
be closed for weeks and still reopen with the same visitor and gift waiting.

## Interaction and feel

Shape Land is the permanent primary mode. A plain primary click/confirm on a
ready harvest source performs exactly one hit. The move-piece action handles
repositioning explicitly, including with a controller-native grid cursor.

Each hit escalates through:

- one varied axe-impact sound per accepted click;
- directional squash/bend and recoil;
- a target-only white impact flash;
- leaf/chip/dust particles and layered audio;
- stronger penultimate and final-hit timing.

The final tree hit falls away from the strike, settles into a small regrowing
silhouette, grants the reward, and later grows back in place. All impact
effects live in the presentation adapter, independently of lifecycle and loot.

Gatherable berry sources use the same authoritative click port but a separate
presentation: ripe fruit lives visibly on the host plant, receives a soft
pickup impact and leaf burst, then disappears while the host plant stays
full-sized. The saved absolute deadline restores the same ripe fruit cluster,
including after offline time. Its occasional attention motion uses a bounded
tween rather than a per-source process loop.

## World Bud reward reveal

Every harvest final hit now supplies a stable `reveal_profile_id` beside its
already-granted reward. `RewardRevealSceneAdapter` resolves that data through
an application-owned presenter registry. The initial `world_bud` presenter:

1. arcs a source-themed clay bud from the harvested object;
2. gives it a short squash-and-swell anticipation beat;
3. opens into a miniature rendered through the real tile/structure factories;
4. communicates rarity and discovery through timing, sound, and the miniature
   instead of screen-filling world text; and
5. flies the miniature toward the Build Bag side of the camera.

The bud is a neutral reward vessel even for berry sources. Ripe berries remain
attached to their plant and are never repurposed as a click-spawned reward prop.

The flow is non-modal. Players may keep building or harvesting while it runs.
Pointer users can click the physical bud and controller users can press the
ordinary Interact action to accelerate it. Neither path consumes the next
world action. Only one World Bud scene exists at a time; queued duplicate
rewards combine into one ceremony, and a backlog automatically uses shorter
timings. This bounds scene-node and animation cost for future farms and
automation while preserving the actual granted quantity.

`presenter_type` is a registry key, not a feature branch. Another reveal style
can replace World Buds or coexist with them without modifying harvesting,
reward rolls, saves, or models.

## Visitors

The heartbeat is global: building more sources or a denser farm never speeds
visitor cadence. At most one visitor is pending or visible, and that exact
event is persisted in data. There is no expiry or FOMO.

The initial adapter chooses one retained procedural SDF animal, places it on a
clear authored world cell, and adds a soft emissive floor shine. Clicking or
confirming it makes it brighten, rise slightly, fade away, and grant its
pre-rolled world piece directly to the Build Library.

First-visitor policy guarantees a useful non-Forest foundation tile bundle;
the exact biome and tile remain random. Later visitors use the global pool.

## Launch tuning

| Source | Hits | Maturation | Regrowth |
| --- | ---: | ---: | ---: |
| Young tree | 3 | 20 s | 35 s |
| Mature tree | 4 | 30 s | 60 s |
| Tall tree | 5 | 45 s | 90 s |
| Berry shrub | 1 | 24 s | 45 s |

The first visitor is scheduled 3–6 active minutes after the world begins.
Later visitors arrive every 15–30 active minutes. A waiting visitor pauses the
heartbeat.

## Future automation seam

Automation consumes the same `request_hit(instance_id, actor)` port. It does
not mutate deadlines or rewards directly. Initial helpers may perform
non-final hits only, leaving the satisfying final click to the player. Later
helper slots and a capped physical reward crate can ease large farms without
making placement density multiply the global economy.

Automated final rewards should later enqueue through the same reveal adapter.
A capped physical basket may retain unopened buds, but it must not bypass
source timers, grant additional rolls, or create a second reward transaction.
