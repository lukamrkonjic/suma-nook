# Suma Nook — a world discovered one piece at a time

Suma Nook is a calm god-view diorama builder. Choose a small Project, gather a
few contributions from the world, reveal a tile, model, or new frontier, and
use it to develop the floating landscape.

Collection Projects are the reliable source of building pieces. Frontier
Projects turn boundary glows into stable goals before procedural land arrives.
One click performs one complete tree, rock, forage, fire, Special Find, or
Reward Drop interaction. An explicit edit mode owns pickup and placement, so
the same click can never interact with and move an object.

Common Timber, Stone, and Provisions flow directly into the tracked Project;
they are not inventory currencies. Rare Special Finds use a tiny reserve.
Falling Objects remain an infrequent bonus whose pre-rolled piece belongs to
the player only after its visible landed drop is claimed.

There is no Inspiration currency, wishing-well meter, Vision choice screen,
refund coin, focus shrine, XP ladder, combat grind, survival pressure, or
delivery FOMO.

**"Build the world that teaches the unknown what to send back."**

Current design: `docs/PROJECT_PROGRESSION.md` · Onboarding:
`docs/NEW_PLAYER_FLOW.md` · Full decision history:
`docs/DESIGN_MASTER_RECORD.md`

- Architecture: `docs/ARCHITECTURE.md`
- Design pillars: `DESIGN_PILLARS.md` · Scope: `MVP_SCOPE.md`
- Visual target: `docs/STYLE_BREAKDOWN.md` +
  `docs/VISUAL_FIDELITY_CHECKLIST.md`
- Asset pipeline: `docs/ASSET_PIPELINE.md`
- Layered tile system: `docs/TILE_AUTHORING.md`
- Large-world rendering: `docs/PERFORMANCE_AUDIT.md`

## Requirements and running

- Godot **4.6.3**, Forward+ renderer.
- Blender **5.x** only when regenerating assets.
- Open the project and press Play (`scenes/main.tscn`), or run
  `Godot --path .`.
- A first run opens character creation; later runs load
  `user://suma_nook_world.json`.

## Controls

Controllers are hot-pluggable. Suma changes prompts, focus, and pointer
visibility as soon as the active input method changes.

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Pan camera | WASD / middle-mouse drag | right stick |
| Move interaction/edit cursor | pointer | D-pad |
| Interact | left click / F | X / west face |
| Projects | P / tracked Project chip | Guide |
| Fish the unknown | interact near an exposed land edge | interact |
| Jump | Space | A / south face |
| Toggle interaction / edit mode | B | Y / north face |
| Place / pick up in build mode | click | A / south face |
| Move build cursor | pointer | D-pad |
| Place detached land | click any empty grid cell | move cursor anywhere, then A |
| Rotate / store held piece | R / X | R3 / X-west |
| Rotate camera | ← / → or Q / X | LB / RB |
| Zoom; build undo / redo | ↑ / ↓ or wheel; Ctrl+Z / Ctrl+Shift+Z | LT / RT |
| Cancel / close | Esc / right click | B / east face |
| Journals | I C K J M | D-pad; LB/RB changes an open page |
| Hide all HUD | H | R3 outside build mode |
| Pause | Esc | Menu / Options |
| Debug asset viewer | F8; drag / wheel | right stick / LT-RT |
| Performance HUD (debug) | F3 | pause menu Admin page |

See `docs/CONTROLLER_SUPPORT.md` for the implementation contract.

## Tests

See `tests/README.md`. The core suite must print `ALL TESTS PASSED`; the
scene-level runner must print `FULL LOOP PASSED`.

## Project structure

`data/` contains validated JSON content. `scripts/core/` loads typed
definitions and composes services. `scripts/features/projects/` owns Project,
contribution, Frontier, Special Find, and reserve state;
`scripts/features/rewards/` owns the shared build reward and landed-drop
boundaries. `scripts/world/`, `scripts/player/`, and `scripts/ui/` own their
runtime and presentation layers.

## How to add content

Everything player-obtainable is data-first.

**A Project** — add a typed definition to `data/projects.json` with a stable
ID, Project type, small contribution slots, reward/collection reference, and
presentation metadata. Use shared contribution tags unless the fantasy truly
needs a rarer Special Find.

**A tile** — follow `docs/TILE_AUTHORING.md`, add its typed definition to
`data/tiles.json`, give it honest `biome_tags`, and add its ID to
`data/tuning.json::active_tile_ids` when production-ready. Then list it in the
appropriate discovery pools. Water remains a real tile, never background
geometry or a special world layer.

**A structure** — add the GLB and a stable entry in `data/structures.json`.
Use biome tags for pieces that should influence local discovery. Give
skill-bearing objects an anchor capability, then include the structure in
weighted pools where it belongs.

**A resource activity** — add a `harvest_source` capability and a profile in
`data/harvest_profiles.json`. Supply contribution tags, action/maturation/
regrowth timing, and an optional depleted visual structure. The shared source
lifecycle and contribution service handle progress, idempotency, and saving.

**A milestone** — add a `practice` or `journal_page` entry to
`data/milestones.json` with stable rewards.

**A hero asset** — write a brief in `docs/asset_briefs/`, archive its source
under `art_source/`, clean it in Blender, and export the production GLB to
`assets/3d/final/` under the same asset ID.

## License and provenance

All shipped 3D, audio, and code are original and project-owned; see
`docs/ASSET_PROVENANCE.md`. Garden Galaxy material is retained only as
read-only research and style reference.
