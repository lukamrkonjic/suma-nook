# Suma progression design

Status: v2 — consolidated after design review; core decisions locked,
tuning numbers open  
Depends on: `data/skills.json`, `data/tiles.json`, `data/parcels.json`,
`data/loot_tables.json`, `data/material_styles.json`, journal
collections, anchors, the wardrobe system.

## Design pillars

1. Progression is tied to the player character, who physically performs
   every activity in the world.
2. The player steers what they earn by choosing what they do — no coin
   dragging, no inventory management.
3. The world the player builds is where earning happens. Placement is
   never punished and density is never the optimal strategy.
4. **Randomness is honest.** No heavy hidden reward-weighting. Dupes
   happen, are visible, and are part of the game — targeting and
   duplicate protection are *player-driven tools in the world* (the
   shrine, the refund meter), not secret math.
5. A slice of rewards change *how you play* (new verbs), and authored
   content is multiplied by a variant system.
6. Inspiration is the only resource for now. Other tokens (trading,
   clothing tokens) are explicitly deferred.

Clean-room note: original terminology, structure, and tuning
throughout. `docs/GG_SPECIAL_ITEM_INSPIRATION.md` is reference-only.

---

## 1. The core loop

```
 do activities  ──►  Inspiration wisps  ──►  well banks a Vision
      ▲               (typed by domain)      (max 3 — then skilling
      │                                       pauses until claimed)
      │                                              │
      │                        player speeds up (+1 per banked Vision,
      │                         spirit trail) and walks to the well
      │                                              ▼
 place tiles/structures  ◄────  keep 1 of 3  ◄──  claim Visions
 (world grows: more nodes,
  more kinds of events)
```

The player fishes, tends trees, watches clouds, opens shore crates.
Each action releases **Inspiration wisps** — colored spirits that fly
to the well on their own. No deposits, no clicks.

## 2. Inspiration domains

Wisps are typed by their source activity, and each domain fills its own
meter, mapped 1:1 onto tile families:

| Domain | Earned by | Rewards lean toward |
|---|---|---|
| Waterside | fishing, shore crates | `waterside` tiles, docks, water life |
| Grove | tending trees | `living_grove` tiles, trees, forest structures |
| Meadow | meadow tending, future bug catching | `home_meadow` tiles, flowers |
| Stone | mining (future) | `stonebound` tiles, rock features |
| Winter | winter activities (future) | `winter` tiles and structures |
| Drift | cloud watching, benches, stargazing | wildcard: curios, keepsakes |

Steering is majority-weight, never exclusivity: grinding the grove
mostly gives forest content, with real chances of anything else — the
surprise is the point.

## 3. Visions — the reward ritual

A full domain meter banks a **Vision** at the well.

- **The well holds at most 3 banked Visions.** At 3, wisps refuse to
  enter and skilling pauses — the current action completes, then nodes
  gently gesture toward the well. The world tells you it's time.
- **Each banked Vision makes the player faster**: +1 stacking movement
  speed with a growing spirit-trail effect (3 stacks = fastest, full
  trail). The fuller the well, the more triumphant and *shorter* the
  walk back feels. The forced trip is the celebration, and walk time
  self-corrects as the world grows.
- Claiming a Vision reveals **three options; the player keeps one.**
  Composition is **2 + 1**: two from the earning domain, one stray from
  the entire catalogue — with a small chance of a rarity from anywhere.
- Roughly 1 Vision in 8 is a **Wild Vision**: all three options fully
  random across every domain. The jackpot pull, and the natural payoff
  of Drift play.
- Early-game insurance: while the world is small, reveals reliably
  include a plain land tile among the three, tapering off as the world
  grows. No separate land currency needed at this stage.

## 4. Duplicates and the refund meter

Dupes are honest outcomes and often *desirable* — building a forest
means wanting many of the same tree. Nothing is silently rerouted.

Unwanted dupes are **refunded at the well**:

- Each domain has a visible **refund meter** on the well itself
  (carvings that fill — not a menu).
- **3 refunds of a category mint that category's coin.** The coin waits
  at the well — no inventory — and the player releases it for a
  **guaranteed draw from that category.**
- Refunds are the deliberate dupe sink; the shrine (below) is the
  deliberate dupe *source*. Between them, duplicates are a system the
  player operates, not a punishment they absorb.

Possible later: other token types (clothing tokens, trading).
Deliberately not designed yet.

## 5. The shrine — player-driven targeting

A placeable **shrine** structure: the player sets one owned item on it,
and draws are visibly biased toward that item and its close family.

- Want ten pine trees for a forest? Shrine a pine tree and grind.
- Chasing the last pieces of a set? Shrine a set member.
- The shrine is spatial, diegetic, and honest — targeting the player
  can see and touch, replacing any hidden pity system.

Late-game completion rests on the shrine plus category coins. This is
the design's main **tuning watchpoint**: the shrine bias and refund
flow must be strong enough that finishing a collection converges in
reasonable time. If late-game stalls in playtests, the lever is
stronger shrine bias — not hidden weighting.

## 6. The world flywheel

Activity opportunities appear **on player-placed content**, so building
expands what can happen — but never rewards density:

- Fishing spots surface on placed `waterside` tiles; crates wash up on
  water-meets-land edges.
- Trees are simultaneously decoration and skilling nodes. Tending puts
  a tree into a visible **resting state** that preserves its silhouette
  (trimmed, budding — never a stump), then it recovers on a timer, in
  real time even while away. Recovery occasionally brings a bonus state
  — a bloom, a nest — feeding journal entries.
- **Anti-density rule:** special opportunities (creature events, rare
  spawns, crates) arrive on a globally paced heartbeat; placed objects
  determine *where* and *what kind*, never *how often*. Ten clustered
  trees and ten scattered trees yield the same income — plant where it
  looks good. Baseline skilling (fish, tend) is always available and
  paced by the well cap, node rest timers, and meter costs.
- **Attractors** bias nearby event kinds: a lantern draws night moths,
  a birdbath draws birds. Decoration becomes habitat.
- **Anchors** (existing) are each domain's hub; skill unlocks upgrade
  them to improve event *quality and variety* in their radius.

Spawns are diegetic and pretty — ripples, a shimmer, a perched bird —
never UI markers cluttering a composed scene.

## 7. Activities — the character spine (levels phased out)

**Decision: XP levels are removed** (archived in
`legacy/progression_v1/` for a possible future revival — see
`docs/PROGRESSION_REWORK_PLAN.md` Phase 3). `data/skills.json` slims to
activity definitions: verb, tool, timing, animation, domain.

- Activities are what the *character* does; collections are what the
  *world* progresses. Character growth is expressed through **tools,
  garments, and new verbs earned at journal milestones** — not level
  numbers.
- Former level unlocks (bench, fence, recipes, anchor upgrades) move to
  journal page completions.
- New verbs still arrive over time — deep-water casting, tree grafting,
  night fishing — gated by milestones, never by XP grind.
- Each future domain ships as a self-similar module: one activity + one
  tile family + one anchor + one journal chapter + one keepsake set.

## 8. Keepsakes — the verb budget

Roughly **1 Vision in 10** offers a Keepsake among its options: an item
that adds an interaction rather than filling space.

- World-mood objects: toggle rain, snow, petals, fog, stars, time of
  day — placeable, no settings menu.
- Creature attractors with visible behavior.
- Playable objects: a ball, stackable stones, snowballs, a kite.
- Spatial utility: storage that lives in the world, signs, and later
  **teleport tiles** (see §11).
- **Gambling verbs**: a reroll station that mutates an item's size or
  appearance with no undo, a wager bowl, a mystery bottle. Cozy stakes,
  and every dud result is itself a collectible ("Well Curiosities"
  journal set) — the floor of any gamble is a journal tick. The reroll
  station doubles as the variant system's entry point, multiplying
  authored content via `data/material_styles.json`.

## 9. Clothing — milestone trophies, never gacha

Garments never appear in Vision pools. They are earned, legibly:
journal page completion, skill milestones, rare world moments,
collection set completion, seasonal events. Every garment has a story —
and reads as an achievement when world-visiting arrives.

## 10. Journal — the visible goal ladder

- Per-domain chapters: creatures, trees tended, clouds seen, items,
  keepsakes, well curiosities.
- Page completion pays a garment, keepsake, or shrine-worthy reward —
  always legible, never raw currency.
- Silhouettes of the next few uncollected things are always visible;
  the player is never more than ~15 minutes from some tick.
- Completed sets can be commemorated with a placeable memento.

## 11. Traversal and the long arc

- **Walk-back rhythm:** the well-cap block plus the stacking speed buff
  makes claim trips frequent, fast, and celebratory. Traversal rewards
  (stepping stones, board paths, a rowboat) let the player shorten
  their own walks by building.
- **Teleport tiles (later):** a placeable teleport tile — not an
  inventory item — for returning across a grown world. Cooldown-based.
  Ships when worlds are big enough to need it.
- **Multiple wells (later):** a second well is a major earnable
  milestone defining a new district. Well count grows with world size,
  keeping walk length roughly constant forever. Placement is a real
  spatial decision.
- **The well evolves** visually with total collection (moss, carvings,
  glow) — the save file's physical progress bar.
- **Landmarks** (existing data family) remain the multi-hundred-hour
  horizon goals, each unlocking a new domain module.

## 12. Onboarding — the first 30 minutes

1. Customize character (wardrobe exists).
2. **Personal start:** the player picks their first tiles from a small
   curated set — around three land styles plus a water edge. The world
   is theirs from minute one, and the pick teaches the keep-1-of-3
   ritual before the first Vision.
3. Guided placement: first tiles, a sapling, the well.
4. First tree tend → wisps visibly fly → first Vision within ~10
   minutes.
5. **The first Vision is rigged:** all three options good, one a
   Keepsake with a verb. The player learns the ceiling immediately.
6. The first fishing spot surfaces on their placed water tile, closing
   the loop: what I place creates what I do.

## 13. Explicitly later

NPCs, houses, quests, market stalls; visiting other players' worlds;
trading and token types beyond Inspiration. The economy stays balanced
single-player-first.

## 14. Open tuning numbers

All hypotheses, to be tuned once pool sizes are known:

- Meter cost per Vision (target: first Vision ≤10 min; early cadence
  5–8 min; late 20–30 min).
- Wild Vision rate (~1 in 8), Keepsake rate (~1 in 10), stray-slot
  rarity chance.
- Refund meter at 3; shrine bias strength (the completion-convergence
  watchpoint from §5).
- Tree rest duration — derive from the rotation target: pick the tree
  count where continuous cycling should begin (~8), multiply by action
  time plus walk time.
- Speed buff per banked Vision (+X% per stack).
- Land-tile insurance taper (reliable early, fading as owned tiles
  grow).
