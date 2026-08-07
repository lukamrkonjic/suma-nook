# Prompt: Analyze Suma — a cozy world-unfolding game

You are a senior game-design analyst. Below is the complete design brief for
**Suma**, a cozy 3D world-building game currently in solo development. Read
it fully, then perform the analysis requested at the end. Be direct and
critical; the designer wants real findings, not encouragement.

---

## The vision in one paragraph

Suma is a quiet game about a small person tending an unfolding world.
Permanent, procedurally generated pockets of nature — **Nooks** — arrive one
choice at a time, fall into place tile by tile, and become yours: you clear
what resists, plant what grows, build what you imagine, and occasionally the
ground gives something back. There is no failure, no timer, no visible quest
list, and no economy treadmill. **Creative expression is the purpose;
everything else serves it.** The reference feeling is a muted, earthy,
painterly diorama — mellow sage greens, dusty pines, blush-cream skies —
somewhere between a hand-painted pixel landscape and a low-poly clay island.

## Design pillars (locked — evaluate against these, not around them)

1. **The world grows as connected chunk-Nooks**, revealed via a signature
   falling-tile wave animation. World growth is the spine of progression.
2. **Only nature generates. All civilization is player-placed.** The
   generator never places a bench, lantern, or house — arrivals are wild.
3. **Trees and stones are terrain-with-resistance, not an economy.** You
   chop, crack, and pry them because they are in the way of your idea —
   clearing must feel inherently pleasant with zero rewards attached.
4. **Discovery is buried, never requested.** Treasures hidden at generation
   time, one-time transformation "Firsts," one dormant mystery per Nook,
   keepsake moments — none of them ever show a marker, bar, or request
   before they happen.
5. **Progressive breadth, unlimited depth.** Unlocks gate *kinds* of things,
   never quantities. Anything unlocked is unlimited forever. Saplings are
   free and infinite from the start.
6. **The only 1-of-3 choice in the game happens at Nook seeds.** Placements
   are never gacha; expansion is the ritual moment of chance.

## The progression loop (as shipped)

**Opening.** A new game asks exactly one question: *"Choose where the world
begins"* — three seed cards (biome + density + mood), a limited reroll, and
a Surprise Me option. The chosen card generates the first 8×8 Nook, which
reveals via the falling-tile wave. The player spawns in it. No tutorial
lesson, no guided placement.

**The frontier rhythm.** After modest activity in the newest Nook (a handful
of placements, clearings, or plantings — minutes, not completion), the next
offer quietly becomes available: a small sprout icon in a corner, and an
entry in the Atlas. Opening it presents three new seed cards for the next
chunk on the frontier. Biomes drift rather than checkerboard: neighboring
biomes multiply their own odds. Nooks are permanent once revealed.

**Inside a Nook.**
- *Clearing:* trees chop in 3–5 deliberate clicks (rising-pitch feedback,
  hit-pause), leaving a pryable stump; stones crack in 2–4; stumps pry in 2.
  Cleared means gone — real absence, cleaner ground, changed light.
  Clearing pays small biome tokens (spent on optional reward boxes) but the
  design intent is that the act itself is the reward.
- *Planting:* placing a young tree from the build bag (unlimited) makes it a
  living sapling that grows through three stages in real time (20–45 min per
  stage, continuing offline). Planting is giving back, not spending.
- *Building:* the full placement sandbox — tiles, structures, stacking,
  elevation, undo — free and instant. Fractional-height terrain tiles
  (quarter/half blocks) let players sculpt gentle rises and terraces by
  hand, and the generator uses the same vocabulary for knolls and mountains.
- *Terrain relief:* generation produces knolls (quarter rims, half cores)
  and, in rocky biomes, occasional two-layer mountain shoulders.

**The discovery layer (all invisible until they fire).**
- *Buried treasures:* rolled at generation time into specific trees, stones,
  and stumps; denser seed cards roll richer tables. Clearing the host makes
  the find tumble out. Deterministic — can't be farmed or re-rolled.
- *Firsts:* one-time transformation triggers. First water brought to a dry
  Nook, first path laid, first planted tree reaching maturity, first named
  Nook, two Nooks touching — each fires once, writes a short journal line,
  and may unlock a new placeable family.
- *Dormant mysteries:* most Nooks generate one visibly odd, non-interactive
  thing (an overgrown arch, a still stone, a sealed hollow). It wakes from
  accumulated nearby life — placements, plantings, matured trees, the
  player simply spending time there — but the wake is deferred to the
  *start of the next session*: you come back and it has changed. No bar, no
  prompt, ever.
- *Keepsakes:* witnessed moments (ten saplings planted, warm lantern light
  at night in a Nook) mint a placeable memento and a journal line. Pure
  output; they gate nothing.

**Memory surfaces.** A single Atlas panel holds the world map, the named
Nook registry (naming a Nook is a small ritual), and the journal — a
reverse-chronological feed of everything that has fired. There is
deliberately no forward-looking list of what a Nook still hides.

**HUD philosophy.** The resting screen is the world plus at most one quiet
icon. The token wallet appears for four seconds after a payout, then fades
out. Prompts are contextual. No persistent bars, minimaps, or quest chrome.

## What was deliberately removed

An earlier build had: a 9-tile authored starter island, a guided
place-a-tree/chop-it tutorial, ferry deliveries on a timer, XP-style hobby
progression (fishing/woodcutting levels), materials crafting, combat and
hostile landmarks (already disabled), and regrowing harvest nodes. All of
this was cut or demoted to test-only flows in favor of the loop above.
Fishing still exists as a calm activity (catch and release, journal record).

## Aesthetic direction

Painterly-pixel presentation over real 3D: a fullscreen pass posterizes
value/saturation into painted bands with subtle cavity/crest relief cues —
outline-free, never a checkerboard filter. One authored palette file drives
every material, light, UI surface, and effect through semantic tokens; the
active scheme ("Hearthfield Haze") is muted sage greens, dusty blue-green
pine shadows, warm grey stone, clay browns, and a blush-cream sky. Gold,
coral, and pink are reserved for small focal moments (fire, flowers,
rewards, UI focus).

## Current state (honest)

Playable end to end: seeded opening → reveal → clear/plant/build → frontier
offers → treasures/Firsts/dormants/keepsakes → Atlas/journal, with save/
reload and controller support. Content is thin by design so systems could be
proven first: 3 biomes, 5 landform stamps, 4 moods, ~10 Firsts, 3 dormants,
3 keepsake moments, one tree growth line. Feel polish exists for reveal and
clearing; treasure-unfold and dormant-wake animations are placeholder-level.
Solo developer, Godot 4, no monetization planned.

---

## Your analysis tasks

1. **Loop integrity.** Trace the minute-to-minute, session-to-session, and
   week-to-week loops as described. Where does motivation thin out first?
   Identify the weakest link in the chain *given the pillars* (e.g. you may
   not propose visible quests — pillar 4).
2. **The clearing bet.** Pillar 3 bets the entire mid-game on clearing and
   planting feeling intrinsically good with near-zero extrinsic reward. Under
   what conditions does that bet fail, and what feel/feedback investments
   (not rewards) most reduce that risk?
3. **Frontier pacing.** Offers unlock after ~6 activity events in the newest
   Nook. Analyze this rhythm for both binge players and 15-minutes-a-day
   players. Does permanence + drift create long-term spatial interest, or
   sprawl fatigue? Suggest tunings, not new systems.
4. **Discovery density.** With the shipped content counts, estimate how many
   hours until a player has "seen the shape of everything" and only quantity
   remains. Which discovery system gives the most retention per authored
   item, and where should the next 20 hours of content authoring go?
5. **The dormant mystery.** Next-session deferred wakes are the most novel
   mechanic here. Steelman it, then attack it: what fraction of players
   never notice a wake happened, and what minimal presentation (no bars, no
   prompts) makes wakes land?
6. **Comparables.** Position Suma against Townscaper, Tiny Glade, Animal
   Crossing, Cozy Grove, and Garden Galaxy: what does each do that Suma's
   pillars forbid, and what gap does Suma actually own? Is "the only gacha
   is land" a marketable identity?
7. **First 20 minutes.** Critique the opening as described (one question,
   reveal, no tutorial) for a player who has never seen the game. What is
   the single highest-risk confusion, and the lightest-touch fix consistent
   with the no-chrome HUD philosophy?
8. **Structural risks.** Rank the top five design risks overall, each with
   the cheapest experiment (playtest question, telemetry probe, or paper
   test) that would falsify or confirm it.

Format: organized by task number, concrete over general, referencing the
pillars by number when a recommendation is constrained by them. Where you
speculate, label it. End with the three changes you would make first if you
owned this game tomorrow — each must respect all six pillars.
