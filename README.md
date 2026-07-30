# Suma Nook — cozy inspiration-fed world builder

A cozy diorama builder where doing gentle activities fills a wishing well
with Inspiration. Fishing releases Waterside wisps, tending trees releases
Grove wisps; a full meter banks a Vision at the well, and claiming it offers
three pieces — keep one, place it, and the world you build creates more to
do. Unwanted duplicates refund into domain coins; the shrine visibly steers
draws toward a focused piece. No XP, no levels — milestones from real play
unlock recipes and rewards. (Progression v1 — XP levels and Land Parcels —
is archived in `legacy/progression_v1/`.)

You begin by creating your keeper against an empty sky, choosing your first
land, and arriving on a nine-cell island: six land cells in your chosen
terrain and three connected water cells across the northern edge. A little
ferry still visits with gift Visions. There is no material-loot grind,
combat loop, survival pressure, or delivery FOMO.

**"A small world arrives one beautiful piece at a time."**

Design: `docs/PROGRESSION_DESIGN.md` · Onboarding:
`docs/NEW_PLAYER_FLOW.md` · Rework plan: `docs/PROGRESSION_REWORK_PLAN.md`

- Design pillars: `DESIGN_PILLARS.md` · Scope: `MVP_SCOPE.md` · Report:
  `MVP_REPORT.md` · Rework history: `REWORK_AUDIT.md`
- Architecture: `docs/ARCHITECTURE.md` · Visual target:
  `docs/STYLE_BREAKDOWN.md` + `docs/VISUAL_FIDELITY_CHECKLIST.md`
- Asset pipeline (incl. Modly → Blender Tier C flow): `docs/ASSET_PIPELINE.md`
- Layered tile system and GLB intake: `docs/TILE_AUTHORING.md`
- Copy-ready tile reference-image prompts: `docs/TILE_IMAGE_GENERATION_PROMPTS.md`
- Large-world renderer, benchmarks, and F3 profiler: `docs/PERFORMANCE_AUDIT.md`

## Requirements & running

- Godot **4.6.3** (`/Applications/Godot.app`), Forward+ renderer.
- Blender **5.x** only if you regenerate assets (`tools/build_assets.sh`).
- Run: open the project and press Play (`scenes/main.tscn` is the main
  scene), or `Godot --path . `.
- First run opens character creation; afterwards the save at
  `user://suma_nook_world.json` loads automatically.

## Controls

Controllers are hot-pluggable. Suma switches prompts, focus, and pointer
visibility as soon as a controller is discovered or either input method is
used. PlayStation and Nintendo button names are shown automatically.

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Walk / sprint | WASD / Shift | left stick / L3 |
| Click travel | left click ground or object | — |
| Interact | E | X / west face |
| Jump | Space | A / south face |
| Build mode / library | B | Y / north face |
| Place / pick up in build mode | click | A / south face |
| Move build cursor | pointer | D-pad |
| Rotate / store held piece | R / X | R3 / X-west |
| Rotate camera | ← / → or Q / X | LB / RB |
| Zoom; build undo / redo | ↑ / ↓ or wheel; Ctrl+Z / Ctrl+Shift+Z | LT / RT |
| Cancel / close | Esc / right click | B / east face |
| Journals | I C K J M | D-pad; LB/RB changes an open page |
| Return home | H | R3 outside build mode |
| Pause | Esc | Menu / Options |
| Debug asset viewer | F8; drag / wheel | right stick / LT-RT |
| Performance HUD (debug) | F3 | pause menu Admin page |

The implementation contract and feature checklist live in
`docs/CONTROLLER_SUPPORT.md`.

## Tests

See `tests/README.md` — headless core suite (must print `ALL TESTS PASSED`)
and the windowed full-loop acceptance runner (must print `FULL LOOP PASSED`).

## Project structure

`data/` JSON content → `scripts/core/registries.gd` typed definitions ·
`scripts/` (core / systems / world / player / visuals / ui) ·
`assets/3d` generated GLBs · `art_source/` Blender pipeline sources ·
`scenes/` main + lighting rig · `tools/` asset, content-validation, and audio
generators · `legacy/` pre-rework prototype (unreferenced, safe to delete).

## How to add content

Everything is data-first; the checklists below are complete — no engine code
changes needed unless stated.

**An activity** — add to `data/skills.json` (stable id, tool type, action
timing, `domain`, direct tile reward chance/pool, collection
category/entries), list it back on its domain in
`data/inspiration_domains.json`, add an anchor in `anchors.json`, and host
tiles in `tiles.json`. Ordinary activity actions intentionally have no
common material drop table — they pay Inspiration.

**An inspiration domain** — entry in `data/inspiration_domains.json` (id,
color, icon, tile_families, activities). Exactly one domain is the
wildcard. Domain reward pools derive from tile families plus structures
tagged `vision_reward` + the domain id.

**A milestone** — entry in `data/milestones.json`: `practice`
(activity + action_count) or `journal_page` (category + entries), with
rewards (tile | structure | gear | note). Gate a recipe by setting its
`unlock_milestone`.

**A tile** — follow `docs/TILE_AUTHORING.md`. One logical tile composes a
required reusable structural `base`, one replaceable `surface`, and optional
`detail`/`edge` GLBs. Generated sand, snow, grass, fern, leaf, or plank sources
are archived and hash-pinned, then a deterministic Blender processor exports
only the useful layer; do not join a copied block into every top. Add the tile
to `data/tiles.json`, and add its id to `data/tuning.json::active_tile_ids`
when it is ready for players. Elevation remains data-driven: `stackable`
allows an upper block, `supports_tiles` allows another block above it, and
`supports_decor` allows objects on its surface.

**A structure** — GLB + entry in `structures.json` (socket_type decor |
structure, blocks_movement, provides, visitor tags) + a recipe in
`recipes.json`. Decorations allow elevated placement by default; set
`allow_elevated: false` for objects that must remain at ground level.

**A landmark** — landmark scene GLB (+ optional reclaimed dressing GLB),
entry in `landmarks.json` (footprint, distance band, enemy roster, guardian,
rewards, salvage). The horizon scheduler, reveal, encounter, reclaim, pack,
and salvage flows are generic.

**Equipment** — item entry with `slot`, `asset_id`, `stats`; grant it from a
recipe, loot table, or guardian reward. Visuals attach automatically via the
named mounts on the character.

**A hero (Tier C) asset** — write a brief in `docs/asset_briefs/`, generate
via Modly into `art_source/modly/<id>/`, clean in Blender, export the GLB to
`assets/3d/final/<same_asset_id>.glb`. No code changes.

## License / provenance

All 3D, audio, and code are original and project-owned
(`docs/ASSET_PROVENANCE.md`). Garden Galaxy screenshots are read-only style
references only (`docs/style_reference/garden_galaxy/`) and are not shipped.
