# Suma — new-player flow

Status: current implementation contract.

The first session starts with the world, not an avatar.

## 1. Nine pieces of land

The game opens directly in Shape Land. Nine ordinary `tile_grass` pieces form
a 3×3 square against the sky. There is no character creator, portal arrival,
land picker, dock, fishing lesson, starter bench, chest, or hidden resource
inventory.

The optional keeper remains a later world tool and is hidden during this
opening sequence.

## 2. One tree in the Build Library

The Build Library contains one stateful Young Pine. The game immediately
holds it at the controller grid cursor or pointer preview and asks:

> Place your first tree.

Placement begins the real maturation timer. The tree is never spawned ready
and picking it up cannot refresh it.

## 3. Let the tree mature

The tree visibly settles and grows while one short hint teaches camera motion:

> Pan or turn the world while your tree grows.

When ready, it gives a small shine and gesture. The prompt becomes:

> Harvest the tree — 3 satisfying hits.

## 4. First forest reward

Each primary click/confirm performs one hit and plays one axe impact. The third
fells the tree and guarantees one random Forest Foundations tile. That finite
piece is already safe in the Build Library before the reveal animation.

The piece is held for immediate placement:

> Add the discovery to your world.

The exact tree remains in place as a regrowing source.

Land may be placed in any empty grid coordinate. Connected gardens remain the
natural visual default, but detached islands never require a temporary bridge.

## 5. First visitor

The global visitor heartbeat begins with the world. Three to six active
minutes into the session, after the first tree loop is complete, a random
retained SDF animal appears on a clear tile inside a quiet shine. It waits
indefinitely.

Clicking/confirming the visitor fades it away and grants a random non-Forest
foundation bundle. This is the explicit bridge out of the opening Forest
collection. The player places one piece, then the normal global visitor pool
and free play take over.

## 6. Free play

The player now has two understandable collection engines:

- harvest a chosen source for themed rewards;
- notice a visitor for a completely random world gift.

The Build Library, collection, and optional keeper tool remain available. New
sources, visitor looks, and reward pools add through data without changing the
flow.

## Persistence contract

Stages are:

1. `place_tree`
2. `wait_tree`
3. `harvest_tree`
4. `place_forest_reward`
5. `wait_visitor`
6. `place_visitor_reward`
7. `complete`

The guided piece's kind and stable ID persist. Interrupted placement repairs
stock only when needed; it never duplicates a promised item. Harvest runtime
is stored on the stable tree instance. A pending visitor stores its selected
presentation and pre-rolled reward, so reload never rerolls either.
