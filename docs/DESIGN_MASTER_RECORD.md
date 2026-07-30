# Suma — design master record

Everything read, found, decided, built, and explored to date. One
document to reload the whole context.

Status: living record, last updated 2026-07-30.  
Current authority: `docs/DISCOVERY_PROGRESSION.md`.
Companions: `docs/PROGRESSION_DESIGN.md` (retired Vision history),
`docs/GG_RESEARCH_FINDINGS.md` (research deep-dive),
`docs/NEW_PLAYER_FLOW.md` (authored first session),
`docs/PROGRESSION_REWORK_PLAN.md` (retired implementation history),
`docs/GG_SPECIAL_ITEM_INSPIRATION.md` (clean-room item notes),
`legacy/progression_v1/` (archived XP/parcel system).

---

# PART A — Where the game stands

**Shipped (progression v3):** exposed land edges let the keeper fish
the unknown for one broad random tile or model. The first catch is
guaranteed real, placeable water. Ponds, trees, and future skill
objects inspect their constructed local biome and draw from the
strongest matching source pool. The built world is therefore both
canvas and gacha steering. Three true spare copies of one exact item
can be offered to the void for a different random item in the same
Build Bag category; one keeper is always protected and partial offers
persist. Ferry gifts use the same single-discovery contract.

**Retired:** Inspiration, wisps, the wishing well, banked Visions,
three-card choices, refund meters/coins, focus shrine, hidden pity,
XP/levels, and the infinite-ocean start. Their reasoning remains below
as history, not as implementation authority.

**Open tuning questions:** cadence and pool weights after playtesting;
how broad individual Build Bag categories should be as the catalog
grows; the first mining object and its local biome pools; later
player-facing explanation of why a local pool won.

---

# PART B — Design journey timeline

1. **Origin.** Luka's pitch: GG-inspired but character-inhabited;
   "Inspiration" earned by OSRS-like activities feeding a wishing
   well; boxes on shores; NPCs later. Wanted brutal critique.
2. **Initial critique found four holes:** (1) one untyped bar = no
   steering; (2) no duplicate/pity economy; (3) placed world didn't
   feed earning (no flywheel); (4) content math vs hundreds of hours.
3. **v1 design doc** written: domains, well ritual, Echo/Motif dupe
   economy, world flywheel, skills spine, keepsake verb budget,
   milestone clothing, journal ladder.
4. **Refinements by Luka:**
   - More randomness wanted → 2+1 stray slot + Wild Visions (~1/8).
   - Trees are decor AND nodes; rest then regrow (later: offline too).
   - External AI critique adjudicated: adopted distributed-reveal
     concerns → but kept walk-to-well as ritual; killed Fresh Eyes;
     killed visible token economies (Echoes/Motifs → replaced);
     kept proactive skilling (rejected one-opportunity-at-a-time).
   - Decisions: well holds 3 Visions max, earning blocks at cap, +speed
     per banked Vision with spirit trail; calling stones → later
     placeable teleport tiles; refund meter (3 → category coin) instead
     of hidden pity ("don't secretly reward too much; dupes are part of
     the game"); GG-style shrine loved → focus shrine; tokens beyond
     Inspiration deferred.
   - Levels phased out entirely, archived for possible revival.
   - Personal first-land pick kept (vs fixed 6-tile start).
5. **New-player flow** authored (portal arrival, staged, resumable),
   then **the phased rework plan**, then **full implementation** (v2)
   with archive `legacy/progression_v1/`, save migration, tests green.
   Screenshots delivered; polish fixes (HUD hidden during creation,
   winter swatch).
6. **Research phase** (Part C): Luka supplied transcripts + reviews in
   waves; findings and proposals doc written; aggregated report
   cross-checked (convergent).
7. **v3 vision** written: whole-game document, Mastery Arc adopted.
8. **Alternatives exploration** (Part G): six ideation rounds testing
   non-Inspiration cores; taste profile converged on GG's typed-coin
   visitor triangle at fountain pace (Part H).

---

# PART C — The research corpus

## C1. Sources
- Basement Broadcast-style **new-player tips video** (pot, coins,
  gumballs, duplicator, banks, shrine/anti-shrine, storage, cauldrons,
  playground/market/food economy, piggy banks).
- **First-play video A** ("so cute" streamer): tutorial beats, joy and
  friction moments live.
- **First-play video B** (idle-focused): base-plate priority, spawner
  strategy, 30-hour progress reality, logistics endgame.
- **Cozy Lotus first-play**: storage relief, trash-desire, return-to-pot
  discoverability failure, anti-shrine desire, overwhelm arc.
- **Higher Plain Games critical review**: recycle RNG returning same
  items, piggy conversion slog, ~100 items shrink fast, 25-coin dump
  waste, AFK rush paradox.
- **Advanced tips video**: duplication-bag-on-altar near-guaranteed
  draws, rainbow farming (coin-on-altar attracts rainbow spirits),
  despawner zoning, food-cart → market-coin → dice → rainbow pipeline,
  gumball determinism, teleport chests, camera arrows, visitor scroll.
- **~40 negative Steam reviews** (0.1–65 h).
- **~200 positive Steam reviews** (0.3–7,874 h; playtime-weighted).
- **Aggregated Player Intelligence Report** (N=99; opportunity 84 /
  risk 49) — fully convergent with own synthesis.

## C2. Complete GG mechanics inventory (observed across all sources)
Pot (typed coin → random item of that set; items sellable back for
coins) · visitor spirits (click → coin; rainbow spirits → rainbow
coins that pull from everything) · coin types per collection set ·
piggy banks (convert generic → themed coins when broken; smashing
beloved) · gambling dice (coin double-or-nothing, can yield rainbow) ·
gumball/vending machines (deterministic purchase, ≤10, rotating
stock) · duplication bag (copy an item; consumed; "most important
item") · altar/shrine (item on it appears MORE) and despawner (item
appears NO MORE — used to "force creative mode") · anti-spawn orbs
(zone visitors away) · storage boxes/chests (stack 99, themed
organization as hobby) · teleport chests (6 colors, camera-follow) ·
camera arrows (waypoints) · coin dish (visitors deposit nearby coins) ·
safe (unlimited coin storage) · playground items (swings/teeter
totters attract + hold visitors) · market stalls + food carts (spirit
orders: assemble sandwich → 4–8 market coins) · cauldrons
(grow/shrink; appearance change; coal dud — itself a collectible) ·
trash pot (destroys; universally warned against) · watering can
(plants grow stages) · fish trap/water baskets (passive water finds) ·
stacking (blocks ×11, trees ×4 grow taller, selective item-on-item,
mushrooms on frogs) · effect items (rain/snow/stars/background/time/
lens; toggle via journal) · animal items (attract tortoise/frog/bird…)
· journal/books (which coin → which items; effects toggles; set
completion books) · visitor-count scroll · duplicate → sell-back loop
· demo save deleted on purchase (rage) · location-permission scare
(dev responded) · no creative mode · abandoned updates (grief).

## C3. Negative review themes (deduplicated, with essence)
1. **Tile/ground starvation** — the #1 complaint verbatim-everywhere:
   "I just want floor"; items pile with nowhere to place.
2. **Clutter-hoarding stress** — no inventory; world becomes a hoard;
   triggers real hoarding anxiety; "battle to fit everything."
3. **RNG blocks intent** — "have an idea, game won't give the item";
   last-items hell (22 h for final pieces); 25-coin dumps of junk.
4. **Recycle feels bad** — sell-backs return the same item; loss of
   value on return.
5. **No creative/sandbox mode** — top requested; several propose
   "creative mode limited to already-discovered items."
6. **Waiting** — income gated on visitor spawns; bored between; AFK
   farming becomes the meta, ruining the chill.
7. **Click/drag RSI** — hands hurt; no toggle-grab; no rebinding.
8. **Storage misery** — 99-stacks, one-at-a-time extraction, box
   archaeology, "which box was it in."
9. **Effects trapped in items** — sell your umbrella, stuck with rain.
10. **Creativity punished** — decorated/elevated terrain reduces
    visitor spawns; effect radii invisible; "punishing creativity."
11. **No goals** — "felt pointless"; wish for missions/inhabitants.
12. **Value/price gripes; small content pool** (~100 items shrink
    fast); **performance at scale**; **abandonment**; **camera
    limits** (4 rotations, zoom, motion-blur eyestrain); **save
    slots** (few, unnamed, demo wipe).

## C4. Positive review themes (deduplicated, with essence)
1. **Nervous-system regulation** — the loudest theme at every playtime:
   anxiety, ADHD, autism, grief, intrusive thoughts, stimming, sleep;
   "brain feel good"; smartwatch-thinks-I'm-asleep.
2. **The tight dopamine triangle** — click visitor → coin → pot →
   surprise → place; described lovingly hundreds of times; "one more
   coin"; drugs-for-ADHD energy; 5-second cadence.
3. **Second-monitor life** — podcasts, work breaks, pomodoro
   companion, bedtime; "check every few minutes."
4. **Collection/completion joy** — sets, journal, books; 15–70 h to
   100 %; "the shiny copper book"; achievement culture.
5. **Organization as hobby** — themed boxes, coin sorting, "the best
   part is organizing" (the same mechanic others hate — split
   audience).
6. **Mastery/engineering pride** — blocking 29/30 items = choose your
   spawn; duplication-bag altars; despawner zoning; "hacking the
   system"; "forced creative mode"; "Big Brain Time."
7. **Combinatorial charm** — fish statue waters plant → plant grows;
   mushrooms perch on frog; trees stack taller; visitors swing, order
   sandwiches; watering; secret discovered tricks (coin on creature →
   more creatures).
8. **Watching little lives** — animal items and visitor behavior are
   the emotional glue; "lost my mind watching them interact."
9. **Constrained creativity praised** — "random items make it MORE
   creative; design around what arrives."
10. **No words, no pressure** — no dialogue, no timers, no failure;
    grandma-to-kids audience span.
11. **Content hunger** — "1,000 theme packs"; would pay DLC; seasonal
    items; color variants; grief at abandonment.
12. **Attachment** — to worlds and saves; demo deletion = heartbreak;
    want more/named saves; New-World-with-unlocks wish.

## C5. Aggregated report (N=99) — convergent + unique adds
Confirms every theme above. Unique adds: **positioning inversion**
(GG's weakest-fit = players wanting freeform building, explicit goals,
minimal RNG — exactly Suma's differentiators); **roadmap-as-feature**
(visible cadence = trust); **teach advanced tools** as top-5 dev rec;
**rebindable controls** to the QoL ledger.

## C6. Playtime-bracket insight
Refunders (<2 h) and superfans (300–7,800 h) describe the *same
mechanics* — the difference is discovering the control tools and the
organization meta. GG's fate was decided by what it failed to teach.

---

# PART D — Findings (condensed F1–F12; full text in GG_RESEARCH_FINDINGS.md)

- **F1 Regulation first.** The genre's core value is calm. Standing
  check: "can this stress anyone?"
- **F2 Three dopamine cadences** — seconds / minutes / hours; every
  feature must feed one.
- **F3 Ambient half.** Second-monitor play is half the audience —
  needs a diegetic answer in a character game.
- **F4 The real progression is progression-of-control** (gambling →
  engineering). GG never designed it; players who found it stayed.
- **F5 Two temperaments** — flow players (love randomness) and
  planners (need earned control). Serve both, teach both.
- **F6 Organization** — joy for some, tax for others → optional play,
  never overhead.
- **F7 Charm compounds combinatorially** — item×item reactions and
  discoverable secrets are content.
- **F8 Little lives are the emotional glue.**
- **F9 Completion must converge** — last-items asymptote is the
  genre's shared wound.
- **F10 Attachment demands save-respect and multiplicity.**
- **F11 Content hunger is bottomless** — module template + variants +
  visible cadence.
- **F12 QoL ledger** — undo, loss-proof effects, batch ops,
  multi-select, camera freedom, eyestrain toggles, rebinding, named
  saves, event findability, performance at scale.

**Key principle learned:** *verbs physical, storage abstract* — GG's
physical pot/converters are beloved; its physical storage is hated.
Suma's well+library split is correct.

---

# PART E — Proposals adopted into v3 (condensed P1–P9)

- **P1 Mastery Arc** (spine): Wonder → Steering → Shaping
  (shrine/coins) → Pruning (anti-shrine) → Convergence (far-seeking
  coins at printed 80 %) → Authorship (Pattern Book, duplicator,
  vendor). Rule: randomness owns discovery forever; control owns
  re-acquisition increasingly. Tools milestone-gated, taught at
  unlock.
- **P2 Rest mode** — sitting = sanctioned ambient state (F3 answer).
- **P3 Discovered-once-yours-forever** — Pattern Book (per-save +
  New World+ toggle) + far-seeking coins.
- **P4 Loss-proof effects** + Atmospheres journal page.
- **P5 Keepsakes as reagents** + 2–3 undocumented secrets per batch.
- **P6 Display/organization furniture line** (optional organization).
- **P7 Creative achievements + photo mode.**
- **P8 Audio identity** (per-domain themes; ASMR one-shots; variety).
- **P9 Save multiplicity stance** (named/many saves; districts; never
  wipe).
Plus: Currents journal page (legibility epiphany engineered), public
roadmap, QoL commitments.

---

# PART F — Decisions log (cumulative)

**Locked (shipped v2):** typed domains, majority-weight steering ·
2+1 + Wild ~1/8 · well cap 3 + speed stacks + earning-block ·
claim-at-well ritual · land insurance · honest randomness (no hidden
pity — explicit Luka call) · refund meter 3 → domain coin · focus
shrine · dupes are legitimate and desirable · levels removed &
archived (revivable; lifetime action counts kept) · milestones replace
unlocks · recipes gate via milestones · ferry delivers gift Visions ·
offline tree recovery · full-screen creation → portal arrival →
first-land choice (Grove Ground / Pale Sand / Fresh Snow) · resumable
staged onboarding · saves migrate forever.

**Adopted v3 (Luka may veto):** Mastery Arc · anti-shrine · far-seeking
at printed 80 % · Pattern Book per-save + New World+ · duplicator +
vendor keepsakes · Rest mode near-term · loss-proof effects ·
reagent keepsakes + secrets policy · public roadmap · QoL list.

**Explicitly rejected:** Fresh Eyes variety tax · visible token
economies (Echo/Motif) · hidden pity/secret weighting · one-global-
opportunity pacing (kills proactive skilling) · reveal-at-site
replacing the well walk · physical coin/storage re-introduction ·
ambient-first, deterministic-first reworks · scoring/judgment
mechanics (stress) · anti-pillars list (survival, colony, chores,
FOMO, monetized RNG…).

**Undecided:** the core-loop question in Part H; material crafting's
long-term fate (currently milestone-gated, works).

---

# PART G — The alternatives exploration (all rounds, all verdicts)

Luka asked for directions ignoring Inspiration entirely. Six rounds:

**Round 1 — five contrasting spines.**
Tide (world washes in) · Grown World (everything grows) ·
**Guests** (visitors gift because of what you built) · Buried World
(uncover pre-existing) · Routes (deterministic trade).  
*Verdict:* "too niche — only Guests feels tied together and could
hold the whole game."

**Round 2 — five GG-close-but-own.**
Waystation Inn (travelers leave homeland bundles at dawn) ·
Little Expeditions (provision wisp-crews; unbox returns; museum) ·
**Postal Island** (pen-pals; parcels; send pressed gifts/photos —
LOVED) · **Sky Harvest** (weather fronts drop sets; placed catchers;
forecast — LOVED) · Bottle Tide (async real-player gift exchange).  
*Verdict:* loves #3+#4; wants 5 more, "utterly beautiful, not overly
complex or witty."

**Round 3 — five poetic-natural.**
Great Migrations · River from Upstream · Heart Tree (graftable,
fruits are the gacha) · Fallen Stars (return stars; constellations
gift) · Season Quilt (anchor seasons).  
*Verdict:* "a bit too crazy, too fantasy — and they break at huge
worlds; GG works because a god-view player drags coins trivially."
→ Scale constraint identified: a walking keeper pays for every meter.

**Round 4 — five grounded + scale-solved.**
Doorstep (all arrives at home) · Fetchers (companions do the walking) ·
Market Day (recurring plaza market) · Waking Path (world wakes around
the player) · Caretakers (district helpers consolidate to porch).  
*Verdict:* "still overcomplex."

**Round 5 — five one-gesture objects.**
Seeds (plant → see what grows) · Morning Tide (beach-walk gathering) ·
Feeder (food out → visitors leave gifts) · Windfall (shake placed
trees) · Swap Basket (leave one, find another).  
*Verdict:* "I hate them — too much micromanaging and too slow."
→ Pace constraint identified: GG is a *fountain* (acts every few
seconds), not a drip.

**Round 6 — five fast/abundant.**
Wisp Rush (spirits around you; token; instant pot) · Sparkle Island
(placed world constantly glints) · Drifting Gifts (presents float by;
wave down) · Coin-per-cast (v2 minus meters; instant pulls) ·
Glinting Ground (items pop out directly, no currency).  
*Verdict:* "I hate them — they don't feel as put together as GG's
visitors you click for coins of different collections."
→ **Structure constraint identified: the sacred triangle.** The typed
coin IS the design: being → one press → **coin of a collection** →
one pot → item *of that collection*. Ideas that replace the typed
currency lose the put-together feeling.

**The learned taste profile (requirements distilled from all
verdicts):**
1. Keep GG's sacred triangle intact — typed coins are non-negotiable.
2. Fountain pace — something to press every few seconds; instant
   pulls; no meters/waits.
3. Zero micromanagement — nothing fed, trained, maintained, or
   scheduled.
4. Grounded, warm, simple — no high fantasy, no witty meta.
5. Character-embodied and scale-proof — beings come to built places /
   typed regions; never scattered across a huge map.
6. Tied together — one metaphor closes earn→spend→place→earn.
7. Broad, not niche — must hold flow + planner + ambient audiences.

---

# PART H — Current candidates: the five triangle skins (awaiting verdict)

All five keep GG's skeleton exactly (beings → press → typed coin →
one pot → instant item of that set), differ only in embodiment;
all bolt onto the existing build (the well is the pot; collections,
shrine, refunds, milestones, journal all carry over):

1. **Gathering Spots** — wisp-visitors drift toward plazas/fountains
   you built; chain-greet crowds there; the spot's materials tint the
   coin types. Building gathering places IS coin strategy; clustering
   solves scale.
2. **Biome Sprites** — visitors visibly typed (mossy/frost/wave);
   they frequent the matching corners of your island; the piggy bank
   is geography.
3. **Butterfly Jar** — colored butterflies drift through; soft
   net-catch; release at the glass jar = that color's pull. Coin =
   butterfly = collection, one visual thread; ACNH's net verb.
4. **Feather Perches** — many bird kinds land on what you build; each
   leaves its feather (= its set's coin); perches you place invite the
   birds you want.
5. **Little Pilgrims** — tiny cloaked travelers row ashore and cross
   your paths; greeting one yields a homeland coin; piers/paths choose
   who comes.

Natural blend candidate: Gathering Spots' clustering + Biome Sprites'
visible typing.

**The decision this sets up:** fold the chosen skin into Suma as
(a) the new core with Inspiration retired, (b) the primary source
with activities as a secondary coin stream, or (c) a hybrid where
activities and visitors both mint the same typed coins. The Mastery
Arc, refunds, shrine, milestones, journal, onboarding, and world
flywheel survive unchanged under any of the three — they are
loop-agnostic.

---

# PART I — Standing intellectual assets

- Positioning: *"the cozy collection game that respects your plans"*
  — GG's rejected audience is Suma's differentiator set, without
  losing GG's core audience.
- Marketing bank: coziest-idle-sandbox framing; background/work-break/
  bedtime use; collector/achiever appeal; "cute, satisfying,
  surprisingly addictive"; screenshot culture via photo mode.
- Content machine: domain module template (activity + tiles + anchor +
  journal chapter + keepsake set) × variant multiplier × seasonal
  returns (never missable-forever) × visible roadmap.
- Engineering assets: data-driven catalog with atomic validation;
  feature-module pattern; save migration policy; controller-complete
  contract; performance benchmarks to 10K tiles; visual capture
  runner; full test suites.

---

# PART J — The discovery era (current authority)

Luka's decisive synthesis was that **fishing the sky/unknown is the
emotionally strongest acquisition fantasy**, while ordinary water,
forests, and future mining must still make physical sense inside the
world the player designs. The discarded infinite-ocean prototype
proved that treating water as background weakened ownership: water
must be the same finite tile the player can discover, place, move,
fish, and eventually manipulate with tools.

The answer is a two-layer acquisition grammar:

1. **The unknown is broad.** Fish from any exposed land edge to receive
   one surprising tile or model from across the game.
2. **The built world is specific.** Use a skill on a pond, tree, or
   future mineral node and its nearby biome shapes the reward pool.

This preserves gacha excitement without another currency ritual. It
also turns decorating into meaningful strategy without making players
manage visitors, meters, machines, schedules, or maintenance chores.

## Locked rules

- New worlds begin as a 3×3 land island with exposed void edges.
- The first void catch is guaranteed `tile_open_water`.
- Water is always a real owned tile, never ambient ocean geometry.
- A discovery is one item, immediately owned before presentation.
- Void pools are deliberately broad; local pools are source- and
  biome-specific with neutral fallbacks.
- Context comes from a bounded neighborhood of tile family, tagged
  biome models, and the skill object's own tags.
- Coherent local biomes beat incidental stray tiles.
- Fishing, woodcutting, and future mining share one generic discovery
  contract rather than bespoke reward code.
- Duplicates are expected.
- Three true spare copies of one exact item may be offered to the
  void. One copy is protected across placed and stored ownership.
- At three, the void returns a different random item from the same
  Build Bag category. Partial offerings persist. Impossible draws
  return the offered copies.
- Ferry gifts are a bonus use of the same discovery system.
- Inspiration, the well, Visions, refund coins, and shrine behavior
  are completely removed rather than hidden behind feature flags.

## Current first-session proof

Create keeper → choose land → arrive on nine matching land tiles →
fish the unknown → reveal and place real water → tend the placed pine
→ receive a biome-shaped discovery → place it → free play.

The proof matters because it demonstrates the whole long-term game in
minutes: wonder, ownership, construction, local steering, and renewed
discovery.

## Extensibility contract

`data/discovery_pools.json` is the content surface. Adding mining,
foraging, bug-catching, or another skill means supplying the physical
skill object and data pools keyed by source plus context; reward
ownership, progress, reveal recovery, category exchange, collection,
and saving remain shared.

Progression save version 3 archives both earlier generations, safely
converts pending promised rewards, retires their currencies, replaces
ritual structures with ordinary decorative counterparts, and rejects
no valid player-built world.
