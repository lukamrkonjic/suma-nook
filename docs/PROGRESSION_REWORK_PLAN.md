# Retired Inspiration rework — phased implementation plan

> **Superseded 2026-07-30.** This plan describes the removed
> Inspiration/Well/Vision implementation. The shipped replacement is
> documented in `docs/DISCOVERY_PROGRESSION.md`.

A master prompt for AI build sessions. Executes the redesign defined in
`docs/PROGRESSION_DESIGN.md` (systems) and `docs/NEW_PLAYER_FLOW.md`
(onboarding order). Work one phase per session; each phase ends green.

> **v3 note:** `docs/PROGRESSION_DESIGN.md` is now the v3 whole-game
> vision (Mastery Arc spine, Rest mode, Pattern Book, far-seeking
> coins, anti-shrine). Its §26 "Build order from here" supersedes the
> "Later" list below for what comes next; the phase history and
> ground rules here remain accurate.

## Status (2026-07-30)

Phases 0–6 are IMPLEMENTED and green (content validation 181 definitions,
core suite 1620 assertions, full acceptance loop 275 checks). The feature
module lives in `scripts/features/progression/`. Phase 7 landed its core
(offline tree recovery; ferry retained as the global heartbeat delivering
gift Visions); water-edge crate spawn points and attractors remain future
work. Phase 8's Keepsake batch, well visual evolution, and milestone
garments await content (see `docs/ASSET_QUEUE.md` placeholders). The
crafting review decision point is OPEN: recipes now unlock via milestones,
but whether material crafting stays long-term is the user's call.

## Ground rules for every phase

1. **Read first:** `docs/PROGRESSION_DESIGN.md`, `docs/NEW_PLAYER_FLOW.md`,
   `docs/ARCHITECTURE.md`. Follow the architecture contract: data in
   JSON + typed Defs, behaviour in typed systems, no content-ID
   branches, atomic catalog validation, controller-complete UI.
2. **Archive, never delete.** Retired systems move to
   `legacy/progression_v1/` (code) with a short README explaining what
   it was and how to restore it. Retired data fields get a commented
   archive copy in `legacy/progression_v1/data/`. Levels/XP may return
   one day — keep the door open.
3. **Saves must survive.** Every phase that changes state shape ships a
   migration in `SaveManager`/save adapters: old saves load, retired
   fields are preserved in the save dict where cheap (forward
   compatibility for a future levels revival) or dropped explicitly
   with a comment.
4. **Tests green per phase:** `tests/test_runner.gd` and
   `tools/validate_content.gd` pass before a phase is done. Update
   tests with the systems they cover; add coverage for each new system.
5. **Out of scope — do not touch:** combat/enemies, camping, the
   clothing/wardrobe pipeline, water/rain/fog visuals, crafting
   (reviewed in Phase 8, not before).

## Current systems → target mapping

| Today | Becomes |
|---|---|
| `SkillManager` (XP, levels, unlocks) | **Archived.** Activities remain; levels go. |
| `RewardManager.resolve_hobby_action` (XP + discovery + direct tile) | Emits **Inspiration** + journal discoveries + rare instant delights. |
| `ParcelManager` (parcel items → 3-choice reveal, pattern dust, hidden pity) | **VisionManager** — same reveal ritual, fed by the well, honest draws. |
| `parcel_reveal.gd` UI | Reused as the Vision reveal UI. |
| Pattern dust + hidden discovery pity | **Archived.** Replaced by refund meter + shrine (player-visible tools). |
| Loot-table parcel/`land_fragment` drops | Replaced by early land insurance in Vision options. |
| In-world character creation | Full-screen creation scene. |

---

## Phase 0 — Baseline and archive scaffolding

- Create `legacy/progression_v1/` with README describing the retired
  design (XP levels, parcel items, pattern dust) and restore notes.
- Record current behaviour: run tests, note pass state.
- No behaviour changes. Acceptance: repo builds, tests green, archive
  folder exists.

## Phase 1 — Inspiration core and the well

- New `InspirationSystem` (scripts/systems/): typed domain meters.
  Domains defined in new `data/inspiration_domains.json` (id, color,
  tile families, source activities) — validated like all content.
- Well as a placeable structure in `data/structures.json` with a
  capability (e.g. `banks_visions`), not a hard-coded scene.
- Hobby actions emit domain-typed Inspiration (wire into
  `RewardManager` result path; keep XP emission for now — removed in
  Phase 3). Wisp presentation: colored spirits fly from action to well.
- Vision banking: full meter banks a Vision at the well, **cap 3**. At
  cap: current action completes, further skilling refuses gently (no
  popup), nodes gesture toward the well.
- Player speed buff: +1 stack per banked Vision with spirit-trail
  effect (presentation via player systems, state in InspirationSystem).
- Acceptance: tend/fish fills meters, wisps fly, 3-cap blocks with
  diegetic feedback, speed stacks apply, saves round-trip.

## Phase 2 — Visions replace parcels

- Build `VisionManager` from `ParcelManager`'s reveal flow; archive
  `ParcelManager` after port. Reuse `parcel_reveal.gd` UI (rename to
  vision reveal; keep the pending-reveal-persists contract).
- Draw composition per design §3: **2 in-domain + 1 stray**, ~1-in-8
  Wild Visions (all-random), stray rare chance. Weights data-driven in
  `data/tuning.json`.
- **Early land insurance:** while owned tiles < threshold, one option
  is always a plain land tile; taper (tuning-driven).
- Remove: parcel items from loot tables, `land_fragment` as expansion
  currency, pattern-dust conversion, the hidden new-discovery pity
  (honest randomness pillar — archive all of it).
- Duplicates now simply arrive as owned copies into stock (dupes are
  legitimate and often wanted). Refund handling comes in Phase 4.
- Acceptance: claiming at the well runs the 3-choice ritual with new
  composition; no parcel items exist in play; old saves with pending
  parcels/dust migrate (dust archived into save dict, pending parcel
  converts to a pending Vision).

## Phase 3 — Flatten skills (levels out, archived)

- Archive `SkillManager` and the level/XP/unlock machinery to
  `legacy/progression_v1/`. Archive copies of `skills.json` unlock
  arrays and XP fields.
- `skills.json` slims to activity definitions: id, tool_type,
  action_seconds, animation/audio tags, collection wiring, domain.
  Update `Defs.SkillDefinition` + validators accordingly.
- `RewardManager` drops XP; hobby actions now yield Inspiration +
  journal discovery chance + rare instant tile delight (keep
  `direct_tile_reward_chance` — decided: kept as lottery moments).
- Re-home former level unlocks as **journal/milestone rewards** (e.g.
  bench, fence, fishing marker recipes move to journal page
  completions) — initial mapping in `data/`, easily rebalanced.
- HUD: remove XP bars/level UI; keep lifetime action counts (cheap,
  useful for future milestones and a possible levels revival).
- Save migration: levels/xp preserved read-only in save dict under an
  archived key.
- Acceptance: no XP anywhere in UI or state transitions; activities
  still animate/pay Inspiration; journal grants former unlock rewards;
  old saves load.

## Phase 4 — Refund meter and category coins

- Well interaction: refund an owned duplicate → per-domain **refund
  meter rendered as carvings on the well** (no menu). 3 refunds mint
  that domain's coin, which waits at the well (never inventory) and
  releases a **guaranteed in-domain Vision** (all three options from
  that domain).
- Refunds consume the item from stock; confirm irreversibility
  in-world (brief hold interaction, not a dialog).
- Acceptance: refund flow works controller-native, meters persist in
  saves, coin draw is domain-locked.

## Phase 5 — Shrine targeting

- New placeable `struct_shrine`: player sets one owned item on it;
  draws bias toward that item and its family (bias strength in
  tuning.json — this is the completion-convergence watchpoint, design
  §5).
- Bias applies to the in-domain slots, visibly signposted at the
  shrine (item hovers/glows). One shrine active at first; multiples
  are a later decision.
- Acceptance: shrined item measurably raises its draw odds in tests
  (deterministic via `RngService` seeding); works for dupe-farming and
  set-completion cases.

## Phase 6 — Onboarding (NEW_PLAYER_FLOW stages 1–4)

- **Full-screen character creation scene**: dedicated backdrop,
  character centered, no world/tiles rendered behind (replaces current
  in-world creation via `character_creator.gd`).
- Arrival: land pick as ~3 curated diorama options + water edge; tiles
  materialize under the character on confirm (reuse/extend arrival
  presentation systems).
- Guided placement of sapling + well; first Vision fast-tracked and
  rigged (three good options, one verb Keepsake); first fishing ripple
  spawns on the player's placed water tile with the one-line callout.
- Sequencing principles from the flow doc apply: one system per
  moment, one-sentence hints, world gestures over popups.
- Acceptance: full new-game run start→first Vision→first fishing in
  under ~10 minutes via `full_loop_runner.gd` scenario.

## Phase 7 — Flywheel pacing and world events

- Node spawning on placed content: fishing spots on `waterside` tiles,
  tree rest/regrow timers (real-time, offline-inclusive, resting state
  preserves silhouette — never a stump; occasional bonus recovery
  states feeding journal).
- **Global heartbeat scheduler** for special events (extend
  `ArrivalScheduler`): shore crates on water-meets-land edges,
  creature visits. Placed variety expands event *kinds*; frequency is
  global — density never pays (design §6 anti-density rule).
- Acceptance: event cadence obeys global pacing in a soak test;
  clustered vs scattered layouts yield equal income; offline tree
  recovery verified.

## Phase 8 — Keepsakes, well evolution, review pass

- First Keepsake batch (~1-in-10 Vision slot): 2–3 world-mood toggles,
  1–2 attractors, 1 playable object, the reroll station (variant
  system entry via `data/material_styles.json`; dud results feed a
  "Well Curiosities" journal set).
- Well visual evolution thresholds from total collection count.
- Journal milestone garments wired end-to-end (first page → garment,
  on-character reveal).
- **Crafting review decision point:** with levels gone, decide whether
  recipes/materials stay (slimmed to keepsake/utility crafting) or
  join the archive. Present findings to the user — do not decide
  unilaterally.

## Later (tracked, not scheduled)

Teleport tiles (placeable, cooldown), second well/districts, horizon
landmark modules, multiple shrines, NPCs/quests/market stalls, world
visiting, trading tokens.

## Tuning values (single source: `data/tuning.json`)

Meter cost per Vision, Wild Vision rate (~1/8), Keepsake rate (~1/10),
stray rarity chance, land insurance threshold + taper, refund meter
size (3), shrine bias strength, tree rest duration, speed buff per
stack, heartbeat interval. All start at design-doc hypotheses; tune in
playtests.
