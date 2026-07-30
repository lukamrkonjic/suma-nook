# Suma — vision & progression design (v3)

Status: v3 — the whole-game vision. Locks v2's shipped decisions,
adopts the Mastery Arc as the progression spine, and integrates the
Garden Galaxy research (`docs/GG_RESEARCH_FINDINGS.md`).  
Supersedes: v2 of this file, and the progression pillars of
`DESIGN_PILLARS.md` (its **visual pillar and anti-pillars remain in
force**).  
Companions: `docs/NEW_PLAYER_FLOW.md` (authored first session),
`docs/PROGRESSION_REWORK_PLAN.md` (implementation phases + status),
`docs/GG_SPECIAL_ITEM_INSPIRATION.md` (clean-room reference).

Decisions marked **[v3 default]** were resolved to the recommended
option and can be vetoed by Luka; everything marked **[locked]**
shipped in v2 and is settled.

---

## 0. The game in one breath

You are a keeper who arrives before the world exists. Everything you
do — fishing, tending trees, watching clouds — releases Inspiration
that your wishing well turns into new pieces of the world. You place
every piece yourself. The world you compose creates the things you can
do next, and the longer you play, the more the well listens to you:
what begins as delightful chance becomes, hour by earned hour, a world
built exactly to your vision.

**"A small world arrives one beautiful piece at a time — and learns to
arrive on purpose."**

## 1. Identity — what Suma is, and refuses to be

Suma is a **character-inhabited, collection-driven world composer**:
GG's cozy gacha heart, carried by a keeper you customize and steer,
with progression that respects the player's plans.

It is also, deliberately, a **nervous-system regulator** (research F1).
Players will come to it anxious, grieving, overstimulated, or simply
tired. Every system must pass the standing check: **"Can this stress
anyone?"** Concretely and forever:

- No failure states, timers, expiry, or FOMO. Away time only
  accumulates gifts.
- No forced reading; prompts are one sentence; the world gestures
  before UI explains.
- Nothing the player owns is ever destroyed by accident: undo in
  build mode, deliberate hold-to-confirm on irreversible offers,
  loss-proof effect unlocks (§15).
- Saves are sacred: never wiped, never regressed, migrated forever.

The anti-pillars of `DESIGN_PILLARS.md` still bind: no survival
crafting, no colony/farming spreadsheets, no daily chores, no base
defense, no live-service pressure, no monetized randomness, ever.

## 2. Audience & positioning

Three overlapping audiences, all served by one design:

1. **Flow players** — delight in surprise, decorate around what
   arrives. Served by honest randomness and the stray slot.
2. **Planners & completionists** — have a vision, need control and
   convergence. Served by the Mastery Arc (§8): control is earned,
   explicit, and taught.
3. **Ambient players** — the second-monitor half of the cozy
   audience: podcast + game, work-break check-ins. Served by Rest
   mode (§12) and accumulate-while-away rules.

**Positioning claim (research Part 6):** GG's weakest-fit players —
those wanting freeform building, explicit goals, or minimal RNG — are
exactly who Suma's differentiators serve, without alienating GG's
delighted core. *The cozy collection game that respects your plans.*

## 3. Pillars (v3)

1. **The keeper is the game.** A visible, customizable character
   performs every activity and inhabits the world. [locked]
2. **Verbs are physical, storage is abstract.** The well, shrine, and
   offerings live in the world; unplaced pieces live in the clean
   Build Library. GG proved both halves. [locked]
3. **You steer by playing.** Activities are typed; doing is aiming.
   No coin dragging, no inventory management. [locked]
4. **Randomness is honest — and mastery over it is the progression.**
   No hidden weighting; every control tool is visible, earned, and
   taught at unlock. Discovery stays random forever; re-acquisition
   becomes increasingly deterministic (§8). [locked + v3]
5. **Building is never punished.** Placement expands what can happen;
   density never raises income; effects show their radii; decorating
   can never reduce spawns. [locked]
6. **Three dopamine cadences, always.** Seconds (wisp + tick),
   minutes (Vision ritual), hours (milestones, sets, garments). Every
   feature must feed at least one. [v3]
7. **Rewards change how you play.** A fixed slice of all rewards are
   verbs, not nouns; keepsakes are reagents that react to each other.
   [locked + v3]
8. **The character grows legibly.** Tools, garments, and verbs — never
   level numbers. Every garment has a story. [locked]
9. **Away time is a gift.** Trees regrow offline, crates wait
   forever, Rest mode accumulates gently. Returning is a warm ritual,
   never a punishment. [locked + v3]
10. **The world is the interface.** Meters are carvings, progress is
    moss on the well, prompts are gestures. UI exists where diegesis
    genuinely can't. [locked]

## 4. The player journey at three scales

- **A minute:** perform an action → wisps fly → meter steps with a
  chime → maybe a journal silhouette fills in.
- **A session (~30 min):** 2–4 Visions claimed and placed, one
  milestone or page tick, one small surprise (crate, rare recovery
  state, creature visit), the world visibly larger or lovelier.
- **A lifetime (hundreds of hours):** the Mastery Arc completes; sets
  close with physical trophies; districts multiply around new wells;
  landmarks land; seasons bring new domains; the keeper's wardrobe
  tells their whole history. The endgame is authorship: building
  exactly the world imagined, with tools earned through play.

## 5. The core loop [locked]

```
 do activities  ──►  Inspiration wisps  ──►  well banks a Vision
      ▲               (typed by domain)      (max 3 — then earning
      │                                       pauses until claimed)
      │                        keeper speeds up (+1 per banked Vision,
      │                         spirit trail) and walks to the well
      │                                              ▼
 place tiles/structures  ◄────  keep 1 of 3  ◄──  claim Visions
 (world grows: more nodes,
  more kinds of events)
```

## 6. Inspiration & domains [locked]

Wisps are typed by their source activity; each domain fills its own
meter, mapped 1:1 onto tile families:

| Domain | Earned by | Rewards lean toward |
|---|---|---|
| Waterside | fishing, shore crates | `waterside` tiles, docks, water life |
| Grove | tending trees | `living_grove` tiles, trees, forest structures |
| Meadow | meadow tending, future bug catching | `home_meadow` tiles, flowers |
| Stone | mining (future) | `stonebound` tiles, rock features |
| Winter | winter activities (future) | `winter` tiles and structures |
| Drift | cloud watching, benches, stargazing, Rest mode | wildcard: curios, keepsakes |

Steering is majority-weight, never exclusivity — surprise is the
point. The **Currents journal page** (§17) makes the mapping explicit
in-game: the legibility epiphany ("it all makes sense!") is engineered
into the first hour, never left to luck.

## 7. The well & Visions [locked]

- The well banks at most **3 Visions**; at the cap, the current action
  completes, then earning gently refuses and nodes gesture wellward.
- Each banked Vision adds a stacking **speed step + spirit trail** —
  the claim walk is the celebration, and it self-corrects as worlds
  grow.
- Claiming reveals **three options, keep one**. Composition **2 + 1**:
  two in-domain, one stray from everywhere. ~1 in 8 is a **Wild
  Vision** (all three fully random) — the jackpot pull and Drift's
  payoff.
- **Land insurance:** while the world is small, one slot is always
  plain land, tapering as it grows. Ground is never the bottleneck —
  GG's #1 failure, permanently designed out.
- The well **physically evolves** with total collection — moss,
  carvings, glow, orbiting wisps: the save's visible progress bar.

## 8. THE MASTERY ARC — the progression spine [v3 default: adopted]

The research's central finding: GG's real long-game was *progression
of control over randomness*, assembled by accident by its most devoted
players and never found by its refunders. Suma designs the arc on
purpose. **The decorations are the collection; the control is the
progression.**

Governing rule: **randomness owns discovery forever; control owns
re-acquisition increasingly.** First-time finds always come through
Visions. Copies, completions, and plans become progressively
deterministic.

| Stage | Player state | Tools (milestone-gated, taught at unlock) |
|---|---|---|
| 1. Wonder | Pure honest Visions; room always grows | — (land insurance active) |
| 2. Steering | "Doing is aiming" understood | Domain meters + Currents page (onboarding teaches) |
| 3. Shaping | First deliberate targeting | **Shrine** (bias toward a piece/family) · **Refund coins** (3 offerings → guaranteed domain draw) |
| 4. Pruning | Curating the pool | **Anti-shrine** — the shrine's second mode: a set piece and its family leave the draw pools ("the well forgets") |
| 5. Convergence | Sets close reliably | **Far-seeking coins**: at a printed threshold (80% of a domain's set), that domain's coin upgrades — its draws offer only unowned pieces. Stated on the well carvings; a rule, not hidden math |
| 6. Authorship | "I build exactly what I envision" | **Pattern Book** (§11) · **Duplicator** keepsake · **Vendor** keepsake |

Stage 6 *is* the earned creative mode GG's reviews begged for —
reached through play, so discovery is never devalued. Every tool
arrives with a one-sentence diegetic introduction (GG's fatal flaw was
leaving its tools to forums; taught-at-unlock is a hard rule).

## 9. The duplicate economy [locked, extended by v3]

Dupes are honest outcomes and often *wanted* (ten pines make a
forest). Unwanted ones are player-operated fuel:

- **Refund at the well:** each domain's meter is carvings on the well
  itself. 3 refunds of a kind mint that domain's **coin**, which waits
  at the well (never inventory) and releases a **guaranteed in-domain
  draw**. Batch offering ("offer all copies of this") ships with it.
- **Far-seeking upgrade** (stage 5): a mastered domain's coin draws
  only unowned pieces. The last-items asymptote — GG's most-cited
  completion pain on both review polarities — mathematically cannot
  happen.
- The refund vessel is charming, not administrative: a small vessel at
  the well visibly fills and ceremonially breaks into the coin (the
  piggy-bank joy, original form).

## 10. Shrine & anti-shrine [locked + v3]

One placeable shrine structure, two modes:

- **Focus** [locked]: set an owned piece; draws visibly lean toward it
  and its family. The dupe *source* for builders.
- **Forget** [v3 default]: set a piece in the shadowed cradle; it and
  its close family leave the pools until removed. The pool *pruner*
  for the finished-with-planters crowd (GG's despawner was one of its
  most-praised advanced tools).

Both are spatial, visible, and reversible. Bias strengths live in
tuning; convergence is guaranteed by stage 5 regardless.

## 11. Pattern Book & the authorship tools [v3 default]

- **Pattern Book:** a journal surface where any *discovered* piece can
  be re-ordered directly for Inspiration (cost scaled by rarity;
  visibly pricier than luck). Discovery remains random; re-acquisition
  becomes a plan. Answers "I want ten pines," "let me buy what I've
  unlocked," and the entire creative-mode demand.  
  **Persistence: per-save** — with a **New World+** toggle at world
  creation that carries the Book into a fresh world (the "saves as
  layouts, not restarts" wish, opt-in so first-worlds keep full
  discovery magic).
- **Duplicator** (keepsake, consumable): copies a held piece. GG's
  power users called theirs "the most important item in the game."
- **Vendor** (keepsake, placeable): a rotating stall offering a few
  known pieces for Inspiration on a lazy cycle — the deterministic
  sink that pairs with ambient check-ins.

## 12. Rest mode — the ambient bridge [v3 default: near-term scope]

Sitting the keeper on any Drift seat (bench, hammock, blanket) enters
a sanctioned ambient state:

- UI fades; camera drifts; the world keeps living — creatures visit,
  weather passes, wisps settle beside the keeper.
- A small **capped** Drift trickle accrues (never optimal play — the
  anti-density pillar applies to idling too).
- Events queue politely and persist. Nothing is ever missed.
- Standing up plays a brief "while you rested" greeting — the return
  ritual.

This gives the second-monitor half of the audience a diegetic home
inside a character game, makes Drift's bench identity real, and turns
the game into the ambient terrarium GG accidentally was — without
surrendering the keeper.

## 13. The world flywheel [locked]

Activity opportunities appear **on player-placed content**; building
expands what can happen and never how fast:

- Fishing spots surface on placed `waterside` tiles; crates wash up on
  water-meets-land edges and persist until opened.
- Trees are decoration *and* nodes: tending enters a pretty resting
  state (never a stump), recovery runs in real time including offline,
  and occasionally returns a bonus state (bloom, nest) feeding the
  journal.
- **Anti-density rule:** special events ride a global heartbeat;
  placement chooses *where and what kind*, never *how often*.
  Clustered and scattered layouts earn identically — plant where it's
  beautiful.
- **Attractors** bias nearby event kinds (lantern → moths, birdbath →
  birds), radii always shown. Feeding an attractor a matching piece
  strengthens it — intentional, lightly documented (§15 secrets).
- **Anchors** are each domain's hub; milestones upgrade event quality
  and variety in their radius.

Spawns are diegetic — ripples, shimmers, perched birds — never UI
markers in a composed scene.

## 14. Activities & the character [locked]

Level-free. `skills.json` defines verbs: tool, timing, animation,
domain. Character growth is **tools, garments, and new verbs** at
journal milestones — deep-water casting, tree grafting, night
fishing, stone stacking. A reward that only raises a number is a
design smell. Each future domain ships as a self-similar module: one
activity + one tile family + one anchor + one journal chapter + one
keepsake set.

## 15. Keepsakes — reagents, not props [locked + v3]

~**1 Vision in 10** offers a Keepsake: an item that adds an
interaction. v3 design rule: every keepsake performs one small verb
**and reacts to at least one other item** (research F7 — charm
compounds combinatorially):

- World-mood objects: rain, snow, petals, fog, stars, time of day.
  **Loss-proof** [v3]: discovering one permanently unlocks its effect
  on the journal's Atmospheres page; the object is the charming
  switch, never the fragile custodian. Refunding it can never strand
  the weather.
- Creature attractors with visible behavior — the most-loved GG
  category; first batch priority.
- Playable objects: ball, stackable stones, snowballs, kite.
- Water-and-growth reagents: pieces that visibly feed adjacent water,
  waterable plants with growth stages, stackable trees.
- Spatial utility: in-world display storage (§22), signs, teleport
  tiles (§19).
- **Gambling verbs**: reroll station (mutates size/appearance, no
  undo — also the variant system's entry), wager bowl, mystery
  bottle. Cozy stakes; every dud is itself a "Well Curiosities"
  collectible — the floor of any gamble is a journal tick.
- **Secrets policy [v3 default: yes]:** each keepsake batch ships 2–3
  interactions deliberately undocumented. Community discovery is
  content; the coin-on-the-creature legend proved it.

## 16. Clothing — the keeper's story [locked]

Garments never enter Vision pools. They arrive only from legible
moments: journal pages, practice milestones, rare world events, set
completions, seasons. The wardrobe is a biography — and becomes
socially legible the day world-visiting ships.

## 17. The journal — goals at a glance [locked + v3]

- Per-domain chapters: creatures, trees, clouds, pieces, keepsakes,
  curiosities.
- **Currents page** [v3]: which activities feed which domain, and
  what each domain's pool holds — silhouettes included. The
  steering epiphany, printed.
- **Atmospheres page** [v3]: every discovered world-mood effect as a
  permanent toggle.
- **Pattern Book pages** [v3]: discovered pieces, re-orderable (§11).
- Silhouettes keep the next goal ~15 minutes away, always.
- Completed sets mint a placeable memento — trophies live in the
  world, not menus.

## 18. Onboarding [locked — see NEW_PLAYER_FLOW.md]

The authored first session teaches the whole loop by doing it once:
create the keeper (full-screen, world unseen) → arrive through the
portal before the world exists → choose the first land, which rises to
catch you → place the well → tend the pine → claim the accelerated first
Vision → place it → fish in the surrounding ocean.
Closing lesson, in-world and wordless where possible: **what I build
creates what I can do.** Saved as a resumable state machine; required
pieces can never be lost.

## 19. World structure & the long arc [locked]

- **Traversal as reward:** stepping stones, paths, a rowboat; later
  **teleport tiles** (placeable, cooldown — never inventory).
- **Districts:** a second well is a major earnable milestone founding
  a new district; well count grows with world size so claim walks stay
  constant forever. Placement is a real spatial decision.
- **Landmarks:** horizon silhouettes visible from the first session;
  multi-hundred-hour goals that each unlock a domain module when
  reclaimed. `land_fragment` remains their macro currency.
- Elevation, stacking, and composition depth continue to grow
  (stackable trees, taller builds) — verticality is beloved.

## 20. The social horizon [explicitly later]

NPC visitors who use what you built (benches, stalls, swings) and
leave gifts; houses and gentle quests; visiting other keepers'
worlds — where wardrobes, wells, and mementos are already legible
biographies; trading, if ever, designed after single-player balance
is proven. Wisps settling on seats (Rest mode) is the near-term
foreshadowing of all of it.

## 21. The content machine & the public roadmap [v3]

- **Module template** per new domain (activity, tiles, anchor,
  chapter, keepsakes) — the repeatable expansion unit.
- **Variant multiplier:** colorways/materials via the reroll station
  and `material_styles`, turning every authored batch into 3–4× the
  collectibles.
- **Seasonal passes of gentle content** (no FOMO: seasonal pieces
  return yearly; nothing is ever missable-forever).
- **The roadmap is a feature** [research Part 6]: a visible
  "coming seasons" surface from launch. GG's abandonment is its
  deepest community wound; cadence visibly promised is trust.

## 22. Presentation & delight systems [v3]

- **Audio identity:** per-domain gentle themes + Rest-mode layer;
  loop lengths that defeat the "one song" complaint; ASMR-grade
  one-shots for wisp, meter step, bank, claim, place, refund, coin
  crack. Sound is a core product, not polish.
- **Photo mode** with postcard framing — screenshot culture is the
  genre's marketing engine.
- **Display & organization line:** shelving, labeled crates, coin
  stands, museum plinths — organization as *optional* play for those
  who love it, decoration for everyone else.
- **Creative achievements:** first composed scene, first vertical
  build, a shore with three water features — reward making, never
  hours idled.

## 23. QoL & accessibility commitments [v3]

Rebindable inputs (actions already named; needs UI) · controller
parity forever (shipped pillar) · toggles for motion blur, bloom,
particle density, camera sway · generous zoom and free rotation ·
batch refund offers · nameable, plentiful save slots · never wipe or
regress a save · performance budgets held at 10K-tile worlds (already
benchmarked).

## 24. Tuning targets & watchpoints

- First Vision ≤ 10 min (onboarding fast-track: 3 tends) [shipped].
- Early cadence 5–8 min/Vision; late 20–30 with convergence tools
  compensating.
- Wild ~1/8 · Keepsake ~1/10 · refund meter 3 · far-seeking at 80%
  [v3 default] · shrine bias strengths — the convergence watchpoint:
  if completion stalls in playtests, strengthen visible tools, never
  add hidden weighting.
- Tree rest from the rotation target (~8 trees for continuous
  cycling); speed stack +12%/Vision; insurance taper by owned tiles.
- Rest-mode trickle: small enough that active play always wins;
  large enough that returning feels greeted.

## 25. Decisions log

**Locked (shipped in v2):** typed domains & majority steering · well
cap 3 + speed stacks · 2+1 & Wild Visions · land insurance · honest
randomness (no hidden pity) · refund meter → domain coins · shrine
focus · level-free activities · milestone rewards · loss-nothing saves
& migration · anti-density heartbeat · offline tree recovery ·
authored onboarding with land choice.

**Adopted in v3 [Luka may veto any]:**
1. Mastery Arc is the official progression spine (§8).
2. Anti-shrine "Forget" mode (§10).
3. Far-seeking coins at a printed 80% (§9).
4. Pattern Book, per-save, with New World+ toggle (§11).
5. Duplicator + Vendor as Authorship keepsakes (§11).
6. Rest mode in near-term scope (§12).
7. Loss-proof atmosphere effects + Atmospheres page (§15, §17).
8. Keepsakes-as-reagents rule + undocumented-secrets policy (§15).
9. Public content roadmap as a launch feature (§21).
10. QoL/accessibility commitment list (§23).

**Open:** none blocking. Numbers in §24 tune in playtests.

## 26. Build order from here

1. **Mastery Arc systems:** anti-shrine mode → far-seeking coin rule →
   Pattern Book (data + journal UI) → milestone gating + taught-at-
   unlock prompts.
2. **Legibility set:** Currents page, Atmospheres page, well-carving
   far-seeking display.
3. **Rest mode** (small system, large audience).
4. **Keepsake batch 1** as reagents — attractors first, reroll station
   (variants), duplicator, vendor; 2–3 secret interactions.
5. **QoL pass:** batch refunds, rebinding UI, accessibility toggles,
   nameable saves.
6. **Presentation pass:** wisp/well VFX from ASSET_QUEUE, audio
   identity, photo mode.
7. **Display line + creative achievements**, then the next domain
   module (Mining) through the content machine.
