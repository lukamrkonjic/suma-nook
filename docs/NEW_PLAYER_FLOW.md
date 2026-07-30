# New-player flow — implementation prompt

Directive spec for the onboarding and progression ramp. Each numbered
item is a buildable instruction. Companion to
`docs/PROGRESSION_DESIGN.md`.

## Stage 1 — Character creation

1. Make character creation a **full-screen dedicated scene**: neutral
   backdrop, character centered, soft light, camera close. Do NOT
   render the world or tiles behind it — the world doesn't exist yet.
   (Replaces current behavior where the player stands on tiles during
   creation.)
2. Offer a small curated set: face, hair, skin, starter outfit. One
   confirm button ends the scene. No stat choices, no text walls.

## Stage 2 — Arrival and first land

3. Fade from creation into soft mist/emptiness. Present the
   **land pick**: ~3 curated land styles + 1 water edge, shown as
   little dioramas. On pick, tiles materialize under the character's
   feet as the camera pulls back — the world visibly begins from their
   choice.
4. Grant the sapling and the wishing well. Prompt the player to place
   each, free placement, no wrong answers, one-sentence hints max.

## Stage 3 — First loop (first 10 minutes)

5. Prompt one tree-tend action. Green wisps visibly fly from the action
   into the well. No deposit UI exists anywhere.
6. Fast-track the first meter. Well glows + chimes. On approach, show
   the **Vision reveal**: three items presented, keep one. Rig it: all
   three good, one is a Keepsake with a verb (ball, creature
   attractor).
7. The moment the reward is placed, spawn a fishing ripple **on the
   player's own water tile**. Tiny callout: "Something stirs where you
   built." This teaches the flywheel wordlessly.

## Stage 4 — Teach the rhythm (first hour)

8. Teach wisp colors by showing, never telling: fishing emits blue
   wisps → reveals lean waterside; tending emits green → reveals lean
   forest. Every reveal keeps one wildcard slot; ~1 in 8 Visions is
   fully random. No tutorial popup explains this — color + contents do.
9. Enable the **3-Vision bank**: each banked Vision adds a stacking
   movement-speed buff + spirit trail. At 3, let the current action
   finish, then wisps refuse to enter and nearby nodes gently gesture
   toward the well. No blocking popups — the world communicates.
10. Early insurance: while owned tiles are under ~25, every reveal
    includes at least one plain land tile option. Taper this off as
    the world grows.

## Stage 5 — Systems come online (first sessions)

11. Surface skill XP after the first few actions; levels unlock **new
    actions and visible tools**, never flat percentages.
12. Open the **journal** at the first discovery: silhouettes always
    show the next few uncollected things.
13. On the first duplicate, show a one-time hint: the well accepts
    refunds. Refund meters are carvings on the well that visibly fill;
    3 refunds of a category mint that category's coin, which waits at
    the well and releases a guaranteed category draw.
14. Trees enter a pretty resting state after tending (never a stump)
    and regrow on a real-time timer, including while offline.
15. First journal page completion pays a **garment**, with an
    on-character reveal moment. Clothing only ever comes from
    milestones.

## Stage 6 — Mid game

16. Unlock the **shrine** via an early milestone: place any owned item
    on it and draws visibly lean toward it and its family. This is the
    player's targeting and dupe-farming tool.
17. Run world events on a **global heartbeat**: shore crates on
    water-meets-land edges, creature visits near attractors. Placed
    variety expands event kinds; density never raises frequency.
18. Evolve the well's look at collection thresholds (moss, carvings,
    glow) — the save's visible progress bar.
19. Keep Keepsakes at ~1 in 10 Visions: weather toggles, attractors,
    playable objects, gambling stations (every dud result is itself a
    "Well Curiosities" journal collectible).

## Stage 7 — Deep game

20. Ship **teleport tiles**: placeable, cooldown-based, for crossing a
    grown world. Never an inventory item.
21. Offer a **second well** as a major milestone: defines a new
    district, keeps claim-walks short forever. Placement is a real
    decision.
22. Show **horizon landmarks** (island, mountain silhouette) from day
    one, unreachable until deep-game investment — the long-term goal is
    literally visible on the horizon from the first session. Each
    landmark unlocks a new domain module: skill + tile family + anchor
    + journal chapter + keepsake set.

## Sequencing principles

- One system per moment; never introduce two at once.
- No tutorial text over one sentence; prefer the world gesturing over
  UI explaining.
- Every unlock should be *encountered* (first dupe → refund hint),
  never front-loaded.
- The first session must contain: a personal choice, a rigged great
  reveal, a self-built earning surface, and a visible horizon goal.
