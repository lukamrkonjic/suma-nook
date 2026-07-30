# Suma — discovery progression

Status: current implementation authority, 2026-07-30.

This document supersedes the Inspiration, wishing well, Vision, refund-coin,
and shrine progression designs. Those documents remain only as historical
records.

## The player promise

The unknown supplies abundance. The world the player builds supplies intent.

An exposed land edge offers **Fish the unknown**. A successful catch grants
one immediately owned tile or model from a broad weighted pool. The result is
shown as a single discovery, not a three-choice draft. This is Suma's main
surprise engine and its source of pieces before the player has built useful
biomes.

Water is a normal, finite, placeable tile. It can be found, stored, moved, and
used to make ponds, rivers, lakes, shorelines, and dock spaces. It is not an
infinite ocean layer and it is not cosmetic background.

## Build → skill → discover

Skills used on placed world objects read a bounded neighborhood around the
source. The resolver builds a context manifest from nearby tile families,
tile/model biome tags, and source-object tags, then selects the strongest
eligible pool.

Examples:

- a pond among sand and palms yields beach and sunset-flavored pieces;
- a pond among pines yields forest and camping-flavored pieces;
- a pond among snow yields winter pieces;
- a tree in a forest corner yields woodland pieces;
- a tree on a beach can yield tropical/beach pieces;
- a future ore node uses the same contract for desert, winter, forest, or
  stone-shaped mining rewards.

This is intentionally legible rather than hidden precision math. Strong,
coherent local biomes should reliably beat a stray neighboring tile. Every
skill has a neutral fallback so rebuilding never makes an activity unusable.

## Reward contract

- Rewards are weighted data entries in `data/discovery_pools.json`.
- Void fishing grants one reward per successful catch.
- Local skills may require several actions per reward.
- A reward enters the Build Bag and collection journal before its reveal
  opens. Closing the game during presentation cannot lose it.
- The first void discovery is guaranteed to be `tile_open_water`, teaching
  that water is a building material and unlocking local pond fishing.
- Later void discoveries use the normal broad pool.
- Duplicate discoveries are allowed and clearly labelled.

Ferry gifts use the same single-item discovery contract. They are a gentle
periodic bonus, not a separate currency or choice economy.

## Duplicate exchange

The player opens **Offer Duplicates** from the Build Bag.

1. The system counts all owned copies of an exact item across placed world
   state and stored stock.
2. One keeper copy is always protected.
3. Each offer consumes one true spare and records `1 / 3`, `2 / 3`, or
   `3 / 3` against that exact item.
4. At three, the void returns a different random item in the same Build Bag
   category.
5. The returned item is owned before presentation, like every discovery.
6. Partial offerings persist in the save.
7. If the current content catalog has no different eligible item, the three
   copies are returned; the player never loses items to an impossible draw.

There are no refund tokens, meters, coins, or placed ritual objects.

## First-session flow

1. Create the keeper.
2. Choose the first land material.
3. Arrive on a 3×3 island surrounded by the unknown.
4. Fish from an exposed edge.
5. Discover and place the guaranteed water tile.
6. Tend the starter tree.
7. Discover and place a reward shaped by the chosen local biome.
8. Enter free play.

The onboarding uses the production systems and persists every stage. It does
not grant a temporary fake ocean tile or a tutorial-only wishing well.

## Architecture

- `DiscoverySystem` owns pool progress, local context resolution, weighted
  draws, ownership, collection recording, and pending presentation.
- `VoidExchangeSystem` owns keeper protection, partial exact-item offerings,
  same-category replacement, and loss-proof failure handling.
- `ProgressionModule` composes those services with milestones and owns the
  versioned save adapter.
- `BuildCategoryResolver` is the shared authority for Build Bag and exchange
  categories.
- `DiscoveryReveal` is acknowledgement-only presentation.
- `data/discovery_pools.json` is the extensibility point for biomes and future
  skills.

The live save format is progression version 3. Loading an older progression
archives its data, converts a pending promised reward into a safely owned
discovery, replaces ritual well/shrine instances with ordinary decorative
counterparts, removes retired currencies from live inventory, and completes
obsolete onboarding stages.

## Non-goals

- no Inspiration meter;
- no wishing well;
- no banked Visions or three-card choice;
- no focus/anti-focus shrine;
- no hidden pity;
- no XP or skill levels;
- no materials from ordinary discovery actions;
- no infinite ocean background masquerading as owned water.
