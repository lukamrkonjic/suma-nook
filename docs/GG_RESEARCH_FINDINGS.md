# Garden Galaxy research findings → Suma proposals

Status: research synthesis, decisions pending  
Sources: 2 first-play videos, 1 critical video review, 1 advanced-tips
video (transcribed), ~40 negative Steam reviews, ~200 positive Steam
reviews (playtime-weighted: 300 h+ superfans read closest).  
Companions: `docs/PROGRESSION_DESIGN.md` (current v2 systems),
`docs/NEW_PLAYER_FLOW.md` (authored first session),
`docs/GG_SPECIAL_ITEM_INSPIRATION.md` (clean-room item notes).

Clean-room note: findings describe observed *player reactions and
design functions*, never assets or copy to reproduce. Every Suma
proposal uses original mechanics, names, and tuning.

---

## Part 1 — Why people give this genre hundreds of hours

### F1. The game is a nervous-system regulator first, a game second
The single loudest positive theme, across every playtime bracket:
players use it to down-regulate. Recurring language: stops intrusive
thoughts, eases anxiety attacks, grief, "brain feel good," stimming,
"my smartwatch thinks I'm asleep while I play." Several explicitly
neurodivergent players call it ideal for ADHD/autism.
**What produces this:** no failure states, no timers, no threats, no
dialogue ("no people and words" is praised), soft plink/plop sound
design, one calm music loop, small repeatable actions with guaranteed
tiny payoffs.
**Suma implication:** this quality is sacred. Every future system must
pass a "can this stress anyone?" check — no expiry, no FOMO, no loud
failure, no forced reading. Sound polish (wisp chimes, claim plinks,
placement thuds) is not decoration; it is the core product. Music
needs *more variety than GG* (its single loop is the most-repeated
audio complaint) while staying gentle.

### F2. Three dopamine cadences, not one
The loop players describe lovingly is *short*: click → coin → pot →
surprise, every few seconds. Long-form satisfaction comes from set
completion; medium-form from unlocking control tools. GG's cadences:
~5 seconds (coin), ~minutes (item), ~hours (set).
**Suma mapping:** per-action (wisp flight + journal ticks), per-vision
(the 3-card ritual), per-milestone (garments, tools, keepsakes). The
risk in our design: the short cadence is currently *only* wisp visuals.
Every activity action needs a felt micro-payoff — sound, sparkle, the
meter visibly stepping — or the loop reads slower than GG's.

### F3. Second-monitor / ambient play is half the audience
Enormous theme: podcast + game, TV + game, work + game, "check every
few minutes," pomodoro companion. Many positive reviews describe
*structuring work sessions around it*. GG supports this accidentally
(visitors accumulate while unattended).
**Tension:** Suma is a character-action game; it cannot be backgrounded
the same way. This is the biggest structural mismatch between our
design and half of GG's audience.
**Proposal — the Rest mode bridge (see P2):** make sitting the keeper
down the sanctioned ambient state. The world keeps living; small
things accumulate; returning is a warm ritual. Ambient play becomes
*diegetic* instead of impossible.

### F4. The real progression is progression-of-control
This is the central insight of the entire research set. Read the
superfan reviews (300 h, 1,000 h) and the tips video together: the
arc every long-term player describes is **from gambling victim to
randomness engineer**.

- Early: pure gacha, delight in surprise.
- Mid: piggy banks (currency targeting), shrine/anti-shrine
  (pool shaping).
- Late: "by blocking 29 of 30 items you always get the one you want,"
  duplication bags on altars for near-guaranteed draws, vending
  machines for deterministic purchases — players proudly describe
  having "essentially forced creative mode."

GG never *designed* this arc — players assembled it from parts, and
the ones who found it stayed for hundreds of hours; the ones who
didn't refunded ("no control, just clutter"). The negative reviews
and the superfan reviews describe the *same game* separated only by
whether the player discovered the control tools.
**Suma implication:** design the arc on purpose. See P1 — this is the
recommended progression rework.

### F5. Two creative temperaments must both be served
Positive reviews split cleanly:
- **Flow players** *praise* randomness: "you design around unexpected
  items," "go with the flow," "makes it more creative."
- **Planner players** tolerate randomness only until they have a
  vision, then need control ("I have an idea and the game won't give
  me the item" is the top negative).
GG serves flow players at hour 1 and planners only after they
reverse-engineer the tools.
**Suma implication:** the honest-randomness base loop serves flow
players; the earned control tools serve planners. Both must be
first-class and *taught*, not discovered by accident (F4).

### F6. Organization is joy for some, tax for others
Many positives call sorting/organizing the best part ("the best thing
is organizing the coins"). The same mechanic is the #1 negative
("hoarding stress," "storage hell," "20 boxes off to the side").
**Split:** organization must be *optional play*, never *required
overhead*. Suma's Build Library already removes the tax. What we lose
is the joy — GG players build sorting stations, labeled crates, coin
displays as expressions of care.
**Proposal (P6):** cosmetic organization content — display shelving,
labeled crates, coin/keepsake display stands — so organizers can build
their sorting worlds as *decoration*, while the library keeps everyone
else friction-free.

### F7. Charm compounds through item×item interactions
The moments quoted with the most delight are combinatorial: fish
statue spits water → waters plant → plant grows; mushrooms perched on
a frog; trees stacking taller; visitors using swings and ordering
sandwiches; watering cans; coins placed on a creature attracting more
creatures (a *community-discovered* secret). One review explicitly
asks for "secret interactions between items to discover."
**Suma implication (P5):** keepsakes and structures should be designed
as *reagents*, not props — small verbs that react to each other, with
a few genuinely undocumented combinations left for the community to
find. Our support-slot system already enables perching/stacking
cheaply.

### F8. Watching creatures/visitors enjoy the world is the emotional glue
"Lost my mind watching the visitors interact with objects." Animal
items ("items that summon animals!") are the most-loved category.
People form attachment through *observed little lives*, not stats.
**Suma implication:** creature/attractor content deserves priority in
the keepsake batches; wisps settling on benches (Rest mode, P2) is the
near-term version; NPC visitors remain the long-term payoff.

### F9. Completion is a real endgame — and it must converge
Most positive completionists finish sets in 15–70 h and describe set
completion as the height of satisfaction ("the shiny copper book").
The last-items grind is the most-cited pain on *both* sides ("22 h and
still missing a few," "1 h for one item," "the last achievement 💀").
**Suma implication:** far-seeking coins (P3) + shrine make completion
a designed convergence, not an asymptote. Set completion should mint a
physical trophy (already in design) *and* feed the control arc (P1).

### F10. Attachment demands save-respect and multiplicity
Players get emotionally attached to worlds ("I get attached," demo
save deletion caused genuine anger, "wish more than 3 saves," "name my
save slots," "use my unlocked items in a new save so saves are
layouts, not restarts").
**Suma implication:** never destroy progress (already policy);
long-term: multiple islands/districts per save; consider profile-level
persistence of *discoveries* (the Pattern Book, P3, could carry across
worlds — decision needed, see Part 4).

### F11. Content hunger is bottomless and monetizable
"I want 1,000 theme packs," "would pay for DLC," seasonal items loved,
color variants loved. GG's abandonment (no updates) flips fans to
grief — several positive reviews downgrade sentiment purely because
updates stopped.
**Suma implication:** the domain-module template (activity + tiles +
anchor + journal chapter + keepsake set) is the correct long-term
content machine; variants multiply each batch; a visible cadence of
additions is itself a retention feature.

### F12. Small frictions repeatedly named (QoL ledger)
From both polarities, deduplicated, with Suma status:

| Friction (GG) | Suma status / proposal |
|---|---|
| Accidental sell, no undo ("sold my coin bowl… 12 piggy banks trying to get it back") | Placement undo exists; refunds are deliberate hold-interactions; keepsake effects must be loss-proof (P4) |
| Effects-as-items lost = stuck weather | P4: effects become permanent journal unlocks; object is just the switch |
| RSI from clicking; "toggle grab" request | Character performs actions; auto-repeat loops; controller-complete ✓ |
| Storage stack limits, one-at-a-time extraction, "which box is this in?" | Library is menu-based ✓; add batch refund ("offer all dupes of a kind") |
| Multi-select / group move | Future placement QoL; noted |
| Camera: 4-step rotation only, zoom-out limit, motion blur eyestrain | Free camera ✓; add accessibility toggles for blur/bloom; generous zoom |
| Non-rebindable controls | Add key/button rebinding UI (InputMap actions already named per `docs/CONTROLLER_SUPPORT.md`, so this is UI work, not plumbing) |
| Music repetition | Larger gentle soundtrack; per-biome ambience |
| Save slots: few, unnamed, demo wiped | Respect saves absolutely; nameable slots cheap; never wipe |
| Visitors hard to find at scale ("scroll that counts them") | Events must ping softly / route via calling stones; anti-density heartbeat already concentrates via attractors |
| Performance at big worlds (GG lags, heats laptops) | Perf work already a pillar ✓ (10K-tile benchmarks) |
| Waiting for spawns with nothing to do | Activities always available ✓ — income is player-initiated, never spawn-gated |
| Achievements = time played, not creativity | P7: milestone/achievement design rewards *making*, not idling |

---

## Part 2 — What Suma v2 already answers (validation)

| GG failure (top negatives) | Suma v2 answer |
|---|---|
| Tile starvation ("I just want floor") | Land-insurance slot in early reveals; land targetable via shrine/coins; activities never spawn-gated |
| Clutter-hoarding anxiety (no inventory) | Build Library: unplaced pieces live in a clean menu — the #1 GG stressor is structurally absent |
| Forced waiting (income = visitor spawns) | Income = chosen activity, any time |
| Clicking RSI | Character + auto-repeat + controller |
| Recycle returns the junk you just recycled | Refunds feed a *meter toward a guaranteed draw*, never a re-roll of the same slot |
| Creativity punished (decorating reduced spawns; hidden radii) | Anti-density rule: frequency is global; placement adds *kinds*, never subtracts; radii must be shown |
| No goals ("felt pointless") | Milestones, journal ladder, authored onboarding |
| Effects/QoL locked inside RNG items | P4 below |
| Abandonment grief | Module template = sustainable cadence |

The one place the earlier "physicalize everything" instinct was wrong:
**verbs physical, storage abstract.** GG proves both halves — its
physical pot/converters are beloved; its physical storage is hated.
Suma's split (diegetic well/shrine + menu library) is the correct
hybrid and is now a named principle.

---

## Part 3 — Proposals

### P1. The Mastery Arc — the recommended progression rework
Reframe Suma's long-game as the *designed* version of F4: progression
of control over randomness. The content players collect is
decorations; the thing that actually progresses is **how much say they
have in the draw**. Sequence the control tools as milestone rewards so
the arc is paced, taught, and earned:

| Stage | Player experience | Tools unlocked (via milestones) |
|---|---|---|
| 1. Wonder (first hours) | Pure honest visions; land insurance keeps room growing | — |
| 2. Steering | "I choose what to do, so I choose what I lean toward" | Domain meters understood (taught by onboarding + Currents journal page) |
| 3. Shaping | First deliberate targeting | **Shrine** (bias toward), **refund coins** (guaranteed domain draw) |
| 4. Pruning | Removing what they're done with | **Anti-shrine mode**: a set piece removes itself/family from pools ("the well forgets") |
| 5. Convergence | Finishing sets reliably | **Far-seeking coins**: a mastered domain's coin offers only undiscovered pieces — a printed rule, not hidden math |
| 6. Authorship | "I build exactly what I envision" | **Pattern Book**: any journal-discovered piece re-orderable for Inspiration; **Duplicator** keepsake (copy a held piece); **Vendor** keepsake (rotating deterministic stock) |

Stage 6 *is* the earned creative mode that a dozen GG reviews beg for
("creative mode with only items you've collected") — reached through
play, so it never devalues discovery. Rule of the arc:
**randomness governs discovery forever; control governs re-acquisition
increasingly.** First-time finds always come from visions (the gacha
thrill is protected); copies and completions become progressively
deterministic.

This is not a replacement of v2 — it is v2's missing spine. The
systems mostly exist (shrine, coins); the rework is *sequencing them
as the visible growth axis* and adding stages 4–6.

### P2. Rest mode — the ambient bridge
When the keeper sits (bench, hammock, blanket — Drift objects), the
game enters a sanctioned ambient state:
- Camera drifts gently; UI fades; the world keeps living (creatures,
  weather, wisps settling on benches beside the keeper).
- A soft Drift trickle accrues (visibly small, capped — never the
  optimal strategy, per the anti-density pillar).
- Events that arrive (crate wash-ups, creature visits) queue politely
  and *persist* — returning after an hour finds gifts, never losses.
- One key/click stands the keeper up; a small "while you rested"
  moment (wisps greet you) makes the return a ritual.
This gives the second-monitor half of the audience (F3) a diegetic
home inside a character game, and it makes benches — Drift's whole
identity — mechanically real.

### P3. Discovered once, yours forever (Pattern Book + far-seeking)
- **Pattern Book:** a journal surface where any discovered piece can
  be re-ordered directly for Inspiration (cost scaled by rarity).
  Discovery stays random; re-acquisition becomes a plan. Answers
  "I want ten pines," "let me buy what I've already unlocked," and
  most creative-mode demand.
- **Far-seeking coins:** when a domain's collection passes a printed
  threshold (e.g., 80 %), its refund coin upgrades: draws offer only
  unowned pieces. Stated on the well carvings — a legible rule, honest
  by our pillar, and the guaranteed end of last-item hell (F9).

### P4. Loss-proof effects
Any keepsake that changes world state (weather, sky, time, ambience)
registers its effect as a **permanent journal unlock on discovery**.
The placeable object is the charming diegetic switch, but refunding,
storing, or losing it never removes the *capability* (toggle remains
available via the journal's Atmospheres page). Direct answer to GG's
"sold my umbrella, stuck with rain forever."

### P5. Keepsakes as reagents (combinatorial charm)
Design rule for every keepsake batch: each item should *do* one small
verb and *react* to at least one other item. Seed list from observed
delights (original implementations): water-mover pieces that visibly
feed adjacent water tiles; waterable plants with growth stages;
stackable trees (taller composites); perch points on creatures and
statues (support slots ✓); attractors whose effect strengthens when
"fed" a matching piece (the community-discovered coin-on-creature
trick, made intentional but undocumented). Leave 2–3 interactions per
batch out of all documentation — community discovery is content (F7).

### P6. Organization as optional play
Ship a small line of *display* structures: open shelving, labeled
crates, coin stands, museum plinths, trophy niches. They interact with
the library (choose a piece to exhibit) but never gate it. Organizers
get their beloved sorting-station gameplay as decoration; everyone
else ignores it at zero cost (F6).

### P7. Goals that honor making, not idling
GG achievements reward hours; a reviewer asked for creativity instead.
Suma milestone/achievement design: first composed scene (N pieces of
one family within a radius), first full-vertical build, first shore
with 3+ water features, photograph-mode firsts, set-completion
keepsakes displayed. Pair with an in-game **photo mode** — screenshot
culture is how GG marketing sustains itself (community screenshots
sold multiple reviewers).

### P8. Audio/visual regulation polish (the F1 budget)
- Distinct gentle themes per domain/biome + a quiet dynamic layer when
  Rest mode is active; loop lengths long enough to avoid the "one
  song" complaint.
- ASMR-grade one-shots: wisp release, meter step, vision chime, claim
  plink, placement thud, refund splash.
- Accessibility toggles: motion blur, bloom, particle density, camera
  sway (each cited as eyestrain sources in reviews).

### P9. Save & world multiplicity stance
- Never wipe or force-restart (absolute).
- Nameable save slots; more than three.
- Districts/multiple islands per save (already on the long arc) serve
  the "new world, keep attachment" desire.
- **Open decision:** does the Pattern Book persist per-save or
  per-profile (new worlds start with your discovered patterns
  purchasable)? Per-profile matches "saves as layouts, not restarts"
  (F10) but weakens fresh-start discovery. Recommend: per-save by
  default, with a New World+ toggle at world creation.

---

## Part 4 — Total-rework options considered

**Option A — status quo v2 + Mastery Arc spine (RECOMMENDED).**
Keeps every locked decision (honest randomness, well cap, refund
meter, shrine, milestones) and adds stages 4–6 tools + Rest mode +
Pattern Book. Rationale: research overwhelmingly *validates* v2's
structure; the gaps are the control endgame, the ambient bridge, and
legibility — all additive.

**Option B — ambient-first rework.** Recenter the game on the
terrarium: the world generates everything while watched; the keeper is
optional garnish. Rejected: abandons the character-centric pillar that
differentiates Suma, and the active-loop half of the audience; Rest
mode (P2) captures the value at 5 % of the cost.

**Option C — deterministic-first rework.** Shop/catalog progression
with gacha as garnish (the "creative mode" petitioners taken
literally). Rejected: every long-hour reviewer's joy traces to
surprise + earned control, not to shopping; determinism is the
*destination* of the arc, not the road.

**Option D — coin-physicalization rework.** Re-introduce physical
currencies (GG's most-imitated surface). Rejected previously and
re-confirmed by this research: physical storage/currency handling is
GG's largest documented stressor; our wisps + carvings + coins-at-the-
well keep the charm without the clutter tax.

---

## Part 5 — Priority order

1. **Mastery Arc formalization** (P1): sequence existing tools into
   milestones; implement anti-shrine, far-seeking coins, Pattern Book.
2. **Legibility set:** Currents journal page; Atmospheres page (P4);
   well carvings display far-seeking state.
3. **Rest mode** (P2) — small system, huge audience unlock.
4. **Keepsake batch 1 as reagents** (P5) + creature attractors first
   (F8).
5. **QoL ledger items** (F12): batch refund, accessibility toggles,
   nameable saves, soundtrack expansion.
6. **Display/organization line** (P6), photo mode + creative
   achievements (P7).
7. Content cadence machine (F11): next domain module + variant pass.

## Part 6 — Cross-check vs. aggregated review intelligence (N=99)

An external aggregated report (99 reviews; opportunity 84 / risk 49)
was compared against this synthesis. Verdict: **convergent on every
love/complaint/request theme** — independent confirmation that the
findings above are representative, not cherry-picked. Its genuinely
new contributions:

1. **Positioning inversion — GG's weakest fits are Suma's
   differentiators.** The report defines GG's worst-fit audience as
   players wanting *freeform building, explicit goals, or minimal
   RNG*. Suma's design serves exactly those three (earned Authorship
   stage, milestone goal ladder, Mastery Arc RNG-mitigation) *while
   keeping* GG's best-fit audience (cozy, collectors, constrained
   creativity). Positioning claim available to no GG-like before us:
   "the cozy collection game that respects your plans."
2. **The roadmap is itself a feature.** Beyond making content
   (F11), *publishing* a visible content cadence converts enthusiasm
   into trust — GG's abandonment is its most-cited meta-wound. Suma
   should maintain a public-facing "coming seasons" page from launch.
3. **Teach the advanced tools explicitly.** The report elevates
   unclear-advanced-mechanics to a top-5 developer recommendation,
   reinforcing the Mastery Arc rule: control tools are *taught at
   unlock* (one-sentence diegetic prompts), never left to forums.
4. **Rebindable controls** joined the QoL ledger (F12).

Marketing-language bank validated by the report (for future store
copy): coziest-idle-sandbox framing, background/work-break/bedtime
use cases, collector/achiever appeal, "cute, satisfying, surprisingly
addictive." Suma adds atop these: "your keeper, your island, your
plans — randomness that delights early and obeys you late."

## Decisions needed from Luka

1. Adopt the Mastery Arc as the official progression spine? (P1)
2. Pattern Book: per-save or per-profile persistence? (P9)
3. Far-seeking threshold: percentage-based (printed on carvings) — 80 %?
4. Rest mode in the near-term scope, or after keepsake batch 1?
5. Secret interactions policy: comfortable leaving some mechanics
   undocumented for community discovery? (P5)
