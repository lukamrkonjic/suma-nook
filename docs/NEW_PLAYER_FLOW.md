# New-player flow

This is the authored first-session sequence. Its job is to make the player
understand the whole world-building loop by doing it once:

**choose land → place the well → create Inspiration → claim a Vision →
grow the world → discover fishing in the surrounding ocean**

Every step is saved. Reloading resumes the exact required step and restores
its guaranteed piece if necessary.

## 1. Make a keeper

- Character creation is a dedicated, full-screen portrait scene.
- It changes identity only: name, body, face, hair, colors, and outfit.
- The world and the starting biome are not shown here.
- “Begin your world” starts the arrival; it does not silently create an
  island.

## 2. Arrive before the world

- The screen returns to open sky with no land.
- A portal opens at the origin and the keeper rises out of it.
- At the top of the rise, the game pauses with the keeper suspended.
- A three-card picker offers:
  - Grove Ground
  - Pale Sand
  - Fresh Snow
- The cards use real tile renders, not abstract icons.
- The choice cannot be cancelled. It decides only the beginning, not a
  permanent class or mechanical bonus.
- After selection, a complete starter island rises beneath the keeper:
  nine chosen ground tiles in a 3×3 square, surrounded by the real ocean
  tile field, with one mature pine already rooted on the land.
- The portal closes and the keeper falls onto the center tile with the
  familiar rescue bounce.

## 3. Build the progression heart

- The wishing well is granted immediately after the island arrives.
- No ocean tile is granted: the surrounding world is already made from real,
  fishable water tiles.
- The player places the well on any of the eight clear land tiles.
- The already-planted pine then becomes the first activity objective.

Shape Land cannot be closed while one of these required arrival pieces is
held. The player may rotate and choose a valid position, but cannot lose or
store away the item that makes progression possible.

## 4. Create the first Vision

- The prompt asks the player to tend the pine.
- Each completed tend sends green Inspiration toward the well.
- The first meter uses its accelerated introductory cost, so three completed
  tends bank the first Vision.
- Once banked, the prompt moves the player back to the well to claim it.
- The normal three-choice Vision ritual opens; the player keeps one.
- The selected tile or structure is immediately held for placement.

This teaches the permanent rhythm in the world itself: activities make
Inspiration, the well remembers it, and Visions become new world pieces.

## 5. Let placement create play

- After the chosen Vision is placed, the surrounding ocean becomes the final
  onboarding destination.
- The prompt says that something stirs in the ocean beyond the shore.
- The player catches and releases one fish there.
- Onboarding completes after the catch. Normal contextual hints and the
  wider progression systems take over.

The closing lesson is causal: **the place I built created the thing I can
do next**.

## Presentation rules

- One objective at a time.
- One sentence per prompt.
- Rewards appear only when their prerequisite is complete.
- Use motion, particles, sound, and world state before explanatory copy.
- Never leave the player without ocean access, a well, a tree, or enough clear land
  to shape freely.
- The land picker and every guided placement are keyboard-, mouse-, and
  controller-complete with deterministic focus.
- Cancel/back may open menus later, but it never dismisses the first-land
  decision or discards a required onboarding piece.

## Saved stages

1. `land_choice`
2. `place_well`
3. `tend_tree`
4. `claim_vision`
5. `place_vision`
6. `try_fishing`
7. `complete`

Saves from before this authored sequence load as `complete`; established
worlds are never pulled backward into onboarding. Saves paused at the retired
`place_water` step migrate to `place_well`, remove the guided ocean tile, and
receive the guaranteed wishing well.
