# Project progression

Projects are Suma's reliable progression spine:

> Choose a Project → contribute a few things from the world → reveal a reward → develop the world.

Collection Projects grant one pre-rolled tile or model from a chosen
collection. Frontier Projects reserve an expansion point's seed card and
generate that land only after their requirements are complete. Both use the
same `ProjectService` state and `ContributionService` transaction boundary.

## Interaction and edit intent

Normal play starts in interaction mode. A click resolves exactly one
highest-priority action through `InteractionTargetResolver` and
`InteractionRegistry`: claim a Reward Drop, gather a Special Find, toggle a
fire, harvest a resource, or open a Frontier Project. Resource nodes remain
tactile even when the tracked Project does not currently need their material.

`build_mode` enters explicit edit mode. In that mode clicks only pick up,
move, place, rotate, or store world pieces. They never execute gameplay
interactions. With a pointer, interaction mode also distinguishes the same two
intents by gesture: click interacts, while hover-drag lifts and moves a world
piece. Reward Drops cannot be moved before claim. The controller uses the same
two intents through its deterministic grid cursor and named move action; it
never emulates or warps a mouse.

## Shared Project state

Definitions live in `data/projects.json`. Runtime Project state contains a
stable ID, type, contribution slots, deterministic seed, concealed pre-rolled
reward or Frontier metadata, completion/reward flags, and presentation tags.
Common contribution tags are deliberately small: `timber`, `stone`, and the
flexible `provisions` family (`fish`, `crop`, `fruit`, `forage`, `herb`).
The initial Build Bag includes a reusable tree and berry shrub, while the
starting land includes a reusable Stone outcrop, so the opening loop is fully
available in god view without deploying the legacy keeper.

Only one Project is tracked in the HUD, but all created Projects retain their
progress. Contribution receipts make commits idempotent. Completion and reward
granting are independently guarded, so a final hit, reload, or duplicate
signal cannot advance or grant twice.

## Resource nodes

Structures opt into `harvest_source` with a profile from
`data/harvest_profiles.json`. The generic lifecycle is:

1. `maturing`
2. `ready`
3. deliberate hit progress stored on the stable instance
4. `regrowing`
5. back to `ready`

One click is one authored impact. Young trees fall in three hits, larger trees
take four or five, and rocks crack in four. The final blow commits one eligible
Project contribution when needed, but the source still visibly depletes when
no Project slot is available. Trees and rocks swap to explicit depleted visuals
while their stable placed instance regrows. Common results never enter the
inventory or token pouch. Fishing commits one Provisions receipt per haul.

## Frontiers and Special Finds

`FrontierProjectService` stores a stable seed card the first time a frontier is
seen (and migrates existing expansion points on load). The world-anchored card
shows each requirement as an icon plus `current/required`; clicking an
incomplete point tracks it without opening the Projects modal. Completion only
makes the point Ready. A deliberate click on that ready point emits the single
generation request, and Main hands the saved card to the cooperative Nook
generator. Interrupted, explicitly confirmed expansions resume after load;
older completed saves migrate to Ready and wait for a click.

`SpecialFindService` owns one world-level opportunity clock and a small active
cap. It marks an eligible existing resource object with persistent visible
state. Gathering moves exactly one item into `FindsReserveService`, a tiny
purpose-built reserve used by rare Projects. Placing more resource models does
not create more clocks or improve event rate.

## Collection rewards and Falling Objects

The Project board maintains three stable Collection offers. Their exact item
is selected when the Project state is created, saved while concealed, and
granted through `BuildRewardService` only once at completion.

Falling Objects are a much rarer bonus. Choosing a collection pre-rolls a
piece but does not grant ownership. `RewardDropService` finds a clear generated
land cell, places one non-movable locator, and grants the existing ownership
model only when that locator is claimed. One unclaimed drop blocks another
event. Wish timers count active play, pause for major menus, persist without
offline catch-up, and use long tuned intervals.

## Persistence and migration

The save's `features.project_progression_version` is `1`. Project states,
receipts, tracked ID, offers, Frontier metadata, Special Finds reserve and
schedule, resource runtime, Reward Drops, and Falling Object timers all save
through `GameCore`. Missing fields are valid old saves: Collection offers are
created, existing frontier points receive stable metadata, expanded land is
preserved, old placed resource instances adopt the reusable lifecycle, and
old pending wishes already granted to stock are marked `pregranted` so their
claim presentation cannot duplicate ownership.

Core acceptance lives in `tests/test_runner.gd`; the real-scene contract lives
in `tests/full_loop_runner.gd`.
