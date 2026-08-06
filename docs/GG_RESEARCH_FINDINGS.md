# Garden Galaxy research findings → Suma proposals

Status: research synthesis, decisions pending  
Sources: 2 first-play videos, 1 critical video review, 1 advanced-tips
video (transcribed), ~40 negative Steam reviews, ~200 positive Steam
reviews (playtime-weighted: 300 h+ superfans read closest).  
Second sweep (Part 7): Steam **Community discussions** (~279 topics
indexed; the 133-reply master wishlist, the 72-reply roadmap thread and
~25 individual threads read in full), plus off-Steam press and guides.
Reviews deliberately excluded from the second sweep — already covered
above.
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

## Part 7 — Forum & web sweep (second source set)

Method note: **r/GardenGalaxy could not be read.** Reddit blocks our
crawler at the site level (fetch, browser and search all refused), and
routing around a publisher's explicit block wasn't appropriate. The
substitute corpus is the Steam *discussion forums* — a different
population from the reviews already mined in Parts 1–6, and a better
one for this purpose: forum posters are retained players describing
what they wanted *next*, not first-impression verdicts. Off-Steam
sources: Higher Plain Games review (6/10), Eggie's Nest review,
TheGamer beginner guide, TapTap (no review volume), general web.

Everything in Parts 1–6 was **re-confirmed**, nothing contradicted.
What follows is the new or materially sharper material.

### F13. The dev published a roadmap and never shipped it — read it as a validated priority list
The pinned wishlist thread (133 replies) opens with the developer's own
ranked list of most-requested features, several tagged "in development"
in April 2023. Nothing shipped; the game has been silent since. That
list is the most valuable single artifact in this sweep — it is what a
solo dev concluded after reading their whole community:

> water-log slants/stairs next to water · **paint/recolour** · wall
> decoration (shelves, hanging plants, banners) · unique plates per
> coin type · **archways** · mountain/snow set · more animals · galaxy
> set · seasonal sets · volcano/lava set · more tree colour variation ·
> expanded cooking · benches & dining chairs · **sand-drawing tool** ·
> **mouse camera rotation** · bookshelves to display books

Plus, from the 72-reply roadmap thread: alternate ways to earn set
coins, **dedicated coin storage**, more customization, new item
interactions, **collection-screen improvements**, and graphics options
for low-spec PCs.

**Suma implication:** treat this as a pre-validated backlog for the
decoration/tooling axis. The recurring shape across it is *surface
control* — paint, recolour, wall/vertical surfaces, archways, drawing
on ground. Suma's curated-tile pillar (P5 in DESIGN_PILLARS) covers
composition but currently offers no **recolour verb**, which is the
single most-requested customization primitive in this entire corpus and
is cheap in a flat-colour matte art style. Recommend adding a palette/
paint system to the roadmap explicitly.

### F14. Building topology: players want air, bridges, and down
A distinct cluster the review corpus missed, because it only surfaces
once players are hours deep:
- **Blank/"air" tiles** to build bridges, archways and floating islands
  (MooochiCat, Supman, raevnn's "clouds as an item so you can make
  floating islands").
- **Building downward**, not just upward (peaxhtree).
- **Boardwalk tiles that sit over water** (ShakeyBox); water blocks on
  slope blocks; multi-layer waterfalls; "stretch land vertically."
- **Merging/composite pieces**: two tables into one larger piece
  (MechaEmu), rocks forming larger rocks, stacking house blocks for
  height, stairs merging so items can sit in the gap.

**Suma implication:** the 3×3 → grown world design assumes lateral and
upward growth on a grid. Bridges/air/negative space are the thing that
turns a diorama from *a surface with objects* into *architecture*, and
they're requested constantly. Worth an explicit answer in the tile
spec: does Suma support unsupported spans and voids? Recommend yes for
bridges/arches at minimum — it's the highest-expressiveness-per-asset
feature in the list, and it fits "composer not CAD."

### F15. The group-manipulation gap is specific, not generic
Parts 1–6 log "multi-select / group move" as a one-line future QoL.
The forums specify it far more precisely, and it is the most repeated
tooling complaint after camera:
- Select an area and **move a whole build** ("having to sort through
  all the tiles 1 by 1 is tedious").
- **Rotate a group 90°** — repeatedly requested, never available.
- **Non-consecutive selection**: shift-click to deselect exceptions
  from a box selection.
- **Selection-depth filtering**: choose how many ground layers to skip
  from bottom or top, Ctrl+scroll to adjust — so you can grab the
  decoration without grabbing the terrain under it.
- **Drag-to-place** a run of tiles; right-click to drop one item at a
  time from a held stack.
- **Quick-stack / vacuum**: shake the mouse to consolidate, or a
  storage item that absorbs loose pieces in a 3×3/5×5 radius.

**Suma implication:** promote group manipulation from "noted" to a
named build-mode feature set. Layer-aware selection in particular is
the difference between a builder that scales to a large world and one
that fights you at hour 20 — and Suma's stacked-tile/anchor design has
exactly the occlusion problem that motivated the request.

### F16. Camera: rotation is only half of it
Confirmed and extended. Beyond the well-known 4-step rotation
complaint: players want **mouse-driven rotation** (right-drag on
background), **left-drag panning** instead of middle-mouse, on-screen
rotation buttons as a fallback, and — twice, independently
(CavalierLady) — a **second, lower camera pitch** for panoramic
"in-the-world" shots rather than only the high 45°. One player's stated
blocker for **one-handed play** was camera rotation specifically.
**Suma implication:** free camera already ✓. Add a low-angle/photo
pitch as a first-class mode (pairs with the P7 photo-mode proposal) and
ensure every camera verb is reachable mouse-only.

### F17. Storage requests are a coherent feature, not scattered gripes
Deduplicated across ~8 threads: **label/name storage boxes** ·
**colour-coded boxes** (exists but its meaning is undiscoverable — a
whole thread asks "what do the colour-coded storage boxes do?") ·
**transfer contents box → box** · **linked/universal vault inventory** ·
**bags inside bags** · **dedicated coin storage / a bank** · **hover
tooltip telling you a copy is already in storage** · **shift-click to
take a whole stack** (this *already exists* via long-click and players
didn't know).
**Suma implication:** the Build Library structurally removes most of
this ✓. Two items still apply and aren't in the ledger: a **"you
already own this" indicator** at placement time, and **search/filter**
in the library. The colour-box thread is also a clean case study for
F19 below.

### F18. Sound design has a hole, and the fix is diegetic
New and actionable: with music off, the game is **silent** — no ambient
or environmental audio at all (Beat). Separately, players repeatedly
ask for a **jukebox / record player / radio / cassette item** to switch
soundtracks in-world (Onyxiam, Zithis, and again in the 2025 "Anything
new?" thread).
**Suma implication:** P8 already budgets soundtrack variety; add (a) an
ambient bed independent of the music toggle, and (b) a **diegetic music
switcher keepsake**. The latter solves the single-loop complaint as
*content* rather than as an options menu, and it's exactly the
"keepsake = small verb" pattern from P5.

### F19. Undiscoverable systems are read as missing systems
A pattern worth naming on its own, because it recurs across a dozen
threads: GG *has* the feature, players never find it, and the forum
fills with requests for the thing that already shipped.
- Long-click already grabs a whole stack → "QOL Suggestion for Devs."
- "Nope logs" already ban items from the pool → players discover the
  anti-shrine mechanic by accident, years in.
- Colour-coded boxes have a function → a thread asks what it is.
- Spawn-increase/prevention radii are invisible → "does anyone know the
  radius?" (twice, one marked *solved* only by community testing).
- Altar percentages, golden nugget, pearls, secret items → all
  reverse-engineered in threads, none explained in game.

**Suma implication:** this is the strongest independent confirmation of
the Mastery Arc's "teach at unlock" rule (Part 6, item 3) and of
"radii must be shown" (Part 2). Elevate it to a hard rule: **any tool
that shapes randomness must announce itself in one diegetic sentence at
the moment it unlocks, and any spatial effect must render its area.**
GG's negative reviews and its superfan reviews are, per F4, the same
game separated by discovery — F19 is the mechanism by which players
land on one side or the other.

### F20. "Pause the world while I build" — a build-mode request
Two independent asks (WindyDay, druanee kisser) for a **toggle to stop
visitors spawning** while redesigning or taking screenshots. Visitors
are the beloved emotional glue (F8) *and* an interruption during
composition.
**Suma implication:** Suma's building mode elevates the camera; it
should also offer an optional "still" toggle that quiets ambient
spawns/events without pausing the world's life permanently. Pairs
naturally with photo mode.

### F21. Planning tools
**Blueprint drawing** to plan a build before committing pieces
(Sharky), and the dev's own **sand-drawing / zen-rake tool** for
freeform lines on gravel (also requested by Tyzillion as a real-time
raking verb). Two different needs — one utility, one expressive —
sharing a "draw on the ground" primitive.
**Suma implication:** the expressive one is the better fit for a cozy
diorama game and is genuinely novel in the space; the utility one is
mostly obviated if group-move (F15) is good.

### F22. Set completion should unlock deterministic re-acquisition — confirmed from a second population
Independently proposed at least three times in the forums: **books as
wildcards** to order a specific item from a completed set (HG Rezende),
**buy items with stored coins at a higher price** (Salithra), and
**displaying a book raises the odds of matching coins** (softlysings) —
i.e. display-as-soft-targeting. Also "alternate methods to gain set
coins" on the dev's own list.
**Suma implication:** direct, independent validation of **P3 (Pattern
Book + far-seeking coins)**. The display-as-targeting idea is a nice
addition: exhibiting a keepsake could gently bias draws toward its
family — it makes the P6 display line *mechanically* meaningful instead
of purely cosmetic, at low balance risk.

### F23. Technical & platform ledger (new specifics)
| Issue | Detail from forums | Suma relevance |
|---|---|---|
| Window/resolution | Can't change window size; fullscreen resolution locked; flickering on start; brown screen with audio at launch | Ship proper display options; don't lock fullscreen res |
| Frame limiter | Absent — laptops heat up; a whole thread asks for a cap | Add an FPS cap; it is a *cozy* feature (quiet fans) |
| Big-world scaling | No hard tile cap, but save/load grows to **several minutes** on large worlds; fps degrades | Concrete target for the 10K-tile benchmark: bound **save/load**, not just frame time |
| Save safety | 12 h save lost after a patch with Steam Cloud off; no autosave/backup discussion; repeated "where are my saves"; demo→full migration pain (14-reply thread); "transfer progress to another account"; **multiple saves** requested repeatedly | Autosave + rolling local backups + cloud on by default; nameable slots (already P9) |
| Brightness | "I felt like I was going blind due to the brightness of the white base tiles" — asked for dimmer/alternate colours | **Direct hit on Suma's cream-background visual pillar.** Add a brightness/contrast or warm-dim toggle to accessibility options |
| Effects you can't undo | Camera-item lens effects, over-saturation and a black-and-white mode players couldn't reverse; fog "basically not visible" | Confirms **P4 loss-proof effects** — and adds: every atmosphere effect needs a visible off switch |
| Platforms | macOS asked repeatedly · iPad/mobile repeatedly · Steam Deck verification · controller support · regional pricing · Steam trading cards | Controller-complete ✓; Deck verification is cheap marketing for this genre |
| Modding | Asked for directly ("Request: Stack everything and mods") | Open question for Suma; nothing in pillars addresses it |

### F24. Navigation at scale
"I got lost" · "How to find home?" · "Eye Spy" · magnifying glass ·
**waypoint signs** · a batch-collect button for visitors on large maps
· double-click a coin to send it to the pot. Once the world is big,
players cannot find their own things or the visitors they need.
**Suma implication:** as the world grows from nine tiles outward, add
navigation affordances early — a home marker, placeable signposts, and
a soft ping for events (the ledger's "events must ping softly" ✓).

### F25. Social & meta asks
Spectator-mode **visits to friends' gardens** (Steam friends), shared
worlds/multiplayer, a **desktop-companion/pet mode** petition, and —
notably — **no official Discord for three years**; the community made
their own and repeatedly asked the dev to adopt one. Also a
"Copycat game — Dev contact?" thread where players actively flagged a
GG-alike to the developer.
**Suma implication:** two things. (1) Community infrastructure at
launch is cheap retention; GG's absence of it is visible in every
abandonment thread. (2) That copycat thread is a caution worth naming
given Suma's stated GG visual reference: this community *polices*
lookalikes. The clean-room discipline in this doc is correct, and Suma
should have visible silhouette/identity differentiation — the keeper
character and the skill-driven growth axis are exactly that, and should
be foregrounded in any store presence.

### F26. Content gaps GG's own players mapped
Ranked by repetition, useful as a content-batch ordering hint:
**water/beach is thinnest** ("lacks the most variety" — fish in pools,
koi, bridges over pools, floating tealights, coral, boardwalks,
waterfalls for the one water type that lacks them) · **animals**
(ducks, rabbits, cats/dogs with bowls, sheep/goats/llamas, butterflies,
fireflies, squirrels) · **seasonal** · **houses with interiors, doors,
roofs, multi-storey** · **statues/marble/busts** · **zen/temple garden**
· **market stalls & shops** · **steampunk, witch/tarot, sakura, honey,
overgrown, road/vehicles, sports, golf, mining/treasure, pixie forest**
· gardening depth (a "plantopedia", seeds, **flower crossbreeding**,
crop signs) · cooking on grills/stoves.
**Suma implication:** water/shore first in the keepsake batches, then
creatures — this matches F8 and the existing priority order. The
crossbreeding/plantopedia cluster is the only one implying a *system*
rather than assets; it's also the one closest to Suma's skill-based
growth pillar, if a botany domain is ever wanted.

### F27. The abandonment wound, in the players' words
The reviews already showed this; the forums show its *shape* over three
years — and the ask is smaller than "more content":

> "I'd love any updates on this game!! Even if it's a *'this game is
> finished'*." — and, months later, "it would be really nice to know if
> the dev is finished working on this game."

Threads titled "Anything new?", "Abandonware?", "update", "Will this
game get more updates?", "为什么还没有更新?" run from 2023 to late 2025,
alongside "I would def buy a DLC for this game" (7 replies) and "WE
LOVE THIS GAME!" (11). The community stayed willing to pay and willing
to wait; what broke trust was **silence**, not the absence of a
roadmap.
**Suma implication:** reinforces Part 6 item 2 with a cheaper version —
the retention-critical artifact is not a content cadence, it's a
**status signal**. A dated "where this project stands" line that gets
updated even when the answer is "no changes this month" costs nothing
and is the single highest-leverage community action available to a solo
dev.

### Additions to the F12 QoL ledger
New items, not previously listed: recolour/paint verb · layer-aware and
non-contiguous selection · rotate group 90° · drag-to-place runs ·
place-one-from-stack · "already owned" indicator at placement ·
library search/filter · ambient audio independent of the music toggle ·
diegetic music switcher · visitor/event "still" toggle for building and
photos · brightness/warm-dim accessibility toggle · FPS cap · autosave
+ rolling local backups · bounded save/load time at scale · home marker
and placeable signposts.

---

## Part 8 — Competitor post-mortem: Mystopia (the natural experiment)

**Mystopia**, Last Minute Studios, Steam app 3012780, released 27 May
2025 at $10 as a **1.0, not Early Access**. Mixed, 67 % of 28 reviews.
This is the game GG's community accused of copying (Part 7, F25) — and
it is the single most useful artifact in the whole corpus, because it
ran the experiment we would otherwise have to guess at: *what happens
to a GG-like that ships?*

**Headline verdict: it did not fail for resembling Garden Galaxy. It
failed on execution, and the "copy" label attached afterward as
shorthand for "buy the working one."** The accusation appears in
reviews only as unfavourable comparison — "a worse copy of garden
galaxy at this point with less options", "feels rushed Garden Galaxy
copy", "get Garden Galaxy instead" — never as a moral or legal charge.
Mystopia had real mechanical differences (creature wishes, potion
brewing, a story mode, Egyptian-themed sets) and was called a clone
anyway, because when the game is broken, comparison is the fastest
insult available. **The clone label attaches to whichever game is more
broken, not to whichever looks more similar.**

### M1. Sentiment collapsed in two weeks, and the launch window lied
Reviews from 27–30 May 2025 are near-uniformly positive. Almost
everything from 8 June onward is negative. Two reviewers publicly
flipped positive → negative ("I'd previously left a positive review
saying I was excited to see where this game goes, but now I see it goes
nowhere"). **Read your own launch reviews with suspicion:** several of
the most glowing are under 1.5 h (0.1 h, 0.6 h, 0.9 h, 1.2 h, 1.3 h),
and two are marked *"Product received for free"* — one from a curator
with 3,733 products. The verdict arrives at weeks 3–6, once players
have reloaded a save a few times.

### M2. The playtime correlation is inverted vs GG
In GG, the 300–1000 h superfans were the advocates. In Mystopia the
angriest reviews are the longest: 17.7 h, 13.1 h, 8.3 h. That 17.7 h
was itself accumulated restarting broken saves 4–5 times. **When
playtime correlates with rage, the loop is not the problem — the build
is.**

### M3. Cause of death: save corruption and progression softlock
- Items missing on reload; black screen on load; save unusable within
  ten minutes; *"Game also deletes items when you load your save."*
- **Single-object softlock.** The lantern (needed to obtain items) and
  the pentagram table (needed to progress, delete, or sell) vanish on
  reload — after which spirits stop spawning and the save is dead.
  Unfixed "for over three months"; still reported ~11 months post-launch.
- Discovered-tile progress resets on quit.
- The idle engine dies mid-session: *"after about 50 minutes of runtime
  spirits stop appearing (the game becomes unplayable)."*
- Cauldron and chests enter permanent unusable states.
- **No Steam Cloud Saves** (promised, never shipped) and no Family
  Sharing — catastrophic in combination with the above.

**Suma implication:** extend **P4 (loss-proof effects)** into a harder
rule — *no single placeable object may gate progression.* And note that
saving the right **data** is not the same as protecting the **file**:
Suma's persistence list is strong on content but says nothing about
autosave cadence, rolling local backups, corruption detection, or
cloud. Both games in this corpus bled trust precisely there.

### M4. Creative Mode was not the answer
Mystopia **shipped Creative Mode** — the single most-requested GG
feature, the thing a dozen GG reviewers begged for — and it changed
nothing. No reviewer complains about it; no reviewer is retained by it.
**Independent confirmation of Part 4's rejection of Option C:** free
building is the destination of the arc, not a differentiator you can
lead with. The broken normal-mode economy underneath it decided
everything.

### M5. False advertising cost more trust than the bugs
Saga mode was listed in the description, shown in screenshots 2 and 3,
and led the gameplay section — with no disclaimer that it did not
exist. Multiple buyers bought *for it*: *"I bought the game not because
it is Garden galaxy clone but because I honestly thought that the Saga
mode would offer me different experience… I feel a bit scammed."*
Meanwhile positive reviewers were still asking when story mode ships.
**Rule for Suma: never show an unbuilt mode in store material.**

### M6. The 1.0 label was the offence, not the bug count
Nearly every negative review anchors here: *"This is not an Early
Access title, they released this game as a full release"* · *"it should
be considered early access at this point"* · *"Overpriced tag on a game
with 1/3 of its advertised modes being playable."* EA framing would
have absorbed most of this anger at zero engineering cost. One reviewer
generalised it into genre-level damage: *"my wakeup call to the
overabundance of broken unfinished games being sold as fully finished
in the cozy game genre."*

### M7. A single developer reply converted the most hostile review
Bells For Her (13.1 h) wrote *"Trash game… I hate this game"* — then
edited to **Recommended** after the dev responded, leading with "READ
THE RESPONSE OF THE DEVELOPER TO SEE THE REASON FOR RECOMENDATION."
Meanwhile another player joined the Discord to file bug reports and the
dev's brief answer was *"the last time he's said a word in that
server."* **Strongest possible evidence for F27 / decision 11:** the
status signal is the highest leverage-per-effort action available.

### M8. GG's design traps recur, unsolved — now confirmed genre-level
- **Tile-vs-object drop imbalance, again:** *"there's no real balance
  for spawning tiles vs objects, forcing you to sell some stuff… and
  hope that it sells something better back, or waiting a while for new
  stock. That's when it gets boring."* Two independent games, same
  trap. Suma's land-insurance slot is the right answer and now has
  second-source evidence.
- **Junk with no disposal:** *"I can't even delete, sell or get rid of
  the massive amount of trash accumulated by the little spirits… its a
  total game breaker."*
- **No goals:** *"No real goal other than just pointless really boring
  clicking"*; another asks directly for "more structure… more goals and
  rewards for the goals."
- **A player names the Mastery Arc unprompted**, as what Mystopia lacks
  and GG has: *"certain items guaranteed after a certain amount of
  pulls… increase chances for certain items or turn them off
  entirely."* Pity, odds-shaping, item-banning — stated as the baseline
  expectation of an informed cozy player.

### M9. What players liked — identical to GG's praise set
Aesthetics and music (near-universal) · no timers/scores/competition,
the F1 regulator effect reproducing exactly · **the block/brick
building system, singled out as the highlight by the reviewer who
otherwise hated the game** · collector satisfaction · themed sets ·
animated objects · an in-game **Polaroid camera** and **collection
book**, both well received (supports P7) · potions that change the
world's vibe. The building substrate was never the problem.

### M10. Consolidated lessons for Suma
1. Visual similarity is survivable; being a worse version of your own
   reference is not.
2. Save integrity is launch-blocking, not polish.
3. No single object may gate progression.
4. Never ship a screenshot of an unbuilt mode.
5. EA framing absorbs enormous goodwill damage — decide deliberately.
6. Distrust the launch window; watch weeks 3–6.
7. Creative mode alone retains nobody.
8. One developer reply can flip a hostile long-playtime review.

---

## Decisions needed from Luka

1. Adopt the Mastery Arc as the official progression spine? (P1)
2. Pattern Book: per-save or per-profile persistence? (P9)
3. Far-seeking threshold: percentage-based (printed on carvings) — 80 %?
4. Rest mode in the near-term scope, or after keepsake batch 1?
5. Secret interactions policy: comfortable leaving some mechanics
   undocumented for community discovery? (P5)

From the Part 7 sweep:

6. **Recolour/paint verb** — add to the roadmap? Most-requested
   customization primitive in the whole corpus, cheap in flat-matte
   art. (F13)
7. **Build topology** — do tiles support voids and unsupported spans
   (bridges, arches, floating islands)? Needs a yes/no in the tile
   spec before build-mode work hardens. (F14)
8. **Group manipulation scope** — is layer-aware + non-contiguous
   selection and 90° group rotation in build mode v1, or later? (F15)
9. **Display-as-soft-targeting** — should exhibiting a keepsake bias
   draws toward its family, making the P6 display line mechanical
   rather than cosmetic? (F22)
10. **Modding stance** — nothing in the pillars addresses it and it was
    requested directly. Open or closed? (F23)
11. **Status-signal commitment** — adopt a dated "where this project
    stands" note, updated even when the answer is "no change"? Highest
    leverage-per-effort item found. (F27)
